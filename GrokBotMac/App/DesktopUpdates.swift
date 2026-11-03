import AppKit
import CommonCrypto
import Combine
import CryptoKit
import UniformTypeIdentifiers
import Foundation
import SwiftUI

@MainActor
final class DesktopUpdates: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var available = false
    @Published private(set) var version = ""
    @Published private(set) var message = "Check for a newer release. Your conversations stay on this Mac."
    @Published private(set) var releaseURL: URL?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var downloading = false
    /// Set once a verified update is unpacked next to the app and ready to swap in.
    @Published private(set) var stagedVersion: String?
    private var stagedApp: URL?
    var readyToInstall: Bool { stagedApp != nil }
    private var installer: (dmg: URL, checksum: URL)?
    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.7.3" }
    private struct Asset: Decodable { var name: String; var browser_download_url: String }
    private struct Release: Decodable { var tag_name: String; var html_url: String; var draft: Bool; var prerelease: Bool; var assets: [Asset]? }
    func check(automatically: Bool = false) async {
        guard !checking else { return }
        let preferences = UserDefaults.standard
        if automatically {
            guard preferences.object(forKey: "checkAppUpdates") as? Bool ?? true,
                  Date().timeIntervalSince1970 - preferences.double(forKey: "lastAppUpdateCheck") > 86400 else { return }
        }
        checking = true; defer { checking = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/carboy285/opengrokbot/releases?per_page=20")!)
            request.timeoutInterval = 15; request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else { throw URLError(.badServerResponse) }
            let releases = try JSONDecoder().decode([Release].self, from: data)
                .filter { !$0.draft && Self.numbers($0.tag_name) != nil && Self.trusted($0.html_url) }
                .sorted { Self.newer($0.tag_name, than: $1.tag_name) }
            checkedAt = Date(); preferences.set(Date().timeIntervalSince1970, forKey: "lastAppUpdateCheck")
            if let release = releases.first {
                available = Self.newer(release.tag_name, than: current); version = release.tag_name
                releaseURL = URL(string: release.html_url)
                let assets = release.assets ?? []
                if let dmg = assets.first(where: { $0.name.hasSuffix("-mac-universal.dmg") }), let sum = assets.first(where: { $0.name == dmg.name + ".sha256" }),
                   let dmgURL = URL(string: dmg.browser_download_url), let sumURL = URL(string: sum.browser_download_url),
                   Self.trustedDownload(dmgURL), Self.trustedDownload(sumURL) { installer = (dmgURL, sumURL) } else { installer = nil }
                message = available ? "\(release.tag_name) is available\(release.prerelease ? " as a development release" : "")." : "You’re using \(current). No newer version is published."
            } else { available = false; message = "No downloadable releases have been published yet." }
        } catch { message = "Updates could not be reached. Check your internet connection and try again." }
    }
    var canInstall: Bool { available && installer != nil }

    /// Downloads the DMG, checks it against the published SHA-256, unpacks the app next to this one and checks its signature.
    /// Nothing is replaced until you choose Restart and install.
    func downloadAndStage() async {
        guard let installer, !downloading, stagedApp == nil else { return }
        downloading = true; defer { downloading = false }
        message = "Downloading \(version)…"
        do {
            let (sumData, sumResponse) = try await URLSession.shared.data(from: installer.checksum)
            guard (sumResponse as? HTTPURLResponse)?.statusCode == 200,
                  let expected = String(data: sumData, encoding: .utf8)?.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)?.lowercased(),
                  expected.count == 64 else { throw URLError(.badServerResponse) }
            let (temporary, response) = try await URLSession.shared.download(from: installer.dmg)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let digest = SHA256.hash(data: try Data(contentsOf: temporary, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { try? FileManager.default.removeItem(at: temporary); message = "The download failed its integrity check and was deleted. Try again."; return }
            let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let target = downloads.appendingPathComponent(installer.dmg.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temporary, to: target)
            message = "Unpacking \(version)…"
            let wanted = version.hasPrefix("v") ? String(version.dropFirst()) : version
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            let running = Bundle.main.bundleURL
            do {
                let staged = try await Task.detached { try UpdateStaging.stage(dmg: target, expectedVersion: wanted, bundleID: bundleID, runningApp: running) }.value
                stagedApp = staged; stagedVersion = version
                message = "\(version) is ready. Restart to install it. Your workspace is kept."
            } catch {
                // Could not swap in place (for example, the app is in a folder you can't write to): fall back to the disk image.
                NSWorkspace.shared.open(target)
                message = "Downloaded and verified. \((error as? LocalizedError)?.errorDescription ?? "Automatic install isn’t available here.") Drag the new app into Applications to replace the old one."
            }
        } catch { message = "The update could not be downloaded. Try again, or use the download page." }
    }

    /// Quits the app, swaps the new version in, and opens it again.
    func restartAndInstall() {
        guard let staged = stagedApp else { return }
        do {
            try UpdateStaging.launchInstaller(staged: staged, target: Bundle.main.bundleURL)
            NSApp.terminate(nil)
        } catch { message = "The install could not be started. Open the disk image in Downloads and drag the app into Applications." }
    }

    func openDownload() {
        guard let url = releaseURL, Self.trusted(url.absoluteString) else { return }
        NSWorkspace.shared.open(url)
    }
    private static func trusted(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil && url.path.hasPrefix("/carboy285/opengrokbot/releases/")
    }
    private static func trustedDownload(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil && url.path.hasPrefix("/carboy285/opengrokbot/releases/download/")
    }
    private static func numbers(_ value: String) -> [Int]? {
        let clean = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let core = clean.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
        let parts = core.split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 ? parts : nil
    }
    private static func newer(_ lhs: String, than rhs: String) -> Bool {
        guard let a = numbers(lhs), let b = numbers(rhs) else { return false }
        return b.lexicographicallyPrecedes(a)
    }
}

