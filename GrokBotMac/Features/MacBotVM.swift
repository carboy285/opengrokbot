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
    func execute(_ bot: Bot, argv: [String]) async throws -> String {
        guard commandsEnabled(bot.id), let id = assigned(bot.id), UUID(uuidString: id) != nil else { throw CloudError.message("Set up this Bot’s VM and enable Bot commands in its VM settings first.") }
        guard (1...16).contains(argv.count), argv[0].hasPrefix("/"), argv.reduce(0, { $0 + $1.utf8.count }) <= 16000, !argv.contains(where: { $0.contains("\0") }) else { throw CloudError.message("Use 1–16 guest command arguments, starting with an absolute Linux executable path.") }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Linux VM").font(.headline)
            Text("Install UTM and download a Linux .utm template from its gallery. Setup imports a separate copy for this Bot and opens its console. Default: 2 CPU cores, 4 GB RAM; disk size comes from the template.").font(.caption).foregroundStyle(.secondary)
            Link("Download UTM", destination: URL(string: "https://mac.getutm.app/")!)
            Link("Download a Linux template", destination: URL(string: "https://mac.getutm.app/gallery/")!)
            Button(vms.busy.contains(bot.id) ? "Setting up VM…" : vms.assigned(bot.id) == nil ? "Set up this Bot’s Linux VM…" : "Open this Bot’s VM") { Task { if vms.assigned(bot.id) == nil { await vms.provision(bot) } else { await vms.open(bot) } } }.disabled(vms.busy.contains(bot.id))
            if vms.assigned(bot.id) != nil {
                Button("Enable remote VM viewing") { vms.enableViewing(bot.id) }
                Text("macOS Screen Recording permission is required. Only this Bot’s matching UTM console window is captured; the rest of the host screen is excluded.").font(.caption).foregroundStyle(.secondary)
                Toggle("Allow this Bot to run guest commands", isOn: Binding(get: { vms.commandsEnabled(bot.id) }, set: { vms.setCommands($0, id: bot.id) }))
                Text("Requires qemu-guest-agent in Linux. Commands run through UTM’s guest agent and may run as root inside the VM.").font(.caption).foregroundStyle(.secondary)
            }
            if let feedback = vms.feedback[bot.id] { Text(feedback).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Text("The VM console opens locally in UTM. The AI CLI remains on the host. Optional guest commands run inside Linux through guest tools; no separate AI agent is installed in the guest.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
