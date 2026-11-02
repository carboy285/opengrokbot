import Darwin
import Foundation

/// Each request owns one subprocess. Prompts use stdin or a private file, never a shell.
final class LocalCLIRun: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOut = false

    func cancel(timeout: Bool = false, immediately: Bool = false) {
        lock.lock()
        cancelled = true
        timedOut = timedOut || timeout
        let running = process.isRunning
        lock.unlock()
        if running {
            if immediately { Darwin.kill(process.processIdentifier, SIGKILL); return }
            process.interrupt()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [self] in
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    static func stream(cli: InstalledCLI, prompt: String, session: String?, directory: URL, mcpURL: String? = nil, model: String = "") -> AsyncThrowingStream<CLIEvent, Error> {
        LocalCLIRun().events(cli: cli, prompt: prompt, session: session, directory: directory, mcpURL: mcpURL, model: model)
    }

    func events(cli: InstalledCLI, prompt: String, session: String?, directory: URL, mcpURL: String? = nil, model: String = "") -> AsyncThrowingStream<CLIEvent, Error> {
        let run = self
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { @Sendable _ in run.cancel() }
            DispatchQueue.global(qos: .userInitiated).async {
                run.execute(cli: cli, prompt: prompt, session: session, directory: directory, mcpURL: mcpURL, model: model, continuation: continuation)
            }
        }
    }

    /// FileHandle.read(upToCount:) can fill its requested buffer before returning on Darwin.
    /// One POSIX read delivers each available pipe chunk, so partial replies and stop remain responsive.
    private func readChunk(_ handle: FileHandle) throws -> Data? {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
            if count > 0 { return Data(buffer.prefix(count)) }
            if count == 0 { return nil }
            if errno != EINTR { throw CLIError.invalidOutput }
        }
    }

    private func execute(cli: InstalledCLI, prompt: String, session: String?, directory: URL, mcpURL: String?, model: String, continuation: AsyncThrowingStream<CLIEvent, Error>.Continuation) {
        var promptFile: URL?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if cli.provider == .grok {
                let file = directory.appendingPathComponent(".prompt-\(UUID().uuidString).txt")
                try Data(prompt.utf8).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                promptFile = file
            }
            defer { if let promptFile { try? FileManager.default.removeItem(at: promptFile) } }
            let mcp = try ComposioCLIConfiguration.make(provider: cli.provider, directory: directory, sessionURL: mcpURL)
            defer { mcp.cleanup() }
            let command = CLICommand.chat(provider: cli.provider, prompt: prompt, session: session, promptFile: promptFile?.path, model: model)
            let input = Pipe(), output = Pipe(), error = Pipe()
            process.executableURL = URL(fileURLWithPath: cli.path)
            process.arguments = command.arguments + mcp.arguments
            process.currentDirectoryURL = directory
            process.environment = CLIInstallationScanner.environment.merging(mcp.environment) { _, new in new }
            process.standardInput = input; process.standardOutput = output; process.standardError = error
            // A child exiting before consuming stdin must not terminate the GUI with SIGPIPE.
            _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            lock.lock()
            if cancelled { lock.unlock(); continuation.finish(throwing: CLIError.stopped); return }
            if !FileManager.default.isExecutableFile(atPath: cli.path) { lock.unlock(); throw CLIError.notInstalled }
            do { try process.run(); lock.unlock() } catch { lock.unlock(); throw error }
            let timeout = DispatchWorkItem { [weak self] in self?.cancel(timeout: true) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 600, execute: timeout)
            defer { timeout.cancel() }
            let stderr = BoundedData(limit: 32_768)
            let readers = DispatchGroup()
            readers.enter()
            DispatchQueue.global().async {
                defer { readers.leave() }
                while let bytes = try? error.fileHandleForReading.read(upToCount: 8192), !bytes.isEmpty { stderr.append(bytes) }
            }
            readers.enter()
            DispatchQueue.global().async {
                defer { try? input.fileHandleForWriting.close(); readers.leave() }
                if !command.input.isEmpty { try? input.fileHandleForWriting.write(contentsOf: Data(command.input.utf8)) }
            }
            var pending = Data(), parser = CLIEventParser(), total = 0, protocolFailed = false
            while let bytes = try readChunk(output.fileHandleForReading) {
                total += bytes.count
                guard total <= 32 * 1024 * 1024 else { cancel(); throw CLIError.invalidOutput }
                pending.append(bytes)
                guard pending.count <= 2 * 1024 * 1024 else { cancel(); throw CLIError.invalidOutput }
                while let newline = pending.firstIndex(of: 10) {
                    let line = pending.prefix(upTo: newline)
                    pending.removeSubrange(...newline)
                    for event in parser.parse(Data(line)) {
                        if event == .failed { protocolFailed = true }
                        continuation.yield(event)
                    }
                }
            }
            if !pending.isEmpty { for event in parser.parse(pending) { if event == .failed { protocolFailed = true }; continuation.yield(event) } }
            process.waitUntilExit()
            readers.wait()
            lock.lock(); let stopped = cancelled, expired = timedOut; lock.unlock()
            if expired { throw CLIError.timedOut }
            if stopped { throw CLIError.stopped }
            if process.terminationStatus != 0 || protocolFailed {
                let diagnostic = String(data: stderr.value, encoding: .utf8) ?? ""
                throw CLIError.classify(stderr: diagnostic, exitCode: process.terminationStatus)
            }
            guard !parser.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CLIError.invalidOutput }
            continuation.finish()
        } catch {
            if process.isRunning { process.terminate() }
            continuation.finish(throwing: error)
        }
    }
}

