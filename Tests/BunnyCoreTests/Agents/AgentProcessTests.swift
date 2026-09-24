import Foundation
import Testing
@testable import BunnyCore

@MainActor
struct AgentProcessTests {
    private let env = ProcessInfo.processInfo.environment

    @Test func startThrowsForMissingExecutable() {
        let process = AgentProcess(executable: "/nonexistent/claude", arguments: [], cwd: NSTemporaryDirectory(), environment: env)
        #expect(throws: (any Error).self) { try process.start() }
        #expect(!process.isRunning)
        process.write(Data("ignored".utf8))   // no-op, no crash
        process.terminate()                   // no-op, no crash
    }

    @Test func startThrowsForNonExecutableFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("bunny-not-exec-\(UUID().uuidString)")
        try "echo hi\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        defer { try? FileManager.default.removeItem(at: file) }

        let process = AgentProcess(executable: file.path, arguments: [], cwd: NSTemporaryDirectory(), environment: env)
        #expect(throws: (any Error).self) { try process.start() }
    }

    @Test func startThrowsForMissingWorkingDirectory() {
        let process = AgentProcess(executable: "/bin/cat", arguments: [], cwd: "/nonexistent/dir", environment: env)
        #expect(throws: (any Error).self) { try process.start() }
    }

    @Test func deliversLinesThenExitWithStderrTail() async throws {
        let script = #"printf '{"a":1}\n\n{"b":2}\r\n'; printf 'oops' >&2; exit 5"#
        let process = AgentProcess(executable: "/bin/sh", arguments: ["-c", script], cwd: NSTemporaryDirectory(), environment: env)
        var lines: [String] = []
        var exit: (code: Int32, stderr: String)?
        var exitCount = 0
        process.onLine = { lines.append(String(decoding: $0, as: UTF8.self)) }
        process.onExit = { code, tail in
            exit = (code, tail)
            exitCount += 1
        }

        try process.start()

        #expect(await waitUntil { exit != nil })
        #expect(lines == [#"{"a":1}"#, #"{"b":2}"#])
        #expect(exit?.code == 5)
        #expect(exit?.stderr == "oops")
        #expect(!process.isRunning)
        // Give any late duplicate a chance to show up.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(exitCount == 1)
    }

    @Test func writeAppendsNewlineAndIsNoOpAfterExit() async throws {
        let process = AgentProcess(executable: "/bin/cat", arguments: [], cwd: NSTemporaryDirectory(), environment: env)
        var lines: [String] = []
        var exitCode: Int32?
        process.onLine = { lines.append(String(decoding: $0, as: UTF8.self)) }
        process.onExit = { code, _ in exitCode = code }

        try process.start()
        #expect(process.isRunning)
        process.write(Data(#"{"hello":"world"}"#.utf8))
        process.write(Data(#"{"n":2}"#.utf8))

        #expect(await waitUntil { lines.count == 2 })
        #expect(lines == [#"{"hello":"world"}"#, #"{"n":2}"#])

        process.terminate()
        #expect(await waitUntil { exitCode != nil })
        #expect(exitCode == SIGTERM)
        process.write(Data("after exit".utf8))   // no-op, no crash
    }

    @Test func terminateEscalatesToSIGKILL() async throws {
        // The child ignores SIGTERM, so only the SIGKILL fallback (after 3 s) ends it.
        let process = AgentProcess(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; exec sleep 30"], cwd: NSTemporaryDirectory(), environment: env)
        var exitCode: Int32?
        process.onExit = { code, _ in exitCode = code }
        try process.start()
        try await Task.sleep(nanoseconds: 200_000_000)

        let started = Date()
        process.terminate()
        #expect(await waitUntil(timeout: 8) { exitCode != nil })
        let elapsed = Date().timeIntervalSince(started)
        #expect(exitCode == SIGKILL)
        #expect(elapsed >= 2.5)
    }

    @Test func exitIsReportedEvenIfAGrandchildKeepsStdoutOpen() async throws {
        let process = AgentProcess(executable: "/bin/sh", arguments: ["-c", "echo '{\"x\":1}'; sleep 5 & exit 0"], cwd: NSTemporaryDirectory(), environment: env)
        var lines: [String] = []
        var exitCode: Int32?
        process.onLine = { lines.append(String(decoding: $0, as: UTF8.self)) }
        process.onExit = { code, _ in exitCode = code }
        try process.start()

        #expect(await waitUntil(timeout: 4) { exitCode != nil })
        #expect(exitCode == 0)
        #expect(lines == [#"{"x":1}"#])
    }
}

struct ShellEnvironmentTests {
    @Test func loginPATHContainsSystemDirectories() {
        let components = ShellEnvironment.loginPATH().split(separator: ":").map(String.init)
        #expect(components.contains("/usr/bin"))
        #expect(components.contains("/bin"))
    }

    @Test func locateFindsCommandsOnLoginPATH() {
        #expect(ShellEnvironment.locate("sh") == "/bin/sh")
        #expect(ShellEnvironment.locate("bunny-no-such-command-xyz") == nil)
        #expect(ShellEnvironment.locate("") == nil)
    }

    @Test func environmentOverridesPATHAndTerminal() {
        let environment = ShellEnvironment.environment()
        #expect(environment["PATH"] == ShellEnvironment.loginPATH())
        #expect(environment["TERM"] == "dumb")
        #expect(environment["NO_COLOR"] == "1")
        #expect(environment["HOME"] == ProcessInfo.processInfo.environment["HOME"])
    }
}
