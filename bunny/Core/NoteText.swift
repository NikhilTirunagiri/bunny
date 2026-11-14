import Foundation

/// Pure text rules for notes: splitting what was typed into the New note field, search, the links in
/// details, and the note side's "Created" line.
enum NoteText {
    /// Longer single-line text than this is split at its first sentence end, when it has one in range.
    static let titleLimit = 120

    /// Title and details for text typed or pasted into the New note field. More than one line: the
    /// first line is the title, the rest the details. One line longer than `titleLimit` with a
    /// sentence end (". ", "? ", "! ") inside the first `titleLimit` characters: split after that
    /// sentence. Otherwise the whole text is the title.
    static func split(_ text: String) -> (title: String, details: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newline = text.firstIndex(where: \.isNewline) {
            return (text[..<newline].trimmingCharacters(in: .whitespaces),
                    text[newline...].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard text.count > titleLimit else { return (text, "") }
        let head = text.prefix(titleLimit)
        let ends = [". ", "? ", "! "].compactMap { head.range(of: $0)?.lowerBound }
        guard let end = ends.min() else { return (text, "") }
        let cut = text.index(after: end)
        return (String(text[..<cut]), text[cut...].trimmingCharacters(in: .whitespaces))
    }

    /// Case- and diacritic-insensitive substring match over a note's title and details. A blank query
    /// matches nothing.
    static func matches(query: String, title: String, details: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return title.range(of: query, options: options) != nil || details.range(of: query, options: options) != nil
    }

    /// Web and mail links in details, with their UTF-16 ranges (what a text view works in).
    static func links(in text: String) -> [(range: NSRange, url: URL)] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).compactMap { match in
            guard let url = match.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return (match.range, url)
        }
    }

    /// A press on a link that is released within this distance opens it; moved further, it is a
    /// drag that selects text.
    static let linkClickSlop: CGFloat = 3

    static func isLinkClick(from down: CGPoint, to point: CGPoint) -> Bool {
        abs(point.x - down.x) <= linkClickSlop && abs(point.y - down.y) <= linkClickSlop
    }

    /// "Created today", "Created yesterday", "Created Nov 3", "Created Oct 9, 2025".
    static func createdLabel(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Created today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Created yesterday"
        }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) { style = style.year() }
        return "Created \(date.formatted(style))"
    }
}
