import AppKit
import SwiftData
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let statusBarController = StatusBarController()
    private var modelContainer: ModelContainer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            modelContainer = try ModelContainer(for: BunnyTask.self, ShelfItem.self)
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }

        UNUserNotificationCenter.current().delegate = self
        AgentSupervisor.shared.configure(modelContainer: modelContainer)
        statusBarController.setup(modelContainer: modelContainer)

        MidnightScheduler.shared.modelContext = modelContainer.mainContext
        MidnightScheduler.shared.schedule()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AgentSupervisor.shared.shutdownAll()
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
