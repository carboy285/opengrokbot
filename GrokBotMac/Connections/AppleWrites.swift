import Foundation
import EventKit
import Contacts

/// Changes to Calendar, Reminders, Contacts, Notes, Mail and Messages.
/// Nothing here asks the human anything: MacDeviceActions decides whether an approval is needed before calling these.
extension AppleReaders {
    // MARK: Calendar
    private static func events(named name: String, on day: Date?, store: EKEventStore) -> [EKEvent] {
        let calendar = Calendar.current
        let from = day.map { calendar.startOfDay(for: $0) } ?? Date().addingTimeInterval(-30 * 86_400)
        let to = day.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) } ?? Date().addingTimeInterval(365 * 86_400)
        let all = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil)).sorted { $0.startDate < $1.startDate }
        return AppleText.match(all.map { $0.title ?? "" }, name).map { all[$0] }
    }

    private static func describe(_ event: EKEvent) -> String {
        "“\(event.title ?? "Untitled")” on \(event.startDate.formatted(date: .abbreviated, time: .shortened))"
    }

    private static func oneEvent(_ name: String, on day: Date?, store: EKEventStore) throws -> EKEvent {
        let found = events(named: name, on: day, store: store)
        guard let first = found.first else { throw AppleError.message("No event matches “\(name)”. Check the title with apple_calendar first.") }
        guard found.count == 1 else {
            throw AppleError.message("\(found.count) events match “\(name)”: " + found.prefix(5).map(describe).joined(separator: "; ") + ". Add \"on\" with the date (for example 2026-11-12) to pick one.")
        }
        return first
    }

    static func previewEvent(name: String, on day: Date?) throws -> String { try describe(oneEvent(name, on: day, store: EKEventStore())) }

    static func editEvent(name: String, on day: Date?, newName: String?, start: Date?, end: Date?, notes: String?) throws -> String {
        let store = EKEventStore()
        let event = try oneEvent(name, on: day, store: store)
        if let newName, !newName.isEmpty { event.title = String(newName.prefix(300)) }
        if let start {
            let length = max(event.endDate.timeIntervalSince(event.startDate), 60)
            event.startDate = start
            if let end, end > start { event.endDate = end } else { event.endDate = start.addingTimeInterval(length) }
        } else if let end, end > event.startDate { event.endDate = end }
        if let notes, !notes.isEmpty { event.notes = String(notes.prefix(1000)) }
        try store.save(event, span: .thisEvent, commit: true)
        return "Updated event: \(describe(event))."
    }

    static func deleteEvent(name: String, on day: Date?) throws -> String {
        let store = EKEventStore()
        let event = try oneEvent(name, on: day, store: store)
        let text = describe(event)
        try store.remove(event, span: .thisEvent, commit: true)
        return "Deleted event \(text)."
    }

    // MARK: Reminders
    /// The Reminders list with this name (created if it does not exist yet), or the default list when no name is given.
    static func reminderList(named name: String?, in store: EKEventStore) throws -> EKCalendar {
        let wanted = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if wanted.isEmpty {
            guard let list = store.defaultCalendarForNewReminders() else { throw AppleError.message("There is no default Reminders list to add to.") }
            return list
        }
        let lists = store.calendars(for: .reminder)
        if let found = lists.first(where: { $0.title.caseInsensitiveCompare(wanted) == .orderedSame }) { return found }
        guard wanted.count <= 100, let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw AppleError.message("The Reminders list “\(wanted)” does not exist and could not be created.")
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = wanted; list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }

    static func reminderLists() -> String {
        let names = EKEventStore().calendars(for: .reminder).map(\.title).sorted()
        return names.isEmpty ? "No Reminders lists." : names.map { "- " + $0 }.joined(separator: "\n")
    }

    enum ReminderChange: Sendable {
        case complete, delete
        case edit(newName: String?, due: Date?, clearDue: Bool, notes: String?, listName: String?, tags: [String])
    }

    private static func reminderWork(_ body: @escaping @Sendable (EKEventStore, [EKReminder]) -> String) async -> String {
        let box = ReminderStoreBox()
        let predicate = box.store.predicateForReminders(in: nil)
        let result: String = await withCheckedContinuation { continuation in
            box.store.fetchReminders(matching: predicate) { all in continuation.resume(returning: body(box.store, all ?? [])) }
        }
        withExtendedLifetime(box) {}
        return result
    }

    /// Applies a change to the one open reminder whose title matches. With `dryRun`, only reports "FOUND\t<title>" or why not.
    static func changeReminder(name: String, _ change: ReminderChange, dryRun: Bool = false) async -> String {
        await reminderWork { store, all in
            let pending = all.filter { !$0.isCompleted }
            let hits = AppleText.match(pending.map { $0.title ?? "" }, name).map { pending[$0] }
            guard let reminder = hits.first else { return "The reminder could not be changed: no open reminder matches “\(name)”. Check the title with apple_reminders first." }
            guard hits.count == 1 else { return "The reminder could not be changed: \(hits.count) open reminders match “\(name)”: " + hits.prefix(5).map { "“\($0.title ?? "Untitled")”" }.joined(separator: ", ") + ". Use the full title." }
            let title = reminder.title ?? "Untitled"
            if dryRun { return "FOUND\t" + title }
            do {
                switch change {
                case .complete:
                    reminder.isCompleted = true
                    try store.save(reminder, commit: true)
                    return "Marked reminder “\(title)” as done."
                case .delete:
                    try store.remove(reminder, commit: true)
                    return "Deleted reminder “\(title)”."
                case .edit(let newName, let due, let clearDue, let notes, let listName, let tags):
                    if let newName, !newName.isEmpty { reminder.title = String(newName.prefix(300)) }
                    if clearDue { reminder.dueDateComponents = nil }
                    else if let due { reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due) }
                    if let notes { reminder.notes = String(notes.prefix(1000)) }
                    if !tags.isEmpty { reminder.notes = AppleText.addingHashtags(tags, to: reminder.notes) }
                    if let listName, !listName.isEmpty { reminder.calendar = try reminderList(named: listName, in: store) }
                    try store.save(reminder, commit: true)
                    return "Updated reminder “\(reminder.title ?? title)”."
                }
            } catch { return "The reminder could not be changed: " + error.localizedDescription }
        }
    }

    // MARK: Contacts
    static func addContact(name: String, phone: String?, email: String?) throws -> String {
        let parts = AppleText.splitName(name)
        guard !parts.given.isEmpty else { throw AppleError.message("A contact needs a name.") }
        let contact = CNMutableContact()
        contact.givenName = parts.given; contact.familyName = parts.family
        if let phone, !phone.isEmpty { contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))] }
        if let email, !email.isEmpty { contact.emailAddresses = [CNLabeledValue(label: CNLabelOther, value: email as NSString)] }
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try CNContactStore().execute(request)
        return "Added contact “\(name)”."
    }

    static func editContact(name: String, newName: String?, phone: String?, email: String?) throws -> String {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor]
        let found = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
        guard let first = found.first else { throw AppleError.message("No contact matches “\(name)”.") }
        guard found.count == 1 else { throw AppleError.message("\(found.count) contacts match “\(name)”. Use the full name.") }
        guard let contact = first.mutableCopy() as? CNMutableContact else { throw AppleError.message("That contact cannot be edited.") }
        if let newName, !newName.isEmpty { let parts = AppleText.splitName(newName); contact.givenName = parts.given; contact.familyName = parts.family }
        if let phone, !phone.isEmpty { contact.phoneNumbers.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))) }
        if let email, !email.isEmpty, !contact.emailAddresses.contains(where: { String($0.value).lowercased() == email.lowercased() }) {
            contact.emailAddresses.append(CNLabeledValue(label: CNLabelOther, value: email as NSString))
        }
        let request = CNSaveRequest()
        request.update(contact)
        try store.execute(request)
        return "Updated contact “\(name)”."
    }

    /// A phone number or email for a name or an address, for sending a message. Fails when a name is unknown or ambiguous.
    static func recipient(_ text: String) throws -> (handle: String, label: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let handle = AppleText.address(trimmed) { return (handle, handle) }
        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor]
        let found: [CNContact]
        do { found = try CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(matchingName: trimmed), keysToFetch: keys) }
        catch { throw AppleError.message("To message “\(trimmed)” by name, turn on and allow Contacts, or give a phone number or email.") }
        guard let first = found.first else { throw AppleError.message("No contact matches “\(trimmed)”. Give a phone number or email address.") }
        guard found.count == 1 else { throw AppleError.message("\(found.count) contacts match “\(trimmed)”. Use the full name, a phone number or an email address.") }
        guard let handle = first.phoneNumbers.first.flatMap({ AppleText.address($0.value.stringValue) }) ?? first.emailAddresses.first.map({ String($0.value) }) else {
            throw AppleError.message("“\(trimmed)” has no phone number or email saved.")
        }
        return (handle, "\([first.givenName, first.familyName].filter { !$0.isEmpty }.joined(separator: " ")) (\(handle))")
    }

    // MARK: AppleScript (every value is passed as an argument, never spliced into the script)
    private static let stripHandler = """
    on strip(s)
      if (length of s) > 2 then return text 3 thru -1 of s
      return ""
    end strip
    """

    static func run(_ body: String, _ args: [String]) async throws -> String {
        let source = stripHandler + "\n" + body
        let prefixed = args.map { "q:" + $0 } // The prefix keeps a leading "-" from being read as an option.
        let result = await Task.detached { CLIInstallationScanner.capture(path: "/usr/bin/osascript", arguments: ["-e", source] + prefixed, timeout: 40, limit: 16_000) }.value
        guard result.exit == 0 else { throw AppleError.message("The app did not answer. Make sure OpenGrokBot is allowed to control it in System Settings → Privacy & Security → Automation, and that the app is set up.") }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Notes
    private static let notesBody = """
    on run argv
      set t to my strip(item 1 of argv)
      set h to my strip(item 2 of argv)
      set mode to my strip(item 3 of argv)
      tell application "Notes"
        if mode is "add" then
          make new note with properties {body:h}
          return "OK"
        end if
        set hits to notes whose name is t
        if (count of hits) is 0 then set hits to notes whose name contains t
        if (count of hits) is 0 then return "NOTFOUND"
        if (count of hits) > 1 then return "AMBIGUOUS"
        set n to item 1 of hits
        if mode is "peek" then return name of n
        if mode is "delete" then
          delete n
        else if mode is "append" then
          set body of n to (body of n) & h
        else if mode is "replace" then
          set body of n to h
        end if
        return name of n
      end tell
    end run
    """

    /// mode: add, append, replace, delete or peek.
    static func note(title: String, text: String, mode: String) async throws -> String {
        let html = mode == "add" || mode == "replace" ? AppleText.noteHTML(title: title, body: text) : AppleText.noteHTML(title: nil, body: text)
        let answer = try await run(notesBody, [title, html, mode])
        switch answer {
        case "NOTFOUND": throw AppleError.message("No note is titled “\(title)”. Check the title with apple_notes first.")
        case "AMBIGUOUS": throw AppleError.message("More than one note matches “\(title)”. Use the exact title.")
        default: break
        }
        switch mode {
        case "add": return "Created note “\(title)”."
        case "append": return "Added to note “\(answer)”."
        case "replace": return "Rewrote note “\(answer)”."
        case "delete": return "Moved note “\(answer)” to Recently Deleted."
        default: return answer
        }
    }

    // MARK: Mail
    private static let mailSendBody = """
    on run argv
      set toList to my strip(item 1 of argv)
      set s to my strip(item 2 of argv)
      set b to my strip(item 3 of argv)
      set mode to my strip(item 4 of argv)
      set AppleScript's text item delimiters to "|"
      set addrs to text items of toList
      set AppleScript's text item delimiters to ""
      tell application "Mail"
        set m to make new outgoing message with properties {subject:s, content:b, visible:(mode is "draft")}
        tell m
          repeat with a in addrs
            make new to recipient at end of to recipients with properties {address:(a as text)}
          end repeat
        end tell
        if mode is "send" then send m
        if mode is "draft" then activate
      end tell
      return "OK"
    end run
    """

    private static let mailActBody = """
    on run argv
      set q to my strip(item 1 of argv)
      set mode to my strip(item 2 of argv)
      set b to my strip(item 3 of argv)
      tell application "Mail"
        set msgs to messages of inbox
        set n to count of msgs
        if n > 150 then set n to 150
        set target to missing value
        repeat with i from 1 to n
          set m to item i of msgs
          set s to ""
          set f to ""
          try
            set s to subject of m
            set f to sender of m
          end try
          if s contains q or f contains q then
            set target to m
            exit repeat
          end if
        end repeat
        if target is missing value then return "NOTFOUND"
        set info to (sender of target) & " | " & (subject of target)
        if mode is "read" then
          set read status of target to true
        else if mode is "unread" then
          set read status of target to false
        else if mode is "flag" then
          set flagged status of target to true
        else if mode is "unflag" then
          set flagged status of target to false
        else if mode is "trash" then
          delete target
        else if mode starts with "reply" then
          set r to reply target opening window (mode is "reply_draft")
          set content of r to b & return & return & (content of r)
          if mode is "reply_send" then send r
          if mode is "reply_draft" then activate
        end if
        return info
      end tell
    end run
    """

    /// mode: send or draft.
    static func composeEmail(to: [String], subject: String, body: String, mode: String) async throws -> String {
        _ = try await run(mailSendBody, [to.joined(separator: "|"), subject, body, mode])
        return mode == "send" ? "Sent the email “\(subject)” to \(to.joined(separator: ", "))." : "Opened a draft email “\(subject)” in Mail for the human to review."
    }

    /// mode: peek, read, unread, flag, unflag, trash, reply_send or reply_draft. Acts on the newest inbox message whose sender or subject contains the text.
    static func mailMessage(matching query: String, mode: String, body: String = "") async throws -> String {
        let answer = try await run(mailActBody, [query, mode, body])
        if answer == "NOTFOUND" { throw AppleError.message("No recent inbox message matches “\(query)”. Check with apple_mail first.") }
        return answer
    }

    // MARK: Mail search (any mailbox, a date window, unread only, attachment names)
    private static let mailSearchBody = """
    on run argv
      set q to my strip(item 1 of argv)
      set dayCount to (my strip(item 2 of argv)) as integer
      set scopeName to my strip(item 3 of argv)
      set onlyUnread to ((my strip(item 4 of argv)) is "1")
      if dayCount < 1 then set dayCount to 365
      set cutoff to (current date) - (dayCount * days)
      set out to ""
      set hits to 0
      tell application "Mail"
        set boxes to {}
        if scopeName is "all" then
          repeat with acct in accounts
            try
              set boxes to boxes & (mailboxes of acct)
            end try
          end repeat
        else
          set boxes to {inbox}
        end if
        repeat with b in boxes
          set boxName to ""
          try
            set boxName to name of b
          end try
          if boxName does not contain "Junk" and boxName does not contain "Spam" and boxName does not contain "Trash" and boxName does not contain "Deleted" then
            set msgs to {}
            try
              set msgs to messages of b
            end try
            set scanCount to count of msgs
            if scanCount > 200 then set scanCount to 200
            repeat with i from 1 to scanCount
              set m to item i of msgs
              set s to ""
              set f to ""
              set stamp to missing value
              set isRead to true
              try
                set s to subject of m
                set f to sender of m
                set stamp to date received of m
                set isRead to read status of m
              end try
              if stamp is not missing value and stamp >= cutoff and (q is "" or s contains q or f contains q) and ((not onlyUnread) or (not isRead)) then
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
                set att to ""
                try
                  repeat with a in mail attachments of m
                    set att to att & (name of a) & ", "
                  end repeat
                end try
                if att is not "" then set att to " [attachments: " & att & "]"
                set out to out & (stamp as string) & " | " & f & " | " & s & att & " | " & snippet & linefeed & "---" & linefeed
                if hits >= 20 then exit repeat
              end if
            end repeat
          end if
          if hits >= 20 then exit repeat
        end repeat
      end tell
      return out
    end run
    """

    static func mailSearch(query: String, days: Int, allMailboxes: Bool, unreadOnly: Bool) async throws -> String {
        let text = String(query.filter { !$0.isNewline }.prefix(100))
        let answer = try await run(mailSearchBody, [text, String(min(max(days, 0), 3650)), allMailboxes ? "all" : "inbox", unreadOnly ? "1" : "0"])
        let collapsed = AppleText.collapse(answer)
        return collapsed.isEmpty ? "No matching messages\(allMailboxes ? "" : " in the most recent part of the inbox (try \"scope\":\"all\" to search every mailbox)")." : collapsed
    }

    // MARK: Messages
    private static let messagesBody = """
    on run argv
      set h to my strip(item 1 of argv)
      set t to my strip(item 2 of argv)
      tell application "Messages"
        try
          set svc to 1st service whose service type = iMessage
          try
            set target to buddy h of svc
          on error
            set target to participant h of svc
          end try
          send t to target
        on error
          set svc to 1st service whose service type = SMS
          set target to buddy h of svc
          send t to target
        end try
      end tell
      return "OK"
    end run
    """

    static func sendMessage(handle: String, text: String) async throws -> String {
        _ = try await run(messagesBody, [handle, text])
        return "Sent the message to \(handle)."
    }
}

