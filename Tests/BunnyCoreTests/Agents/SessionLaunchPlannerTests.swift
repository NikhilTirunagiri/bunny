import Foundation
import Testing

@testable import BunnyCore

@Suite
struct SessionLaunchPlannerTests {
    // MARK: - shellQuote Tests

    @Test("shellQuote: plain string")
    func shellQuote_plain() {
        let result = SessionLaunchPlanner.shellQuote("abc")
        #expect(result == "'abc'")
    }

    @Test("shellQuote: string with single quote")
    func shellQuote_withSingleQuote() {
        let result = SessionLaunchPlanner.shellQuote("it's")
        #expect(result == "'it'\\''s'")
    }

    @Test("shellQuote: string with spaces")
    func shellQuote_withSpaces() {
        let result = SessionLaunchPlanner.shellQuote("hello world")
        #expect(result == "'hello world'")
    }

    // MARK: - resumeCommand Tests

    @Test("resumeCommand: claudeCode harness")
    func resumeCommand_claudeCode() {
        let result = SessionLaunchPlanner.resumeCommand(
            harness: .claudeCode,
            cliPath: "/usr/local/bin/claude",
            sessionID: "abc123",
            cwd: "/tmp/project"
        )
        let expected = "cd '/tmp/project' && exec '/usr/local/bin/claude' --resume 'abc123'"
        #expect(result == expected)
    }

    @Test("resumeCommand: codex harness")
    func resumeCommand_codex() {
        let result = SessionLaunchPlanner.resumeCommand(
            harness: .codex,
            cliPath: "/usr/local/bin/codex",
            sessionID: "xyz789",
            cwd: "/home/user/work"
        )
        let expected = "cd '/home/user/work' && exec '/usr/local/bin/codex' resume 'xyz789'"
        #expect(result == expected)
    }

    @Test("resumeCommand: claudeCode with model and effort")
    func resumeCommand_claudeCodeModelEffort() {
        let result = SessionLaunchPlanner.resumeCommand(
            harness: .claudeCode, cliPath: "/c", sessionID: "id1", cwd: "/w", model: "opus", effort: "high")
        #expect(result == "cd '/w' && exec '/c' --resume 'id1' --model 'opus' --effort 'high'")
    }

    @Test("resumeCommand: codex with model and effort")
    func resumeCommand_codexModelEffort() {
        let result = SessionLaunchPlanner.resumeCommand(
            harness: .codex, cliPath: "/x", sessionID: "id2", cwd: "/w", model: "gpt-6-luna", effort: "low")
        #expect(result == "cd '/w' && exec '/x' resume -m 'gpt-6-luna' -c 'model_reasoning_effort=\"low\"' 'id2'")
    }

    @Test("resumeCommand: blank model/effort are omitted")
    func resumeCommand_blankModelEffort() {
        let claude = SessionLaunchPlanner.resumeCommand(
            harness: .claudeCode, cliPath: "/c", sessionID: "id1", cwd: "/w", model: " ", effort: nil)
        #expect(claude == "cd '/w' && exec '/c' --resume 'id1'")
        let codex = SessionLaunchPlanner.resumeCommand(
            harness: .codex, cliPath: "/x", sessionID: "id2", cwd: "/w", model: nil, effort: "")
        #expect(codex == "cd '/w' && exec '/x' resume 'id2'")
    }

    @Test("plan: terminal script carries model and effort")
    func plan_terminalModelEffort() {
        let steps = SessionLaunchPlanner.plan(
            app: .terminal, harness: .codex, cliPath: "/x", sessionID: "id2", cwd: "/w", model: "m", effort: "high")
        #expect(steps == [.runCommandFile(script: SessionLaunchPlanner.commandScript("cd '/w' && exec '/x' resume -m 'm' -c 'model_reasoning_effort=\"high\"' 'id2'"), openArguments: Self.inTerminal)])
    }

    @Test("resumeCommand: claudeCode with cwd with space and quote")
    func resumeCommand_claudeCodeCwdWithSpaceAndQuote() {
        let result = SessionLaunchPlanner.resumeCommand(
            harness: .claudeCode,
            cliPath: "/usr/bin/claude",
            sessionID: "session-1",
            cwd: "/tmp/my project's folder"
        )
        let expected = "cd '/tmp/my project'\\''s folder' && exec '/usr/bin/claude' --resume 'session-1'"
        #expect(result == expected)
    }

