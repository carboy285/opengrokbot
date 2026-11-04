import AppKit
import LocalAuthentication

/// Asks the human before a Bot does something consequential. The dialog shows exactly what will happen and defaults to Deny.
/// `authenticate` additionally requires Touch ID or the Mac password, for actions that use a saved credential.
@MainActor
final class MacApproval {
    static let shared = MacApproval()
    /// Replaced in tests so no dialog appears.
    var handler: (@MainActor (_ title: String, _ detail: String, _ authenticate: Bool) async -> Bool)?

    func approve(title: String, detail: String, authenticate: Bool = false) async -> Bool {
        if let handler { return await handler(title, detail, authenticate) }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "Deny")
        alert.addButton(withTitle: "Approve")
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        guard authenticate else { return true }
        return await Self.verifyOwner(reason: title)
    }

    nonisolated static func verifyOwner(reason: String) async -> Bool {
        let context = LAContext()
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) } catch { return false }
    }
}
