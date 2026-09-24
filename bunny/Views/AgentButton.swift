import SwiftUI

extension Color {
    /// `needsInput` tint: yellow mixed toward orange for light-mode contrast (spec §8).
    static var agentNeedsInput: Color { .yellow.mix(with: .orange, by: 0.35) }
}

/// The agent handoff button shown on parent-task rows: hands off to the default (or task's chosen)
/// harness, or opens the live/last session, and offers the full agent config menu on right-click.
struct AgentButton: View {
    @Bindable var task: BunnyTask

    /// Bunny tools reach sessions Bunny runs itself; a session reopened in a terminal only sees them via
    /// the global install.
    static let sessionToolsNote = "Bunny tools are available in the opened session only if they're " +
        "installed globally (Settings → Agents → Bunny tools)."

    private var runSettings: RunSettings { AgentSettings.runSettings(for: task) }
    private var harness: AgentHarness { runSettings.harness }

    private var statusDotColor: Color? {
        switch task.runState {
        case .running: return Color.accentColor
        case .needsInput: return Color.agentNeedsInput
        case .finished: return Color.green
        case .failed: return Color.red
        default: return nil
        }
    }

    /// "Hand off to <harness> · <model> · <effort>" before a session exists, else the open-session hint.
    private var tooltip: String {
        guard task.agentSessionID == nil else {
            return "Open session in \(AgentSettings.openIn.displayName). \(Self.sessionToolsNote)"
        }
        return "Hand off to \(RunSettingsResolver.caption(runSettings))"
    }

    var body: some View {
        Button {
            AgentSupervisor.shared.primaryAction(for: task)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                AgentLogo(harness: harness, size: 12)
                if let statusDotColor {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(statusDotColor)
                        .symbolEffect(.pulse, isActive: task.runState == .running)
                        .offset(x: 2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .contextMenu {
            // Only before a session exists; afterwards only the session items below.
            if AgentConfigMenu.isAvailable(for: task) {
                AgentConfigMenu(task: task)
            }

            if task.agentSessionID != nil {
                Button("Open Session in \(AgentSettings.openIn.displayName)") {
                    AgentSupervisor.shared.openSession(task)
                }
            }

            if task.runState.isActive {
                Button("Stop Agent") {
                    AgentSupervisor.shared.stop(task)
                }
            }

            if !task.runState.isActive && task.runState != .idle {
                Button("Clear Agent") {
                    AgentSupervisor.shared.clear(task)
                }
            }
        }
    }
}