    @Test("resumeCommand: codex with cwd with space and quote")
    func resumeCommand_codexCwdWithSpaceAndQuote() {
        let result = SessionLaunchPlanner.resumeCommand(
            harness: .codex,
            cliPath: "/usr/bin/codex",
            sessionID: "session-1",
            cwd: "/tmp/my project's folder"
        )
        let expected = "cd '/tmp/my project'\\''s folder' && exec '/usr/bin/codex' resume 'session-1'"
        #expect(result == expected)
    }

    // MARK: - plan Tests

    @Test("plan: terminal + claudeCode")
    func plan_terminal_claudeCode() {
        let result = SessionLaunchPlanner.plan(
            app: .terminal,
            harness: .claudeCode,
            cliPath: "/usr/local/bin/claude",
            sessionID: "abc123",
            cwd: "/tmp/project"
        )

        let expectedCommand = "cd '/tmp/project' && exec '/usr/local/bin/claude' --resume 'abc123'"
        let expectedScript = SessionLaunchPlanner.commandScript(expectedCommand)
        let expected: [LaunchStep] = [.runCommandFile(script: expectedScript, openArguments: Self.inTerminal)]

        #expect(result == expected)
    }

    @Test("plan: terminal + codex")
    func plan_terminal_codex() {
        let result = SessionLaunchPlanner.plan(
            app: .terminal,
            harness: .codex,
            cliPath: "/usr/local/bin/codex",
            sessionID: "xyz789",
            cwd: "/home/user/work"
        )

        let expectedCommand = "cd '/home/user/work' && exec '/usr/local/bin/codex' resume 'xyz789'"
        let expectedScript = SessionLaunchPlanner.commandScript(expectedCommand)
        let expected: [LaunchStep] = [.runCommandFile(script: expectedScript, openArguments: Self.inTerminal)]

        #expect(result == expected)
    }

    @Test("plan: vscode + claudeCode")
    func plan_vscode_claudeCode() {
        let result = SessionLaunchPlanner.plan(
            app: .vscode,
            harness: .claudeCode,
            cliPath: "/usr/local/bin/claude",
            sessionID: "abc123",
            cwd: "/tmp/project"
        )

        let urlString = "vscode://anthropic.claude-code/open?session=abc123"
        let expected: [LaunchStep] = [
            .exec(executable: "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code", arguments: ["/tmp/project"]),
            .openURL(urlString, delay: 1.0)
        ]

        #expect(result == expected)
    }

    @Test("plan: vscode + claudeCode with special characters in session id")
    func plan_vscode_claudeCodeSpecialChars() {
        let result = SessionLaunchPlanner.plan(
            app: .vscode,
            harness: .claudeCode,
            cliPath: "/usr/local/bin/claude",
            sessionID: "a&b=c d/e?f",
            cwd: "/tmp/project"
        )

        let urlString = "vscode://anthropic.claude-code/open?session=a%26b%3Dc%20d%2Fe%3Ff"
        let expected: [LaunchStep] = [
            .exec(executable: "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code", arguments: ["/tmp/project"]),
            .openURL(urlString, delay: 1.0)
        ]

        #expect(result == expected)
    }

    @Test("plan: vscode + codex")
    func plan_vscode_codex() {
        let result = SessionLaunchPlanner.plan(
            app: .vscode,
            harness: .codex,
            cliPath: "/usr/local/bin/codex",
            sessionID: "xyz789",
            cwd: "/home/user/work"
        )

        let script = SessionLaunchPlanner.commandScript("cd '/home/user/work' && exec '/usr/local/bin/codex' resume 'xyz789'")
        let expected: [LaunchStep] = [
            .exec(executable: "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code", arguments: ["/home/user/work"]),
            .runCommandFile(script: script, openArguments: Self.inTerminal)
        ]

        #expect(result == expected)
    }

    // MARK: - Every target × harness

    private static let inTerminal = ["-a", "Terminal", "{script}"]
    private static let claudeScript = SessionLaunchPlanner.commandScript("cd '/w dir' && exec '/bin/claude' --resume 's1' --model 'opus'")
    private static let codexScript = SessionLaunchPlanner.commandScript("cd '/w dir' && exec '/bin/codex' resume -m 'opus' 's1'")

    private func plan(_ app: OpenInApp, _ harness: AgentHarness, appPath: String? = nil) -> [LaunchStep] {
        SessionLaunchPlanner.plan(app: app, harness: harness, cliPath: harness == .claudeCode ? "/bin/claude" : "/bin/codex",
                                  sessionID: "s1", cwd: "/w dir", model: "opus", appPath: appPath)
    }

    private func script(_ harness: AgentHarness) -> String {
        harness == .claudeCode ? Self.claudeScript : Self.codexScript
    }

