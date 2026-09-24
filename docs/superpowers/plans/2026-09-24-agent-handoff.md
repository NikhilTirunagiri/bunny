# Agent Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One click hands a Bunny task (title, description, shelf, subtasks, timer) to a background Claude Code or Codex session. Bunny shows running/needs-input/finished states and relays questions through the side panel. Existing sessions open in Terminal, Ghostty, VS Code or Cursor.

**Architecture:** Everything that talks to the CLIs lives in `bunny/Core/Agents/`. That code is Foundation-only and tested with `swift test` against verified protocol fixtures and fake-CLI scripts. It covers:
- value types
- prompt/context building
- wire codecs
- process runners
- the launch planner

The app side adds persisted agent fields on `BunnyTask`, a main-actor `AgentSupervisor` that maps runner events to task state, a `SessionLauncher` that executes launch plans, and SwiftUI for the row, panel and settings.

**Tech Stack:** Swift 5 mode, Foundation `Process`, SwiftUI, SwiftData, swift-testing, python3 (fake CLIs in tests only).

**Spec:** `docs/superpowers/specs/2026-09-24-agent-handoff-design.md` (read it — §5 prompt text, §6 runner mapping, §7 supervisor rules, §8 UI are binding).
Protocol references: `docs/superpowers/research/claude-stream-json.md`, `codex-app-server.md`, `open-session-in-app.md`, fixtures in `docs/superpowers/research/fixtures/*.jsonl` (real Codex stdout captures, one JSON-RPC message per line).

## Global Constraints

