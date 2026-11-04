import AppKit
import Contacts
import EventKit
import Foundation
import SQLite3

/// Apple apps on this Mac that a Bot can look at, once the human turns each one on.
enum AppleService: String, CaseIterable, Identifiable, Sendable {
    case calendar, reminders, contacts, mail, notes, messages
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        case .mail: "Mail"
        case .notes: "Notes"
        case .messages: "Messages"
        }
    }
    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .contacts: "person.crop.circle.fill"
        case .mail: "envelope.fill"
        case .notes: "note.text"
        case .messages: "message.fill"
        }
    }
    var summary: String {
        switch self {
        case .calendar: "Upcoming events from every calendar on this Mac. A Bot can also add events, after you approve each one."
        case .reminders: "Your open reminders. A Bot can also add reminders, after you approve each one."
        case .contacts: "Look up names, phone numbers and email addresses."
        case .mail: "Search recent messages in your Mail inbox by sender or subject. Read-only."
        case .notes: "Search your Notes by title or text. Read-only."
        case .messages: "Search recent iMessages and texts. Read-only. Needs Full Disk Access."
        }
    }
    var action: String { "apple_" + rawValue }
}

enum AppleAccess: Equatable, Sendable {
    case granted, notDetermined, denied, needsFullDiskAccess, unavailable
    var label: String {
        switch self {
        case .granted: "Allowed"
        case .notDetermined: "Not allowed yet"
        case .denied: "Blocked in System Settings"
        case .needsFullDiskAccess: "Needs Full Disk Access"
        case .unavailable: "Not available on this Mac"
        }
    }
}

enum AppleError: LocalizedError {
    case message(String), needsFullDiskAccess, timedOut
    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .needsFullDiskAccess: "Full Disk Access is not granted to OpenGrokBot. Allow it in System Settings → Privacy & Security → Full Disk Access, then quit and reopen the app."
        case .timedOut: "The request took too long. Try a more specific search."
        }
    }
}

/// Which Apple apps are switched on, and what macOS currently allows. Nothing is read until the human enables a service.
@MainActor
final class AppleConnections: ObservableObject {
    static let shared = AppleConnections()
    @Published private(set) var enabled: Set<AppleService>
    @Published private(set) var access: [AppleService: AppleAccess] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = Set(AppleService.allCases.filter { defaults.bool(forKey: Self.key($0)) })
        refreshAccess()
    }

    private static func key(_ service: AppleService) -> String { "appleConnection." + service.rawValue }

    func isEnabled(_ service: AppleService) -> Bool { enabled.contains(service) }

    func setEnabled(_ service: AppleService, _ on: Bool) {
        if on { enabled.insert(service) } else { enabled.remove(service) }
        defaults.set(on, forKey: Self.key(service))
        if on, access[service] != .granted { Task { await requestAccess(service) } }
    }

    func refreshAccess() { for service in AppleService.allCases { access[service] = Self.currentAccess(service) ?? access[service] ?? .notDetermined } }

    /// Synchronous status where macOS can report it. Mail and Notes are only learned by trying (Automation prompts on first use).
    nonisolated static func currentAccess(_ service: AppleService) -> AppleAccess? {
        switch service {
        case .calendar: return map(EKEventStore.authorizationStatus(for: .event))
        case .reminders: return map(EKEventStore.authorizationStatus(for: .reminder))
        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .messages:
            let path = AppleReaders.messagesPath
            let descriptor = open(path, O_RDONLY)
            if descriptor >= 0 { close(descriptor); return .granted }
            return errno == ENOENT ? .unavailable : .needsFullDiskAccess
        case .mail, .notes: return nil
        }
    }

    private nonisolated static func map(_ status: EKAuthorizationStatus) -> AppleAccess {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess(_ service: AppleService) async {
        switch service {
        case .calendar: _ = await AppleReaders.requestEvents()
        case .reminders: _ = await AppleReaders.requestReminders()
        case .contacts: _ = await AppleReaders.requestContacts()
        case .mail: access[.mail] = await AppleReaders.probeAutomation(app: "Mail") ? .granted : .denied
        case .notes: access[.notes] = await AppleReaders.probeAutomation(app: "Notes") ? .granted : .denied
        case .messages:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
        }
        refreshAccess()
    }

    /// True if a Bot may read this service right now.
    func canRead(_ service: AppleService) -> Bool {
        guard isEnabled(service) else { return false }
        switch service {
        case .mail, .notes, .messages: return true // Attempted; macOS asks or reports the exact problem.
        default: return Self.currentAccess(service) == .granted
        }
    }
}

