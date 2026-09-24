import AppKit
import SwiftUI

/// Settings → Agents (spec §8): default harness, CLI paths, autonomy, open-in app, default workspace.
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

    var body: some View {
        Form {
            Section {
                Picker("Default agent", selection: $defaultHarness) {
                    ForEach(AgentHarness.allCases, id: \.self) { harness in
                        Text(harness.displayName).tag(harness)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: defaultHarness) { _, new in AgentSettings.defaultHarness = new }
            }

            Section("CLI paths") {
                pathRow(.claudeCode, path: $claudePath)
                    .onChange(of: claudePath) { _, new in AgentSettings.claudePath = new }
                pathRow(.codex, path: $codexPath)
                    .onChange(of: codexPath) { _, new in AgentSettings.codexPath = new }
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
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

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
