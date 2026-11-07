import Foundation

/// Keys and connector settings copied between computers on one account. It travels only inside the end-to-end encrypted relay, and a
/// computer only sends or accepts one while its own "Share keys and connectors" switch is on (it is off until you turn it on).
/// Whatever arrives is re-validated field by field; nothing is trusted because another computer sent it.
struct SettingsBundle: Codable, Sendable {
    struct Composio: Codable, Sendable { var key: String; var userID: String; var toolkits: [String] }

    static let format = "opengrokbot-settings-bundle"
    static let shareKey = "shareKeysWithComputers"
    static let cliProviders: Set<String> = ["codex", "claude", "grok", "gemini"]
    static let voiceProviders: Set<String> = ["groq", "openAI", "elevenLabs", "nvidiaNIM", "nvidiaCloud", "gemini"]

    var format = SettingsBundle.format
    var version = 1
    var sourceName: String
    var cliKeys: [String: String] = [:]
    var voiceKeys: [String: String] = [:]
    var composio: Composio?

    static var sharingAllowed: Bool { UserDefaults.standard.bool(forKey: shareKey) }
    static let sharingOffMessage = "Turn on “Share keys and connectors” in the Computers screen on both computers first."

    var isEmpty: Bool { cliKeys.isEmpty && voiceKeys.isEmpty && composio == nil }

    /// What this bundle contains, for the result message (never the keys themselves).
    var summary: String {
        var parts: [String] = []
        if !cliKeys.isEmpty { parts.append("\(cliKeys.count) AI provider key\(cliKeys.count == 1 ? "" : "s")") }
        if !voiceKeys.isEmpty { parts.append("\(voiceKeys.count) voice key\(voiceKeys.count == 1 ? "" : "s")") }
        if let composio { parts.append("connectors (\(composio.toolkits.count) apps)") }
        return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> SettingsBundle {
        guard data.count <= 200_000, let bundle = try? JSONDecoder().decode(SettingsBundle.self, from: data), bundle.format == Self.format, bundle.version == 1 else {
            throw CloudError.message("That is not a settings bundle this version understands. Update OpenGrokBot on both computers.")
        }
        return bundle.sanitized()
    }

    /// Keeps only well-formed keys for known providers.
    func sanitized() -> SettingsBundle {
        var clean = SettingsBundle(sourceName: String(sourceName.prefix(80)))
        for (provider, key) in cliKeys where Self.cliProviders.contains(provider) {
            if let value = ProviderAPIKeys.normalized(key) { clean.cliKeys[provider] = value }
        }
        for (provider, key) in voiceKeys where Self.voiceProviders.contains(provider) {
            let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if (8...600).contains(value.count), value.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) { clean.voiceKeys[provider] = value }
        }
        if let composio {
            let key = composio.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let slugs = composio.toolkits.filter { $0.range(of: "^[_a-z0-9]{1,100}$", options: .regularExpression) != nil }
            if !key.isEmpty, key.count < 4096, !key.contains(where: { $0.isWhitespace }), composio.userID.range(of: "^[A-Za-z0-9_-]{8,100}$", options: .regularExpression) != nil, !slugs.isEmpty, slugs.count <= 30 {
                clean.composio = Composio(key: key, userID: composio.userID, toolkits: Array(slugs))
            }
        }
        return clean
    }
}

extension MacAppModel {
    /// This Mac's keys and connector settings, if this Mac has been allowed to share them.
    func makeSettingsBundle() -> SettingsBundle {
        var bundle = SettingsBundle(sourceName: Host.current().localizedName ?? "Mac")
        for provider in CLIProvider.allCases where ProviderAPIKeys.info(for: provider) != nil {
            if let key = ProviderAPIKeys.get(provider) { bundle.cliKeys[provider.rawValue] = key }
        }
        for provider in VoiceProvider.allCases where provider != .apple {
            let key = VoiceKeys.get(provider)
            if !key.isEmpty { bundle.voiceKeys[provider.rawValue] = key }
        }
        if let export = composio.exportConfiguration() {
            bundle.composio = SettingsBundle.Composio(key: export.key, userID: UserDefaults.standard.string(forKey: "composioUserID") ?? "", toolkits: export.toolkits)
        }
        return bundle.sanitized()
    }

    /// Saves keys and sets up the connector project on this Mac. Returns a sentence for the result message.
    func applySettingsBundle(_ bundle: SettingsBundle) async -> String {
        let bundle = bundle.sanitized()
        guard !bundle.isEmpty else { return "Nothing to copy: no keys or connectors were found on \(bundle.sourceName)." }
        var parts: [String] = []
        var saved = 0
        for (name, key) in bundle.cliKeys { if let provider = CLIProvider(rawValue: name), (try? ProviderAPIKeys.save(key, for: provider)) == true { saved += 1 } }
        if saved > 0 { parts.append("\(saved) AI provider key\(saved == 1 ? "" : "s")") }
        var voice = 0
        for (name, key) in bundle.voiceKeys { if let provider = VoiceProvider(rawValue: name) { VoiceKeys.set(key, for: provider); voice += 1 } }
        if voice > 0 { parts.append("\(voice) voice key\(voice == 1 ? "" : "s")") }
        if let connector = bundle.composio {
            let result = await composio.adopt(projectKey: connector.key, userID: connector.userID, toolkits: connector.toolkits)
            parts.append(result)
        }
        return "Received " + parts.joined(separator: ", ") + " from \(bundle.sourceName)."
    }
}
