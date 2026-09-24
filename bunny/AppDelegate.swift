import AppKit
import SwiftData
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let statusBarController = StatusBarController()
    private var modelContainer: ModelContainer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        WindowManager.applyAppearance(UserDefaults.standard.string(forKey: "appearance") ?? "system")

        // Dedicated store (never the shared `Application Support/default.store`), seeded once
        // by copying the old sandboxed build's store; the originals are left as a backup.
        guard let storeURL = StoreSetup.prepare() else {
            NSApp.terminate(nil)
            return
        }
        do {
            modelContainer = try ModelContainer(for: BunnyTask.self, ShelfItem.self,
                                                configurations: ModelConfiguration(url: storeURL))
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }

        UNUserNotificationCenter.current().delegate = self
        // Bunny tools (spec §5): agents manage tasks through the local MCP server.
        BunnyToolsServer.shared.backend = BunnyToolsBackendImpl(modelContainer: modelContainer)
        BunnyToolsServer.shared.start()
        AgentSupervisor.shared.configure(modelContainer: modelContainer)
        statusBarController.setup(modelContainer: modelContainer)

        MidnightScheduler.shared.modelContext = modelContainer.mainContext
        MidnightScheduler.shared.schedule()

        if !UserDefaults.standard.bool(forKey: "onboarding.completed") {
            WindowManager.shared.showOnboarding()
        } else {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AgentSupervisor.shared.shutdownAll()
        BunnyToolsServer.shared.stop()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while Bunny is the active app (e.g. the popover is open).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Tapping an agent notification opens the popover and that task's panel.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let taskID = (response.notification.request.content.userInfo["taskID"] as? String).flatMap(UUID.init(uuidString:))
        completionHandler()
        guard let taskID else { return }
        Task { @MainActor in
            self.statusBarController.openPopover()
            PanelCoordinator.shared.open(taskID)
        }
    }
}
