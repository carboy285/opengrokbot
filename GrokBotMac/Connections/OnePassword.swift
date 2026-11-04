import Foundation

/// Optional 1Password source for secure logins, through the official `op` command-line tool (with its desktop-app integration).
/// 1Password asks for Touch ID itself. OpenGrokBot reads the username and password only at the moment it types them into the page.
enum OnePassword {
    struct Credentials: Equatable { let username: String; let password: String }

    static var executable: String? {
        ["/opt/homebrew/bin/op", "/usr/local/bin/op", "/usr/bin/op"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func isValidItemName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...120).contains(trimmed.count) && !trimmed.contains(where: { $0.isNewline || $0 == "\u{0}" }) && !trimmed.hasPrefix("-")
    }

    /// Reads the username and password from `op item get --format json` output.
    static func parse(_ data: Data) -> Credentials? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let fields = root["fields"] as? [[String: Any]] else { return nil }
        func value(_ purpose: String, fallbackID: String) -> String? {
            let field = fields.first { ($0["purpose"] as? String) == purpose } ?? fields.first { ($0["id"] as? String)?.lowercased() == fallbackID }
            return (field?["value"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let user = value("USERNAME", fallbackID: "username"), let password = value("PASSWORD", fallbackID: "password") else { return nil }
        return Credentials(username: user, password: password)
    }

    enum Failure: LocalizedError {
        case notInstalled, invalidItem, failed
        var errorDescription: String? {
            switch self {
            case .notInstalled: "1Password’s command-line tool (op) is not installed. Install it with Homebrew (brew install 1password-cli) and turn on its desktop app integration."
            case .invalidItem: "That 1Password item name is not valid."
            case .failed: "1Password did not return the login. Unlock 1Password, approve the prompt, and check the item name."
            }
        }
    }

    static func fetch(item: String) async throws -> Credentials {
        guard let path = executable else { throw Failure.notInstalled }
        guard isValidItemName(item) else { throw Failure.invalidItem }
        let result = await Task.detached { CLIInstallationScanner.capture(path: path, arguments: ["item", "get", item.trimmingCharacters(in: .whitespacesAndNewlines), "--format", "json"], timeout: 45, limit: 262_144) }.value
        guard result.exit == 0, let credentials = parse(Data(result.text.utf8)) else { throw Failure.failed }
        return credentials
    }
}
