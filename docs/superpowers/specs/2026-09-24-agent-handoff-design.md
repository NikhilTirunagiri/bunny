# Spec B — Hand a Task to Claude Code / Codex

Date: 2026-09-24 · Status: approved-by-delegation (owner asked us to make the calls)
Depends on Spec A (`2026-09-24-task-panel-shelf-design.md`): side panel, shelf, `PanelCoordinator`, `BunnyCore`.
Protocol references (verified on this Mac): `docs/superpowers/research/claude-stream-json.md`,
`codex-app-server.md`, `open-session-in-app.md`.

## 1. Intent

Create a task from the menu bar, then hand it off to a coding agent with one
click. The agent works in the background with everything the task knows —
title, description, shelf files/folders, subtasks and timer. Bunny shows what
the agent is doing at a glance, pulls the owner in only when the agent asks
something, and lets them jump into the live conversation in their editor or
terminal.

Owner requirements (verbatim intent):
- Harnesses: Claude Code and Codex, both connectable.
- Agent button on each task, right after pin and before archive; click → the
  respective agent starts. If a session already exists, clicking it opens that
  session in the preferred app (Terminal / Ghostty / VS Code / Cursor).
- Running → title "flows" left→right between ~30 % and 100 % opacity.
- Agent finished → task turns **green** (manual check-off stays blue).
- Agent needs input → task turns **yellow**; clicking it opens the panel with
  the question and options/input; answering continues the agent.
- "Chat about this" in the panel opens the same session in the preferred app.
- The agent inherits the timer.

## 2. Scope

In: harness runners (Claude stream-json, Codex app-server), supervisor,
persistence, prompt/context building, timer budget, row states and effects,
agent button, panel agent section (status, questions, approvals, summary,
chat, stop), Settings → Agents, open-in-app launcher, notifications, menu-bar
attention dot.

Out: editing agent output inside Bunny, multiple concurrent sessions per
task, remote/cloud agents, Paseo.

## 3. Concepts

- **Harness** — `claudeCode` | `codex`.
- **Run state** (persisted on the task):
  `idle` → `running` ⇄ `needsInput` → `finished` | `failed` | `stopped`;
  any active state → `handedOff` when the owner takes the session into their app.
- **Session id** — Claude `session_id` / Codex `threadId`, stored on the task;
  used to resume in the background and to open in apps.
- **Pending question** — the one thing the agent is waiting on (Claude
  AskUserQuestion, a permission approval, or a Codex `<bunny-question>` block).

## 4. Data model (additive to `BunnyTask`)

| field | type | default |
|---|---|---|
| `agentHarness` | `String?` | nil (raw value of `AgentHarness`) |
| `agentState` | `String` | `"idle"` (raw `AgentRunState`) |
| `agentSessionID` | `String?` | nil |
| `agentWorkingDirectory` | `String?` | nil |
| `agentActivity` | `String` | `""` — latest one-line progress |
| `agentSummary` | `String` | `""` — final message / failure reason |
| `agentQuestionData` | `Data?` | nil — JSON `AgentQuestion` |
| `agentStartedAt` / `agentFinishedAt` | `Date?` | nil |
| `completedByAgent` | `Bool` | false |

On successful finish: `isCompleted = true`, `completedAt = now`,
`completedByAgent = true`. Manually unchecking clears `completedByAgent`.
Manually checking an agent task does not change `agentState`.

## 5. Context handed to the agent

`AgentBrief` (Core): title, description, subtasks (title + done flag, in
order), shelf entries (absolute path + isDirectory, missing ones skipped),
time budget (seconds, optional), working directory, extra directories.

**Working directory** (`WorkingDirectoryResolver`, Core):
1. first shelf folder; else 2. parent folder of the first shelf file; else
3. Settings → Default workspace (default `~`).
Extra dirs = every other shelf folder and every distinct parent folder of other
shelf files (deduped, excluding the cwd). Claude: `--add-dir` each.
Codex: `config.sandbox_workspace_write.writable_roots`.

**Prompt** (`AgentPromptBuilder`, Core) — first user message, markdown:
```
# Task: <title>
<description or "(no description)">
## Subtasks            (omitted if none)
- [ ] 1. <title>
- [x] 2. <title>
## Files and folders   (omitted if none)
- <abs path> (folder)
## Time budget         (omitted if no timer)
You have <N> minutes (until <HH:mm local>). Prioritize finishing within it.
```
**System appendix** (Claude `--append-system-prompt`; Codex `developerInstructions`):
- You were handed this task from Bunny, a menu-bar task list. Work autonomously.
- Only ask the user when genuinely blocked or when a decision is theirs.
  Claude: use the AskUserQuestion tool. Codex: end your turn with exactly one
  `<bunny-question>{"question": "...", "options": ["...", "..."]}</bunny-question>`
  block (options optional; omit for free-text answers) and nothing after it.
