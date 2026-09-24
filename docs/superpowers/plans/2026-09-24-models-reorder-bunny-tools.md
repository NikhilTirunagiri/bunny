# Model/Effort, Reorder & Nest, Bunny Tools — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-harness model and effort selection, make starting a run use the default agent, restore drag-to-reorder (plus drag-into to nest), and let agents manage Bunny tasks through a local MCP server.

**Architecture:** The pure logic is Foundation-only and tested with `swift test`. That logic is the move rules, the MCP JSON-RPC core, tool argument validation, runner argv/config and the Codex model-list codec. The app side is SwiftUI drag and drop, a Network.framework HTTP listener, a SwiftData tool backend and the settings/panel UI.

**Tech Stack:** Swift 5 mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (app), SwiftUI/AppKit/SwiftData/Network, swift-testing.

**Spec:** `docs/superpowers/specs/2026-09-24-models-reorder-bunny-tools-design.md`

## Global Constraints
- Xcode 27 is installed and licensed, so `xcodebuild` works. App verification is a Debug build with `xcodebuild -project bunny.xcodeproj -scheme bunny -configuration Debug -derivedDataPath <scratch>/dd-<task> build`, which must report 0 errors. Core verification is `swift test` passing.
- `bunny/Core/**`: Foundation only, internal access, and it must compile both under SwiftPM (Swift 6.1 CLT toolchain, Swift 5 mode) and in the app target (default MainActor). Mark functions called off-main `nonisolated`.
- Never put arithmetic inside `#expect(a == b)`; precompute the expected value.
- Don't edit `project.pbxproj`. New files under `bunny/` are auto-included.
- Commits: repo-local author. Never add Co-Authored-By, Claude-Session or AI attribution. `git add` only your own files.
- MCP: loopback only (`127.0.0.1`), a bearer token on every request, default port 47823.
- UserDefaults keys:
  - `agent.claude.model`, `agent.claude.effort`, `agent.codex.model`, `agent.codex.effort` (empty string means Default)
  - `bunnyTools.token`, `bunnyTools.port`
- Claude efforts: `low`, `medium`, `high`, `xhigh`, `max`. Claude model aliases: `fable`, `opus`, `sonnet`, `haiku`.

## Review Focus
1. **Nest a parent that has subtasks:** dropping it into another task must not create a second nesting level (Task D1 test).
2. **Drag a subtask to the top level:** above or below a parent task, it becomes top-level at that spot (D1).
3. **File drop on a row:** dragging a Finder file onto a row still shelves it, and never triggers a move (D2).
4. **Unauthorized MCP request:** a missing or wrong token gets 401 and never touches data (D4, D5).
5. **Codex model list unavailable:** if `codex` is missing or the list call times out, the Settings Codex model picker still works with Default/Custom (D3, D6).

---

### Task D1: Core `TaskMoveRules`

**Files:** Create `bunny/Core/TaskMoveRules.swift` and `Tests/BunnyCoreTests/TaskMoveRulesTests.swift`.

**Interfaces (Produces):**
```swift
struct TaskNode: Equatable { let id: UUID; var parentID: UUID?; var sortOrder: Int }
enum DropZone: Equatable { case above, below, into }
struct TaskPlacement: Equatable { let id: UUID; let parentID: UUID?; let sortOrder: Int }
enum TaskMoveRules {
    /// Zone from pointer y within a row of height h: y < 0.3h → above, y > 0.7h → below, else into.
    static func zone(y: CGFloat, height: CGFloat) -> DropZone
    /// Effective zone after rules (into → below when not allowed). nil = no-op.
    static func resolve(dragged: UUID, target: UUID, zone: DropZone, nodes: [TaskNode]) -> DropZone?
    /// New placements for every task whose parentID/sortOrder changes (source & destination sibling lists renumbered 0…n, ordered by current sortOrder then input order).
    static func move(dragged: UUID, target: UUID, zone: DropZone, nodes: [TaskNode]) -> [TaskPlacement]
}
```
Rules: see spec §4. Siblings of X are `nodes.filter { $0.parentID == X.parentID }`, sorted by `(sortOrder, index in nodes)`. "Has subtasks" means some node has `parentID == id`.

- [ ] **Step 1: Write the failing tests.**
  - `zone` boundaries.
  - Reorder a top-level task above or below another; the orders come out dense.
  - Move a top-level task without subtasks into a top-level task; it gets that parent and goes last among its children.
  - "Into" when the dragged task has subtasks becomes "below".
  - "Into" when the target is a subtask becomes "below", as a sibling in the subtask's parent.
  - Move a subtask above a top-level task; it becomes top-level (un-nest).
  - Move a subtask within its parent.
  - Moving onto itself returns nil / `[]`.
  - Moving a parent onto its own subtask returns nil.
  - Moving a subtask to a different parent renumbers both parents' child lists.
