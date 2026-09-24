# Settings Window & Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Settings into its own app window (with Dock presence while open) and add a first-run onboarding window; the icon redesign is tracked separately (Task C1, done by a design agent).

**Architecture:** A main-actor `WindowManager` owns reusable `NSWindow`s hosting SwiftUI views and toggles the activation policy (`.regular` while a window is open, `.accessory` otherwise). The popover's gear opens the Settings window; the in-popover settings page is removed.

**Tech Stack:** SwiftUI, AppKit, ServiceManagement, UserNotifications. Swift 5 mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, macOS 26.

**Spec:** `docs/superpowers/specs/2026-09-24-app-windows-onboarding-icon-design.md`

## Global Constraints
- No Xcode here: app code is verified by `swiftc -typecheck` against the 15.5 SDK with scratch-only stubs (see Verification sections in `.superpowers/sdd/2026-09-24-task-panel-shelf/task-4-report.md`) plus careful review; `swift test` must stay green.
- Don't edit `project.pbxproj`. New files under `bunny/` are auto-included.
- Commits: repo-local author; never add Co-Authored-By / Claude-Session / AI attribution.
- UserDefaults key `onboarding.completed` (Bool). Window sizes: Settings 560×460, Onboarding 640×520.
- Glass only on primary buttons (`.glassProminent`) and secondary (`.glass`); forms use native grouped style.

## Review Focus
1. Dock icon must disappear again after closing the last window (activation policy back to `.accessory`), including after Cmd-W and the red close button.
2. Opening Settings twice must focus the existing window, not create a second.
3. Onboarding closed early must reappear next launch; completed must never reappear automatically.
4. Removing the in-popover settings must not leave dead code paths (`ActiveView.settings`) or break the Archive toggle.
5. Agents tab must work before plan B's `AgentSettings` exists (placeholder) and after (real section).

---

### Task C2: WindowManager + Settings window

**Files:**
- Create `bunny/Controllers/WindowManager.swift`.
- Create `bunny/Views/Settings/SettingsWindowView.swift`, `GeneralSettingsView.swift`, `AboutSettingsView.swift`, and `AgentSettingsSection.swift` (the last one as a placeholder).
- Delete `bunny/Views/SettingsView.swift`.
- Modify `bunny/ContentView.swift`.

**Interfaces (Produces):**
```swift
@MainActor final class WindowManager: NSObject, NSWindowDelegate {
    static let shared: WindowManager
    enum SettingsTab: Hashable { case general, agents, about }
    var onWillShowWindow: (() -> Void)?     // StatusBarController sets this to close the popover
    func showSettings(tab: SettingsTab = .general)
    func showOnboarding()                    // Task C3 provides OnboardingView; until then this may be a no-op stub
    func closeOnboarding()
}
struct AgentSettingsSection: View   // placeholder body in this task; plan B Task 7 replaces the body
```

- [ ] **Step 1: `WindowManager`:**
```swift
import AppKit
import SwiftUI

/// Owns Bunny's real windows (Settings, Onboarding). While any is open Bunny shows in the Dock and ⌘-Tab.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    enum SettingsTab: Hashable { case general, agents, about }

    var onWillShowWindow: (() -> Void)?
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
```
  Until Task C3 lands, add a minimal `struct OnboardingView: View { var body: some View { Text("Welcome to Bunny") } }` in `bunny/Views/Onboarding/OnboardingView.swift` so the project compiles. C3 replaces it.

- [ ] **Step 2: Settings views.**
  - `SettingsWindowView`: `@Environment(SettingsSelection.self)`, `@Bindable` for the selection. A `TabView(selection: $selection.tab)` holds `GeneralSettingsView().tabItem { Label("General", systemImage: "gearshape") }.tag(.general)`, then `AgentSettingsSection()` (Agents, `sparkle`) and `AboutSettingsView()` (About, `info.circle`). The frame is `.frame(minWidth: 560, minHeight: 460)`.
  - `GeneralSettingsView`: move the launch-at-login toggle and appearance picker from the old `SettingsView` verbatim into a `Form { Section { toggle } Section("Appearance") { picker } Section { Button("Show Welcome Guide…") { WindowManager.shared.showOnboarding() } } }.formStyle(.grouped)`. The Quit button goes at the bottom: `Button("Quit Bunny", role: .destructive) { NSApp.terminate(nil) }.buttonStyle(.glass).tint(.red)`, `.padding(.horizontal, 20).padding(.bottom, 16)`.
  - `AboutSettingsView`: a centered `VStack`:
    - `Image(nsImage: NSApp.applicationIconImage)` at 128 pt
    - `Text("Bunny").font(.title.bold())`
    - version `Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"`
    - the "Made with ❤️ by" + `Link("Nikhil Tirunagiri", destination: URL(string: "https://www.nikhilt.dev")!)` line, copied from the old view
  - `AgentSettingsSection` placeholder: `ContentUnavailableView("Agents", systemImage: "sparkle", description: Text("Connect Claude Code and Codex here."))`.
