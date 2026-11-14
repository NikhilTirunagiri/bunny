import Foundation

/// The one-time copy of the store made before v3 first opens it:
/// `<applicationSupport>/Bunny/Backups/pre-v3/`. "The folder exists" is the done marker, so the
/// files are copied into a temporary folder that is renamed into place last; a failed or interrupted
/// copy leaves no `pre-v3` folder and is tried again at the next launch.
enum StoreBackup {
    static let partialSuffix = ".partial"

    static func directory(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("Bunny", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("pre-v3", isDirectory: true)
    }

    /// Copies to make: the store and its sidecar files that exist, under their own names. Empty when
    /// there is no store yet (nothing to protect) or the backup folder is already there.
    static func plan(store: URL, directory: URL, fileExists: (URL) -> Bool) -> [(from: URL, to: URL)] {
        guard fileExists(store), !fileExists(directory) else { return [] }
        return StoreMigration.suffixes.compactMap { suffix in
            let from = URL(fileURLWithPath: store.path + suffix)
            guard fileExists(from) else { return nil }
            return (from, directory.appendingPathComponent(from.lastPathComponent, isDirectory: false))
        }
    }

    /// Makes the backup when `plan` says so. Returns false when there was nothing to do. On an error
    /// what was written is removed and the error rethrown. `copy` is injectable for tests.
    @discardableResult
    static func run(store: URL, directory: URL, fileManager: FileManager = .default,
                    copy: ((URL, URL) throws -> Void)? = nil) throws -> Bool {
        let copies = plan(store: store, directory: directory) { fileManager.fileExists(atPath: $0.path) }
        guard !copies.isEmpty else { return false }
        let copyItem = copy ?? { try fileManager.copyItem(at: $0, to: $1) }
        let partial = URL(fileURLWithPath: directory.path + partialSuffix, isDirectory: true)
        do {
            if fileManager.fileExists(atPath: partial.path) { try fileManager.removeItem(at: partial) }
            try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
            for pair in copies {
                try copyItem(pair.from, partial.appendingPathComponent(pair.to.lastPathComponent, isDirectory: false))
            }
            try fileManager.moveItem(at: partial, to: directory)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
        return true
    }
}
