# Task Side Panel & Shelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hovering a Bunny task opens an attached glass panel to the left of the popover with editable title, description and a drag-in/drag-out file shelf; app restyled for macOS 27.

**Architecture:** Pure logic (panel geometry, hover state machine, shelf path rules) lives in `bunny/Core/` and is unit-tested through a root SwiftPM package. AppKit owns windows (`TaskPanel` child window of the popover, status-item drop view, drag source); SwiftUI renders content; SwiftData stores `ShelfItem`s keyed by task UUID.

**Tech Stack:** Swift 5 mode, SwiftUI, AppKit, SwiftData, macOS 26.0 deployment target, swift-testing.

**Spec:** `docs/superpowers/specs/2026-09-24-task-panel-shelf-design.md`

## Global Constraints

- Deployment target `MACOSX_DEPLOYMENT_TARGET = 26.0` for the app target; `ENABLE_APP_SANDBOX = NO`.
- `bunny/Core/*.swift`: `import Foundation` / `CoreGraphics` only. No SwiftUI, AppKit, SwiftData. Must compile in Swift 5 language mode.
- The Xcode project uses file-system-synchronized groups: any new file under `bunny/` is automatically in the app target. **Do not edit `project.pbxproj` except where a task says so.**
- This machine has NO Xcode. Only `swift test` (Core) can be executed. App-target code cannot be compiled here — write it carefully against the macOS 26 SDK APIs named in this plan, and self-review every symbol you use.
- Commits: author is the repo-local identity (already configured). Never add `Co-Authored-By`, `Claude-Session` or any AI attribution to commit messages.
- Panel width 300 pt, gap 8 pt, dwell 350 ms, grace 250 ms.
- Glass: one glass surface per window; never glass on glass; system controls render natively.
- Visual/copy: placeholder "Add a description…", shelf empty text "Drop files or folders here", missing subtitle "Missing".

## Review Focus

1. Dropping the same file twice, or a symlink to an already-shelved file → one item only (Task 2 test `duplicateViaSymlink`).
2. A file deleted/moved after shelving → item shows Missing (deleted) or follows the move (bookmark) and never crashes (Task 3 `ShelfService.resolve` handles `nil`).
3. Dragging a shelf item back onto its own shelf must not delete it (Task 5: drop handler returns `false` for duplicates → operation none).
4. Popover near the left screen edge (external display arrangement) → panel flips right (Task 2 test `flipsRightWhenNoRoomLeft`).
5. Typing in the description then moving the pointer off the panel must not hide the panel mid-edit (Task 2 test `editingBlocksHide`).

## File Map

| File | Responsibility | Task |
|---|---|---|
| `Package.swift` (root) | SwiftPM package exposing `bunny/Core` for tests | 1 |
| `Tests/BunnyCoreTests/*.swift` | swift-testing tests | 2 (+B) |
| `bunny/Core/PanelPlacement.swift` | panel frame math | 2 |
| `bunny/Core/HoverIntent.swift` | show/hide/lock state machine | 2 |
| `bunny/Core/ShelfRules.swift` | path normalize, dedupe, display strings | 2 |
| `bunny/Models/BunnyTask.swift` | + `taskDescription` | 3 |
| `bunny/Models/ShelfItem.swift` | SwiftData model | 3 |
| `bunny/Controllers/ShelfService.swift` | add/remove/resolve shelf items | 3 |
| `bunny/Controllers/PanelCoordinator.swift` | drives HoverIntent with timers, observable shown/locked ids | 4 |
| `bunny/Controllers/TaskPanelController.swift` + `bunny/Views/Panel/TaskPanel.swift` | NSPanel window, placement, attach to popover | 4 |
| `bunny/Controllers/StatusBarController.swift` | applicationDefined popover, monitors, Esc, panel wiring | 4 |
| `bunny/Views/Panel/TaskPanelView.swift` | panel SwiftUI content | 5 |
| `bunny/Views/Panel/ShelfView.swift` | shelf list, drop zone | 5 |
| `bunny/Views/Panel/ShelfItemDragSource.swift` | AppKit drag source / click / menu handling | 5 |
| `bunny/Controllers/StatusItemDropView.swift` | spring-loading on the menu bar icon | 6 |
| `bunny/Views/TaskRowView.swift`, `ContentView.swift`, `ArchiveView.swift`, `SettingsView.swift`, `TimerPickerView.swift` | hover hooks (4), drop + badges (5), restyle (7) | 4,5,7 |

---

### Task 1: Build configuration & test package

**Files:**
- Modify: `bunny.xcodeproj/project.pbxproj` (target build settings for Debug & Release)
- Create: `Package.swift`, `bunny/Core/.gitkeep` → replaced by real files in Task 2, `Tests/BunnyCoreTests/SmokeTests.swift`
- Modify: `.gitignore` (append `.build/`, `.swiftpm/`)

**Interfaces:** Produces the `BunnyCore` SwiftPM target (path `bunny/Core`) and `BunnyCoreTests`.

- [ ] **Step 1: Edit build settings.** In `project.pbxproj`, for BOTH app-target configurations (the blocks containing `PRODUCT_BUNDLE_IDENTIFIER = nikhiltirunagiri.bunny;`):
  - `ENABLE_APP_SANDBOX = YES;` → `ENABLE_APP_SANDBOX = NO;`
  - delete the line `ENABLE_USER_SELECTED_FILES = readonly;`
  - `MACOSX_DEPLOYMENT_TARGET = 15.6;` → `MACOSX_DEPLOYMENT_TARGET = 26.0;`
  Use `sed -i ''` with exact matches, then `grep -n "ENABLE_APP_SANDBOX\|ENABLE_USER_SELECTED_FILES\|MACOSX_DEPLOYMENT_TARGET" bunny.xcodeproj/project.pbxproj` and confirm: two `NO`, zero `ENABLE_USER_SELECTED_FILES`, target configs `26.0` (project-level `26.1` lines stay).
