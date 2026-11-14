import Foundation
import Testing
@testable import BunnyCore

struct StoreBackupTests {
    private let support = URL(fileURLWithPath: "/Users/someone/Library/Application Support")
    private var store: URL { StoreMigration.storeURL(applicationSupport: support) }
    private var directory: URL { StoreBackup.directory(applicationSupport: support) }

    @Test func path() {
        #expect(directory.path == "/Users/someone/Library/Application Support/Bunny/Backups/pre-v3")
    }

    @Test func noStoreNothingToBackUp() {
        #expect(StoreBackup.plan(store: store, directory: directory) { _ in false }.isEmpty)
    }

    @Test func alreadyBackedUpCopiesNothing() {
        let existing: Set<String> = [store.path, store.path + "-wal", directory.path]
        #expect(StoreBackup.plan(store: store, directory: directory) { existing.contains($0.path) }.isEmpty)
    }

    @Test func copiesTheStoreFilesThatExist() {
        let existing: Set<String> = [store.path, store.path + "-wal"]
        let plan = StoreBackup.plan(store: store, directory: directory) { existing.contains($0.path) }
        #expect(plan.map(\.from.path) == [store.path, store.path + "-wal"])
        #expect(plan.map(\.to.path) == [directory.path + "/Bunny.store", directory.path + "/Bunny.store-wal"])
    }

    // MARK: - On disk (temp directory)

    private func makeTemp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bunny-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func runCopiesOnceAndLeavesTheStoreAlone() throws {
        let fileManager = FileManager.default
        let root = try makeTemp()
        defer { try? fileManager.removeItem(at: root) }
        let store = StoreMigration.storeURL(applicationSupport: root)
        let directory = StoreBackup.directory(applicationSupport: root)
        try fileManager.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("main".utf8).write(to: store)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: store.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: store.path + "-shm"))

        let made = try StoreBackup.run(store: store, directory: directory)
        #expect(made)
        func text(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }
        #expect(try text(directory.appendingPathComponent("Bunny.store")) == "main")
        #expect(try text(directory.appendingPathComponent("Bunny.store-wal")) == "wal")
        #expect(try text(directory.appendingPathComponent("Bunny.store-shm")) == "shm")
        #expect(try text(store) == "main")

        // A later launch, with a changed store: the backup is not touched.
        try Data("newer".utf8).write(to: store)
        let again = try StoreBackup.run(store: store, directory: directory)
        #expect(!again)
        #expect(try text(directory.appendingPathComponent("Bunny.store")) == "main")
    }

    @Test func runWithoutAStoreCreatesNothing() throws {
        let root = try makeTemp()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = StoreBackup.directory(applicationSupport: root)
        let made = try StoreBackup.run(store: StoreMigration.storeURL(applicationSupport: root), directory: directory)
        #expect(!made)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func aFailedCopyLeavesNoBackupFolderSoItIsRetried() throws {
        let fileManager = FileManager.default
        let root = try makeTemp()
        defer { try? fileManager.removeItem(at: root) }
        let store = StoreMigration.storeURL(applicationSupport: root)
        let directory = StoreBackup.directory(applicationSupport: root)
        try fileManager.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("main".utf8).write(to: store)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: store.path + "-wal"))

        struct Boom: Error {}
        var copies = 0
        #expect(throws: Boom.self) {
            try StoreBackup.run(store: store, directory: directory) { from, to in
                copies += 1
                if copies == 2 { throw Boom() }
                try fileManager.copyItem(at: from, to: to)
            }
        }
        #expect(!fileManager.fileExists(atPath: directory.path))
        let leftovers = try fileManager.contentsOfDirectory(atPath: directory.deletingLastPathComponent().path)
        #expect(leftovers.isEmpty)
        let retried = try StoreBackup.run(store: store, directory: directory)
        #expect(retried)
    }
}
