import Foundation

/// Phone notifications through ntfy (https://ntfy.sh, or your own server): no account or Apple push key needed.
/// Install the free ntfy app on the iPhone and subscribe to the topic shown in Settings. By default only "<Bot> replied" is sent,
/// never the reply text, because anyone who learns the topic name could read it.
enum MacPush {
    static let enabledKey = "pushEnabled", serverKey = "pushServer", topicKey = "pushTopic", textKey = "pushIncludeText"
    static let defaultServer = "https://ntfy.sh"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var includeText: Bool { UserDefaults.standard.bool(forKey: textKey) }
    static var server: String { UserDefaults.standard.string(forKey: serverKey) ?? defaultServer }

    /// A long random topic, created once. The topic name is the only secret protecting the notifications.
    static func topic(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: topicKey), isValid(topic: existing) { return existing }
        let made = "opengrokbot-" + (0..<12).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        defaults.set(made, forKey: topicKey)
        return made
    }

    static func isValid(topic: String) -> Bool {
        (8...80).contains(topic.count) && topic.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// An https server address with no credentials, path or query.
    static func validatedServer(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host, host.contains("."), url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { return nil }
        return url
    }

    static func payload(topic: String, title: String, body: String, urgent: Bool) -> Data? {
        let object: [String: Any] = ["topic": topic, "title": String(title.prefix(120)), "message": String(body.prefix(300)), "priority": urgent ? 4 : 3, "tags": [urgent ? "warning" : "robot"]]
        return try? JSONSerialization.data(withJSONObject: object)
    }

    @discardableResult
    static func send(title: String, body: String, urgent: Bool = false, force: Bool = false) async -> Bool {
        guard force || enabled, let url = validatedServer(server), let data = payload(topic: topic(), title: title, body: body, urgent: urgent) else { return false }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (_, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
