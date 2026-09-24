import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

// MARK: - Page 1: Welcome

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("Welcome to Bunny")
                .font(.largeTitle.bold())

            Text("Your tasks live in the menu bar. Hand them to Claude Code or Codex when you're ready.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Page 2: Everything a task needs

struct TaskContextPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Everything a task needs")
                .font(.largeTitle.bold())

            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    symbol: "sidebar.left",
                    title: "Hover for details",
                    detail: "Every task opens a side panel with its description and shelf."
                )
                FeatureRow(
                    symbol: "text.alignleft",
                    title: "Describe it",
                    detail: "Add notes the whole task can carry."
                )
                FeatureRow(
                    symbol: "tray.and.arrow.down",
                    title: "Shelve files",
                    detail: "Drop files or folders on a task, or onto the menu-bar icon, and drag them back out anywhere."
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Page 3: Connect your agents

struct AgentsPage: View {
    enum DetectionStatus: Equatable {
        case detecting
        case found(String)
        case notFound
    }

    @State private var defaultHarness = AgentSettings.defaultHarness
    @State private var openIn = AgentSettings.openIn
    @State private var claudeStatus: DetectionStatus = .detecting
    @State private var codexStatus: DetectionStatus = .detecting

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect your agents")
                    .font(.largeTitle.bold())
                Text("Hand any task to Claude Code or Codex with one click.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                AgentRow(
                    harness: .claudeCode,
                    status: claudeStatus,
                    installHint: "npm i -g @anthropic-ai/claude-code",
                    choose: { choosePath(for: .claudeCode) }
                )
                AgentRow(
                    harness: .codex,
                    status: codexStatus,
                    installHint: "npm i -g @openai/codex",
                    choose: { choosePath(for: .codex) }
                )
            }

            Picker("Default agent", selection: $defaultHarness) {
                ForEach(AgentHarness.allCases, id: \.self) { harness in
                    Text(harness.displayName).tag(harness)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: defaultHarness) { _, newValue in
                AgentSettings.defaultHarness = newValue
            }

            Picker("Open sessions in", selection: $openIn) {
                ForEach(OpenInApp.allCases.filter(AgentSettings.isInstalled), id: \.self) { app in
                    Text(app.displayName).tag(app)
                }
            }
            .onChange(of: openIn) { _, newValue in
                AgentSettings.openIn = newValue
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            async let claudeResult = Task.detached { ShellEnvironment.locate("claude") }.value
            async let codexResult = Task.detached { ShellEnvironment.locate("codex") }.value
            applyDetection(await claudeResult, harness: .claudeCode)
            applyDetection(await codexResult, harness: .codex)
        }
    }

    /// Updates the row's status and, only if the user hasn't already set an explicit path,
    /// persists the detected one so Settings shows it immediately. Detection itself happens
    /// off the main thread (`.task` below); this only ever reads/writes the stored setting.
    private func applyDetection(_ path: String?, harness: AgentHarness) {
        switch harness {
        case .claudeCode:
            claudeStatus = path.map(DetectionStatus.found) ?? .notFound
            if let path, AgentSettings.claudePath.isEmpty {
                AgentSettings.claudePath = path
            }
        case .codex:
            codexStatus = path.map(DetectionStatus.found) ?? .notFound
            if let path, AgentSettings.codexPath.isEmpty {
                AgentSettings.codexPath = path
            }
        }
    }

    private func choosePath(for harness: AgentHarness) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch harness {
        case .claudeCode:
            AgentSettings.claudePath = url.path
            claudeStatus = .found(url.path)
        case .codex:
            AgentSettings.codexPath = url.path
            codexStatus = .found(url.path)
        }
    }
}

private struct AgentRow: View {
    let harness: AgentHarness
    let status: AgentsPage.DetectionStatus
    let installHint: String
    let choose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: harness.symbolName)
                .font(.title2)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(harness.displayName)
                    .font(.headline)
                statusView
            }

            Spacer()

            Button("Choose…", action: choose)
                .buttonStyle(.glass)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .detecting:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Detecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .found(let path):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .notFound:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Not found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(installHint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Page 4: You're all set

struct FinishPage: View {
    @State private var notificationsAuthorized = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("You're all set")
                .font(.largeTitle.bold())

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notifications")
                        .font(.headline)
                    Text("Get notified when an agent needs your input or finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if notificationsAuthorized {
                    Label("Notifications on", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Button("Enable Notifications") { requestNotifications() }
                        .buttonStyle(.glass)
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Launch at login")
                        .font(.headline)
                    Text("Start Bunny automatically when you log in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("SMAppService error: \(error)")
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            Text("Tip: click the 🐇 in your menu bar any time.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAuthorized = settings.authorizationStatus == .authorized
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                notificationsAuthorized = granted
            }
        }
    }
}
