# Codex app-server protocol (verified 2026-09-24, codex-cli 0.155.0)

Launch: `codex app-server --stdio` — newline-delimited JSON-RPC 2.0 (no Content-Length).
Captures: scratchpad/codex-proto (run1–4.json).

1. `{"id":1,"method":"initialize","params":{"clientInfo":{"name":"bunny","version":"1.0"},"capabilities":{"experimentalApi":true}}}`
   then notification `{"method":"initialized"}`.
2. `thread/start` params: `cwd`, `approvalPolicy:"never"`, `sandbox:"workspace-write"` (or `danger-full-access`),
   optional `model`, `developerInstructions`, `config` (JSON form of config.toml, e.g.
   `{"sandbox_workspace_write":{"writable_roots":["/abs"]}}`).
   Result: `{"thread":{"id":"<uuid>","path":"<rollout.jsonl>"}}`.
3. `turn/start` `{"threadId","input":[{"type":"text","text":"..."}]}` → result `{"turn":{"id","status":"inProgress"}}`.
   Notifications: `turn/started`, `item/started`, `item/agentMessage/delta` `{itemId,delta}`,
   `item/completed` (`item.type` = userMessage/reasoning/agentMessage(`text`)/commandExecution/fileChange…),
   `turn/completed` `{"turn":{"id","status":"completed"|"interrupted"|"failed", "error"?}}`.
4. Interrupt: `turn/interrupt {"threadId","turnId"}` → `turn/completed` status `interrupted`.
5. Server→client requests (have `id`) — approvals won't occur with approvalPolicy never; if any unknown request
   arrives, reply `{"id":<same>,"error":{"code":-32601,"message":"unsupported"}}` (or approve for approval methods).
6. Structured questions (`item/tool/requestUserInput`) exist but ONLY in Plan collaboration mode (read-only) with
   `config.tools.experimental_request_user_input.enabled=true`. Bunny does NOT use it; instead the agent ends
   its turn with a `<bunny-question>` block (see Spec B) and Bunny sends the answer as the next `turn/start`.
7. Resume: interactive `codex resume <threadId>` works (restores cwd itself). Rollouts in ~/.codex/sessions.
8. The process loads the user's ~/.codex config, AGENTS.md and MCP servers (fine; noisy stderr is ignored).
