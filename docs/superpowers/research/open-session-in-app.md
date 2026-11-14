# Opening an agent session in the user's app (verified 2026-09-24 on this Mac)

| App | Claude Code (session id) | Codex (thread id) |
|---|---|---|
| Terminal.app | temp `.command` file: `#!/bin/zsh -l` · `cd '<dir>' && exec claude --resume '<id>'` → `open -a Terminal <file>` | same, `exec codex resume '<id>'` |
| Ghostty | `open -na /Applications/Ghostty.app --args --working-directory=<dir> -e <login-shell> -lc "claude --resume <id>"` | same with `codex resume <id>` |
| VS Code | 1) `"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" <dir>` 2) open URL `vscode://anthropic.claude-code/open?session=<id>` | no Codex IDE extension installed → open folder with `code <dir>` **and** fall back to the Terminal route for `codex resume <id>` |
| Cursor | 1) `/Applications/Cursor.app/Contents/Resources/app/bin/cursor <dir>` 2) `cursor://anthropic.claude-code/open?session=<id>` | same fallback as VS Code |

Notes
- `.command` route avoids AppleEvents/Automation permission prompts entirely
  (`open -a Terminal file.command` runs it in Terminal). Files created locally
  carry no quarantine attribute. Write them into
  `~/Library/Application Support/Bunny/launch/`, `chmod 755`, delete after 60 s.
- Ghostty: launching the binary directly is unsupported on macOS; `+new-window`
  unsupported. `-e` passes remaining argv verbatim.
- Claude Code VS Code/Cursor extension URI handler: path `/open`, query
  `session` (validated; malformed ids silently ignored) and optional `prompt`.
  No folder param → open the folder first, then the URI after ~1 s.
- `claude --resume <id>` must run in the session's original cwd (sessions are
  stored per project dir) — always `cd` to the task's working directory.
- `codex resume <id>` restores the recorded cwd itself; `-C <dir>` overrides.
- Resolve CLI paths from Settings (auto-detected via login shell `command -v`).

## Per-agent targets (updated 2026-11-14)

Settings → Agents has one row per agent ("Open Claude Code sessions in", "Open Codex sessions in";
keys `agent.openIn.claude` / `agent.openIn.codex`). The menu is short: Terminal · VS Code · the agent's
own desktop app · the app picked with "Other App…" (`agent.openIn.<agent>.customPath` / `.customName`).
An app picked with "Other App…" is driven by its bundle identifier (`SessionLaunchPlanner.customRoute`);
unknown apps get the script route. `<script>` is the `.command` file (`#!/bin/zsh -l`, the `unset` line,
`cd '<dir>' && exec claude --resume '<id>' …` or `exec codex resume … '<id>'`), deleted after 60 s.
Every route falls back to Terminal with a one-line note in the agent section; if Terminal fails too the
resume command is copied.

