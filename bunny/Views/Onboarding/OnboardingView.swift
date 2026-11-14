import AppKit
import SwiftUI

/// The Welcome window (v3 spec §9): two pages, both skippable. Shown by `WindowManager` at the first
/// launch and from Settings → General. Closing it by any means marks it done.
struct OnboardingView: View {
    static let size = NSSize(width: 560, height: 440)

    @State var page = 0
    /// Whether each agent's CLI is on this Mac; an agent missing here is still being looked for.
    /// Passed in by snapshots (nothing is looked up then).
    @State var found: [AgentHarness: Bool] = [:]
    var live = true
    private let enablement = AgentEnablement.shared

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if page == 0 { welcome } else { agents }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                if page == 0 {
                    Button("Skip") { WindowManager.shared.closeOnboarding(openMainWindow: false) }
                        .buttonStyle(.bunny)
                } else {
                    Button("Back") { page = 0 }
                        .buttonStyle(.bunny)
                }
                Spacer()
                if page == 0 {
                    Button("Continue") { page = 1 }
                        .buttonStyle(.bunnyProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start using Bunny") { WindowManager.shared.closeOnboarding(openMainWindow: true) }
                        .buttonStyle(.bunnyProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(BunnyTheme.background())
    }

    // MARK: - Page 1

    private var welcome: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Welcome to Bunny")
                .font(.system(size: 24, weight: .bold))
            Text("Quick notes in your menu bar.")
                .font(.system(size: 14))
                .foregroundStyle(BunnyTheme.secondary)
            card {
                row("plus.circle", "Click the icon, type, press Return.")
                Divider().opacity(0.6)
                row("paperclip", "Click a note to add details, files or a screenshot.")
                Divider().opacity(0.6)
                row("checkmark.circle", "Tick it when done. Right-click for everything else.")
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(BunnyTheme.secondary)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13.5))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .background(BunnyTheme.surface(dark: .quaternary.opacity(0.5)), in: .rect(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Page 2

    private var agents: some View {
        VStack(spacing: 10) {
            Text("Hand a note to an agent")
                .font(.system(size: 24, weight: .bold))
            Text("Optional. You can turn this on later in Settings.")
                .font(.system(size: 14))
                .foregroundStyle(BunnyTheme.secondary)
            card {
                agentRow(.claudeCode)
                Divider().opacity(0.6)
                agentRow(.codex)
            }
            .padding(.top, 14)
            Text("The agent gets the note, its details and its attachments, and works in the background. Bunny tells you when it has a question or is done.")
                .font(.system(size: 12.5))
                .foregroundStyle(BunnyTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .onAppear(perform: detect)
    }

    private func agentRow(_ harness: AgentHarness) -> some View {
        HStack(spacing: 12) {
            AgentLogo(harness: harness, size: 20)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(harness.displayName)
                    .font(.system(size: 13.5, weight: .medium))
                switch found[harness] {
                case true?:
                    // Plain green is too faint as text on the light card.
                    Text("Found on this Mac").foregroundStyle(Color.green.mix(with: .primary, by: 0.25))
                case false?:
                    Text("Not found — install it, then turn it on in Settings").foregroundStyle(BunnyTheme.secondary)
                case nil:
                    Text("Looking…").foregroundStyle(BunnyTheme.tertiary)
                }
            }
            .font(.system(size: 12))
            Spacer(minLength: 8)
            SettingsSwitch(isOn: Binding(get: { enablement.isEnabled(harness) }, set: { on in
                guard live else { return }
                enablement.setEnabled(on, for: harness) { path in
                    if on { found[harness] = path != nil }
                }
            }))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    /// The one place an agent that is not switched on is looked for: the user is being asked about
    /// it. Off the main thread (`AgentSettings.detect`); a path already set and working needs no search.
    private func detect() {
        guard live else { return }
        for harness in AgentHarness.allCases where found[harness] == nil {
            if FileManager.default.isExecutableFile(atPath: AgentSettings.cliPath(for: harness)) {
                found[harness] = true
            } else {
                AgentSettings.detect(harness) { path in found[harness] = path != nil }
            }
        }
    }
}
