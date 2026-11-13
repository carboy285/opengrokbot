import AppKit
import EventKit
import Foundation
import UserNotifications

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


// MARK: Heads-ups (0.9.6)
// Grok Bot reaches out first: new mail from people, a meeting about to start, two events that overlap, and a short
// morning brief. It reads Mail and Calendar on this Mac through the connections switched on in Connect apps → This Mac.

/// One calendar event, as heads-ups need it.
struct HeadsUpEvent: Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let declined: Bool
    let link: String?
}

/// Heads-up settings. The keys are shared with the Settings page's @AppStorage values.
enum HeadsUpSettings {
    static let enabledKey = "headsUps.enabled", emailKey = "headsUps.email", meetingsKey = "headsUps.meetings", leadKey = "headsUps.lead"
    static let conflictsKey = "headsUps.conflicts", briefKey = "headsUps.brief", briefMinutesKey = "headsUps.briefMinutes"
    static let quietKey = "headsUps.quiet", quietStartKey = "headsUps.quietStart", quietEndKey = "headsUps.quietEnd", lastBriefKey = "headsUps.lastBrief"
    private static func flag(_ key: String, _ fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }
    private static func number(_ key: String, _ fallback: Int) -> Int { UserDefaults.standard.object(forKey: key) as? Int ?? fallback }
    static var enabled: Bool { flag(enabledKey, false) }
    static var email: Bool { flag(emailKey, true) }
    static var meetings: Bool { flag(meetingsKey, true) }
    static var lead: Int { number(leadKey, 10) }
    static var conflicts: Bool { flag(conflictsKey, true) }
    static var brief: Bool { flag(briefKey, true) }
    static var briefMinutes: Int { number(briefMinutesKey, 8 * 60) }
    static var quiet: Bool { flag(quietKey, true) }
    static var quietStart: Int { number(quietStartKey, 22 * 60) }
    static var quietEnd: Int { number(quietEndKey, 7 * 60) }
}