- [ ] **Step 2: Create `Package.swift`:**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BunnyCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BunnyCore", targets: ["BunnyCore"])],
    targets: [
        .target(name: "BunnyCore", path: "bunny/Core"),
        .testTarget(name: "BunnyCoreTests", dependencies: ["BunnyCore"], path: "Tests/BunnyCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 3: Smoke test.** `bunny/Core/BunnyCore.swift`:

```swift
import Foundation

/// Namespace marker for Bunny's platform-independent logic (compiled into the app and the BunnyCore test package).
enum BunnyCore {
    static let version = 1
}
```

`Tests/BunnyCoreTests/SmokeTests.swift`:

```swift
import Testing
@testable import BunnyCore

@Test func coreIsLinked() {
    #expect(BunnyCore.version == 1)
}
```

- [ ] **Step 4:** Run `swift test` from repo root. Expected: `Test run with 1 test passed`.
- [ ] **Step 5:** Append `.build/` and `.swiftpm/` to `.gitignore` (it is untracked on purpose; do not `git add` it). Commit `Package.swift bunny/Core Tests bunny.xcodeproj/project.pbxproj` with message `build: disable sandbox, target macOS 26, add BunnyCore test package`.

---

### Task 2: Core logic — PanelPlacement, HoverIntent, ShelfRules

**Files:**
- Create: `bunny/Core/PanelPlacement.swift`, `bunny/Core/HoverIntent.swift`, `bunny/Core/ShelfRules.swift`
- Test: `Tests/BunnyCoreTests/PanelPlacementTests.swift`, `HoverIntentTests.swift`, `ShelfRulesTests.swift`

**Interfaces (Produces):**
```swift
enum PanelSide: Equatable { case left, right }
enum PanelPlacement {
    static let defaultWidth: CGFloat = 300
    static let defaultGap: CGFloat = 8
    static func frame(popover: CGRect, visible: CGRect,
                      width: CGFloat = defaultWidth, gap: CGFloat = defaultGap) -> (frame: CGRect, side: PanelSide)
}

struct HoverIntent {
    enum Effect: Equatable { case none, show(UUID), hide }
    enum EscapeResult: Equatable { case unlocked, closePopover }
    static let dwell: TimeInterval = 0.35
    static let grace: TimeInterval = 0.25
    private(set) var shownTaskID: UUID?
    private(set) var lockedTaskID: UUID?
    var nextDeadline: Date? { get }
    mutating func rowEntered(_ id: UUID, now: Date) -> Effect
    mutating func rowExited(_ id: UUID, now: Date)
    mutating func panelEntered()
    mutating func panelExited(now: Date)
    mutating func setEditing(_ editing: Bool, now: Date)
    mutating func rowClicked(_ id: UUID) -> Effect
    mutating func fileDragEntered(_ id: UUID) -> Effect
    mutating func lock(_ id: UUID) -> Effect          // used by Spec B (open a task's panel programmatically)
    mutating func escape(now: Date) -> EscapeResult
    mutating func popoverClosed() -> Effect
    mutating func tick(now: Date) -> Effect
}

enum ShelfRules {
    static func normalizedPath(_ url: URL) -> String
    static func isDuplicate(_ url: URL, existingPaths: [String]) -> Bool
    static func displayName(for url: URL) -> String
    static func abbreviatedParentPath(of path: String, home: String = NSHomeDirectory()) -> String
}
```

- [ ] **Step 1: Write failing tests.**

`Tests/BunnyCoreTests/PanelPlacementTests.swift`:
```swift
import Testing
import CoreGraphics
@testable import BunnyCore

struct PanelPlacementTests {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func placesLeftWithGapAndTopAligned() {
        let popover = CGRect(x: 1000, y: 395, width: 340, height: 480)
        let r = PanelPlacement.frame(popover: popover, visible: visible)
        #expect(r.side == .left)
        #expect(r.frame == CGRect(x: 1000 - 8 - 300, y: 395, width: 300, height: 480))
    }

    @Test func flipsRightWhenNoRoomLeft() {
        let popover = CGRect(x: 100, y: 395, width: 340, height: 480)
        let r = PanelPlacement.frame(popover: popover, visible: visible)
        #expect(r.side == .right)
        #expect(r.frame.minX == 440 + 8)
    }

    @Test func clampsInsideVisibleWhenNeitherFits() {
        let narrow = CGRect(x: 0, y: 0, width: 700, height: 875)
        let popover = CGRect(x: 200, y: 395, width: 340, height: 480)
        let r = PanelPlacement.frame(popover: popover, visible: narrow)
        #expect(r.side == .left)
        #expect(r.frame.minX == 0)
        #expect(r.frame.width == 300)
    }

    @Test func respectsVisibleOriginOnSecondaryScreen() {
        let screen2 = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let popover = CGRect(x: -500, y: 575, width: 340, height: 480)
        let r = PanelPlacement.frame(popover: popover, visible: screen2)
        #expect(r.side == .left)
        #expect(r.frame.minX == -500 - 308)
    }
}
```

`Tests/BunnyCoreTests/HoverIntentTests.swift`:
```swift
import Testing
import Foundation
@testable import BunnyCore

struct HoverIntentTests {
    let a = UUID(), b = UUID()
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func dwellBeforeFirstShow() {
        var h = HoverIntent()
        #expect(h.rowEntered(a, now: t0) == .none)
        #expect(h.tick(now: t0.addingTimeInterval(0.2)) == .none)
        #expect(h.tick(now: t0.addingTimeInterval(0.36)) == .show(a))
        #expect(h.shownTaskID == a)
    }

    @Test func leavingBeforeDwellCancelsShow() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0)
        h.rowExited(a, now: t0.addingTimeInterval(0.1))
        #expect(h.tick(now: t0.addingTimeInterval(1)) == .none)
        #expect(h.shownTaskID == nil)
    }

    @Test func switchesImmediatelyOnceVisible() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0); _ = h.tick(now: t0.addingTimeInterval(0.4))
        h.rowExited(a, now: t0.addingTimeInterval(0.5))
        #expect(h.rowEntered(b, now: t0.addingTimeInterval(0.55)) == .show(b))
        #expect(h.tick(now: t0.addingTimeInterval(2)) == .none) // pending hide was cancelled
    }

    @Test func hidesAfterGraceWhenPointerLeaves() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0); _ = h.tick(now: t0.addingTimeInterval(0.4))
        h.rowExited(a, now: t0.addingTimeInterval(1))
        #expect(h.tick(now: t0.addingTimeInterval(1.2)) == .none)
        #expect(h.tick(now: t0.addingTimeInterval(1.26)) == .hide)
        #expect(h.shownTaskID == nil)
    }

    @Test func pointerInPanelKeepsItOpen() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0); _ = h.tick(now: t0.addingTimeInterval(0.4))
        h.rowExited(a, now: t0.addingTimeInterval(1))
        h.panelEntered()
        #expect(h.tick(now: t0.addingTimeInterval(5)) == .none)
        h.panelExited(now: t0.addingTimeInterval(6))
        #expect(h.tick(now: t0.addingTimeInterval(6.3)) == .hide)
    }

    @Test func editingBlocksHide() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0); _ = h.tick(now: t0.addingTimeInterval(0.4))
        h.rowExited(a, now: t0.addingTimeInterval(0.9))
        h.panelEntered()
        h.setEditing(true, now: t0.addingTimeInterval(1))
        h.panelExited(now: t0.addingTimeInterval(2))
        #expect(h.tick(now: t0.addingTimeInterval(10)) == .none)
        h.setEditing(false, now: t0.addingTimeInterval(11))
        #expect(h.tick(now: t0.addingTimeInterval(11.3)) == .hide)
    }

    @Test func clickLocksAndHoverDoesNotSteal() {
        var h = HoverIntent()
        #expect(h.rowClicked(a) == .show(a))
        #expect(h.lockedTaskID == a)
        #expect(h.rowEntered(b, now: t0) == .none)
        h.rowExited(b, now: t0.addingTimeInterval(0.1))
        #expect(h.tick(now: t0.addingTimeInterval(5)) == .none)
        #expect(h.shownTaskID == a)
    }

    @Test func clickingLockedRowUnlocks() {
        var h = HoverIntent()
        _ = h.rowClicked(a)
        _ = h.rowClicked(a)
        #expect(h.lockedTaskID == nil)
        #expect(h.shownTaskID == a)
    }

    @Test func escapeUnlocksThenCloses() {
        var h = HoverIntent()
        _ = h.rowClicked(a)
        #expect(h.escape(now: t0) == .unlocked)
        #expect(h.escape(now: t0) == .closePopover)
    }

    @Test func fileDragShowsImmediately() {
        var h = HoverIntent()
        #expect(h.fileDragEntered(b) == .show(b))
    }

    @Test func popoverCloseResetsEverything() {
        var h = HoverIntent()
        _ = h.rowClicked(a)
        #expect(h.popoverClosed() == .hide)
        #expect(h.shownTaskID == nil && h.lockedTaskID == nil && h.nextDeadline == nil)
    }

    @Test func nextDeadlineReflectsPendingWork() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0)
        #expect(h.nextDeadline == t0.addingTimeInterval(HoverIntent.dwell))
    }
}
```

`Tests/BunnyCoreTests/ShelfRulesTests.swift`:
```swift
import Testing
import Foundation
@testable import BunnyCore

struct ShelfRulesTests {
    @Test func duplicateSamePath() {
        let url = URL(fileURLWithPath: "/tmp/x/../x/file.txt")
        #expect(ShelfRules.isDuplicate(url, existingPaths: [ShelfRules.normalizedPath(URL(fileURLWithPath: "/tmp/x/file.txt"))]))
    }

    @Test func duplicateViaSymlink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real.txt")
        try "x".write(to: real, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(ShelfRules.isDuplicate(link, existingPaths: [ShelfRules.normalizedPath(real)]))
    }

    @Test func differentFileIsNotDuplicate() {
        #expect(!ShelfRules.isDuplicate(URL(fileURLWithPath: "/tmp/a"), existingPaths: ["/tmp/b"]))
    }

    @Test func displayNameIsLastComponent() {
        #expect(ShelfRules.displayName(for: URL(fileURLWithPath: "/Users/n/Code/bunny/")) == "bunny")
    }

    @Test func abbreviatesHome() {
        #expect(ShelfRules.abbreviatedParentPath(of: "/Users/n/Code/bunny/README.md", home: "/Users/n") == "~/Code/bunny")
        #expect(ShelfRules.abbreviatedParentPath(of: "/Volumes/X/a.txt", home: "/Users/n") == "/Volumes/X")
        #expect(ShelfRules.abbreviatedParentPath(of: "/Users/n/a.txt", home: "/Users/n") == "~")
    }
}
```

- [ ] **Step 2:** `swift test` → FAIL (types not found).
- [ ] **Step 3: Implement.**

`bunny/Core/PanelPlacement.swift`:
```swift
import CoreGraphics

enum PanelSide: Equatable { case left, right }

/// Computes where the task side panel sits relative to the popover window (AppKit screen coordinates, origin bottom-left).
enum PanelPlacement {
    static let defaultWidth: CGFloat = 300
    static let defaultGap: CGFloat = 8

    static func frame(popover: CGRect, visible: CGRect,
                      width: CGFloat = defaultWidth, gap: CGFloat = defaultGap) -> (frame: CGRect, side: PanelSide) {
        let height = min(popover.height, visible.height)
        let y = min(max(popover.maxY - height, visible.minY), visible.maxY - height)
        let leftX = popover.minX - gap - width
        if leftX >= visible.minX {
            return (CGRect(x: leftX, y: y, width: width, height: height), .left)
        }
        let rightX = popover.maxX + gap
        if rightX + width <= visible.maxX {
            return (CGRect(x: rightX, y: y, width: width, height: height), .right)
        }
        let clampedX = min(max(leftX, visible.minX), visible.maxX - width)
        return (CGRect(x: clampedX, y: y, width: width, height: height), .left)
    }
}
```

`bunny/Core/HoverIntent.swift`:
```swift
import Foundation

/// Pure state machine deciding when the task side panel shows, switches, hides or stays locked.
/// Time is injected so it can be unit tested; the app calls `tick(now:)` at `nextDeadline`.
struct HoverIntent {
    enum Effect: Equatable { case none, show(UUID), hide }
    enum EscapeResult: Equatable { case unlocked, closePopover }

    static let dwell: TimeInterval = 0.35
    static let grace: TimeInterval = 0.25

    private(set) var shownTaskID: UUID?
    private(set) var lockedTaskID: UUID?
    private var hoveredRowID: UUID?
    private var pendingShow: (id: UUID, at: Date)?
    private var pendingHideAt: Date?
    private var pointerInPanel = false
    private var editing = false

    var nextDeadline: Date? {
        [pendingShow?.at, pendingHideAt].compactMap { $0 }.min()
    }

    mutating func rowEntered(_ id: UUID, now: Date) -> Effect {
        hoveredRowID = id
        pendingHideAt = nil
        if lockedTaskID != nil { return .none }
        if shownTaskID != nil {
            pendingShow = nil
            if shownTaskID == id { return .none }
            shownTaskID = id
            return .show(id)
        }
        pendingShow = (id, now.addingTimeInterval(Self.dwell))
        return .none
    }

    mutating func rowExited(_ id: UUID, now: Date) {
        if hoveredRowID == id { hoveredRowID = nil }
        if pendingShow?.id == id { pendingShow = nil }
        scheduleHideIfIdle(now: now)
    }

    mutating func panelEntered() {
        pointerInPanel = true
        pendingHideAt = nil
    }

    mutating func panelExited(now: Date) {
        pointerInPanel = false
        scheduleHideIfIdle(now: now)
    }

    mutating func setEditing(_ editing: Bool, now: Date) {
        self.editing = editing
        if editing { pendingHideAt = nil } else { scheduleHideIfIdle(now: now) }
    }

    mutating func rowClicked(_ id: UUID) -> Effect {
        if lockedTaskID == id {
            lockedTaskID = nil
            return .none
        }
        return lock(id)
    }

    mutating func lock(_ id: UUID) -> Effect {
        lockedTaskID = id
        pendingShow = nil
        pendingHideAt = nil
        let changed = shownTaskID != id
        shownTaskID = id
        return changed ? .show(id) : .none
    }

    mutating func fileDragEntered(_ id: UUID) -> Effect {
        pendingShow = nil
        pendingHideAt = nil
        if shownTaskID == id { return .none }
        shownTaskID = id
        return .show(id)
    }

    mutating func escape(now: Date) -> EscapeResult {
        if lockedTaskID != nil {
            lockedTaskID = nil
            scheduleHideIfIdle(now: now)
            return .unlocked
        }
        return .closePopover
    }

    mutating func popoverClosed() -> Effect {
        let wasShown = shownTaskID != nil
        self = HoverIntent()
        return wasShown ? .hide : .none
    }

    mutating func tick(now: Date) -> Effect {
        if let p = pendingShow, now >= p.at {
            pendingShow = nil
            shownTaskID = p.id
            return .show(p.id)
        }
        if let h = pendingHideAt, now >= h {
            pendingHideAt = nil
            shownTaskID = nil
            return .hide
        }
        return .none
    }

    private mutating func scheduleHideIfIdle(now: Date) {
        guard shownTaskID != nil, lockedTaskID == nil, !pointerInPanel, !editing, hoveredRowID == nil else { return }
        pendingHideAt = now.addingTimeInterval(Self.grace)
    }
}
```
Note: `popoverClosedResetsEverything` returns `.hide` — in that test the panel was shown via lock, so `wasShown` is true.

`bunny/Core/ShelfRules.swift`:
```swift
import Foundation

/// Pure rules for shelf items: identity (dedupe) and display strings.
enum ShelfRules {
    static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func isDuplicate(_ url: URL, existingPaths: [String]) -> Bool {
        let path = normalizedPath(url)
        return existingPaths.contains(path)
    }

    static func displayName(for url: URL) -> String {
        url.standardizedFileURL.lastPathComponent
    }

    static func abbreviatedParentPath(of path: String, home: String = NSHomeDirectory()) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        if parent == home { return "~" }
        if parent.hasPrefix(home + "/") { return "~" + parent.dropFirst(home.count) }
        return parent
    }
}
```
Note: on macOS `/tmp` resolves to `/private/tmp`; `duplicateSamePath` normalizes both sides the same way so it still passes.

- [ ] **Step 4:** `swift test` → all pass. Fix implementation (not tests) until green.
- [ ] **Step 5:** Commit `feat(core): panel placement, hover intent and shelf rules`.

---

### Task 3: Data model & ShelfService

**Files:**
- Modify: `bunny/Models/BunnyTask.swift` (add field), `bunny/AppDelegate.swift:13` (container), `bunny/Views/TaskRowView.swift` `commitEdit`/`cancelEdit` (delete shelf items with the task)
- Create: `bunny/Models/ShelfItem.swift`, `bunny/Controllers/ShelfService.swift`

**Interfaces (Produces):**
```swift
@Model final class ShelfItem { id, taskID, bookmark, displayName, lastKnownPath, isDirectory, addedAt, sortOrder
    init(taskID: UUID, bookmark: Data, url: URL, isDirectory: Bool, sortOrder: Int) }
struct ResolvedShelfItem { let item: ShelfItem; let url: URL?   // nil = missing
    var isMissing: Bool { url == nil } }
@MainActor enum ShelfService {
    @discardableResult static func add(_ urls: [URL], to taskID: UUID, in context: ModelContext) -> Int   // number added
    static func items(for taskID: UUID, in context: ModelContext) -> [ShelfItem]   // sorted by sortOrder
    static func resolve(_ item: ShelfItem) -> URL?   // refreshes stale bookmarks in place
    static func remove(_ item: ShelfItem, in context: ModelContext)
    static func removeAll(for taskID: UUID, in context: ModelContext)
    static func containsPath(_ url: URL, taskID: UUID, in context: ModelContext) -> Bool
}
```
`BunnyTask.taskDescription: String = ""`.

- [ ] **Step 1:** Add `var taskDescription: String = ""` to `BunnyTask` after `title`.
- [ ] **Step 2:** Create `ShelfItem.swift`:

```swift
import Foundation
import SwiftData

@Model
final class ShelfItem {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var bookmark: Data = Data()
    var displayName: String = ""
    var lastKnownPath: String = ""
    var isDirectory: Bool = false
    var addedAt: Date = Date()
    var sortOrder: Int = 0

    init(taskID: UUID, bookmark: Data, url: URL, isDirectory: Bool, sortOrder: Int) {
        self.taskID = taskID
        self.bookmark = bookmark
        self.displayName = ShelfRules.displayName(for: url)
        self.lastKnownPath = ShelfRules.normalizedPath(url)
        self.isDirectory = isDirectory
        self.sortOrder = sortOrder
    }
}
```

- [ ] **Step 3:** Create `ShelfService.swift`:

```swift
import Foundation
import SwiftData

@MainActor
enum ShelfService {
    static func items(for taskID: UUID, in context: ModelContext) -> [ShelfItem] {
        let descriptor = FetchDescriptor<ShelfItem>(
            predicate: #Predicate { $0.taskID == taskID },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.addedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func containsPath(_ url: URL, taskID: UUID, in context: ModelContext) -> Bool {
        ShelfRules.isDuplicate(url, existingPaths: items(for: taskID, in: context).map(\.lastKnownPath))
    }

    /// Links each file URL to the task. Skips duplicates and URLs that can't be bookmarked. Returns how many were added.
    @discardableResult
    static func add(_ urls: [URL], to taskID: UUID, in context: ModelContext) -> Int {
        var existing = items(for: taskID, in: context)
        var added = 0
        for url in urls where url.isFileURL {
            guard !ShelfRules.isDuplicate(url, existingPaths: existing.map(\.lastKnownPath)),
                  let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            else { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let item = ShelfItem(taskID: taskID, bookmark: data, url: url, isDirectory: isDir,
                                 sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1)
            context.insert(item)
            existing.append(item)
            added += 1
        }
        return added
    }

    /// Resolves the bookmark. Returns nil when the file is gone. Refreshes stale bookmarks and cached path/name.
    static func resolve(_ item: ShelfItem) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        let path = ShelfRules.normalizedPath(url)
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            item.bookmark = fresh
        }
        if item.lastKnownPath != path {
            item.lastKnownPath = path
            item.displayName = ShelfRules.displayName(for: url)
        }
        return url
    }

    static func remove(_ item: ShelfItem, in context: ModelContext) {
        context.delete(item)
    }

    static func removeAll(for taskID: UUID, in context: ModelContext) {
        for item in items(for: taskID, in: context) { context.delete(item) }
    }
}
```

- [ ] **Step 4:** `AppDelegate`: `modelContainer = try ModelContainer(for: BunnyTask.self, ShelfItem.self)`.
- [ ] **Step 5:** `TaskRowView.commitEdit` and `cancelEdit`: before each `modelContext.delete(task)` add `ShelfService.removeAll(for: task.id, in: modelContext)`.
- [ ] **Step 6: Verify.** `swift test` still green (Core unaffected). Self-review: `#Predicate` captures a local `let taskID` (it does — the parameter); every SwiftData call is on the main actor. Commit `feat: task description field and shelf item model/service`.

---

### Task 4: Side panel window, coordinator & popover behavior

**Files:**
- Create: `bunny/Controllers/PanelCoordinator.swift`, `bunny/Controllers/TaskPanelController.swift`, `bunny/Views/Panel/TaskPanel.swift`, `bunny/Views/Panel/TaskPanelView.swift` (minimal placeholder — Task 5 replaces its body)
- Modify: `bunny/Controllers/StatusBarController.swift`, `bunny/Views/TaskRowView.swift` (hover/click hooks only)

**Interfaces:**
- Consumes: `HoverIntent`, `PanelPlacement` (Task 2).
- Produces:
```swift
@MainActor @Observable final class PanelCoordinator {
    static let shared: PanelCoordinator
    private(set) var shownTaskID: UUID?
    private(set) var lockedTaskID: UUID?
    var onShow: ((UUID) -> Void)?     // set by TaskPanelController
    var onHide: (() -> Void)?
    var onClosePopover: (() -> Void)? // set by StatusBarController
    func rowEntered(_ id: UUID); func rowExited(_ id: UUID)
    func panelEntered(); func panelExited()
    func setEditing(_ editing: Bool)
    func rowClicked(_ id: UUID); func fileDragEntered(_ id: UUID)
    func open(_ id: UUID)             // = lock; used by Spec B
    func escape()                     // unlock, else close popover
    func popoverClosed()
}
final class TaskPanelController {  // owned by StatusBarController
    init(modelContainer: ModelContainer)
    func attach(to popoverWindow: NSWindow)
    func show(taskID: UUID)
    func hide()
    var window: NSWindow { get }
}
struct TaskPanelView: View { let taskID: UUID }   // Task 5 fills it in
```

- [ ] **Step 1: `PanelCoordinator.swift`:**

```swift
import Foundation
import Observation

/// Main-actor driver for `HoverIntent`: forwards pointer events, runs the dwell/grace timer and tells the panel window what to do.
@MainActor
@Observable
final class PanelCoordinator {
    static let shared = PanelCoordinator()
    private init() {}

    private(set) var shownTaskID: UUID?
    private(set) var lockedTaskID: UUID?

    @ObservationIgnored var onShow: ((UUID) -> Void)?
    @ObservationIgnored var onHide: (() -> Void)?
    @ObservationIgnored var onClosePopover: (() -> Void)?

    @ObservationIgnored private var intent = HoverIntent()
    @ObservationIgnored private var timer: Timer?

    func rowEntered(_ id: UUID) { apply(intent.rowEntered(id, now: Date())) }
    func rowExited(_ id: UUID) { intent.rowExited(id, now: Date()); sync() }
    func panelEntered() { intent.panelEntered(); sync() }
    func panelExited() { intent.panelExited(now: Date()); sync() }
    func setEditing(_ editing: Bool) { intent.setEditing(editing, now: Date()); sync() }
    func rowClicked(_ id: UUID) { apply(intent.rowClicked(id)) }
    func fileDragEntered(_ id: UUID) { apply(intent.fileDragEntered(id)) }
    func open(_ id: UUID) { apply(intent.lock(id)) }

    func escape() {
        switch intent.escape(now: Date()) {
        case .unlocked: sync()
        case .closePopover: onClosePopover?()
        }
    }

    func popoverClosed() { apply(intent.popoverClosed()) }

    private func apply(_ effect: HoverIntent.Effect) {
        switch effect {
        case .none: break
        case .show(let id): onShow?(id)
        case .hide: onHide?()
        }
        sync()
    }

    private func sync() {
        shownTaskID = intent.shownTaskID
        lockedTaskID = intent.lockedTaskID
        timer?.invalidate()
        timer = nil
        guard let deadline = intent.nextDeadline else { return }
        let t = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.intent.tick(now: Date()))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
```

- [ ] **Step 2: `TaskPanel.swift`** — the window:

```swift
import AppKit

/// Borderless glass panel that sits beside the popover. Can become key so its text fields work.
final class TaskPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: PanelPlacement.defaultWidth, height: 480),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]

        let glass = NSGlassEffectView()
        glass.cornerRadius = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content
        contentView = glass
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 3: `TaskPanelController.swift`:**

```swift
import AppKit
import SwiftUI
import SwiftData

/// Owns the side panel window: creates it, keeps it attached to the popover window, swaps its task.
@MainActor
final class TaskPanelController {
    private let panel: TaskPanel
    private let host: NSHostingView<AnyView>
    private weak var popoverWindow: NSWindow?
    private let modelContainer: ModelContainer

    var window: NSWindow { panel }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        host = NSHostingView(rootView: AnyView(EmptyView()))
        panel = TaskPanel(content: host)
        PanelCoordinator.shared.onShow = { [weak self] id in self?.show(taskID: id) }
        PanelCoordinator.shared.onHide = { [weak self] in self?.hide() }
    }

    func attach(to popoverWindow: NSWindow) {
        self.popoverWindow = popoverWindow
    }

    func show(taskID: UUID) {
        guard let popoverWindow, popoverWindow.isVisible,
              let screen = popoverWindow.screen ?? NSScreen.main else { return }
        host.rootView = AnyView(
            TaskPanelView(taskID: taskID)
                .id(taskID)
                .modelContainer(modelContainer)
                .environment(AppState.shared)
                .environment(TimerManager.shared)
                .environment(PanelCoordinator.shared)
        )
        let placement = PanelPlacement.frame(popover: popoverWindow.frame, visible: screen.visibleFrame)
        panel.setFrame(placement.frame, display: true)
        if panel.parent == nil {
            popoverWindow.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide() {
        popoverWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}
```

- [ ] **Step 4: Placeholder `TaskPanelView.swift`** (Task 5 replaces the body):

```swift
import SwiftUI
import SwiftData

struct TaskPanelView: View {
    let taskID: UUID
    @Environment(PanelCoordinator.self) private var coordinator

    var body: some View {
        Text(taskID.uuidString)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onHover { inside in inside ? coordinator.panelEntered() : coordinator.panelExited() }
    }
}
```

- [ ] **Step 5: `StatusBarController` changes.**
  - Make the class `@MainActor` (it already runs on main). Add `private var panelController: TaskPanelController!`, `private var globalMonitor: Any?`, `private var localMonitor: Any?`. Conform to `NSPopoverDelegate`.
  - In `setup`: `popover.behavior = .applicationDefined`, `popover.delegate = self`, `panelController = TaskPanelController(modelContainer: modelContainer)`, `PanelCoordinator.shared.onClosePopover = { [weak self] in self?.closePopover() }`. Pass `.environment(PanelCoordinator.shared)` into the popover's `ContentView` environment.
  - Replace `togglePopover` with `@objc func togglePopover() { popover.isShown ? closePopover() : openPopover() }`, plus:

```swift
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

func popoverDidClose(_ notification: Notification) {
    removeMonitors()
    PanelCoordinator.shared.popoverClosed()
    panelController.hide()
}

private func installMonitors() {
    removeMonitors()
    // Clicks in other apps close the popover (mouse-down global monitors need no Accessibility permission).
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        MainActor.assumeIsolated { self?.closePopover() }
    }
    // Esc: unlock the panel, then close. Leave Esc alone while a text field is being edited.
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
        guard event.keyCode == 53 else { return event }
        if event.window?.firstResponder is NSTextView { return event }
        MainActor.assumeIsolated { PanelCoordinator.shared.escape() }
        return nil
    }
}

private func removeMonitors() {
    if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
}
```
  - Status item clicks: the global monitor does not see clicks on our own status item (it is our process), so the toggle keeps working.

- [ ] **Step 6: `TaskRowView` hooks.** Add `@Environment(PanelCoordinator.self) private var coordinator`. On the row's outer `HStack` (after `.contentShape(Rectangle())`):

```swift
.onHover { inside in inside ? coordinator.rowEntered(task.id) : coordinator.rowExited(task.id) }
.onTapGesture { coordinator.rowClicked(task.id) }
```
  The single-tap gesture must not break the title's existing `onTapGesture(count: 2)`: attach the title's double-tap with `.highPriorityGesture(TapGesture(count: 2).onEnded { startEditing() })` instead of `.onTapGesture(count: 2)`. Buttons inside the row keep receiving their own clicks.

- [ ] **Step 7: Verify.** `swift test` green. Self-review checklist: `NSGlassEffectView.contentView` & `.cornerRadius` exist (macOS 26); `addChildWindow(_:ordered:)` on the popover window; every `PanelCoordinator` call site is main-actor; `TaskPanelView` receives `.environment(PanelCoordinator.shared)`. Commit `feat: attached task side panel with hover/lock coordinator`.

---

### Task 5: Panel content, shelf UI, drag in/out, row drops & badges

**Files:**
- Replace: `bunny/Views/Panel/TaskPanelView.swift`
- Create: `bunny/Views/Panel/ShelfView.swift`, `bunny/Views/Panel/ShelfItemDragSource.swift`
- Modify: `bunny/Views/TaskRowView.swift` (row file drop + badges), `bunny/ContentView.swift` (pass nothing new; keep reorder as is)

**Interfaces:**
- Consumes: `ShelfService`, `ShelfItem`, `ShelfRules`, `PanelCoordinator`, `BunnyTask.taskDescription`.
- Produces: `TaskPanelView(taskID:)` with a bottom slot for Spec B:

```swift
struct TaskPanelView: View {
    let taskID: UUID
    // Spec B mounts AgentPanelSection(task:) in `agentSection`; in this task it's EmptyView.
}
```

- [ ] **Step 1: `ShelfItemDragSource.swift`** — AppKit view overlaid on each shelf row; handles drag-out, double-click, context menu and hover.

```swift
import AppKit
import SwiftUI

/// Transparent AppKit overlay for a shelf row: starts file drags (copy outside the app, move inside it),
/// opens on double-click, shows the context menu, and reports hover.
struct ShelfItemDragSource: NSViewRepresentable {
    let url: URL?                        // nil = missing file → not draggable
    var onDragEnded: (NSDragOperation) -> Void
    var onDoubleClick: () -> Void
    var menu: () -> NSMenu
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.url = url
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
        view.menuProvider = menu
        view.onHover = onHover
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var url: URL?
        var onDragEnded: ((NSDragOperation) -> Void)?
        var onDoubleClick: (() -> Void)?
        var menuProvider: (() -> NSMenu)?
        var onHover: ((Bool) -> Void)?
        private var mouseDownEvent: NSEvent?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            if event.clickCount == 2 { onDoubleClick?() }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let url, let down = mouseDownEvent else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard dx * dx + dy * dy > 9 else { return }
            mouseDownEvent = nil
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            let p = convert(down.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32), contents: icon)
            beginDraggingSession(with: [item], event: down, source: self)
        }

        override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : .move
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            onDragEnded?(operation)
        }
    }
}
```

- [ ] **Step 2: `ShelfView.swift`:**

```swift
import SwiftUI
import SwiftData
import AppKit

