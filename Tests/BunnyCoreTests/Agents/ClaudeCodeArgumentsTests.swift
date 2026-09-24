import Foundation
import Testing
@testable import BunnyCore

@MainActor
struct ClaudeCodeArgumentsTests {
    private let taskID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private var tools: BunnyToolsEndpoint {
        BunnyToolsEndpoint(url: "http://127.0.0.1:47823/mcp", token: "secret-token", taskID: taskID)
    }

    @Test func argvWithoutModelEffortOrToolsIsUnchanged() {
        let argv = ClaudeCodeRunner.arguments(brief: makeBrief(title: "X"), harness: .claudeCode, autonomy: .autonomous, resumeSessionID: nil)
        let expected = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--permission-prompt-tool", "stdio", "--permission-mode", "bypassPermissions",
            "--append-system-prompt", AgentPromptBuilder.systemAppendix(for: .claudeCode),
        ]
        #expect(argv == expected)
    }

    @Test func blankModelAndEffortAreOmitted() {
        let argv = ClaudeCodeRunner.arguments(
            brief: makeBrief(title: "X"), harness: .claudeCode, autonomy: .autonomous, resumeSessionID: nil,
            model: "  ", effort: ""
        )
        #expect(!argv.contains("--model"))
        #expect(!argv.contains("--effort"))
    }

    @Test func argvWithModelEffortAndTools() throws {
        let argv = ClaudeCodeRunner.arguments(
            brief: makeBrief(title: "X", extraDirectories: ["/tmp/a", "/tmp/b"]),
            harness: .claudeCode,
            autonomy: .askFirst,
            resumeSessionID: "sess-9",
            model: "opus",
            effort: "xhigh",
            tools: tools
        )
        let expected = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--permission-prompt-tool", "stdio", "--permission-mode", "acceptEdits",
            "--model", "opus",
            "--effort", "xhigh",
            "--mcp-config", ClaudeCodeRunner.mcpConfigJSON(for: tools),
            "--allowedTools", "mcp__bunny",
            "--append-system-prompt", AgentPromptBuilder.systemAppendix(for: .claudeCode, toolsAvailable: true),
            "--add-dir", "/tmp/a",
            "--add-dir", "/tmp/b",
            "--resume", "sess-9",
        ]
        #expect(argv == expected)
    }

    @Test func mcpConfigJSONMatchesVerifiedShape() throws {
        let json = ClaudeCodeRunner.mcpConfigJSON(for: tools)
        let decoded = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
        let expected: NSDictionary = [
            "mcpServers": [
                "bunny": [
                    "type": "http",
                    "url": "http://127.0.0.1:47823/mcp",
                    "headers": [
                        "Authorization": "Bearer secret-token",
                        "X-Bunny-Task": "11111111-2222-3333-4444-555555555555",
                    ],
                ],
            ],
        ]
        #expect(decoded == expected)
    }

    @Test func mcpConfigJSONWithoutTaskOmitsTaskHeader() throws {
        let endpoint = BunnyToolsEndpoint(url: "http://127.0.0.1:1/mcp", token: "t", taskID: nil)
        let json = ClaudeCodeRunner.mcpConfigJSON(for: endpoint)
        let decoded = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let servers = try #require(decoded["mcpServers"] as? [String: Any])
        let bunny = try #require(servers["bunny"] as? [String: Any])
        #expect(bunny["headers"] as? [String: String] == ["Authorization": "Bearer t"])
    }

    /// `--allowedTools`, `--mcp-config` and `--add-dir` are variadic in Claude Code: a bare argument after
    /// their values is swallowed. Parse argv like commander does and check every value lands where intended.
    @Test func variadicFlagsNeverSwallowOtherArguments() throws {
        let argv = ClaudeCodeRunner.arguments(
            brief: makeBrief(title: "X", extraDirectories: ["/tmp/a b"]),
            harness: .claudeCode,
            autonomy: .autonomous,
            resumeSessionID: "sess-9",
            model: "haiku",
            effort: "low",
            tools: tools
        )
        let parsed = try #require(Self.commanderParse(argv))
        #expect(parsed.positionals.isEmpty)
        #expect(parsed.options["--allowedTools"] == [["mcp__bunny"]])
        #expect(parsed.options["--mcp-config"] == [[ClaudeCodeRunner.mcpConfigJSON(for: tools)]])
        #expect(parsed.options["--add-dir"] == [["/tmp/a b"]])
        #expect(parsed.options["--resume"] == [["sess-9"]])
        #expect(parsed.options["--model"] == [["haiku"]])
        #expect(parsed.options["--effort"] == [["low"]])
        #expect(parsed.options["--append-system-prompt"] == [[AgentPromptBuilder.systemAppendix(for: .claudeCode, toolsAvailable: true)]])
        // Every variadic flag's single value is followed by another flag or the end of argv.
        for (index, flag) in argv.enumerated() where ClaudeCodeRunner.variadicFlags.contains(flag) {
            let next = index + 2 < argv.count ? argv[index + 2] : "--"
            #expect(next.hasPrefix("--"), "\(flag) is followed by \(next)")
        }
    }

    @Test func runnerPassesModelEffortAndToolsToCLI() async throws {
        var options = FakeCLI.options(cliPath: FakeCLI.claude)
        options.model = "sonnet"
        options.effort = "max"
        options.tools = tools
        let runner = ClaudeCodeRunner(options: options)
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "Args"), harness: .claudeCode, resumeSessionID: nil, initialMessage: nil)

        #expect(await recorder.waitForTurnFinished())
        let text = try #require(recorder.events.turnsFinished.first?.text)
        let argvJSON = try #require(text.components(separatedBy: " | argv=").last)
        let argv = try #require(JSONSerialization.jsonObject(with: Data(argvJSON.utf8)) as? [String])
        let expected = ClaudeCodeRunner.arguments(
            brief: makeBrief(title: "Args"), harness: .claudeCode, autonomy: .autonomous, resumeSessionID: nil,
            model: "sonnet", effort: "max", tools: tools
        )
        #expect(argv == expected)
    }

    // MARK: - commander-style parsing

    private static let booleanFlags: Set<String> = ["-p", "--verbose"]
    private static let valueFlags: Set<String> = [
        "--input-format", "--output-format", "--permission-prompt-tool", "--permission-mode",
        "--append-system-prompt", "--resume", "--model", "--effort",
    ]

    /// Mimics commander: a value flag takes the next token; a variadic flag takes tokens up to the next one
    /// starting with "-". Returns nil for an unknown flag or a flag missing its value.
    private static func commanderParse(_ argv: [String]) -> (options: [String: [[String]]], positionals: [String])? {
        var options: [String: [[String]]] = [:]
        var positionals: [String] = []
        var index = 0
        while index < argv.count {
            let token = argv[index]
            if booleanFlags.contains(token) {
                index += 1
            } else if valueFlags.contains(token) {
                guard index + 1 < argv.count else { return nil }
                options[token, default: []].append([argv[index + 1]])
                index += 2
            } else if ClaudeCodeRunner.variadicFlags.contains(token) {
                var values: [String] = []
                index += 1
                while index < argv.count, !argv[index].hasPrefix("-") {
                    values.append(argv[index])
                    index += 1
                }
                guard !values.isEmpty else { return nil }
                options[token, default: []].append(values)
            } else if token.hasPrefix("-") {
                return nil
            } else {
                positionals.append(token)
                index += 1
            }
        }
        return (options, positionals)
    }
}
