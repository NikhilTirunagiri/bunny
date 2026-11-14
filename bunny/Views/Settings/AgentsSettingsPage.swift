import AppKit
import SwiftUI

/// Settings → Agents: which CLIs were found, the defaults a hand-off uses, and under Advanced the CLI
/// paths, per-agent model and effort, permissions, and Bunny tools (the local MCP server and its
/// global install). `@State` mirrors are seeded from `AgentSettings` when the page appears; a control
/// writes its setting when the user changes it. A CLI path that is empty on appear triggers
/// `AgentSettings.detect` off the main thread.
struct AgentsSettingsPage: View {
    @Environment(\.settingsLive) private var live
    @Environment(SettingsModel.self) private var model

    @State private var defaultHarness: AgentHarness = .claudeCode
    @State private var claudePath = ""
    @State private var codexPath = ""
    @State private var autonomy: AgentAutonomy = .askFirst
    @State private var openIn: OpenInApp = .terminal
    /// The chosen default folder; nil = Bunny's own folder.
    @State private var customFolder: String?
    @State private var folderNote: String?

    // MARK: - Model & effort

    private static let customKey = "__custom__"
    private static let claudeModelChoices = [""] + AgentModelOptions.claudeModelAliases + [customKey]
    private static let efforts = [""] + AgentModelOptions.claudeEfforts

    @State private var claudeModelChoice = ""
    @State private var claudeModelCustomText = ""
    @State private var claudeEffort = ""

    @State private var codexModelChoice = ""
    @State private var codexModelCustomText = ""
    @State private var codexEffort = ""
    private let codexModelStore = CodexModelStore.shared
    private var codexModels: [CodexModel] { codexModelStore.models }

    // MARK: - Bunny tools

    @State private var toolsStatus: [AgentHarness: BunnyToolsInstaller.Status] = [:]
    @State private var toolsBusy: Set<AgentHarness> = []
    @State private var toolsError: [AgentHarness: String] = [:]
    @State private var tokenRegenerated = false
    private let toolsServer = BunnyToolsServer.shared

