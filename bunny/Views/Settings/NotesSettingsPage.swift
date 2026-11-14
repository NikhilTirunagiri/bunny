import SwiftUI

struct NotesSettingsPage: View {
    @AppStorage(NotesPreferences.completedRetentionKey) private var completedRetention = "24h"
    @AppStorage(NotesPreferences.trashRetentionDaysKey) private var trashRetentionDays = 30
    @AppStorage(NotesPreferences.confirmDeleteForeverKey) private var confirmDeleteForever = true

    /// One width for both pop-up buttons, so they line up at both edges.
    private static let pickerWidth: CGFloat = 140

    var body: some View {
        SettingsCard {
            SettingsRow(.completedRetention, caption: "Ticked notes wait in the Completed group until then.") {
                PopUpButton(selection: $completedRetention, options: [
                    .init(value: "24h", title: "After 24 hours"),
                    .init(value: "7d", title: "After 7 days"),
                    .init(value: "never", title: "Never"),
                ], width: Self.pickerWidth)
            }
            SettingsRow(.trashRetention, caption: "Notes in Trash are deleted for good after this long.") {
                PopUpButton(selection: $trashRetentionDays, options: [
                    .init(value: 7, title: "After 7 days"),
                    .init(value: 30, title: "After 30 days"),
                    .init(value: 90, title: "After 90 days"),
                    .init(value: 0, title: "Never"),
                ], width: Self.pickerWidth)
            }
            SettingsRow(.confirmDelete, caption: "For Delete Forever and Empty Trash in the Trash view.") {
                SettingsSwitch(isOn: $confirmDeleteForever)
            }
        }
        // A new retention applies at once, not at the next hourly check.
        .onChange(of: completedRetention) { MidnightScheduler.shared.runHousekeeping() }
        .onChange(of: trashRetentionDays) { MidnightScheduler.shared.runHousekeeping() }
    }
}
