import AppKit
import SwiftUI
import SwiftData
import UserNotifications
import ServiceManagement

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private(set) var popover: NSPopover!
    private var updateTimer: Timer?
    private var modelContext: ModelContext?

    private static let monoFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
    )

    private static let menuBarIcon: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let img = NSImage(systemSymbolName: "hare.circle.fill", accessibilityDescription: "Bunny")?
            .withSymbolConfiguration(config)
        img?.isTemplate = true
        return img
    }()

    /// Fixed width keeps the popover position stable when pinned state changes.
    private static let statusItemLength: CGFloat = 180

    func setup(modelContainer: ModelContainer) {
        modelContext = modelContainer.mainContext

        statusItem = NSStatusBar.system.statusItem(withLength: Self.statusItemLength)
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
    }

    @objc private func handleClosePopover() {
        if popover.isShown {
            popover.performClose(nil)
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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
        content.title = "Timer Complete"
        content.body = "⏰  \(title)"
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)

        // Play a pleasant system sound as an audible cue
        NSSound(named: "Tink")?.play()
    }
}
