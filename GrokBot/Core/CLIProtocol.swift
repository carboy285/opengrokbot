import Foundation

enum CLIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case codex, claude, grok, opencode, gemini
    var id: String { rawValue }
    var name: String { switch self { case .codex: "Codex"; case .claude: "Claude Code"; case .grok: "Grok Build"; case .opencode: "OpenCode"; case .gemini: "Gemini CLI" } }
    var executable: String { rawValue }
    var loginCommand: String { switch self { case .codex: "codex login"; case .opencode: "opencode auth login"; default: executable } }
    var guideURL: URL {
        let address: String
        switch self {
        case .codex: address = "https://github.com/openai/codex#quickstart"
        case .claude: address = "https://code.claude.com/docs/en/setup"
        case .grok: address = "https://github.com/xai-org/grok-build#installing-the-released-binary"
        case .opencode: address = "https://opencode.ai/docs/"
        case .gemini: address = "https://geminicli.com/docs/get-started/installation/"
        }
        return URL(string: address)!
    }
    var installCommand: String {
        switch self {
        case .codex: "npm install -g @openai/codex"
        case .claude: "npm install -g @anthropic-ai/claude-code"
        case .opencode: "npm install -g opencode-ai"
        case .gemini: "npm install -g @google/gemini-cli"
        case .grok: "See the official Grok Build install guide."
        }
    }

}

struct BotAIProvider: Codable, Hashable, Sendable, Identifiable {
    var provider: CLIProvider
    var model: String = ""
    var id: String { provider.rawValue }
}

/// `one`: only the active provider answers. `compare`: every enabled provider answers side by side, in plain text with no tools. (`all` is a legacy value that is always treated as `one`.)
enum ProviderReplyMode: String, Codable, Hashable, Sendable { case one, all, compare }

struct BotAIConfiguration: Codable, Hashable, Sendable {
    var providers: [BotAIProvider]
    var activeProvider: CLIProvider?
    var replyMode: ProviderReplyMode = .one
}

struct AvailableCLIModel: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
}

struct InstalledCLI: Identifiable, Hashable, Sendable {
    let provider: CLIProvider
    let path: String
    let version: String
    var id: String { provider.rawValue + ":" + path }
}

/// `notice` is a short explanation for the human (for example that connected apps did not load); it is shown in the chat.
enum CLIEvent: Sendable, Equatable { case session(String), text(String), activity(String), notice(String), failed }

enum CLIError: Error, LocalizedError, Equatable {
    case notInstalled, notLoggedIn, invalidModel, network, rateLimited, failed(Int32), invalidOutput, stopped, timedOut
    /// Classify locally; never return raw stderr, which may contain credentials or conversation data.
    static func classify(stderr: String, exitCode: Int32) -> CLIError {
        let text = stderr.lowercased()
        if ["rate limit", "too many requests", "http 429", "status 429"].contains(where: text.contains) { return .rateLimited }
        if ["model not found", "unknown model", "invalid model", "unsupported model"].contains(where: text.contains) { return .invalidModel }
        if ["not logged in", "unauthorized", "authentication failed", "sign in", "http 401", "status 401"].contains(where: text.contains) { return .notLoggedIn }
        if ["network error", "connection refused", "could not resolve host", "dns lookup failed", "connection timed out"].contains(where: text.contains) { return .network }
        return .failed(exitCode)
    }
    var errorDescription: String? {
        switch self {
        case .notInstalled: "Choose an installed AI CLI in setup first."
        case .notLoggedIn: "Your CLI needs authentication. Open setup, sign in through the CLI, then try again."
        case .invalidModel: "The selected model was rejected or could not be found. Choose a model available to this provider and try again."
        case .network: "The CLI could not reach its service. Check the computer’s network connection and try again."
        case .rateLimited: "The provider reported a rate limit. Wait a little while and try again."
        case .failed(let code): "The AI CLI stopped with exit code \(code). Check its login and configuration in Terminal, then retry."
        case .invalidOutput: "The CLI did not return a supported AI response. Update the CLI or select another installation."
        case .stopped: "Response stopped. You can send another message."
        case .timedOut: "The CLI did not finish within ten minutes. Check its connection and try again."
        }
    }
}

