import Foundation
import Testing
@testable import BunnyCore

struct NoteTextTests {
    // MARK: - Split

    @Test func shortSingleLineIsAllTitle() {
        let split = NoteText.split("  Buy milk. Then eggs.  ")
        #expect(split.title == "Buy milk. Then eggs.")
        #expect(split.details == "")
    }

    @Test func firstLineIsTheTitleAndTheRestIsDetails() {
        let split = NoteText.split("Call the bank \n\nAsk about the fee.\nAnd the card.\n")
        #expect(split.title == "Call the bank")
        #expect(split.details == "Ask about the fee.\nAnd the card.")
    }

    @Test func windowsLineEndingsSplitToo() {
        let split = NoteText.split("Title\r\nBody")
        #expect(split.title == "Title")
        #expect(split.details == "Body")
    }

    @Test func longLineSplitsAfterItsFirstSentence() {
        let rest = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces)
        for mark in [".", "?", "!"] {
            let split = NoteText.split("Fix the login bug\(mark) Second sentence. \(rest)")
            #expect(split.title == "Fix the login bug\(mark)")
            #expect(split.details == "Second sentence. \(rest)")
        }
    }

    @Test func longLineWithoutASentenceEndInRangeStaysWhole() {
        let long = String(repeating: "a", count: 130) + ". tail"
        #expect(NoteText.split(long).title == long)
        #expect(NoteText.split(long).details == "")
    }

    @Test func exactlyAtTheLimitIsNotSplit() {
        let text = "One. " + String(repeating: "b", count: NoteText.titleLimit - 5)
        #expect(text.count == NoteText.titleLimit)
        #expect(NoteText.split(text).title == text)
    }

    @Test func blankTextGivesAnEmptyTitle() {
        #expect(NoteText.split(" \n ").title == "")
        #expect(NoteText.split(" \n ").details == "")
    }

    // MARK: - Search

    @Test func matchesTitleOrDetailsIgnoringCaseAndDiacritics() {
        #expect(NoteText.matches(query: "cafe", title: "Book the Café", details: ""))
        #expect(NoteText.matches(query: "RÉSUMÉ", title: "x", details: "send resume today"))
        #expect(NoteText.matches(query: " milk ", title: "Buy milk", details: ""))
        #expect(!NoteText.matches(query: "tea", title: "Buy milk", details: "and eggs"))
    }

    @Test func blankQueryMatchesNothing() {
        #expect(!NoteText.matches(query: "", title: "Buy milk", details: ""))
        #expect(!NoteText.matches(query: "  ", title: "Buy milk", details: ""))
    }

    // MARK: - Links

    @Test func findsWebLinksInDetails() {
        let text = "Spec: https://example.com/a?b=1, and docs at http://docs.example.org."
        let links = NoteText.links(in: text)
        #expect(links.map(\.url.absoluteString) == ["https://example.com/a?b=1", "http://docs.example.org"])
        #expect((text as NSString).substring(with: links[0].range) == "https://example.com/a?b=1")
    }

    @Test func rangesAreUTF16SoEmojiBeforeALinkDoNotShiftIt() {
        let text = "🐰 see https://example.com"
        let links = NoteText.links(in: text)
        #expect(links.count == 1)
        #expect((text as NSString).substring(with: links[0].range) == "https://example.com")
    }

    @Test func plainTextHasNoLinks() {
        #expect(NoteText.links(in: "Call the bank at 9. Ask about v2.1 of the form.").isEmpty)
        #expect(NoteText.links(in: "").isEmpty)
    }

    @Test func pressReleasedNearbyIsALinkClick() {
        let down = CGPoint(x: 40, y: 12)
        #expect(NoteText.isLinkClick(from: down, to: down))
        #expect(NoteText.isLinkClick(from: down, to: CGPoint(x: 43, y: 9)))
    }

    @Test func pressMovedAwayIsADrag() {
        let down = CGPoint(x: 40, y: 12)
        #expect(!NoteText.isLinkClick(from: down, to: CGPoint(x: 44, y: 12)))
        #expect(!NoteText.isLinkClick(from: down, to: CGPoint(x: 40, y: 8)))
    }

    // MARK: - Created label

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let locale = Locale(identifier: "en_US")
    /// 2026-11-13 14:05:09 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_578_709)

    private func created(daysAgo: Double) -> String {
        NoteText.createdLabel(now.addingTimeInterval(-86_400 * daysAgo), now: now, calendar: calendar, locale: locale)
    }

    @Test func createdTodayAndYesterdayAreNamed() {
        #expect(created(daysAgo: 0.2) == "Created today")
        #expect(created(daysAgo: 1) == "Created yesterday")
    }

    @Test func createdEarlierThisYearShowsDayAndMonth() {
        #expect(created(daysAgo: 10) == "Created Nov 3")
    }

    @Test func createdInAnotherYearShowsTheYear() {
        #expect(created(daysAgo: 400) == "Created Oct 9, 2025")
    }
}