- App target build setting `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 5 mode): Core files compiled into the app are implicitly `@MainActor` there, but nonisolated under SwiftPM. Write Core code that is correct under both: background work only inside closures handed to `DispatchQueue`/`Process` handlers that touch lock-protected or queue-confined state, and every callback to clients hops to `DispatchQueue.main`. Do not use `nonisolated` on type declarations (the CLT compiler is Swift 6.1).

- `bunny/Core/**`: Foundation only (no SwiftUI/AppKit/SwiftData). Swift 5 language mode. Everything `internal` (tests use `@testable import BunnyCore`).
- The Xcode project auto-includes new files under `bunny/`. Do not edit `project.pbxproj`.
- No Xcode on this machine: app-target code (outside `bunny/Core`) cannot be compiled. Self-review every API against the macOS 26 SDK. Core code MUST pass `swift test`.
- Tests reading fixtures locate them via `#filePath` (e.g. `URL(fileURLWithPath: #filePath).deletingLastPathComponent()...`), not SwiftPM resources.
- Commits: repo-local author only. Never add `Co-Authored-By`, `Claude-Session` or any AI attribution.
- Harness raw values: `claudeCode`, `codex`. Run state raw values: `idle`, `running`, `needsInput`, `finished`, `failed`, `stopped`, `handedOff`. Autonomy raw values: `autonomous`, `askFirst`. Open-in raw values: `terminal`, `ghostty`, `vscode`, `cursor`.
- Markers: `<bunny-question>{json}</bunny-question>`, `<bunny-subtasks-done>1,3</bunny-subtasks-done>`.
- Shimmer: opacity 0.3 → 1.0 → 0.3, period 1.8 s, left→right.
- UserDefaults keys: `agent.defaultHarness`, `agent.claudePath`, `agent.codexPath`, `agent.autonomy`, `agent.openIn`, `agent.defaultWorkspace`.

## Review Focus

1. Agent asks a question, the owner quits Bunny, relaunches, then answers. The answer must resume the session, not be lost (Task 5 `answer` with no live runner → `resume`).
2. Two tasks run agents at the same time. Events must route to the right task (Task 5: runner map keyed by task id, closures capture the id).
3. A CLI is missing or not on the GUI app's PATH. The task shows `failed` with a clear message rather than hanging in `running` (Task 4 `AgentProcess` launch-failure test; Task 5 availability check).
4. A task title or path contains quotes or spaces, or a shelf path has `'`. The launch command must not break or inject (Task 3 quoting tests).
5. Clicking the agent button while an agent is running must open the session rather than start a duplicate (Task 5 `primaryAction`, Task 6 button).

## File Map

| File | Responsibility | Task |
|---|---|---|
| `bunny/Core/Agents/AgentTypes.swift` | Harness, RunState, Autonomy, OpenInApp, Question/Answer, Brief, Event | 1 |
| `bunny/Core/Agents/AgentPromptBuilder.swift` | prompt + system appendix text | 1 |
| `bunny/Core/Agents/WorkingDirectoryResolver.swift` | cwd + extra dirs | 1 |
| `bunny/Core/Agents/AgentMarkers.swift` | parse/strip bunny markers | 1 |
| `bunny/Core/Agents/JSONLineBuffer.swift` | byte stream → lines | 2 |
| `bunny/Core/Agents/ClaudeWire.swift` | Claude stream-json encode/parse | 2 |
| `bunny/Core/Agents/CodexWire.swift` | Codex JSON-RPC encode/parse | 2 |
| `bunny/Core/Agents/SessionLaunchPlanner.swift` | pure open-in-app plans + shell quoting | 3 |
| `bunny/Core/Agents/ShellEnvironment.swift` | login-shell PATH, `command -v` | 4 |
| `bunny/Core/Agents/AgentProcess.swift` | Process wrapper | 4 |
| `bunny/Core/Agents/AgentRunner.swift`, `ClaudeCodeRunner.swift`, `CodexRunner.swift` | runners | 4 |
| `Tests/BunnyCoreTests/Agents/*` + `Tests/BunnyCoreTests/FakeCLIs/*.py` | tests | 1–4 |
| `bunny/Models/BunnyTask.swift` | agent fields | 5 |
| `bunny/Controllers/AgentSettings.swift` | UserDefaults-backed settings | 5 |
| `bunny/Controllers/AgentSupervisor.swift` | runners ↔ task state, notifications, timer | 5 |
| `bunny/Controllers/SessionLauncher.swift` | executes launch plans | 5 |
| `bunny/AppDelegate.swift`, `StatusBarController.swift` | supervisor boot, attention dot | 5 |
| `bunny/Views/ShimmerText.swift`, `bunny/Views/AgentButton.swift`, `TaskRowView.swift` | row UI | 6 |
| `bunny/Views/Panel/AgentPanelSection.swift`, `TaskPanelView.swift`, `bunny/Views/Settings/AgentSettingsSection.swift` (replace plan C placeholder body) | panel + settings UI | 7 |

---

### Task 1: Core agent types, prompt builder, cwd resolver, markers

**Files:** Create `bunny/Core/Agents/AgentTypes.swift`, `AgentPromptBuilder.swift`, `WorkingDirectoryResolver.swift`, `AgentMarkers.swift`. Tests are in `Tests/BunnyCoreTests/Agents/AgentPromptBuilderTests.swift`, `WorkingDirectoryResolverTests.swift`, `AgentMarkersTests.swift` and `AgentTypesTests.swift`.

**Interfaces (Produces) — exact:**
```swift
enum AgentHarness: String, Codable, CaseIterable, Sendable {
    case claudeCode, codex
    var displayName: String      // "Claude Code" / "Codex"
    var symbolName: String       // "sparkle" / "chevron.left.forwardslash.chevron.right"
}
enum AgentRunState: String, Codable, Sendable {
    case idle, running, needsInput, finished, failed, stopped, handedOff
    var isActive: Bool           // running || needsInput
    var label: String            // "Idle","Working…","Needs your input","Done","Failed","Stopped","Opened in app"
}
enum AgentAutonomy: String, Codable, CaseIterable, Sendable { case autonomous, askFirst }
enum OpenInApp: String, Codable, CaseIterable, Sendable {
    case terminal, ghostty, vscode, cursor
    var displayName: String      // "Terminal","Ghostty","VS Code","Cursor"
}
struct AgentQuestionOption: Codable, Equatable, Sendable { var label: String; var detail: String? }
struct AgentQuestionItem: Codable, Equatable, Sendable {
    var key: String              // Claude: exact question text; Codex marker: "answer"
    var header: String?
    var question: String
    var options: [AgentQuestionOption]
    var multiSelect: Bool
    var allowsOther: Bool        // true for Claude AskUserQuestion and for marker questions with options
}
struct AgentQuestion: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case choices, freeform, approval }
    var kind: Kind
    var items: [AgentQuestionItem]   // choices: 1+; freeform: exactly 1 with no options; approval: empty
    var approvalTitle: String?       // e.g. "Run command", "Edit files", "Use Bash"
    var approvalDetail: String?      // command text / path / tool input summary
    var requestID: String?           // Claude control request_id, or Codex JSON-RPC id rendered as string
    var method: String?              // Codex server-request method (approvals)
    var rawInput: Data?              // Claude original tool input JSON (needed for updatedInput)
}
struct AgentAnswer: Codable, Equatable, Sendable {
    var selections: [String: [String]]   // item.key → chosen labels and/or typed text
    var approved: Bool?                  // approvals only
    /// Human-readable answer used for Codex follow-up turns and resumed sessions.
    func summary(for question: AgentQuestion) -> String
}
struct AgentBrief: Equatable, Sendable {
    struct Subtask: Equatable, Sendable { var title: String; var done: Bool }
    struct ShelfEntry: Equatable, Sendable { var path: String; var isDirectory: Bool }
    var title: String
    var description: String
    var subtasks: [Subtask]
    var shelf: [ShelfEntry]
    var deadline: Date?               // nil = no timer
    var workingDirectory: String
    var extraDirectories: [String]
}
enum AgentEvent: Equatable, Sendable {
    case sessionStarted(String)
    case activity(String)
    case question(AgentQuestion)
    case turnFinished(text: String, success: Bool)
    case failed(String)
    case exited(Int32)
}
enum AgentPromptBuilder {
    static func prompt(for brief: AgentBrief, now: Date, timeZone: TimeZone = .current) -> String
    static func systemAppendix(for harness: AgentHarness) -> String
}
enum WorkingDirectoryResolver {
    static func resolve(shelf: [AgentBrief.ShelfEntry], defaultWorkspace: String) -> (cwd: String, extra: [String])
}
enum AgentMarkers {
    static func extractQuestion(from text: String) -> (text: String, question: AgentQuestion?)
    static func extractCompletedSubtasks(from text: String) -> (text: String, numbers: [Int])
}
```

**Behavior details:**
- `AgentAnswer.summary`:
  - Approval: `"Allowed"` / `"Denied"`.
  - One item: its selections joined with `", "`.
  - Several items: `"<question>: <joined>"` per line.
- `prompt(for:now:)` follows spec §5 exactly. The sections are `# Task: <title>`, then the description (or `(no description)`), then the optional ones: `## Subtasks` (`- [ ] 1. t` / `- [x] 2. t`), `## Files and folders` (`- <path> (folder)` or `- <path>`) and `## Time budget`. They are separated by one blank line. The time budget reads `You have <N> minutes (until <HH:mm>). Prioritize finishing within it.`, where N = `max(1, Int(ceil(deadline - now) / 60))`, rounded up, and HH:mm is formatted in `timeZone` with `en_US_POSIX`.
- `systemAppendix(for:)` has the three bullets from spec §5. For `.claudeCode` the ask sentence names the AskUserQuestion tool. For `.codex` it gives the exact `<bunny-question>` format and "nothing after it". Both include the `<bunny-subtasks-done>` instruction.
- `resolve`:
  - cwd = first directory entry's path. Otherwise the parent of the first file entry. Otherwise `defaultWorkspace`.
  - extra = other directory paths plus the distinct parent dirs of the other files, in shelf order, deduped and excluding cwd.
  - Paths are compared after trimming a trailing `/`.
- `extractQuestion`:
  - Finds the LAST `<bunny-question>…</bunny-question>` block, removes it and trims the remaining text.
  - Parses the JSON `{"question": String, "options": [String]?}`. Options present and non-empty → `.choices`, one item `key "answer"`, `allowsOther true`, `multiSelect false`. Otherwise `.freeform`, one item `key "answer"`, no options.
  - Invalid JSON → question `nil`, block still stripped.
  - Text without a block is returned trimmed.
- `extractCompletedSubtasks`: finds `<bunny-subtasks-done>…</bunny-subtasks-done>`, parses comma-separated ints (ignores junk) and strips the block.

- [ ] **Step 1: Write failing tests** covering at least:
  - `promptIncludesAllSections`: brief with a description, 2 subtasks (one done), 1 folder and 1 file, and a deadline 25 min after `now` in UTC. Expect the exact full string:
```
# Task: Fix login

Users get logged out.

## Subtasks
- [ ] 1. Repro
- [x] 2. Patch

## Files and folders
- /Users/n/code/app (folder)
- /Users/n/notes.md

## Time budget
You have 25 minutes (until 10:25). Prioritize finishing within it.
```
    (with `now = 2026-09-24T10:00:00Z`, `timeZone = UTC`).
  - `promptMinimal`: no description, subtasks, shelf or deadline → `"# Task: X\n\n(no description)"`.
  - `appendixMentionsHarnessMechanism`: Claude contains `AskUserQuestion`; Codex contains `<bunny-question>`; both contain `<bunny-subtasks-done>`.
  - `resolverPrefersFolder`, `resolverFallsBackToFileParent`, `resolverFallsBackToDefault`, `resolverExtraDirsDedupedAndExcludeCwd` (two files in the same folder plus a second folder).
  - `markerChoices`, `markerFreeform`, `markerInvalidJSONStripped`, `markerAbsent`, `subtasksDone` (`"Did it.\n<bunny-subtasks-done>1, 3,x</bunny-subtasks-done>"` → text `"Did it."`, numbers `[1,3]`).
  - `answerSummary`: one-item multi selection → `"A, B"`; approval → `"Allowed"`.
  - `questionRoundTripsThroughJSON`: encode then decode an `AgentQuestion` with `rawInput` → equal.
- [ ] **Step 2:** Run `swift test --filter Agent` → FAIL.
- [ ] **Step 3:** Implement the four files.
- [ ] **Step 4:** Run `swift test` → all pass, with no warnings from your files.
- [ ] **Step 5:** Commit `feat(core): agent types, prompt builder, cwd resolver, markers`.

---

### Task 2: Wire codecs — JSONLineBuffer, ClaudeWire, CodexWire

**Files:** Create `bunny/Core/Agents/JSONLineBuffer.swift`, `ClaudeWire.swift` and `CodexWire.swift`. Tests are in `Tests/BunnyCoreTests/Agents/JSONLineBufferTests.swift`, `ClaudeWireTests.swift` and `CodexWireTests.swift`.

**Interfaces:**
- Consumes (Task 1): `AgentQuestion`, `AgentQuestionItem`, `AgentQuestionOption`, `AgentAnswer`.
- Produces — exact:
```swift
struct JSONLineBuffer {
    /// Appends bytes; returns complete non-empty lines (without "\n" / "\r\n"). Keeps a partial trailing line.
    mutating func append(_ data: Data) -> [Data]
}
enum ClaudeWire {
    enum Incoming: Equatable {
        case initialized(sessionID: String)
        case assistantText(String)                       // concatenated text blocks of one assistant message
        case toolUse(name: String, summary: String)      // summary: Bash→command, Edit/Write/Read→file_path, else ""
        case permissionRequest(requestID: String, toolName: String, input: Data)  // input = raw JSON object bytes
        case result(success: Bool, text: String, sessionID: String?)  // error: text = joined `errors` or terminal_reason
        case ignored
    }
    static func parse(_ line: Data) -> Incoming               // malformed → .ignored
    static func userMessage(_ text: String) -> Data            // one line, no trailing newline
    static func interrupt(requestID: String) -> Data
    static func allow(requestID: String, updatedInput: Data) -> Data
    static func deny(requestID: String, message: String) -> Data
    /// AskUserQuestion → .choices question (items keyed by exact question text, allowsOther true); other tools → .approval.
    static func question(requestID: String, toolName: String, input: Data) -> AgentQuestion
    /// Original AskUserQuestion input + "answers": {questionText: joined selections}.
    static func answeredInput(for question: AgentQuestion, answer: AgentAnswer) -> Data
}
enum CodexWire {
    enum Incoming: Equatable {
        case response(id: Int, threadID: String?, turnID: String?, error: String?)
        case turnStarted(turnID: String)
        case agentMessageDelta(String)
        case agentMessage(String)                  // item/completed with item.type == "agentMessage"
        case commandStarted(String)                // item/started with item.type == "commandExecution" → command
        case turnCompleted(status: String, error: String?)
        case approvalRequest(rpcID: String, method: String, title: String, detail: String)
        case unsupportedRequest(rpcID: String)     // any other server→client request (has id + method)
        case ignored
    }
    static func parse(_ line: Data) -> Incoming
    static func initialize(id: Int) -> Data
    static func initialized() -> Data
    static func threadStart(id: Int, cwd: String, approvalPolicy: String, sandbox: String,
                            developerInstructions: String, writableRoots: [String]) -> Data
    static func threadResume(id: Int, threadID: String) -> Data
    static func turnStart(id: Int, threadID: String, text: String) -> Data
    static func turnInterrupt(id: Int, threadID: String, turnID: String) -> Data
    static func approvalReply(rpcID: String, approved: Bool) -> Data   // {"id":<rpcID>,"result":{"decision":"accept"|"decline"}}
    static func methodNotFound(rpcID: String) -> Data                   // {"id":..,"error":{"code":-32601,"message":"unsupported"}}
}
```
**Wire details:**
- Use `JSONSerialization` with `[String: Any]`. Encode output with `.sortedKeys` for deterministic tests, and include `"jsonrpc":"2.0"` on Codex messages.
- `rpcID` round-trips its JSON type. A numeric id is rendered as `"7"` and re-encoded as the number `7`; a string id is re-encoded as a string. Keep a helper `rpcIDValue(_ s: String) -> Any` that returns `Int` when `Int(s)` succeeds.
- `thread/start` params:
  - `cwd`, `approvalPolicy`, `sandbox`, `developerInstructions`
  - `config: {"sandbox_workspace_write": {"writable_roots": [...]}}`, only when roots are non-empty
- Codex `response` threadID comes from `result.thread.id`, turnID from `result.turn.id`, and error from `error.message`.
- Approval request methods:
  - `item/commandExecution/requestApproval`: title "Run command", detail = `params.command` or `""`.
  - `item/fileChange/requestApproval`: title "Edit files", detail = `params.reason` or `params.grantRoot` or `""`.
  - Any other request (`id` + `method` present) → `unsupportedRequest`.
- Claude `result` success = `subtype == "success" && is_error == false`.

- [ ] **Step 1: Write failing tests:**
  - `JSONLineBuffer`: split across chunks, `\r\n`, multiple lines in one chunk, empty lines skipped.
  - `ClaudeWire` parse, using the literal lines from `docs/superpowers/research/claude-stream-json.md`: `system/init` → `initialized("abc")`; assistant with 2 text blocks → text joined with `"\n"`; assistant `tool_use` Bash → `toolUse("Bash","ls -la")`; `can_use_tool` AskUserQuestion → `permissionRequest`; result success; result error with no `result` field → `success false`; garbage → `.ignored`.
  - `ClaudeWire` encode: `userMessage("hi")` decodes to `type == "user"` with text `"hi"`. For `answeredInput`, AskUserQuestion input with 2 questions (one multiSelect) plus selections gives `answers["Q1"] == "Blue"` and `answers["Q2"] == "A, B"`, and the original `questions` are preserved.
  - `question(...)` for Bash → `.approval`, title `"Use Bash"`, detail = command.
  - `CodexWire` over the fixture `docs/superpowers/research/fixtures/codex-basic.jsonl`: parse every line, then expect `response(id:2, threadID: non-nil…)`, at least one `agentMessageDelta`, `agentMessage("OK")` and a final `turnCompleted(status: "completed", error: nil)`.
  - `codex-run3.jsonl` contains an `item/tool/requestUserInput` request → `unsupportedRequest`.
  - Encoders: `approvalReply(rpcID:"7", approved:true)` → JSON has numeric id 7 and `decision == "accept"`; `threadStart` without roots omits `config`.
- [ ] **Step 2:** `swift test --filter Wire` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test` → all pass.
- [ ] **Step 5:** Commit `feat(core): claude and codex wire codecs`.

---

### Task 3: SessionLaunchPlanner (pure)

**Files:** Create `bunny/Core/Agents/SessionLaunchPlanner.swift`. Test: `Tests/BunnyCoreTests/Agents/SessionLaunchPlannerTests.swift`.

**Interfaces (Produces):**
```swift
enum LaunchStep: Equatable {
    case runCommandFile(script: String)                     // write .command file with this content, `open -a Terminal`
    case exec(executable: String, arguments: [String])      // Process.run
    case openURL(String, delay: TimeInterval)
}
enum SessionLaunchPlanner {
    static func shellQuote(_ s: String) -> String           // POSIX single-quote: abc → 'abc', it's → 'it'\''s'
    static func resumeCommand(harness: AgentHarness, cliPath: String, sessionID: String, cwd: String) -> String
        // "cd '<cwd>' && exec '<cli>' --resume '<id>'"   /   "cd '<cwd>' && exec '<cli>' resume '<id>'"
    static func plan(app: OpenInApp, harness: AgentHarness, cliPath: String, sessionID: String, cwd: String) -> [LaunchStep]
}
```
**Rules** (from `open-session-in-app.md`):
- terminal → `[.runCommandFile(script: "#!/bin/zsh -l\n" + resumeCommand + "\n")]`
- ghostty → `[.exec("/usr/bin/open", ["-na", "/Applications/Ghostty.app", "--args", "--working-directory=\(cwd)", "-e", "/bin/zsh", "-lc", resumeCommand])]`
- vscode/cursor + claudeCode:
  - `[.exec(editorCLI, [cwd]), .openURL("<scheme>://anthropic.claude-code/open?session=<percent-encoded id>", delay: 1.0)]`
  - editorCLI = `/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code` or `/Applications/Cursor.app/Contents/Resources/app/bin/cursor`
  - scheme `vscode` / `cursor`
- vscode/cursor + codex → `[.exec(editorCLI, [cwd]), .runCommandFile(script: …same as terminal…)]`

- [ ] **Step 1:** Write failing tests:
  - `shellQuote` with a plain string, one with `'` and one with spaces.
  - `resumeCommand` for both harnesses with a cwd containing a space and `'`.
  - Each of the 8 app × harness plans, with exact expected arrays.
- [ ] **Step 2:** Run the tests and watch them FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the tests; they should PASS.
- [ ] **Step 5:** Commit `feat(core): session launch planner`.

---

### Task 4: Process layer & runners (with fake CLIs)

**Files:** Create `bunny/Core/Agents/ShellEnvironment.swift`, `AgentProcess.swift`, `AgentRunner.swift`, `ClaudeCodeRunner.swift` and `CodexRunner.swift`, plus the fake CLIs `Tests/BunnyCoreTests/FakeCLIs/fake_claude.py` and `fake_codex.py`. Tests: `Tests/BunnyCoreTests/Agents/ClaudeCodeRunnerTests.swift`, `CodexRunnerTests.swift`, `AgentProcessTests.swift`.

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces — exact:
```swift
enum ShellEnvironment {
    /// PATH from the user's login shell (`/bin/zsh -lic 'print -r -- $PATH'`), cached; falls back to ProcessInfo PATH + /opt/homebrew/bin:/usr/local/bin:~/.local/bin. 3 s timeout.
    static func loginPATH() -> String
    /// Absolute path of `name` via login shell `command -v`, or nil.
    static func locate(_ name: String) -> String?
    static func environment() -> [String: String]   // ProcessInfo env with PATH = loginPATH(), TERM=dumb, NO_COLOR=1
}
final class AgentProcess {
    var onLine: ((Data) -> Void)?          // stdout JSON lines, on an internal serial queue
    var onExit: ((Int32, String) -> Void)? // exit code + stderr tail (last 4 KB, UTF-8 lossy)
    init(executable: String, arguments: [String], cwd: String, environment: [String: String])
    func start() throws                    // throws if executable missing/not executable (FileManager check) or run() fails
    func write(_ line: Data)               // appends "\n"; no-op after exit
    func terminate()                       // SIGTERM, SIGKILL after 3 s if still running
    var isRunning: Bool { get }
}
struct AgentRunOptions: Equatable, Sendable {
    var cliPath: String
    var autonomy: AgentAutonomy
    var environment: [String: String]
}
protocol AgentRunner: AnyObject {
    var onEvent: ((AgentEvent) -> Void)? { get set }   // ALWAYS delivered on DispatchQueue.main
    var sessionID: String? { get }
    /// Starts a new session (resumeSessionID nil) or resumes one. `initialMessage` overrides the brief prompt as first user turn (used for resume-with-answer).
    func start(brief: AgentBrief, harness: AgentHarness, resumeSessionID: String?, initialMessage: String?)
    func answer(_ question: AgentQuestion, with answer: AgentAnswer)
    func send(_ text: String)
    func interrupt()
    func terminate()
}
final class ClaudeCodeRunner: AgentRunner { init(options: AgentRunOptions) }
final class CodexRunner: AgentRunner { init(options: AgentRunOptions) }
```

**Claude runner:**
- argv:
  - `-p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio --permission-mode <bypassPermissions|acceptEdits> --append-system-prompt <appendix>`
  - then `--add-dir <d>` for each extra dir
  - plus `--resume <id>` when resuming
- cwd = `brief.workingDirectory`. After start it writes `userMessage(initialMessage ?? prompt)`.
- Event mapping:
  - `initialized` → `sessionStarted` (once per new id)
  - `assistantText` → `activity(first non-empty line, ≤120 chars)`
  - `toolUse` → `activity("Running <name>…")`, or `"Running <name>: <summary>"` truncated to 120
  - `permissionRequest` → `question(ClaudeWire.question(...))`
  - `result` → `turnFinished(text:, success:)`
  - process exit before any `result` → `failed(stderrTail or "exited with code N")`; always followed by `exited(code)`
- `answer`:
  - `.approval` → `allow(requestID, updatedInput: rawInput ?? {})` or `deny(requestID, "The user declined.")`
  - `.choices` → `allow(requestID, updatedInput: ClaudeWire.answeredInput(...))`
- `send` → `userMessage`. `interrupt` → `interrupt(requestID: random 13 chars)`.

**Codex runner:**
- Launches `codex app-server --stdio` and sends `initialize(id:1)`.
- On the id 1 response it sends `initialized()`, then `threadStart(id:2, …)` (or `threadResume(id:2, threadID:)`).
  - approvalPolicy: `never` for autonomous, `on-request` for askFirst
  - sandbox `workspace-write`
  - developerInstructions = appendix
- On the id 2 response it emits `sessionStarted(threadID)`, then `turnStart(id:3, text: initialMessage ?? prompt)`. Later ids increment.
- Deltas accumulate into the current message. `agentMessage` → store `lastMessage` and emit `activity(first line)`. `commandStarted` → `activity("Running <cmd>")`.
- `turnCompleted`:
  - `completed`: run `AgentMarkers.extractQuestion(lastMessage)`. A question → `question(q)` with `requestID nil`. Otherwise `turnFinished(lastMessage, true)`.
  - `failed` → `turnFinished(error ?? "Codex turn failed", false)`.
  - `interrupted` → `turnFinished("Interrupted", false)`.
- `approvalRequest` → `question(.approval, requestID: rpcID, method:)`. `unsupportedRequest` → reply `methodNotFound`.
- `answer`:
  - approvals → `approvalReply`
  - marker questions → `send(answer.summary(for:))`, which becomes a new `turn/start`
- A response with an error before thread start → `failed(error)`.
- `interrupt` → `turnInterrupt` with the current turn id (captured from `turnStarted` or the turn/start response).

**Fake CLIs** (python3, read stdin line by line, write JSON lines with flush):
- `fake_claude.py`: prints `system/init` (`session_id "sess-1"`) on the first user message.
  - Message text containing `ASK` → a `can_use_tool` AskUserQuestion request (`request_id "r1"`, a question "Pick one?" with options A/B). It waits for the `control_response`, then prints a `result` whose text is `"answered: <answers json>"`.
  - Message containing `FAIL` → exits with code 3 after writing `boom` to stderr.
  - Otherwise → an assistant text `"working"`, then result success `"done: <text>"`.
  - Every `result` text ends with `" | argv=" + json.dumps(sys.argv[1:])` so tests can assert the flags.
- `fake_codex.py`: minimal JSON-RPC server for `initialize`, `thread/start` (`thread.id "th-1"`) and `turn/start`.
  - Text containing `QUESTION` → agentMessage `"Need info\n<bunny-question>{\"question\":\"Which DB?\",\"options\":[\"pg\",\"sqlite\"]}</bunny-question>"`, then `turn/completed completed`.
  - Otherwise → agentMessage `"done: <text>"`, then completed.
- Make the fake scripts executable with `#!/usr/bin/env python3`, chmod 755 in the test setup, and pass their path as `cliPath`. `CodexRunner` passes `["app-server","--stdio"]`, which the fake ignores.

- [ ] **Step 1: Write the fake CLIs and failing tests.** Use an `AsyncStream`/expectation helper that collects events until a predicate or a 10 s timeout. Tests:
  - `claudeHappyPath`: events contain `sessionStarted("sess-1")`, `activity("working")` and `turnFinished("done: …", true)`.
  - `claudeAskAndAnswer`: a question with `kind .choices` and key `"Pick one?"`. Answer `["Pick one?": ["B"]]` → `turnFinished` text contains `"Pick one?"` and `"B"`.
  - `claudeProcessFailure`: `FAIL` → `failed` containing `"boom"`, then `exited(3)`.
  - `claudeMissingCLI`: cliPath `/nonexistent` → `failed` event, no crash.
  - `claudeArgvIncludesAddDirAndMode`: a brief with extraDirectories and autonomy `.askFirst` → the result text's `argv=` part contains `--add-dir`, that directory, and `acceptEdits`.
  - `codexHappyPath`: `sessionStarted("th-1")`, `turnFinished("done: …", true)`.
  - `codexMarkerQuestionThenAnswer`: question `.choices` with options pg/sqlite. `answer(["answer": ["sqlite"]])` → the next `turnFinished` text contains `"sqlite"`.
- [ ] **Step 2:** `swift test --filter Runner` → FAIL.
- [ ] **Step 3: Implement.**
  - `AgentProcess` uses `Process`, `Pipe`s, `readabilityHandler` feeding a `JSONLineBuffer` on a private serial queue, and `terminationHandler`.
  - Guard double-exit.
  - Runners hop to `DispatchQueue.main` for every `onEvent`.
- [ ] **Step 4:** `swift test` → all pass. Also run it 3× (`for i in 1 2 3; do swift test --filter Runner || break; done`) to catch flakiness.
- [ ] **Step 5:** Optional live check, gated: `BUNNY_LIVE_AGENT_TESTS=1 swift test --filter Live`. This is one test per harness with the real CLI at `ShellEnvironment.locate(...)`, the prompt "Reply with the word OK and nothing else." and a 120 s timeout, expecting `turnFinished` with success. Skip unless the env var is set.
- [ ] **Step 6:** Commit `feat(core): agent process and claude/codex runners`.

---

### Task 5: App integration — model fields, settings, supervisor, launcher, menu-bar dot

**Files:** Modify `bunny/Models/BunnyTask.swift`, `bunny/AppDelegate.swift` and `bunny/Controllers/StatusBarController.swift`. Create `bunny/Controllers/AgentSettings.swift`, `bunny/Controllers/AgentSupervisor.swift` and `bunny/Controllers/SessionLauncher.swift`.

**Interfaces:**
- Consumes: all Core agent APIs, `ShelfService.items/resolve`, `PanelCoordinator.shared.open(_:)`.
- Produces — exact:
```swift
// BunnyTask additions (defaults per spec §4):
var agentHarness: String? = nil
var agentState: String = "idle"
var agentSessionID: String? = nil
var agentWorkingDirectory: String? = nil
var agentActivity: String = ""
var agentSummary: String = ""
var agentQuestionData: Data? = nil
var agentStartedAt: Date? = nil
var agentFinishedAt: Date? = nil
var completedByAgent: Bool = false
// computed:
var runState: AgentRunState { get set }        // wraps agentState
var harness: AgentHarness? { get }
var pendingQuestion: AgentQuestion? { get }   // decodes agentQuestionData

@MainActor enum AgentSettings {
    static var defaultHarness: AgentHarness { get set }   // UserDefaults "agent.defaultHarness", default .claudeCode
    static var claudePath: String { get set }             // default ShellEnvironment.locate("claude") ?? ""
    static var codexPath: String { get set }
    static var autonomy: AgentAutonomy { get set }        // default .autonomous
    static var openIn: OpenInApp { get set }              // default .terminal
    static var defaultWorkspace: String { get set }       // default NSHomeDirectory()
    static func cliPath(for harness: AgentHarness) -> String
    static func isInstalled(_ app: OpenInApp) -> Bool     // terminal always true; others check /Applications/<App>.app
}

@MainActor @Observable final class AgentSupervisor {
    static let shared: AgentSupervisor
    func configure(modelContainer: ModelContainer)        // called from AppDelegate; runs launch recovery (spec §7)
    private(set) var attentionCount: Int                  // tasks in needsInput (drives menu-bar dot)
    func primaryAction(for task: BunnyTask)               // no session → start(default harness); else openSession
    func start(_ task: BunnyTask, harness: AgentHarness?)
    func answer(_ task: BunnyTask, with answer: AgentAnswer)
    func stop(_ task: BunnyTask)
    func openSession(_ task: BunnyTask)
    func clear(_ task: BunnyTask)                         // reset agent fields when not active
    func taskWillArchiveOrDelete(_ taskID: UUID)          // stops a live runner
    func isLive(_ taskID: UUID) -> Bool
}

@MainActor enum SessionLauncher {
    /// Executes SessionLaunchPlanner steps; on failure falls back to the Terminal plan; last resort copies the resume command to the pasteboard and returns it.
    @discardableResult
    static func open(harness: AgentHarness, sessionID: String, cwd: String) -> String?   // non-nil = fallback text shown in panel
}
```
**Supervisor rules** (spec §7 — implement all):
- `start`:
  - Refuse if `runState.isActive`.
  - If the CLI path is empty or not executable, set `failed` with summary `"<Harness> not found — set its path in Settings → Agents."`.
  - Build `AgentBrief`:
    - subtasks = children sorted by `sortOrder`/`createdAt`
    - shelf = resolved `ShelfService` URLs, skipping missing ones
    - the deadline starts the timer first if `timerDuration != nil && timerStartedAt == nil`; deadline = `timerStartedAt + timerDuration`, only if not expired
    - cwd/extra come from `WorkingDirectoryResolver`
  - Set fields `agentHarness`, `agentWorkingDirectory`, `runState = .running`, `agentStartedAt`, `agentFinishedAt = nil`, `agentSummary = ""` and `agentActivity = "Starting…"`.
  - Create the runner, keep it in `[UUID: AgentRunner]`, subscribe with the task id captured, then start.
- Event handling (look up the task by id in `modelContainer.mainContext`, ignore if gone):
  - `sessionStarted` → `agentSessionID`.
  - `activity` → `agentActivity`.
  - `question` → `runState = .needsInput`, store the JSON and notify `"<title> needs your input"`.
  - `turnFinished(success)`:
    - If a timeout wrap-up is pending: `stopped` with the summary.
    - Else if success: `finished`, then `isCompleted = true`, `completedAt`, `completedByAgent = true`. Apply `extractCompletedSubtasks` to subtasks (1-based in brief order). Summary = cleaned text. Notify `"<title> is done"`.
    - Else: `failed`.
    - In every case: `agentFinishedAt = now`, clear the question, and terminate + remove the runner (Claude/Codex processes are one-turn-per-handoff; follow-ups resume).
  - `failed` → `failed`, summary = message, remove the runner.
  - `exited` while still `running` with no finish → `failed "Agent exited unexpectedly"`.
- `answer`:
  - Live runner → `runner.answer(question, with:)`, state `running`, clear the question.
  - Otherwise → `resume`: a new runner with `start(brief, harness, resumeSessionID: agentSessionID, initialMessage: "Answer to your earlier question \"<q>\": <summary>")`.
- `stop` → `interrupt`, and `terminate` after 3 s. State `stopped`, activity `"Stopped"`.
- `openSession`:
  - No session id → `start` instead.
  - Active → terminate the runner, state `handedOff`.
  - Then `SessionLauncher.open(harness:sessionID:cwd:)`; a fallback text is stored into `agentActivity`.
- Timer: a 1 s check piggybacks on `TimerManager.shared.tick` via a `Timer`. For each live task whose `isTimerExpired` flips true:
  - `running` → mark a wrap-up pending, `interrupt()`, then `send("Time's up — stop here and reply with a summary of what's done and what's left.")` after 1 s. The runner must not be removed on the interrupted turnFinished while a wrap-up is pending.
  - `needsInput` → append `" · Time ran out"` to activity once.
- `configure` launch recovery: `running` → `stopped`, activity `"Interrupted — Bunny quit"`. `attentionCount` is recomputed after every state change.
- Notifications: `UNUserNotificationCenter` with `userInfo["taskID"]`. `AppDelegate` becomes the `UNUserNotificationCenterDelegate`; tapping a notification opens the popover (`statusBarController.openPopover()`) and calls `PanelCoordinator.shared.open(taskID)`.
- `TaskRowView.archiveTask` and `ArchiveView` don't exist in this task's files — the call to `taskWillArchiveOrDelete` is added in Task 6.

**Menu-bar dot:** In `StatusBarController.updateMenuBarItem`, when `AgentSupervisor.shared.attentionCount > 0`, use a non-template image: the hare symbol drawn in `labelColor` plus a 6 pt `systemYellow` circle at the top-right, built once with `NSImage(size:flipped:drawingHandler:)`. Otherwise use the template icon.

- [ ] **Step 1:** Add the fields and computed accessors to `BunnyTask`.
- [ ] **Step 2:** Write `AgentSettings` and `SessionLauncher`. The `.runCommandFile` step writes to `~/Library/Application Support/Bunny/launch/<uuid>.command`, sets permissions `0o755`, runs `/usr/bin/open -a Terminal <file>` and deletes the file after 60 s. `.exec` uses `Process`. `.openURL` uses `NSWorkspace.shared.open` after the delay.
- [ ] **Step 3:** Write `AgentSupervisor`.
- [ ] **Step 4:** In `AppDelegate`, call `AgentSupervisor.shared.configure(modelContainer:)` after the container is created, and set the notification delegate. In `StatusBarController`, add the dot.
- [ ] **Step 5:** Run `swift test` (still green). Self-review every rule above against the code, using a checklist in the report.
- [ ] **Step 6:** Commit `feat: agent supervisor, settings, session launcher`.

---

### Task 6: Row UI — agent button, shimmer title, state colors

**Files:** Create `bunny/Views/ShimmerText.swift` and `bunny/Views/AgentButton.swift`. Modify `bunny/Views/TaskRowView.swift` and `bunny/Views/ArchiveView.swift` (restore clears `completedByAgent`).

**Interfaces:**
- Consumes: `AgentSupervisor` API, `BunnyTask.runState/harness/completedByAgent`, `AgentSettings.defaultHarness/openIn`.
- Produces: `ShimmerText(text: String, font: Font)` and `AgentButton(task: BunnyTask)`.

- [ ] **Step 1: `ShimmerText`:**
```swift
import SwiftUI

/// Title that "flows" left→right: a soft bright band sweeps across text drawn at 30 % opacity.
struct ShimmerText: View {
    let text: String
    var font: Font = .system(size: 14)
    var period: Double = 1.8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let label = Text(text).font(font).lineLimit(1)
        if reduceMotion {
            label.opacity(0.6)
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = CGFloat((t.truncatingRemainder(dividingBy: period)) / period) // 0…1
                label
                    .foregroundStyle(.primary.opacity(0.3))
                    .overlay {
                        label
                            .foregroundStyle(.primary)
                            .mask {
                                GeometryReader { geo in
                                    let w = geo.size.width
                                    LinearGradient(stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .black, location: 0.5),
                                        .init(color: .clear, location: 1),
                                    ], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: w * 0.6)
                                    .offset(x: -w * 0.6 + phase * (w * 1.6))
                                }
                            }
                    }
            }
        }
    }
}
```
- [ ] **Step 2: `AgentButton`:**
  - Symbol = `(task.harness ?? AgentSettings.defaultHarness).symbolName`, 11 pt, `.buttonStyle(.plain)`.
  - Tint by `runState`:
    - running: `Color.accentColor` + `.symbolEffect(.pulse, isActive: true)`
    - needsInput: yellow
    - finished: green
    - failed: red
    - otherwise: `.secondary`
  - Action: `AgentSupervisor.shared.primaryAction(for: task)`.
  - `.help`: no session → `"Hand off to <Harness>"`; else `"Open session in <App>"`.
  - `.contextMenu` without icons (macOS 27 style): `Start with Claude Code`, `Start with Codex` (disabled while active), `Open Session in <App>` (only when `agentSessionID != nil`), `Stop Agent` (only when active), `Clear Agent` (only when not active and state != idle).
- [ ] **Step 3: `TaskRowView`:**
  - Insert `AgentButton(task: task)` between the pin button and the archive button, for `!task.isSubtask` only.
  - Title (non-editing branch):
    - `runState == .running` → `ShimmerText(text: task.title)`.
    - `.needsInput` → `Text` with `.foregroundStyle(Color.yellow.mix(with: .orange, by: 0.35))`.
    - Otherwise keep the existing text.
  - Checkbox symbol and color:
    - `needsInput` → `questionmark.circle.fill`, same yellow.
    - `failed` → `exclamationmark.circle`, red.
    - `isCompleted && completedByAgent` → `checkmark.circle.fill`, green.
    - Otherwise existing.
  - `toggleComplete`: when unchecking, set `completedByAgent = false`.
  - `archiveTask`: call `AgentSupervisor.shared.taskWillArchiveOrDelete(task.id)` first.
  - Keep every hook from Spec A intact (hover, click-lock, drop, badges, restyle).
- [ ] **Step 4: `ArchiveView.restore`:** set `completedByAgent = false` on the restored task and its subtasks.
- [ ] **Step 5:** Self-review. `Color.mix(with:by:)` is macOS 15+; `symbolEffect(.pulse, isActive:)` exists. Commit `feat: agent button, shimmer and agent state colors on task rows`.

---

### Task 7: Panel agent section & Settings → Agents

**Files:** Create `bunny/Views/Panel/AgentPanelSection.swift`. Replace the placeholder body of `bunny/Views/Settings/AgentSettingsSection.swift` (created by plan C Task C2; it is the Agents tab of the Settings window — wrap content in `Form { … }.formStyle(.grouped)`). Modify `bunny/Views/Panel/TaskPanelView.swift` (`agentSection` → `AgentPanelSection(task: task)`). Do not touch other settings files.

**Interfaces:** Consumes `AgentSupervisor`, `AgentSettings`, `BunnyTask.pendingQuestion/runState/agentActivity/agentSummary`, `ShellEnvironment.locate`.

- [ ] **Step 1: `AgentPanelSection(task:)`** — hidden entirely when `runState == .idle && agentSessionID == nil`; in that case it shows one row with two buttons, `Start with Claude Code` / `Start with Codex` (`.buttonStyle(.glass)`, small).
  - Otherwise:
    - Header `HStack`: harness symbol, harness name (12 pt semibold), state label (11 pt, state color), `Spacer`, elapsed since `agentStartedAt` as `mm:ss` (monospaced, 11 pt, uses `TimerManager.tick`) while active.
    - Activity line: 11 pt secondary, 2 lines max.
    - `needsInput` → `QuestionForm`:
      - For each item: header (11 pt secondary), question (13 pt).
      - Options as full-width rows with a circle or checkmark-square symbol, label and detail (secondary). Tapping toggles the selection (single select replaces).
      - `allowsOther` → a `TextField("Other…")` that, when non-empty, is included as an extra selection.
      - Freeform → a `TextField(axis: .vertical)` with 3–6 lines.
      - `Send` (`.glassProminent`) is disabled until every item has at least one selection or text. On tap: `AgentSupervisor.shared.answer(task, with: AgentAnswer(selections:…, approved: nil))`.
      - Approval → the title and detail (monospaced, 11 pt, selectable, 4 lines max) and `Deny` (`.glass`) / `Allow` (`.glassProminent`).
    - `finished`/`failed`/`stopped`/`handedOff` with a non-empty summary → `ScrollView` (max height 160) with `Text(agentSummary).textSelection(.enabled)` (12 pt).
    - Actions row: `Chat about this` (`.glass`, symbol `bubble.left.and.text.bubble.right`) → `openSession`. `Stop` (`.glass`, red tint) while active.
  - The section sits in a rounded `.quaternary.opacity(0.5)` fill (no glass — the panel root is glass).
- [ ] **Step 2: `AgentSettingsSection`:**
  - `Picker("Default agent", selection:)` segmented over `AgentHarness.allCases`.
  - Two path rows (Claude Code / Codex): a `TextField` bound to the setting, a status dot (green if `FileManager.isExecutableFile`, else red) and a `Detect` button (`ShellEnvironment.locate("claude"/"codex")`, run off-main with `Task.detached`, then assign on main).
  - `Picker("Autonomy")`: Autonomous / Ask before running commands.
  - `Picker("Open sessions in")`: installed `OpenInApp` cases only.
  - Default workspace: path text plus a `Choose…` button → `NSOpenPanel` (directories only).
  - Use `@State` mirrors initialized from `AgentSettings` in `.onAppear` and written back on change.
- [ ] **Step 3:** Mount `AgentPanelSection` in `TaskPanelView.agentSection` (the Settings tab already hosts `AgentSettingsSection`).
- [ ] **Step 4:** Self-review: no `.glassEffect` inside the panel; all buttons are reachable at 300 pt width. Commit `feat: agent status, questions and settings UI`.

## Execution waves
- Wave 1 (parallel, disjoint Core files): Task 1 ∥ Task 3 (Task 3 needs only `AgentHarness`/`OpenInApp` — the Task 3 implementer defines nothing new; if Task 1 is not merged yet, wait for it).
- Then Task 2 (needs Task 1 types) — may run in parallel with Spec A UI tasks.
- Task 4 after Task 2.
- Task 5 after Task 4 and Spec A Task 4 (`PanelCoordinator`).
- Task 6 after Spec A Task 7 (both edit `TaskRowView`).
- Task 7 after Task 5 and Spec A Task 5.
