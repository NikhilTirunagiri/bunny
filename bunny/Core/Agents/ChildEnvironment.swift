import Foundation

/// What Bunny takes out of the environment of every process it starts. Started from inside a Claude
/// Code session (as in development), Bunny inherits that session's own variables; passed on, they make
/// an agent or an opened session behave as that session's child (no transcript, no /resume).
/// Only these session markers go: settings a user exports on purpose (`CLAUDE_CODE_USE_BEDROCK`,
/// `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_*`, …) are kept.
/// Pure, Foundation-only.
enum ChildEnvironment {
    nonisolated static let removedNames = [
        "CLAUDECODE", "CLAUDE_PID", "CLAUDE_EFFORT",
        "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_SESSION_ATTENDED",
        "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_EXECPATH", "CLAUDE_CODE_SSE_PORT",
        "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN",
    ]

    nonisolated static func isRemoved(_ name: String) -> Bool {
        removedNames.contains(name)
    }

    nonisolated static func scrubbed(_ environment: [String: String]) -> [String: String] {
        environment.filter { !isRemoved($0.key) }
    }

    /// The same removal as a shell line, for a script that runs in a shell Bunny did not start.
    nonisolated static let shellUnset = "unset " + removedNames.joined(separator: " ")
}
