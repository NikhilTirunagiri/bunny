import AppKit
import SwiftData

/// Settings → Data: how much Bunny stores, where, and the two bulk deletions.
@MainActor
enum DataActions {
    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// `Application Support/Bunny`.
    static var folder: URL {
        StoreMigration.storeURL(applicationSupport: applicationSupport).deletingLastPathComponent()
    }

    static func showInFinder() {
        NSWorkspace.shared.open(folder)
    }

    /// Sizes on disk of the notes database (with its sidecar files) and of the Attachments folder,
    /// as text ("1.2 MB"). Measured off the main thread.
    static func measure(completion: @escaping @MainActor @Sendable (_ notes: String, _ attachments: String) -> Void) {
        let store = StoreMigration.storeURL(applicationSupport: applicationSupport)
        let storeFiles = StoreMigration.suffixes.map { URL(fileURLWithPath: store.path + $0) }
        let attachments = AttachmentRules.root(applicationSupport: applicationSupport)
        DispatchQueue.global(qos: .utility).async {
            let notesSize = storeFiles.reduce(0) { $0 + fileSize($1) }
            var attachmentsSize = 0
            let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
            if let files = FileManager.default.enumerator(at: attachments, includingPropertiesForKeys: keys) {
                for case let url as URL in files { attachmentsSize += fileSize(url) }
            }
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let notesText = formatter.string(fromByteCount: Int64(notesSize))
            let attachmentsText = formatter.string(fromByteCount: Int64(attachmentsSize))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(notesText, attachmentsText) }
            }
        }
    }

    nonisolated private static func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey])
        return values?.isRegularFile == true ? values?.totalFileAllocatedSize ?? 0 : 0
    }

    // MARK: - Deleting

    /// Asks, then deletes everything in Trash for good. Returns whether it did.
    @discardableResult
    static func confirmEmptyTrash(in context: ModelContext) -> Bool {
        let trashed = ((try? context.fetch(FetchDescriptor<BunnyTask>())) ?? []).filter { !$0.isLive }
        guard !trashed.isEmpty,
              confirm("Empty Trash?", detail: "The notes in Trash are deleted for good. This can't be undone.",
                      action: "Empty Trash") else { return false }
        TaskActions.deleteForever(Set(trashed.map(\.id)), in: context)
        return true
    }

    /// Asks, then erases every note. Returns whether it did.
    @discardableResult
    static func confirmEraseAll(in context: ModelContext) -> Bool {
        guard confirm("Erase all data?",
                      detail: "Every note, subtask and attachment stored by Bunny is deleted for good, and running agents are stopped. " +
                              "Your settings and the files you linked stay. This can't be undone.",
                      action: "Erase All Data") else { return false }
        eraseAll(in: context)
        return true
    }

    /// Stops every agent and deletes every note, subtask and attachment record, and every file Bunny
    /// stored for them. Clears the selection and the pending Undo. Preferences are not touched.
    static func eraseAll(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<BunnyTask>())) ?? []
        TaskActions.deleteForever(Set(all.map(\.id)), in: context)
        // Attachment records and stored files whose note was already gone.
        for item in (try? context.fetch(FetchDescriptor<ShelfItem>())) ?? [] {
            AttachmentThumbnails.drop(item.id)
            context.delete(item)
        }
        try? context.save()
        try? FileManager.default.removeItem(at: AttachmentRules.root(applicationSupport: applicationSupport))
        PanelCoordinator.shared.dataErased()
    }

    // MARK: - Reset settings

    /// Stored values that are not settings and survive a reset: Welcome was seen (a reset must not
    /// show it again) and where the Settings window sits.
    static let resetKeepList: Set<String> = [WindowManager.onboardingCompletedKey, WindowManager.settingsFrameKey]

    /// Asks, then returns every setting to its default and restarts Bunny. Notes are not touched.
    static func confirmResetSettings() {
        guard confirm("Reset all settings?",
                      detail: "Every setting returns to its default: appearance, shortcut, agents, folders, retention times. " +
                              "Your notes, attachments and Trash are not touched. Bunny will restart.",
                      action: "Reset and Restart") else { return }
        resetSettingsAndRestart()
    }

    /// Stops the agents as quitting does, clears the preferences, then starts a new Bunny and quits
    /// this one, so everything starts again from defaults.
    private static func resetSettingsAndRestart() {
        AgentSupervisor.shared.shutdownAll()
        BunnyToolsServer.shared.stop()
        GlobalHotKey.shared.unregister()
        if LaunchAtLogin.isEnabled { LaunchAtLogin.set(false) }
        resetSettings()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error { NSLog("Bunny: restarting after the reset failed: %@", error.localizedDescription) }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Removes every stored preference of Bunny except the keep-list, then stores the agent and
    /// Bunny tools switches as off (what a fresh install has after its first launch).
    private static func resetSettings() {
        let defaults = UserDefaults.standard
        let stored = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:)) ?? [:]
        for key in SettingsReset.keysToRemove(from: stored, keeping: resetKeepList) {
            defaults.removeObject(forKey: key)
        }
        AgentSettings.storeEverythingOff()
        defaults.synchronize()
    }

    /// Cancel is the default button (Return); the destructive one is second.
    private static func confirm(_ message: String, detail: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: action).hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }
}
