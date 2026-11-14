import Testing
@testable import BunnyCore

struct SettingsCatalogTests {
    @Test func everyRowIDHasExactlyOneRow() {
        for id in SettingsCatalog.RowID.allCases {
            #expect(SettingsCatalog.rows.filter { $0.id == id }.count == 1, "\(id)")
        }
        #expect(SettingsCatalog.rows.allSatisfy { !$0.title.isEmpty && !$0.icon.isEmpty })
    }

    @Test func everyPageHasRows() {
        for page in SettingsCatalog.Page.allCases {
            #expect(!SettingsCatalog.rows(on: page).isEmpty, "\(page)")
        }
        #expect(SettingsCatalog.Page.allCases.map(\.title) == ["General", "Appearance", "Notes", "Agents", "Data", "About"])
    }

    @Test func emptyQueryFindsNothing() {
        #expect(SettingsCatalog.search("").isEmpty)
        #expect(SettingsCatalog.search("   ").isEmpty)
    }

    @Test func matchesTitlesIgnoringCaseAndDiacritics() {
        let rows = [
            SettingsCatalog.Row(id: .theme, page: .appearance, title: "Thème", icon: "x"),
            SettingsCatalog.Row(id: .quit, page: .general, title: "Quit Bunny", icon: "x"),
        ]
        #expect(SettingsCatalog.search("THEME", in: rows) == [.init(page: .appearance, rows: [rows[0]])])
        #expect(SettingsCatalog.search("thé", in: rows).map(\.page) == [.appearance])
        #expect(SettingsCatalog.search("zebra", in: rows).isEmpty)
    }

    @Test func matchesKeywordsAndNeedsEveryWord() {
        let rows = [
            SettingsCatalog.Row(id: .globalShortcut, page: .general, title: "Global shortcut", icon: "x", keywords: ["hotkey", "keyboard"]),
            SettingsCatalog.Row(id: .quit, page: .general, title: "Quit Bunny", icon: "x"),
        ]
        #expect(SettingsCatalog.search("hotkey", in: rows).first?.rows.map(\.id) == [.globalShortcut])
        #expect(SettingsCatalog.search("global key", in: rows).first?.rows.map(\.id) == [.globalShortcut])
        #expect(SettingsCatalog.search("global zebra", in: rows).isEmpty)
    }

    @Test func resultsAreGroupedByPageInPageOrder() {
        let results = SettingsCatalog.search("trash")
        #expect(results.map(\.page) == [.notes, .data])
        #expect(results[0].rows.map(\.id) == [.completedRetention, .trashRetention])
        #expect(results[1].rows.map(\.id) == [.emptyTrash])
    }

    @Test func aPageTitleMatchListsThePageEvenWithNoRowMatch() {
        let results = SettingsCatalog.search("appearance")
        #expect(results.map(\.page) == [.appearance])
    }

    @Test func realCatalogFindsCommonWords() {
        #expect(SettingsCatalog.search("dark").flatMap(\.rows).map(\.id) == [.theme])
        #expect(SettingsCatalog.search("mcp").flatMap(\.rows).contains { $0.id == .toolsServer })
        #expect(SettingsCatalog.search("update").flatMap(\.rows).map(\.id) == [.checkForUpdates])
        let models = SettingsCatalog.search("model").flatMap(\.rows)
        #expect(!models.isEmpty && models.filter(\.advanced).count == models.count)
    }
}