/// Reads and writes. Each call builds its own system store so nothing non-Sendable crosses isolation.
enum AppleReaders {
    static var messagesPath: String { NSHomeDirectory() + "/Library/Messages/chat.db" }

    // MARK: Permissions
    static func requestEvents() async -> Bool { (try? await EKEventStore().requestFullAccessToEvents()) ?? false }
    static func requestReminders() async -> Bool { (try? await EKEventStore().requestFullAccessToReminders()) ?? false }
    static func requestContacts() async -> Bool { (try? await CNContactStore().requestAccess(for: .contacts)) ?? false }
    static func probeAutomation(app: String) async -> Bool {
        await Task.detached { CLIInstallationScanner.capture(path: "/usr/bin/osascript", arguments: ["-e", "tell application \"\(app)\" to count of accounts"], timeout: 30).exit == 0 }.value
    }

    // MARK: Calendar
    static func calendar(days: Int) -> String {
        let store = EKEventStore()
        let span = min(max(days, 1), 30)
        let start = Date(), end = Calendar.current.date(byAdding: .day, value: span, to: start) ?? start.addingTimeInterval(Double(span) * 86_400)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
        guard !events.isEmpty else { return "No events in the next \(span) days." }
        let day = DateFormatter(); day.dateFormat = "EEE MMM d"
        let time = DateFormatter(); time.dateFormat = "HH:mm"
        return events.prefix(60).map { event in
            let when = event.isAllDay ? "\(day.string(from: event.startDate)) all day" : "\(day.string(from: event.startDate)) \(time.string(from: event.startDate))–\(time.string(from: event.endDate))"
            var line = "- \(when): \(event.title ?? "Untitled")"
            if let place = event.location, !place.isEmpty { line += " @ \(place)" }
            if let name = event.calendar?.title { line += " [\(name)]" }
            return line
        }.joined(separator: "\n")
    }

