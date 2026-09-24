# Spec C — App Icon, Settings Window, First-Run Onboarding

Date: 2026-09-24 · Status: approved-by-delegation (owner: "make the best choices")
Builds on Spec A (UI refresh) and Spec B (agents: `AgentSettings`, `ShellEnvironment`).

## 1. Intent (owner's words)
- "Design a better logo … use the same rabbit … don't mess with the menu bar icon, only the app icon I see in the Dock."
- "Onboarding setup on first install."
- "Settings can be the app window but not in the menu bar, because it's a lot of stuff we are adding."

## 2. App icon
- Keep the hare silhouette (`bunnyicon.icon/Assets/Group.svg`); redesign the
  Icon Composer document `bunny/bunnyicon.icon` with a richer gradient
  background, the hare as a luminous glass hero layer, and one minimal
  supporting layer (speed streaks or a check badge). Light/dark/tinted variants.
- Menu-bar `hare.circle.fill` status icon is unchanged.
- Preview: `docs/superpowers/research/app-icon-preview.png` (approximation;
  the real render comes from Xcode's asset compiler).

## 3. Windows & Dock presence
Bunny stays a menu-bar (accessory) app. A `WindowManager` (main actor) owns
two optional windows — Settings and Onboarding — each an `NSWindow` hosting
SwiftUI (`NSHostingController`), titled, closable, full-size content view,
transparent titlebar, centered on first show, reused if already open.
- While any Bunny window is open: `NSApp.setActivationPolicy(.regular)` (the
  new icon appears in the Dock and ⌘-Tab) and `NSApp.activate()`.
- When the last one closes (`windowWillClose`): back to `.accessory`.
- Opening a window closes the popover.

## 4. Settings window
- Opened from the popover's gear button (the in-popover settings page is
  removed; `ContentView` keeps only Tasks/Archive) and from onboarding.
- `SettingsWindowView`: `TabView` with three tabs, 560×460 pt:
  - **General** — Launch at login, Appearance (System/Light/Dark),
    "Show Welcome Guide…" (reopens onboarding), Quit Bunny.
  - **Agents** — `AgentSettingsSection` (Spec B §8: default agent, CLI paths
    with detect + status, autonomy, open sessions in, default workspace).
  - **About** — large app icon, name, version (from bundle
    `CFBundleShortVersionString`), "Made with ❤️ by Nikhil Tirunagiri" link.
- `Form { … }.formStyle(.grouped)` per tab; native controls (glass is system-provided).

## 5. Onboarding (first run)
- Shown at launch when `UserDefaults` bool `onboarding.completed` is false;
  reopenable from Settings → General.
- 640×520 pt window, four pages with a page indicator and Back/Continue
  (`.glassProminent` primary):
  1. **Welcome** — large app icon, "Welcome to Bunny", one-line tagline:
     "Your tasks live in the menu bar. Hand them to Claude Code or Codex when
     you're ready."
  2. **Everything a task needs** — three rows with SF Symbols: hover a task for
     its side panel; add a description; drop files/folders on the shelf (also by
     dragging onto the menu-bar icon).
  3. **Connect your agents** — rows for Claude Code and Codex: detected path
     (via `ShellEnvironment.locate`, off-main) with a green check / "Not found"
     + install hint (`npm i -g @anthropic-ai/claude-code`, `npm i -g @openai/codex`)
     + "Choose…" to pick a binary; default agent picker; "Open sessions in"
     picker (installed apps only). Writes `AgentSettings`.
  4. **You're set** — Notifications: "Enable notifications" button
     (requests authorization, shows granted state); Launch at login toggle;
     primary "Start using Bunny" → sets `onboarding.completed = true`, closes
     the window, opens the popover.
- Closing the window early does not mark it complete (it shows again next launch).
- The launch-time notification authorization request moves into onboarding
  page 4 for first-run users; returning users keep the silent request at launch.

## 6. Testing
Pure pieces (page model: next/back bounds, completion flag) are small enough
to live in the view; no Core additions. Verified by static review + the Xcode
build. Manual QA: first launch shows onboarding; Dock icon appears only while
a window is open; gear opens Settings window; closing restores menu-bar-only.