- When you finish, reply with a short summary of what you did. If you
  completed specific subtasks, add a final line
  `<bunny-subtasks-done>1,3</bunny-subtasks-done>` with their numbers.

Marker parsing (`AgentMarkers`, Core) strips both blocks from displayed text.
Completed subtask numbers mark those subtasks `isCompleted` on success.

## 6. Runners (Core, Foundation-only, unit + fake-CLI tested)

`AgentProcess` — wraps `Process`: argv, cwd, environment (login-shell `PATH`
from `ShellEnvironment`, plus `TERM=dumb`), stdout line stream
(`JSONLineBuffer`), stderr kept in a 64 KB ring for failure messages,
`write(line:)`, `terminate()` (SIGTERM, SIGKILL after 3 s), exit callback.

Common runner interface:
```
protocol AgentRunner: AnyObject {
  var onEvent: ((AgentEvent) -> Void)? { get set }   // delivered on main queue
  func start(brief: AgentBrief, resumeSessionID: String?, initialMessage: String?)
  func answer(_ answer: AgentAnswer)                    // replies to the pending question
  func send(_ text: String)                             // new user turn
  func interrupt()
  func terminate()
}
enum AgentEvent { sessionStarted(id), activity(String), question(AgentQuestion),
                  turnFinished(text: String, success: Bool), failed(String), exited(code) }
```

**ClaudeCodeRunner** — argv per research doc; permission mode from Settings
(`autonomous` → `bypassPermissions`, `askFirst` → `acceptEdits`). Maps:
`system/init` → sessionStarted; assistant text → activity (first line,
≤ 120 chars); tool_use → activity "Running <Tool>…"; `can_use_tool` for
AskUserQuestion → `question(.choices)`; other `can_use_tool` → `question(.approval)`;
`result` success → turnFinished(text, true); `result` error → turnFinished(text/errors, false)
unless we interrupted for a timeout; process exit before any result → failed(stderr tail).
Answers: allow + `updatedInput` with `answers` keyed by exact question text
(multi-select joined with ", "); approval allow/deny.
Resume: `--resume <id>`, then the pending answer (if the original process died)
is sent as a plain user message: `Answer to your earlier question "<q>": <a>`.

**CodexRunner** — `codex app-server --stdio`; `initialize` → `initialized` →
`thread/start` (or `thread/resume` with `threadId`) with cwd, `approvalPolicy`
(`autonomous` → `never`, `askFirst` → `on-request`), `sandbox: workspace-write`,
`developerInstructions`, writable roots → `turn/start` with the prompt.
`item/agentMessage/delta` accumulates; `item/completed` agentMessage →
activity; commandExecution → "Running <cmd>…". `turn/completed completed` →
if last agent message contains `<bunny-question>` → question(.freeform or
.choices) else turnFinished(text, true); `failed` → turnFinished(error, false);
`interrupted` handled by supervisor. Server approval requests
(`item/commandExecution/requestApproval`, `item/fileChange/requestApproval`)
→ question(.approval); reply per the generated schema's decision enum.
Unknown server requests → JSON-RPC error `-32601`.
Answer to a `<bunny-question>` → new `turn/start` with the answer text.

## 7. Supervisor (app, main actor)

