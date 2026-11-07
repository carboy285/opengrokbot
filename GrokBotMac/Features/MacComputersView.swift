import SwiftUI

/// Computers on this account: see one in the main window, copy a Bot to another, or copy everything (Bots, keys, connectors) in one click.
/// This is its own screen, not a menu, so it stays still while the app refreshes in the background.
struct MacComputersView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @AppStorage(SettingsBundle.shareKey) private var share = false
    @State private var hosts: [CloudDevice] = []
    @State private var destination: String = ""          // "mac" or a host ID
    @State private var oneBot: UUID?
    @State private var copyBots = true
    @State private var copyKeys = true
    @State private var copyConnectors = true

    private var shownName: String { desktop.gateway?.hostName ?? "This computer" }
    /// Where the computer on screen can be copied to: this Mac when viewing another computer, and every other computer except the one on screen.
    private var destinations: [(id: String, name: String, host: CloudDevice?)] {
        var list: [(String, String, CloudDevice?)] = []
        if desktop.gateway != nil { list.append(("mac", "This Mac", nil)) }
        for host in hosts where host.name != desktop.gateway?.hostName { list.append((host.id.uuidString, host.name + (host.online ? "" : " · offline"), host)) }
        return list
    }
    private var chosen: (id: String, name: String, host: CloudDevice?)? { destinations.first { $0.id == destination } ?? destinations.first }
    private var bots: [Bot] { app.workspace.bots.filter { $0.memberIDs == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Computers").font(.system(size: 25, weight: .medium))
                Spacer()
                Button { desktop.panel = nil } label: { Image(systemName: "xmark").frame(width: 38, height: 38) }.buttonStyle(.plain).accessibilityLabel("Close Computers")
            }
            if !desktop.remote.account.signedIn {
                Text("Sign in under Settings → Computer to use your other computers.").foregroundStyle(MacTheme.secondary)
                MacPillButton(title: "Open Settings", prominent: true) { desktop.openSettings(.computer) }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        viewSection
                        if chosen == nil {
                            card { Text("No other computers found yet. Open OpenGrokBot on them, sign in with this account and turn on phone access.").font(.system(size: 14)).foregroundStyle(MacTheme.secondary) }
                        } else {
                            destinationSection
                            everythingSection
                            oneBotSection
                        }
                        shareSection
                    }.frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(34)
        .task {
            oneBot = desktop.copyingBot
            while !Task.isCancelled {
                hosts = desktop.computers()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(MacTheme.raised, in: RoundedRectangle(cornerRadius: 16))
    }

    private var viewSection: some View {
        card {
            Text("Look at a computer").font(.system(size: 17, weight: .medium))
            Text("It opens in this window exactly like this Mac’s own Bots. Everything you do runs on that computer.").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
            HStack(spacing: 10) {
                MacPillButton(title: "This computer", prominent: desktop.gateway == nil) { desktop.openComputer(nil, app: desktop.localApp ?? app); desktop.panel = nil }
                ForEach(hosts) { host in
                    MacPillButton(title: host.name + (host.online ? "" : " · offline"), prominent: desktop.gateway?.hostName == host.name) {
                        desktop.openComputer(host, app: desktop.localApp ?? app); desktop.panel = nil
                    }
                }
            }
            Text("Showing: \(shownName)").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
        }
    }

    private var destinationSection: some View {
        card {
            Text("Copy from \(shownName) to").font(.system(size: 17, weight: .medium))
            Picker("Destination", selection: Binding(get: { chosen?.id ?? "" }, set: { destination = $0 })) {
                ForEach(destinations, id: \.id) { Text($0.name).tag($0.id) }
            }.labelsHidden().pickerStyle(.segmented)
            Text("A copy never removes anything from \(shownName).").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
        }
    }

    private var everythingSection: some View {
        card {
            Text("Copy everything").font(.system(size: 17, weight: .medium))
            Toggle("All Bots: job, provider, memory, chat history, Knowledge files, paused routines", isOn: $copyBots).toggleStyle(.checkbox)
            Toggle("API keys: AI providers (Codex, Claude Code, Grok, Gemini) and voice", isOn: $copyKeys).toggleStyle(.checkbox)
            Toggle("Connectors: your Composio project and its apps", isOn: $copyConnectors).toggleStyle(.checkbox)
            Text("Keys and connectors travel only inside your encrypted account link, and only when “Share keys and connectors” is on at both computers. Secure logins and passwords are never copied.")
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(MacTheme.secondary)
            HStack {
                MacPillButton(title: desktop.copying ? "Copying…" : "Copy everything to \(chosen?.name ?? "…")", prominent: true) {
                    guard let target = chosen else { return }
                    desktop.copyEverything(shown: app, to: target.host, bots: copyBots, keys: copyKeys, connectors: copyConnectors)
                }.disabled(desktop.copying || (!copyBots && !copyKeys && !copyConnectors))
                if desktop.copying { ProgressView().controlSize(.small) }
            }
            if let notice = desktop.copyNotice { Text(notice).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private var oneBotSection: some View {
        card {
            Text("Copy just one Bot").font(.system(size: 17, weight: .medium))
            Picker("Bot", selection: Binding(get: { oneBot ?? bots.first?.id }, set: { oneBot = $0 })) {
                ForEach(bots) { Text($0.name).tag(Optional($0.id)) }
            }.labelsHidden()
            MacPillButton(title: "Copy this Bot to \(chosen?.name ?? "…")") {
                guard let target = chosen, let bot = bots.first(where: { $0.id == (oneBot ?? bots.first?.id) }) else { return }
                desktop.copyBot(bot, shown: app, to: target.host)
            }.disabled(desktop.copying || bots.isEmpty)
        }
    }

    private var shareSection: some View {
        card {
            Toggle("Share keys and connectors with my other computers", isOn: $share).toggleStyle(.switch)
            Text("Off by default. Turn it on here, and on the computer you copy to or from, before keys and connectors can move. Bots can be copied without it.")
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(MacTheme.secondary)
        }
    }
}