struct ShelfView: View {
    let taskID: UUID
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [ShelfItem]
    @State private var isTargeted = false
    @State private var hoveredID: UUID?

    init(taskID: UUID) {
        self.taskID = taskID
        _items = Query(filter: #Predicate<ShelfItem> { $0.taskID == taskID },
                       sort: [SortDescriptor(\ShelfItem.sortOrder), SortDescriptor(\ShelfItem.addedAt)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Shelf").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                if !items.isEmpty {
                    Text("\(items.count)").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            if items.isEmpty {
                emptyZone
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(items) { item in row(item) }
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.clear)))
        .dropDestination(for: URL.self) { urls, _ in
            ShelfService.add(urls, to: taskID, in: modelContext) > 0
        } isTargeted: { isTargeted = $0 }
    }

    private var emptyZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 18)).foregroundStyle(.tertiary)
            Text("Drop files or folders here").font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.quaternary))
    }

    private func row(_ item: ShelfItem) -> some View {
        let url = ShelfService.resolve(item)
        return HStack(spacing: 8) {
            Group {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                } else {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                Text(url == nil ? "Missing" : ShelfRules.abbreviatedParentPath(of: item.lastKnownPath))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .opacity(url == nil ? 0.55 : 1)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(hoveredID == item.id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
        .overlay(
            ShelfItemDragSource(
                url: url,
                onDragEnded: { op in if !op.isEmpty { ShelfService.remove(item, in: modelContext) } },
                onDoubleClick: { if let url { NSWorkspace.shared.open(url) } },
                menu: { menu(for: item, url: url) },
                onHover: { hoveredID = $0 ? item.id : (hoveredID == item.id ? nil : hoveredID) }
            )
        )
        .help(item.lastKnownPath)
    }

    private func menu(for item: ShelfItem, url: URL?) -> NSMenu {
        let menu = NSMenu()
        if let url {
            menu.addItem(ClosureMenuItem("Open") { NSWorkspace.shared.open(url) })
            menu.addItem(ClosureMenuItem("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
            menu.addItem(ClosureMenuItem("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            })
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem("Remove from Shelf") { ShelfService.remove(item, in: modelContext) })
        return menu
    }
}

/// NSMenuItem that runs a closure (keeps itself as target).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func run() { handler() }
}
```
Same-shelf drop: `ShelfService.add` returns 0 for the duplicate → closure returns `false` → the source sees an empty operation → item kept (Review Focus 3).

- [ ] **Step 3: Replace `TaskPanelView.swift`:**

```swift
import SwiftUI
import SwiftData

struct TaskPanelView: View {
    let taskID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(PanelCoordinator.self) private var coordinator
    @Environment(TimerManager.self) private var timerManager
    @Query private var matches: [BunnyTask]
    @Query private var parents: [BunnyTask]
    @Query private var children: [BunnyTask]
    @State private var titleDraft = ""
    @FocusState private var focus: Field?
    private enum Field { case title, description }

    init(taskID: UUID) {
        self.taskID = taskID
        _matches = Query(filter: #Predicate<BunnyTask> { $0.id == taskID })
        _children = Query(filter: #Predicate<BunnyTask> { $0.parentID == taskID && $0.archivedAt == nil },
                          sort: [SortDescriptor(\BunnyTask.sortOrder), SortDescriptor(\BunnyTask.createdAt)])
        _parents = Query()
    }

    var body: some View {
        Group {
            if let task = matches.first {
                content(task)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { $0 ? coordinator.panelEntered() : coordinator.panelExited() }
        .onChange(of: focus) { _, f in coordinator.setEditing(f != nil) }
    }

    @ViewBuilder
    private func content(_ task: BunnyTask) -> some View {
        @Bindable var task = task
        VStack(alignment: .leading, spacing: 12) {
            if let pid = task.parentID, let parent = parents.first(where: { $0.id == pid }) {
                Label(parent.title, systemImage: "arrow.turn.left.up")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            TextField("Title", text: $titleDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1...3)
                .focused($focus, equals: .title)
                .onSubmit { commitTitle(task) }
                .onAppear { titleDraft = task.title }
                .onChange(of: focus) { old, _ in if old == .title { commitTitle(task) } }
            metaLine(task)
            ZStack(alignment: .topLeading) {
                if task.taskDescription.isEmpty {
                    Text("Add a description…").font(.system(size: 13)).foregroundStyle(.tertiary)
                        .padding(.top, 1).allowsHitTesting(false)
                }
                TextEditor(text: $task.taskDescription)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .description)
            }
            .frame(minHeight: 60, maxHeight: 180)
            ShelfView(taskID: task.id)
            Spacer(minLength: 0)
            agentSection(task)
        }
        .padding(16)
    }

    @ViewBuilder
    private func metaLine(_ task: BunnyTask) -> some View {
        let _ = timerManager.tick
        HStack(spacing: 10) {
            if task.isTimerRunning {
                Label("\(task.formattedRemaining) left", systemImage: "timer")
            } else if task.isTimerExpired {
                Label("Time's up", systemImage: "clock.badge.checkmark")
            } else if let d = task.timerDuration {
                Label("\(Int(d / 60)) min timer", systemImage: "clock")
            }
            if !task.isSubtask && !children.isEmpty {
                let done = children.filter(\.isCompleted).count
                Label("\(done)/\(children.count) subtasks", systemImage: "checklist")
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    /// Spec B mounts the agent status / questions UI here.
    @ViewBuilder
    private func agentSection(_ task: BunnyTask) -> some View {
        EmptyView()
    }

    private func commitTitle(_ task: BunnyTask) {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { titleDraft = task.title } else { task.title = trimmed }
    }
}
```

- [ ] **Step 4: `TaskRowView` — row file drop + badges.**
  - Add `@Query private var shelfItems: [ShelfItem]` initialized in a custom `init(task:hasSubtasks:)` with `#Predicate<ShelfItem> { $0.taskID == id }` (capture `let id = task.id` first). Keep the memberwise call sites in `ContentView` working (`TaskRowView(task:hasSubtasks:)`).
  - After the title `Text`, inside the same `HStack`, add badges (only when not editing):

```swift
if !task.taskDescription.isEmpty {
    Image(systemName: "text.alignleft").font(.system(size: 10)).foregroundStyle(.tertiary)
}
if !shelfItems.isEmpty {
    HStack(spacing: 1) {
        Image(systemName: "paperclip")
        Text("\(shelfItems.count)")
    }
    .font(.system(size: 10)).foregroundStyle(.tertiary)
}
```
  Title `Text` keeps `.frame(maxWidth: .infinity, alignment: .leading)` — move that frame to a wrapping `HStack(spacing: 4) { Text…; badges }` so badges sit right after the title.
  - On the row, add a file drop that also opens the panel during drags:

```swift
@State private var isFileTargeted = false
// …
.dropDestination(for: URL.self) { urls, _ in
    ShelfService.add(urls, to: task.id, in: modelContext) > 0
} isTargeted: { targeted in
    isFileTargeted = targeted
    if targeted { coordinator.fileDragEntered(task.id) }
}
.background(isFileTargeted ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
```

- [ ] **Step 5: Verify.** `swift test` green. Self-review: `@Query` with init-injected predicates uses captured `let`s; `ShelfItemDragSource` overlay is the full row size; `NSDragOperation.isEmpty` exists (OptionSet). Commit `feat: panel content with editable description and draggable file shelf`.

---

### Task 6: Spring-loading on the menu bar icon

**Files:**
- Create: `bunny/Controllers/StatusItemDropView.swift`
- Modify: `bunny/Controllers/StatusBarController.swift` (`setup`)

**Interfaces:** Consumes `StatusBarController.openPopover()` / `togglePopover()` (Task 4).

- [ ] **Step 1: Create:**

```swift
import AppKit

/// Transparent view covering the status item button. A file dragged onto the menu bar icon opens the popover
/// so the drag can continue onto a task. Clicks are forwarded to the button's normal action.
final class StatusItemDropView: NSView {
    var onDragEntered: (() -> Void)?
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return []     // the icon itself never accepts the drop
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
}
```

- [ ] **Step 2:** In `StatusBarController.setup`, after configuring `button`:

```swift
let dropView = StatusItemDropView(frame: button.bounds)
dropView.onDragEntered = { [weak self] in self?.openPopover() }
dropView.onClick = { [weak self] in self?.togglePopover() }
button.addSubview(dropView)
```
  Keep `button.action`/`target` as a fallback.
- [ ] **Step 3: Verify & commit** `feat: spring-load popover when dragging files onto the menu bar icon`.

---

### Task 7: macOS 27 visual refresh

**Files:** Modify `bunny/ContentView.swift`, `bunny/Views/TaskRowView.swift`, `bunny/Views/ArchiveView.swift`, `bunny/Views/SettingsView.swift`, `bunny/Views/TimerPickerView.swift`. Reference: `docs/superpowers/research/macos27-design.md`.

**Interfaces:** No API changes. Must not remove hooks added in Tasks 4–5.

- [ ] **Step 1: ContentView.**
  - New-task field: `HStack(spacing: 8) { Image(systemName: "plus").foregroundStyle(.secondary); TextField(...) }` inside `.padding(.horizontal, 12).padding(.vertical, 9).background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous)).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)`; remove the `Divider()` under it.
  - Task list: `LazyVStack(spacing: 2)`, `.padding(.horizontal, 6)`; drop target highlight uses `RoundedRectangle(cornerRadius: 10, style: .continuous)`.
  - Bottom bar: remove top `Divider()`; wrap the two buttons in `GlassEffectContainer(spacing: 8)`; each button `.buttonStyle(.glass)` with `.buttonBorderShape(.circle)` and `.controlSize(.large)`; keep help texts; active state tints the symbol with `Color.accentColor`. Height 44.
  - Add `.containerShape(.rect(cornerRadius: 16))` on the root `VStack`.
- [ ] **Step 2: TaskRowView.**
  - Add `@State private var isHovered = false`, set in the existing `.onHover` (keep the coordinator calls).
  - Row background: `.background { ConcentricRectangle().fill(isHovered || coordinator.shownTaskID == task.id ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear)) }` combined with the file-drop tint (file-drop tint wins).
  - Checkbox: `.contentTransition(.symbolEffect(.replace))`; pin icon same.
  - Right-side action buttons only fully visible on hover: `.opacity(isHovered || task.isPinned || task.hasTimer ? 1 : 0.0)` applied to add-subtask and archive buttons only (timer and pin remain visible when active); animate with `.animation(.easeOut(duration: 0.15), value: isHovered)`.
  - Title font 14 regular (unchanged), vertical padding 6.
- [ ] **Step 3: ArchiveView.** Section header: remove `.background(.regularMaterial)` (glass-era: header over list uses `.background(.bar)` is wrong too) → use plain `Text` with `.font(.system(size: 11, weight: .semibold))`, `.foregroundStyle(.secondary)`, `.padding(.top, 10)`; rows get the same concentric hover highlight as TaskRowView (local `@State hovered: UUID?`).
- [ ] **Step 4: SettingsView.** Wrap content in `Form { Section { launch toggle } Section("Appearance") { picker } Section("About") { … } }.formStyle(.grouped).scrollContentBackground(.hidden)`; Quit button below the form: `.buttonStyle(.glass)`, `.tint(.red)`, full width, `.padding(12)`.
- [ ] **Step 5: TimerPickerView.** `Start` → `.buttonStyle(.glassProminent)`; `Clear` → `.buttonStyle(.glass)`; `+/-` buttons `.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)`; the numeric fields get `.background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))`.
- [ ] **Step 6: Verify & commit.** `swift test` green; grep that no view applies `.glassEffect` inside `TaskPanelView` (panel root already glass). Commit `style: macOS 27 Liquid Glass refresh`.

---

## Execution waves (for the orchestrator)
- Wave 1 (parallel): Task 1→2 (one worker, sequential) ∥ Task 3.
- Wave 2: Task 4.
- Wave 3 (parallel): Task 5 ∥ Task 6.
- Wave 4: Task 7 (touches the same view files as Spec B's row changes — run before Spec B's row task).
