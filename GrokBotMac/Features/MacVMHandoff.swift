import AppKit
import SwiftUI

/// Clicks, typing and keys sent into the VM by running xdotool inside it, through the same guest-command channel Bots use.
/// Needs xdotool and an Xorg (not Wayland) desktop session in the VM.
enum VMInput {
    static let keys = ["Return", "Tab", "Escape", "BackSpace", "Up", "Down", "Left", "Right"]
    /// Finds the logged-in desktop's display and permission file, then runs xdotool with the arguments after it. Nothing is spliced into the script.
    private static let launcher = "export DISPLAY=:0; for f in /run/user/*/gdm/Xauthority /home/*/.Xauthority /root/.Xauthority; do if [ -f \"$f\" ]; then export XAUTHORITY=\"$f\"; break; fi; done; exec \"$@\""
    private static func run(_ words: [String]) -> [String] { ["/bin/sh", "-c", launcher, "sh", "xdotool"] + words }
    static var geometry: [String] { run(["getdisplaygeometry"]) }
    static func click(x: Int, y: Int) -> [String]? { x >= 0 && y >= 0 && x < 20000 && y < 20000 ? run(["mousemove", String(x), String(y), "click", "1"]) : nil }
    static func type(_ text: String) -> [String]? {
        let clean = String(text.prefix(500))
        guard !clean.isEmpty, !clean.contains("\0") else { return nil }
        return run(["type", "--delay", "30", "--", clean])
    }
    static func key(_ name: String) -> [String]? { keys.contains(name) ? run(["key", name]) : nil }
    /// "Linux guest exit 0:\n1920 1080" becomes (1920, 1080).
    static func parseGeometry(_ output: String) -> (Int, Int)? {
        let numbers = output.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        let tail = Array(numbers.suffix(2))
        return tail[0] > 100 && tail[1] > 100 ? (tail[0], tail[1]) : nil
    }
    static let needsNote = "Clicking and typing need xdotool and an Xorg desktop session in the VM (Ubuntu: sudo apt install xdotool, and sign in with “Ubuntu on Xorg”)."
}

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
    /// Set by the app: runs a guest command in the shared VM (wherever it is) and returns what it printed.
    var inputRunner: (@MainActor ([String]) async throws -> String)?
    @Published private(set) var sending = false
    private var guestSize: (Int, Int)?
    private var continuation: CheckedContinuation<VMHandoffOutcome, Never>?
    private var timeout: Task<Void, Never>?
    static let waitLimit: Duration = .seconds(1800)

    /// Puts the request on screen and waits. Another Bot's request waits its turn.
    func ask(botName: String, reason: String) async -> VMHandoffOutcome {
        while request != nil { try? await Task.sleep(for: .milliseconds(400)) }
        let clean = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        request = VMHandoffRequest(botName: botName, reason: clean.isEmpty ? "It needs you to use the VM." : clean)
        preview = nil; note = nil; guestSize = nil
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
        request = nil; preview = nil; guestSize = nil
        waiting?.resume(returning: outcome)
    }

    func refreshPreview() async {
        guard request != nil, let previewLoader else { return }
        do {
            if let data = try await previewLoader(), let image = NSImage(data: data) { preview = image; note = nil }
        } catch { note = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    /// A click on the picture of the VM screen, as fractions (0...1) of its width and height.
    func click(fx: Double, fy: Double) async {
        guard !sending else { return }
        sending = true; defer { sending = false }
        do {
            let size = try await guestScreenSize()
            guard let argv = VMInput.click(x: Int((fx * Double(size.0)).rounded()), y: Int((fy * Double(size.1)).rounded())) else { return }
            _ = try await send(argv)
            note = nil
        } catch { note = message(error) }
        await refreshPreview()
    }
    func type(_ text: String) async {
        guard !sending, let argv = VMInput.type(text) else { return }
        sending = true; defer { sending = false }
        do { _ = try await send(argv); note = nil } catch { note = message(error) }
        await refreshPreview()
    }
    func press(_ key: String) async {
        guard !sending, let argv = VMInput.key(key) else { return }
        sending = true; defer { sending = false }
        do { _ = try await send(argv); note = nil } catch { note = message(error) }
        await refreshPreview()
    }
    private func guestScreenSize() async throws -> (Int, Int) {
        if let guestSize { return guestSize }
        let output = try await send(VMInput.geometry)
        guard let size = VMInput.parseGeometry(output) else { throw CloudError.message("The VM screen size could not be read. " + VMInput.needsNote) }
        guestSize = size; return size
    }
    private func send(_ argv: [String]) async throws -> String {
        guard let inputRunner else { throw CloudError.message("Open the VM from Settings → Computer to use it.") }
        let output = try await inputRunner(argv)
        if output.contains("exit 1") || output.localizedCaseInsensitiveContains("Can't open display") || output.localizedCaseInsensitiveContains("not found") { throw CloudError.message(VMInput.needsNote) }
        return output
    }
    private func message(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }

    func openConsole() async {
        guard let opener else { return }
        do { note = try await opener() } catch { note = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

struct MacVMHandoffOverlay: View {
    @ObservedObject var handoff: MacVMHandoff
    @State private var typed = ""
    private func sendTyped() { let text = typed; typed = ""; Task { await handoff.type(text) } }

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
                        if let image = handoff.preview {
                            GeometryReader { box in
                                let ratio = image.size.width / max(image.size.height, 1)
                                let width = min(box.size.width, box.size.height * ratio), height = width / max(ratio, 0.01)
                                Image(nsImage: image).resizable().frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                    .onTapGesture(coordinateSpace: .local) { point in Task { await handoff.click(fx: point.x / width, fy: point.y / height) } }
                                    .position(x: box.size.width / 2, y: box.size.height / 2)
                                    .help("Click in the picture to click in the VM")
                            }
                        }
                        else { Text("The VM screen appears here when it can be shown. Use Open VM to work in it.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary).padding(20).multilineTextAlignment(.center) }
                    }.frame(height: 260)
                    HStack(spacing: 8) {
                        TextField("Type into the VM", text: $typed).textFieldStyle(.roundedBorder).onSubmit { sendTyped() }
                        Button("Type") { sendTyped() }.disabled(typed.isEmpty || handoff.sending)
                        ForEach(["Return", "Tab", "Escape", "BackSpace"], id: \.self) { key in
                            Button(key == "BackSpace" ? "⌫" : key == "Return" ? "↩" : key == "Escape" ? "Esc" : key) { Task { await handoff.press(key) } }.disabled(handoff.sending)
                        }
                        if handoff.sending { ProgressView().controlSize(.small) }
                    }
                    Text("Click the picture to click in the VM; type below. Each action takes a moment. " + VMInput.needsNote).font(.system(size: 11)).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
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
