import AppKit
import LocalAuthentication

/// Asks the human before a Bot does something consequential. The request shows exactly what will happen and defaults to Deny.
/// 0.9.2: shown as a card in the chat (like Grok Bot's approval cards) while a window is open; a system alert only when no window is.
/// `authenticate` additionally requires Touch ID or the Mac password, for actions that use a saved credential.
/// Requests that need no Touch ID can also be answered from an approved phone, and whichever answer comes first wins.
@MainActor
final class MacApproval: ObservableObject {
    static let shared = MacApproval()

    /// What the in-chat approval card shows.
    struct Pending: Identifiable, Equatable {
        let id: UUID
        let title: String
        let detail: String
        let authenticate: Bool
    }
    /// The request waiting for an answer in the chat, if any.
    @Published private(set) var pending: Pending?
    static let phoneKey = "phoneApprovalsEnabled"
    /// Replaced in tests so no dialog appears.
    var handler: (@MainActor (_ title: String, _ detail: String, _ authenticate: Bool) async -> Bool)?
    /// Called when the request shown to phones changes.
    var onChange: (() -> Void)?

    @MainActor private final class Request {
        let id = UUID()
        let title: String, detail: String, phoneCanAnswer: Bool
        var continuation: CheckedContinuation<Bool, Never>?
        var sheet: NSWindow?, parent: NSWindow?
        init(title: String, detail: String, phoneCanAnswer: Bool) { self.title = title; self.detail = detail; self.phoneCanAnswer = phoneCanAnswer }
        func resolve(_ approved: Bool) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: approved)
        }
    }
    private var current: Request?

    static var phoneApprovalsEnabled: Bool { UserDefaults.standard.object(forKey: phoneKey) as? Bool ?? true }

    /// What approved phones see, if anything is waiting and a phone is allowed to answer it.
    var remoteRequest: RemoteApproval? {
        guard let current, current.phoneCanAnswer else { return nil }
        return RemoteApproval(id: current.id, title: String(current.title.prefix(200)), detail: String(current.detail.prefix(1500)))
    }

    func respondFromPhone(id: UUID, approved: Bool) -> Bool {
        guard let request = current, request.id == id, request.phoneCanAnswer, Self.phoneApprovalsEnabled else { return false }
        request.resolve(approved)
        if let sheet = request.sheet, let parent = request.parent { parent.endSheet(sheet) }
        if pending?.id == id { pending = nil }
        return true
    }

    /// The human answered the card in the chat.
    func answer(id: UUID, approved: Bool) {
        guard let request = current, request.id == id else { return }
        request.resolve(approved)
        if pending?.id == id { pending = nil }
    }

    /// The Bot named at the start of a request's title ("Let Travel …"), so the sidebar can show who is waiting.
    func isWaiting(on botName: String) -> Bool {
        guard let pending else { return false }
        return pending.title.hasPrefix("Let \(botName) ")
    }

    /// `tool` and `target` let the human's rules answer without a dialog. A Touch ID request is never answered by a rule.
    func approve(title: String, detail: String, authenticate: Bool = false, tool: String? = nil, target: String = "") async -> Bool {
        if !authenticate, let tool, ApprovalRules.shared.decide(tool: tool, target: target) == .allow { return true }
        if let handler { return await handler(title, detail, authenticate) }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "Deny")
        alert.addButton(withTitle: "Approve")
        let request = Request(title: title, detail: detail, phoneCanAnswer: !authenticate && Self.phoneApprovalsEnabled)
        current = request; onChange?()
        if MacPush.enabled { Task { await MacPush.send(title: "Approval needed", body: MacPush.includeText ? title : "A Bot is waiting for your OK.", urgent: true) } }
        let hasWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && !$0.isMiniaturized }
        let approved: Bool = await withCheckedContinuation { continuation in
            request.continuation = continuation
            if hasWindow {
                // The chat shows a card; a phone answer or the card resolves it, whichever comes first.
                pending = Pending(id: request.id, title: title, detail: detail, authenticate: authenticate)
            } else if let parent = NSApp.keyWindow ?? NSApp.mainWindow {
                // A sheet can be closed from the phone's answer; a modal alert could not.
                request.parent = parent; request.sheet = alert.window
                alert.beginSheetModal(for: parent) { response in request.resolve(response == .alertSecondButtonReturn) }
            } else {
                request.resolve(alert.runModal() == .alertSecondButtonReturn)
            }
        }
        if pending?.id == request.id { pending = nil }
        if current === request { current = nil }
        onChange?()
        guard approved, authenticate else { return approved }
        return await Self.verifyOwner(reason: title)
    }

    nonisolated static func verifyOwner(reason: String) async -> Bool {
        let context = LAContext()
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) } catch { return false }
    }
}
