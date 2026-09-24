import Foundation

/// Agent preferences, backed by `UserDefaults` (keys `agent.*`, shared with the Settings → Agents pane).
@MainActor
enum AgentSettings {
    private enum Key {
        static let defaultHarness = "agent.defaultHarness"
        static let claudePath = "agent.claudePath"
        static let codexPath = "agent.codexPath"
        static let autonomy = "agent.autonomy"
        static let openIn = "agent.openIn"
        static let defaultWorkspace = "agent.defaultWorkspace"
    }

    private static var defaults: UserDefaults { .standard }

    static var defaultHarness: AgentHarness {
        get { defaults.string(forKey: Key.defaultHarness).flatMap(AgentHarness.init(rawValue:)) ?? .claudeCode }
        set { defaults.set(newValue.rawValue, forKey: Key.defaultHarness) }
    }

    /// Stored path, else the CLI found on the login-shell PATH, else "".
    static var claudePath: String {
        get { storedPath(Key.claudePath) ?? located("claude") }
        set { defaults.set(newValue, forKey: Key.claudePath) }
    }

    static var codexPath: String {
        get { storedPath(Key.codexPath) ?? located("codex") }
        set { defaults.set(newValue, forKey: Key.codexPath) }
    }

    static var autonomy: AgentAutonomy {
        get { defaults.string(forKey: Key.autonomy).flatMap(AgentAutonomy.init(rawValue:)) ?? .autonomous }
        set { defaults.set(newValue.rawValue, forKey: Key.autonomy) }
    }

    static var openIn: OpenInApp {
        get { defaults.string(forKey: Key.openIn).flatMap(OpenInApp.init(rawValue:)) ?? .terminal }
        set { defaults.set(newValue.rawValue, forKey: Key.openIn) }
    }

    static var defaultWorkspace: String {
        get {
            let stored = defaults.string(forKey: Key.defaultWorkspace)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? NSHomeDirectory() : (stored as NSString).expandingTildeInPath
        }
        set { defaults.set(newValue, forKey: Key.defaultWorkspace) }
    }

    static func cliPath(for harness: AgentHarness) -> String {
        switch harness {
        case .claudeCode: return claudePath
        case .codex: return codexPath
        }
    }

    /// Terminal is always available; the others must be installed in /Applications.
    static func isInstalled(_ app: OpenInApp) -> Bool {
        guard let bundle = applicationBundlePath(app) else { return true }
        return FileManager.default.fileExists(atPath: bundle)
    }

    static func applicationBundlePath(_ app: OpenInApp) -> String? {
        switch app {
        case .terminal: return nil
        case .ghostty: return "/Applications/Ghostty.app"
        case .vscode: return "/Applications/Visual Studio Code.app"
        case .cursor: return "/Applications/Cursor.app"
        }
    }

    /// Resolves the login-shell PATH and the CLI locations on a background queue, so the first agent start
    /// (or the first Settings read) doesn't block the main thread on a cold login shell (up to 3 s each).
    static func warmUp() {
        let needsClaude = storedPath(Key.claudePath) == nil && locatedPaths["claude"] == nil
        let needsCodex = storedPath(Key.codexPath) == nil && locatedPaths["codex"] == nil
        DispatchQueue.global(qos: .utility).async {
            // ShellEnvironment is Foundation-only and thread-safe (lock-protected cache, per-call temp files).
            // In the app target it is implicitly @MainActor (default isolation), so Swift 5 mode warns here.
            _ = ShellEnvironment.loginPATH()
            let claude = needsClaude ? ShellEnvironment.locate("claude") : nil
            let codex = needsCodex ? ShellEnvironment.locate("codex") : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let claude, locatedPaths["claude"] == nil { locatedPaths["claude"] = claude }
                    if let codex, locatedPaths["codex"] == nil { locatedPaths["codex"] = codex }
                }
            }
        }
    }

    // MARK: - Private

    /// A non-empty stored path (an empty string means "not set": fall back to auto-detection).
    private static func storedPath(_ key: String) -> String? {
        let stored = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? nil : (stored as NSString).expandingTildeInPath
    }

    /// Successful lookups are cached for the process lifetime: `locate` runs a login shell (up to 3 s).
    /// Misses are not cached, so a CLI installed while Bunny runs is found on the next attempt.
    private static var locatedPaths: [String: String] = [:]

    private static func located(_ name: String) -> String {
        if let cached = locatedPaths[name] { return cached }
        guard let path = ShellEnvironment.locate(name) else { return "" }
        locatedPaths[name] = path
        return path
    }
}
