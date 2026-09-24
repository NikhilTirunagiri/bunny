import Testing
import Foundation
@testable import BunnyCore

struct StoreMigrationTests {
    private let home = URL(fileURLWithPath: "/Users/someone")
    private var legacy: URL { StoreMigration.legacySandboxStoreURL(home: home) }
    private var newStore: URL {
        StoreMigration.storeURL(applicationSupport: home.appendingPathComponent("Library/Application Support"))
    }

    @Test func paths() {
        #expect(legacy.path == "/Users/someone/Library/Containers/nikhiltirunagiri.bunny/Data/Library/Application Support/default.store")
        #expect(newStore.path == "/Users/someone/Library/Application Support/Bunny/Bunny.store")
        #expect(newStore.path != "/Users/someone/Library/Application Support/default.store")
    }

    @Test func freshInstallCopiesNothing() {
        #expect(StoreMigration.plan(legacyStore: legacy, newStore: newStore) { _ in false }.isEmpty)
    }

    @Test func sandboxDataPresentCopiesAllThree() {
        let existing: Set<String> = [legacy.path, legacy.path + "-shm", legacy.path + "-wal"]
        let plan = StoreMigration.plan(legacyStore: legacy, newStore: newStore) { existing.contains($0.path) }
        #expect(plan.map(\.from.path) == [legacy.path, legacy.path + "-shm", legacy.path + "-wal"])
        #expect(plan.map(\.to.path) == [newStore.path, newStore.path + "-shm", newStore.path + "-wal"])
    }

    @Test func alreadyMigratedCopiesNothing() {
        let existing: Set<String> = [legacy.path, legacy.path + "-shm", legacy.path + "-wal", newStore.path]
        #expect(StoreMigration.plan(legacyStore: legacy, newStore: newStore) { existing.contains($0.path) }.isEmpty)
    }

    @Test func partialCopiesOnlyExistingFiles() {
        let existing: Set<String> = [legacy.path, legacy.path + "-wal"]
        let plan = StoreMigration.plan(legacyStore: legacy, newStore: newStore) { existing.contains($0.path) }
        #expect(plan.map(\.from.path) == [legacy.path, legacy.path + "-wal"])
        #expect(plan.map(\.to.path) == [newStore.path, newStore.path + "-wal"])
    }

    @Test func sidecarsWithoutMainStoreCopyNothing() {
        let existing: Set<String> = [legacy.path + "-shm", legacy.path + "-wal"]
        #expect(StoreMigration.plan(legacyStore: legacy, newStore: newStore) { existing.contains($0.path) }.isEmpty)
    }
}

