# Spec D — Model & Effort, Default-Agent Start, Drag to Reorder/Nest, Bunny Tools for Agents, Frosted 🐇 Icon

Date: 2026-09-24 · Status: approved-by-delegation (owner: "make the best choices")
Builds on Specs A–C. Protocol references: `docs/superpowers/research/claude-stream-json.md`,
`codex-app-server.md`, `mcp-http.md` (HTTP MCP config for both CLIs, verified).

## 1. Owner requests (verbatim intent)
1. "Select the model I want to use and the effort."
2. "If I choose my default harness, why do I have to select what I want to run when I
   click the agent icon? It should just use the default one."
3. "Can the agent create more tasks within Bunny? e.g. go through my Canvas and create
   tasks for my assignments."
4. "Why can't I move tasks around anymore? Move a task above or below, or under a task
   making it a subtask."
5. "A new icon: blurry glass, light grey, with 🐇."

## 2. Model & effort
- Per-harness defaults in Settings → Agents:
  - Claude Code model: `Default` (no flag) · `fable` · `opus` · `sonnet` · `haiku` ·
    `Custom…` (free text, e.g. `claude-opus-5-5`). Effort: `Default` · `low` · `medium` ·
    `high` · `xhigh` · `max` → `--model <m>` / `--effort <e>`.
  - Codex model: list fetched live from `codex app-server` `model/list`
    (`displayName`, `supportedReasoningEfforts`, `defaultReasoningEffort`, `isDefault`,
    hidden excluded), cached in memory; fallback to `Default` + `Custom…` if the fetch
    fails. Effort: `Default` + the selected model's supported efforts →
    `thread/start.model`, `turn/start.effort`.
- Per-run override: the panel's start control (below) lets the owner pick harness,
  model and effort for this run; the choice is stored on the task
  (`agentModel: String?`, `agentEffort: String?`) so resumes use the same settings.
- UserDefaults keys: `agent.claude.model`, `agent.claude.effort`, `agent.codex.model`,
  `agent.codex.effort` (empty string = Default).
- Resolution (`RunSettingsResolver`, the single source for start/answer/resume, the row
  tooltip/logo and the panel caption): harness = the explicitly requested one, else the
  task's `agentHarness`, else Settings' default. The task's model/effort apply only when they
  were chosen for that harness (the agent menu stores its harness together with a model or
  effort choice); otherwise Settings' values. Blank = the CLI's default. Terminal resumes
  ("Open Session") pass the same model/effort (`claude --model/--effort`, `codex resume -m …
  -c model_reasoning_effort=…`).
- The Codex model list is prefetched once at launch (after CLI detection) and refreshed when
  Settings opens; menus show "Loading models…" / "Model list unavailable" while it's empty.
- The agent menu (Agent/Model/Effort/Use Defaults) is shown only while the task has no
  session and no active run; afterwards only the session items (Open Session, Stop, Clear).

