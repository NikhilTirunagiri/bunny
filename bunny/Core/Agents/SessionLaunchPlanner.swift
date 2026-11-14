import Foundation

/// Actions to take when launching a session in an external application.
enum LaunchStep: Equatable {
    /// Write a `.command` file with the given script, then run `/usr/bin/open` with `openArguments`,
    /// where the argument `SessionLaunchPlanner.scriptPlaceholder` stands for the file's path.
    case runCommandFile(script: String, openArguments: [String])
    /// Execute a process with the given executable and arguments.
    case exec(executable: String, arguments: [String])
    /// Open a URL (a deep link). With a delay it is opened later, unchecked; without, at once and a refusal fails the step.
    case openURL(String, delay: TimeInterval)
    /// Run a short-lived command in `cwd` and wait for it: a non-zero exit (or no exit in time) fails the step.
    /// What it prints is never a failure by itself.
    case runCLI(executable: String, arguments: [String], cwd: String)
}

/// Planner for how to open an existing Claude Code or Codex session in various applications.
enum SessionLaunchPlanner {
    /// Stands for the written `.command` file's path in `LaunchStep.runCommandFile`'s arguments.
    static let scriptPlaceholder = "{script}"
    /// Gives a command a terminal of its own (a pseudo-terminal): `script -q /dev/null <command…>`.
    static let pseudoTerminalTool = "/usr/bin/script"