final class BoundedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int
    init(limit: Int) { self.limit = limit }
    func append(_ bytes: Data) { lock.lock(); defer { lock.unlock() }; if data.count < limit { data.append(bytes.prefix(limit - data.count)) } }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}

enum CLIInstallationScanner {
    static var directories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.npm-global/bin", home + "/.bun/bin", home + "/.opencode/bin", home + "/.volta/bin", home + "/.asdf/shims"]
        let nvm = URL(fileURLWithPath: home + "/.nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil) {
            dirs += versions.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }.prefix(6).map { $0.appendingPathComponent("bin").path }
        }
        return Array(NSOrderedSet(array: dirs)) as? [String] ?? dirs
    }
    static var environment: [String:String] {
        var value = ProcessInfo.processInfo.environment
        value["PATH"] = directories.joined(separator: ":")
        return value
    }

    static func scan(overrides: [String:String]) -> [InstalledCLI] {
        CLIProvider.allCases.compactMap { provider in
            let custom = overrides[provider.rawValue] ?? ""
            let candidates = custom.isEmpty ? directories.map { $0 + "/" + provider.executable } : [custom]
            guard let path = candidates.first(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
            let version = capture(path: path, arguments: ["--version"])
            guard version.exit == 0 else { return nil }
            return InstalledCLI(provider: provider, path: path, version: version.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100).description)
        }
    }

    static func capture(path: String, arguments: [String], timeout: TimeInterval = 4, limit: Int = 4096) -> (exit: Int32, text: String) {
        let task = Process(), stdout = Pipe(), stderr = Pipe(), collected = BoundedData(limit: limit)
        task.executableURL = URL(fileURLWithPath: path); task.arguments = arguments
        task.environment = environment; task.standardInput = FileHandle.nullDevice
        task.standardOutput = stdout; task.standardError = stderr
        let finished = DispatchSemaphore(value: 0), drains = DispatchGroup()
        task.terminationHandler = { _ in finished.signal() }
        do {
            try task.run()
            drains.enter(); DispatchQueue.global().async { defer { drains.leave() }; while let data = try? stdout.fileHandleForReading.read(upToCount: 4096), !data.isEmpty { collected.append(data) } }
            drains.enter(); DispatchQueue.global().async { defer { drains.leave() }; while let data = try? stderr.fileHandleForReading.read(upToCount: 4096), !data.isEmpty {} }
            if finished.wait(timeout: .now() + timeout) == .timedOut {
                task.terminate()
                if finished.wait(timeout: .now() + 1) == .timedOut { Darwin.kill(task.processIdentifier, SIGKILL); _ = finished.wait(timeout: .now() + 1) }
                return (-1, "")
            }
            _ = drains.wait(timeout: .now() + 1)
            return (task.terminationStatus, String(data: collected.value, encoding: .utf8) ?? "")
        } catch { return (-1, "") }
    }
}
