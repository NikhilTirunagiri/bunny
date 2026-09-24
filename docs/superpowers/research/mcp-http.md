# Local MCP over Streamable HTTP for Bunny (verified 2026-09-24)

Empirical research only — nothing in `/Users/nt/bunny` was modified. Test harness and
minimal server: `/private/tmp/claude-501/-Users-nt-bunny/339a7c84-a22d-4368-a011-7253e1dd8293/scratchpad/mcp-http/`
(`server.py`, `drive_appserver.py`). CLIs used: `claude` 2.1.281 (`--model haiku`),
`codex` 0.155.0 (cheapest model `gpt-5.6-luna` for CLI tests; app-server test used the
account default model).

## 1. Minimal server — VERIFIED

Plain `http.server`/`ThreadingHTTPServer`, no framework, no SSE, no session-id handling
needed. Requirements that actually mattered:

- `POST /mcp` only. `GET /mcp` → **405** with empty/error body is fine — neither Claude
  Code nor Codex require SSE or a `GET` stream for this flow; Claude Code *does* probe
  `GET /mcp` once and silently accepts the 405.
- Every JSON-RPC **request** (has `id`) → `200`, `Content-Type: application/json`, a
  single JSON object body (not SSE, not chunked).
- Every JSON-RPC **notification** (no `id`, e.g. `notifications/initialized`) →
  **202 Accepted**, empty body, no JSON.
- `Authorization: Bearer testtoken` required on every request; otherwise **401**. Both
  clients send the header on every call, including the pre-`initialize` probe.
- No `Mcp-Session-Id` requirement observed from either client.
- `initialize`: echo the client's `protocolVersion` if in an allow-list, else fall back
  to `"2025-06-18"`. Claude Code 2.1.281 actually requests **`protocolVersion:
  "2025-11-25"`** (newer than the commonly-documented `2025-06-18`) — a server that
  hard-rejects unknown versions instead of falling back would break it. Codex requests
  `"2025-06-18"`.
- Claude Code sends an extra **`server/discover`** probe (custom method, id
  `"server-discover-probe-1"`) before `initialize`. Returning a normal JSON-RPC error
  for the unknown method is fine — Claude Code proceeds to `initialize` regardless.
- `tools/call` → `{"content":[{"type":"text","text":"created"}]}`; logging args to a
  file (`calls.log`) is enough to prove invocation end-to-end.

Working file: `.../scratchpad/mcp-http/server.py` (self-contained, ~140 lines, stdlib only).

## 2. Claude Code — VERIFIED

Exact `--mcp-config` JSON (inline string or `--mcp-config path/to/file.json` — both work
identically):

```json
{"mcpServers":{"bunny":{"type":"http","url":"http://127.0.0.1:PORT/mcp","headers":{"Authorization":"Bearer testtoken"}}}}
```

Command:
```
claude --model haiku --mcp-config '<json above>' -p "Use the bunny create_task tool..." --allowedTools 'mcp__bunny'
```

**Gotcha (argv order):** `--allowedTools`/`--disallowedTools` are *variadic*
(`<tools...>`) — they greedily swallow every following bare argument, including the
prompt, producing `Error: Input must be provided either through stdin or as a prompt
argument`. Fix: put the prompt argument **before** `--allowedTools`, or terminate the
tool list with `--` before the prompt. Bunny should always place `--allowedTools ...`
last, or use `--` as a separator, when constructing argv programmatically.

**Auto-allow pattern:** both `mcp__bunny` (whole server) and `mcp__bunny__*` (wildcard)
auto-allow every tool call from that server with **zero permission prompt** — confirmed
via the server's call-log recording `create_task` invocations with no interactive
prompt and clean non-interactive exit. `mcp__bunny` (server-level, no suffix) is the
simplest and is what Claude Code's own `claude mcp add` help implies as the canonical
form; prefer it.

`--permission-mode acceptEdits` combined with `--allowedTools 'mcp__bunny'`: not
re-verified in the final pass (flaky under heavy local system load — see Gotchas), but
this mode only affects file-edit tool prompts (Edit/Write) per Claude Code's documented
behavior; it should not change MCP tool auto-allow, which is governed solely by
`--allowedTools`. **INFERRED**, not independently re-confirmed this run (an earlier
identical test before the environment got noisy did complete but its output was lost to
a background-task filesystem issue — see Gotchas).

`--output-format stream-json --input-format stream-json --permission-prompt-tool stdio`
was not empirically exercised in this pass (time-boxed) — **not verified**. Given that
`--allowedTools mcp__bunny` already fully auto-allows the tool with the plain `-p`
transport, no `can_use_tool` request would be expected to reach the permission-prompt
sidecar for that tool either. **INFERRED**.

## 3. Codex — VERIFIED

### config.toml (global `codex mcp add`)
```
codex mcp add bunny --url http://127.0.0.1:PORT/mcp --bearer-token-env-var BUNNY_TOKEN
```
produces:
```toml
[mcp_servers.bunny]
url = "http://127.0.0.1:PORT/mcp"
bearer_token_env_var = "BUNNY_TOKEN"
```
`codex mcp add` has **no `--header` flag** — only `--bearer-token-env-var` (reads the
token from an env var at launch; a literal inline `bearer_token` key is explicitly
rejected: *"uses unsupported `bearer_token`; set `bearer_token_env_var`"*). Confirmed via
`codex mcp add`/`list`/`get`/`remove bunny` dry run (config restored to original after).