/// Real-file tests for the crash-safe copy (temp directory per test).
struct StoreMigrationFileTests {
    private let fm = FileManager.default
    private let root: URL
    private let legacy: URL
    private let newStore: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bunny-store-\(UUID().uuidString)")
        legacy = StoreMigration.legacySandboxStoreURL(home: root)
        newStore = StoreMigration.storeURL(applicationSupport: root.appendingPathComponent("AppSupport"))
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func write(_ text: String, _ url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    private func path(_ base: URL, _ suffix: String) -> URL { URL(fileURLWithPath: base.path + suffix) }

    private func writeLegacy(_ suffixes: [String] = ["", "-shm", "-wal"]) throws {
        for suffix in suffixes { try write("legacy\(suffix)", path(legacy, suffix)) }
    }

    /// No Bunny.store, no sidecars, no temp file.
    private func expectNothingWritten() {
        for suffix in ["", "-shm", "-wal", StoreMigration.tempSuffix] {
            #expect(!fm.fileExists(atPath: newStore.path + suffix), "\(suffix) left behind")
        }
    }

    private func expectLegacyUntouched(_ suffixes: [String] = ["", "-shm", "-wal"]) {
        for suffix in suffixes { #expect(read(path(legacy, suffix)) == "legacy\(suffix)") }
    }

    @Test func copiesAllThreeWithMatchingNames() throws {
        defer { try? fm.removeItem(at: root) }
        try writeLegacy()
        #expect(try StoreMigration.migrate(legacyStore: legacy, newStore: newStore))
        #expect(read(newStore) == "legacy")
        #expect(read(path(newStore, "-shm")) == "legacy-shm")
        #expect(read(path(newStore, "-wal")) == "legacy-wal")
        #expect(!fm.fileExists(atPath: StoreMigration.tempURL(for: newStore).path))
        expectLegacyUntouched()
        // Second launch: already migrated, nothing changes.
        try write("new data", newStore)
        #expect(try !StoreMigration.migrate(legacyStore: legacy, newStore: newStore))
        #expect(read(newStore) == "new data")
    }

    @Test func freshInstallWritesNothing() throws {
        defer { try? fm.removeItem(at: root) }
        #expect(try !StoreMigration.migrate(legacyStore: legacy, newStore: newStore))
        expectNothingWritten()
    }

    @Test func staleSidecarsAndTempAreReplacedOrRemoved() throws {
        defer { try? fm.removeItem(at: root) }
        try writeLegacy(["", "-wal"])
        try write("stale-shm", path(newStore, "-shm"))
        try write("stale-wal", path(newStore, "-wal"))
        try write("stale-temp", StoreMigration.tempURL(for: newStore))
        #expect(try StoreMigration.migrate(legacyStore: legacy, newStore: newStore))
        #expect(read(newStore) == "legacy")
        #expect(read(path(newStore, "-wal")) == "legacy-wal")
        // No legacy -shm: the stale one must not survive next to the migrated store.
        #expect(!fm.fileExists(atPath: newStore.path + "-shm"))
        #expect(!fm.fileExists(atPath: StoreMigration.tempURL(for: newStore).path))
    }

    @Test func failureCopyingMainLeavesNothing() throws {
        defer { try? fm.removeItem(at: root) }
        try writeLegacy()
        let temp = StoreMigration.tempURL(for: newStore)
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try StoreMigration.migrate(legacyStore: legacy, newStore: newStore) { from, to in
                if to == temp {
                    try Data("partial".utf8).write(to: to)   // a half-written temp file
                    throw Boom()
                }
                try FileManager.default.copyItem(at: from, to: to)
            }
        }
        expectNothingWritten()
        expectLegacyUntouched()
    }

    @Test func failureCopyingSidecarLeavesNothing() throws {
        defer { try? fm.removeItem(at: root) }
        try writeLegacy()
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try StoreMigration.migrate(legacyStore: legacy, newStore: newStore) { from, to in
                if to.path.hasSuffix("-wal") { throw Boom() }
                try FileManager.default.copyItem(at: from, to: to)
            }
        }
        expectNothingWritten()
        // A retry after the failure succeeds.
        #expect(try StoreMigration.migrate(legacyStore: legacy, newStore: newStore))
        #expect(read(path(newStore, "-wal")) == "legacy-wal")
    }

    @Test func realCopyFailureFromVanishedSidecarLeavesNothing() throws {
        defer { try? fm.removeItem(at: root) }
        try writeLegacy()
        // The -wal disappears between planning and copying.
        #expect(throws: (any Error).self) {
            try StoreMigration.migrate(legacyStore: legacy, newStore: newStore) { from, to in
                if from.path.hasSuffix("-wal") { try FileManager.default.removeItem(at: from) }
                try FileManager.default.copyItem(at: from, to: to)
            }
        }
        expectNothingWritten()
    }

    @Test func legacyStatusProbe() throws {
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: legacy.deletingLastPathComponent().path)
            try? fm.removeItem(at: root)
        }
        #expect(StoreMigration.legacyStatus(legacy) == .absent)
        #expect(StoreMigration.legacyStatus(StoreMigration.legacySandboxStoreURL(home: root.appendingPathComponent("nobody"))) == .absent)
        try writeLegacy()
        #expect(StoreMigration.legacyStatus(legacy) == .present)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: legacy.deletingLastPathComponent().path)
        guard case .unreadable = StoreMigration.legacyStatus(legacy) else {
            Issue.record("expected .unreadable for a directory without read permission")
            return
        }
    }

    @Test func permissionErrorDetection() {
        #expect(StoreMigration.isPermissionError(CocoaError(.fileReadNoPermission)))
        #expect(StoreMigration.isPermissionError(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))))
        #expect(StoreMigration.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: 1,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])))
        #expect(!StoreMigration.isPermissionError(CocoaError(.fileNoSuchFile)))
    }
}
