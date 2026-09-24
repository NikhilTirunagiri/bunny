import AppKit
import SwiftUI

/// Settings → Agents (spec §8): default harness, CLI paths, autonomy, open-in app, default workspace,
/// per-harness model/effort defaults (spec §2), and the global "Bunny tools" install (spec §5).
/// `@State` mirrors are re-seeded from `AgentSettings` each time the pane appears and written back on
/// change. A CLI path that is still empty on appear (launch-time detection not finished, or found
/// nothing) triggers `AgentSettings.detect` off the main thread and fills the field if it finds one.
struct AgentSettingsSection: View {
    @State private var defaultHarness: AgentHarness = .claudeCode
    @State private var claudePath: String = ""
    @State private var codexPath: String = ""
    @State private var autonomy: AgentAutonomy = .autonomous
    @State private var openIn: OpenInApp = .terminal
    @State private var defaultWorkspace: String = ""

    // MARK: - Model & effort (spec §2)

    private static let customKey = "__custom__"
    private static let claudeModelChoices = [""] + AgentModelOptions.claudeModelAliases + [customKey]
    private static let efforts = [""] + AgentModelOptions.claudeEfforts

    @State private var claudeModelChoice: String = ""
    @State private var claudeModelCustomText: String = ""
    @State private var claudeEffort: String = ""

    @State private var codexModelChoice: String = ""
    @State private var codexModelCustomText: String = ""
    @State private var codexEffort: String = ""
    private let codexModelStore = CodexModelStore.shared
    private var codexModels: [CodexModel] { codexModelStore.models }

    // MARK: - Bunny tools (spec §5)

    @State private var toolsStatus: [AgentHarness: BunnyToolsInstaller.Status] = [:]
    @State private var toolsBusy: Set<AgentHarness> = []
    @State private var toolsError: [AgentHarness: String] = [:]
    @State private var tokenRegenerated = false
    private let toolsServer = BunnyToolsServer.shared

    var body: some View {
        Form {
            Section {
                Picker("Default agent", selection: $defaultHarness) {
                    ForEach(AgentHarness.allCases, id: \.self) { harness in
                        HStack(spacing: 4) {
                            AgentLogo(harness: harness, size: 12)
                            Text(harness.displayName)
                        }
                        .tag(harness)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: defaultHarness) { _, new in AgentSettings.defaultHarness = new }
            }

            Section("CLI paths") {
                pathRow(.claudeCode, path: $claudePath)
                    .onChange(of: claudePath) { _, new in AgentSettings.claudePath = new }
                pathRow(.codex, path: $codexPath)
                    .onChange(of: codexPath) { _, new in
                        // Seeding the field on appear, or Detect (which stores the path itself), isn't a
                        // change of CLI: just make sure a list is loaded.
                        guard new != AgentSettings.codexPath else {
                            codexModelStore.loadIfNeeded()
                            return
                        }
                        AgentSettings.codexPath = new
                        codexModelStore.reset()
                    }
            }

            Section("Model & effort") {
                claudeModelEffortRows
                Divider()
                codexModelEffortRows
            }

            Section {
                Picker("Autonomy", selection: $autonomy) {
                    Text("Autonomous").tag(AgentAutonomy.autonomous)
                    Text("Ask before running commands").tag(AgentAutonomy.askFirst)
                }
                .onChange(of: autonomy) { _, new in AgentSettings.autonomy = new }
            }

            Section {
                Picker("Open sessions in", selection: $openIn) {
                    ForEach(OpenInApp.allCases.filter(AgentSettings.isInstalled), id: \.self) { app in
                        Text(app.displayName).tag(app)
                    }
                }
                .onChange(of: openIn) { _, new in AgentSettings.openIn = new }
            }

            Section("Default workspace") {
                HStack {
                    TextField("~", text: $defaultWorkspace)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: defaultWorkspace) { _, new in AgentSettings.defaultWorkspace = new }
                    Button("Choose…") { chooseWorkspace() }
                }
            }

            Section {
                bunnyToolsHeader
                bunnyToolsRow(.claudeCode)
                bunnyToolsRow(.codex)
                regenerateTokenRow
            } header: {
                Text("Bunny tools")
            } footer: {
                Text("Installing writes Bunny's access token to ~/.claude.json and ~/.codex/config.toml. " +
                     "Any program running as you can read it. Uninstall removes it.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        // A stored model id that matches a just-fetched model is no longer "Custom".
        .onChange(of: codexModelStore.models) { _, _ in reconcileCodexModelChoice() }
    }

    // MARK: - CLI paths

    private func pathRow(_ harness: AgentHarness, path: Binding<String>) -> some View {
        HStack {
            Circle()
                .fill(FileManager.default.isExecutableFile(atPath: path.wrappedValue) ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(harness.displayName).font(.system(size: 13))
                TextField("Path to \(AgentSettings.commandName(for: harness))", text: path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit { AgentSettings.setCLIPath(path.wrappedValue, for: harness) }
            }
            Button("Detect") {
                // Off the main thread with a fresh lookup (finds a CLI installed since launch); stores what it finds.
                AgentSettings.detect(harness) { located in
                    if let located { path.wrappedValue = located }
                }
            }
        }
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if !defaultWorkspace.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (defaultWorkspace as NSString).expandingTildeInPath)
        }
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        defaultWorkspace = url.path
        AgentSettings.defaultWorkspace = url.path
    }

    // MARK: - Model & effort rows

    private var claudeModelEffortRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude Code").font(.system(size: 12, weight: .semibold))
            Picker("Model", selection: claudeModelSelection) {
                ForEach(Self.claudeModelChoices, id: \.self) { choice in
                    Text(Self.claudeModelLabel(choice)).tag(choice)
                }
            }
            if claudeModelChoice == Self.customKey {
                TextField("Model id (e.g. claude-opus-5-5)", text: $claudeModelCustomText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: claudeModelCustomText) { _, new in AgentSettings.setModel(new, for: .claudeCode) }
            }
            Picker("Effort", selection: claudeEffortSelection) {
                ForEach(Self.efforts, id: \.self) { effort in
                    Text(effort.isEmpty ? "Default" : effort).tag(effort)
                }
            }
        }
    }

