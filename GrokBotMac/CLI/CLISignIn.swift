import AppKit
import Foundation

/// Sign-in and install helpers for the provider CLIs. Subscriptions (ChatGPT, Claude, Grok) work through each CLI's own login:
/// OpenGrokBot opens that login in Terminal for you and never reads or copies the token.
enum CLISignIn {
    enum Credential: Equatable { case apiKey(String), signIn }

    static func credential(for provider: CLIProvider) -> Credential {
        ProviderAPIKeys.get(provider).map { .apiKey(ProviderAPIKeys.masked($0)) } ?? .signIn
    }

    /// Which credentials this provider will use for the next message.
    static func credentialLabel(for provider: CLIProvider) -> String {
        switch credential(for: provider) {
        case .apiKey(let mask): "Using API key \(mask)"
        case .signIn: "Using your \(provider.name) sign-in"
        }
    }

    /// Only fixed provider commands are ever run: the login command, or an npm install line. Chat text can never reach here.
    static func isAllowed(_ command: String) -> Bool {
        CLIProvider.allCases.contains { $0.loginCommand == command } || CLIProvider.allCases.contains { $0.installCommand == command && command.hasPrefix("npm install -g @") }
    }

    static func canInstall(_ provider: CLIProvider) -> Bool { provider.installCommand.hasPrefix("npm install -g @") }

    enum Failure: LocalizedError {
        case notAllowed, couldNotOpen
        var errorDescription: String? { self == .notAllowed ? "That command is not one OpenGrokBot can open." : "Terminal could not be opened." }
    }

    /// Opens a Terminal window running `command` so the sign-in or install happens in a place you can see and control.
    static func openInTerminal(_ command: String, title: String) throws {
        guard isAllowed(command) else { throw Failure.notAllowed }
        let label = String(title.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }.prefix(40))
        let script = "#!/bin/zsh\nclear\nprintf '\\n  OpenGrokBot · %s\\n\\n' '\(label)'\n\(command)\nprintf '\\n  Finished. You can close this window and return to OpenGrokBot.\\n'\n"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("opengrokbot-" + UUID().uuidString + ".command")
        do {
            try Data(script.utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        } catch { throw Failure.couldNotOpen }
        guard NSWorkspace.shared.open(file) else { throw Failure.couldNotOpen }
        Task.detached { try? await Task.sleep(for: .seconds(180)); try? FileManager.default.removeItem(at: file) }
    }

    /// Best-effort: Claude Code keeps its login in the macOS Keychain (or ~/.claude). Only the item's existence is checked, never its contents.
    static func claudeLoginFound() -> Bool {
        if FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.claude/.credentials.json") { return true }
        return CLIInstallationScanner.capture(path: "/usr/bin/security", arguments: ["find-generic-password", "-s", "Claude Code-credentials"], timeout: 4).exit == 0
    }
}