    /// Character set for strict percent-encoding (unreserved characters only).
    private static let strictUnreservedSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Escapes a string for safe use in POSIX shell commands using single-quote wrapping.
    /// Plain strings are wrapped in single quotes. Single quotes within the string are escaped
    /// by ending the quote, adding an escaped single quote, and resuming the quote.
    /// Example: "it's" -> "'it'\\''s'"
    static func shellQuote(_ s: String) -> String {
        // Replace each single quote with '\''
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Builds a shell command to resume a session in the appropriate CLI, with the run's model/effort
    /// when set (nil or blank = the CLI's default).
    /// For claudeCode: "cd '<cwd>' && exec '<cli>' --resume '<id>' [--model '<m>'] [--effort '<e>']"
    /// For codex: "cd '<cwd>' && exec '<cli>' resume [-m '<m>'] [-c 'model_reasoning_effort="<e>"'] '<id>'"
    static func resumeCommand(harness: AgentHarness, cliPath: String, sessionID: String, cwd: String,
                              model: String? = nil, effort: String? = nil) -> String {
        let quotedCwd = shellQuote(cwd)
        let quotedCli = shellQuote(cliPath)
        let quotedID = shellQuote(sessionID)
        let model = AgentRunnerText.nonEmpty(model)
        let effort = AgentRunnerText.nonEmpty(effort)

        switch harness {
        case .claudeCode:
            var command = "cd \(quotedCwd) && exec \(quotedCli) --resume \(quotedID)"
            if let model { command += " --model \(shellQuote(model))" }
            if let effort { command += " --effort \(shellQuote(effort))" }
            return command
        case .codex:
            var options = ""
            if let model { options += " -m \(shellQuote(model))" }
            if let effort { options += " -c \(shellQuote("model_reasoning_effort=\(tomlString(effort))"))" }
            return "cd \(quotedCwd) && exec \(quotedCli) resume\(options) \(quotedID)"
        }
    }

    /// A TOML basic string, for `codex -c key=value` overrides.
    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// A `.command` file that runs `command`. The terminal runs it in a shell of its own, which may carry
    /// an enclosing Claude Code session's variables (`ChildEnvironment`): they are unset first.
    static func commandScript(_ command: String) -> String {
        "#!/bin/zsh -l\n\(ChildEnvironment.shellUnset)\n\(command)\n"
    }

    /// How an app picked with "Other App…" is driven, by its bundle identifier.
    enum CustomRoute: Equatable {
        /// `open -a <app> <script>`: iTerm, Warp and any app Bunny doesn't know.
        case script
        case ghostty, kitty, wezterm, alacritty
        /// VS Code or a fork: `cli` is the command's name inside the bundle, `scheme` its URL scheme.
        case editor(cli: String, scheme: String)
        case claudeApp, codexApp
    }

    static func customRoute(bundleIdentifier: String?) -> CustomRoute {
        switch bundleIdentifier {
        case "com.mitchellh.ghostty": return .ghostty
        case "net.kovidgoyal.kitty": return .kitty
        case "com.github.wez.wezterm": return .wezterm
        case "org.alacritty": return .alacritty
        case "com.microsoft.VSCode": return .editor(cli: "code", scheme: "vscode")
        case "com.microsoft.VSCodeInsiders": return .editor(cli: "code", scheme: "vscode-insiders")
        case "com.todesktop.230313mzl4w4u92": return .editor(cli: "cursor", scheme: "cursor")
        case "com.exafunction.windsurf": return .editor(cli: "windsurf", scheme: "windsurf")
        case "com.vscodium": return .editor(cli: "codium", scheme: "vscodium")
        case "com.anthropic.claudefordesktop": return .claudeApp
        case "com.openai.codex": return .codexApp
        default: return .script
        }
    }

    /// Whether an app can be offered under "Other App…": one Bunny knows how to drive, or one that
    /// declares it runs `.command` shell scripts (terminals do; a text editor that merely opens
    /// scripts as text does not claim this type). Anything else could not open a session.
    static func canOpenSessions(bundleIdentifier: String?, claimedExtensions: [String], claimedTypes: [String]) -> Bool {
        if customRoute(bundleIdentifier: bundleIdentifier) != .script { return true }
        return claimedExtensions.contains { $0.lowercased() == "command" }
            || claimedTypes.contains("com.apple.terminal.shell-script")
    }

    /// `open -a <app> <script>`: the app opens the `.command` file as a document and runs it.
    private static func scriptStep(_ resumeCmd: String, openWith app: String) -> LaunchStep {
        .runCommandFile(script: commandScript(resumeCmd), openArguments: ["-a", app, scriptPlaceholder])
    }

    /// `open -na <app> --args <arguments> /bin/zsh -l <script>`: a new instance of a terminal that
    /// doesn't open `.command` files, started with its own CLI arguments to run the script.
    private static func scriptStep(_ resumeCmd: String, launching app: String, arguments: [String]) -> LaunchStep {
        .runCommandFile(script: commandScript(resumeCmd),
                        openArguments: ["-na", app, "--args"] + arguments + ["/bin/zsh", "-l", scriptPlaceholder])
    }

    /// VS Code or a fork: the editor's CLI opens the folder, then the Claude Code extension's URI opens
    /// the session; a Codex session has no such URI, so it resumes in Terminal beside the editor.
    private static func editorSteps(bundle: String, cli: String, scheme: String, harness: AgentHarness,
                                    sessionID: String, cwd: String, resumeCmd: String) -> [LaunchStep] {
        let openFolder = LaunchStep.exec(executable: "\(bundle)/Contents/Resources/app/bin/\(cli)", arguments: [cwd])
        guard harness == .claudeCode else { return [openFolder, scriptStep(resumeCmd, openWith: "Terminal")] }
        return [openFolder, .openURL("\(scheme)://anthropic.claude-code/open?session=\(encoded(sessionID))", delay: 1.0)]
    }

    private static func encoded(_ sessionID: String) -> String {
        sessionID.addingPercentEncoding(withAllowedCharacters: strictUnreservedSet) ?? sessionID
    }

    /// Plans the steps needed to open a session in the specified application.
    /// `appPath`: the located app bundle (required for `custom`; nil for VS Code = /Applications).
    /// `bundleIdentifier`: of a `custom` app, which picks its route (`customRoute`).
    /// `model`/`effort`: the run's settings, added to terminal resume commands (the editor extension URI
    /// and the desktop apps open the session by id, which carries no model/effort).
    /// A desktop app asked for the other agent's session, or a custom app with no path, plans the Terminal route.
    static func plan(app: OpenInApp, harness: AgentHarness, cliPath: String, sessionID: String, cwd: String,
                     model: String? = nil, effort: String? = nil,
                     appPath: String? = nil, bundleIdentifier: String? = nil) -> [LaunchStep] {
        let resumeCmd = resumeCommand(harness: harness, cliPath: cliPath, sessionID: sessionID, cwd: cwd,
                                      model: model, effort: effort)
        let terminal = [scriptStep(resumeCmd, openWith: "Terminal")]
        let route: CustomRoute
        var bundle = appPath
        switch app {
        case .terminal: return terminal
        case .vscode:
            route = .editor(cli: "code", scheme: "vscode")
            bundle = appPath ?? "/Applications/Visual Studio Code.app"
        case .claudeApp: route = .claudeApp
        case .codexApp: route = .codexApp
        case .custom: route = customRoute(bundleIdentifier: bundleIdentifier)
        }

        switch route {
        case .claudeApp:
            guard harness == .claudeCode else { return terminal }
            // `claude --desktop` refuses to run without a terminal ("can't run non-interactively"), so it
            // gets a pseudo-terminal; it only hands the session to the app and exits.
            return [.runCLI(executable: pseudoTerminalTool,
                            arguments: ["-q", "/dev/null", cliPath, "--desktop", "--resume", sessionID], cwd: cwd)]
        case .codexApp:
            guard harness == .codex else { return terminal }
            return [.openURL("codex://threads/\(encoded(sessionID))", delay: 0)]
        default: break
        }
        guard let bundle else { return terminal }

        switch route {
        case .script:
            return [scriptStep(resumeCmd, openWith: bundle)]
        case .ghostty:
            return [.exec(executable: "/usr/bin/open",
                          arguments: ["-na", bundle, "--args", "--working-directory=\(cwd)", "-e", "/bin/zsh", "-lc", resumeCmd])]
        case .kitty:
            return [scriptStep(resumeCmd, launching: bundle, arguments: ["--directory", cwd])]
        case .wezterm:
            return [scriptStep(resumeCmd, launching: bundle, arguments: ["start", "--cwd", cwd, "--"])]
        case .alacritty:
            return [scriptStep(resumeCmd, launching: bundle, arguments: ["--working-directory", cwd, "-e"])]
        case let .editor(cli, scheme):
            return editorSteps(bundle: bundle, cli: cli, scheme: scheme, harness: harness, sessionID: sessionID,
                               cwd: cwd, resumeCmd: resumeCmd)
        case .claudeApp, .codexApp:
            return terminal
        }
    }

    /// The first line of a command's output that says something, for the note shown when it failed.
    /// Output captured from a pseudo-terminal carries escape sequences ("\u{1B}[?25h"), the echoed
    /// end-of-input ("^D" and backspaces) and other control characters: they are dropped first.
    static func firstMeaningfulLine(_ output: String, limit: Int = 160) -> String? {
        let scalars = Array(output.unicodeScalars)
        var cleaned = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\u{1B}" {
                index += 1
                guard index < scalars.count else { break }
                if scalars[index] == "[" {
                    // CSI: parameters, then one final byte.
                    index += 1
                    while index < scalars.count, !(0x40...0x7E).contains(scalars[index].value) { index += 1 }
                } else if scalars[index] == "]" {
                    // OSC: up to BEL, or ESC and a backslash.
                    index += 1
                    while index < scalars.count, scalars[index] != "\u{07}", scalars[index] != "\u{1B}" { index += 1 }
                    if index < scalars.count, scalars[index] == "\u{1B}" { index += 1 }
                }
                index += 1
                continue
            }
            if scalar == "^", index + 1 < scalars.count, scalars[index + 1] == "D" {
                index += 2
                continue
            }
            if scalar == "\r" || scalar == "\n" {
                cleaned.append("\n")
            } else if scalar == "\t" {
                cleaned.append(" ")
            } else if scalar.value >= 0x20, scalar.value != 0x7F {
                cleaned.append(scalar)
            }
            index += 1
        }
        return String(cleaned).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(limit)) }
    }
}
