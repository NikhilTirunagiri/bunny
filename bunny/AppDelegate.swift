import AppKit
import SwiftData
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let statusBarController = StatusBarController()
    private var modelContainer: ModelContainer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if let directory = SnapshotRunner.outputDirectory {
            SnapshotRunner.run(to: directory)
            exit(0)
        }
        #endif
        WindowManager.applyAppearance(UserDefaults.standard.string(forKey: "appearance") ?? "system")

        // Dedicated store (never the shared `Application Support/default.store`), seeded once
        // by copying the old sandboxed build's store; the originals are left as a backup.
        guard let storeURL = StoreSetup.prepare() else {
            NSApp.terminate(nil)
            return
        }
        backUpBeforeV3(storeURL)
        do {
            modelContainer = try ModelContainer(for: BunnyTask.self, ShelfItem.self,
                                                configurations: ModelConfiguration(url: storeURL))
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }

        // Before anything reads the notes: the Archive is gone.
        TaskActions.migrateArchived(in: modelContainer.mainContext)

        UNUserNotificationCenter.current().delegate = self
        // Agents are opt-in: nothing of theirs starts unless one is switched on. Bunny tools (the
        // local MCP server) listen only while they are switched on too.
        AgentEnablement.shared.migrateIfNeeded(context: modelContainer.mainContext)
        AgentSettings.migrateOpenIn()
        BunnyToolsServer.shared.backend = BunnyToolsBackendImpl(modelContainer: modelContainer)
        AgentEnablement.shared.syncToolsServer()
        AgentSupervisor.shared.configure(modelContainer: modelContainer)
        WindowManager.shared.modelContainer = modelContainer
        statusBarController.setup(modelContainer: modelContainer)

        MidnightScheduler.shared.modelContext = modelContainer.mainContext
        MidnightScheduler.shared.schedule()

        if !UserDefaults.standard.bool(forKey: WindowManager.onboardingCompletedKey) {
            WindowManager.shared.showOnboarding()
        }
    }

    /// Once, before v3 first opens the store (after any copy from the sandboxed build): keep the
    /// files as they are in `Backups/pre-v3`. A failure is logged and never blocks the launch.
    private func backUpBeforeV3(_ storeURL: URL) {
        let applicationSupport = storeURL.deletingLastPathComponent().deletingLastPathComponent()
        do {
            try StoreBackup.run(store: storeURL, directory: StoreBackup.directory(applicationSupport: applicationSupport))
        } catch {
            NSLog("Bunny: the pre-v3 backup failed: %@", error.localizedDescription)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AgentSupervisor.shared.shutdownAll()
        BunnyToolsServer.shared.stop()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while Bunny is the active app (e.g. the window is open).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Tapping an agent notification opens the window on that note.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let taskID = (response.notification.request.content.userInfo["taskID"] as? String).flatMap(UUID.init(uuidString:))
        completionHandler()
        guard let taskID else { return }
        Task { @MainActor in
            self.statusBarController.openWindow(showing: taskID)
        }
    }
}

/// Notifications are asked for the first time one is about to be needed (a timer started, a note
/// handed off), never at launch. The system shows its prompt once; later calls do nothing.
enum NotificationPermission {
    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
