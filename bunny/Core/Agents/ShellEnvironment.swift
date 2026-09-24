import Foundation

/// The user's login-shell environment. A GUI app launched from Finder/Dock inherits a minimal
/// `PATH` (no Homebrew, no ~/.local/bin), so agent CLIs are located and launched with the PATH
/// an interactive login `zsh` would have.
enum ShellEnvironment {
    private static let cacheLock = NSLock()
    private static var cachedPATH: String?
    private static let shellTimeout: TimeInterval = 3

    /// PATH from the user's login shell (`/bin/zsh -lic 'print -r -- $PATH'`), cached; falls back to ProcessInfo PATH + /opt/homebrew/bin:/usr/local/bin:~/.local/bin. 3 s timeout.
    static func loginPATH() -> String {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedPATH { return cachedPATH }

        let path: String
        if let output = runLoginShell(script: "print -r -- $PATH", arguments: []),
           let line = lastNonEmptyLine(output), line.contains("/") {
            path = line
        } else {
            path = fallbackPATH()
        }
        cachedPATH = path
        return path
    }

    /// Absolute path of `name` via login shell `command -v`, or nil.
    static func locate(_ name: String) -> String? {
        guard !name.isEmpty else { return nil }
        let fileManager = FileManager.default
        if name.contains("/") {
            return fileManager.isExecutableFile(atPath: name) ? name : nil
        }

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
        return nil
    }

    /// ProcessInfo env with PATH = loginPATH(), TERM=dumb, NO_COLOR=1.
    static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = loginPATH()
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        return environment
    }

    // MARK: - Private

    private static func fallbackPATH() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", (home as NSString).appendingPathComponent(".local/bin")]
        var seen = Set<String>()
        return (inherited + extras).filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }

    private static func lastNonEmptyLine(_ output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }

    /// Runs `script` in an interactive login zsh (so .zprofile and .zshrc both apply) and returns
    /// its stdout, or nil on failure or after `shellTimeout`. Stdout goes to a temporary file so a
    /// chatty rc file or a lingering background job can never block us on a pipe.
    private static func runLoginShell(script: String, arguments: [String]) -> String? {
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
            // Interactive shells ignore SIGTERM.
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 1)
            return nil
        }
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let data = try? Data(contentsOf: outputURL) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}
