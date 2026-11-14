import AppKit
import SwiftData
import SwiftUI

/// Owns Bunny's real windows (Settings, Onboarding). While any is open Bunny shows in the Dock and ⌘-Tab.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    private static let settingsSize = NSSize(width: 780, height: 540)
    private static let settingsMinSize = NSSize(width: 680, height: 420)
    private static let settingsFrameName = "BunnySettings"
    /// Where AppKit stores the Settings window's frame in the preferences.
    static let settingsFrameKey = "NSWindow Frame \(settingsFrameName)"
    static let onboardingCompletedKey = "onboarding.completed"

    /// The notes store, for Settings → Data. Set at launch.
    var modelContainer: ModelContainer?
    var onWillShowWindow: (() -> Void)?
    /// Set by `StatusBarController`; called when onboarding finishes so the popover opens.
    /// (`NSApp.delegate as? AppDelegate` is nil under `@NSApplicationDelegateAdaptor`.)
    var onFinishOnboarding: (() -> Void)?
    private var settingsWindow: SettingsWindow?
    private var onboardingWindow: NSWindow?
    private let settingsModel = SettingsModel()

    /// Shows the Settings window, on `page` or where it was left. A closed window is never shown
    /// again (see `present`): each open after a close makes a new one, at the remembered frame.
    func showSettings(page: SettingsCatalog.Page? = nil) {
        guard let modelContainer else { return }
        if let page { settingsModel.page = page }
        present(self.settingsWindow) { [self] in
            let window = makeSettingsWindow(
                root: SettingsView().environment(settingsModel).modelContainer(modelContainer))
            settingsWindow = window
            // Every open starts with nothing focused.
            window.dropFocus()
            return window
        }
    }

    /// Resizable, with the size and place remembered; the page title stands in for the window title.
    private func makeSettingsWindow<V: View>(root: V) -> SettingsWindow {
        let window = configure(SettingsWindow(contentRect: NSRect(origin: .zero, size: Self.settingsSize),
                                              styleMask: Self.style, backing: .buffered, defer: false),
                               title: "Bunny Settings", size: Self.settingsSize, root: root)
        window.styleMask.insert(.resizable)
        window.titleVisibility = .hidden
        // The window's size is the user's, not the content's.
        (window.contentViewController as? NSHostingController<V>)?.sizingOptions = []
        window.contentMinSize = Self.settingsMinSize
        window.setContentSize(Self.settingsSize)
        window.center()
        // The closed window gave the name up (`windowWillClose`).
        window.setFrameUsingName(Self.settingsFrameName)
        window.setFrameAutosaveName(Self.settingsFrameName)
        return window
    }

    func showOnboarding() {
        present(self.onboardingWindow) { [self] in
            let window = makeWindow(title: "Welcome to Bunny", size: OnboardingView.size, root: OnboardingView())
            onboardingWindow = window
            return window
        }
    }

    /// Skip and "Start using Bunny" (`openMainWindow`). Closing by any means marks the welcome as
    /// done (`windowWillClose`), so it never comes back by itself.
    func closeOnboarding(openMainWindow: Bool) {
        onboardingWindow?.close()
        if openMainWindow { onFinishOnboarding?() }
    }

    /// Applies the "appearance" setting ("system" / "light" / "dark") to every Bunny window
    /// (Settings, Onboarding, the task panel). The popover also follows it via `ContentView`.
    static func applyAppearance(_ value: String) {
        switch value {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    private static let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]

    private func makeWindow<V: View>(title: String, size: NSSize, root: V) -> NSWindow {
        configure(NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: Self.style,
                           backing: .buffered, defer: false),
                  title: title, size: size, root: root)
    }

    private func configure<W: NSWindow, V: View>(_ window: W, title: String, size: NSSize, root: V) -> W {
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // A normal window of a regular app: it lives on a desktop Space and never joins another
        // app's full-screen Space (no `.fullScreenAuxiliary`, `.canJoinAllSpaces` or
        // `.moveToActiveSpace`), so showing it switches to a desktop Space.
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenNone]
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(size)
        window.center()
        window.delegate = self
        return window
    }

    /// Brings `open` to the front, or makes the window when there is none. A window is created and
    /// ordered in only after Bunny is a regular, active app: made or ordered in while still an
    /// accessory, it joins another app's full-screen Space and floats above that app. A window stays
    /// tied to the Space it was last shown in, which is why a closed one is dropped
    /// (`windowWillClose`) instead of shown again.
    private func present(_ open: @autoclosure @escaping @MainActor () -> NSWindow?, make: @escaping @MainActor () -> NSWindow) {
        onWillShowWindow?()
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            // Not the cooperative `activate()`: opened by a shortcut from the non-activating main
            // window, that one may be refused, and Settings then opens on another Space unseen.
            NSApp.activate(ignoringOtherApps: true)
            (open() ?? make()).makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === settingsWindow {
            closing.saveFrame(usingName: Self.settingsFrameName)
            closing.setFrameAutosaveName("")
            settingsWindow = nil
        } else if closing === onboardingWindow {
            UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
            onboardingWindow = nil
        }
        // The window is let go once its close has finished.
        DispatchQueue.main.async { _ = closing }
        let others = [settingsWindow, onboardingWindow].compactMap { $0 }.filter { $0.isVisible }
        if others.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