- [ ] **Step 3: ContentView.**
  - Remove `.settings` from `ActiveView` and its `switch` case.
  - The gear button action becomes `WindowManager.shared.showSettings()`; its symbol is always `.secondary`, and its help is "Settings".
  - Delete `bunny/Views/SettingsView.swift` (`git rm`).
- [ ] **Step 4: StatusBarController.** In `setup`, set `WindowManager.shared.onWillShowWindow = { [weak self] in self?.closePopover() }`.
- [ ] **Step 5: Verify and commit.**
  - Typecheck the new and changed files; run `swift test`.
  - Grep that nothing references `SettingsView(` any more.
  - Commit `feat: settings in its own window with Dock presence`.

---

### Task C3: First-run onboarding

**Files:**
- Replace `bunny/Views/Onboarding/OnboardingView.swift`.
- Create `bunny/Views/Onboarding/OnboardingPages.swift`.
- Modify `bunny/AppDelegate.swift`.

**Interfaces:**
- Consumes: `WindowManager` (C2), and from plan B Task 5 `AgentSettings` and `OpenInApp`.
- Also consumes `AgentHarness` (plan B Task 1) and `ShellEnvironment.locate` (plan B Task 4).

- [ ] **Step 1: `OnboardingView`.**
  - State: `@State private var page = 0`; 4 pages.
  - Layout is a `VStack`: page content (a `Group` switch over `page`, with a `.transition(.push(from: .trailing))` animated on `page`), then a bottom bar.
  - Bottom bar:
    - A page indicator: 4 dots, 6 pt, current in `.primary`, others in `.tertiary`.
    - `Back`, disabled on page 0, `.buttonStyle(.glass)`.
    - The primary button, `.buttonStyle(.glassProminent)` with `.keyboardShortcut(.defaultAction)`. It reads `Continue` on pages 0–2 and `Start using Bunny` on page 3.
  - Finishing: `UserDefaults.standard.set(true, forKey: "onboarding.completed")`, then `WindowManager.shared.closeOnboarding()`, then `(NSApp.delegate as? AppDelegate)?.statusBarController.openPopover()`.
  - Padding 32, frame 640×520.
- [ ] **Step 2: Pages (`OnboardingPages.swift`)**, each a small `View`:
  1. `WelcomePage`:
     - App icon at 128 pt
     - `Text("Welcome to Bunny").font(.largeTitle.bold())`
     - The tagline from spec §5 in `.title3` `.secondary`, centered
  2. `TaskContextPage`: a title "Everything a task needs" and three `FeatureRow(symbol:title:detail:)` rows:
     - `sidebar.left`: "Hover for details" — "Every task opens a side panel with its description and shelf."
     - `text.alignleft`: "Describe it" — "Add notes the whole task can carry."
     - `tray.and.arrow.down`: "Shelve files" — "Drop files or folders on a task, or onto the menu-bar icon, and drag them back out anywhere."
  3. `AgentsPage`:
     - Title "Connect your agents" and a subtitle "Hand any task to Claude Code or Codex with one click."
     - One `AgentRow` per `AgentHarness`:
       - symbol, name, status (a `ProgressView` while detecting, then a green `checkmark.circle.fill` + path, or an orange "Not found" + an install hint in monospaced caption: `npm i -g @anthropic-ai/claude-code` / `npm i -g @openai/codex`)
       - a `Choose…` button → `NSOpenPanel` (files, the executable) → writes `AgentSettings.claudePath`/`codexPath`
     - Detection runs in `.task`, via `Task.detached { ShellEnvironment.locate("claude") }`, then assigns on main. It writes the setting if found and the current setting is empty.
     - `Picker("Default agent")` segmented, and `Picker("Open sessions in")` over installed `OpenInApp` cases. Both are bound to `AgentSettings` through `@State` mirrors that write on change.
  4. `FinishPage`:
     - Title "You're all set".
     - A notifications row: `Button("Enable Notifications")` → `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])`. Read the current status on appear via `notificationSettings()` and show "Notifications on" with a check when authorized.
     - A launch-at-login `Toggle`, using the same `SMAppService` logic as `GeneralSettingsView`.
     - A tip: "Tip: click the 🐇 in your menu bar any time."
- [ ] **Step 3: `AppDelegate`.**
  - After `statusBarController.setup(...)`: if `!UserDefaults.standard.bool(forKey: "onboarding.completed")`, call `WindowManager.shared.showOnboarding()`.
  - Otherwise keep the existing `requestAuthorization` call. Move that call into the `else` branch, since first-run users grant it on page 4.
- [ ] **Step 4: Verify and commit.** Typecheck with stubs for the plan B symbols if they are not yet present, and run `swift test`. Commit `feat: first-run onboarding`.