struct DesktopUpdatesView: View {
    @ObservedObject var updates: DesktopUpdates
    /// True while a Bot is replying; installing then would cut the reply off.
    var busy = false
    @AppStorage("checkAppUpdates") private var automatic = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("OpenGrokBot \(updates.current)", systemImage: "arrow.down.circle").font(.title2)
            Text(updates.message).foregroundStyle(.secondary)
            Toggle("Notify me about updates once a day when the app is open", isOn: $automatic)
            HStack {
                Button(updates.checking ? "Checking…" : "Check for updates") { Task { await updates.check() } }.disabled(updates.checking)
                if updates.readyToInstall {
                    Button("Restart and install") { updates.restartAndInstall() }
                        .buttonStyle(.borderedProminent).disabled(busy)
                } else if updates.canInstall {
                    Button(updates.downloading ? "Downloading…" : "Download update") { Task { await updates.downloadAndStage() } }
                        .buttonStyle(.borderedProminent).disabled(updates.downloading)
                }
                if updates.available { Button("Open download page") { updates.openDownload() } }
            }
            if updates.readyToInstall && busy { Text("A Bot is still replying. Restart when it finishes.").font(.footnote).foregroundStyle(.secondary) }
            if let date = updates.checkedAt { Text("Last checked \(date.formatted())").font(.caption).foregroundStyle(.secondary) }
            Text("Updates come from this project’s GitHub releases and are checked before they are installed. Restart replaces the app in place and reopens it; your workspace is kept.").font(.footnote).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Password-encrypted workspace backups. Same envelope as the Windows app (backup.cjs):
/// PBKDF2-SHA256 (600,000 rounds) -> AES-256-GCM, ciphertext stored as ct || 16-byte tag.
enum BackupCrypto {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    private struct Envelope: Codable {
        var format: String, version: Int, platform: String, createdAt: String, kdf: String
        var iterations: Int, salt: String, iv: String, ciphertext: String
    }
    static let rounds = 600_000