    /// Timed events that begin within the next few minutes (used to trigger routines).
    static func startingSoon(minutes: Int) -> [(id: String, text: String)] {
        let store = EKEventStore()
        let now = Date(), end = now.addingTimeInterval(Double(min(max(minutes, 1), 120)) * 60)
        let time = DateFormatter(); time.dateFormat = "HH:mm"
        return store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: nil)).filter { !$0.isAllDay }.map { event in
            (id: (event.eventIdentifier ?? event.title ?? "") + "@" + String(Int(event.startDate.timeIntervalSince1970)), text: "\(event.title ?? "Untitled") at \(time.string(from: event.startDate))")
        }
    }

    static func addEvent(title: String, start: Date, end: Date?, notes: String?) throws -> String {
        let store = EKEventStore()
        guard let calendar = store.defaultCalendarForNewEvents else { throw AppleError.message("There is no default calendar to add the event to.") }
        let event = EKEvent(eventStore: store)
        event.title = title; event.calendar = calendar; event.startDate = start
        event.endDate = (end ?? start.addingTimeInterval(3600)) > start ? (end ?? start.addingTimeInterval(3600)) : start.addingTimeInterval(3600)
        if let notes, !notes.isEmpty { event.notes = notes }
        try store.save(event, span: .thisEvent, commit: true)
        return "Added event “\(title)” to \(calendar.title)."
    }

    // MARK: Reminders
    static func reminders() async -> String {
        let store = EKEventStore()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let lines: [String] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let format = DateFormatter(); format.dateFormat = "EEE MMM d HH:mm"
                let rows = (reminders ?? []).prefix(60).map { reminder -> String in
                    var line = "- " + (reminder.title ?? "Untitled")
                    if let components = reminder.dueDateComponents, let due = Calendar.current.date(from: components) { line += " (due \(format.string(from: due)))" }
                    if let list = reminder.calendar?.title { line += " [\(list)]" }
                    return line
                }
                continuation.resume(returning: Array(rows))
            }
        }
        withExtendedLifetime(store) {} // The store must outlive its asynchronous fetch.
        return lines.isEmpty ? "No open reminders." : lines.joined(separator: "\n")
    }

    static func addReminder(title: String, due: Date?) throws -> String {
        let store = EKEventStore()
        guard let list = store.defaultCalendarForNewReminders() else { throw AppleError.message("There is no default Reminders list to add to.") }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title; reminder.calendar = list
        if let due { reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due) }
        try store.save(reminder, commit: true)
        return "Added reminder “\(title)” to \(list.title)."
    }

    // MARK: Contacts
    static func contacts(query: String) throws -> String {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AppleError.message("Contacts needs a name to search for.") }
        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactOrganizationNameKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor]
        let found = try CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
        guard !found.isEmpty else { return "No contacts match “\(name)”." }
        return found.prefix(10).map { contact in
            var parts = [([contact.givenName, contact.familyName].filter { !$0.isEmpty }).joined(separator: " ")]
            if !contact.organizationName.isEmpty { parts.append(contact.organizationName) }
            parts += contact.phoneNumbers.prefix(3).map { $0.value.stringValue }
            parts += contact.emailAddresses.prefix(3).map { String($0.value) }
            return "- " + parts.joined(separator: " · ")
        }.joined(separator: "\n")
    }

    // MARK: Mail and Notes (AppleScript through osascript; the search text is passed as an argument, never spliced into the script)
    private static let mailScript = """
    on run argv
      set raw to item 1 of argv
      set q to ""
      if (length of raw) > 2 then set q to text 3 thru -1 of raw
      set out to ""
      set hits to 0
      tell application "Mail"
        set inboxMessages to messages of inbox
        set scanCount to count of inboxMessages
        if scanCount > 150 then set scanCount to 150
        repeat with i from 1 to scanCount
          set m to item i of inboxMessages
          set s to ""
          set f to ""
          try
            set s to subject of m
            set f to sender of m
          end try
          if q is "" or s contains q or f contains q then
            set hits to hits + 1
            set snippet to ""
            if hits <= 5 then
              try
                set theContent to content of m
                if (length of theContent) > 300 then
                  set snippet to text 1 thru 300 of theContent
                else
                  set snippet to theContent
                end if
              end try
            end if
            set stamp to ""
            try
              set stamp to (date received of m) as string
            end try
            set out to out & stamp & " | " & f & " | " & s & " | " & snippet & linefeed & "---" & linefeed
            if hits >= 15 then exit repeat
          end if
        end repeat
      end tell
      return out
    end run
    """

    private static let notesScript = """
    on run argv
      set raw to item 1 of argv
      set q to ""
      if (length of raw) > 2 then set q to text 3 thru -1 of raw
      set out to ""
      set hits to 0
      tell application "Notes"
        set allNotes to notes
        set scanCount to count of allNotes
        if scanCount > 200 then set scanCount to 200
        repeat with i from 1 to scanCount
          set n to item i of allNotes
          set t to ""
          set b to ""
          try
            set t to name of n
            set b to plaintext of n
          end try
          if q is "" or t contains q or b contains q then
            set hits to hits + 1
            if (length of b) > 400 then set b to text 1 thru 400 of b
            set out to out & t & " | " & b & linefeed & "---" & linefeed
            if hits >= 10 then exit repeat
          end if
        end repeat
      end tell
      return out
    end run
    """

    static func mail(query: String) async throws -> String { try await script(mailScript, query: query, empty: "No matching messages in the most recent part of the inbox.") }
    static func notes(query: String) async throws -> String { try await script(notesScript, query: query, empty: "No matching notes.") }

    private static func script(_ source: String, query: String, empty: String) async throws -> String {
        let argument = "q:" + String(query.filter { !$0.isNewline }.prefix(100)) // The prefix keeps a leading "-" from being read as an option.
        let result = await Task.detached { CLIInstallationScanner.capture(path: "/usr/bin/osascript", arguments: ["-e", source, argument], timeout: 25, limit: 64_000) }.value
        guard result.exit == 0 else { throw AppleError.message("The app did not answer. Make sure OpenGrokBot is allowed to control it in System Settings → Privacy & Security → Automation, and that the app is set up.") }
        let text = AppleText.collapse(result.text)
        return text.isEmpty ? empty : text
    }

    // MARK: Messages (the local Messages database; needs Full Disk Access)
    static func messages(query: String, limit: Int = 25) throws -> String {
        var database: OpaquePointer?
        guard sqlite3_open_v2(messagesPath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(database); throw AppleError.needsFullDiskAccess }
        defer { sqlite3_close(database) }
        let sql = "SELECT m.date, m.is_from_me, COALESCE(h.id, ''), m.text, m.attributedBody FROM message m LEFT JOIN handle h ON m.handle_id = h.ROWID WHERE m.text IS NOT NULL OR m.attributedBody IS NOT NULL ORDER BY m.date DESC LIMIT 400"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { sqlite3_finalize(statement); throw AppleError.needsFullDiskAccess }
        defer { sqlite3_finalize(statement) }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let format = DateFormatter(); format.dateFormat = "MMM d HH:mm"
        var rows: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW, rows.count < limit {
            var body = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            if body.isEmpty, let bytes = sqlite3_column_blob(statement, 4) {
                body = AppleText.decodeAttributedBody(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 4)))) ?? ""
            }
            body = AppleText.collapse(body)
            let handle = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            guard !body.isEmpty, needle.isEmpty || body.lowercased().contains(needle) || handle.lowercased().contains(needle) else { continue }
            let stamp = format.string(from: AppleText.messageDate(sqlite3_column_int64(statement, 0)))
            let who = sqlite3_column_int(statement, 1) == 1 ? "me" : (handle.isEmpty ? "unknown" : handle)
            rows.append("\(stamp) \(who): \(String(body.prefix(300)))")
        }
        return rows.isEmpty ? "No matching recent messages." : rows.joined(separator: "\n")
    }
}

