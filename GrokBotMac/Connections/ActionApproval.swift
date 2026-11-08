import AppKit
import LocalAuthentication

/// Asks the human before a Bot does something consequential. The dialog shows exactly what will happen and defaults to Deny.
/// `authenticate` additionally requires Touch ID or the Mac password, for actions that use a saved credential.
/// Requests that need no Touch ID can also be answered from an approved phone, and whichever answer comes first wins.
@MainActor
final class MacApproval {
    static let shared = MacApproval()
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
        return true
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
        let approved: Bool = await withCheckedContinuation { continuation in
            request.continuation = continuation
            if let parent = NSApp.keyWindow ?? NSApp.mainWindow {
                // A sheet can be closed from the phone's answer; a modal alert could not.
                request.parent = parent; request.sheet = alert.window
                alert.beginSheetModal(for: parent) { response in request.resolve(response == .alertSecondButtonReturn) }
            } else {
                request.resolve(alert.runModal() == .alertSecondButtonReturn)
            }
        }
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