struct CLICommand: Sendable {
    let arguments: [String]
    let input: String
    /// The name Bots' connected apps (Composio) are registered under in each CLI.
    static let connectedAppsServer = "opengrokbot-composio"
    /// `allowConnectedApps` pre-approves only the connected-apps tools for Claude Code, which cannot ask for permission in the background.
    static func chat(provider: CLIProvider, prompt: String, session: String?, promptFile: String? = nil, model: String = "", allowConnectedApps: Bool = false) -> CLICommand {
        let modelArguments = model.isEmpty ? [String]() : ["--model", model]
        switch provider {
        case .codex:
            var args = ["exec", "--sandbox", "read-only"]
            if let session { args += ["resume", session] }
            args += modelArguments + ["--json", "--skip-git-repo-check", "-"]
            return CLICommand(arguments: args, input: prompt)
        case .claude:
            var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
            if allowConnectedApps { args += ["--allowedTools", "mcp__" + connectedAppsServer] }
            if let session { args += ["--resume", session] }
            return CLICommand(arguments: args + modelArguments, input: prompt)
        case .opencode:
            var args = ["run", "--format", "json"]
            if let session { args += ["--session", session] }
            return CLICommand(arguments: args + modelArguments, input: prompt)
        case .gemini:
            var args = ["--output-format", "stream-json"]
            if let session { args += ["--resume", session] }
            return CLICommand(arguments: args + modelArguments, input: prompt)
        case .grok:
            var args = ["--prompt-file", promptFile ?? "prompt.txt", "--output-format", "streaming-messages-json", "--include-partial-messages"]
            if let session { args += ["--resume", session] }
            return CLICommand(arguments: args + modelArguments, input: "")
        }
    }
}

/// Decode only documented conversational fields. Auth metadata and stderr never enter chat.
struct CLIEventParser {
    private(set) var text = ""
    private var codexOrder: [String] = []
    private var codexMessages: [String:String] = [:]
    mutating func parse(_ data: Data) -> [CLIEvent] {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String:Any], let type = value["type"] as? String else { return [] }
        var events: [CLIEvent] = []
        if let id = (value["thread_id"] ?? value["session_id"] ?? value["sessionID"]) as? String,
           !id.isEmpty, id.count <= 200, id.first != "-", id.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_" )).inverted) == nil { events.append(.session(id)) }
        // Claude Code reports which MCP servers started and which tool calls it refused. Say so, instead of leaving the Bot to guess.
        if type == "system", value["subtype"] as? String == "init", let servers = value["mcp_servers"] as? [[String:Any]] {
            for server in servers where (server["name"] as? String) == CLICommand.connectedAppsServer {
                let status = (server["status"] as? String) ?? "unknown"
                if status != "connected" { events.append(.notice("Connected apps did not load: the Composio connection reported “\(status)”. Open Connect apps and choose Refresh connections, then send the message again.")) }
            }
        }
        if type == "result", let denials = value["permission_denials"] as? [[String:Any]],
           denials.contains(where: { ($0["tool_name"] as? String)?.hasPrefix("mcp__" + CLICommand.connectedAppsServer) == true }) {
            events.append(.notice("Claude Code did not run a connected-app action because it needs your permission and cannot ask while it works in the background. In Connect apps, turn on “Let Claude Code use connected apps without asking” if you want it to."))
        }
        if type == "turn.failed" || (type == "result" && (value["is_error"] as? Bool == true || value["status"] as? String == "error")) { events.append(.failed); return events }
        if type == "error" { events.append(.activity("The CLI is handling a connection or provider error…")) }
        if value["parent_tool_use_id"] is String { return events }
        if type == "text", let part = value["part"] as? [String:Any], let message = part["text"] as? String {
            let id = part["id"] as? String ?? "answer"
            if codexMessages[id] == nil { codexOrder.append(id) }
            codexMessages[id] = message
            text = codexOrder.compactMap { codexMessages[$0] }.joined(separator: "\n\n")
            events.append(.text(text))
        } else if type == "message", value["role"] as? String == "assistant", let message = value["content"] as? String {
            if value["delta"] as? Bool == true { text += message } else { text = message }
            events.append(.text(text))
        } else if type == "item.completed" || type == "item.updated", let item = value["item"] as? [String:Any] {
            if item["type"] as? String == "agent_message", let message = item["text"] as? String {
                let id = item["id"] as? String ?? "answer"
                if codexMessages[id] == nil { codexOrder.append(id) }
                codexMessages[id] = message
                text = codexOrder.compactMap { codexMessages[$0] }.joined(separator: "\n\n")
                events.append(.text(text))
            } else if type == "item.updated" { events.append(.activity("Working…")) }
        } else if type == "stream_event", let event = value["event"] as? [String:Any], let delta = event["delta"] as? [String:Any], delta["type"] as? String == "text_delta", let fragment = delta["text"] as? String {
            text += fragment; events.append(.text(text))
        } else if type == "assistant", let message = value["message"] as? [String:Any], let content = message["content"] as? [[String:Any]], text.isEmpty {
            text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { events.append(.text(text)) }
        } else if type == "result", let result = value["result"] as? String, !result.isEmpty {
            text = result; events.append(.text(text))
        }
        return events
    }
}
