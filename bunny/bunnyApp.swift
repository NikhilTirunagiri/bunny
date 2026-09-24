import SwiftUI

@main
struct BunnyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Kept so the App has a scene; ⌘, is rerouted to Bunny's own AppKit settings window.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { WindowManager.shared.showSettings() }
                    .keyboardShortcut(",")
            }
        }
    }
}
