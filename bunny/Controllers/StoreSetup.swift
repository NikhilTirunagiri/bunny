import AppKit

/// Decides where the SwiftData store is opened at launch, and whether the sandboxed build's store
/// may be migrated now. The copy itself is `StoreMigration` (Core); this adds the checks that need
/// AppKit: another running copy of Bunny, and asking the owner when the old data can't be read.
@MainActor
enum StoreSetup {
    /// The store URL to open, or nil when Bunny must quit (the owner has already been told why).
    static func prepare() -> URL? {
        let fileManager = FileManager.default
        let newStore: URL
        do {
            let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
            newStore = StoreMigration.storeURL(applicationSupport: appSupport)
            try fileManager.createDirectory(at: newStore.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            showQuitAlert("Bunny can't create its data folder.", detail: error.localizedDescription)
            return nil
        }

        // Already migrated (or started fresh before): the only marker is Bunny.store itself.
        if fileManager.fileExists(atPath: newStore.path) { return newStore }

        let legacy = StoreMigration.legacySandboxStoreURL(home: fileManager.homeDirectoryForCurrentUser)
        switch StoreMigration.legacyStatus(legacy, fileManager: fileManager) {
        case .absent:
            return newStore
        case .unreadable(let reason):
            return confirmStartFresh(legacy: legacy, reason: reason) ? newStore : nil
        case .present:
            // Never copy a database another process may be writing; and don't open an empty store
            // either, since that would mark the migration done and strand the old data.
            if otherCopyIsRunning() {
                showQuitAlert("Quit the other copy of Bunny, then relaunch.",
                              detail: "Another copy of Bunny is running. Your tasks are copied to the new version only while it is closed.")
                return nil
            }
            do {
                try StoreMigration.migrate(legacyStore: legacy, newStore: newStore, fileManager: fileManager)
                return newStore
            } catch {
                return confirmStartFresh(legacy: legacy, reason: error.localizedDescription) ? newStore : nil
            }
        }
    }

    private static func otherCopyIsRunning() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: StoreMigration.bundleIdentifier)
            .contains { $0.processIdentifier != me && !$0.isTerminated }
    }

    /// "Quit" is the default (Return). Starting fresh leaves the old data where it is.
    private static func confirmStartFresh(legacy: URL, reason: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Bunny couldn't read your existing tasks."
        alert.informativeText = """
            Your data is safe and untouched at:
            \(legacy.deletingLastPathComponent().path)

            If macOS asked for permission to access another app's data, quit, allow access, and relaunch. \
            Or start fresh with an empty task list (the old data stays where it is).

            \(reason)
            """
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Start fresh")
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn
    }

    private static func showQuitAlert(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        alert.runModal()
    }
}
