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
            // SwiftUI's menu for a Settings-only app has Quit and Edit but no Close: ⌘W for the
            // Settings and Welcome windows. (The main window is not closable and takes no ⌘W.)
            CommandGroup(before: .windowSize) {
                Button("Close") {
                    if let window = NSApp.keyWindow, window.styleMask.contains(.closable) { window.performClose(nil) }
                }
                .keyboardShortcut("w")
            }
        }
    }
}