    var body: some View {
        SettingsCard {
            agentRow(.claudeCode, path: claudePath, installHint: "npm i -g @anthropic-ai/claude-code")
            agentRow(.codex, path: codexPath, installHint: "npm i -g @openai/codex")
        }
        .onAppear(perform: load)
        // A stored model id that matches a just-fetched model is no longer "Custom".
        .onChange(of: codexModelStore.models) { reconcileCodexModelChoice() }
        SettingsCard {
            SettingsRow(.defaultAgent, caption: "The agent a hand-off uses unless the note says otherwise.") {
                Picker("", selection: stored($defaultHarness) { AgentSettings.defaultHarness = $0 }) {
                    ForEach(AgentHarness.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(.openSessionsIn, caption: "Where Open session shows an agent's full log.") {
                Picker("", selection: stored($openIn) { AgentSettings.openIn = $0 }) {
                    ForEach(OpenInApp.allCases, id: \.self) { app in
                        Text(app.displayName).tag(app)
                            .selectionDisabled(!AgentSettings.isInstalled(app))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(.defaultFolder, caption: "Where an agent works when the note has no folder.") {
                Picker("", selection: folderSelection) {
                    Text("Bunny folder").tag("bunny")
                    if let customFolder {
                        Text(URL(fileURLWithPath: customFolder).lastPathComponent).tag("custom")
                    }
                    Divider()
                    Text("Choose…").tag("choose")
                }
                .labelsHidden()
                .fixedSize()
            } detail: {
                if let customFolder {
                    SettingsNote((customFolder as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(customFolder)
                }
                if let folderNote { SettingsNote(folderNote, color: .orange) }
            }
        }
        SettingsCard {
            SettingsRow(.advanced, caption: "CLI paths, model and effort, permissions, Bunny tools.") {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BunnyTheme.secondary)
                    .rotationEffect(.degrees(model.advancedExpanded ? 90 : 0))
            }
            .contentShape(.rect)
            .onTapGesture { model.advancedExpanded.toggle() }
            .accessibilityAddTraits(.isButton)
        }
        if model.advancedExpanded { advanced }
    }

    @ViewBuilder
    private var advanced: some View {
        SettingsHeading("CLI paths")
        SettingsCard {
            pathRow(.claudePath, .claudeCode, path: claudePath)
            pathRow(.codexPath, .codex, path: codexPath)
        }

        SettingsHeading("Model & effort")
        SettingsCard {
            SettingsRow(.claudeModel) {
                Picker("", selection: claudeModelSelection) {
                    ForEach(Self.claudeModelChoices, id: \.self) { Text(Self.claudeModelLabel($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            } detail: {
                if claudeModelChoice == Self.customKey {
                    TextField("Model id (e.g. claude-opus-5-5)", text: stored($claudeModelCustomText) {
                        AgentSettings.setModel($0, for: .claudeCode)
                    })
                    .textFieldStyle(.roundedBorder)
                }
            }
            SettingsRow(.claudeEffort) {
                Picker("", selection: stored($claudeEffort) { AgentSettings.setEffort($0, for: .claudeCode) }) {
                    ForEach(Self.efforts, id: \.self) { Text($0.isEmpty ? "Default" : $0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(.codexModel) {
                Picker("", selection: codexModelSelection) {
                    Text("Default").tag("")
                    ForEach(codexModels, id: \.id) { Text($0.displayName).tag($0.id) }
                    Text("Custom…").tag(Self.customKey)
                }
                .labelsHidden()
                .fixedSize()
            } detail: {
                if codexModelStore.isLoading && codexModels.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        SettingsNote("Loading models…")
                    }
                } else if codexModels.isEmpty {
                    // Codex missing or the list call timed out.
                    SettingsNote("Model list unavailable. Default and Custom still work.")
                }
                if codexModelChoice == Self.customKey {
                    TextField("Model id", text: stored($codexModelCustomText) { AgentSettings.setModel($0, for: .codex) })
                        .textFieldStyle(.roundedBorder)
                }
            }
            SettingsRow(.codexEffort) {
                Picker("", selection: stored($codexEffort) { AgentSettings.setEffort($0, for: .codex) }) {
                    Text("Default").tag("")
                    ForEach(codexEffortOptions(), id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }

        SettingsHeading("Permissions")
        SettingsCard {
            SettingsRow(.permissions) {
                Picker("", selection: stored($autonomy) { AgentSettings.autonomy = $0 }) {
                    Text("Ask before running commands").tag(AgentAutonomy.askFirst)
                    Text("Autonomous").tag(AgentAutonomy.autonomous)
                }
                .labelsHidden()
                .fixedSize()
            } detail: {
                if autonomy == .autonomous {
                    SettingsNote("Agents run commands and change files without asking you first.", color: .orange)
                }
            }
        }

        SettingsHeading("Bunny tools")
        SettingsCard {
            SettingsRow(.toolsServer, caption: toolsServer.port.map { "Running on port \($0)." } ?? "Not running.") {
                Button("Copy MCP URL") { copyToolsURL() }
                    .buttonStyle(.bunny)
            } detail: {
                Text(AgentSettings.toolsURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BunnyTheme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if isOnFallbackPort, let boundPort = toolsServer.port {
                    SettingsNote("Port \(AgentSettings.toolsPort) was busy; Bunny is using \(boundPort). " +
                                 "Global tools use port \(AgentSettings.toolsPort), so they can't reach Bunny and " +
                                 "Install is off until that port is free and Bunny restarts.", color: .orange)
                }
            }
            SettingsRow(.toolsToken, caption: "What agents show the server to be let in.") {
                Button("Regenerate") { regenerateToken() }
                    .buttonStyle(.bunny)
            } detail: {
                if tokenRegenerated {
                    SettingsNote("New token in use. Uninstall and install the global tools again so they use it.", color: .orange)
                }
            }
            bunnyToolsRow(.toolsClaude, .claudeCode)
            bunnyToolsRow(.toolsCodex, .codex)
        }
        SettingsNote("Installing writes Bunny's access token to ~/.claude.json and ~/.codex/config.toml. " +
                     "Any program running as you can read it. Uninstall removes it.")
            .padding(.horizontal, SettingsMetrics.rowPadding)
    }

    /// The control shows `state`; a change by the user is also written with `save`. Seeding the
    /// state (on appear, after detection) writes nothing.
    private func stored<Value>(_ state: Binding<Value>, save: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { state.wrappedValue },
            set: { newValue in
                state.wrappedValue = newValue
                save(newValue)
            }
        )
    }

    // MARK: - Agents found

    private func isFound(_ path: String) -> Bool {
        live ? FileManager.default.isExecutableFile(atPath: path) : !path.isEmpty
    }

    private func agentRow(_ harness: AgentHarness, path: String, installHint: String) -> some View {
        let found = isFound(path)
        return SettingsRow(harness == .claudeCode ? .claudeCode : .codex,
                           caption: found ? nil : "Install it with \(installHint), or set its path under Advanced.") {
            // The on/off switch of the next phase goes after the status, at the trailing edge.
            HStack(spacing: 10) {
                Label(found ? "Found" : "Not found", systemImage: found ? "checkmark.circle.fill" : "minus.circle")
                    .font(.callout)
                    // Plain green is too faint as text on the light card.
                    .foregroundStyle(found ? Color.green.mix(with: .primary, by: 0.25) : Color.secondary)
                    .help(found ? path : "\(AgentSettings.commandName(for: harness)) was not found")
            }
        }
    }

    // MARK: - CLI paths

    private func pathBinding(_ harness: AgentHarness) -> Binding<String> {
        switch harness {
        case .claudeCode:
            return stored($claudePath) { AgentSettings.claudePath = $0 }
        case .codex:
            return stored($codexPath) { new in
                AgentSettings.codexPath = new
                // Another CLI: its model list replaces the old one.
                codexModelStore.reset()
            }
        }
    }

    private func pathRow(_ id: SettingsCatalog.RowID, _ harness: AgentHarness, path: String) -> some View {
        SettingsRow(id) {
            HStack(spacing: 6) {
                Button("Detect") { detect(harness) }
                    .buttonStyle(.bunny)
                Button("Choose…") { choosePath(harness) }
                    .buttonStyle(.bunny)
            }
        } detail: {
            TextField("Path to \(AgentSettings.commandName(for: harness))", text: pathBinding(harness))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    /// Off the main thread with a fresh lookup (finds a CLI installed since launch); `detect` stores
    /// what it finds itself.
    private func detect(_ harness: AgentHarness) {
        AgentSettings.detect(harness) { located in
            guard let located else { return }
            showDetected(located, for: harness)
        }
    }

    /// A path `AgentSettings.detect` found and stored: show it, and make sure a Codex model list is loaded.
    private func showDetected(_ path: String, for harness: AgentHarness) {
        switch harness {
        case .claudeCode: claudePath = path
        case .codex:
            codexPath = path
            codexModelStore.loadIfNeeded()
        }
    }

    private func choosePath(_ harness: AgentHarness) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pathBinding(harness).wrappedValue = url.path
    }

    // MARK: - Default folder

    private var folderSelection: Binding<String> {
        Binding(
            get: { customFolder == nil ? "bunny" : "custom" },
            set: { choice in
                switch choice {
                case "bunny":
                    customFolder = nil
                    folderNote = nil
                    AgentSettings.defaultWorkspace = ""
                case "choose": chooseFolder()
                default: break
                }
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let customFolder { panel.directoryURL = URL(fileURLWithPath: customFolder) }
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        guard AgentSettings.notHome(url.path) == url.path else {
            folderNote = "The home folder can't be used: an agent could change everything in it."
            return
        }
        folderNote = nil
        customFolder = url.path
        AgentSettings.defaultWorkspace = url.path
    }

    // MARK: - Model & effort

    private var claudeModelSelection: Binding<String> {
        stored($claudeModelChoice) { choice in
            AgentSettings.setModel(choice == Self.customKey ? claudeModelCustomText : choice, for: .claudeCode)
        }
    }

    private static func claudeModelLabel(_ raw: String) -> String {
        switch raw {
        case "": return "Default"
        case customKey: return "Custom…"
        default: return raw
        }
    }

    private var codexModelSelection: Binding<String> {
        stored($codexModelChoice) { choice in
            AgentSettings.setModel(choice == Self.customKey ? codexModelCustomText : choice, for: .codex)
        }
    }

    /// The selected model's supported efforts, or the generic fallback when the selection is
    /// Default/Custom (no fetched `CodexModel` to read efforts from).
    private func codexEffortOptions() -> [String] {
        let modelID = codexModelChoice == Self.customKey ? codexModelCustomText : codexModelChoice
        return AgentModelOptions.efforts(for: .codex, modelID: modelID, codexModels: codexModels)
    }

    private func reconcileCodexModelChoice() {
        guard live else { return }
        let stored = AgentSettings.model(for: .codex)
        if stored.isEmpty || codexModels.contains(where: { $0.id == stored }) {
            codexModelChoice = stored
            codexModelCustomText = ""
        } else {
            codexModelChoice = Self.customKey
            codexModelCustomText = stored
        }
    }

    // MARK: - Bunny tools

    /// The server fell back to another port. Global installs always use the fixed port, so installing now
    /// would point them at a port nothing listens on: Install is disabled until the fixed port is back.
    private var isOnFallbackPort: Bool {
        guard let boundPort = toolsServer.port else { return false }
        return boundPort != AgentSettings.toolsPort
    }

    /// Rotates the token and restarts the server with it. Running agents keep working until their next
    /// request; global installs keep the old token until reinstalled.
    private func regenerateToken() {
        AgentSettings.regenerateToolsToken()
        BunnyToolsServer.shared.restart()
        tokenRegenerated = true
    }

    private func bunnyToolsRow(_ id: SettingsCatalog.RowID, _ harness: AgentHarness) -> some View {
        let status = toolsStatus[harness]
        let busy = toolsBusy.contains(harness)
        return SettingsRow(id) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    statusLabel(status)
                }
                toolsActionButton(harness, status: status, busy: busy)
            }
        } detail: {
            if let error = toolsError[harness] { SettingsNote(error, color: .red) }
        }
        .onAppear { refreshToolsStatus(harness) }
    }

    @ViewBuilder
    private func statusLabel(_ status: BunnyToolsInstaller.Status?) -> some View {
        switch status {
        case .installed:
            Text("Installed").font(.callout).foregroundStyle(.green)
        case .notInstalled, .none:
            Text("Not installed").font(.callout).foregroundStyle(BunnyTheme.secondary)
        case let .unavailable(message):
            Text(message).font(.callout).foregroundStyle(BunnyTheme.secondary)
        }
    }

    @ViewBuilder
    private func toolsActionButton(_ harness: AgentHarness, status: BunnyToolsInstaller.Status?, busy: Bool) -> some View {
        switch status {
        case .installed:
            Button("Uninstall") { performTools(harness, install: false) }
                .buttonStyle(.bunny)
                .disabled(busy)
        case .unavailable:
            Button("Install") {}
                .buttonStyle(.bunny)
                .disabled(true)
        case .notInstalled, .none:
            Button("Install") { performTools(harness, install: true) }
                .buttonStyle(.bunny)
                .disabled(busy || isOnFallbackPort)
        }
    }

    private func refreshToolsStatus(_ harness: AgentHarness) {
        guard live else { return }
        BunnyToolsInstaller.status(for: harness) { status in
            toolsStatus[harness] = status
        }
    }

    private func performTools(_ harness: AgentHarness, install: Bool) {
        toolsBusy.insert(harness)
        toolsError[harness] = nil
        let finished: @MainActor @Sendable (Result<Void, Error>) -> Void = { result in
            toolsBusy.remove(harness)
            switch result {
            case .success:
                refreshToolsStatus(harness)
            case let .failure(error):
                toolsError[harness] = (error as? BunnyToolsInstaller.InstallerError)?.message ?? error.localizedDescription
            }
        }
        if install {
            BunnyToolsInstaller.install(for: harness, completion: finished)
        } else {
            BunnyToolsInstaller.uninstall(for: harness, completion: finished)
        }
    }

    private func copyToolsURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AgentSettings.toolsURL, forType: .string)
    }

    // MARK: - Load

    private func load() {
        guard live else {
            // Snapshots: one agent found, one not; nothing is read, detected or fetched.
            claudePath = "/opt/homebrew/bin/claude"
            toolsStatus = [.claudeCode: .installed, .codex: .notInstalled]
            return
        }
        defaultHarness = AgentSettings.defaultHarness
        claudePath = AgentSettings.claudePath
        codexPath = AgentSettings.codexPath
        autonomy = AgentSettings.autonomy
        // Never a blank picker: an uninstalled stored app shows (and opens in) Terminal.
        openIn = AgentSettings.isInstalled(AgentSettings.openIn) ? AgentSettings.openIn : .terminal
        let folder = AgentSettings.defaultWorkspace
        customFolder = folder == AgentSettings.bunnyFolder ? nil : folder
        detectIfEmpty(.claudeCode)
        detectIfEmpty(.codex)

        let storedClaudeModel = AgentSettings.model(for: .claudeCode)
        if Self.claudeModelChoices.contains(storedClaudeModel) {
            claudeModelChoice = storedClaudeModel
            claudeModelCustomText = ""
        } else {
            claudeModelChoice = Self.customKey
            claudeModelCustomText = storedClaudeModel
        }
        claudeEffort = AgentSettings.effort(for: .claudeCode)

        reconcileCodexModelChoice()
        codexEffort = AgentSettings.effort(for: .codex)
        // Refresh on every open: the account's model list can change while Bunny runs.
        codexModelStore.refresh()
    }

    /// Fills an empty path field once detection returns (unless the owner typed one meanwhile).
    private func detectIfEmpty(_ harness: AgentHarness) {
        let path = harness == .claudeCode ? $claudePath : $codexPath
        guard path.wrappedValue.isEmpty else { return }
        AgentSettings.detect(harness) { located in
            if path.wrappedValue.isEmpty {
                if let located { showDetected(located, for: harness) }
            } else {
                // `detect` stored what it found; the owner's typed path wins.
                AgentSettings.setCLIPath(path.wrappedValue, for: harness)
            }
        }
    }
}
