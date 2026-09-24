# Spec A — Task Side Panel, Description & Shelf (+ macOS 27 refresh)

Date: 2026-09-24 · Status: approved-by-delegation (owner asked us to make the calls)
Follow-up: Spec B (`2026-09-24-agent-handoff-design.md`) builds on this panel.

## 1. Intent

Bunny is a menu-bar task list. The owner wants each task to carry context —
a description and a **shelf** of linked files/folders — shown in a Maccy-style
panel that opens to the **left** of the popover when a task row is hovered.
This context is later handed to coding agents (Spec B), so the panel must also
be the place where agent state and questions will appear.

Success looks like:
- Hover any task (parent or subtask) → panel appears beside the popover with the
  task's title, description and shelf, all editable in place.
- Drag a file from Finder onto the Bunny menu-bar icon → popover springs open →
  drag over a task → its panel opens → drop on the shelf (or on the row) → linked.
- Drag an item out of the shelf into Finder/Slack/etc. → the app receives a copy,
  the original is untouched, and the item leaves the shelf.
- The whole app looks native on macOS 27 (Liquid Glass era), not Sequoia.

Decisions made with the owner: spring-load entry (A1), copy-out-and-remove (A2),
every task gets an editable panel (A3), panel is a separate attached window (A4).

## 2. Scope

In: data model additions, side panel window, hover/lock behavior, shelf drag
in/out, spring-loading on the status item, row badges, visual refresh of all
existing views, sandbox removal, deployment target bump, test harness.

Out (Spec B): agents, agent button, task agent states, questions UI, settings
for harnesses/open-in app.

## 3. Data model

`BunnyTask` gains:
- `taskDescription: String = ""` (not `description`, which collides with
  `CustomStringConvertible`).

New SwiftData model `ShelfItem`:

| field | type | notes |
|---|---|---|
| `id` | `UUID` | |
| `taskID` | `UUID` | owning task; mirrors the `parentID` style (no `@Relationship`) |
| `bookmark` | `Data` | `URL.bookmarkData(options: [])` — plain bookmark (app not sandboxed) |
| `displayName` | `String` | last known `lastPathComponent`, shown if unresolvable |
| `lastKnownPath` | `String` | used for dedupe and as a tooltip |
| `isDirectory` | `Bool` | for icon fallback |
| `addedAt` | `Date` | |
| `sortOrder` | `Int` | append order |

`ModelContainer(for: BunnyTask.self, ShelfItem.self)`. Both changes are
additive with defaults → SwiftData lightweight migration, no schema versioning.

Lifecycle rules:
- Archive / midnight archive: shelf items untouched (restore brings them back).
- Task deletion (currently only empty-title subtask cancel): delete its items.
- Successful external drag-out: delete the item (file untouched).
- Unresolvable bookmark (deleted file, ejected volume): item stays, rendered
  dimmed with `exclamationmark.triangle`, removable via context menu. A stale
  bookmark that still resolves is refreshed in place (new `bookmark`,
  `lastKnownPath`, `displayName`).
- Dedupe: dropping a URL whose standardized, symlink-resolved path equals an
  existing item's resolved path on the same task is ignored.

`ShelfService` (main-actor, app target) owns add/remove/resolve against a
`ModelContext`; the pure rules (path normalization, dedupe, display name,
stale-refresh decision) live in `BunnyCore` (§9) and are unit tested.

## 4. Panel window

`TaskPanelController` (AppKit, owned by `StatusBarController`):
- `TaskPanel: NSPanel`, style `[.borderless, .nonactivatingPanel]`,
  `canBecomeKey = true` (text editing), `hasShadow = true`, clear background,
  `level = .popUpMenu` (same layer as the popover), `hidesOnDeactivate = false`.
- Content: `NSHostingView(TaskPanelView)` with the same `.modelContainer` and
  environment objects as the popover.
- Attached with `popoverWindow.addChildWindow(panel, ordered: .above)` so it
  follows the popover; removed/ordered out when the popover closes.
- Geometry (pure function `PanelPlacement.frame(...)` in `BunnyCore`):
  width 300 pt, height = popover content height, top edges aligned,
  8 pt gap to the popover's left edge. If that would cross the screen's
  `visibleFrame.minX`, place it on the right of the popover instead; if neither
  fits, overlap-clamp inside the visible frame.

### 4.1 Showing / hiding (hover model)

