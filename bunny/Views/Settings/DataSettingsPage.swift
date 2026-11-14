import SwiftData
import SwiftUI

struct DataSettingsPage: View {
    @Environment(\.settingsLive) private var live
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BunnyTask> { $0.deletedAt != nil }) private var trashed: [BunnyTask]
    @State private var sizes: String?
    private let exporter = NoteExporter.shared

    var body: some View {
        SettingsCard {
            SettingsRow(.storage, caption: sizes ?? "Measuring…") {
                Button("Show in Finder") { DataActions.showInFinder() }
                    .buttonStyle(.bunny)
            } detail: {
                SettingsNote("Bunny's own files, for backups. To read your notes as files, use Export.")
            }
            SettingsRow(.export, caption: exportCaption) {
                Button("Export…") { exporter.chooseDestinationAndExport(from: modelContext) }
                    .buttonStyle(.bunny)
                    .disabled(exporter.isRunning)
            } detail: {
                if case .failed(let message) = exporter.state { SettingsNote(message, color: .red) }
            }
            SettingsRow(.emptyTrash, caption: trashCaption) {
                Button("Empty…") {
                    if DataActions.confirmEmptyTrash(in: modelContext) { measure() }
                }
                .buttonStyle(.bunny)
                .disabled(trashed.isEmpty)
            }
        }
        SettingsCard {
            SettingsRow(.resetSettings, caption: "Returns every setting to its default. Your notes are kept.") {
                Button("Reset…") { DataActions.confirmResetSettings() }
                    .buttonStyle(.bunny)
            }
            SettingsRow(.eraseAll, caption: "Deletes every note and stored attachment. Settings are kept.") {
                Button("Erase…") {
                    if DataActions.confirmEraseAll(in: modelContext) { measure() }
                }
                .buttonStyle(.bunnyDestructive)
            }
        }
        .onAppear(perform: measure)
    }

    private var exportCaption: String {
        switch exporter.state {
        case .idle, .failed: return "Markdown files, with attached files copied next to them."
        case .running(let done, let total): return "Exporting \(done) of \(total)…"
        case .finished(let message): return message
        }
    }

    private var trashCaption: String {
        // Subtasks trashed with their note are part of it.
        let ids = Set(trashed.map(\.id))
        let count = trashed.filter { $0.parentID.map(ids.contains) != true }.count
        switch count {
        case 0: return "Trash is empty."
        case 1: return "1 note in Trash."
        default: return "\(count) notes in Trash."
        }
    }

    private func measure() {
        guard live else {
            sizes = "Notes 1.2 MB · Attachments 34.6 MB"
            return
        }
        DataActions.measure { notes, attachments in
            sizes = "Notes \(notes) · Attachments \(attachments)"
        }
    }
}
