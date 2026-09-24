import SwiftUI

extension Color {
    /// `needsInput` tint: yellow mixed toward orange for light-mode contrast (spec §8).
    static var agentNeedsInput: Color { .yellow.mix(with: .orange, by: 0.35) }
}

/// The agent handoff button shown on parent-task rows: hands off to the default (or task's chosen)
/// harness, or opens the live/last session, and offers the full agent config menu on right-click.
struct AgentButton: View {
    @Bindable var task: BunnyTask

    private var harness: AgentHarness {
        task.harness ?? AgentSettings.defaultHarness
    }

    private var statusDotColor: Color? {
        switch task.runState {
        case .running: return Color.accentColor
        case .needsInput: return Color.agentNeedsInput
        case .finished: return Color.green
        case .failed: return Color.red
        default: return nil
        }
    }

    private func displayValue(_ raw: String) -> String { raw.isEmpty ? "Default" : raw }

    /// "Hand off to <harness> · <model> · <effort>" before a session exists, else the open-session hint.
    private var tooltip: String {
        guard task.agentSessionID == nil else {
            return "Open session in \(AgentSettings.openIn.displayName)"
        }
        let model = displayValue(task.agentModel ?? AgentSettings.model(for: harness))
        let effort = displayValue(task.agentEffort ?? AgentSettings.effort(for: harness))
        return "Hand off to \(harness.displayName) · \(model) · \(effort)"
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
            if !task.runState.isActive {
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