| Target | Bundle id | Launch form | Status |
|---|---|---|---|
| Terminal (built in) | `com.apple.Terminal` | `open -a Terminal <script>` | verified on this Mac (2026-09-24) |
| VS Code (built in) | `com.microsoft.VSCode` (read from the installed app) | `<bundle>/Contents/Resources/app/bin/code <dir>`, then after 1 s `vscode://anthropic.claude-code/open?session=<id>`; Codex: the folder, then the Terminal route | URI documented by the Claude Code extension; verified 2026-09-24 |
| Claude app (Claude Code only) | `com.anthropic.claudefordesktop` (read from the installed app) | `/usr/bin/script -q /dev/null <claude cli> --desktop --resume <id>` (a pseudo-terminal), stdin from `/dev/null`, run in `<dir>` with the scrubbed environment, waited for (30 s, then the process group is killed). Success = exit status 0 only; a non-zero exit or the timeout = failure → Terminal, with the first meaningful line of the output (control characters and escape sequences stripped) in the note | verified on this Mac (2026-11-14, Claude Code 2.1.325): prints "Opening session <id> in Claude Desktop" and exits 0 within a few seconds. Run as a plain child with pipes (no terminal) the CLI refuses: "--desktop opens the Claude Desktop app and can't run non-interactively (`--print`, `--sdk-url`, `--init-only`, …)", which is why v3.0.0 always fell back to Terminal. The output is not judged: under `script` it carries `^D` and escape sequences such as `ESC[?25h`. Flag from `claude --help` ("Open in the Claude Desktop app instead of the terminal (with --continue or --resume <id> to pick the session)"). Needs CLI ≥ 2.1.285 and a subscription sign-in, and refuses a session still running elsewhere (per the task brief; not found again on code.claude.com/docs/en/desktop) |
| Codex app (Codex only) | `com.openai.codex` (read from the installed app, which is named ChatGPT.app and registers the `codex` scheme); else whatever handles `codex://` | open URL `codex://threads/<thread-id>` | deep link documented (https://learn.chatgpt.com/docs/reference/commands: "`<thread-id>` is its technical thread ID"). Not documented that an app-server thread id is that id: best-effort. Failure is only detectable when no app handles the URL; "opened but thread not found" cannot be detected |
| Other App…: Ghostty | `com.mitchellh.ghostty` (project.pbxproj in ghostty-org/ghostty) | `open -na <bundle> --args --working-directory=<dir> -e /bin/zsh -lc "<resume command>"` | verified 2026-09-24 |
| Other App…: kitty | `net.kovidgoyal.kitty` (setup.py in kovidgoyal/kitty) | `open -na <bundle> --args --directory <dir> /bin/zsh -l <script>` | CLI documented (https://sw.kovidgoyal.net/kitty/invocation/: `kitty [options] [program-to-run ...]`, `--directory`); not run |
| Other App…: WezTerm | `com.github.wez.wezterm` (Info.plist in wezterm/wezterm; executable `wezterm-gui`) | `open -na <bundle> --args start --cwd <dir> -- /bin/zsh -l <script>` | CLI documented (https://wezterm.org/cli/start.html: `--cwd`, `wezterm start -- prog`); not run |
| Other App…: Alacritty | `org.alacritty` (Info.plist in alacritty/alacritty) | `open -na <bundle> --args --working-directory <dir> -e /bin/zsh -l <script>` | CLI documented (man page extra/man/alacritty.1.scd: `--working-directory`, `-e` "must be last argument"); not run |
| Other App…: Cursor | `com.todesktop.230313mzl4w4u92` (read from the installed app) | `<bundle>/Contents/Resources/app/bin/cursor <dir>`, then `cursor://anthropic.claude-code/open?session=<id>`; Codex: folder + Terminal route | best-effort: the extension documents only the `vscode://` form |
| Other App…: VS Code Insiders, Windsurf, VSCodium | `com.microsoft.VSCodeInsiders`, `com.exafunction.windsurf`, `com.vscodium` (from memory, unverified) | same editor route with `bin/code` + `vscode-insiders://`, `bin/windsurf` + `windsurf://`, `bin/codium` + `vscodium://` | best-effort, unverified (ids, CLI names and schemes); a missing CLI falls back to Terminal |
| Other App…: iTerm, Warp, anything else | iTerm `com.googlecode.iterm2`, Warp `dev.warp.Warp-Stable` (both unverified; not needed, they take the default route) | `open -a <bundle> <script>` | iTerm: opens `.command` files (well known, not run). Warp: its docs say it opens `.command` files, but an open issue (warpdotdev/Warp #9020, April 2026) reports them opening in Warp's editor instead of running: best-effort. Other apps: only works if the app runs a `.command` document |

Migration: an old `agent.openIn` is copied once to both agents. `terminal` and `vscode` map directly;
`ghostty` and `cursor` become that agent's "Other App…" pick when the app is installed, else Terminal.
With no old value nothing is written (unset reads as Terminal).
