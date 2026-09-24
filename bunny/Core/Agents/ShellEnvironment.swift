import Foundation

/// The user's login-shell environment. A GUI app launched from Finder/Dock inherits a minimal
/// `PATH` (no Homebrew, no ~/.local/bin), so agent CLIs are located and launched with the PATH
/// an interactive login `zsh` would have.
///
/// Every member is `nonisolated` (the app target defaults to `@MainActor`) so the supervisor can
/// call these blocking lookups from a background queue; shared caches are lock-protected.
enum ShellEnvironment {
    // State is guarded by its lock, so it is safe to touch from the nonisolated functions below.
    nonisolated private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedPATH: String?
    nonisolated private static let locateLock = NSLock()
    nonisolated(unsafe) private static var locateCache: [String: String?] = [:]
    nonisolated private static let shellTimeout: TimeInterval = 3
    /// Marks the PATH line so rc-file chatter on stdout can't be mistaken for it.
    nonisolated private static let pathSentinel = "__BUNNY_PATH__"

    /// PATH from the user's login shell (`/bin/zsh -lic 'print -r -- $PATH'`), cached; falls back to ProcessInfo PATH + /opt/homebrew/bin:/usr/local/bin:~/.local/bin. 3 s timeout.
    nonisolated static func loginPATH() -> String {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedPATH { return cachedPATH }

        let path: String
        if let output = runLoginShell(script: "print -r -- \"\(pathSentinel)$PATH\"", arguments: []),
           let line = output.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix(pathSentinel) }),
           case let value = String(line.dropFirst(pathSentinel.count)).trimmingCharacters(in: .whitespaces),
           value.contains("/") {
            path = value
        } else {
            path = fallbackPATH()
        }
        cachedPATH = path
        return path
    }

    /// Absolute path of `name` via login shell `command -v`, or nil.
    /// Results (including misses) are cached per name; a cached path that is no longer executable is
    /// looked up again. Pass `refresh: true` to bypass the cache (e.g. a Settings "Detect" button).
    nonisolated static func locate(_ name: String, refresh: Bool = false) -> String? {
        guard !name.isEmpty else { return nil }
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }

        locateLock.lock()
        defer { locateLock.unlock() }
        if !refresh, let cached = locateCache[name] {
            guard let path = cached else { return nil }
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        let path = resolve(name)
        locateCache[name] = .some(path)
        return path
    }

    nonisolated private static func resolve(_ name: String) -> String? {
        let fileManager = FileManager.default

        // `$1` keeps the name out of the script text, so it cannot inject shell syntax.
        if let output = runLoginShell(script: "command -v -- \"$1\"", arguments: [name]),
           let line = lastNonEmptyLine(output),
           line.hasPrefix("/"),
           fileManager.isExecutableFile(atPath: line) {
            return line
        }

        // `command -v` prints alias/function definitions for non-files; fall back to scanning PATH.
        for directory in loginPATH().split(separator: ":") where !directory.isEmpty {
            let candidate = (String(directory) as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
               !isDirectory.boolValue,
               fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Claude Code's "local" install lives outside PATH unless the user aliased it.
        if name == "claude" {
            let local = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/local/claude").path
            if fileManager.isExecutableFile(atPath: local) {
                return local
            }
        }
        return nil
    }

    /// ProcessInfo env with PATH = loginPATH(), TERM=dumb, NO_COLOR=1.
    nonisolated static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = loginPATH()
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        return environment
    }

    // MARK: - Private

    nonisolated private static func fallbackPATH() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", (home as NSString).appendingPathComponent(".local/bin")]
        var seen = Set<String>()
        return (inherited + extras).filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }

    nonisolated private static func lastNonEmptyLine(_ output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }

    /// Runs `script` in an interactive login zsh (so .zprofile and .zshrc both apply) and returns
    /// its stdout, or nil on failure or after `shellTimeout`. Stdout goes to a temporary file so a
    /// chatty rc file or a lingering background job can never block us on a pipe.
    nonisolated private static func runLoginShell(script: String, arguments: [String]) -> String? {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("bunny-shell-\(UUID().uuidString).out")
        guard fileManager.createFile(atPath: outputURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return nil
        }
        defer {
            try? outputHandle.close()
            try? fileManager.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", script, "bunny"] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        process.environment = environment

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }

        if exited.wait(timeout: .now() + shellTimeout) == .timedOut {
            // Interactive shells ignore SIGTERM. Wait only briefly for the reap.
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 0.1)
            return nil
        }
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let data = try? Data(contentsOf: outputURL) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}
