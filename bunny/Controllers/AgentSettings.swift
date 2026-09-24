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

    /// The stored path only ("" = not set). Getters never auto-detect: detection runs a login shell,
    /// so it happens off the main thread in `warmUp()` / `detect(_:completion:)`, which store what they find.
    static var claudePath: String {
        get { storedPath(Key.claudePath) }
        set { defaults.set(newValue, forKey: Key.claudePath) }
    }

    static var codexPath: String {
        get { storedPath(Key.codexPath) }
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

    static func setCLIPath(_ path: String, for harness: AgentHarness) {
        switch harness {
        case .claudeCode: claudePath = path
        case .codex: codexPath = path
        }
    }

    static func commandName(for harness: AgentHarness) -> String {
        switch harness {
        case .claudeCode: return "claude"
        case .codex: return "codex"
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

    /// At launch: warms the login-shell PATH on a background queue and stores the location of each CLI
    /// whose path isn't set yet. Never overwrites a path the owner set.
    static func warmUp() {
        let missing = AgentHarness.allCases.filter { cliPath(for: $0).isEmpty }
        let names = missing.map { ($0, commandName(for: $0)) }
        DispatchQueue.global(qos: .utility).async {
            _ = ShellEnvironment.loginPATH()
            let found = names.compactMap { harness, name in ShellEnvironment.locate(name).map { (harness, $0) } }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for (harness, path) in found where cliPath(for: harness).isEmpty {
                        setCLIPath(path, for: harness)
                    }
                }
            }
        }
    }

    /// Explicit detection (Settings/Onboarding "Detect", or a start with no path set): locates the CLI on a
    /// background queue with a fresh lookup, stores the path when found, then calls `completion` on main.
    static func detect(_ harness: AgentHarness, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        let name = commandName(for: harness)
        DispatchQueue.global(qos: .userInitiated).async {
            let path = ShellEnvironment.locate(name, refresh: true)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let path {
                        setCLIPath(path, for: harness)
                    }
                    completion(path)
                }
            }
        }
    }

    // MARK: - Private

    /// The trimmed, tilde-expanded stored path, or "".
    private static func storedPath(_ key: String) -> String {
        let stored = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? "" : (stored as NSString).expandingTildeInPath
    }
}
