import AppKit
import Observation
import SwiftData

/// "Export all notes" (Settings → Data): one Markdown file per top-level note that is not in Trash,
/// in a new "Bunny export <date>" folder, with attached regular files copied next to them. What goes
/// where is `NoteExport` (Core); this reads the notes, then writes off the main thread. Nothing that
/// exists is ever overwritten.
@MainActor @Observable
final class NoteExporter {
    static let shared = NoteExporter()
    private init() {}

    enum State: Equatable {
        case idle
        case running(done: Int, total: Int)
        case finished(String)
        case failed(String)
    }

    private(set) var state: State = .idle

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Asks for the destination folder, then exports into a new subfolder of it.
    func chooseDestinationAndExport(from context: ModelContext) {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose where to put the folder of exported notes."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        export(from: context, to: destination)
    }

    func export(from context: ModelContext, to destination: URL) {
        guard !isRunning else { return }
        let planned = NoteExport.plan(notes(in: context))
        guard !planned.isEmpty else {
            state = .finished("There are no notes to export.")
            return
        }
        let fileManager = FileManager.default
        let base = NoteExport.folderName(at: Date())
        var folder = destination.appendingPathComponent(base, isDirectory: true)
        var number = 2
        while fileManager.fileExists(atPath: folder.path) {
            folder = destination.appendingPathComponent("\(base) \(number)", isDirectory: true)
            number += 1
        }
        let files = planned.map { (name: $0.fileName + ".md", text: $0.markdown, copies: $0.copies.map { (from: $0.from, to: $0.to) }) }
        state = .running(done: 0, total: files.count)
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Self.write(files, to: folder) { done in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if NoteExporter.shared.isRunning { NoteExporter.shared.state = .running(done: done, total: files.count) }
                    }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NoteExporter.shared.finish(outcome, count: files.count) }
            }
        }
    }

    private func finish(_ outcome: Result<Int, Error>, count: Int) {
        switch outcome {
        case .success(let failedCopies):
            var message = count == 1 ? "Exported 1 note" : "Exported \(count) notes"
            if failedCopies > 0 {
                message += failedCopies == 1 ? " · 1 attachment could not be copied" : " · \(failedCopies) attachments could not be copied"
            }
            state = .finished(message)
        case .failure(let error):
            state = .failed("Export failed: \(error.localizedDescription)")
        }
    }

    /// Top-level notes that are not in Trash, in list order, with their subtasks and attachments.
    private func notes(in context: ModelContext) -> [NoteExport.Note] {
        let descriptor = FetchDescriptor<BunnyTask>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        let live = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
        return live.filter { !$0.isSubtask }.map { task in
            NoteExport.Note(
                title: task.title,
                details: task.taskDescription,
                createdAt: task.createdAt,
                isCompleted: task.isCompleted,
                subtasks: live.filter { $0.parentID == task.id }.map { .init(title: $0.title, done: $0.isCompleted) },
                attachments: ShelfService.items(for: task.id, in: context).map { item in
                    guard let url = ShelfService.resolve(item) else {
                        return .init(name: item.displayName, path: item.lastKnownPath, kind: .missing)
                    }
                    let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                    return .init(name: item.displayName, path: url.path, kind: isFile ? .file : .folder)
                })
        }
    }

    /// Creates `folder` (it must not exist) and writes every note and its copies into it. Returns how
    /// many attachment copies failed; the notes themselves failing ends the export with the error.
    nonisolated private static func write(_ files: [(name: String, text: String, copies: [(from: String, to: String)])],
                                          to folder: URL, progress: @escaping @Sendable (Int) -> Void) -> Result<Int, Error> {
        let fileManager = FileManager.default
        var failedCopies = 0
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
            for (index, file) in files.enumerated() {
                try Data(file.text.utf8).write(to: folder.appendingPathComponent(file.name), options: .withoutOverwriting)
                for copy in file.copies {
                    let target = folder.appendingPathComponent(copy.to)
                    do {
                        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fileManager.copyItem(atPath: copy.from, toPath: target.path)
                    } catch {
                        failedCopies += 1
                    }
                }
                progress(index + 1)
            }
        } catch {
            return .failure(error)
        }
        return .success(failedCopies)
    }
}
