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
**Superseded:** `default_tools_approval_mode = "approve"` on the server entry fixes this under
`workspace-write`. See "Codex approval — resolved" below.

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
(Bunny's installer no longer uses `--bearer-token-env-var`; see "Codex config merge and the global
install" below.)
Confirmed via `codex mcp list`/`get`, and `config.toml` diffed back to identical
(modulo unrelated key-order churn from TOML rewriting) after removal.

## Gotchas

- **Claude Code argv order**: `--allowedTools` is variadic and will eat a
  trailing bare prompt string — always sequence flags so `--allowedTools` isn't
  immediately followed by the prompt, or use `--`.
- **Codex approval is two-layered**: the top-level `approval_policy` governs shell/exec
  approval; MCP tool calls have their own gate. The earlier conclusion here, that only
  `danger-full-access` bypasses that gate, is **superseded**: the per-server
  `default_tools_approval_mode = "approve"` works under `workspace-write`. See
  "Codex approval — resolved".
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

## Codex approval — resolved (verified 2026-09-24, codex-cli 0.155.0, `gpt-5.6-luna`)

Bunny keeps `sandbox: "workspace-write"` and does not switch to `danger-full-access`. Every run
below used `codex app-server --stdio` with `workspace-write` and the Bunny server in
`thread/start` `config.mcp_servers.bunny`. The turn asked the model to call `create_task`, and a
driver logged every server→client request. Drivers are in `.../scratchpad/d3/drive.py`, run logs in
`.../scratchpad/d3/run-*.log`, and the server is `.../scratchpad/mcp-http/server.py`.

| approvalPolicy | bunny server extra | server→client request for the MCP call | result |
|---|---|---|---|
| `"never"` | — | none | **fails**: `mcpToolCall` `status:"failed"`, error *"MCP tool call requires approval, but approval policy is never"* |
| `"never"` | `default_tools_approval_mode = "approve"` | **none** | **works**: `mcpToolCall` completed, server log has the call |
| `"on-request"` | — | `mcpServer/elicitation/request` (below) | works once the client replies `accept` |
| `"on-request"` | `default_tools_approval_mode = "approve"` | **none** | works |
| `{"granular": {sandbox_approval:false, rules:false, skill_approval:false, request_permissions:false, mcp_elicitations:true}}` | — | `mcpServer/elicitation/request` | works once accepted. Commands behave like `never`: a `touch` outside the workspace failed with *Operation not permitted*, and there was no approval request |

`"on-request"` also asks for command escalation. `touch /Users/nt/…` produced
`item/commandExecution/requestApproval` with `availableDecisions: ["accept",
{"acceptWithExecpolicyAmendment": …}, "cancel"]`. So on-request is not a hands-off policy.

The approval request Codex sends for an MCP tool call is an MCP elicitation, not an
`item/*/requestApproval`:

```json
{"method":"mcpServer/elicitation/request","id":0,"params":{"threadId":"…","turnId":"…",
 "serverName":"bunny","mode":"form",
 "_meta":{"codex_approval_kind":"mcp_tool_call","persist":["session","always"],
          "tool_description":"Create a task in Bunny","tool_params":{"title":"ProbeTask"}, …},
 "message":"Allow the bunny MCP server to run tool \"create_task\"?",
 "requestedSchema":{"type":"object","properties":{}}}}
```

The reply that works (`McpServerElicitationRequestResponse`) is
`{"id":0,"result":{"action":"accept","content":null,"_meta":null}}`.

The earlier section's `default_tools_approval_mode="auto"` does **not** help, because "auto" defers
to tool annotations. `"approve"` does.

### What Bunny does (`CodexRunner` / `CodexWire`)

- **Approval policy is unchanged.** `.autonomous` sends `"never"` and `.askFirst` sends `"on-request"`,
  always with `workspace-write`, so command and file approval semantics stay as they were.
- **The Bunny server entry carries `default_tools_approval_mode: "approve"`:**
  ```json
  "config": {"mcp_servers": {"bunny": {
    "url": "http://127.0.0.1:PORT/mcp",
    "http_headers": {"Authorization": "Bearer TOKEN", "X-Bunny-Task": "UUID"},
    "default_tools_approval_mode": "approve"}}}
  ```
  It is merged with `sandbox_workspace_write.writable_roots` when there are extra directories, and
  re-sent on `thread/resume` together with the model, because a new app-server process does not have it.
- **Defense in depth.** An `mcpServer/elicitation/request` whose `serverName` is `"bunny"` is
  auto-accepted with the reply above, in either autonomy mode, but only when the run has Bunny
  tools configured (`options.tools != nil`). This matches Claude's `--allowedTools mcp__bunny`.
  All other elicitations, including a "bunny" server the run did not attach, get the existing
  method-not-found reply. Command and file approvals keep the existing flow: they surface as
  questions under `.askFirst`, and `"never"` never asks.
- The gated live test `liveCodexCreatesTaskWithBunnyTools` (`BUNNY_LIVE_AGENT_TESTS=1`) runs the real
  `CodexRunner` under `never` + `workspace-write` against
  `Tests/BunnyCoreTests/FakeCLIs/fake_mcp_http.py`. It checks that `create_task` reached the server
  with the right `X-Bunny-Task` header. `liveClaudeCodeCreatesTaskWithBunnyTools` does the same for
  Claude with the real argv (`--mcp-config … --allowedTools mcp__bunny --append-system-prompt …`).

**Global install (`codex mcp add bunny`)**: `config.toml` should also get
`default_tools_approval_mode = "approve"` under `[mcp_servers.bunny]`. Otherwise sessions outside
Bunny that run with `never` + `workspace-write` hit the same failure. (Inferred from the table above;
not separately tested through `config.toml`.) Superseded by the next section: the installer now writes
the token and the approval mode itself.

## Codex config merge and the global install (verified 2026-09-24, codex-cli 0.155.0)

Everything ran against a throwaway `CODEX_HOME` (`.../scratchpad/codex-merge/home*`); the real
`~/.codex/config.toml` was never touched. `run_all.sh` re-runs every case below and its output is in
`.../scratchpad/codex-merge/results.log`. Driver: `.../scratchpad/codex-merge/drive.py` starts
`codex app-server --stdio`, sends `thread/start` (`never` + `workspace-write`) with a given `config`, and
prints every `mcpServer/startupStatus/updated`. No model turn is needed (no auth), since MCP servers start
with the thread. `hdrserver.py` is a minimal MCP server that logs each request's `Authorization` header.

The global config always had a second server `other` and a `bunny` entry pointing at a stale port.

| # | global `[mcp_servers.bunny]` | per-run `thread/start.config` | result |
|---|---|---|---|
| A | `bearer_token_env_var = "BUNNY_TOKEN"` (what `codex mcp add … --bearer-token-env-var` writes) | nested `{"mcp_servers":{"bunny":{url, http_headers, default_tools_approval_mode}}}` | **bunny fails**: *"Environment variable BUNNY_TOKEN for MCP server 'bunny' is not set"*. `other` starts. |
| B | same as A | same plus `"bearer_token_env_var": null` | **fails**: the null becomes `""` (*"Environment variable  for MCP server 'bunny' is not set"*). |
| C | same as A | dotted keys `{"mcp_servers.bunny.url": …, "mcp_servers.bunny.http_headers": …}` | **fails** exactly like A. |
| D | `http_headers = { Authorization = "Bearer stale" }` + stale url | nested, `http_headers` with `Authorization: Bearer run`, `X-Test` | **works**: bunny gets the run's url, `Bearer run` and `X-Test`. `other` starts. |
| F | same as A | nested plus `"bearer_token_env_var": "BUNNY_TOOLS_RUN_TOKEN"`, that variable set in the app-server environment | **works**: header is `Bearer <env value>`. The env var wins over `http_headers`' Authorization; `X-Test` still arrives. |
| G | patched entry (below), no per-run config | — | **works**: `Bearer <token from config.toml>`. |
| H | patched entry | nested with `bearer_token_env_var` + env set | **works**: the run's token, url and headers. |

Findings:

- The per-run `config` is **merged key by key** into the global config. It does not replace the
  `mcp_servers` table (other servers keep starting in every case) nor the `bunny` entry (global keys the run
  doesn't set survive). Dotted override keys behave identically, so switching `CodexWire` to them would not
  help.
- A global `bearer_token_env_var` therefore breaks Bunny's own runs, and a run can't delete it (null →
  `""`). It can only override it with another variable name.
- `codex mcp add` rewrites the whole file: inline tables become sub-tables
  (`[mcp_servers.other.http_headers]`), and re-adding `bunny` replaces its entry wholesale (headers and
  approval mode are dropped). `codex mcp remove bunny` removes the entry including a headers sub-table.

What Bunny does now:

- **Global install** runs `codex mcp add bunny --url http://127.0.0.1:<fixed port>/mcp` (no env var), then
  `CodexConfigPatcher` rewrites the entry to
  ```toml
  [mcp_servers.bunny]
  url = "http://127.0.0.1:47823/mcp"
  http_headers = { Authorization = "Bearer <token>" }
  default_tools_approval_mode = "approve"
  ```
  removing any `bearer_token_env_var` and any `[mcp_servers.bunny.http_headers]` sub-table. `codex mcp get
  bunny` then shows `bearer_token_env_var: -`, `http_headers: Authorization=*****`,
  `default_tools_approval_mode: approve` (the "install" step in `results.log`). The rewrite after a later
  `codex mcp add` of another server (sub-table form) was checked by hand the same way and is covered by
  `CodexConfigPatcherTests`.
- **Per-run config** (`CodexWire.mcpServersConfig`) keeps the nested object and adds
  `"bearer_token_env_var": "BUNNY_TOOLS_TOKEN"`; `CodexRunner` sets `BUNNY_TOOLS_TOKEN=<token>` in the
  app-server's environment (runs F and H). A stale global entry, such as one written by the earlier installer
  or by hand, can then no longer break Bunny's runs. Codex's default `shell_environment_policy` leaves
  variables whose names contain `TOKEN` out of the environment of the commands the agent runs. That comes
  from Codex's documentation and was not tested here.
