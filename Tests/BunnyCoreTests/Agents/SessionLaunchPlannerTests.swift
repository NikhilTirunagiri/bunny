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
        #expect(steps == [.runCommandFile(script: "#!/bin/zsh -l\ncd '/w' && exec '/x' resume -m 'm' -c 'model_reasoning_effort=\"high\"' 'id2'\n")])
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
        let expectedScript = "#!/bin/zsh -l\n\(expectedCommand)\n"
        let expected: [LaunchStep] = [.runCommandFile(script: expectedScript)]

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
        let expectedScript = "#!/bin/zsh -l\n\(expectedCommand)\n"
        let expected: [LaunchStep] = [.runCommandFile(script: expectedScript)]

        #expect(result == expected)
    }

    @Test("plan: ghostty + claudeCode")
    func plan_ghostty_claudeCode() {
        let result = SessionLaunchPlanner.plan(
            app: .ghostty,
            harness: .claudeCode,
            cliPath: "/usr/local/bin/claude",
            sessionID: "abc123",
            cwd: "/tmp/project"
        )

        let command = "cd '/tmp/project' && exec '/usr/local/bin/claude' --resume 'abc123'"
        let expected: [LaunchStep] = [
            .exec(
                executable: "/usr/bin/open",
                arguments: ["-na", "/Applications/Ghostty.app", "--args", "--working-directory=/tmp/project", "-e", "/bin/zsh", "-lc", command]
            )
        ]

        #expect(result == expected)
    }

    @Test("plan: ghostty + codex")
    func plan_ghostty_codex() {
        let result = SessionLaunchPlanner.plan(
            app: .ghostty,
            harness: .codex,
            cliPath: "/usr/local/bin/codex",
            sessionID: "xyz789",
            cwd: "/home/user/work"
        )

        let command = "cd '/home/user/work' && exec '/usr/local/bin/codex' resume 'xyz789'"
        let expected: [LaunchStep] = [
            .exec(
                executable: "/usr/bin/open",
                arguments: ["-na", "/Applications/Ghostty.app", "--args", "--working-directory=/home/user/work", "-e", "/bin/zsh", "-lc", command]
            )
        ]

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

        let script = "#!/bin/zsh -l\ncd '/home/user/work' && exec '/usr/local/bin/codex' resume 'xyz789'\n"
        let expected: [LaunchStep] = [
            .exec(executable: "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code", arguments: ["/home/user/work"]),
            .runCommandFile(script: script)
        ]

        #expect(result == expected)
    }

    @Test("plan: cursor + claudeCode")
    func plan_cursor_claudeCode() {
        let result = SessionLaunchPlanner.plan(
            app: .cursor,
            harness: .claudeCode,
            cliPath: "/usr/local/bin/claude",
            sessionID: "abc123",
            cwd: "/tmp/project"
        )

        let urlString = "cursor://anthropic.claude-code/open?session=abc123"
        let expected: [LaunchStep] = [
            .exec(executable: "/Applications/Cursor.app/Contents/Resources/app/bin/cursor", arguments: ["/tmp/project"]),
            .openURL(urlString, delay: 1.0)
        ]

        #expect(result == expected)
    }

    @Test("plan: cursor + codex")
    func plan_cursor_codex() {
        let result = SessionLaunchPlanner.plan(
            app: .cursor,
            harness: .codex,
            cliPath: "/usr/local/bin/codex",
            sessionID: "xyz789",
            cwd: "/home/user/work"
        )

        let script = "#!/bin/zsh -l\ncd '/home/user/work' && exec '/usr/local/bin/codex' resume 'xyz789'\n"
        let expected: [LaunchStep] = [
            .exec(executable: "/Applications/Cursor.app/Contents/Resources/app/bin/cursor", arguments: ["/home/user/work"]),
            .runCommandFile(script: script)
        ]

        #expect(result == expected)
    }
}
