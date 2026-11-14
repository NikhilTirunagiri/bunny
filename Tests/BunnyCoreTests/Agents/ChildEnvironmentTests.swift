import Testing
import Foundation
@testable import BunnyCore

struct ChildEnvironmentTests {
    private let session = [
        "CLAUDECODE": "1", "CLAUDE_PID": "42", "CLAUDE_EFFORT": "high",
        "CLAUDE_CODE_CHILD_SESSION": "1", "CLAUDE_CODE_SESSION_ID": "abc", "CLAUDE_CODE_ENTRYPOINT": "cli",
        "CLAUDE_CODE_SSE_PORT": "1234", "CLAUDE_CODE_MESSAGING_SOCKET": "/tmp/s", "CLAUDE_CODE_MESSAGING_TOKEN": "t",
        "CLAUDE_CODE_EXECPATH": "/x", "CLAUDE_CODE_SESSION_ATTENDED": "1",
    ]
    private let kept = [
        "PATH": "/usr/bin:/bin", "HOME": "/Users/sample", "ANTHROPIC_API_KEY": "k", "ANTHROPIC_BASE_URL": "u",
        "CLAUDE_CONFIG_DIR": "/c", "OPENAI_API_KEY": "o", "CODEX_HOME": "/h", "CLAUDE": "x", "MY_CLAUDECODE": "y",
        "CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDE_CODE_OAUTH_TOKEN": "t",
    ]

    @Test func removesTheSessionVariablesOnly() {
        #expect(ChildEnvironment.scrubbed(session.merging(kept) { a, _ in a }) == kept)
        #expect(ChildEnvironment.scrubbed([:]) == [:])
    }

    @Test func commandScriptUnsetsBeforeTheCommand() {
        let script = SessionLaunchPlanner.commandScript("exec true")
        #expect(script == "#!/bin/zsh -l\n\(ChildEnvironment.shellUnset)\nexec true\n")
        #expect(ChildEnvironment.shellUnset.hasPrefix("unset CLAUDECODE CLAUDE_PID CLAUDE_EFFORT "))
    }

    /// The shell lines remove what `scrubbed` removes, in a real zsh.
    @Test func shellLinesMatchScrubbed() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", ChildEnvironment.shellUnset + "\nenv"]
        process.environment = session.merging(kept) { a, _ in a }
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let names = Set(output.split(separator: "\n").compactMap { $0.split(separator: "=").first.map(String.init) })
        #expect(names.isDisjoint(with: session.keys))
        #expect(names.isSuperset(of: kept.keys))
    }
}