/// Pure helpers, unit-tested without any system access.
enum AppleText {
    static func clip(_ text: String, limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "\n[truncated]"
    }

    /// Collapses runs of whitespace inside each line so snippets stay compact; keeps line breaks between records.
    static func collapse(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.split(whereSeparator: { $0 == "\r" || $0 == "\t" || $0 == " " }).joined(separator: " ") }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Messages stores dates as nanoseconds (newer macOS) or seconds (older) since 2001-01-01.
    static func messageDate(_ raw: Int64) -> Date {
        Date(timeIntervalSinceReferenceDate: raw > 1_000_000_000_000 ? Double(raw) / 1_000_000_000 : Double(raw))
    }

    /// Best-effort text from a Messages `attributedBody` typedstream blob. Returns nil when the layout is not recognized.
    static func decodeAttributedBody(_ data: Data) -> String? {
        guard let marker = data.range(of: Data("NSString".utf8)) else { return nil }
        var index = marker.upperBound + 5
        guard index < data.endIndex else { return nil }
        var length = Int(data[index]); index += 1
        if length == 0x81 {
            guard index + 2 <= data.endIndex else { return nil }
            length = Int(data[index]) | Int(data[index + 1]) << 8; index += 2
        } else if length == 0x82 {
            guard index + 4 <= data.endIndex else { return nil }
            length = Int(data[index]) | Int(data[index + 1]) << 8 | Int(data[index + 2]) << 16 | Int(data[index + 3]) << 24; index += 4
        }
        guard length > 0, index + length <= data.endIndex else { return nil }
        return String(data: data[index..<(index + length)], encoding: .utf8)
    }

    /// Accepts ISO 8601 with or without a zone or fractional seconds; a missing zone means this Mac's time zone.
    static func parseDate(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let withZone = ISO8601DateFormatter()
        if let date = withZone.date(from: text) { return date }
        withZone.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withZone.date(from: text) { return date }
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let local = DateFormatter(); local.locale = Locale(identifier: "en_US_POSIX"); local.dateFormat = pattern
            if let date = local.date(from: text) { return date }
        }
        return nil
    }
}
