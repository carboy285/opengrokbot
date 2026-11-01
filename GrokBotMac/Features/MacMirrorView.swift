import SwiftUI

/// A controller owns a separate in-memory workspace; it never replaces the local host's file.
struct MacMirrorView: View {
    @ObservedObject var source: CloudAccount
    @StateObject private var workspace = AppModel()
    @StateObject private var remote = RemoteController(
        account: CloudAccount(kind: "controller", secrets: KeychainSecretStore(service: "org.opengrokbot.mac.mirror-identity")),
        secrets: KeychainSecretStore(service: "org.opengrokbot.mac.mirror-selection"))
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var draft = ""
    @State private var sending = false
    @State private var follow = true
    @State private var creating = false
    @State private var name = ""
    @State private var purpose = ""
    @State private var editing: Bot?
    @State private var browser = false
    private var roster: [Bot] { workspace.visibleBots.filter { remote.isPinned($0) } + workspace.recentlyUsed(workspace.visibleBots.filter { !remote.isPinned($0) }) }
    private var bot: Bot? { workspace.workspace.bots.first { $0.id == selected } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("This computer") { dismiss() }
                Menu {
                    ForEach(remote.account.hosts) { host in
                        Button(host.name + (host.online ? " · online" : " · offline")) { selected = nil; draft = ""; remote.select(host) }
                    }
                } label: { Label(remote.hostName, systemImage: "server.rack") }
                Text(remote.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("New Bot") { creating = true }.disabled(!remote.online)
            }.padding()
            Divider()
            if !source.signedIn {
                VStack(spacing: 12) { Text("Sign in under Settings → Computer to view another computer."); Button("Close") { dismiss() } }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    List(roster, selection: $selected) { item in
                        HStack { MacBotAvatar(color: item.color, size: 32, appearance: item.appearance); Text(item.name); if remote.isPinned(item) { Image(systemName: "pin.fill").font(.caption) } }
                            .tag(item.id)
                            .contextMenu {
                                Button(remote.isPinned(item) ? "Unpin" : "Pin") { remote.setPinned(!remote.isPinned(item), bot: item) }
                                if item.isMain != true { Button("Delete Bot", role: .destructive) { Task { _ = await remote.command(RemoteCommand(action: "delete_bot", botID: item.id)) } } }
                            }
                    }.frame(width: 245)
                    Divider()
                    if let bot { conversation(bot) }
                    else {
                        VStack(spacing: 14) {
                            Text(remote.hasSnapshot ? "Choose a Bot" : remote.status).font(.title3)
                            if let device = remote.account.localDevice { Text("Controller fingerprint: " + device.fingerprint).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                            Text("Select your server above, then approve this computer on the server after comparing its fingerprint. Your phone can select the same server.").foregroundStyle(.secondary)
                        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(MacTheme.canvas)
        .task { remote.account.useAccount(from: source); remote.attach(workspace); remote.setActive(true) }
        .onDisappear { remote.setActive(false) }
        .onChange(of: selected) { old, _ in if let old { remote.drafts[old] = draft }; draft = selected.flatMap { remote.drafts[$0] } ?? ""; follow = true; if let id = selected { Task { _ = await remote.command(RemoteCommand(action: "touch_bot", botID: id)) } } }
        .onChange(of: remote.account.session?.user.id) { _, _ in selected = nil; draft = "" }
        .alert("Remote workspace", isPresented: Binding(get: { remote.error != nil }, set: { if !$0 { remote.error = nil } })) { Button("OK") { remote.error = nil } } message: { Text(remote.error ?? "") }
        .sheet(isPresented: $browser) { if let bot { CloudBrowserView(botID: bot.id, remote: remote).frame(width: 900, height: 700) } }
        .sheet(item: $editing) { bot in
            BotAvatarPicker(bot: bot, save: { appearance in await remote.command(RemoteCommand(action: "update_avatar", botID: bot.id, appearance: appearance)) }, close: { editing = nil }).frame(width: 450, height: 650)
        }
        .sheet(isPresented: $creating) {
            VStack(spacing: 16) {
                Text("Create Bot on \(remote.hostName)").font(.headline)
                TextField("Name", text: $name); TextField("Purpose", text: $purpose)
                Button("Create") { Task { if await remote.command(RemoteCommand(action: "create_bot", name: name, purpose: purpose, color: "purple")) { creating = false; name = ""; purpose = "" } } }.disabled(name.isEmpty || name.count > 200 || purpose.count > 2000)
                Button("Cancel") { creating = false }
            }.padding(24).frame(width: 420)
        }
    }
    private func conversation(_ bot: Bot) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { editing = bot } label: { MacBotAvatar(color: bot.color, size: 36, appearance: bot.appearance) }.buttonStyle(.plain).disabled(!remote.online)
                Text(bot.name).font(.headline)
                Button("Browser") { browser = true }.disabled(!remote.online)
                Menu("Provider") {
                    ForEach(remote.providers) { provider in
                        Button(provider.provider.name + " · default model") {
                            let configuration = BotAIConfiguration(providers: [BotAIProvider(provider: provider.provider, model: "")], activeProvider: provider.provider, replyMode: .one)
                            Task { _ = await remote.command(RemoteCommand(action: "configure_bot", botID: bot.id, configuration: configuration)) }
                        }
                    }
                }.disabled(!remote.online || remote.running.contains(bot.id))
                Spacer()
                Button(remote.isPinned(bot) ? "Unpin" : "Pin") { remote.setPinned(!remote.isPinned(bot), bot: bot) }
            }.padding()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(workspace.entries(for: bot)) { entry in MacMessageView(entry: entry).id(entry.id) }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(20).background(ChatScrollMonitor(onUserScroll: { follow = $0 }, onLayout: { if follow { proxy.scrollTo("latest", anchor: .bottom) } }))
                }
                .task(id: bot.id) { await Task.yield(); proxy.scrollTo("latest", anchor: .bottom) }
                .onChange(of: workspace.entries(for: bot).last) { _, _ in if follow { Task { @MainActor in await Task.yield(); proxy.scrollTo("latest", anchor: .bottom) } } }
            }
            ForEach(bot.schedules ?? []) { task in
                HStack { Text(task.name + " · " + (task.nextRun ?? "Incoming Bot message")).font(.caption); Spacer(); Button("Cancel task") { Task { _ = await remote.command(RemoteCommand(action: "cancel_task", botID: bot.id, taskID: task.id)) } }.disabled(!remote.online) }.padding(.horizontal)
            }
            HStack {
                TextField("Message \(bot.name)", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...6).onSubmit { send(bot) }
                Button("Send") { send(bot) }.disabled(!remote.online || sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if remote.running.contains(bot.id) { Button("Stop") { Task { _ = await remote.command(RemoteCommand(action: "stop", botID: bot.id)) } }.disabled(!remote.online) }
            }.padding()
            Text("Runs on \(remote.hostName)").font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
        }
    }
    private func send(_ bot: Bot) {
        guard !sending, remote.online else { return }; let text = draft; sending = true; follow = true
        Task { let accepted = await remote.send(text, bot: bot); if accepted, draft == text { draft = "" }; sending = false }
    }
}
