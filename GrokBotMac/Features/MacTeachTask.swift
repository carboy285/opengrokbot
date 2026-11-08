import AppKit
import SwiftUI

/// One thing the human did while teaching a task.
enum TeachStep: Equatable, Sendable {
    case open(app: String)
    case click(app: String, count: Int)
    case type(text: String)
    case secret
    case note(String)

    var line: String {
        switch self {
        case .open(let app): "Open \(app)."
        case .click(let app, let count): count > 1 ? "Click in \(app) (\(count) times)." : "Click in \(app)."
        case .type(let text): "Type “\(text)”."
        case .secret: "Type a password or secret (the human enters this themselves; never type or look it up)."
        case .note(let text): text
        }
    }
}

/// The pure part of recording: collecting steps, merging repeats, and hiding secrets. Nothing here touches the screen or keyboard.
struct TeachRecording: Equatable, Sendable {
    static let maxSteps = 80
    private(set) var steps: [TeachStep] = []

    mutating func opened(_ app: String) {
        guard !app.isEmpty, steps.count < Self.maxSteps else { return }
        if case .open(let last)? = steps.last, last == app { return }
        steps.append(.open(app: app))
    }

    mutating func clicked(in app: String) {
        guard !app.isEmpty else { return }
        if case .click(let last, let count)? = steps.last, last == app { steps[steps.count - 1] = .click(app: app, count: count + 1); return }
        guard steps.count < Self.maxSteps else { return }
        steps.append(.click(app: app, count: 1))
    }

    /// Typed text is kept only when it doesn't look like a secret, and when the human didn't mark it as one.
    mutating func typed(_ text: String, markedSecret: Bool) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, steps.count < Self.maxSteps else { return }
        steps.append(markedSecret || Self.looksSecret(clean) ? .secret : .type(text: String(clean.prefix(300))))
    }

    mutating func noted(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, steps.count < Self.maxSteps else { return }
        steps.append(Self.looksSecret(clean) ? .secret : .note(String(clean.prefix(300))))
    }

    /// Long unbroken tokens, card-like numbers, and text that says it is a password or key.
    static func looksSecret(_ text: String) -> Bool {
        let lower = text.lowercased()
        if ["password", "passcode", "passwd", "secret", "api key", "apikey", "token", "private key", "2fa", "one-time code", "verification code"].contains(where: { lower.contains($0) }) { return true }
        let digits = text.filter(\.isNumber)
        if digits.count >= 12, digits.count <= 19, text.filter({ $0.isLetter }).isEmpty { return true }
        return text.split(whereSeparator: \.isWhitespace).contains { word in
            word.count >= 24 && word.allSatisfy { $0.isLetter || $0.isNumber || "-_=+/".contains($0) } && word.contains { $0.isNumber } && word.contains { $0.isLetter }
        }
    }

    /// The text saved to the Bot's memory.
    static func instruction(title: String, lines: [String]) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return String("Task “\(name.isEmpty ? "Untitled task" : name)”. When asked to do this, follow these steps in order, and ask me before anything that sends, buys or deletes:\n\(body)".prefix(1900))
    }
}

/// Watches which app is in front and where the mouse is clicked while recording. It never reads keystrokes, text on screen or window contents,
/// so it needs no Accessibility permission. Anything typed is added by the human in the recording bar.
@MainActor
final class MacTeachRecorder: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var botID: UUID?
    @Published private(set) var recordingValue = TeachRecording()
    /// Set when recording stops; the review sheet edits and saves it.
    @Published var review: [String]?
    @Published var reviewTitle = ""
    private var activation: NSObjectProtocol?
    private var clickMonitor: Any?
    private let ownBundle = Bundle.main.bundleIdentifier

    var stepCount: Int { recordingValue.steps.count }

    func start(for bot: UUID) {
        guard !recording else { return }
        recordingValue = TeachRecording(); botID = bot; review = nil; reviewTitle = ""
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != ownBundle { recordingValue.opened(front.localizedName ?? "") }
        activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = app?.localizedName ?? "", id = app?.bundleIdentifier
            MainActor.assumeIsolated { if id != self?.ownBundle { self?.objectWillChange.send(); self?.recordingValue.opened(name) } }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != self.ownBundle else { return }
                self.recordingValue.clicked(in: front.localizedName ?? "")
            } }
        }
        recording = true
    }

    func addTyped(_ text: String, secret: Bool) { recordingValue.typed(text, markedSecret: secret) }
    func addNote(_ text: String) { recordingValue.noted(text) }

    func stop() {
        guard recording else { return }
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        activation = nil; clickMonitor = nil; recording = false
        review = recordingValue.steps.map(\.line)
    }

    func discard() { stop(); review = nil; botID = nil; recordingValue = TeachRecording() }
}

/// The recording bar above the message box, and the review sheet that opens when recording stops.
struct MacTeachBar: View {
    let bot: Bot
    @ObservedObject var teach: MacTeachRecorder
    @EnvironmentObject private var app: AppModel
    @State private var text = ""
    @State private var secret = false
    @State private var editing = ""

    var body: some View {
        Group {
            if teach.recording, teach.botID == bot.id {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.red).frame(width: 9, height: 9)
                        Text("Recording · \(teach.stepCount) step\(teach.stepCount == 1 ? "" : "s")").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Stop") { teach.stop() }.buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                    }
                    Text("Switch to the app you want to teach and do the task. Come back here to stop. Only the apps you open and where you click are recorded: no keystrokes and no screen contents.")
                        .font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                    HStack(spacing: 8) {
                        TextField(secret ? "Describe the secret step (the text is not saved)" : "Add a typed step or a note", text: $text).textFieldStyle(.roundedBorder).onSubmit(add)
                        Toggle("Secret", isOn: $secret).toggleStyle(.checkbox).font(.system(size: 12))
                        Button("Add", action: add).controlSize(.small).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }.padding(12).background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 4)
            }
        }
        .sheet(isPresented: Binding(get: { teach.review != nil && teach.botID == bot.id }, set: { if !$0 { teach.discard() } })) { reviewSheet }
    }

    private func add() {
        teach.addTyped(text, secret: secret)
        text = ""; secret = false
    }

    private var reviewSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save what you taught").font(.system(size: 20, weight: .semibold))
            TextField("Name this task, for example Weekly report", text: $teach.reviewTitle).textFieldStyle(.roundedBorder)
            Text("Edit the steps. Secrets are never saved. This is added to \(bot.name)’s memory, so the Bot can follow it when you ask.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
            TextEditor(text: Binding(get: { (teach.review ?? []).joined(separator: "\n") }, set: { teach.review = $0.components(separatedBy: .newlines) }))
                .font(.system(size: 13)).frame(minHeight: 180).scrollContentBackground(.hidden).padding(8)
                .background(MacTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("Discard", role: .destructive) { teach.discard() }
                Spacer()
                Button("Save to memory") { save() }.buttonStyle(.borderedProminent)
                    .disabled(teach.reviewTitle.trimmingCharacters(in: .whitespaces).isEmpty || (teach.review ?? []).allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            }
        }.padding(24).frame(width: 480)
    }

    private func save() {
        let lines = (teach.review ?? []).map { TeachRecording.looksSecret($0) ? TeachStep.secret.line : $0 }
        let note = TeachRecording.instruction(title: teach.reviewTitle, lines: lines)
        if app.updateDetails(bot, name: bot.name, purpose: bot.purpose, memory: (bot.memory ?? []) + [note]) { teach.discard() }
    }
}
