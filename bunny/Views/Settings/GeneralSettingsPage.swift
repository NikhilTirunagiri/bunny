import AppKit
import SwiftUI

struct GeneralSettingsPage: View {
    @Environment(\.settingsLive) private var live
    @AppStorage(StatusBarController.showPinnedNoteKey) private var showPinnedNote = true
    @State private var launchAtLogin = false
    @State private var shortcutMessage: String?

    var body: some View {
        SettingsCard {
            SettingsRow(.launchAtLogin, caption: "Start Bunny when you log in.") {
                SettingsSwitch(isOn: launchAtLoginBinding)
            }
            SettingsRow(.globalShortcut, caption: "Opens Bunny from any app, ready for a new note.") {
                ShortcutRecorder(message: $shortcutMessage)
            } detail: {
                if let shortcutMessage { SettingsNote(shortcutMessage, color: .orange) }
            }
            SettingsRow(.menuBarNote, caption: "Off: the menu bar shows only the icon.") {
                SettingsSwitch(isOn: $showPinnedNote)
            }
            SettingsRow(.welcomeGuide, caption: "A short tour of what Bunny does.") {
                Button("Open") { WindowManager.shared.showOnboarding() }
                    .buttonStyle(.bunny)
            }
        }
        SettingsCard {
            SettingsRow(.quit, caption: "Running agents are stopped first.") {
                HStack(spacing: 8) {
                    Text("⌘Q")
                        .font(.callout)
                        .foregroundStyle(BunnyTheme.secondary)
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(.bunny)
                }
            }
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
        // The status item's menu toggles it too.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                guard live else { return }
                LaunchAtLogin.set(enabled)
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        )
    }
}
