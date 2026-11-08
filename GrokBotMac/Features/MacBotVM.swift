import AppKit
import SwiftUI
import ScreenCaptureKit
import CoreGraphics

@MainActor
final class MacBotVMs: ObservableObject {
    static let shared = MacBotVMs()
    @Published var busy = Set<UUID>()
    @Published var feedback: [UUID:String] = [:]
    private let preferences = UserDefaults.standard
    func commandsEnabled(_ id: UUID) -> Bool { preferences.bool(forKey: "bot-vm-commands-" + id.uuidString) }
    func setCommands(_ enabled: Bool, id: UUID) { preferences.set(enabled, forKey: "bot-vm-commands-" + id.uuidString); objectWillChange.send() }
    // MARK: A VM on another computer
    /// Another computer's VM that one of this Mac's Bots uses instead of a VM of its own.
    struct RemoteLink: Codable, Equatable {
        var hostID: UUID
        var hostName: String
        var vmBotID: UUID
        var vmName: String
    }
    /// Set by the app: runs a command in a VM on another computer on this account.
    var remoteRunner: (@MainActor (RemoteLink, [String]) async throws -> String)?
    func remoteLink(_ id: UUID) -> RemoteLink? {
        preferences.data(forKey: "bot-vm-remote-" + id.uuidString).flatMap { try? JSONDecoder().decode(RemoteLink.self, from: $0) }
    }
    func setRemoteLink(_ link: RemoteLink?, for id: UUID) {
        if let link, let data = try? JSONEncoder().encode(link) { preferences.set(data, forKey: "bot-vm-remote-" + id.uuidString) } else { preferences.removeObject(forKey: "bot-vm-remote-" + id.uuidString) }
        objectWillChange.send()
    }
    /// Whether other computers on this account may run commands in this Bot's VM. Off until the human turns it on here.
    func sharedWithComputers(_ id: UUID) -> Bool { preferences.bool(forKey: "bot-vm-shared-" + id.uuidString) }
    func setShared(_ on: Bool, id: UUID) { preferences.set(on, forKey: "bot-vm-shared-" + id.uuidString); objectWillChange.send() }

    private static func checkCommand(_ argv: [String]) throws {
        guard (1...16).contains(argv.count), argv[0].hasPrefix("/"), argv.reduce(0, { $0 + $1.utf8.count }) <= 16000, !argv.contains(where: { $0.contains("\0") }) else { throw CloudError.message("Use 1–16 guest command arguments, starting with an absolute Linux executable path.") }
    }

    /// Runs a Bot's guest command in the VM it uses: one on another computer if it is set up that way, otherwise its own.
    func execute(_ bot: Bot, argv: [String]) async throws -> String {
        guard let link = remoteLink(bot.id) else { return try await executeLocal(bot, argv: argv) }
        try Self.checkCommand(argv)
        guard let remoteRunner else { throw CloudError.message("Sign in to your OpenGrokBot account to use a VM on another computer.") }
        return "Linux guest on \(link.hostName) (\(link.vmName)):\n" + (try await remoteRunner(link, argv))
    }