- [ ] **Step 2:** Run `swift test --filter TaskMoveRules` and confirm it fails.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `swift test`; all pass.
- [ ] **Step 5:** Commit `feat(core): task move rules for reorder and nesting`.

### Task D2: Row drag & drop (bug fix + nesting UI)

**Files:**
- Modify `bunny/ContentView.swift`: remove the group-level `.onDrag`/`.dropDestination`, `dropTargetID` and `moveTask`.
- Modify `bunny/Views/TaskRowView.swift`: add `.onDrag` on every row and replace the row's `.dropDestination(for: URL.self)` with one `.onDrop(of:delegate:)`.
- Create `bunny/Views/RowDropDelegate.swift`.
- Create `bunny/Controllers/TaskMover.swift`, which applies `TaskPlacement`s to SwiftData, unpins new subtasks and expands the new parent.

**Interfaces:**
- Consumes D1.
- `@MainActor enum TaskMover { static func perform(dragged: UUID, target: UUID, zone: DropZone, in context: ModelContext) }`. It fetches all non-archived tasks, builds `[TaskNode]`, calls `TaskMoveRules.move` and writes the results.

- [ ] **Step 1: RowDropDelegate.** It conforms to `DropDelegate` and holds the task ID, a `ModelContext`, and a callback to set the row's `@State var dropIndicator: DropZone?` / `isFileTargeted`.
  - `validateDrop`: true if `info.hasItemsConforming(to: [.fileURL])` or `[.utf8PlainText]`.
  - `dropEntered`/`dropUpdated`:
    - If file URLs: set `isFileTargeted = true`, call `PanelCoordinator.shared.fileDragEntered(id)`, return `DropProposal(operation: .copy)`.
    - Otherwise: compute the zone from `info.location.y` and the row height (captured via `GeometryReader`/`onGeometryChange`), set `dropIndicator`, return `.move`.
  - `dropExited`: clear the indicators.
  - `performDrop`:
    - File URLs: load them via `info.itemProviders(for: [.fileURL])`, using `loadItem`/`loadObject(ofClass: URL.self)`, then `ShelfService.add` on main.
    - Otherwise: load the String, parse the UUID, `resolve`, then `TaskMover.perform` inside `withAnimation`.
    - Clear the indicators.
- [ ] **Step 2: TaskRowView.**
  - `.onDrag { NSItemProvider(object: task.id.uuidString as NSString) }` on every row.
  - The indicator is an overlay: a 2 pt `Color.accentColor` capsule at the top or bottom edge, or an accent 1.5 pt rounded stroke for `.into`.
  - Keep the file-target tint, hover and click-lock unchanged.
- [ ] **Step 3: ContentView.** Remove the old reorder code. Make sure subtasks of a collapsed parent still move with it.
- [ ] **Step 4: Verify and commit.** The xcodebuild Debug build must have 0 errors, and `swift test` must pass. Commit `fix: drag to reorder and nest tasks (single row drop target)`.

### Task D3: Core model/effort + MCP wiring in runners, Codex model list

**Files:**
- Modify `bunny/Core/Agents/AgentRunner.swift`, `ClaudeCodeRunner.swift`, `CodexRunner.swift`, `CodexWire.swift` and `AgentPromptBuilder.swift`.
- Create `bunny/Core/Agents/CodexModelCatalog.swift`.
- Tests: update and add the runner, wire and prompt tests.

**Interfaces (Produces):**
```swift
struct BunnyToolsEndpoint: Equatable, Sendable { var url: String; var token: String; var taskID: UUID? }
struct AgentRunOptions { var cliPath; var autonomy; var environment; var model: String?; var effort: String?; var tools: BunnyToolsEndpoint? }  // new fields default nil
struct CodexModel: Equatable, Sendable { let id: String; let displayName: String; let efforts: [String]; let defaultEffort: String?; let isDefault: Bool }
enum CodexWire { static func modelList(id: Int) -> Data; static func parseModelList(_ line: Data) -> [CodexModel]? }
enum CodexModelCatalog { nonisolated static func fetch(cliPath: String, environment: [String: String], timeout: TimeInterval = 8, completion: @escaping @Sendable ([CodexModel]?) -> Void) }
```
- **Claude argv:** `--model <m>` when non-empty, and `--effort <e>` when non-empty. When `tools` is set, add `--mcp-config <json>` using the exact JSON from `docs/superpowers/research/mcp-http.md`. The headers are `Authorization: Bearer <token>`, plus `X-Bunny-Task: <uuid>` when `taskID` is set. Also add `--allowedTools mcp__bunny`, or the verified pattern from that doc.
- **Codex:**
  - `thread/start` gets `model` when set.
  - `config.mcp_servers.bunny` is added per `mcp-http.md` when `tools` is set; merge it with any existing `sandbox_workspace_write` config.
  - `turn/start` gets `effort` when set.