    static func seal(_ payload: Data, password: String, platform: String) throws -> Data {
        guard password.count >= 8 else { throw Failure("Use a password of at least 8 characters.") }
        let salt = randomBytes(16), iv = randomBytes(12)
        guard let key = key(password, salt: salt, rounds: rounds) else { throw Failure("The backup key could not be created.") }
        let sealed = try AES.GCM.seal(payload, using: key, nonce: AES.GCM.Nonce(data: iv))
        let envelope = Envelope(format: "opengrokbot-backup", version: 1, platform: platform, createdAt: ISO8601DateFormatter().string(from: Date()),
                                kdf: "pbkdf2-sha256", iterations: rounds, salt: salt.base64EncodedString(), iv: iv.base64EncodedString(),
                                ciphertext: (sealed.ciphertext + sealed.tag).base64EncodedString())
        return try JSONEncoder().encode(envelope)
    }

    static func open(_ data: Data, password: String) throws -> (platform: String, payload: Data) {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.format == "opengrokbot-backup",
              envelope.version == 1, envelope.kdf == "pbkdf2-sha256" else { throw Failure("This is not an OpenGrokBot backup.") }
        guard (100_000...5_000_000).contains(envelope.iterations) else { throw Failure("This backup uses unsupported settings.") }
        guard let salt = Data(base64Encoded: envelope.salt), let iv = Data(base64Encoded: envelope.iv), let body = Data(base64Encoded: envelope.ciphertext),
              salt.count >= 16, iv.count == 12, body.count > 16 else { throw Failure("This backup is damaged.") }
        guard let key = key(password, salt: salt, rounds: envelope.iterations) else { throw Failure("The backup key could not be created.") }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: body.dropLast(16), tag: body.suffix(16))
            return (envelope.platform, try AES.GCM.open(box, using: key))
        } catch { throw Failure("Wrong password, or the backup was changed.") }
    }

    private static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    private static func key(_ password: String, salt: Data, rounds: Int) -> SymmetricKey? {
        let secret = Array(password.utf8), saltBytes = Array(salt)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = secret.withUnsafeBufferPointer { secretPointer in
            secretPointer.withMemoryRebound(to: CChar.self) { passwordPointer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordPointer.baseAddress, secret.count, saltBytes, saltBytes.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds), &derived, derived.count)
            }
        }
        return status == Int32(kCCSuccess) ? SymmetricKey(data: derived) : nil
    }
}

