import Foundation

/// Reads Gmail and Google Calendar for heads-ups through the user's Composio project, the same way the Windows app does.
/// Nothing here touches the Mail or Calendar apps on this Mac, so they never open. Everything is read-only: the only
/// two tools heads-ups may run are listed in `allowed`.
enum ComposioHeadsUpSource {
    static let mailTool = "GMAIL_FETCH_EMAILS"
    static let calendarTool = "GOOGLECALENDAR_EVENTS_LIST"
    static let allowed: Set<String> = [mailTool, calendarTool]

    /// Unread mail from people's inboxes, newest first. Promotions, social and forum mail are left out.
    static func mailArguments() -> [String: Any] {
        ["query": "in:inbox is:unread newer_than:2d -category:promotions -category:social -category:forums", "max_results": 25, "include_payload": false]
    }

    /// Events from an hour ago through the next 24 hours, with repeating events already expanded.
    static func calendarArguments(now: Date) -> [String: Any] {
        let stamp = ISO8601DateFormatter()
        return ["calendarId": "primary", "timeMin": stamp.string(from: now.addingTimeInterval(-3600)), "timeMax": stamp.string(from: now.addingTimeInterval(86_400)),
                "singleEvents": true, "orderBy": "startTime", "maxResults": 50]
    }

    // MARK: Reading Composio's answers

    private static func text(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        return ""
    }

    private static func clean(_ value: Any?) -> String {
        text(value).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Composio wraps provider answers differently from tool to tool, so the list is found wherever it sits.
    static func findArray(_ data: Any?, keys: [String], depth: Int = 0) -> [Any]? {
        if let array = data as? [Any] { return array }
        guard depth <= 3, let object = data as? [String: Any] else { return nil }
        for key in keys { if let array = object[key] as? [Any] { return array } }
        for value in object.values where value is [String: Any] {
            if let found = findArray(value, keys: keys, depth: depth + 1) { return found }
        }
        return nil
    }

    /// An ISO date-time, a date alone (all-day events, local midnight) or a Unix time in seconds or milliseconds.
    static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return epoch(number.doubleValue) }
        let string = text(value).trimmingCharacters(in: .whitespaces)
        guard !string.isEmpty else { return nil }
        if string.count >= 10, string.allSatisfy(\.isNumber), let number = Double(string) { return epoch(number) }
        let full = ISO8601DateFormatter()
        if let found = full.date(from: string) { return found }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let found = fractional.date(from: string) { return found }
        let day = ISO8601DateFormatter(); day.formatOptions = [.withFullDate]; day.timeZone = .current
        return day.date(from: string)
    }

    private static func epoch(_ number: Double) -> Date { Date(timeIntervalSince1970: number < 1e12 ? number : number / 1000) }

    /// Gmail messages as heads-ups need them. The key is Gmail's own message ID, so it never changes.
    static func mail(from data: Any?) -> [HeadsUpMail] {
        (findArray(data, keys: ["messages", "emails"]) ?? []).compactMap { raw in
            guard let message = raw as? [String: Any] else { return nil }
            let headers = ((message["payload"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? []
            func header(_ name: String) -> String { clean(headers.first { text($0["name"]).lowercased() == name }?["value"]) }
            let id = clean(message["messageId"] ?? message["id"])
            guard !id.isEmpty else { return nil }
            let preview = message["preview"] as? [String: Any]
            let sender = clean(message["sender"] ?? message["from"] ?? header("from"))
            let subject = clean(message["subject"] ?? preview?["subject"] ?? header("subject"))
            let snippet = clean(preview?["body"] ?? message["snippet"] ?? message["messageText"])
            return HeadsUpMail(key: id, sender: String(sender.prefix(200)), subject: String(subject.isEmpty ? "(no subject)" : subject.prefix(300)), snippet: String(snippet.prefix(600)))
        }
    }

    /// Google Calendar events as heads-ups need them. Cancelled events and ones with no start are dropped.
    static func events(from data: Any?) -> [HeadsUpEvent] {
        (findArray(data, keys: ["items", "events"]) ?? []).compactMap { raw in
            guard let event = raw as? [String: Any], text(event["status"]) != "cancelled" else { return nil }
            let start = event["start"] as? [String: Any], end = event["end"] as? [String: Any]
            let startText = start?["dateTime"] ?? start?["date"], endText = end?["dateTime"] ?? end?["date"]
            let id = clean(event["id"])
            guard !id.isEmpty, let begin = date(startText) else { return nil }
            let attendees = (event["attendees"] as? [[String: Any]]) ?? []
            let mine = attendees.first { ($0["self"] as? Bool) == true }
            let entryPoints = ((event["conferenceData"] as? [String: Any])?["entryPoints"] as? [[String: Any]]) ?? []
            let video = entryPoints.first { text($0["entryPointType"]) == "video" }.map { text($0["uri"]) }
            let place = String(clean(event["location"]).prefix(300))
            let placeLink = place.range(of: "https://[^ ]+", options: .regularExpression).map { String(place[$0]) }
            let link = [text(event["hangoutLink"]), video ?? "", placeLink ?? ""].first { $0.hasPrefix("https://") }
            let title = clean(event["summary"])
            return HeadsUpEvent(id: id, title: String((title.isEmpty ? "(untitled event)" : title).prefix(300)), start: begin, end: date(endText) ?? begin,
                                allDay: start?["dateTime"] == nil, declined: text(mine?["responseStatus"]) == "declined", link: link)
        }
    }

    /// Timed events that start within `minutes`, for routines that wait for "a calendar event about to begin".
    static func startingSoon(_ events: [HeadsUpEvent], minutes: Int, now: Date) -> [HeadsUpEvent] {
        events.filter { event in
            let until = event.start.timeIntervalSince(now)
            return !event.allDay && !event.declined && until <= Double(minutes) * 60 && until > -60
        }
    }
}
