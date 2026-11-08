import Foundation

/// Rules the human wrote for what Bots may do without asking, and what must always be asked.
/// "Always ask" beats "Allow without asking". Deleting, sending, typing-and-submitting and saved logins can never be allowed by a rule.
struct ApprovalRule: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case ask, allow }
    var id = UUID()
    var kind: Kind
    /// One of `ApprovalRules.tools`.
    var tool: String
    /// Optional text the target must contain (a website for browser clicks, a name for Apple apps). Blank means any.
    var pattern: String = ""
}

enum ApprovalDecision: Equatable, Sendable { case allow, ask, noRule }

@MainActor
final class ApprovalRules: ObservableObject {
    static let shared = ApprovalRules()
    /// Tools a rule can name. Everything else always asks.
    /// Clicks on web pages can only get an "Always ask" rule: a click that sends or buys always asks regardless.
    static let askOnlyTools: Set<String> = ["browser_click"]
    static let tools: [(id: String, title: String)] = [
        ("reminders", "Add or change reminders"), ("calendar", "Add or change calendar events"),
        ("contacts", "Add or change contacts"), ("notes", "Add or change notes"),
        ("browser_click", "Click on a web page")
    ]
    static let maxRules = 60
    static func title(for tool: String) -> String { tools.first { $0.id == tool }?.title ?? tool }

    @Published private(set) var rules: [ApprovalRule]
    /// When off the lists are ignored and the per-app toggles decide.
    @Published private(set) var enabled: Bool
    private let defaults: UserDefaults
    private static let rulesKey = "approvalRules.v1", enabledKey = "approvalRulesEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        if let data = defaults.data(forKey: Self.rulesKey), let saved = try? JSONDecoder().decode([ApprovalRule].self, from: data) {
            rules = saved.filter { rule in Self.tools.contains { $0.id == rule.tool } && (rule.kind == .ask || !Self.askOnlyTools.contains(rule.tool)) }.prefix(Self.maxRules).map { $0 }
        } else { rules = [] }
    }

    func setEnabled(_ on: Bool) { enabled = on; defaults.set(on, forKey: Self.enabledKey) }

    @discardableResult
    func add(kind: ApprovalRule.Kind, tool: String, pattern: String) -> Bool {
        let clean = String(pattern.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard Self.tools.contains(where: { $0.id == tool }), rules.count < Self.maxRules, kind == .ask || !Self.askOnlyTools.contains(tool),
              !rules.contains(where: { $0.kind == kind && $0.tool == tool && $0.pattern.caseInsensitiveCompare(clean) == .orderedSame }) else { return false }
        rules.append(ApprovalRule(kind: kind, tool: tool, pattern: clean)); save(); return true
    }

    func remove(_ id: UUID) { rules.removeAll { $0.id == id }; save() }

    private func save() { if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: Self.rulesKey) } }

    /// What the rules say about doing `tool` on `target`. "Always ask" wins over "Allow".
    func decide(tool: String, target: String = "") -> ApprovalDecision {
        guard enabled, Self.tools.contains(where: { $0.id == tool }) else { return .noRule }
        let matching = rules.filter { rule in
            rule.tool == tool && (rule.pattern.isEmpty || target.range(of: rule.pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
        if matching.contains(where: { $0.kind == .ask }) { return .ask }
        if !Self.askOnlyTools.contains(tool), matching.contains(where: { $0.kind == .allow }) { return .allow }
        return .noRule
    }
}