/// The decisions behind heads-ups, kept free of system calls so they are easy to check.
enum HeadsUpRules {
    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
    /// Quiet hours may wrap past midnight (22:00–07:00).
    static func inQuietHours(_ date: Date, on: Bool, start: Int, end: Int, calendar: Calendar = .current) -> Bool {
        guard on, start != end else { return false }
        let now = minuteOfDay(date, calendar: calendar)
        return start < end ? (now >= start && now < end) : (now >= start || now < end)
    }
    /// A moved meeting gets a new key, so it is reminded again.
    static func key(_ event: HeadsUpEvent) -> String { event.id + "@" + String(Int(event.start.timeIntervalSince1970)) }
    static func dueReminders(_ events: [HeadsUpEvent], lead: Int, now: Date, reminded: Set<String>) -> [HeadsUpEvent] {
        events.filter { event in
            guard !event.allDay, !event.declined, !reminded.contains(key(event)) else { return false }
            let until = event.start.timeIntervalSince(now)
            return until <= Double(lead) * 60 && until > -60
        }
    }
    /// Pairs of timed events that overlap. Back-to-back events do not.
    static func overlaps(_ events: [HeadsUpEvent], now: Date, known: Set<String>) -> [(key: String, first: HeadsUpEvent, second: HeadsUpEvent)] {
        let timed = events.filter { !$0.allDay && !$0.declined && $0.end > now }.sorted { $0.start < $1.start }
        var found: [(key: String, first: HeadsUpEvent, second: HeadsUpEvent)] = []
        for i in timed.indices {
            for j in timed.indices where j > i {
                let first = timed[i], second = timed[j]
                if second.start >= first.end { break }
                let pair = [key(first), key(second)].sorted().joined(separator: "&")
                if !known.contains(pair) { found.append((key: pair, first: first, second: second)) }
            }
        }
        return found
    }
    /// Once a day, at or after the chosen time, within four hours of it.
    static func briefDue(now: Date, at minutes: Int, lastBrief: String, calendar: Calendar = .current) -> Bool {
        let current = minuteOfDay(now, calendar: calendar)
        return lastBrief != dayKey(now, calendar: calendar) && current >= minutes && current < minutes + 240
    }
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    /// Mail from automated senders stays quiet; mail from people is worth a heads-up.
    static func isFromPerson(_ sender: String) -> Bool {
        let value = sender.lowercased()
        let automated = ["noreply", "no-reply", "donotreply", "do-not-reply", "newsletter", "notification", "mailer-daemon", "marketing", "digest", "promo", "news@", "updates@"]
        return !value.isEmpty && !automated.contains { value.contains($0) }
    }
    static func senderName(_ sender: String) -> String {
        if let open = sender.firstIndex(of: "<") {
            let name = sender[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if !name.isEmpty { return name }
        }
        return sender.trimmingCharacters(in: .whitespaces)
    }
    /// "date | sender | subject | snippet" lines from the Mail reader. Only the first few carry a snippet, so the key
    /// leaves it out: a message keeps the same key as newer mail pushes it down the list.
    static func mailItems(_ text: String) -> [(key: String, sender: String, subject: String)] {
        text.split(separator: "\n").map(String.init).filter { $0 != "---" && $0.contains(" | ") }.map { line in
            let parts = line.components(separatedBy: " | ")
            return (key: parts.prefix(3).joined(separator: " | "), sender: parts.count > 1 ? parts[1] : "", subject: parts.count > 2 ? parts[2] : line)
        }
    }
    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    static func reminderText(_ event: HeadsUpEvent, now: Date) -> String {
        let minutes = max(0, Int((event.start.timeIntervalSince(now) / 60).rounded()))
        let when = minutes == 0 ? "is starting now" : "starts in \(minutes) min"
        return "\(event.title) \(when) (\(time(event.start)))." + (event.link.map { "\nJoin: \($0)" } ?? "")
    }
    static func conflictText(_ first: HeadsUpEvent, _ second: HeadsUpEvent) -> String {
        "\(first.title) (\(time(first.start))–\(time(first.end))) overlaps with \(second.title) (\(time(second.start))–\(time(second.end))). Want help picking one, or a note to move the other?"
    }
    static func emailText(_ items: [(key: String, sender: String, subject: String)]) -> String {
        var lines = items.prefix(6).map { "• \(senderName($0.sender)): \($0.subject)" }
        if items.count > 6 { lines.append("• …and \(items.count - 6) more") }
        let count = items.count == 1 ? "New email from a person" : "\(items.count) new emails from people"
        return "\(count):\n" + lines.joined(separator: "\n") + "\nWant me to read any of them or draft a reply?"
    }
    static func briefText(_ events: [HeadsUpEvent], overlaps: Int) -> String {
        let today = events.filter { !$0.declined }.sorted { $0.start < $1.start }
        guard !today.isEmpty else { return "Good morning. Your calendar is clear today." }
        var text = "Good morning. Here’s today:\n" + today.prefix(10).map { "• \($0.allDay ? "All day" : time($0.start)): \($0.title)" }.joined(separator: "\n")
        if overlaps > 0 { text += "\nHeads-up: \(overlaps == 1 ? "two events overlap" : "\(overlaps) pairs of events overlap") today." }
        return text
    }
}

extension AppleReaders {
    /// Calendar events from an hour ago through the next few hours, for heads-ups.
    static func headsUpEvents(hours: Int) -> [HeadsUpEvent] {
        let store = EKEventStore()
        let now = Date(), end = now.addingTimeInterval(Double(min(max(hours, 1), 48)) * 3600)
        return store.events(matching: store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: end, calendars: nil)).map { event in
            let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
            let place = event.location ?? ""
            let placeLink = place.range(of: "https://[^ ]+", options: .regularExpression).map { String(place[$0]) }
            let eventLink = event.url.flatMap { $0.scheme == "https" ? $0.absoluteString : nil }
            let start: Date = event.startDate ?? now
            let finish: Date = event.endDate ?? start
            return HeadsUpEvent(id: event.eventIdentifier ?? (event.title ?? "event"), title: event.title ?? "Untitled", start: start, end: finish,
                                allDay: event.isAllDay, declined: declined, link: eventLink ?? placeLink)
        }
    }
}

