import AppKit
import SwiftUI
import SwiftData
import UserNotifications

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private(set) var popover: NSPopover!
    private var updateTimer: Timer?
    private var modelContext: ModelContext?
    private var panelController: TaskPanelController!
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private static let monoFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
    )

    private static let menuBarIcon: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
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
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        // Closed explicitly (global click monitor, Esc, status item) so clicks in the side panel don't dismiss it.
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .modelContainer(modelContainer)
                .environment(AppState.shared)
                .environment(TimerManager.shared)
                .environment(PanelCoordinator.shared)
        )

        panelController = TaskPanelController(modelContainer: modelContainer)
        PanelCoordinator.shared.onClosePopover = { [weak self] in self?.closePopover() }

        restorePinnedTask()
        startUpdateTimer()
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
        popover.isShown ? closePopover() : openPopover()
    }

    func openPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.makeKey()
            panelController.attach(to: window)
        }
        installMonitors()
    }

    func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        removeMonitors()
        PanelCoordinator.shared.popoverClosed()
        panelController.hide()
    }

    // MARK: - Event monitors

    private func installMonitors() {
        removeMonitors()
        // Clicks in other apps close the popover (mouse-down global monitors need no Accessibility permission).
        // Clicks on our own status item are delivered to this app, so the global monitor doesn't see them.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.closePopover()
            }
        }
        // Esc: unlock the panel, then close. Leave Esc alone while a text field is being edited.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard event.keyCode == 53 else { return false }
                if event.window?.firstResponder is NSTextView { return false }
                PanelCoordinator.shared.escape()
                return true
            }
            return consumed ? nil : event
        }
    }

    private func removeMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    func updateMenuBarItem() {
        guard let button = statusItem?.button else { return }
        guard let pinnedID = AppState.shared.pinnedTaskID,
              let context = modelContext else {
            setDefault(button)
            return
        }

        let descriptor = FetchDescriptor<BunnyTask>()
        guard let all = try? context.fetch(descriptor),
              let task = all.first(where: { $0.id == pinnedID && $0.archivedAt == nil }) else {
            AppState.shared.pinnedTaskID = nil
            setDefault(button)
            return
        }

        let truncated = String(task.title.prefix(20))

        if task.isTimerRunning {
            setPinned(button, title: "\(truncated)  \(task.formattedRemaining)")
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
        let content = UNMutableNotificationContent()
        content.title = "Timer complete"
        content.body = title
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
