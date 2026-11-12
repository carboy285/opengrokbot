import Darwin
import Foundation

/// Queries the local CLI's own catalog. Model selection never triggers inference.
enum CLIModelCatalog {
    static func models(for cli: InstalledCLI) -> [AvailableCLIModel] {
        if cli.provider.isLocalServer {
            return (LocalModelServer.modelsBlocking(cli.path, timeout: 4) ?? []).filter(validID).map { AvailableCLIModel(id: $0, name: $0) }
        }
        if cli.provider == .opencode {
            let result = CLIInstallationScanner.capture(path: cli.path, arguments: ["models"], timeout: 12, limit: 262_144)
            guard result.exit == 0 else { return [] }
            return Array(Set(result.text.split(whereSeparator: \.isNewline).map(String.init).filter { $0.contains("/") && validID($0) }))
                .sorted().prefix(1000).map { AvailableCLIModel(id: $0, name: $0) }
        }
        guard cli.provider == .codex else { return [] }
        let process = Process(), input = Pipe(), output = Pipe(), result = ModelResult()
        let completed = DispatchSemaphore(value: 0), exited = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: cli.path)
        process.arguments = ["app-server"]; process.environment = CLIInstallationScanner.environment
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in exited.signal() }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        func write(_ value: [String:Any]) {
            if let data = try? JSONSerialization.data(withJSONObject: value) { try? input.fileHandleForWriting.write(contentsOf: data + Data([10])) }
        }
        do { try process.run() } catch { return [] }
        DispatchQueue.global().async {
            defer { completed.signal() }
            var pending = Data(), total = 0
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(output.fileHandleForReading.fileDescriptor, $0.baseAddress, $0.count) }
                if count <= 0 { return }
                total += count; if total > 2_000_000 { return }
                pending.append(contentsOf: buffer.prefix(count))
                while let newline = pending.firstIndex(of: 10) {
                    let line = Data(pending.prefix(upTo: newline)); pending.removeSubrange(...newline)
                    guard let value = try? JSONSerialization.jsonObject(with: line) as? [String:Any] else { continue }
                    if value["id"] as? Int == 1 {
                        guard value["error"] == nil else { return }
                        let messages: [[String:Any]] = [["method":"initialized"],["id":2,"method":"model/list","params":["limit":100]]]
                        for message in messages {
                            if let data = try? JSONSerialization.data(withJSONObject: message) { try? input.fileHandleForWriting.write(contentsOf: data + Data([10])) }
                        }
                    } else if value["id"] as? Int == 2 {
                        let rows = (value["result"] as? [String:Any])?["data"] as? [[String:Any]] ?? []
                        result.set(rows.compactMap { row in
                            guard let id = (row["model"] ?? row["id"]) as? String, validID(id) else { return nil }
                            return AvailableCLIModel(id: id, name: row["displayName"] as? String ?? id)
                        }); return
                    }
                }
            }
        }
        write(["id":1,"method":"initialize","params":["clientInfo":["name":"opengrokbot-models","version":"0.4.0"]]])
        _ = completed.wait(timeout: .now() + 12)
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        if exited.wait(timeout: .now() + 1) == .timedOut { Darwin.kill(process.processIdentifier, SIGKILL); _ = exited.wait(timeout: .now() + 1) }
        return result.value
    }

    private static func validID(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 200 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_./:@+".contains($0)) }
    }
}

private final class ModelResult: @unchecked Sendable {
    private let lock = NSLock()
    private var models: [AvailableCLIModel] = []
    func set(_ value: [AvailableCLIModel]) { lock.lock(); defer { lock.unlock() }; models = value }
    var value: [AvailableCLIModel] { lock.lock(); defer { lock.unlock() }; return models }
}
