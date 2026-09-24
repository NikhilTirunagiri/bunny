import Foundation

/// Where Bunny's SwiftData store lives, and the one-time copy of a store left behind by the
/// sandboxed build. Pure path/copy logic (Foundation only) so it is unit-testable; the app target
/// decides *whether* to migrate (another copy running, permission prompts) — see `StoreSetup`.
///
/// Bunny is no longer sandboxed, so the default `ModelContainer` location would be
/// `~/Library/Application Support/default.store` — a file that can belong to another app.
/// Bunny therefore uses a dedicated `~/Library/Application Support/Bunny/Bunny.store` and never
/// touches `default.store` in the shared Application Support directory.
///
/// Crash safety: "`Bunny.store` exists" is the migrated marker. The sidecars are copied first,
/// the main file goes to a temp name and is renamed to `Bunny.store` last (rename(2) within one
/// directory is atomic). A crash before the rename leaves no `Bunny.store`, so the next launch
/// clears the leftovers and migrates again. The legacy files are only ever read.
enum StoreMigration {
    static let bundleIdentifier = "nikhiltirunagiri.bunny"
    /// SQLite store plus its sidecar files, in plan order (main first).
    static let suffixes = ["", "-shm", "-wal"]
    static let tempSuffix = ".migrating"

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

    /// `Bunny.store.migrating`, next to the store (same directory, so the final rename is atomic).
    static func tempURL(for newStore: URL) -> URL {
        URL(fileURLWithPath: newStore.path + tempSuffix)
    }

    /// Everything a migration may write besides `Bunny.store` itself: the temp main file and the sidecars.
    static func scratchURLs(for newStore: URL) -> [URL] {
        [tempURL(for: newStore)] + suffixes.dropFirst().map { URL(fileURLWithPath: newStore.path + $0) }
    }

    /// Copies to perform (never moves). Empty when the new store already exists (already migrated)
    /// or when there is no legacy store (fresh install). Otherwise one pair per legacy file that
    /// exists, main file first, with the sidecars renamed to match the new base name.
    static func plan(legacyStore: URL, newStore: URL, fileExists: (URL) -> Bool) -> [(from: URL, to: URL)] {
        guard !fileExists(newStore), fileExists(legacyStore) else { return [] }
        return suffixes.compactMap { suffix in
            let from = URL(fileURLWithPath: legacyStore.path + suffix)
            guard fileExists(from) else { return nil }
            return (from, URL(fileURLWithPath: newStore.path + suffix))
        }
    }

    /// What is known about the legacy store before migrating.
    enum LegacyStatus: Equatable {
        case absent
        case present
        /// The container exists but can't be read (e.g. macOS App Data protection).
        case unreadable(String)
    }

    /// Probes the legacy store by listing its directory and opening the main file for reading, so a
    /// permission problem is reported as `.unreadable` instead of looking like "no data" (which would
    /// start a fresh store and block the migration for good).
    static func legacyStatus(_ legacyStore: URL, fileManager: FileManager = .default) -> LegacyStatus {
        let directory = legacyStore.deletingLastPathComponent().path
        do {
            let names = try fileManager.contentsOfDirectory(atPath: directory)
            guard names.contains(legacyStore.lastPathComponent) else { return .absent }
            let handle = try FileHandle(forReadingFrom: legacyStore)
            try? handle.close()
            return .present
        } catch {
            if isPermissionError(error) { return .unreadable(error.localizedDescription) }
            if !fileManager.fileExists(atPath: directory) { return .absent }
            return .unreadable(error.localizedDescription)
        }
    }

    /// Crash-safe copy of the legacy store into `newStore` (see the type comment). Returns false when
    /// there was nothing to do. On any error everything written so far is removed and the error rethrown.
    /// `copy` is injectable for tests; it defaults to `FileManager.copyItem`.
    @discardableResult
    static func migrate(legacyStore: URL, newStore: URL, fileManager: FileManager = .default,
                        copy: ((URL, URL) throws -> Void)? = nil) throws -> Bool {
        let copies = plan(legacyStore: legacyStore, newStore: newStore) { fileManager.fileExists(atPath: $0.path) }
        guard let main = copies.first(where: { $0.to == newStore }) else { return false }
        let copyItem = copy ?? { try fileManager.copyItem(at: $0, to: $1) }
        let scratch = scratchURLs(for: newStore)
        let temp = tempURL(for: newStore)

        do {
            try fileManager.createDirectory(at: newStore.deletingLastPathComponent(), withIntermediateDirectories: true)
            // (a) Leftovers of a crashed attempt, or stale sidecars without a store: never mix them in.
            for url in scratch where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            // (b) Sidecars straight to their final names.
            for pair in copies where pair.to != newStore {
                try copyItem(pair.from, pair.to)
            }
            // (c) Main file to the temp name, then the atomic rename that marks the migration done.
            try copyItem(main.from, temp)
            try fileManager.moveItem(at: temp, to: newStore)
        } catch {
            for url in scratch { try? fileManager.removeItem(at: url) }
            throw error
        }
        return true
    }

    /// True for "not permitted" failures (Cocoa no-permission codes, EPERM/EACCES), including underlying errors.
    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EPERM) || nsError.code == Int(EACCES) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isPermissionError(underlying)
        }
        return false
    }
}
