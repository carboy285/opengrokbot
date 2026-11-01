import Foundation

struct ComposioCLIConfiguration {
    var arguments: [String] = []
    var environment: [String:String] = [:]
    private var files: [URL] = []
    func cleanup() { for file in files { try? FileManager.default.removeItem(at: file) } }

    static func make(provider: CLIProvider, directory: URL, sessionURL: String?) throws -> Self {
        guard let sessionURL else { return Self() }
        guard ComposioClient.trustedURL(sessionURL) != nil else { throw ComposioError.invalidResponse }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ComposioBridge").path
        guard FileManager.default.isExecutableFile(atPath: helper) else { throw CLIError.invalidOutput }
        let name = "opengrokbot-composio", variable = "OPENGROKBOT_COMPOSIO_MCP_URL"
        var config = Self(environment: [variable: sessionURL])
        // All generated configs contain environment placeholders; no key or capability URL is written to disk.
        let server: [String:Any] = ["command":helper, "args":[String](), "env":[variable:"${\(variable)}"]]
        func write(_ relative: String, bytes: Data) throws {
            let url = directory.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
            // App-owned per-Bot working directories only. Never replace unrelated project settings.
            guard !FileManager.default.fileExists(atPath: url.path) else { throw CLIError.invalidOutput }
            try bytes.write(to: url, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: url.path)
            config.files.append(url)
        }
        func json(_ object: [String:Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
        do {
            switch provider {
            case .codex:
                // TOML strings use JSON-compatible escaping for ordinary path strings.
                let quoted = String(data: try JSONSerialization.data(withJSONObject: [helper]), encoding: .utf8)!.dropFirst().dropLast()
                config.arguments = ["-c", "mcp_servers.\(name).command=\(quoted)", "-c", "mcp_servers.\(name).env_vars=[\"\(variable)\"]"]
            case .claude:
                let filename = ".composio-\(UUID().uuidString).json"
                try write(filename, bytes: json(["mcpServers":[name:server]]))
                config.arguments = ["--mcp-config",directory.appendingPathComponent(filename).path]
            case .grok:
                let quoted = String(data: try JSONSerialization.data(withJSONObject: [helper]), encoding: .utf8)!.dropFirst().dropLast()
                try write(".grok/config.toml", bytes: Data("[mcp_servers.\(name)]\ncommand = \(quoted)\n[mcp_servers.\(name).env]\n\(variable) = \"${\(variable)}\"\n".utf8))
            case .opencode:
                let filename = ".composio-\(UUID().uuidString).json"
                try write(filename, bytes: json(["mcp":[name:["type":"local", "command":[helper], "enabled":true, "environment":[variable:"{env:\(variable)}"]]]]))
                config.environment["OPENCODE_CONFIG"] = directory.appendingPathComponent(filename).path
            case .gemini:
                try write(".gemini/settings.json", bytes: json(["mcpServers":[name:server]]))
            }
            return config
        } catch { config.cleanup(); throw error }
    }
}
