import Foundation

/// Where Bunny's SwiftData store lives, and the one-time copy of a store left behind by the
/// sandboxed build. Pure path logic (file-system access is injected) so it is unit-testable.
///
/// Bunny is no longer sandboxed, so the default `ModelContainer` location would be
/// `~/Library/Application Support/default.store` — a file that can belong to another app.
/// Bunny therefore uses a dedicated `~/Library/Application Support/Bunny/Bunny.store` and never
/// touches `default.store` in the shared Application Support directory.
enum StoreMigration {
    static let bundleIdentifier = "nikhiltirunagiri.bunny"
    /// SQLite store plus its sidecar files, in copy order.
    static let suffixes = ["", "-shm", "-wal"]

    /// `<applicationSupport>/Bunny/Bunny.store`.
    static func storeURL(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("Bunny", isDirectory: true)
            .appendingPathComponent("Bunny.store", isDirectory: false)
    }

    /// The sandboxed build's store: `<home>/Library/Containers/<bundle id>/Data/Library/Application Support/default.store`.
    static func legacySandboxStoreURL(home: URL, bundleIdentifier: String = bundleIdentifier) -> URL {
        home.appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent("default.store", isDirectory: false)
    }

    /// Copies to perform (never moves). Empty when the new store already exists (already migrated)
    /// or when there is no legacy store (fresh install). Otherwise one pair per legacy file that
    /// exists, with the sidecars renamed to match the new base name.
    static func plan(legacyStore: URL, newStore: URL, fileExists: (URL) -> Bool) -> [(from: URL, to: URL)] {
        guard !fileExists(newStore), fileExists(legacyStore) else { return [] }
        return suffixes.compactMap { suffix in
            let from = URL(fileURLWithPath: legacyStore.path + suffix)
            guard fileExists(from) else { return nil }
            return (from, URL(fileURLWithPath: newStore.path + suffix))
        }
    }

    /// Creates the store directory and performs the planned copies. Returns the store URL to open.
    /// A failed copy removes any partially copied files so the next launch retries cleanly.
    @discardableResult
    static func prepareStore(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                             appropriateFor: nil, create: true)
        let newStore = storeURL(applicationSupport: appSupport)
        try fileManager.createDirectory(at: newStore.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = legacySandboxStoreURL(home: fileManager.homeDirectoryForCurrentUser)
        let copies = plan(legacyStore: legacy, newStore: newStore) { fileManager.fileExists(atPath: $0.path) }
        do {
            for copy in copies {
                try fileManager.copyItem(at: copy.from, to: copy.to)
            }
        } catch {
            for copy in copies { try? fileManager.removeItem(at: copy.to) }
            throw error
        }
        return newStore
    }
}