### Direct `http_headers` (used for `-c` overrides and the app-server `config` object)
The TOML schema for a streamable-HTTP `mcp_servers.<name>` entry does accept
`http_headers` directly (confirmed via `codex exec -c` overrides and via app-server
`config`), e.g.:
```toml
[mcp_servers.bunny]
url = "http://127.0.0.1:PORT/mcp"
http_headers = { Authorization = "Bearer testtoken" }
```
Full field set for a streamable-HTTP server (from binary introspection, not all
exercised): `url`, `bearer_token_env_var`, `http_headers`, `env_http_headers`,
`http_headers_helper` (stdio-only), `startup_timeout_sec`, `tool_timeout_sec`, `enabled`,
`default_tools_approval_mode` (valid values: `auto`, `prompt`, `writes`, `approve` — no
`never`/`always`).

### `codex exec` — VERIFIED, with a critical approval gotcha
```
codex exec -m gpt-5.6-luna -c model_reasoning_effort="low" \
  -c approval_policy="never" -c sandbox_mode="danger-full-access" \
  -c 'mcp_servers.bunny.url="http://127.0.0.1:PORT/mcp"' \
  -c 'mcp_servers.bunny.http_headers={Authorization="Bearer testtoken"}' \
  "Use the bunny create_task MCP tool to create a task titled Hello, then reply done."
```
This called the tool cleanly (verified in the server log) with reply `done`.

**Gotcha:** `approval_policy="never"` alone (with `sandbox_mode="workspace-write"`) does
**not** auto-allow MCP tool calls — it fails closed. Observed error: *"MCP tool call
requires approval, but approval policy is never"*, and the agent gives up (`"I couldn't
create it because the Bunny tool requires approval, which isn't available in this
session."`). `default_tools_approval_mode="auto"` on the server entry did **not** fix
this either. The combination that worked was `approval_policy="never"` **+**
`sandbox_mode="danger-full-access"` together (also confirmed the CLI-only escape hatch
`--dangerously-bypass-approvals-and-sandbox` works, but that's broader than needed — the
`-c` pair above is the mechanism to use programmatically). Bunny must set
**both** `approvalPolicy: "never"` and `sandbox: "danger-full-access"` — `workspace-write`
is not sufficient for unattended MCP tool calls.

### App-server `thread/start` (what Bunny actually uses) — VERIFIED
```jsonc
{
  "cwd": "/abs/path",
  "approvalPolicy": "never",
  "sandbox": "danger-full-access",
  "config": {
    "mcp_servers": {
      "bunny": {
        "url": "http://127.0.0.1:PORT/mcp",
        "http_headers": { "Authorization": "Bearer testtoken" }
      }
    }
  }
}
```
Driven end-to-end with `/private/tmp/.../scratchpad/mcp-http/drive_appserver.py`
(adapted from the existing `drive4.py`). Result: `mcpServer/startupStatus/updated`
(`status:"ready"`) → `turn/start` → an `item/started`/`item/completed` pair with
`"type":"mcpToolCall","server":"bunny","tool":"create_task","status":"completed"` and no
approval request round-trip at all → final `agentMessage` "Done." → `turn/completed`.
Server log confirms the real HTTP call landed. This is the strongest signal: with
`danger-full-access` + `never`, MCP tool calls are silent and require no
`item/*/requestApproval` handling in Bunny's driver.

## 4. Global install / uninstall — VERIFIED, both cleaned up after testing

Claude Code:
```
claude mcp add --transport http --scope user bunny http://127.0.0.1:PORT/mcp --header "Authorization: Bearer testtoken"
claude mcp remove bunny -s user
```
Confirmed `claude mcp get bunny` showed `Scope: User config`, `Status: ✔ Connected`,
headers redacted in `list` but shown in `get`; after `remove`, `claude mcp get bunny`
correctly reports no such server.

Codex:
```
codex mcp add bunny --url http://127.0.0.1:PORT/mcp --bearer-token-env-var BUNNY_TOKEN
codex mcp remove bunny
```
Confirmed via `codex mcp list`/`get`, and `config.toml` diffed back to identical
(modulo unrelated key-order churn from TOML rewriting) after removal.

## Gotchas

- **Claude Code argv order**: `--allowedTools` is variadic and will eat a
  trailing bare prompt string — always sequence flags so `--allowedTools` isn't
  immediately followed by the prompt, or use `--`.
- **Codex approval is two-layered**: the top-level `approval_policy` governs shell/exec
  approval; MCP tool calls have their own gate that, per this test, is only fully
  bypassed by pairing `approval_policy: "never"` with `sandbox: "danger-full-access"`
  (not `workspace-write`). Bunny should always launch Codex threads with both set this
  way when it wants unattended MCP tool use.
- **Codex config has no plaintext inline bearer token field** — `bearer_token` is
  rejected; use `bearer_token_env_var` (global config) or `http_headers` directly (CLI
  `-c` overrides / app-server `config` object both accept `http_headers` inline, which
  is what Bunny's app-server driver should use since it doesn't need to persist a token
  to an env var).
- **This dev machine's background-task plumbing was flaky** under heavy concurrent
  load (many real Claude/Codex processes already running from the live Bunny app and
  other sessions): a couple of `claude -p` invocations that were moved to the harness's
  "background" state lost their redirected output entirely (files never appeared) and
  had to be re-run once the system quieted down. Not a Claude Code or Codex bug — an
  artifact of this test environment. Re-runs succeeded cleanly and quickly (a few
  seconds) once load dropped, so treat any single slow/hung local repro with suspicion
  before concluding it's a client/server protocol issue.
- Neither client requires `Mcp-Session-Id` or SSE for this flow — a plain
  request/response `POST /mcp` server is sufficient for both Claude Code and Codex as
  Bunny will use them (single JSON-RPC request → single JSON response).