    private func custom(_ bundleIdentifier: String?, _ harness: AgentHarness, appPath: String? = "/Apps/X.app") -> [LaunchStep] {
        SessionLaunchPlanner.plan(app: .custom, harness: harness, cliPath: harness == .claudeCode ? "/bin/claude" : "/bin/codex",
                                  sessionID: "s1", cwd: "/w dir", model: "opus", appPath: appPath, bundleIdentifier: bundleIdentifier)
    }

    private func command(_ harness: AgentHarness) -> String {
        harness == .claudeCode
            ? "cd '/w dir' && exec '/bin/claude' --resume 's1' --model 'opus'"
            : "cd '/w dir' && exec '/bin/codex' resume -m 'opus' 's1'"
    }

    private func inTerminal(_ harness: AgentHarness) -> LaunchStep {
        .runCommandFile(script: script(harness), openArguments: Self.inTerminal)
    }

    @Test("plan: the script keeps the unset line", arguments: AgentHarness.allCases)
    func plan_scriptUnsets(harness: AgentHarness) {
        #expect(script(harness) == "#!/bin/zsh -l\n\(ChildEnvironment.shellUnset)\n\(command(harness))\n")
    }

    @Test("plan: Terminal", arguments: AgentHarness.allCases)
    func plan_terminal(harness: AgentHarness) {
        #expect(plan(.terminal, harness) == [inTerminal(harness)])
    }

