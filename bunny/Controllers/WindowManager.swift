import AppKit
import SwiftUI
import Observation

/// Owns Bunny's real windows (Settings, Onboarding). While any is open Bunny shows in the Dock and ⌘-Tab.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    enum SettingsTab: Hashable { case general, agents, about }

    var onWillShowWindow: (() -> Void)?
    /// Set by `StatusBarController`; called when onboarding finishes so the popover opens.
    /// (`NSApp.delegate as? AppDelegate` is nil under `@NSApplicationDelegateAdaptor`.)
    var onFinishOnboarding: (() -> Void)?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let settingsSelection = SettingsSelection()

    func showSettings(tab: SettingsTab = .general) {
        settingsSelection.tab = tab
        let window = settingsWindow ?? makeWindow(
            title: "Bunny Settings",
            size: NSSize(width: 560, height: 460),
            root: SettingsWindowView().environment(settingsSelection)
        )
        settingsWindow = window
        present(window)
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

    private func makeWindow<V: View>(title: String, size: NSSize, root: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        let others = [settingsWindow, onboardingWindow].compactMap { $0 }.filter { $0 !== closing && $0.isVisible }
        if others.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor @Observable
final class SettingsSelection {
    var tab: WindowManager.SettingsTab = .general
}