    /// Runs a guest command in this Mac's own VM for the Bot. This is also what a command from another computer uses, so it never forwards again.
    func executeLocal(_ bot: Bot, argv: [String]) async throws -> String {
        guard commandsEnabled(bot.id), let id = assigned(bot.id), UUID(uuidString: id) != nil else { throw CloudError.message("Set up this Bot’s VM and enable Bot commands in its VM settings first.") }
        try Self.checkCommand(argv)
        let result = await Task.detached { CLIInstallationScanner.capture(path: "/Applications/UTM.app/Contents/MacOS/utmctl", arguments: ["exec",id,"--cmd"] + argv, timeout: 65, limit: 16000) }.value
        guard result.exit >= 0 else { throw CloudError.message("Guest command did not finish. Install/start qemu-guest-agent in the Linux template and check UTM. A timed-out guest process may still be running.") }
        return "Linux guest exit \(result.exit):\n" + result.text
    }
    func enableViewing(_ id: UUID) {
        preferences.set(true, forKey: "bot-vm-viewing-" + id.uuidString)
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        objectWillChange.send()
    }
    func preview(_ bot: Bot) async throws -> RemoteBrowserPreview {
        guard assigned(bot.id) != nil else { return RemoteBrowserPreview(title: "VM not set up", url: "Set up this Bot’s Linux VM on the host desktop.", imageData: nil) }
        guard preferences.bool(forKey: "bot-vm-viewing-" + bot.id.uuidString), CGPreflightScreenCaptureAccess() else { throw CloudError.message("On the hosting Mac, open this Bot’s VM settings, enable remote VM viewing, and allow macOS Screen Recording for OpenGrokBot.") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let expected = "OpenGrokBot-" + bot.id.uuidString
        guard let window = content.windows.first(where: { window in
            guard let owner = window.owningApplication else { return false }
            return owner.bundleIdentifier.lowercased().contains("utm") && (window.title?.range(of: expected, options: .caseInsensitive) != nil)
        }) else { throw CloudError.message("Open this Bot’s UTM console on the hosting Mac. Only its matching VM window can be shared.") }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration(); configuration.width = 900
        configuration.height = max(1, min(1600, Int(900 * window.frame.height / max(1, window.frame.width))))
        configuration.showsCursor = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor:0.6]), data.count <= 2_000_000 else { throw CloudError.message("The VM preview is too large.") }
        return RemoteBrowserPreview(title: window.title ?? expected, url: "UTM · local Linux VM", imageData: data)
    }
    func assigned(_ id: UUID) -> String? { preferences.string(forKey: "bot-vm-" + id.uuidString) }
    var installed: Bool { FileManager.default.isExecutableFile(atPath: "/Applications/UTM.app/Contents/MacOS/utmctl") }
    func provision(_ bot: Bot) async {
        guard !busy.contains(bot.id) else { return }
        guard installed else { feedback[bot.id] = "Install UTM in Applications first, then download a Linux .utm template matching this Mac’s architecture."; return }
        guard assigned(bot.id) == nil else { await open(bot); return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.treatsFilePackagesAsDirectories = false
        panel.title = "Choose a downloaded Linux .utm template"; panel.message = "OpenGrokBot creates an independent VM for this Bot with 2 CPU cores and 4 GB RAM. The template’s disk and Linux desktop are copied."
        guard panel.runModal() == .OK, let template = panel.url, template.pathExtension.lowercased() == "utm" else { return }
        busy.insert(bot.id); feedback[bot.id] = "Importing and cloning Linux template…"; defer { busy.remove(bot.id) }
        let vmName = "OpenGrokBot-" + bot.id.uuidString
        let script = """
        on run argv
          tell application "UTM"
            set sourceVM to import new virtual machine from (POSIX file (item 1 of argv))
            duplicate sourceVM with properties {configuration:{name:(item 2 of argv), memory:4096, cpu cores:2}}
            set assignedVM to virtual machine named (item 2 of argv)
            return id of assignedVM
          end tell
        end run
        """
        let result = await Task.detached {
            CLIInstallationScanner.capture(path: "/usr/bin/osascript", arguments: ["-e",script,template.path,vmName], timeout: 600, limit: 4096)
        }.value
        guard result.exit == 0, let id = UUID(uuidString: result.text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            feedback[bot.id] = "UTM could not finish setup. Allow OpenGrokBot to control UTM in macOS Privacy & Security → Automation, and use a stopped Linux template for this Mac’s architecture. Check UTM for a partially imported VM before retrying."; return
        }
        preferences.set(id.uuidString, forKey: "bot-vm-" + bot.id.uuidString)
        await open(bot)
    }
    func open(_ bot: Bot) async {
        guard let id = assigned(bot.id), UUID(uuidString: id) != nil else { feedback[bot.id] = "Set up this Bot’s Linux VM from Bot details first."; return }
        let result = await Task.detached { CLIInstallationScanner.capture(path: "/Applications/UTM.app/Contents/MacOS/utmctl", arguments: ["start",id], timeout: 60, limit: 4096) }.value
        feedback[bot.id] = result.exit == 0 ? "Linux VM opened in UTM. The AI CLI still runs on the host; guest automation requires guest tools." : "UTM could not start the VM. If it is already running, open its console in UTM."
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/UTM.app"))
    }
}