    @Test("plan: VS Code with a located bundle")
    func plan_vscodeLocated() {
        #expect(plan(.vscode, .claudeCode, appPath: "/Apps/Code.app") == [
            .exec(executable: "/Apps/Code.app/Contents/Resources/app/bin/code", arguments: ["/w dir"]),
            .openURL("vscode://anthropic.claude-code/open?session=s1", delay: 1.0)])
        #expect(plan(.vscode, .codex, appPath: "/Apps/Code.app") == [
            .exec(executable: "/Apps/Code.app/Contents/Resources/app/bin/code", arguments: ["/w dir"]),
            inTerminal(.codex)])
    }

    @Test("plan: Claude app runs the CLI's --desktop under a pseudo-terminal, in the session folder")
    func plan_claudeApp() {
        // `claude --desktop` refuses to run without a terminal, so `script` gives it one.
        let expected: [LaunchStep] = [.runCLI(executable: "/usr/bin/script",
                                              arguments: ["-q", "/dev/null", "/bin/claude", "--desktop", "--resume", "s1"],
                                              cwd: "/w dir")]
        #expect(plan(.claudeApp, .claudeCode) == expected)
        // Picked through "Other App…": the same route.
        #expect(custom("com.anthropic.claudefordesktop", .claudeCode) == expected)
    }

    /// Runs the planned Claude app step as the launcher does (no terminal, stdin from /dev/null) with a
    /// stand-in for the CLI: the pseudo-terminal form must pass the command's exit status through.
    @Test("Claude app step: exit status decides, output is only a note",
          arguments: [("/bin/echo", true), ("/usr/bin/false", false)])
    func claudeAppStepExitStatus(cli: String, succeeds: Bool) throws {
        let steps = SessionLaunchPlanner.plan(app: .claudeApp, harness: .claudeCode, cliPath: cli, sessionID: "s1",
                                              cwd: NSTemporaryDirectory())
        guard case let .runCLI(executable, arguments, cwd)? = steps.first, steps.count == 1 else {
            Issue.record("unexpected plan \(steps)")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let printed = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect((process.terminationStatus == 0) == succeeds)
        // `echo` stands in for the CLI: what it was given is what the pseudo-terminal passed on.
        #expect(SessionLaunchPlanner.firstMeaningfulLine(printed) == (succeeds ? "--desktop --resume s1" : nil))
    }

    @Test("failure note: the first line that says something, without terminal control characters")
    func firstMeaningfulLine() {
        // What `script` captures: the echoed end-of-input, cursor escapes, CR LF line ends.
        let captured = "^D\u{08}\u{08}\u{1B}[?25l\r\n\u{1B}[31mError:\u{1B}[0m session is running elsewhere\r\nmore\r\n\u{1B}[?25h"
        #expect(SessionLaunchPlanner.firstMeaningfulLine(captured) == "Error: session is running elsewhere")
        #expect(SessionLaunchPlanner.firstMeaningfulLine("\u{1B}]0;title\u{07}  plain  \n") == "plain")
        #expect(SessionLaunchPlanner.firstMeaningfulLine("\u{1B}]0;title\u{1B}\\said\n") == "said")
        #expect(SessionLaunchPlanner.firstMeaningfulLine("^D\u{08}\u{08}\u{1B}[?25h\r\n \n") == nil)
        #expect(SessionLaunchPlanner.firstMeaningfulLine("") == nil)
        #expect(SessionLaunchPlanner.firstMeaningfulLine(String(repeating: "x", count: 300))?.count == 160)
    }

    @Test("plan: Codex app opens the thread deep link")
    func plan_codexApp() {
        #expect(plan(.codexApp, .codex) == [.openURL("codex://threads/s1", delay: 0)])
        #expect(custom("com.openai.codex", .codex) == [.openURL("codex://threads/s1", delay: 0)])
        let odd = SessionLaunchPlanner.plan(app: .codexApp, harness: .codex, cliPath: "/x", sessionID: "a/b c", cwd: "/w")
        #expect(odd == [.openURL("codex://threads/a%2Fb%20c", delay: 0)])
    }

    @Test("plan: a desktop app never opens the other agent's session")
    func plan_desktopAppWrongHarness() {
        #expect(plan(.claudeApp, .codex) == [inTerminal(.codex)])
        #expect(plan(.codexApp, .claudeCode) == [inTerminal(.claudeCode)])
        #expect(custom("com.anthropic.claudefordesktop", .codex) == [inTerminal(.codex)])
        #expect(custom("com.openai.codex", .claudeCode) == [inTerminal(.claudeCode)])
    }

    @Test("plan: custom app, script route (iTerm, Warp, unknown apps)",
          arguments: ["com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.example.unknown", nil] as [String?], AgentHarness.allCases)
    func plan_customScript(bundleIdentifier: String?, harness: AgentHarness) {
        #expect(custom(bundleIdentifier, harness, appPath: "/Apps/My Term.app")
            == [.runCommandFile(script: script(harness), openArguments: ["-a", "/Apps/My Term.app", "{script}"])])
    }

    @Test("plan: custom app with no path uses Terminal", arguments: AgentHarness.allCases)
    func plan_customMissing(harness: AgentHarness) {
        #expect(custom("net.kovidgoyal.kitty", harness, appPath: nil) == [inTerminal(harness)])
        #expect(custom(nil, harness, appPath: nil) == [inTerminal(harness)])
    }

    @Test("plan: custom app, Ghostty", arguments: AgentHarness.allCases)
    func plan_customGhostty(harness: AgentHarness) {
        #expect(custom("com.mitchellh.ghostty", harness, appPath: "/Applications/Ghostty.app") == [.exec(
            executable: "/usr/bin/open",
            arguments: ["-na", "/Applications/Ghostty.app", "--args", "--working-directory=/w dir", "-e", "/bin/zsh", "-lc", command(harness)])])
    }

    @Test("plan: custom app, kitty", arguments: AgentHarness.allCases)
    func plan_customKitty(harness: AgentHarness) {
        #expect(custom("net.kovidgoyal.kitty", harness) == [.runCommandFile(script: script(harness), openArguments: [
            "-na", "/Apps/X.app", "--args", "--directory", "/w dir", "/bin/zsh", "-l", "{script}"])])
    }

    @Test("plan: custom app, WezTerm", arguments: AgentHarness.allCases)
    func plan_customWezTerm(harness: AgentHarness) {
        #expect(custom("com.github.wez.wezterm", harness) == [.runCommandFile(script: script(harness), openArguments: [
            "-na", "/Apps/X.app", "--args", "start", "--cwd", "/w dir", "--", "/bin/zsh", "-l", "{script}"])])
    }

    @Test("plan: custom app, Alacritty", arguments: AgentHarness.allCases)
    func plan_customAlacritty(harness: AgentHarness) {
        #expect(custom("org.alacritty", harness) == [.runCommandFile(script: script(harness), openArguments: [
            "-na", "/Apps/X.app", "--args", "--working-directory", "/w dir", "-e", "/bin/zsh", "-l", "{script}"])])
    }

    @Test("plan: custom app, editors", arguments: [
        ("com.todesktop.230313mzl4w4u92", "cursor", "cursor"), ("com.microsoft.VSCode", "code", "vscode"),
        ("com.microsoft.VSCodeInsiders", "code", "vscode-insiders"), ("com.exafunction.windsurf", "windsurf", "windsurf"),
        ("com.vscodium", "codium", "vscodium"),
    ])
    func plan_customEditor(bundleIdentifier: String, cli: String, scheme: String) {
        let openFolder = LaunchStep.exec(executable: "/Apps/X.app/Contents/Resources/app/bin/\(cli)", arguments: ["/w dir"])
        #expect(custom(bundleIdentifier, .claudeCode) == [
            openFolder, .openURL("\(scheme)://anthropic.claude-code/open?session=s1", delay: 1.0)])
        #expect(custom(bundleIdentifier, .codex) == [openFolder, inTerminal(.codex)])
    }

    @Test("plan: opening never starts a run", arguments: OpenInApp.allCases, AgentHarness.allCases)
    func plan_total(app: OpenInApp, harness: AgentHarness) {
        let ids = app == .custom ? ["com.mitchellh.ghostty", "net.kovidgoyal.kitty", "com.todesktop.230313mzl4w4u92", "x.y"] : [nil]
        for id in ids {
            let steps = SessionLaunchPlanner.plan(app: app, harness: harness, cliPath: "/bin/cli", sessionID: "s1",
                                                  cwd: "/w dir", appPath: "/Apps/X.app", bundleIdentifier: id)
            #expect(!steps.isEmpty)
            // Only resume forms, the folder, or a deep link carrying the session id.
            for step in steps {
                switch step {
                case let .runCommandFile(script, arguments):
                    #expect(script.contains("resume") && script.contains("'s1'") && arguments.last == "{script}")
                case let .exec(executable, arguments):
                    #expect(executable == "/usr/bin/open" ? arguments.last?.contains("'s1'") == true : arguments == ["/w dir"])
                case let .openURL(url, _):
                    #expect(url.hasSuffix("s1"))
                case let .runCLI(_, arguments, cwd):
                    #expect(arguments == ["-q", "/dev/null", "/bin/cli", "--desktop", "--resume", "s1"] && cwd == "/w dir")
                }
            }
        }
    }

    @Test("menu: Terminal, VS Code, then only the agent's own desktop app")
    func builtIn() {
        #expect(OpenInApp.builtIn(for: .claudeCode) == [.terminal, .vscode, .claudeApp])
        #expect(OpenInApp.builtIn(for: .codex) == [.terminal, .vscode, .codexApp])
        #expect(OpenInApp.claudeApp.supports(.claudeCode) && !OpenInApp.claudeApp.supports(.codex))
        #expect(OpenInApp.codexApp.supports(.codex) && !OpenInApp.codexApp.supports(.claudeCode))
    }

    @Test("migration of the old single setting")
    func migration() {
        #expect(OpenInApp.migrated(from: nil) == .builtIn(.terminal))
        #expect(OpenInApp.migrated(from: "terminal") == .builtIn(.terminal))
        #expect(OpenInApp.migrated(from: "vscode") == .builtIn(.vscode))
        #expect(OpenInApp.migrated(from: "ghostty") == .customApp(bundleIdentifier: "com.mitchellh.ghostty"))
        #expect(OpenInApp.migrated(from: "cursor") == .customApp(bundleIdentifier: "com.todesktop.230313mzl4w4u92"))
        #expect(OpenInApp.migrated(from: "nonsense") == .builtIn(.terminal))
    }

    @Test func onlyAppsThatCanOpenSessionsAreOffered() {
        // Known apps, whatever they declare.
        #expect(SessionLaunchPlanner.canOpenSessions(bundleIdentifier: "net.kovidgoyal.kitty", claimedExtensions: [], claimedTypes: []))
        #expect(SessionLaunchPlanner.canOpenSessions(bundleIdentifier: "com.todesktop.230313mzl4w4u92", claimedExtensions: [], claimedTypes: []))
        // Unknown terminals that run .command files.
        #expect(SessionLaunchPlanner.canOpenSessions(bundleIdentifier: "com.example.term", claimedExtensions: ["sh", "COMMAND"], claimedTypes: []))
        #expect(SessionLaunchPlanner.canOpenSessions(bundleIdentifier: "com.example.term", claimedExtensions: [], claimedTypes: ["com.apple.terminal.shell-script"]))
        // A menu bar utility, and an editor that only opens scripts as text.
        #expect(!SessionLaunchPlanner.canOpenSessions(bundleIdentifier: "com.example.utility", claimedExtensions: [], claimedTypes: []))
        #expect(!SessionLaunchPlanner.canOpenSessions(bundleIdentifier: "com.example.editor", claimedExtensions: ["sh", "txt"], claimedTypes: ["public.shell-script"]))
        #expect(!SessionLaunchPlanner.canOpenSessions(bundleIdentifier: nil, claimedExtensions: [], claimedTypes: []))
    }
}