- `CodexModelCatalog` launches `codex app-server --stdio` with `AgentProcess`, sends `initialize`, `initialized` and `model/list` (with `includeHidden: false`), parses the result, terminates the process and completes on the main queue. It completes with nil on timeout or error.
- **System appendix (both harnesses):** add "You can read and manage the user's Bunny task list with the `bunny` tools (list_tasks, create_task, create_tasks, update_task, complete_task, add_to_shelf). Use them when the user asks you to add or organize tasks." Include this only when tools are available. Change `systemAppendix(for:)` to `systemAppendix(for:toolsAvailable:)`, defaulting to false, and update callers.
- **Tests:**
  - argv with and without model/effort/tools
  - the exact mcp-config JSON (decode it and compare the dictionary)
  - codex thread/start and turn/start JSON with model/effort/mcp
  - `parseModelList` against a fixture. Capture it from the real CLI via a small script, or build it from `Model.ts` field names: id, model, displayName, supportedReasoningEfforts[{reasoningEffort, description}], defaultReasoningEffort, hidden, isDefault. Check `ReasoningEffortOption` in the schema at `/private/tmp/claude-501/-Users-nt-bunny/339a7c84-a22d-4368-a011-7253e1dd8293/scratchpad/codex-proto/ts/v2/`.
  - the fake codex answering `model/list`
- Commit: `feat(core): model/effort and bunny tools wiring for runners; codex model catalog`.

### Task D4: Core MCP server protocol

**Files:** Create `bunny/Core/BunnyTools/MCPServerCore.swift`, `BunnyToolsSchema.swift` and `BunnyToolArguments.swift`. Tests go in `Tests/BunnyCoreTests/BunnyTools/*`.

**Interfaces (Produces):**
```swift
struct HTTPRequestLite { var method: String; var path: String; var headers: [String: String]; var body: Data }   // header names lowercased
struct HTTPResponseLite: Equatable { var status: Int; var headers: [String: String]; var body: Data }
enum BunnyToolCall: Equatable {
    case listTasks(includeCompleted: Bool)
    case createTask(NewTask, parentID: UUID?)
    case createTasks([NewTask], parentID: UUID?)
    case updateTask(id: UUID, title: String?, description: String?, timerMinutes: Double?)
    case completeTask(id: UUID, completed: Bool)
    case addToShelf(taskID: UUID, paths: [String])
}
struct NewTask: Equatable { var title: String; var description: String?; var timerMinutes: Double?; var subtasks: [String] }
protocol BunnyToolsBackend: AnyObject { func perform(_ call: BunnyToolCall, contextTaskID: UUID?) -> Result<String, BunnyToolError> }  // String = JSON text for the tool result
struct BunnyToolError: Error, Equatable { var message: String }
final class MCPServerCore {
    init(token: String, backend: BunnyToolsBackend)
    func handle(_ request: HTTPRequestLite) -> HTTPResponseLite
}
enum BunnyToolArguments { static func parse(name: String, arguments: [String: Any]) -> Result<BunnyToolCall, BunnyToolError> }
enum BunnyToolsSchema { static var tools: [[String: Any]] }  // name, description, inputSchema (JSON Schema)
```
**Behavior** (follow the minimal-server requirements in `mcp-http.md` exactly):
- Only `POST /mcp` is handled. `GET` returns 405, other paths 404.
- The bearer token is checked with a constant-time comparison; a mismatch returns 401.
- JSON-RPC methods:
  - `initialize`: echo a supported protocolVersion; capabilities `{tools: {}}`; serverInfo `{name: "bunny", version}`.
  - `notifications/*`: return 202 with an empty body.
  - `ping`: `{}`.
  - `tools/list`: returns the schema.
  - `tools/call`: parse the arguments, call the backend, and return `{content: [{type: "text", text}], isError: false}`. A `BunnyToolError` becomes `isError: true` with the message.
  - Unknown method: `-32601`. Malformed JSON: `-32700`.