## 3. Starting uses the default agent
- Row ✦ button: left click = start with Settings' default harness/model/effort (already
  true in code); its tooltip shows the resolved choice ("Hand off to Claude Code · opus ·
  high"). Right-click menu keeps alternatives but is titled "Start with…" submenu.
- Panel idle state: ONE primary button "Start with ‹Default harness›" plus a small
  trailing menu button (chevron) offering: other harness, model picker, effort picker for
  this run. No more two equal "Start with Claude Code / Start with Codex" buttons.

## 4. Drag to reorder and nest (bug fix + feature)
Root cause (debugged): Spec A added a row-level `.dropDestination(for: URL.self)` that
covers the whole group-level reorder drop target; SwiftUI delivers drops to the
innermost drop target and does not bubble type mismatches, so task drops died.
Design:
- Every row (parent and subtask) is draggable: `.onDrag` provides the task UUID as
  `public.utf8-plain-text` (unchanged payload).
- Every row has ONE `.onDrop(of: [.fileURL, .utf8PlainText], delegate: RowDropDelegate)`:
  - File URLs → shelf add (existing behavior, incl. opening the panel while targeted).
  - Task UUID → a move computed from the pointer's y within the row:
    top 30 % = **above**, bottom 30 % = **below**, middle 40 % = **into** (make subtask).
  - Visual feedback: 2 pt accent insertion line above/below the row, or an accent
    rounded highlight + indent chevron for "into".
- Rules (pure, in Core `TaskMoveRules`, unit tested):
  - Only one nesting level. "Into" is allowed only when the target is top-level, the
    dragged task is not the target, and the dragged task has no subtasks; otherwise
    "into" degrades to "below".
  - Dropping above/below a subtask places the dragged task as a sibling in that
    subtask's parent (a top-level task without subtasks can become a subtask this way).
  - Dropping above/below a top-level task makes the dragged task top-level at that
    position (un-nesting a subtask).
  - A parent moves with its subtasks (they keep `parentID`).
  - Dropping a task on itself or on its own subtask is a no-op.
  - Sort orders are renumbered 0…n within the affected sibling lists (source and
    destination) so ordering is dense and deterministic.
  - Nesting sets the new parent's `isExpanded = true`.
  - Pinned tasks that become subtasks are unpinned (subtasks can't be pinned).
  - A task with a timer or any agent state (a run, or a session, finished or not) can't
    move under a new parent: it may move to the top level or reorder within its current
    parent (subtasks have no agent button, so nesting would hide the session).

## 5. Bunny tools for agents (MCP)
- Bunny hosts a local MCP server (Streamable HTTP, JSON-RPC over POST, application/json
  responses) on `127.0.0.1:<port>/mcp` using Network.framework `NWListener`, bound to
  loopback only. Port: fixed default 47823; if busy, pick a free port and warn in Settings
  that the global install must be refreshed. **Deviation:** the port is not editable in the
  UI (only the `bunnyTools.port` default can change it). Global installs always use the fixed
  port, so Install is disabled while the server runs on a fallback port. If the fallback port
  fails too, the server retries once after 5 s.
- Auth: bearer token (random 32 bytes hex) stored in UserDefaults
  `bunnyTools.token`; every request must carry `Authorization: Bearer <token>`
  (401 otherwise). Settings → Bunny tools has "Regenerate Token" (new token, server restart;
  global installs must be reinstalled). Requests from Bunny-launched sessions additionally carry
  `X-Bunny-Task: <taskUUID>` so created tasks can default to that context.
- Tools (all main-actor SwiftData operations):
  - `list_tasks {include_completed?: bool}` → id, title, description, parent_id,
    completed, timer, agent state, shelf paths; top-level with nested subtasks.
  - `create_task {title, description?, parent_id?, timer_minutes?, subtasks?: [string]}`
    → id. Appends at the end of the target sibling list. At most 50 subtasks per task.
    Subtasks can't have timers: `timer_minutes` with `parent_id` is a tool error.
  - `create_tasks {tasks: [ {title, description?, timer_minutes?, subtasks?} ], parent_id?}`
    (batch, for "all my assignments").
  - `update_task {id, title?, description?, timer_minutes?}`: `timer_minutes` 0 or null removes
    the timer; setting a timer on a subtask is a tool error.
  - `complete_task {id, completed?: bool = true}`: un-completing also clears "completed by
    agent"; a failed save is a tool error.
  - `add_to_shelf {task_id, paths: [string]}` (absolute paths; missing paths reported).
  - Titles trimmed, capped at 200 chars; batch ≤ 100; unknown ids → tool error result.
    JSON booleans are not accepted as numbers.
- Agent wiring (per verified configs in `mcp-http.md`):
  - Claude: `--mcp-config <json>` with the http server + headers, and
    `--allowedTools mcp__bunny` so Bunny tools never prompt.
  - Codex: `thread/start.config.mcp_servers.bunny` with url + headers, plus
    `bearer_token_env_var: "BUNNY_TOOLS_TOKEN"` set in the app-server environment. Codex merges
    this key by key into a global `[mcp_servers.bunny]`, so overriding the variable keeps a
    stale global entry from breaking the run (mcp-http.md, "Codex config merge").
  - The system appendix tells agents they can manage the user's Bunny tasks with these
    tools (e.g. create tasks for assignments they find).
- Global install (Settings → Agents → "Bunny tools in all Claude Code / Codex sessions",
  off by default): Install writes the user-level config via the CLIs
  (`claude mcp add … --scope user`, Codex config) with the fixed port and token;
  Uninstall removes it. Status shown per CLI. For Codex, `codex mcp add bunny --url …` is
  followed by a rewrite of `[mcp_servers.bunny]` to `http_headers = { Authorization = … }` +
  `default_tools_approval_mode = "approve"`, with no `bearer_token_env_var`. The section
  footer says the token is written to `~/.claude.json` / `~/.codex/config.toml` and is
  readable by any program running as the user.
  Sessions reopened in a terminal ("Open Session") only have Bunny tools if they are
  installed globally; the tooltips say so.
- UI: tasks created by agents appear immediately (SwiftData on the main context), like
  any other task.

## 6. Icon
Light-grey frosted glass background (dark: graphite frosted), the 🐇 Apple Color Emoji
as the hero layer (natural colors, soft shadow). Menu-bar icon unchanged. Caveat:
Apple emoji artwork is fine for a self-distributed app; not for App Store icons.

## 7. Testing
Core: `TaskMoveRules` (all rules above), `MCPProtocol` codec (initialize, tools/list,
tools/call parse/encode, errors), `BunnyToolArguments` validation, runner argv/config
(model, effort, mcp config), `CodexWire.modelList` parse. App: direct-toolchain compile +
xcodebuild; live check: a real Claude session creates a task through the server.