struct MacBotVMControls: View {
    let bot: Bot
    @ObservedObject private var vms = MacBotVMs.shared
    var body: some View {
        InspectorCard(title: "Linux VM", footer: "The AI CLI stays on this Mac. Guest commands run inside Linux through UTM’s guest agent; no AI agent is installed in the guest.") {
            Text("Runs in UTM on this Mac. Install UTM and a Linux template, then set up the VM. It starts with 2 CPU cores and 4 GB RAM; disk size comes from the template.")
                .font(.system(size: 13)).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
            if vms.assigned(bot.id) == nil {
                VMLinkRow(title: "Download UTM", url: "https://mac.getutm.app/")
                VMLinkRow(title: "Download a Linux template", url: "https://mac.getutm.app/gallery/")
            }
            Button(vms.busy.contains(bot.id) ? "Setting up VM…" : vms.assigned(bot.id) == nil ? "Set up this Bot’s Linux VM…" : "Open this Bot’s VM") { Task { if vms.assigned(bot.id) == nil { await vms.provision(bot) } else { await vms.open(bot) } } }
                .buttonStyle(InspectorButtonStyle()).disabled(vms.busy.contains(bot.id))
            if vms.assigned(bot.id) != nil {
                Divider()
                Button("Enable remote VM viewing") { vms.enableViewing(bot.id) }.buttonStyle(InspectorButtonStyle())
                Text("Needs macOS Screen Recording permission. Only this Bot’s UTM console window is captured.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Allow guest commands", isOn: Binding(get: { vms.commandsEnabled(bot.id) }, set: { vms.setCommands($0, id: bot.id) }))
                Text("Needs qemu-guest-agent in Linux. Commands may run as root inside the VM.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Let my other computers use this VM", isOn: Binding(get: { vms.sharedWithComputers(bot.id) }, set: { vms.setShared($0, id: bot.id) }))
                    .disabled(!vms.commandsEnabled(bot.id))
                Text("Bots on your other computers (signed in to your account) can run commands in this VM. It needs “Allow guest commands” above, and you can turn it off at any time.").font(.system(size: 12)).foregroundStyle(MacTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let feedback = vms.feedback[bot.id] { Text(feedback).font(.system(size: 12)).foregroundStyle(MacTheme.secondary).textSelection(.enabled) }
        }
    }
}

/// Lets this Bot use a Linux VM that another computer on the account is sharing, instead of a VM of its own.
struct MacRemoteVMCard: View {
    let bot: Bot
    @EnvironmentObject private var desktop: MacAppModel
    @ObservedObject private var vms = MacBotVMs.shared
    @State private var host: CloudDevice?
    @State private var available: [RemoteVM] = []
    @State private var loading = false
    @State private var note: String?

    var body: some View {
        InspectorCard(title: "VM on another computer", footer: "The VM keeps running on the other computer. Commands travel over your encrypted account connection, and the other computer must have turned sharing on for that VM. The first time, approve this Mac there if it asks.") {
            if let link = vms.remoteLink(bot.id) {
                Text("Using “\(link.vmName)” on \(link.hostName). This Bot’s guest commands run there.").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                Button("Stop using it") { vms.setRemoteLink(nil, for: bot.id); note = nil }.buttonStyle(InspectorButtonStyle())
            } else {
                let computers = desktop.computers()
                if computers.isEmpty {
                    Text("Sign in to your account on another computer that has OpenGrokBot open to use its VM here.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
                } else {
                    Menu(host?.name ?? "Choose a computer…") {
                        ForEach(computers, id: \.id) { computer in Button(computer.name) { host = computer; Task { await load(computer) } } }
                    }
                    if loading { ProgressView().controlSize(.small) }
                    ForEach(available) { vm in
                        Button("Use “\(vm.botName)”", systemImage: "externaldrive.connected.to.line.below") {
                            guard let host else { return }
                            vms.setRemoteLink(MacBotVMs.RemoteLink(hostID: host.id, hostName: host.name, vmBotID: vm.botID, vmName: vm.botName), for: bot.id)
                        }.buttonStyle(InspectorButtonStyle())
                    }
                }
            }
            if let note { Text(note).font(.system(size: 12)).foregroundStyle(MacTheme.secondary).textSelection(.enabled) }
        }
    }

    private func load(_ computer: CloudDevice) async {
        loading = true; note = nil; available = []
        defer { loading = false }
        do {
            let list = try await desktop.ensureCopyGateway().vms(on: computer)
            available = list
            if list.isEmpty { note = "\(computer.name) is not sharing any VM. On that computer, open a Bot’s Linux VM settings, turn on “Allow guest commands”, then “Let my other computers use this VM”." }
        } catch { note = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

private struct VMLinkRow: View {
    let title: String
    let url: String
    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack {
                    Text(title).font(.system(size: 14))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(MacTheme.secondary)
                }
                .padding(.horizontal, 12).frame(minHeight: 36)
                .background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 10)).contentShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
        }
    }
}