/// EventKit objects are not Sendable; one store is created and used only inside its own fetch callback.
private final class ReminderStoreBox: @unchecked Sendable { let store = EKEventStore() }

extension AppleText {
    /// Reminders has no public tag API, so tags are kept as #hashtags in the reminder's notes.
    static func hashtags(_ tags: [String]) -> String {
        tags.compactMap { tag -> String? in
            let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")).split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }).joined(separator: "-")
            return clean.isEmpty ? nil : "#" + String(clean.prefix(40))
        }.prefix(10).joined(separator: " ")
    }

    static func addingHashtags(_ tags: [String], to notes: String?) -> String {
        let existing = notes ?? ""
        let fresh = hashtags(tags).split(separator: " ").map(String.init).filter { !existing.localizedCaseInsensitiveContains($0) }
        guard !fresh.isEmpty else { return existing }
        return existing.isEmpty ? fresh.joined(separator: " ") : existing + "\n" + fresh.joined(separator: " ")
    }

    /// Indexes of titles that equal the wanted text (ignoring case), or, when none do, that contain it.
    static func match(_ titles: [String], _ wanted: String) -> [Int] {
        let wanted = wanted.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return [] }
        let lowered = titles.map { $0.lowercased() }
        let exact = lowered.indices.filter { lowered[$0] == wanted }
        return exact.isEmpty ? lowered.indices.filter { lowered[$0].contains(wanted) } : exact
    }

    static func splitName(_ name: String) -> (given: String, family: String) {
        let words = name.split(separator: " ").map(String.init)
        guard let last = words.last, words.count > 1 else { return (words.first ?? "", "") }
        return (words.dropLast().joined(separator: " "), last)
    }

    /// An email address, or a phone number reduced to digits and a leading plus. Nil for anything else.
    static func address(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        if parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasSuffix("."), !trimmed.contains(where: { $0.isWhitespace || $0 == "|" || $0 == "," || $0 == "<" || $0 == ">" || $0 == "\"" }) { return trimmed }
        let digits = trimmed.filter(\.isNumber)
        let allowed = trimmed.allSatisfy { $0.isNumber || " +-().".contains($0) }
        guard allowed, (7...15).contains(digits.count) else { return nil }
        return (trimmed.hasPrefix("+") ? "+" : "") + digits
    }

    /// Notes stores HTML. Plain text is escaped and each line becomes a paragraph; a title becomes the first heading.
    static func noteHTML(title: String?, body: String) -> String {
        func escape(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { "<div>" + ($0.isEmpty ? "<br>" : escape(String($0))) + "</div>" }
        return (title.map { "<div><h1>\(escape($0))</h1></div>" } ?? "") + lines.joined()
    }
}
