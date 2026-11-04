import EventKit
import Foundation

/// Watches this Mac for events that can start a Bot's routine: a new email in Mail, or a calendar event about to begin.
/// Nothing is read unless a routine asks for that trigger and the matching Apple service is switched on.
@MainActor
final class MacTriggers {
    private var mailSeen: Set<String> = []
    private var mailPrimed = false
    private var announced: Set<String> = []

    struct MailRecord: Equatable { let key: String; let sender: String; let subject: String }

    /// Parses the Mail reader's output ("date | sender | subject | snippet", records separated by ---).
    nonisolated static func mailRecords(_ text: String) -> [MailRecord] {
        text.split(separator: "\n").map(String.init).filter { $0 != "---" && $0.contains(" | ") }.map { line in
            let parts = line.components(separatedBy: " | ")
            return MailRecord(key: line, sender: parts.count > 1 ? parts[1] : "", subject: parts.count > 2 ? parts[2] : line)
        }
    }

    func poll(app: AppModel, apple: AppleConnections = .shared) async {
        let tasks = app.workspace.bots.flatMap { bot in (bot.schedules ?? []).filter { $0.enabled && $0.source != nil }.map { (bot.id, $0.source ?? "") } }
        guard !tasks.isEmpty else { return }
        let mailBots = Set(tasks.filter { $0.1 == "mail" }.map(\.0)), calendarBots = Set(tasks.filter { $0.1 == "calendar" }.map(\.0))
        if !mailBots.isEmpty, apple.canRead(.mail), let text = try? await AppleReaders.mail(query: "") {
            let records = Self.mailRecords(text)
            // The first look only records what is already there, so old mail never starts a routine.
            let fresh = mailPrimed ? records.filter { !mailSeen.contains($0.key) } : []
            mailSeen.formUnion(records.map(\.key)); mailPrimed = true
            for record in fresh.prefix(5) { for id in mailBots { app.triggerEvent("New email from \(record.sender): \(record.subject)", source: "mail", for: id) } }
        }
        if !calendarBots.isEmpty, apple.canRead(.calendar) {
            for item in AppleReaders.startingSoon(minutes: 10) where !announced.contains(item.id) {
                announced.insert(item.id)
                for id in calendarBots { app.triggerEvent("Event starting soon: \(item.text)", source: "calendar", for: id) }
            }
            if announced.count > 500 { announced = [] }
        }
    }
}


/// A Mac cannot be woken by an app without administrator rights, so the app builds the one command you can run yourself.
enum WakeCommand {
    /// `sudo pmset schedule wake …` for a few minutes before the next timed routine, or nil if none is coming.
    static func next(for schedules: [BotSchedule], now: Date = Date(), leadMinutes: Int = 3) -> (date: Date, command: String)? {
        let upcoming = schedules.filter(\.enabled).compactMap { $0.nextRun.flatMap(BotSchedule.date) }.filter { $0 > now.addingTimeInterval(Double(leadMinutes) * 60) }.min()
        guard let routine = upcoming else { return nil }
        let wake = routine.addingTimeInterval(-Double(leadMinutes) * 60)
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = "MM/dd/yyyy HH:mm:ss"
        return (wake, "sudo pmset schedule wake \"\(format.string(from: wake))\"")
    }
}
