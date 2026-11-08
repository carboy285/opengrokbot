import AppKit
import SwiftUI

/// A Bot asking the human to use the shared VM themselves (to sign in, pick something, and so on) and then carry on.
struct VMHandoffRequest: Identifiable, Equatable {
    let id = UUID()
    let botName: String
    let reason: String
}

enum VMHandoffOutcome: Equatable {
    case done, cancelled, timedOut
    /// What the Bot is told. Only `.done` lets it continue.
    var botMessage: String {
        switch self {
        case .done: "The human finished using the VM and is ready for you to continue. Check the VM for what changed before you go on."
        case .cancelled: "The human cancelled the VM request. Do not continue that task; ask what they would like instead."
        case .timedOut: "The human did not respond about the VM within 30 minutes. Stop this task and tell them it is waiting."
        }
    }
    var continues: Bool { self == .done }
}

/// Shows one request at a time, waits for the human, and hands the answer back to the waiting Bot.
@MainActor
final class MacVMHandoff: ObservableObject {
    static let shared = MacVMHandoff()
    @Published private(set) var request: VMHandoffRequest?
    @Published private(set) var preview: NSImage?
    @Published var note: String?
    /// Set by the app: a picture of the shared VM's screen, and a way to open its console for the human.
    var previewLoader: (@MainActor () async throws -> Data?)?
    var opener: (@MainActor () async throws -> String)?
    private var continuation: CheckedContinuation<VMHandoffOutcome, Never>?
    private var timeout: Task<Void, Never>?
    static let waitLimit: Duration = .seconds(1800)

    /// Puts the request on screen and waits. Another Bot's request waits its turn.
    func ask(botName: String, reason: String) async -> VMHandoffOutcome {
        while request != nil { try? await Task.sleep(for: .milliseconds(400)) }
        let clean = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        request = VMHandoffRequest(botName: botName, reason: clean.isEmpty ? "It needs you to use the VM." : clean)
        preview = nil; note = nil
        let outcome: VMHandoffOutcome = await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeout = Task { [weak self] in
                try? await Task.sleep(for: Self.waitLimit)
                guard !Task.isCancelled else { return }
                self?.finish(.timedOut)
            }
        }
        return outcome
    }

    func finish(_ outcome: VMHandoffOutcome) {
        timeout?.cancel(); timeout = nil
        let waiting = continuation; continuation = nil
        request = nil; preview = nil
        waiting?.resume(returning: outcome)
    }

    func refreshPreview() async {
        guard request != nil, let previewLoader else { return }
        do {
            if let data = try await previewLoader(), let image = NSImage(data: data) { preview = image; note = nil }
        } catch { note = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func openConsole() async {
        guard let opener else { return }
        do { note = try await opener() } catch { note = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

struct MacVMHandoffOverlay: View {
    @ObservedObject var handoff: MacVMHandoff

    var body: some View {
        if let request = handoff.request {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "display").font(.system(size: 18))
                        Text("\(request.botName) needs you in the VM").font(.system(size: 18, weight: .semibold))
                    }
                    Text(request.reason).font(.system(size: 14)).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(MacTheme.canvas)
                        if let image = handoff.preview { Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)) }
                        else { Text("The VM screen appears here when it can be shown. Use Open VM to work in it.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary).padding(20).multilineTextAlignment(.center) }
                    }.frame(height: 260)
                    if let note = handoff.note { Text(note).font(.system(size: 12)).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true) }
                    HStack(spacing: 10) {
                        Button("Open VM") { Task { await handoff.openConsole() } }
                        Spacer()
                        Button("Cancel task") { handoff.finish(.cancelled) }
                        Button("I’m done — continue") { handoff.finish(.done) }.buttonStyle(.borderedProminent)
                    }
                }
                .padding(22).frame(width: 560)
                .background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1)))
                .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
                .task(id: request.id) {
                    await handoff.openConsole()
                    while !Task.isCancelled && handoff.request?.id == request.id {
                        await handoff.refreshPreview()
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
            }
            .transition(.opacity)
            .accessibilityAddTraits(.isModal)
        }
    }
}
