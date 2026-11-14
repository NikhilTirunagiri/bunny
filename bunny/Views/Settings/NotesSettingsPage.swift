import SwiftUI

struct NotesSettingsPage: View {
    @AppStorage(NotesPreferences.completedRetentionKey) private var completedRetention = "24h"
    @AppStorage(NotesPreferences.trashRetentionDaysKey) private var trashRetentionDays = 30
    @AppStorage(NotesPreferences.confirmDeleteForeverKey) private var confirmDeleteForever = true

    var body: some View {
        SettingsCard {
            SettingsRow(.completedRetention, caption: "Ticked notes wait in the Completed group until then.") {
                Picker("", selection: $completedRetention) {
                    Text("After 24 hours").tag("24h")
                    Text("After 7 days").tag("7d")
                    Text("Never").tag("never")
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(.trashRetention, caption: "Notes in Trash are deleted for good after this long.") {
                Picker("", selection: $trashRetentionDays) {
                    Text("After 7 days").tag(7)
                    Text("After 30 days").tag(30)
                    Text("After 90 days").tag(90)
                    Text("Never").tag(0)
                }
                .labelsHidden()
                .fixedSize()
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
