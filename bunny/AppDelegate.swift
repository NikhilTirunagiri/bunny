import AppKit
import SwiftData
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusBarController = StatusBarController()
    private var modelContainer: ModelContainer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            modelContainer = try ModelContainer(for: BunnyTask.self)
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }

        statusBarController.setup(modelContainer: modelContainer)

        MidnightScheduler.shared.modelContext = modelContainer.mainContext
        MidnightScheduler.shared.schedule()

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .provisional]) { granted, error in
            if let error { print("Notification auth error: \(error.localizedDescription)") }
            if granted { print("Notification permission granted") }
        }
    }
}
