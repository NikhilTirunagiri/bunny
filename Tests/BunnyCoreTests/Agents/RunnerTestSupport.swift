import Foundation
@testable import BunnyCore

/// Locates the python fake CLIs next to the tests and makes sure they are executable.
enum FakeCLI {
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Agents
            .deletingLastPathComponent()   // BunnyCoreTests
            .appendingPathComponent("FakeCLIs", isDirectory: true)
    }

    static var claude: String { prepared("fake_claude.py") }
    static var codex: String { prepared("fake_codex.py") }

    private static func prepared(_ name: String) -> String {
        let path = directory.appendingPathComponent(name).path
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    static func options(cliPath: String, autonomy: AgentAutonomy = .autonomous) -> AgentRunOptions {
        AgentRunOptions(cliPath: cliPath, autonomy: autonomy, environment: ProcessInfo.processInfo.environment)
    }
}

func makeBrief(title: String, extraDirectories: [String] = []) -> AgentBrief {
    AgentBrief(
        title: title,
        description: "",
        subtasks: [],
        shelf: [],
        deadline: nil,
        workingDirectory: NSTemporaryDirectory(),
        extraDirectories: extraDirectories
    )
}

/// Polls on the main actor (letting DispatchQueue.main callbacks run in between) until `condition` holds or the timeout passes.
@MainActor
func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() >= deadline { return false }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return true
}

/// Records every `AgentEvent` a runner delivers (on the main queue).
@MainActor
final class EventRecorder {
    private(set) var events: [AgentEvent] = []

    init(_ runner: AgentRunner) {
        runner.onEvent = { [weak self] event in
            self?.events.append(event)
        }
    }

    /// Waits until `predicate(events)` holds or 10 s pass.
    func wait(timeout: TimeInterval = 10, for predicate: @escaping ([AgentEvent]) -> Bool) async -> Bool {
        await waitUntil(timeout: timeout) { predicate(self.events) }
    }

    func waitForTurnFinished(count: Int = 1, timeout: TimeInterval = 10) async -> Bool {
        await wait(timeout: timeout) { $0.turnsFinished.count >= count }
    }
}

extension Array where Element == AgentEvent {
    var sessionIDs: [String] {
        compactMap { if case let .sessionStarted(id) = $0 { return id } else { return nil } }
    }

    var activities: [String] {
        compactMap { if case let .activity(text) = $0 { return text } else { return nil } }
    }

    var questions: [AgentQuestion] {
        compactMap { if case let .question(question) = $0 { return question } else { return nil } }
    }

    var turnsFinished: [(text: String, success: Bool)] {
        compactMap { if case let .turnFinished(text, success) = $0 { return (text, success) } else { return nil } }
    }

    var failures: [String] {
        compactMap { if case let .failed(message) = $0 { return message } else { return nil } }
    }

    var exitCodes: [Int32] {
        compactMap { if case let .exited(code) = $0 { return code } else { return nil } }
    }
}