- `X-Bunny-Task` becomes the `contextTaskID`.
- **Validation:** titles are trimmed, must be non-empty, and are capped at 200 characters. Descriptions are capped at 10k. `timer_minutes` must be > 0 and ≤ 1440. Batches hold at most 100. UUIDs are parsed strictly. `paths` must be absolute.

- [ ] Write the tests first:
  - auth (401 on missing or wrong token)
  - initialize
  - tools/list names
  - each tool's argument parsing (valid and invalid)
  - notification → 202
  - unknown method → -32601
  - malformed JSON → -32700
  - backend error → isError
  - context header passthrough
- [ ] Then implement, and commit `feat(core): bunny tools MCP server core`.

### Task D5: App — MCP listener, SwiftData backend, supervisor wiring

**Files:**
- Create `bunny/Controllers/BunnyToolsServer.swift`: an `NWListener` on 127.0.0.1 with a minimal HTTP/1.1 parser (request line, headers, and a `Content-Length` body; keep-alive not required, so close after each response; 1 MB limit). It serves via `MCPServerCore`.
- Create `bunny/Controllers/BunnyToolsBackendImpl.swift`, which does SwiftData operations on the main context. It reuses `ShelfService`, the `BunnyTask` init and `sortOrder` semantics (append), and `AgentSupervisor.taskWillArchiveOrDelete` where relevant.
- Modify `AgentSupervisor.swift` to pass `AgentRunOptions.tools`, `model` and `effort`. Model and effort come from the task's `agentModel`/`agentEffort` or else the settings.
- Modify `AppDelegate.swift`: start the server at launch and stop it at quit.
- Modify `bunny/Models/BunnyTask.swift`: add `agentModel: String? = nil` and `agentEffort: String? = nil`.
- Modify `AgentSettings.swift`: add model/effort per harness, plus `toolsPort` and `toolsToken` (generated on first read).

The endpoint is `http://127.0.0.1:<port>/mcp`. `list_tasks` JSON: `[{id, title, description, completed, parent_id, timer_minutes, agent_state, shelf: [paths], subtasks: [...] }]`.

- Live check (required): with Bunny's server not runnable outside the app, write a tiny test harness instead. It is a scratch Swift script that constructs `MCPServerCore` with a fake backend, serves it through the same `NWListener` code (copy the file into the scratch package), and runs a real `claude -p --model haiku` with the `--mcp-config` from D3 to create a task. Assert the backend received `createTask`.
- Verify: an xcodebuild Debug build with 0 errors, and `swift test`. Commit `feat: bunny tools server for agents; model/effort per run`.

### Task D6: App UI — model/effort pickers, single Start, global tools install

**Files:** Modify `bunny/Views/Settings/AgentSettingsSection.swift`, `bunny/Views/Panel/AgentPanelSection.swift` and `bunny/Views/AgentButton.swift`. Create `bunny/Controllers/BunnyToolsInstaller.swift`.

- **Settings → Agents:**
  - Per harness, add a model picker. Claude: Default/fable/opus/sonnet/haiku/Custom…, where Custom shows a text field. Codex: Default + the `CodexModelCatalog.fetch` results, loaded off-main on appear with a spinner, + Custom….
  - Add an effort picker: Default + the efforts (for Codex, the selected model's efforts).
  - Add a new "Bunny tools" section. It shows the port, a "Copy MCP URL" button, and per-CLI Install/Uninstall buttons for "Bunny tools in all Claude Code / Codex sessions" with a status line. It uses `BunnyToolsInstaller`, which runs the exact commands from `mcp-http.md` off-main and reports success or failure.
- **Panel idle state:** one `.glassProminent` button reading "Start with <Default harness>", plus a `Menu` (chevron) holding:
  - "Start with <other harness>"
  - a "Model" submenu, which sets the task's `agentModel` for this run
  - an "Effort" submenu, which sets `agentEffort`
  - "Use defaults", which clears both
  The main button's subtitle shows the resolved model and effort.
- **AgentButton:** the tooltip shows the resolved harness · model · effort. The context menu becomes a "Start with…" submenu (Claude Code / Codex) plus the existing items.
- Verify: an xcodebuild Debug build with 0 errors. Commit `feat: model/effort pickers, default-agent start, bunny tools install`.

### Task D7: Icon (design agent; already in progress)

## Execution
- Parallel in worktrees: D1, D3 and D4 (Core, disjoint files).
- Then D2 (after D1) and D5 (after D3 and D4), in parallel since their files are disjoint.
- Then D6.
- Then the final review, a Release build and reinstall.
