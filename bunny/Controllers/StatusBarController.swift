import AppKit
import SwiftData
import UserNotifications

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var updateTimer: Timer?
    private var modelContext: ModelContext?
    private var windowController: MainWindowController?
    /// Up to when finished timers have been announced (`TimerRules.justExpired`).
    private var lastTimerCheck = Date()

    /// "Show the pinned note in the menu bar" (Settings → General). Default on; off = icon only.
    static let showPinnedNoteKey = "menuBar.showPinnedNote"

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

    /// Shown while an agent needs input: the hare in `labelColor` plus a yellow dot (non-template, so the dot keeps its color).
    private static let attentionIcon: NSImage? = {
        guard let symbol = menuBarIcon else { return nil }
        let size = symbol.size
        let dotDiameter: CGFloat = 6
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            // Tint the template's alpha mask with the current appearance's label color.
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)

            let dot = NSRect(x: rect.maxX - dotDiameter, y: rect.maxY - dotDiameter, width: dotDiameter, height: dotDiameter)
            // Punch a thin gap around the dot so it reads against the filled circle.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemYellow.set()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Bunny — an agent needs your input"
        return image
    }()

    private var currentIcon: NSImage? {
        AgentSupervisor.shared.attentionCount > 0 ? (Self.attentionIcon ?? Self.menuBarIcon) : Self.menuBarIcon
    }

    func setup(modelContainer: ModelContainer) {
        modelContext = modelContainer.mainContext

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = Self.menuBarIcon
        button.imagePosition = .imageOnly
        button.action = #selector(toggleWindow)
        button.target = self

        let dropView = StatusItemDropView(frame: button.bounds)
        dropView.onDragEntered = { [weak self] in self?.openWindow() }
        dropView.onClick = { [weak self] in self?.toggleWindow() }
        dropView.onRightClick = { [weak self] in self?.showMenu() }
        button.addSubview(dropView)

        windowController = MainWindowController(modelContainer: modelContainer, statusButton: button)
        WindowManager.shared.onWillShowWindow = { [weak self] in self?.closeWindow() }
        WindowManager.shared.onFinishOnboarding = { [weak self] in self?.openWindow() }
        GlobalHotKey.shared.onPress = { [weak self] in self?.windowController?.toggleFromShortcut() }
        GlobalHotKey.shared.registerStored()

        restorePinnedTask()
        startUpdateTimer()
    }

    private func restorePinnedTask() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<BunnyTask>()
        guard let all = try? context.fetch(descriptor) else { return }
        if let pinned = all.first(where: { $0.isPinned && $0.deletedAt == nil }) {
            AppState.shared.pinnedTaskID = pinned.id
        }
    }

    private func startUpdateTimer() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMenuBarItem()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        updateTimer = t
    }

    @objc func toggleWindow() {
        windowController?.toggle()
    }

    /// Right click on the status item. The menu is attached only while it is open: a status item
    /// that keeps a menu shows it on every click.
    private func showMenu() {
        closeWindow()
        let menu = NSMenu()
        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Bunny", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.set(!LaunchAtLogin.isEnabled) }
    @objc private func showSettings() { WindowManager.shared.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    func openWindow() {
        windowController?.openWindow()
    }

    /// Opens the window on one note (agent notification).
    func openWindow(showing taskID: UUID) {
        windowController?.openWindow(showing: taskID)
    }

    func closeWindow() {
        windowController?.closeWindow()
    }

    func updateMenuBarItem() {
        notifyFinishedTimers()
        guard let button = statusItem?.button else { return }
        guard let pinnedID = AppState.shared.pinnedTaskID,
              let context = modelContext else {
            setDefault(button)
            return
        }

        let descriptor = FetchDescriptor<BunnyTask>()
        guard let all = try? context.fetch(descriptor),
              let task = all.first(where: { $0.id == pinnedID && $0.deletedAt == nil }) else {
            AppState.shared.pinnedTaskID = nil
            setDefault(button)
            return
        }

        // The note stays pinned; it is only not written out.
        guard UserDefaults.standard.object(forKey: Self.showPinnedNoteKey) as? Bool ?? true else {
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
        } else {
            setPinned(button, title: truncated)
            clearGreen(button)
        }
    }

    private func setDefault(_ button: NSStatusBarButton) {
        button.image = currentIcon
        button.imagePosition = .imageOnly
        button.attributedTitle = attributed("")
        clearGreen(button)
    }

    private func setPinned(_ button: NSStatusBarButton, title: String) {
        button.image = currentIcon
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

    /// "Timer complete", once for every note in the list whose timer just ran out, shown in the menu
    /// bar or not.
    private func notifyFinishedTimers() {
        let now = Date()
        defer { lastTimerCheck = now }
        let started = FetchDescriptor<BunnyTask>(predicate: #Predicate { $0.timerStartedAt != nil })
        let live = ((try? modelContext?.fetch(started)) ?? []).filter(\.isLive)
        let timers = live.compactMap { task -> TimerRules.Started? in
            guard let startedAt = task.timerStartedAt, let duration = task.timerDuration else { return nil }
            return TimerRules.Started(id: task.id, startedAt: startedAt, duration: duration)
        }
        let finished = Set(TimerRules.justExpired(timers, since: lastTimerCheck, now: now))
        for task in live where finished.contains(task.id) { notify(title: task.title) }
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
