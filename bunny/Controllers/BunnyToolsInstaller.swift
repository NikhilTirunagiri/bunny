import Foundation

/// Global "Bunny tools" MCP install/uninstall for the owner's Claude Code / Codex CLIs
/// (Settings → Agents → "Bunny tools"), independent of any live task. Commands match
/// `docs/superpowers/research/mcp-http.md` §4 (global install/uninstall) and its Codex
/// approval-mode note ("Codex approval — resolved").
@MainActor
enum BunnyToolsInstaller {
    enum Status: Equatable, Sendable {
        case notInstalled
        case installed
        case unavailable(String)
    }

    /// Plain `Error` (not `LocalizedError`): in the app target this type is implicitly `@MainActor`,
    /// which cannot satisfy `LocalizedError`'s nonisolated requirements (see `AgentProcessError`).
    enum InstallerError: Error, Equatable, Sendable {
        case cliMissing(String)
        case commandFailed(String)

        var message: String {
            switch self {
            case let .cliMissing(name): return "\(name) not found — set its path in Settings → Agents."
            case let .commandFailed(text): return text
            }
        }
    }

    private static let serverName = "bunny"
    /// Lets an unattended `never`-policy Codex session call Bunny tools with no per-call approval
    /// prompt (mcp-http.md, "Codex approval — resolved"). `codex mcp add` has no flag for this, so
    /// the installer patches `config.toml` directly, right after adding the server.
    nonisolated private static let codexApprovalKey = "default_tools_approval_mode"
    nonisolated private static let codexApprovalValue = "approve"

    // MARK: - Status

    /// Off-main; `completion` runs on main. `.unavailable` when the CLI path is unset or not
    /// executable (spec's Codex-unavailable fallback applies to install status the same way it
    /// applies to the model picker).
    static func status(for harness: AgentHarness, completion: @escaping @MainActor @Sendable (Status) -> Void) {
        guard let cliPath = executableCLIPath(for: harness) else {
            let message = InstallerError.cliMissing(AgentSettings.commandName(for: harness)).message
            completion(.unavailable(message))
            return
        }
        run(cliPath: cliPath, arguments: ["mcp", "get", serverName]) { exitCode, stdout, _ in
            completion(exitCode == 0 && stdout.localizedCaseInsensitiveContains(serverName) ? .installed : .notInstalled)
        }
    }

    // MARK: - Install

    static func install(for harness: AgentHarness, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        guard let cliPath = executableCLIPath(for: harness) else {
            completion(.failure(InstallerError.cliMissing(AgentSettings.commandName(for: harness))))
            return
        }
        let url = AgentSettings.toolsURL
        let token = AgentSettings.toolsToken

        switch harness {
        case .claudeCode:
            let arguments = [
                "mcp", "add", "--transport", "http", "--scope", "user", serverName, url,
                "--header", "Authorization: Bearer \(token)"
            ]
            run(cliPath: cliPath, arguments: arguments) { exitCode, stdout, stderr in
                completion(commandResult(exitCode: exitCode, stdout: stdout, stderr: stderr))
            }
        case .codex:
            let arguments = ["mcp", "add", serverName, "--url", url, "--bearer-token-env-var", "BUNNY_TOKEN"]
            installCodex(cliPath: cliPath, arguments: arguments, completion: completion)
        }
    }

    // MARK: - Uninstall

    static func uninstall(for harness: AgentHarness, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        guard let cliPath = executableCLIPath(for: harness) else {
            completion(.failure(InstallerError.cliMissing(AgentSettings.commandName(for: harness))))
            return
        }
        let arguments: [String]
        switch harness {
        case .claudeCode: arguments = ["mcp", "remove", serverName, "-s", "user"]
        case .codex: arguments = ["mcp", "remove", serverName]
        }
        run(cliPath: cliPath, arguments: arguments) { exitCode, stdout, stderr in
            completion(commandResult(exitCode: exitCode, stdout: stdout, stderr: stderr))
        }
    }

    // MARK: - Private

    private static func executableCLIPath(for harness: AgentHarness) -> String? {
        let path = AgentSettings.cliPath(for: harness)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    nonisolated private static func commandResult(exitCode: Int32, stdout: String, stderr: String) -> Result<Void, Error> {
        guard exitCode == 0 else {
            let text = [stderr, stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            return .failure(InstallerError.commandFailed(text ?? "Command failed (exit \(exitCode))"))
        }
        return .success(())
    }

    /// `codex mcp add`, then (only on success) patches `config.toml` with the approval-mode key.
    /// Both steps run off-main; `completion` runs on main.
    nonisolated private static func installCodex(
        cliPath: String,
        arguments: [String],
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let (exitCode, stdout, stderr) = runProcess(cliPath: cliPath, arguments: arguments)
            let finalResult: Result<Void, Error>
            switch commandResult(exitCode: exitCode, stdout: stdout, stderr: stderr) {
            case .success:
                do {
                    try setCodexApprovalMode()
                    finalResult = .success(())
                } catch {
                    finalResult = .failure(error)
                }
            case let .failure(error):
                finalResult = .failure(error)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(finalResult) }
            }
        }
    }

    /// Runs `cliPath arguments` off-main with the login-shell environment; `completion` runs on
    /// main with (exit code, stdout, stderr). A launch failure reports exit code -1.
    nonisolated private static func run(
        cliPath: String,
        arguments: [String],
        completion: @escaping @MainActor @Sendable (Int32, String, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let (exitCode, stdout, stderr) = runProcess(cliPath: cliPath, arguments: arguments)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(exitCode, stdout, stderr) }
            }
        }
    }

    /// Synchronous (blocks the calling thread until the child exits) — only ever called from a
    /// background queue by `run`/`installCodex`.
    nonisolated private static func runProcess(cliPath: String, arguments: [String]) -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        process.environment = ShellEnvironment.environment()
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self)
        )
    }

    /// Adds `default_tools_approval_mode = "approve"` under `[mcp_servers.bunny]` in Codex's
    /// `config.toml`, without disturbing anything else in the file. No-op if already set.
    nonisolated private static func setCodexApprovalMode() throws {
        let configURL = codexConfigURL()
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            throw InstallerError.commandFailed("Codex config not found at \(configURL.path)")
        }
        var lines = text.components(separatedBy: "\n")
        guard let sectionIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "[mcp_servers.bunny]"
        }) else {
            throw InstallerError.commandFailed("[mcp_servers.bunny] not found in Codex config")
        }
        var endIndex = lines.count
        for index in (sectionIndex + 1)..<lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                endIndex = index
                break
            }
        }
        let alreadySet = lines[(sectionIndex + 1)..<endIndex].contains {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(codexApprovalKey)
        }
        guard !alreadySet else { return }
        lines.insert("\(codexApprovalKey) = \"\(codexApprovalValue)\"", at: sectionIndex + 1)
        try lines.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)
    }

    nonisolated private static func codexConfigURL() -> URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath).appendingPathComponent("config.toml")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
    }
}
