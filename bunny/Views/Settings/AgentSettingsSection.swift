import AppKit
import SwiftUI

/// Settings → Agents (spec §8): default harness, CLI paths, autonomy, open-in app, default workspace.
/// `@State` mirrors are seeded from `AgentSettings` in `.onAppear` and written back on change,
/// so a fresh Settings window always reflects auto-detected paths.
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
                pathRow(title: "Claude Code", path: $claudePath, cliName: "claude") { AgentSettings.claudePath = $0 }
                    .onChange(of: claudePath) { _, new in AgentSettings.claudePath = new }
                pathRow(title: "Codex", path: $codexPath, cliName: "codex") { AgentSettings.codexPath = $0 }
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

    private func pathRow(title: String, path: Binding<String>, cliName: String, save: @escaping (String) -> Void) -> some View {
        HStack {
            Circle()
                .fill(FileManager.default.isExecutableFile(atPath: path.wrappedValue) ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                TextField("Path to \(cliName)", text: path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit { save(path.wrappedValue) }
            }
            Button("Detect") {
                // Off the main thread: ShellEnvironment.locate runs a login shell (up to 3 s).
                // `refresh: true` bypasses the cached miss, so Detect finds a CLI installed since launch.
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let located = ShellEnvironment.locate(cliName, refresh: true) else { return }
                    DispatchQueue.main.async {
                        path.wrappedValue = located
                        save(located)
                    }
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
        openIn = AgentSettings.openIn
        defaultWorkspace = AgentSettings.defaultWorkspace
    }
}