/// Shows a heads-up as a Mac notification (when the app is in the background) and on your phone if phone alerts are on.
enum HeadsUpNotifier {
    @MainActor static func send(title: String, body: String, silent: Bool, urgent: Bool) {
        let flat = String(body.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(200))
        if MacPush.enabled, !silent {
            let text = MacPush.includeText ? flat : "Open OpenGrokBot to read it."
            Task { _ = await MacPush.send(title: title, body: text, urgent: urgent) }
        }
        guard !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = flat
        if !silent { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }
}

/// Watches Mail and Calendar on this Mac and posts heads-ups into the main Bot's chat.
@MainActor
final class MacHeadsUps {
    private var mailSeen: Set<String> = []
    private var mailPrimed = false
    private var reminded: Set<String> = []
    private var knownOverlaps: Set<String> = []

    func poll(app: AppModel, apple: AppleConnections = .shared, now: Date = Date()) async {
        guard HeadsUpSettings.enabled, let bot = app.workspace.bots.first(where: { $0.isMain == true }) else { return }
        let quiet = HeadsUpRules.inQuietHours(now, on: HeadsUpSettings.quiet, start: HeadsUpSettings.quietStart, end: HeadsUpSettings.quietEnd)
        if apple.canRead(.calendar), HeadsUpSettings.meetings || HeadsUpSettings.conflicts || HeadsUpSettings.brief {
            let events = AppleReaders.headsUpEvents(hours: 24)
            if HeadsUpSettings.meetings {
                for event in HeadsUpRules.dueReminders(events, lead: HeadsUpSettings.lead, now: now, reminded: reminded) {
                    reminded.insert(HeadsUpRules.key(event))
                    post(HeadsUpRules.reminderText(event, now: now), kind: "meeting", title: event.title, bot: bot, app: app, quiet: quiet, urgent: true)
                }
                if reminded.count > 500 { reminded = [] }
            }
            if HeadsUpSettings.conflicts {
                for overlap in HeadsUpRules.overlaps(events, now: now, known: knownOverlaps) {
                    knownOverlaps.insert(overlap.key)
                    post(HeadsUpRules.conflictText(overlap.first, overlap.second), kind: "conflict", title: "Calendar overlap", bot: bot, app: app, quiet: quiet)
                }
                if knownOverlaps.count > 500 { knownOverlaps = [] }
            }
            let lastBrief = UserDefaults.standard.string(forKey: HeadsUpSettings.lastBriefKey) ?? ""
            if HeadsUpSettings.brief, HeadsUpRules.briefDue(now: now, at: HeadsUpSettings.briefMinutes, lastBrief: lastBrief) {
                UserDefaults.standard.set(HeadsUpRules.dayKey(now), forKey: HeadsUpSettings.lastBriefKey)
                let today = events.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
                let overlapsToday = HeadsUpRules.overlaps(today, now: now, known: []).count
                post(HeadsUpRules.briefText(today, overlaps: overlapsToday), kind: "brief", title: "Morning brief", bot: bot, app: app, quiet: false)
            }
        }
        if HeadsUpSettings.email, apple.canRead(.mail), let text = try? await AppleReaders.mail(query: "") {
            let items = HeadsUpRules.mailItems(text)
            // The first look only records what is already in the inbox, so turning heads-ups on never floods the chat.
            let fresh = mailPrimed ? items.filter { !mailSeen.contains($0.key) } : []
            mailSeen.formUnion(items.map(\.key)); mailPrimed = true
            if mailSeen.count > 2000 { mailSeen = Set(items.map(\.key)) }
            let people = fresh.filter { HeadsUpRules.isFromPerson($0.sender) }
            if !people.isEmpty {
                let title = people.count == 1 ? HeadsUpRules.senderName(people[0].sender) : "\(people.count) new emails"
                post(HeadsUpRules.emailText(people), kind: "email", title: title, bot: bot, app: app, quiet: quiet)
            }
        }
    }

    private func post(_ text: String, kind: String, title: String, bot: Bot, app: AppModel, quiet: Bool, urgent: Bool = false) {
        guard app.postHeadsUp(text, kind: kind, title: title, to: bot.id) else { return }
        HeadsUpNotifier.send(title: title, body: text, silent: quiet, urgent: urgent)
    }
}
