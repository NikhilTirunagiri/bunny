import AppKit
import SwiftUI
import SwiftData
import UserNotifications
import ServiceManagement

final class StatusBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private(set) var popover: NSPopover!
    private var updateTimer: Timer?
    private var modelContext: ModelContext?
    private var lastButtonWidth: CGFloat = 0
    private var isPopoverOpen = false

    private static let monoFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
    )

    private static let menuBarIcon: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let img = NSImage(systemSymbolName: "hare.circle.fill", accessibilityDescription: "Bunny")?
            .withSymbolConfiguration(config)
        img?.isTemplate = true
        return img
    }()

    func setup(modelContainer: ModelContainer) {
        modelContext = modelContainer.mainContext

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon
            button.imagePosition = .imageOnly
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .modelContainer(modelContainer)
                .environment(AppState.shared)
                .environment(TimerManager.shared)
        )

        restorePinnedTask()
        startUpdateTimer()
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClosePopover),
            name: .bunnyClosePopover,
            object: nil
        )

        // Close the popover when the app loses focus (e.g. user clicks another
        // menu bar app).  NSPopover.transient does not detect these clicks on
        // its own because they happen in another process.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClosePopover),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func handleClosePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        isPopoverOpen = true
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        // Apply active highlight only if no green (timer-expired) highlight is showing
        if button.layer?.backgroundColor == nil {
            button.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.5).cgColor
        }
    }

    func popoverDidClose(_ notification: Notification) {
        isPopoverOpen = false
        guard let button = statusItem?.button else { return }
        // Remove active highlight.  If the green timer-expired highlight is active
        // we must preserve it — let updateMenuBarItem re-evaluate on the next tick.
        let hadGreen = button.layer?.backgroundColor != nil
            && AppState.shared.timerExpiredTaskID != nil
        if !hadGreen {
            button.layer?.backgroundColor = nil
        }
    }

    @objc func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Bunny", action: nil, keyEquivalent: "")
            .attributedTitle = NSAttributedString(
                string: "Bunny",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
            )
        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit Bunny", action: #selector(quitApp), keyEquivalent: "q")
            .target = self

        // Temporarily attach menu to the status item to display it
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("SMAppService error: \(error)")
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func restorePinnedTask() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<BunnyTask>()
        guard let all = try? context.fetch(descriptor) else { return }
        if let pinned = all.first(where: { $0.isPinned && $0.archivedAt == nil }) {
            AppState.shared.pinnedTaskID = pinned.id
        }
    }

    private func startUpdateTimer() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarItem()
        }
        RunLoop.main.add(t, forMode: .common)
        updateTimer = t
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            // Anchor the popover centered under the full button so it looks correct
            // whether or not a task is pinned (icon + text vs icon only).
            let centerX = button.bounds.midX
            let anchorRect = NSRect(x: centerX - 14, y: 0, width: 28, height: button.bounds.height)
            popover.show(relativeTo: anchorRect, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            lastButtonWidth = button.bounds.width
        }
    }

    func updateMenuBarItem() {
        guard let button = statusItem?.button else { return }
        guard let pinnedID = AppState.shared.pinnedTaskID,
              let context = modelContext else {
            setDefault(button)
            checkReposition(button)
            applyActiveHighlightIfNeeded(button)
            return
        }

        let descriptor = FetchDescriptor<BunnyTask>()
        guard let all = try? context.fetch(descriptor),
              let task = all.first(where: { $0.id == pinnedID && $0.archivedAt == nil }) else {
            AppState.shared.pinnedTaskID = nil
            setDefault(button)
            checkReposition(button)
            applyActiveHighlightIfNeeded(button)
            return
        }

        // Timer always takes priority — make sure there is room for it even with a long title.
        let timerStr = task.isTimerRunning ? "  \(task.formattedRemaining)" : ""
        let maxTitleLen = max(8, 24 - timerStr.count) // leave enough budget for the timer
        let truncated = String(task.title.prefix(maxTitleLen))

        if task.isTimerRunning {
            setPinned(button, title: "\(truncated)\(timerStr)")
            clearGreen(button)
        } else if task.isTimerExpired {
            setPinned(button, title: truncated)
            applyGreen(button)
            if AppState.shared.timerExpiredTaskID != pinnedID {
                AppState.shared.timerExpiredTaskID = pinnedID
                notify(title: task.title)
            }
        } else {
            setPinned(button, title: truncated)
            clearGreen(button)
        }
        checkReposition(button)
        applyActiveHighlightIfNeeded(button)
    }

    /// If the popover is open and no green (timer-expired) highlight is active,
    /// show a subtle background to indicate the menu bar item is selected.
    private func applyActiveHighlightIfNeeded(_ button: NSStatusBarButton) {
        guard isPopoverOpen, button.layer?.backgroundColor == nil else { return }
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.5).cgColor
    }

    /// If the popover is open and the button width has changed (e.g. user
    /// pinned/unpinned a task), smoothly reposition the popover window so it
    /// stays centered under the menu bar item.
    private func checkReposition(_ button: NSStatusBarButton) {
        guard popover.isShown else {
            lastButtonWidth = button.bounds.width
            return
        }
        let newWidth = button.bounds.width
        guard abs(newWidth - lastButtonWidth) > 0.5 else { return }

        guard let window = popover.contentViewController?.view.window else {
            lastButtonWidth = newWidth
            return
        }

        // Calculate how far the button center moved
        let deltaX = (lastButtonWidth - newWidth) / 2

        let oldFrame = window.frame
        let targetFrame = NSRect(
            x: oldFrame.origin.x + deltaX,
            y: oldFrame.origin.y,
            width: oldFrame.width,
            height: oldFrame.height
        )

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(targetFrame, display: true)
        }

        lastButtonWidth = newWidth
    }

    private func setDefault(_ button: NSStatusBarButton) {
        button.image = Self.menuBarIcon
        button.imagePosition = .imageOnly
        button.attributedTitle = attributed("")
        clearGreen(button)
    }

    private func setPinned(_ button: NSStatusBarButton, title: String) {
        button.image = Self.menuBarIcon
        button.imagePosition = .imageLeft
        button.attributedTitle = attributed(title)
    }

    private func attributed(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: Self.monoFont])
    }

    private func applyGreen(_ button: NSStatusBarButton) {
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.25).cgColor
    }

    private func clearGreen(_ button: NSStatusBarButton) {
        button.layer?.backgroundColor = nil
    }

    private func notify(title: String) {
        // Use UserNotifications.framework for proper banner delivery.
        let content = UNMutableNotificationContent()
        content.title = "Timer Complete"
        content.subtitle = title
        content.sound = nil // we play our own sound

        let request = UNNotificationRequest(
            identifier: "bunny-timer-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Notification delivery error: \(error.localizedDescription)")
            }
        }

        // Pleasant audible cue — "Glass" is a soft, brief chime
        NSSound(named: "Glass")?.play()
    }
}
