import Foundation

/// Decides which browser actions need the human's approval. Pure and unit-tested.
enum BrowserRisk {
    /// Words on a button or link that mean "do something that is hard to undo or affects others".
    private static let consequential = try! NSRegularExpression(pattern: "\\b(buy|purchase|pay|place (your )?order|order now|checkout|check out|complete (your )?order|confirm|send|submit|post|publish|tweet|reply|delete|remove|cancel|unsubscribe|subscribe|book|reserve|donate|transfer|withdraw|draft|trade|accept|propose|drop|waiver|claim|bid|bet|wager|vote|apply|enroll|register|upgrade|sign out|log out|logout)\\b", options: [.caseInsensitive])
    private static let payment = try! NSRegularExpression(pattern: "(cc-|card.?number|credit.?card|cvv|cvc|security.?code|iban|routing.?number|account.?number|ssn|social.?security)", options: [.caseInsensitive])

    /// A click needs approval when its label sounds consequential, or it submits a form.
    static func clickNeedsApproval(label: String, tag: String, submitsForm: Bool) -> Bool {
        let range = NSRange(label.startIndex..., in: label)
        return submitsForm || consequential.firstMatch(in: label, range: range) != nil
    }

    enum TypeDecision: Equatable { case allow, needsApproval, refuse(String) }

    /// Typing is fine in ordinary fields. Passwords belong to secure logins and payment details are never typed by a Bot.
    static func typeDecision(fieldType: String, hint: String, isSearch: Bool, submit: Bool) -> TypeDecision {
        if fieldType.lowercased() == "password" { return .refuse("This is a password field. Use secure_login so the app can fill it without you or the AI seeing the password.") }
        if payment.firstMatch(in: hint, range: NSRange(hint.startIndex..., in: hint)) != nil || fieldType.lowercased() == "tel" && hint.lowercased().contains("card") {
            return .refuse("This looks like a payment or identity field. Bots never type these; the human must enter them.")
        }
        return submit && !isSearch ? .needsApproval : .allow
    }

    /// What a Bot may ask the browser to do, parsed from an action block.
    struct Request: Equatable {
        enum Kind: Equatable { case click(String), type(field: String, text: String, submit: Bool), scroll(String), back }
        let kind: Kind
        static func from(_ action: BotAction) -> Request? {
            let text = (action.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch action.action {
            case "browser_click": return text.isEmpty || text.count > 200 ? nil : Request(kind: .click(text))
            case "browser_type":
                guard let value = action.text, value.count <= 2000 else { return nil }
                let field = (action.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return field.count <= 200 ? Request(kind: .type(field: field, text: value, submit: action.submit ?? false)) : nil
            case "browser_scroll":
                let direction = (action.direction ?? "down").lowercased()
                return ["up", "down", "top", "bottom"].contains(direction) ? Request(kind: .scroll(direction)) : nil
            case "browser_back": return Request(kind: .back)
            default: return nil
            }
        }
    }
}