State lives in `AppState`: `panelTaskID: UUID?`, `panelLocked: Bool`.
A pure `HoverIntent` state machine (in `BunnyCore`, clock-injected) decides:

| event | effect |
|---|---|
| row hover enter, panel hidden | show after **350 ms** dwell (cancelled if pointer leaves first) |
| row hover enter, panel visible | switch to that task **immediately** |
| pointer leaves rows and panel | hide after **250 ms** grace (cancelled on re-entry into any row or the panel) |
| pointer inside panel | never hides |
| panel text field/editor focused | never hides until focus leaves |
| single click on a row's empty area | **lock** panel to that task (`panelLocked = true`); stays until another row is clicked, Esc, or popover closes. Clicking the locked row again unlocks. |
| file drag enters a row (`isTargeted`) | show that task immediately (no dwell) — hover events do not fire during drags |
| popover closes | hide, clear lock |

Locking is also what Spec B uses for "click the yellow task to answer".

### 4.2 Popover closing behavior

`.transient` popovers close on clicks in other windows, including our own child
panel. Change `popover.behavior` to `.applicationDefined` and close explicitly:
- global monitor for `.leftMouseDown/.rightMouseDown` (clicks in other apps) → close;
- local monitor: clicks inside the popover or panel windows (or their sheets/
  child popovers such as the timer picker) are ignored; others close;
- status item click toggles as today; Esc in the popover closes it (Esc in the
  panel first clears a lock, second Esc closes).
- Closing the popover orders the panel out.

## 5. Shelf

### 5.1 UI (inside `TaskPanelView`)
- Header row: `Shelf` label + item count.
- Items: vertical list, each row = 20 pt Finder icon
  (`NSWorkspace.shared.icon(forFile:)`, cached), name, secondary line with the
  abbreviated parent path (`~/…`). Hover highlight. Missing items dimmed with a
  warning glyph and "Missing" subtitle.
- Double-click → `NSWorkspace.open`. Context menu: Open, Reveal in Finder,
  Copy Path, Remove from Shelf.
- Drop zone: the whole shelf section accepts drops; when empty it shows a dashed
  rounded "Drop files or folders here" placeholder; when targeted it highlights.

### 5.2 Drag in
- Accepted type: `.fileURL` (multiple items per drop). Sources: Finder, other
  apps, another Bunny task's shelf.
- Drop targets: the panel's shelf section, and every `TaskRowView` (drop onto a
  row adds to that task's shelf and flashes the row's shelf badge).
- Task reordering currently uses a `String` payload; it moves to a private
  pasteboard type (`com.nikhiltirunagiri.bunny.task-id`) so a Finder drag
  (which also carries text) can never be mistaken for a reorder.

### 5.3 Spring-loading on the status item
- Register the status item button's window for `.fileURL` and set a dragging
  handler on it (window delegate implementing `NSDraggingDestination`). On
  `draggingEntered`, open the popover (no drop is accepted on the icon itself;
  the user continues the drag into the popover). If the window-delegate route
  fails on the target OS, fall back to a transparent `NSView` overlay on the
  button that returns `nil` from `hitTest` for mouse events but is registered
  for dragged types.

### 5.4 Drag out
Shelf rows use an AppKit drag source (`NSViewRepresentable` wrapping an
`NSView` that starts `beginDraggingSession` with an `NSDraggingItem` whose
pasteboard writer is the resolved file `URL`, image = file icon):
- `sourceOperationMaskFor .outsideApplication` → `.copy` only, so Finder copies
  (never moves) the original.
