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
