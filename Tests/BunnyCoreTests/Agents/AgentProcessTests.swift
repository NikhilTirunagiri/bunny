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

    @Test func exitIsReportedAndGrandchildKilledIfItKeepsStdoutOpen() async throws {
        let pidFile = temporaryPath("grandchild-pid")
        defer { try? FileManager.default.removeItem(atPath: pidFile) }
        // The background sleep inherits stdout, so EOF never comes on its own.
        let script = "echo '{\"x\":1}'; sleep 60 & echo $! > '\(pidFile)'; exit 0"
        let process = AgentProcess(executable: "/bin/sh", arguments: ["-c", script], cwd: NSTemporaryDirectory(), environment: env)
        var lines: [String] = []
        var exitCode: Int32?
        process.onLine = { lines.append(String(decoding: $0, as: UTF8.self)) }
        process.onExit = { code, _ in exitCode = code }
        try process.start()

        #expect(await waitUntil(timeout: 4) { exitCode != nil })
        #expect(exitCode == 0)
        #expect(lines == [#"{"x":1}"#])
        let grandchild = try #require(readPID(pidFile))
        #expect(await waitUntil(timeout: 4) { !isAlive(grandchild) })
    }

    @Test func childIsItsOwnProcessGroupLeader() async throws {
        let marker = "sleep 29.\(Int.random(in: 100_000...999_999))"   // unique, so ps finds exactly this child
        let process = AgentProcess(executable: "/bin/sh", arguments: ["-c", "exec \(marker)"], cwd: NSTemporaryDirectory(), environment: env)
        var exitCode: Int32?
        process.onExit = { code, _ in exitCode = code }
        try process.start()
        defer { process.terminate() }
        // Find the child via its group: pgid == pid is what makes group signalling reach grandchildren.
        var found: PSEntry?
        _ = await waitUntil { found = (try? runPS())?.first { $0.command == marker }; return found != nil }
        let entry = try #require(found)
        #expect(entry.pid == entry.pgid)
        process.terminate()
        #expect(await waitUntil { exitCode != nil })
    }

    @Test func terminateKillsBackgroundGrandchildren() async throws {
        let pidFile = temporaryPath("bg-pid")
        defer { try? FileManager.default.removeItem(atPath: pidFile) }
        // The grandchild's output goes elsewhere, so only group signalling can reach it.
        let script = "sleep 60 >/dev/null 2>&1 & echo $! > '\(pidFile)'; wait"
        let process = AgentProcess(executable: "/bin/sh", arguments: ["-c", script], cwd: NSTemporaryDirectory(), environment: env)
        var exitCode: Int32?
        process.onExit = { code, _ in exitCode = code }
        try process.start()

        #expect(await waitUntil { readPID(pidFile) != nil })
        let grandchild = try #require(readPID(pidFile))
        #expect(isAlive(grandchild))

        process.terminate()
        #expect(await waitUntil(timeout: 4) { exitCode != nil && !isAlive(grandchild) })
        #expect(!isAlive(grandchild))
    }

    @Test func terminateKillsGrandchildrenThatIgnoreSIGTERM() async throws {
        let pidFile = temporaryPath("stubborn-pid")
        defer { try? FileManager.default.removeItem(atPath: pidFile) }
        // The leader exits on SIGTERM; the detached grandchild ignores it, so only the 3 s group SIGKILL ends it.
        let script = "(trap '' TERM; exec sleep 60) >/dev/null 2>&1 & echo $! > '\(pidFile)'; wait"
        let process = AgentProcess(executable: "/bin/sh", arguments: ["-c", script], cwd: NSTemporaryDirectory(), environment: env)
        try process.start()

        #expect(await waitUntil { readPID(pidFile) != nil })
        let grandchild = try #require(readPID(pidFile))
        try await Task.sleep(nanoseconds: 100_000_000)

        process.terminate()
        #expect(await waitUntil(timeout: 5) { !isAlive(grandchild) })
    }

    @Test func deliversFinalUnterminatedLineAtEOF() async throws {
        let process = AgentProcess(executable: "/bin/sh", arguments: ["-c", #"printf '{"a":1}\n{"last":true}'"#], cwd: NSTemporaryDirectory(), environment: env)
        var lines: [String] = []
        var exitCode: Int32?
        process.onLine = { lines.append(String(decoding: $0, as: UTF8.self)) }
        process.onExit = { code, _ in exitCode = code }
        try process.start()

        #expect(await waitUntil { exitCode != nil })
        #expect(lines == [#"{"a":1}"#, #"{"last":true}"#])
    }
}

private func temporaryPath(_ name: String) -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("bunny-\(name)-\(UUID().uuidString)").path
}

private func readPID(_ path: String) -> pid_t? {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
}

/// True while `pid` exists and isn't a zombie.
private func isAlive(_ pid: pid_t) -> Bool {
    guard kill(pid, 0) == 0 else { return false }
    let state = (try? runPS().first { $0.pid == pid }?.state) ?? nil
    return state.map { !$0.hasPrefix("Z") } ?? false
}

private struct PSEntry {
    var pid: pid_t
    var pgid: pid_t
    var state: String
    var command: String
}

private func runPS() throws -> [PSEntry] {
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-axo", "pid=,pgid=,state=,command="]
    let pipe = Pipe()
    ps.standardOutput = pipe
    try ps.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    ps.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
        // Columns are space-padded; maxSplits would count the padding, so split fully and rejoin the command.
        let parts = line.split(separator: " ")
        guard parts.count >= 4, let pid = pid_t(parts[0]), let pgid = pid_t(parts[1]) else { return nil }
        return PSEntry(pid: pid, pgid: pgid, state: String(parts[2]), command: parts[3...].joined(separator: " "))
    }
}