- `sourceOperationMaskFor .withinApplication` → `.move` (moving an item to
  another task's shelf).
- `endedAt operation:` non-empty → delete the `ShelfItem` from its task.
  Dropping back on the **same** task's shelf is rejected by the drop handler
  (dedupe → returns false → operation none) so the item is not lost.
- Missing (unresolvable) items are not draggable.

## 6. Row changes (`TaskRowView`)
- Tiny badges after the title: `text.alignleft` when the description is
  non-empty, `paperclip` + count when the shelf is non-empty (secondary color,
  10 pt). They make context visible without hovering.
- Hover background highlight on rows (rounded, concentric with the popover).
- Row reports hover enter/exit and click-to-lock to `AppState`/`HoverIntent`.
- Right-side button order stays timer · add-subtask · pin · archive; Spec B
  inserts the agent button between pin and archive.

## 7. Panel content layout (`TaskPanelView`)
Top to bottom, 16 pt padding:
1. Title — `TextField`, 17 pt semibold, commits on submit/blur; empty title
   reverts. Subtasks show a small "in <parent title>" breadcrumb above.
2. Meta line — timer state (e.g. "25:00 left"), subtask count for parents.
3. Description — `TextEditor`, 13 pt, placeholder "Add a description…",
   saves on every change (SwiftData autosave), grows to ~40% of panel height,
   then scrolls.
4. Shelf (§5).
5. Reserved bottom region (empty in A) where Spec B mounts agent status,
   questions and "Chat about this".

## 8. Visual refresh (macOS 27 "Golden Gate")

Goal: native Liquid Glass look, consistent in light/dark. macOS 27 keeps
Tahoe's glass but uses calmer, standardized corner radii, cleaner menus (fewer
decorative symbols) and sparing "glass bounce" feedback. Reference notes:
`docs/superpowers/research/macos27-design.md`.
- Raise `MACOSX_DEPLOYMENT_TARGET` to **26.0** (owner runs macOS 27) so glass
  APIs (`glassEffect`, `Glass`, `GlassEffectContainer`, `.buttonStyle(.glass)`,
  `.glassProminent`, `ConcentricRectangle`, `NSGlassEffectView`) need no
  availability branches. Nothing macOS-27-only is required.
- Glass belongs to chrome, never content, and never glass on glass.
  Popover: the system popover chrome is the glass surface — remove any opaque
  backgrounds that fight it. Side panel: exactly one `NSGlassEffectView` as the
  panel's root (corner radius matched to the popover); everything inside uses
  plain fills (`.quaternary` / `.fill.tertiary`) and vibrancy, not more glass.
- Controls: system `Toggle`/`Picker`/`TextField` render natively (no reskin).
  Bottom-bar icon buttons: `.buttonStyle(.glass)` in a `GlassEffectContainer`,
  circular. Primary actions (`Start` in the timer picker, `Send` answer in Spec B)
  use `.glassProminent`. `Glass.interactive()` only on those primaries.
- Rows: hover/selection background is a `ConcentricRectangle` fill inset
  6–8 pt from the popover edge (via `.containerShape`), no hard dividers
  between rows.
- New-task field: rounded fill background, leading `plus` symbol, 14 pt.
- Typography: system defaults; task title 14 pt regular, secondary text uses
  `.secondary`; section headers 11 pt semibold `.secondary` (no all-caps).
- SF Symbols: `.contentTransition(.symbolEffect(.replace))` on checkbox/pin
  toggles; `.symbolEffect(.bounce)` on add/drop confirmation; context menus
  without decorative icons (macOS 27 style).
- Settings and Archive adopt the same grouped rounded sections
  (`Form { … }.formStyle(.grouped)` in Settings).

## 9. Code organization & testing

- New folder `bunny/Core/` — Foundation-only, no SwiftData/AppKit. Compiled
  into the app (file-system-synchronized group) **and** by a root
  `Package.swift` (`BunnyCore` library target, `path: "bunny/Core"`) with a
  `BunnyCoreTests` swift-testing target in `Tests/BunnyCoreTests`. Runs with
  `swift test` using only the Command Line Tools.
- Core units in A: `PanelPlacement`, `HoverIntent`, `ShelfRules`
  (normalize/dedupe/display name/abbreviated path).
- App-side units: `ShelfItem` (model), `ShelfService`, `TaskPanelController`,
  `TaskPanel`, `TaskPanelView`, `ShelfView`, `ShelfItemDragSource`,
  `StatusItemDropHandler`, updates to `StatusBarController`, `AppState`,
  `TaskRowView`, `ContentView`, `ArchiveView`, `SettingsView`,
  `TimerPickerView`, `AppDelegate`.
- Build config: `ENABLE_APP_SANDBOX = NO`, drop `ENABLE_USER_SELECTED_FILES`,
  keep hardened runtime, deployment target 26.0.
- Verification limits: this machine currently has only the Command Line Tools
  (no Xcode), so app-target code cannot be compiled here until Xcode is
  installed. Core is fully tested via `swift test`; app code is reviewed
  against the SDK and must be built in Xcode before merge.

## 10. Error handling
- Bookmark creation failure on drop → skip that URL, show a brief inline
  "Couldn't add <name>" in the shelf header for 3 s.
- Resolution failure → "missing" state (never crashes, never auto-deletes).
- Drag-out of a file that vanished mid-drag → drag simply fails; item stays.
- Panel geometry with no screen (popover not shown) → panel not shown.
