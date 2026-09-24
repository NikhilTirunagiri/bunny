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