struct MacBackupView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @State private var password = ""
    @State private var confirm = ""
    @State private var restorePassword = ""
    @State private var status: String?
    @State private var working = false
    private let fileType = UTType(filenameExtension: "ogbackup") ?? .data

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Encrypted backup", systemImage: "lock.doc").font(.title2)
            Text("Saves your Bots, conversations and routines to one file encrypted with your password. AI sign-ins, API keys and vault secrets are not included. Without the password the backup cannot be opened.")
                .foregroundStyle(.secondary)
            SecureField("Backup password (8+ characters)", text: $password).frame(maxWidth: 360)
            SecureField("Repeat password", text: $confirm).frame(maxWidth: 360)
            Button("Export backup…") { exportBackup() }.disabled(working || password.count < 8 || password != confirm)
            Divider().padding(.vertical, 4)
            Text("Restoring replaces the Bots and conversations on this Mac. A safety copy of the current workspace is saved first, encrypted with the same password.")
                .font(.footnote).foregroundStyle(.secondary)
            SecureField("Backup password", text: $restorePassword).frame(maxWidth: 360)
            Button("Restore from backup…") { restoreBackup() }.disabled(working || restorePassword.isEmpty || !desktop.runningBots.isEmpty)
            if let status { Text(status).font(.footnote).accessibilityAddTraits(.updatesFrequently) }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func encodedWorkspace() throws -> Data {
        var workspace = app.workspace
        workspace.sessions = [:]
        return try JSONEncoder().encode(workspace)
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [fileType]
        panel.nameFieldStringValue = "OpenGrokBot-backup-\(Date().formatted(.iso8601.year().month().day())).ogbackup"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        working = true; defer { working = false }
        do {
            try BackupCrypto.seal(try encodedWorkspace(), password: password, platform: "mac").write(to: url, options: .atomic)
            password = ""; confirm = ""; status = "Backup saved."
        } catch { status = (error as? LocalizedError)?.errorDescription ?? "The backup could not be saved." }
    }

    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [fileType]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        working = true; defer { working = false }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 200_000_000 else { status = "Choose an OpenGrokBot backup file."; return }
            let opened = try BackupCrypto.open(data, password: restorePassword)
            guard opened.platform == "mac" else { status = "This backup was made on Windows. Restore it in the Windows app."; return }
            guard let restored = try? JSONDecoder().decode(Workspace.self, from: opened.payload) else { status = "This backup could not be read by this version of OpenGrokBot."; return }
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("OpenGrokBot", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try BackupCrypto.seal(try encodedWorkspace(), password: restorePassword, platform: "mac")
                .write(to: support.appendingPathComponent("pre-restore.ogbackup"), options: .atomic)
            if app.restoreWorkspace(restored) { restorePassword = ""; status = "Backup restored. A safety copy of the previous workspace is in Application Support/OpenGrokBot." }
            else { status = app.errorMessage ?? "The backup could not be restored." }
        } catch { status = (error as? LocalizedError)?.errorDescription ?? "The backup could not be restored." }
    }
}

/// Unpacks a downloaded update and swaps it in after the app quits.
enum UpdateStaging {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(String(data: data, encoding: .utf8) ?? "A helper tool failed.") }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Mounts the DMG, copies the app next to the running one (same volume, so the swap is a rename), and verifies it.
    static func stage(dmg: URL, expectedVersion: String, bundleID: String, runningApp: URL) throws -> URL {
        let parent = runningApp.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw Failure("This app’s folder isn’t writable.") }
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("opengrokbot-mount-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? FileManager.default.removeItem(at: mount)
        }
        let apps = (try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)).filter { $0.pathExtension == "app" }
        guard let source = apps.first(where: { Bundle(url: $0)?.bundleIdentifier == bundleID }),
              let info = Bundle(url: source)?.infoDictionary,
              (info["CFBundleShortVersionString"] as? String) == expectedVersion else { throw Failure("The disk image doesn’t contain the expected version.") }
        let folder = parent.appendingPathComponent(".OpenGrokBot-update", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder.appendingPathComponent(runningApp.lastPathComponent)
        try run("/usr/bin/ditto", [source.path, staged.path])
        do { try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path]) }
        catch { try? FileManager.default.removeItem(at: folder); throw Failure("The new app failed its signature check.") }
        return staged
    }

    private static let script = """
    #!/bin/sh
    # Waits for OpenGrokBot to quit, swaps in the staged app, and reopens it.
    PID="$1"; NEW="$2"; TARGET="$3"; BACKUP="$TARGET.previous"
    i=0
    while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 150 ]; do sleep 0.2; i=$((i+1)); done
    if [ -d "$NEW" ]; then
      rm -rf "$BACKUP"
      if mv "$TARGET" "$BACKUP"; then
        if mv "$NEW" "$TARGET"; then
          xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
          rm -rf "$BACKUP"
        else
          mv "$BACKUP" "$TARGET"
        fi
      fi
      rmdir "$(dirname "$NEW")" 2>/dev/null
    fi
    open "$TARGET"
    rm -f "$0"
    """

    static func launchInstaller(staged: URL, target: URL) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("opengrokbot-install-" + UUID().uuidString + ".sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/sh", file.path, String(ProcessInfo.processInfo.processIdentifier), staged.path, target.path]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
