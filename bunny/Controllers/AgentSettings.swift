import AppKit
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
        static let claudeModel = "agent.claude.model"
        static let claudeEffort = "agent.claude.effort"
        static let codexModel = "agent.codex.model"
        static let codexEffort = "agent.codex.effort"
        static let toolsToken = "bunnyTools.token"
        static let toolsPort = "bunnyTools.port"
        static let claudeEnabled = "agent.claude.enabled"
        static let codexEnabled = "agent.codex.enabled"
        static let toolsEnabled = "bunnyTools.enabled"
        static let recentFolders = "agent.recentFolders"
        static let lastClaudeModel = "agent.claude.lastDefaultModel"
    }

    static let defaultToolsPort = 47823

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
        get { defaults.string(forKey: Key.autonomy).flatMap(AgentAutonomy.init(rawValue:)) ?? .askFirst }
        set { defaults.set(newValue.rawValue, forKey: Key.autonomy) }
    }

    // MARK: - Open sessions in (per agent)

    /// An app picked with "Other App…": its bundle path and the name the menu shows.
    struct CustomApp: Equatable {
        var path: String
        var name: String

        init(path: String, name: String) {
            self.path = path
            self.name = name
        }

        init(url: URL) {
            let name = FileManager.default.displayName(atPath: url.path)
            self.init(path: url.path, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
        }
    }

    /// Where an open session can go, resolved against this Mac.
    struct OpenTarget: Equatable {
        var app: OpenInApp
        /// "Terminal", "VS Code", "Claude app", or the custom app's own name.
        var name: String
        /// The app's bundle; nil = not installed (or, for a custom app, no longer there).
        var appPath: String?
        var bundleIdentifier: String?
    }

    private static func openInKey(_ harness: AgentHarness) -> String {
        Key.openIn + (harness == .claudeCode ? ".claude" : ".codex")
    }

    /// The stored choice for `harness` (Terminal when unset, or when it is the other agent's desktop app).
    static func openIn(for harness: AgentHarness) -> OpenInApp {
        let stored = defaults.string(forKey: openInKey(harness)).flatMap(OpenInApp.init(rawValue:)) ?? .terminal
        return stored.supports(harness) && (stored != .custom || customApp(for: harness) != nil) ? stored : .terminal
    }

    static func setOpenIn(_ app: OpenInApp, for harness: AgentHarness) {
        defaults.set(app.rawValue, forKey: openInKey(harness))
    }

    /// The one remembered "Other App…" pick of `harness` (kept while another target is selected).
    /// nil too for a stored app that cannot open sessions (saved before the picker filtered apps):
    /// it is not offered, and the target reads as Terminal. An app that is gone is kept: it may return.
    static func customApp(for harness: AgentHarness) -> CustomApp? {
        let path = trimmedString(openInKey(harness) + ".customPath")
        guard !path.isEmpty else { return nil }
        if FileManager.default.fileExists(atPath: path), !canOpenSessions(URL(fileURLWithPath: path)) { return nil }
        let name = trimmedString(openInKey(harness) + ".customName")
        return CustomApp(path: path, name: name.isEmpty ? CustomApp(url: URL(fileURLWithPath: path)).name : name)
    }

    /// Whether the app at `url` can open an agent session (`SessionLaunchPlanner.canOpenSessions`):
    /// the rule of the "Other App…" picker, and of a stored pick when it is read.
    static func canOpenSessions(_ url: URL) -> Bool {
        guard let bundle = Bundle(url: url) else { return false }
        let documentTypes = bundle.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        return SessionLaunchPlanner.canOpenSessions(
            bundleIdentifier: bundle.bundleIdentifier,
            claimedExtensions: documentTypes.flatMap { $0["CFBundleTypeExtensions"] as? [String] ?? [] },
            claimedTypes: documentTypes.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
    }

    static func setCustomApp(_ app: CustomApp, for harness: AgentHarness) {
        defaults.set(app.path, forKey: openInKey(harness) + ".customPath")
        defaults.set(app.name, forKey: openInKey(harness) + ".customName")
    }

    /// Once: the old single "Open sessions in" becomes both agents' choice. Ghostty and Cursor, no
    /// longer built in, become the custom app when installed (else Terminal). Nothing is written when
    /// the old value was never set: an unset choice already reads as Terminal.
    static func migrateOpenIn() {
        guard let old = defaults.string(forKey: Key.openIn) else { return }
        for harness in AgentHarness.allCases where defaults.object(forKey: openInKey(harness)) == nil {
            switch OpenInApp.migrated(from: old) {
            case let .builtIn(app):
                setOpenIn(app, for: harness)
            case let .customApp(bundleIdentifier):
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                    setCustomApp(CustomApp(url: url), for: harness)
                    setOpenIn(.custom, for: harness)
                } else {
                    setOpenIn(.terminal, for: harness)
                }
            }
        }
    }

    /// `app` as a target for `harness`, with where it is on this Mac (`appPath` nil = not there).
    static func openTarget(_ app: OpenInApp, for harness: AgentHarness) -> OpenTarget {
        if app == .custom {
            guard let custom = customApp(for: harness) else {
                return OpenTarget(app: .custom, name: app.displayName, appPath: nil, bundleIdentifier: nil)
            }
            let exists = FileManager.default.fileExists(atPath: custom.path)
            return OpenTarget(app: .custom, name: custom.name, appPath: exists ? custom.path : nil,
                              bundleIdentifier: exists ? Bundle(path: custom.path)?.bundleIdentifier : nil)
        }
        var url = app.bundleIdentifier.flatMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:))
        if url == nil, app == .codexApp, let link = URL(string: "codex://threads/new") {
            // Whatever handles the Codex deep link is the Codex app.
            url = NSWorkspace.shared.urlForApplication(toOpen: link)
        }
        return OpenTarget(app: app, name: app.displayName, appPath: url?.path, bundleIdentifier: app.bundleIdentifier)
    }

    /// The stored choice of `harness`, resolved.
    static func openTarget(for harness: AgentHarness) -> OpenTarget {
        openTarget(openIn(for: harness), for: harness)
    }

    /// Terminal is always available; the others must be found on this Mac.
    static func isInstalled(_ app: OpenInApp, for harness: AgentHarness) -> Bool {
        app == .terminal || openTarget(app, for: harness).appPath != nil
    }

    /// The name on the open-session controls: the chosen target, or Terminal when it isn't there.
    static func openInName(for harness: AgentHarness) -> String {
        let target = openTarget(for: harness)
        return target.app == .terminal || target.appPath != nil ? target.name : OpenInApp.terminal.displayName
    }

    // MARK: - On/off switches (v3 spec §7 "Enable")

    /// Whether the switches were ever written (`AgentEnablement.migrateIfNeeded` writes them once).
    static var enablementIsStored: Bool { defaults.object(forKey: Key.claudeEnabled) != nil }

    static func isEnabled(_ harness: AgentHarness) -> Bool {
        defaults.bool(forKey: harness == .claudeCode ? Key.claudeEnabled : Key.codexEnabled)
    }

    static func setEnabled(_ enabled: Bool, for harness: AgentHarness) {
        defaults.set(enabled, forKey: harness == .claudeCode ? Key.claudeEnabled : Key.codexEnabled)
    }

    static var toolsEnabled: Bool {
        get { defaults.bool(forKey: Key.toolsEnabled) }
        set { defaults.set(newValue, forKey: Key.toolsEnabled) }
    }

    /// Any `agent.*` preference is stored: this install used agents before the switches existed.
    /// Reset settings: the switches are stored as off, as on a fresh install, so the next launch's
    /// one-time enable migration (which reads "no stored switch" as "an older install") does not run.
    static func storeEverythingOff() {
        for key in [Key.claudeEnabled, Key.codexEnabled, Key.toolsEnabled] { defaults.set(false, forKey: key) }
    }

    static var hasAgentPreferences: Bool {
        let own = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:)) ?? [:]
        return own.keys.contains { $0.hasPrefix("agent.") }
    }

    // MARK: - Folders (v3 spec §7 "Folder")

    static var homeFolder: String { URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path }

    /// An agent never works in the home folder itself: it could read and change everything the user owns.
    static func isHome(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == homeFolder
    }

    private static var workspaces: URL {
        URL.applicationSupportDirectory.appending(path: "Bunny/Workspaces", directoryHint: .isDirectory)
    }

    /// "Bunny folder": an empty folder of Bunny's own, one per agent, for hand-offs that need no
    /// project. Only the path: `ensureFolder` creates it when a run starts there.
    static func bunnyFolder(for harness: AgentHarness) -> String {
        workspaces.appending(path: harness.displayName, directoryHint: .isDirectory).path
    }

    /// Creates `path` when it is one of Bunny's own folders (never a folder of the user's).
    static func ensureFolder(_ path: String) {
        let path = WorkingDirectoryResolver.key(path)
        guard path.hasPrefix(workspaces.path + "/") else { return }
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    /// Settings' default folder; nil = the Bunny folder. Never the home folder.
    static var defaultFolder: String? {
        get {
            let stored = defaults.string(forKey: Key.defaultWorkspace)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !stored.isEmpty else { return nil }
            let path = (stored as NSString).expandingTildeInPath
            return isHome(path) ? nil : path
        }
        set { defaults.set(newValue ?? "", forKey: Key.defaultWorkspace) }
    }

    /// Where a new run of `harness` for a note works (`WorkingDirectoryResolver`): the note's choice,
    /// else its attachments, else Settings' default.
    static func folder(choice: String?, shelf: [AgentBrief.ShelfEntry], harness: AgentHarness) -> WorkingDirectoryResolver.Resolution {
        WorkingDirectoryResolver.resolve(choice: choice, shelf: shelf, defaultFolder: defaultFolder,
                                         bunnyFolder: bunnyFolder(for: harness), home: homeFolder,
                                         exists: isFolder)
    }

    /// A run's folder as the note side shows it: "Bunny folder", or the path with "~".
    static func folderLabel(_ path: String) -> String {
        WorkingDirectoryResolver.key(path).hasPrefix(workspaces.path + "/") ? "Bunny folder" : abbreviated(path)
    }

    static func abbreviated(_ path: String) -> String {
        WorkingDirectoryResolver.abbreviated(path, home: homeFolder)
    }

    /// Folders recent hand-offs worked in, newest first; only the ones still there.
    static var recentFolders: [String] {
        RecentFolders.shown(defaults.stringArray(forKey: Key.recentFolders) ?? [], exists: isFolder)
    }

    static func recordRecentFolder(_ path: String) {
        let list = defaults.stringArray(forKey: Key.recentFolders) ?? []
        defaults.set(RecentFolders.adding(path, to: list, excluding: [workspaces.path]), forKey: Key.recentFolders)
    }

    private static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
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

    // MARK: - Model & effort (spec §2)

    /// The default model for runs of `harness` ("" = the CLI's default).
    static func model(for harness: AgentHarness) -> String {
        trimmedString(harness == .claudeCode ? Key.claudeModel : Key.codexModel)
    }

    static func setModel(_ model: String, for harness: AgentHarness) {
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines),
                     forKey: harness == .claudeCode ? Key.claudeModel : Key.codexModel)
    }

    /// The default reasoning effort for runs of `harness` ("" = the CLI's default).
    static func effort(for harness: AgentHarness) -> String {
        trimmedString(harness == .claudeCode ? Key.claudeEffort : Key.codexEffort)
    }

    static func setEffort(_ effort: String, for harness: AgentHarness) {
        defaults.set(effort.trimmingCharacters(in: .whitespacesAndNewlines),
                     forKey: harness == .claudeCode ? Key.claudeEffort : Key.codexEffort)
    }

    /// The model Claude Code last reported for a run that named none: the real name of its "Default".
    static var lastClaudeModel: String? {
        get { defaults.string(forKey: Key.lastClaudeModel) }
        set { defaults.set(newValue, forKey: Key.lastClaudeModel) }
    }

    /// The model a run with `settings` uses, by its real name: the chosen one, else the one the CLI
    /// reports as its default, else "Default".
    static func modelName(_ settings: RunSettings) -> String {
        let codexModels = CodexModelStore.shared.models
        if let model = settings.model { return AgentModelOptions.modelName(model, codexModels: codexModels) }
        return AgentModelOptions.defaultModelName(for: settings.harness, settingsModel: "", codexModels: codexModels,
                                                  lastClaudeModel: lastClaudeModel) ?? "Default"
    }

    /// The effort a run with `settings` uses: the chosen one, else Codex's default for the model, else "Default".
    static func effortName(_ settings: RunSettings) -> String {
        settings.effort ?? AgentModelOptions.defaultEffortName(for: settings.harness, settingsEffort: "", modelID: settings.model,
                                                               codexModels: CodexModelStore.shared.models) ?? "Default"
    }

    /// The attachments a folder can come from: the ones still on disk.
    static func shelfEntries(_ items: [ShelfItem]) -> [AgentBrief.ShelfEntry] {
        items.filter { FileManager.default.fileExists(atPath: $0.lastKnownPath) }
            .map { AgentBrief.ShelfEntry(path: $0.lastKnownPath, isDirectory: $0.isDirectory) }
    }

    /// What a run of `task` uses (`RunSettingsResolver`): the harness from `requestedHarness`, else the
    /// one of the task's session, else the task's chosen one, else the default (the other agent when
    /// the default is switched off); the task's model/effort only when chosen for that harness.
    /// `newRun`: a fresh hand-off, which is not tied to the agent of the note's old session.
    static func runSettings(for task: BunnyTask, requestedHarness: AgentHarness? = nil, newRun: Bool = false) -> RunSettings {
        let enablement = AgentEnablement.shared
        return RunSettingsResolver.resolve(
            requestedHarness: requestedHarness,
            taskHarness: task.agentHarness,
            harnessIsChosen: task.agentHarnessChosen,
            hasSession: task.agentSessionID != nil,
            sessionHarness: task.agentSessionHarness,
            freshRun: newRun,
            taskModel: task.agentModel,
            taskEffort: task.agentEffort,
            defaultHarness: enablement.defaultHarness ?? defaultHarness,
            settingsModel: { model(for: $0) },
            settingsEffort: { effort(for: $0) },
            isEnabled: enablement.isEnabled
        )
    }

    // MARK: - Bunny tools (spec §5)

    /// The port Bunny's MCP server tries first (default 47823). Not editable in the UI (spec §5 deviation).
    /// The server may end up on another port when this one is taken; `toolsURL` always has the actual one.
    static var toolsPort: Int {
        get {
            let stored = defaults.integer(forKey: Key.toolsPort)
            return (1...65_535).contains(stored) ? stored : defaultToolsPort
        }
        set { defaults.set(newValue, forKey: Key.toolsPort) }
    }

    /// Bearer token for the MCP server: 32 random bytes as 64 hex chars, generated on first read.
    /// Never log it.
    static var toolsToken: String {
        if let stored = defaults.string(forKey: Key.toolsToken), stored.count == 64 {
            return stored
        }
        let token = randomHexToken(byteCount: 32)
        defaults.set(token, forKey: Key.toolsToken)
        return token
    }

    /// Replaces the token with a new random one. The server must restart to use it, and global installs
    /// keep the old token until they are reinstalled.
    static func regenerateToolsToken() {
        defaults.set(randomHexToken(byteCount: 32), forKey: Key.toolsToken)
    }

    /// The URL of the running server (its actual port), for runs Bunny launches.
    static var toolsURL: String {
        "http://127.0.0.1:\(BunnyToolsServer.shared.port ?? toolsPort)/mcp"
    }

    /// The URL written by the global install: always the fixed `toolsPort`, never a fallback port.
    static var globalToolsURL: String {
        "http://127.0.0.1:\(toolsPort)/mcp"
    }

    static func commandName(for harness: AgentHarness) -> String {
        switch harness {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        }
    }

    /// Shortly after launch, for the switched-on agents only (nothing runs when `harnesses` is empty): warms the
    /// login-shell PATH on a background queue and stores the location of each CLI whose path isn't
    /// set yet. Never overwrites a path the owner set.
    static func warmUp(_ harnesses: [AgentHarness]) {
        guard !harnesses.isEmpty else { return }
        let names = harnesses.filter { cliPath(for: $0).isEmpty }.map { ($0, commandName(for: $0)) }
        // A little after launch, so the app is up before a login shell runs.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
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

    private static func trimmedString(_ key: String) -> String {
        defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func randomHexToken(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<byteCount).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }

    /// The trimmed, tilde-expanded stored path, or "".
    private static func storedPath(_ key: String) -> String {
        let stored = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? "" : (stored as NSString).expandingTildeInPath
    }
}
