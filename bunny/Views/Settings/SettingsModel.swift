import Observation
import SwiftUI

/// What the Settings window shows: the page, the search text, and the row a search result jumped to.
@MainActor @Observable
final class SettingsModel {
    static let highlightDuration: TimeInterval = 1.6

    var page: SettingsCatalog.Page = .general
    var query = ""
    /// The row to scroll to and tint for a moment.
    private(set) var highlighted: SettingsCatalog.RowID?
    /// The Agents page's Advanced part is unfolded.
    var advancedExpanded = false
    /// Bumped by ⌘F; the sidebar focuses its search field on change.
    private(set) var searchFocusRequests = 0

    func focusSearch() { searchFocusRequests += 1 }

    /// A search result was chosen: open its page (unfolding Advanced if the row is in there), scroll
    /// to the row and tint it briefly.
    func reveal(_ row: SettingsCatalog.Row) {
        page = row.page
        if row.advanced { advancedExpanded = true }
        highlighted = row.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.highlightDuration) { [weak self] in
            if self?.highlighted == row.id { self?.highlighted = nil }
        }
    }
}

extension EnvironmentValues {
    /// False in snapshots: the pages then show fixed sample values and start nothing (no CLI
    /// detection, no model list, no disk or network access).
    @Entry var settingsLive = true
}