`AgentSupervisor.shared` owns `[taskID: AgentRunner]` and all state writes.
- `start(task, harness?)` — resolves harness (argument, else Settings default),
  checks CLI availability (else shows failure "Claude Code not found — set its
  path in Settings"), resolves cwd, starts the task timer if it has a duration
  and isn't running, builds brief, launches, sets `running`.
- Events → task fields; `question` → `needsInput` + `agentQuestionData`
  + notification "Bunny: <task> needs your input"; `turnFinished(success)` →
  `finished` (+ green completion, subtasks) + notification "<task> is done";
  `turnFinished(false)`/`failed` → `failed` + summary.
- `answer(taskID, answer)` — live runner → `runner.answer`; no live runner
  (Bunny restarted) → resume session with the answer as initial message.
  Clears question, state `running`.
- `stop(taskID)` — interrupt, then terminate after 3 s; state `stopped`.
- `openSession(task)` — if `running`/`needsInput`: stop the background process
  first and set `handedOff` (one process per session). Then `SessionLauncher`
  opens it in Settings → Open sessions in.
- **Timer**: when the task's timer expires while `running`, interrupt and send
  "Time's up — stop here and reply with a summary of what's done and what's
  left." Its result → `stopped` with that summary (not green). If
  `needsInput` at expiry → leave the question open, add "Time ran out" to
  activity.
- Archiving or deleting a task with a live runner stops it.
- **App launch**: tasks persisted as `running` → `stopped` with activity
  "Interrupted — Bunny quit"; `needsInput` stays (answer resumes).
- Menu bar: while any task is `needsInput`, the status icon shows a small
  yellow dot (non-template composed image).

## 8. UI

**Row (`TaskRowView`)**, parent tasks only get the agent button:
- Button between pin and archive. Symbol by harness — Claude Code `sparkle`,
  Codex `chevron.left.forwardslash.chevron.right` (default harness when idle).
  Tint by state: running accent + `.symbolEffect(.pulse)`, needsInput yellow,
  finished green, failed red, stopped/handedOff secondary.
  Click: no session → start; session exists → open session.
  Right-click menu: Start with Claude Code · Start with Codex · Open Session in
  <App> · Stop Agent · Clear Agent (resets agent fields; only when not active).
- Title effects: `running` → `ShimmerText` (gradient mask sweeping left→right,
  opacity 0.3 → 1.0 → 0.3, 1.8 s period, `TimelineView(.animation)`;
  reduced-motion → static 0.6 opacity pulse-free).
  `needsInput` → title and checkbox yellow (`Color.yellow` mixed toward
  `.orange` for light-mode contrast), checkbox symbol `questionmark.circle.fill`;
  row click locks the panel (Spec A) so the question is right there.
  `failed` → checkbox `exclamationmark.circle` red.
  Completed with `completedByAgent` → green `checkmark.circle.fill` (manual stays accent blue).

**Panel agent section (`AgentPanelSection`)** mounted in `TaskPanelView.agentSection`:
- Header: harness name, state label, elapsed time; latest activity line (secondary).
- Question (`needsInput`): per question — header, text, options as selectable
  rows with descriptions (radio or checkboxes for multiSelect), "Other…" field;
  free-text questions get a multiline field. Primary `Send` (`.glassProminent`).
  Approval: tool name + summary (command/path) with `Allow` / `Deny`.
- Summary (`finished`/`failed`/`stopped`): selectable text, scrolls.
- Actions row: `Chat about this` (opens session), `Stop` while active,
  `Start with Claude Code/Codex` when idle.

**Settings → Agents**
- Default agent: Claude Code / Codex (segmented).
- Claude Code path, Codex path — auto-detected via login shell `command -v`,
  editable, with a status dot (found/not found) and "Detect" button.
- Autonomy: "Autonomous" (default) / "Ask before running commands".
- Open sessions in: Terminal / Ghostty / VS Code / Cursor (only installed ones enabled).
- Default workspace folder (folder picker, default `~`).

## 9. Open in app (`SessionLauncher` + Core `SessionLaunchPlanner`)

Per `open-session-in-app.md`:
- Terminal: write `~/Library/Application Support/Bunny/launch/<uuid>.command`
  (`#!/bin/zsh -l`, `cd <quoted dir> && exec <cli> --resume <id>` / `exec <codex> resume <id>`),
  chmod 755, `open -a Terminal <file>`; delete after 60 s.
- Ghostty: `open -na Ghostty.app --args --working-directory=<dir> -e /bin/zsh -lc "<cmd>"`.
- VS Code / Cursor + Claude: run editor CLI with `<dir>`, then after 1 s open
  `vscode://anthropic.claude-code/open?session=<id>` / `cursor://…`.
- VS Code / Cursor + Codex: open the folder in the editor and run the
  Terminal route for `codex resume <id>` (no Codex IDE URI exists).
Planner is pure (returns an enum of actions); launcher executes them.

## 10. Build/config

- Sandbox is already off (Spec A). No Apple Events needed (the `.command` route).
- `Info.plist` keys unchanged. Notifications already authorized at launch.

## 11. Testing

Core (`swift test`): prompt builder, cwd resolver, markers, Claude/Codex codecs
(against the verified JSON), `JSONLineBuffer`, `SessionLaunchPlanner`, and
runner behavior against **fake CLIs** (small Python scripts under
`Tests/BunnyCoreTests/Fixtures/` that speak the protocol). Optional live smoke
test gated by `BUNNY_LIVE_AGENT_TESTS=1` (real `claude`/`codex`, cheap model).
App code: static review; build in Xcode before merge.

## 12. Error handling

- CLI missing / not executable → `failed` with a Settings pointer.
- Process exits without result → `failed` with the last stderr lines.
- Malformed JSON lines → ignored (logged in DEBUG).
- Launching the chosen app fails → fall back to Terminal route; if that fails,
  copy the resume command to the clipboard and show it in the panel.
