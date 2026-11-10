import AppKit
import SwiftUI

private enum BotInspectorTab: String, CaseIterable, Identifiable {
    case details = "Details", library = "Library", computer = "Computer"
    var id: String { rawValue }
}

/// A persistent companion to the conversation, rather than a modal over it.
struct MacBotInspectorView: View {
    let bot: Bot
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var desktop: MacAppModel
    @State private var tab = BotInspectorTab.details
    @State private var files: [URL] = []
    @State private var fileError: String?
    @State private var editingAvatar = false
    @State private var folderDraft = ""
    @State private var editingDetails = false
    @State private var nameDraft = ""
    @State private var purposeDraft = ""
    @State private var memoryDraft = ""
    @State private var creatingRoutine = false
    @State private var routineName = ""
    @State private var routineInstruction = ""
    @State private var routineDate = Date().addingTimeInterval(3600)
    @State private var routineRepeat = "none"
    @State private var routineTrigger = "time"
    @State private var routineContains = ""
    @State private var routineZone = TimeZone.current.identifier
    @State private var editingRoutine: BotSchedule?
    @State private var routineToDelete: BotSchedule?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                ShareLink(item: desktop.conversationText(for: bot, app: app)) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 19))
                        .frame(width: 42, height: 42).glassChrome(in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Share conversation").help("Share conversation")
                MacCircleButton(symbol: "xmark", label: "Close bot details") { desktop.showBotInspector = false }.keyboardShortcut(.cancelAction)
            }.padding(18)
            if editingAvatar {
                BotAvatarPicker(bot: bot, save: { appearance in app.setAppearance(appearance, for: bot) }, close: { editingAvatar = false })
                    .id(bot.id)
                Spacer(minLength: 0)
            } else { VStack(spacing: 0) {
                    Button { editingAvatar = true } label: {
                        MacBotAvatar(color: bot.color, size: 86, appearance: bot.appearance)
                    }.buttonStyle(.plain).help("Change Bot avatar").accessibilityLabel("Change Bot avatar").padding(.top, 14)
                    Text(bot.name).font(.system(size: 24, weight: .medium))
                        .multilineTextAlignment(.center).textSelection(.enabled)
                        .padding(.horizontal, 24).padding(.top, 30)
                    HStack(spacing: 4) {
                        ForEach(BotInspectorTab.allCases) { item in
                            Button { tab = item; if item == .library { refreshFiles() } } label: {
                                Text(item.rawValue).font(.system(size: 16))
                                    .foregroundStyle(tab == item ? Color.primary : MacTheme.secondary)
                                    .padding(.horizontal, 13).padding(.vertical, 9)
                                    .background(tab == item ? MacTheme.panel : .clear, in: Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("bot-inspector-tab-\(item.rawValue.lowercased())")
                                .accessibilityAddTraits(tab == item ? [.isSelected] : [])
                        }
                    }.padding(.top, 30).padding(.bottom, 46)
                    ScrollView {
                    VStack(spacing: 0) {
                    switch tab {
                    case .details: details
                    case .library: library
                    case .computer: computer
                    }
                }.frame(maxWidth: .infinity).padding(.bottom, 30)
                    }
            } }
        }
        .frame(maxHeight: .infinity).background(MacTheme.canvas)
        .confirmationDialog("Delete this routine?", isPresented: Binding(get: { routineToDelete != nil }, set: { if !$0 { routineToDelete = nil } }), presenting: routineToDelete) { task in
            Button("Delete \(task.name)", role: .destructive) { _ = app.removeSchedule(task.id, botID: bot.id); routineToDelete = nil }
        } message: { _ in Text("Future runs will be removed from this Bot.") }
        .onChange(of: desktop.runningBots) { _, running in if !running.contains(bot.id), tab == .library { refreshFiles() } }
        .onAppear { folderDraft = bot.folder ?? "" }
        .onChange(of: bot.id) { _, _ in editingAvatar = false; editingDetails = false; creatingRoutine = false; editingRoutine = nil; folderDraft = bot.folder ?? "" }
    }

    private var details: some View {
        VStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                Button((bot.isPinned ?? (bot.isMain == true)) ? "Unpin Bot" : "Pin to top") { desktop.remote.setPinned(bot, pinned: !(bot.isPinned ?? (bot.isMain == true))) }
                TextField("Folder · blank for Unfiled", text: $folderDraft).textFieldStyle(.roundedBorder)
                Button("Save folder") { _ = app.organize(bot, folder: folderDraft) }.disabled(folderDraft.count > 80)
                Text("Drag Bots in the sidebar to change their order.").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Button("Open local browser", systemImage: "globe") {
                    do { _ = try LocalBotBrowsers.shared.open(bot) } catch { app.errorMessage = error.localizedDescription }
                }
                Text("This Bot has its own local browser profile. Its window is visible on this computer.").font(.caption).foregroundStyle(.secondary)
                MacBotVMControls(bot: bot)
                Text("Scheduled tasks").font(.headline)
                Text("Ask this Bot to schedule a task at a time, repeat hourly/daily/weekly, or react to incoming Bot messages. This app must be running; missed times catch up once.").font(.caption).foregroundStyle(.secondary)
                Button("Create routine…") { editingRoutine = nil; routineName = ""; routineInstruction = ""; routineDate = Date().addingTimeInterval(3600); routineZone = TimeZone.current.identifier; routineRepeat = "none"; routineTrigger = "time"; routineContains = ""; creatingRoutine = true }
                if creatingRoutine {
                    TextField("Routine name", text: $routineName).textFieldStyle(.roundedBorder)
                    TextField("What should this Bot do?", text: $routineInstruction, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...5)
                    Picker("Trigger", selection: $routineTrigger) { Text("At a time").tag("time"); Text("Bot message received").tag("message") }
                    if routineTrigger == "time" {
                        TextField("IANA time zone, for example America/Chicago", text: $routineZone).textFieldStyle(.roundedBorder)
                        DatePicker("First run", selection: $routineDate, in: Date()...).environment(\.timeZone, TimeZone(identifier: routineZone) ?? .current)
                        Picker("Repeat", selection: $routineRepeat) {
                            Text("Once").tag("none"); Text("Hourly").tag("hourly"); Text("Daily").tag("daily"); Text("Weekly").tag("weekly")
                        }
                    } else {
                        TextField("Optional message text to match", text: $routineContains).textFieldStyle(.roundedBorder)
                        Text("Triggered by messages from other Bots. Existing messages do not trigger a newly configured routine.").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(editingRoutine == nil ? "Save routine" : "Save changes") {
                            saveRoutine()
                        }
                        Button("Cancel") { creatingRoutine = false }
                    }
                }
                ForEach(bot.schedules ?? []) { task in
                    Text(task.name)
                    Text("\(task.enabled ? (task.nextRun ?? "Incoming Bot message") : "Paused") · \(task.recurrence) · \(task.timezone)").font(.caption)
                    if let last = task.lastRun { Text("Last run: \(last) · \(task.lastResult ?? "outcome unavailable")").font(.caption).foregroundStyle(.secondary) }
                    if !(task.history ?? []).isEmpty {
                        DisclosureGroup("Run history") {
                            ForEach((task.history ?? []).reversed()) { run in Text("\(run.date) · \(run.status)").font(.caption).textSelection(.enabled) }
                        }
                    }
                    HStack {
                        Button("Run now") { desktop.runRoutineNow(task, for: bot, app: app) }.disabled(desktop.runningBots.contains(bot.id) || bot.memberIDs != nil)
                        Button("Edit") {
                            editingRoutine = task; routineName = task.name; routineInstruction = task.text; routineZone = task.timezone
                            routineDate = task.nextRun.flatMap(BotSchedule.date) ?? Date().addingTimeInterval(3600)
                            routineRepeat = task.recurrence; routineTrigger = task.eventBased ? "message" : "time"; routineContains = task.contains ?? ""; creatingRoutine = true
                        }.disabled(desktop.runningBots.contains(bot.id))
                        Button(task.enabled ? "Pause" : "Resume") {
                            var updated = task; updated.enabled.toggle(); _ = app.updateSchedule(updated, botID: bot.id)
                        }
                        Button("Delete", role: .destructive) { routineToDelete = task }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                if editingDetails {
                    TextField("Bot name", text: $nameDraft).textFieldStyle(.roundedBorder)
                    TextField("Purpose", text: $purposeDraft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...6)
                    Text("Saved private memory · one item per line").font(.caption)
                    TextEditor(text: $memoryDraft).frame(minHeight: 100).border(Color.secondary.opacity(0.3))
                    HStack {
                        Button("Save details") {
                            let items = memoryDraft.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                            if app.updateDetails(bot, name: nameDraft, purpose: purposeDraft, memory: items) { editingDetails = false }
                        }
                        Button("Cancel") { editingDetails = false }
                    }
                } else {
                    Button("Edit name, purpose and memory") { nameDraft = bot.name; purposeDraft = bot.purpose; memoryDraft = (bot.memory ?? []).joined(separator: "\n"); editingDetails = true }
                    Text("Saved memory is separate from chat history. Editing it does not erase messages.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let members = bot.memberIDs {
                Text("Group members").font(.headline)
                ForEach(app.workspace.bots.filter { members.contains($0.id) }) { member in
                    Button(member.name) { desktop.selectedID = member.id }
                }
                Text("Each member answers with its own selected provider and model.").font(.caption).foregroundStyle(MacTheme.secondary)
            } else { MacBotProviderSettingsView(bot: bot) }
            if !(bot.memory ?? []).isEmpty {
                Text("This Bot’s memory").font(.headline)
                ForEach(bot.memory ?? [], id: \.self) { Text($0).font(.system(size: 13)).textSelection(.enabled) }
            }
            if !(app.workspace.sharedMemory ?? []).isEmpty {
                Text("Shared memory").font(.headline)
                ForEach(app.workspace.sharedMemory ?? [], id: \.self) { Text($0).font(.system(size: 13)).textSelection(.enabled) }
            }
            if bot.isMain != true, !bot.purpose.isEmpty {
                Text(bot.purpose).font(.system(size: 16)).textSelection(.enabled)
            }
            if (bot.schedules ?? []).isEmpty {
                Text("This Bot has no scheduled routines.").font(.system(size: 17)).foregroundStyle(MacTheme.secondary)
            }
        }.multilineTextAlignment(.center).padding(.horizontal, 34).padding(.top, 7)
    }

    private var library: some View {
        VStack(spacing: 18) {
            if files.isEmpty {
                Image(systemName: "sparkles.rectangle.stack").font(.system(size: 30, weight: .light)).foregroundStyle(MacTheme.secondary)
                Text("No files yet").font(.system(size: 18, weight: .medium))
                Text("Files & image thumbnails from this Bot's working folder appear here. Drag images or PDFs onto the chat.").font(.system(size: 14)).foregroundStyle(MacTheme.secondary).multilineTextAlignment(.center)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(files, id: \.path) { file in
                        Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: {
                            VStack(spacing: 8) {
                                if let data = try? Data(contentsOf: file), let nsImg = NSImage(data: data) {
                                    Image(nsImage: nsImg).resizable().scaledToFill().frame(height: 84).clipped().clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                } else {
                                    ZStack { RoundedRectangle(cornerRadius: 10).fill(MacTheme.panel); Image(systemName: file.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc.text").font(.system(size: 22)).foregroundStyle(MacTheme.secondary) }.frame(height: 84)
                                }
                                Text(file.lastPathComponent).font(.system(size: 12)).lineLimit(1).multilineTextAlignment(.center)
                            }.padding(10).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).help("Show \(file.lastPathComponent) in Finder")
                    }
                }
            }
            if let fileError { Text(fileError).font(.caption).foregroundStyle(MacTheme.secondary) }
            HStack {
                Button("Refresh") { refreshFiles() }
                Button("Open folder") { desktop.openWorkingDirectory(for: bot) }
            }.controlSize(.small).padding(.top, 6)
        }.padding(.horizontal, 20)
    }

    private var computer: some View {
        VStack(spacing: 22) {
            // 9.2 Header — unified Computer like real Grokbot
            VStack(spacing: 6) {
                Image(systemName: "desktopcomputer").font(.system(size: 34, weight: .light)).foregroundStyle(MacTheme.secondary)
                Text("Computer · on this Mac").font(.system(size: 18, weight: .medium))
                Text("Browser, files & terminal — per-Bot, visible locally").font(.system(size: 12)).foregroundStyle(MacTheme.secondary).multilineTextAlignment(.center)
            }
            if let provider = desktop.providersToRun(for: bot).first {
                HStack(spacing: 8) { Image(systemName: "terminal.fill").foregroundStyle(MacTheme.secondary); Text(provider.cli.provider.name).font(.system(size: 14, weight: .medium)); Text(provider.choice.model.isEmpty ? "default model" : provider.choice.model).font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
                Text(desktop.runningBots.contains(bot.id) ? "● Working…" : (desktop.providerHealth[provider.cli.provider] ?? "Installed · authentication not yet verified")).font(.system(size: 12)).foregroundStyle(desktop.runningBots.contains(bot.id) ? Color.green : MacTheme.secondary)
            } else {
                Label("Choose an AI CLI to start chatting.", systemImage: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(.orange)
            }
            // Files quick preview with thumbnails
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Files").font(.headline); Spacer(); Button("Open folder") { desktop.openWorkingDirectory(for: bot) }.font(.caption) }
                if files.isEmpty {
                    Text("No files yet — drops appear here with thumbnails.").font(.caption).foregroundStyle(MacTheme.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(files.prefix(6), id: \.path) { file in
                                VStack(spacing: 6) {
                                    if let data = try? Data(contentsOf: file), let ns = NSImage(data: data) {
                                        Image(nsImage: ns).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                    } else {
                                        ZStack { RoundedRectangle(cornerRadius: 8).fill(MacTheme.panel); Image(systemName: "doc.text").foregroundStyle(MacTheme.secondary) }.frame(width: 64, height: 64)
                                    }
                                    Text(file.lastPathComponent).font(.caption2).lineLimit(1).frame(width: 64)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button("Refresh") { refreshFiles() }.controlSize(.small)
                    Button("Open browser") { do { _ = try LocalBotBrowsers.shared.open(bot) } catch { app.errorMessage = error.localizedDescription } }.controlSize(.small)
                }
            }.padding(12).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            // Browser pane preview
            VStack(alignment: .leading, spacing: 8) {
                HStack { Label("Browser", systemImage: "globe").font(.headline); Spacer(); Text("isolated per Bot").font(.caption2).foregroundStyle(MacTheme.secondary) }
                Text("Each Bot has its own cookie jar. Sign in once in the visible window; Bots reuse it via browse_web.").font(.caption).foregroundStyle(.secondary)
                Button { do { _ = try LocalBotBrowsers.shared.open(bot) } catch { app.errorMessage = error.localizedDescription } } label: { Label("Open local browser", systemImage: "arrow.up.forward.app") }.buttonStyle(.bordered).controlSize(.small)
                // Live preview handled via remote snapshots every ~3s when enabled
                Text("Preview available to Mac/iPhone viewers when signed in.").font(.caption2).foregroundStyle(.secondary).padding(8).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }.padding(12).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            // VM pane
            VStack(alignment: .leading, spacing: 8) {
                HStack { Label("Linux VM", systemImage: "server.rack").font(.headline); Spacer() }
                if MacBotVMs.shared.assigned(bot.id) != nil {
                    Label("VM assigned — open console on this Mac", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    Button("Open VM console") { Task { await MacBotVMs.shared.open(bot) } }.controlSize(.small)
                } else {
                    Text("No VM for this Bot. Set up in Bot details → Linux VM.").font(.caption).foregroundStyle(MacTheme.secondary)
                }
            }.padding(12).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            if desktop.runningBots.contains(bot.id) { Button("Stop response") { desktop.stop(botID: bot.id) }.buttonStyle(.borderedProminent).tint(.red) }
            Button("AI CLI setup") { desktop.panel = .setup }.font(.caption)
            DisclosureGroup("Recent recorded activity") {
                let events = app.entries(for: bot).filter { $0.kind == .activity }.suffix(5)
                if events.isEmpty { Text("No recorded activity yet.").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(events)) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                        Text(event.text).font(.caption).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Tool calls are audited here. Remote viewers see browser/VM previews every ~3s.").font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 20)
    }

    private func saveRoutine() {
        let name = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = routineInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let zone = routineTrigger == "time" ? routineZone.trimmingCharacters(in: .whitespacesAndNewlines) : TimeZone.current.identifier
        guard !name.isEmpty, name.count <= 200, !instruction.isEmpty, instruction.count <= 8000,
              TimeZone(identifier: zone) != nil, routineContains.count <= 200,
              routineTrigger != "time" || routineDate > Date() else { app.errorMessage = "Enter a name, instruction, valid time zone and future run time."; return }
        let next = routineTrigger == "time" ? ISO8601DateFormatter().string(from: routineDate) : nil
        var task = editingRoutine ?? BotSchedule(name: name, text: instruction, recurrence: "none", timezone: zone)
        let triggerChanged = task.nextRun != next || task.contains != (routineTrigger == "message" ? routineContains : nil)
        task.name = name; task.text = instruction; task.nextRun = next; task.recurrence = routineTrigger == "time" ? routineRepeat : "none"; task.timezone = zone
        task.contains = routineTrigger == "message" ? routineContains : nil
        if triggerChanged {
            task.occurrence = UUID()
            if routineTrigger == "message" { task.lastEvent = app.entries(for: bot).last(where: { $0.kind == .activity && $0.senderBotID != nil })?.id }
        }
        let saved = editingRoutine == nil ? app.createSchedule(task, botID: bot.id) : app.updateSchedule(task, botID: bot.id)
        if saved { creatingRoutine = false; editingRoutine = nil; routineName = ""; routineInstruction = "" }
    }

    private func refreshFiles() {
        let directory = desktop.workingDirectory(for: bot)
        guard FileManager.default.fileExists(atPath: directory.path) else { files = []; fileError = nil; return }
        do {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
            let rootFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            let folder = directory.appendingPathComponent("Attachments", isDirectory: true)
            let attachmentFiles = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
            files = (rootFiles + attachmentFiles).filter { url in
                guard let info = try? url.resourceValues(forKeys: keys) else { return false }
                return info.isRegularFile == true && info.isSymbolicLink != true
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            fileError = nil
        } catch { files = []; fileError = "The files could not be read. Try opening the folder in Finder." }
    }
}