    private var claudeModelSelection: Binding<String> {
        Binding(
            get: { claudeModelChoice },
            set: { newValue in
                claudeModelChoice = newValue
                AgentSettings.setModel(newValue == Self.customKey ? claudeModelCustomText : newValue, for: .claudeCode)
            }
        )
    }

    private var claudeEffortSelection: Binding<String> {
        Binding(
            get: { claudeEffort },
            set: { newValue in
                claudeEffort = newValue
                AgentSettings.setEffort(newValue, for: .claudeCode)
            }
        )
    }

    private static func claudeModelLabel(_ raw: String) -> String {
        switch raw {
        case "": return "Default"
        case customKey: return "Custom…"
        default: return raw
        }
    }

    private var codexModelEffortRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Codex").font(.system(size: 12, weight: .semibold))
            Picker("Model", selection: codexModelSelection) {
                Text("Default").tag("")
                ForEach(codexModels, id: \.id) { model in
                    Text(model.displayName).tag(model.id)
                }
                Text("Custom…").tag(Self.customKey)
            }
            if codexModelStore.isLoading && codexModels.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading models…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if codexModels.isEmpty {
                // Review Focus #5: codex missing or the list call timed out — Default/Custom still work.
                Text("Model list unavailable — Default and Custom still work.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            if codexModelChoice == Self.customKey {
                TextField("Model id", text: $codexModelCustomText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: codexModelCustomText) { _, new in AgentSettings.setModel(new, for: .codex) }
            }
            Picker("Effort", selection: codexEffortSelection) {
                Text("Default").tag("")
                ForEach(codexEffortOptions(), id: \.self) { effort in
                    Text(effort).tag(effort)
                }
            }
        }
    }

    private var codexModelSelection: Binding<String> {
        Binding(
            get: { codexModelChoice },
            set: { newValue in
                codexModelChoice = newValue
                AgentSettings.setModel(newValue == Self.customKey ? codexModelCustomText : newValue, for: .codex)
            }
        )
    }

    private var codexEffortSelection: Binding<String> {
        Binding(
            get: { codexEffort },
            set: { newValue in
                codexEffort = newValue
                AgentSettings.setEffort(newValue, for: .codex)
            }
        )
    }

    /// The selected model's supported efforts, or the generic fallback when the selection is
    /// Default/Custom (no fetched `CodexModel` to read efforts from).
    private func codexEffortOptions() -> [String] {
        let modelID = codexModelChoice == Self.customKey ? codexModelCustomText : codexModelChoice
        return AgentModelOptions.efforts(for: .codex, modelID: modelID, codexModels: codexModels)
    }

    private func reconcileCodexModelChoice() {
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

    private var bunnyToolsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Port")
                Spacer()
                Text("\(toolsServer.port ?? AgentSettings.toolsPort)")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11, design: .monospaced))
            }
            HStack {
                Text(AgentSettings.toolsURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button("Copy MCP URL") { copyToolsURL() }
            }
            if isOnFallbackPort, let boundPort = toolsServer.port {
                Text("Port \(AgentSettings.toolsPort) was busy; Bunny is using \(boundPort). " +
                     "Global tools use port \(AgentSettings.toolsPort), so they can't reach Bunny and " +
                     "Install is off until that port is free and Bunny restarts.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }
        }
    }

    /// The server fell back to another port. Global installs always use the fixed port, so installing now
    /// would point them at a port nothing listens on: Install is disabled until the fixed port is back.
    private var isOnFallbackPort: Bool {
        guard let boundPort = toolsServer.port else { return false }
        return boundPort != AgentSettings.toolsPort
    }

    private var regenerateTokenRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Access token")
                Spacer()
                Button("Regenerate Token") { regenerateToken() }
            }
            if tokenRegenerated {
                Text("New token in use. Uninstall and install the global tools again so they use it.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Rotates the token and restarts the server with it. Running agents keep working until their next
    /// request; global installs keep the old token until reinstalled.
    private func regenerateToken() {
        AgentSettings.regenerateToolsToken()
        BunnyToolsServer.shared.restart()
        tokenRegenerated = true
    }

    private func bunnyToolsRow(_ harness: AgentHarness) -> some View {
        let status = toolsStatus[harness]
        let busy = toolsBusy.contains(harness)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Bunny tools in all \(harness.displayName) sessions")
                Spacer()
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    statusLabel(status)
                }
                toolsActionButton(harness, status: status, busy: busy)
            }
            if let error = toolsError[harness] {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
            }
        }
        .onAppear { refreshToolsStatus(harness) }
    }

    @ViewBuilder
    private func statusLabel(_ status: BunnyToolsInstaller.Status?) -> some View {
        switch status {
        case .installed:
            Text("Installed").font(.system(size: 11)).foregroundStyle(.green)
        case .notInstalled, .none:
            Text("Not installed").font(.system(size: 11)).foregroundStyle(.secondary)
        case let .unavailable(message):
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func toolsActionButton(_ harness: AgentHarness, status: BunnyToolsInstaller.Status?, busy: Bool) -> some View {
        switch status {
        case .installed:
            Button("Uninstall") { performToolsUninstall(harness) }.disabled(busy)
        case .unavailable:
            Button("Install") { performToolsInstall(harness) }.disabled(true)
        case .notInstalled, .none:
            Button("Install") { performToolsInstall(harness) }.disabled(busy || isOnFallbackPort)
        }
    }

    private func refreshToolsStatus(_ harness: AgentHarness) {
        BunnyToolsInstaller.status(for: harness) { status in
            toolsStatus[harness] = status
        }
    }

    private func performToolsInstall(_ harness: AgentHarness) {
        toolsBusy.insert(harness)
        toolsError[harness] = nil
        BunnyToolsInstaller.install(for: harness) { result in
            toolsBusy.remove(harness)
            switch result {
            case .success:
                refreshToolsStatus(harness)
            case let .failure(error):
                toolsError[harness] = Self.errorText(error)
            }
        }
    }

    private func performToolsUninstall(_ harness: AgentHarness) {
        toolsBusy.insert(harness)
        toolsError[harness] = nil
        BunnyToolsInstaller.uninstall(for: harness) { result in
            toolsBusy.remove(harness)
            switch result {
            case .success:
                refreshToolsStatus(harness)
            case let .failure(error):
                toolsError[harness] = Self.errorText(error)
            }
        }
    }

    private func copyToolsURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AgentSettings.toolsURL, forType: .string)
    }

    private static func errorText(_ error: Error) -> String {
        (error as? BunnyToolsInstaller.InstallerError)?.message ?? error.localizedDescription
    }

    // MARK: - Load

    private func load() {
        defaultHarness = AgentSettings.defaultHarness
        claudePath = AgentSettings.claudePath
        codexPath = AgentSettings.codexPath
        autonomy = AgentSettings.autonomy
        // Never a blank picker: an uninstalled stored app shows (and opens in) Terminal.
        openIn = AgentSettings.isInstalled(AgentSettings.openIn) ? AgentSettings.openIn : .terminal
        defaultWorkspace = AgentSettings.defaultWorkspace
        detectIfEmpty(.claudeCode, path: $claudePath)
        detectIfEmpty(.codex, path: $codexPath)

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
    private func detectIfEmpty(_ harness: AgentHarness, path: Binding<String>) {
        guard path.wrappedValue.isEmpty else { return }
        AgentSettings.detect(harness) { located in
            if path.wrappedValue.isEmpty {
                if let located { path.wrappedValue = located }
            } else {
                // `detect` stored what it found; the owner's typed path wins.
                AgentSettings.setCLIPath(path.wrappedValue, for: harness)
            }
        }
    }
}
