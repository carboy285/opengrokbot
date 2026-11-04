import Foundation

/// A website login saved on this Mac. The password lives only in the Keychain.
struct SecureLogin: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var label: String
    var host: String
    var username: String
    /// A 1Password item name. When set, the username and password are read from 1Password at sign-in time and none is stored here.
    var onePassword: String? = nil
}

/// Saved logins that the app (never the Bot, never the AI provider) types into a page after the human approves.
/// The index holds names only; each password is a separate Keychain item.
struct SecureLoginStore: Sendable {
    var store = KeychainSecretStore(service: "org.opengrokbot.mac.secure-logins")
    static let maxLogins = 100

    enum Failure: LocalizedError {
        case invalid(String), full, storage
        var errorDescription: String? {
            switch self {
            case .invalid(let text): text
            case .full: "You can save up to \(SecureLoginStore.maxLogins) logins. Remove one first."
            case .storage: "The Keychain could not save this login. Unlock your Mac and try again."
            }
        }
    }

    func list() -> [SecureLogin] {
        guard let data = try? store.read(account: "index"), let logins = try? JSONDecoder().decode([SecureLogin].self, from: data) else { return [] }
        return logins
    }

    @discardableResult
    func add(label: String, url: String, username: String, password: String) throws -> SecureLogin {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(label.count) else { throw Failure.invalid("Give the login a short name (up to 60 characters).") }
        guard let host = Self.host(from: url) else { throw Failure.invalid("Enter the website as an https:// address, for example https://example.com/login.") }
        guard (1...200).contains(username.count), !username.contains(where: { $0.isNewline }) else { throw Failure.invalid("Enter the username or email for this site.") }
        guard (1...512).contains(password.count), !password.contains("\u{0}") else { throw Failure.invalid("Enter the password (up to 512 characters).") }
        var logins = list()
        guard logins.count < Self.maxLogins else { throw Failure.full }
        guard !logins.contains(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) else { throw Failure.invalid("A login with this name already exists. Choose a different name.") }
        let entry = SecureLogin(id: UUID(), label: label, host: host, username: username)
        do {
            try store.save(Data(password.utf8), account: Self.account(entry.id))
            logins.append(entry)
            try store.save(JSONEncoder().encode(logins), account: "index")
        } catch {
            try? store.delete(account: Self.account(entry.id))
            throw Failure.storage
        }
        return entry
    }

    /// Saves a login that lives in 1Password: only the site and item name are kept here.
    @discardableResult
    func addOnePassword(label: String, url: String, item: String) throws -> SecureLogin {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(label.count) else { throw Failure.invalid("Give the login a short name (up to 60 characters).") }
        guard let host = Self.host(from: url) else { throw Failure.invalid("Enter the website as an https:// address, for example https://example.com/login.") }
        guard OnePassword.isValidItemName(item) else { throw Failure.invalid("Enter the exact name of the 1Password item.") }
        var logins = list()
        guard logins.count < Self.maxLogins else { throw Failure.full }
        guard !logins.contains(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) else { throw Failure.invalid("A login with this name already exists. Choose a different name.") }
        let entry = SecureLogin(id: UUID(), label: label, host: host, username: "1Password", onePassword: item.trimmingCharacters(in: .whitespacesAndNewlines))
        logins.append(entry)
        do { try store.save(JSONEncoder().encode(logins), account: "index") } catch { throw Failure.storage }
        return entry
    }

    func remove(_ id: UUID) throws {
        let logins = list().filter { $0.id != id }
        try store.save(JSONEncoder().encode(logins), account: "index")
        try store.delete(account: Self.account(id))
    }

    /// Only the page-filling code calls this. The result is never returned to a Bot or written to the transcript.
    func password(for id: UUID) -> String? {
        guard let data = try? store.read(account: Self.account(id)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func account(_ id: UUID) -> String { "password-" + id.uuidString }

    /// An https host with no embedded credentials, lowercased.
    static func host(from text: String) -> String? {
        guard text.count <= 2000, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil, let host = url.host?.lowercased(), host.contains("."), !host.hasSuffix(".") else { return nil }
        return host
    }

    /// A saved login may only be used on its own site or a subdomain of it, never on a look-alike.
    static func matches(loginHost: String, pageHost: String) -> Bool {
        let login = loginHost.lowercased(), page = pageHost.lowercased()
        return page == login || page.hasSuffix("." + login)
    }
}
