# Claude Code headless stream-json protocol (verified 2026-09-24, Claude Code 2.1.281)

Captures/driver: scratchpad/claude-proto. Cross-checked against @anthropic-ai/claude-agent-sdk 0.3.281.

argv: `claude -p --input-format stream-json --output-format stream-json --verbose
       --permission-prompt-tool stdio --permission-mode <acceptEdits|bypassPermissions>
       [--append-system-prompt <text>] [--add-dir <dir>]... [--resume <sessionId>] [--model <m>]`
- Never pass a positional prompt (and `--add-dir` is variadic — it would swallow it). All input via stdin.
- No initialize handshake needed. Inherits the user's ~/.claude settings/plugins/CLAUDE.md (intended).

stdin (one JSON per line):
- user message: `{"type":"user","message":{"role":"user","content":[{"type":"text","text":"..."}]}}`
- interrupt: `{"type":"control_request","request_id":"<random>","request":{"subtype":"interrupt"}}`
- permission answer: `{"type":"control_response","response":{"subtype":"success","request_id":"<id>","response":{"behavior":"allow","updatedInput":{...}}}}`
  deny: `..."response":{"behavior":"deny","message":"<why>"}`

stdout:
- `{"type":"system","subtype":"init","session_id":"<uuid>","cwd":...}` — re-emitted each turn.
- `{"type":"assistant","message":{"content":[{"type":"text","text":"..."},{"type":"tool_use","name":"Bash","input":{...}}]},"session_id":...}`
- `{"type":"user",...}` (tool results) — ignore.
- `{"type":"result","subtype":"success","is_error":false,"result":"<final text>","session_id":...,"total_cost_usd":0.02,"duration_ms":9143}`
  error/interrupted: `"subtype":"error_during_execution","is_error":true,"terminal_reason":"aborted_streaming"` (no `result` field).
- `{"type":"control_request","request_id":"<id>","request":{"subtype":"can_use_tool","tool_name":"<Tool>","input":{...},"tool_use_id":"..."}}`
- `{"type":"control_response",...}` replies to our interrupts — ignore.

AskUserQuestion: arrives as can_use_tool with tool_name "AskUserQuestion", input
`{"questions":[{"question","header","options":[{"label","description"}],"multiSelect"}]}`.
Answer = allow with updatedInput = original input + `"answers":{"<exact question text>":"<label>"}`
(multi-select: labels joined with ", "; "Other": the typed text). Fires even under bypassPermissions.
Under acceptEdits, other tools (e.g. Bash) may also send can_use_tool → surface as approval.

Multi-turn: send another user message after `result`. Resume: `claude --resume <id>` (run in the task's cwd).
