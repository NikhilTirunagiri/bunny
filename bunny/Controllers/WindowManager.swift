import AppKit
import SwiftData
import SwiftUI

/// Owns Bunny's real windows (Settings, Onboarding). While any is open Bunny shows in the Dock and ⌘-Tab.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    private static let settingsSize = NSSize(width: 780, height: 540)
    private static let settingsMinSize = NSSize(width: 680, height: 420)

    /// The notes store, for Settings → Data. Set at launch.
    var modelContainer: ModelContainer?
    var onWillShowWindow: (() -> Void)?
    /// Set by `StatusBarController`; called when onboarding finishes so the popover opens.
    /// (`NSApp.delegate as? AppDelegate` is nil under `@NSApplicationDelegateAdaptor`.)
    var onFinishOnboarding: (() -> Void)?
    private var settingsWindow: SettingsWindow?
    private var onboardingWindow: NSWindow?
    private let settingsModel = SettingsModel()

    /// Shows the one Settings window, on `page` or where it was left.
    func showSettings(page: SettingsCatalog.Page? = nil) {
        guard let modelContainer else { return }
        if let page { settingsModel.page = page }
        let window = settingsWindow ?? makeSettingsWindow(
            root: SettingsView().environment(settingsModel).modelContainer(modelContainer))
        settingsWindow = window
        // Every open starts with nothing focused, whatever was being edited when it closed.
        if !window.isVisible { window.dropFocus() }
        present(window)
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
        window.setFrameAutosaveName("BunnySettings")
        return window
    }

    func showOnboarding() {
        let window = onboardingWindow ?? makeWindow(
            title: "Welcome to Bunny",
            size: NSSize(width: 640, height: 520),
            root: OnboardingView()
        )
        onboardingWindow = window
        present(window)
    }

    func closeOnboarding() { onboardingWindow?.close() }

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
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(size)
        window.center()
        window.delegate = self
        return window
    }

    private func present(_ window: NSWindow) {
        onWillShowWindow?()
        NSApp.setActivationPolicy(.regular)
        // Order the window in only after Bunny is a regular, active app. Ordered in while still an
        // accessory, it joins another app's full-screen Space and floats above that app for good.
        DispatchQueue.main.async {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        let others = [settingsWindow, onboardingWindow].compactMap { $0 }.filter { $0 !== closing && $0.isVisible }
        if others.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
