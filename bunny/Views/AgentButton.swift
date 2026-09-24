import SwiftUI

extension Color {
    /// `needsInput` tint: yellow mixed toward orange for light-mode contrast (spec §8).
    static var agentNeedsInput: Color { .yellow.mix(with: .orange, by: 0.35) }
}

/// The agent handoff button shown on parent-task rows: hands off to the default
/// harness, or opens the live/last session, and offers the full agent menu.
struct AgentButton: View {
    @Bindable var task: BunnyTask

    private var harness: AgentHarness {
        task.harness ?? AgentSettings.defaultHarness
    }

    private var tint: AnyShapeStyle {
        switch task.runState {
        case .running: return AnyShapeStyle(Color.accentColor)
        case .needsInput: return AnyShapeStyle(Color.agentNeedsInput)
        case .finished: return AnyShapeStyle(Color.green)
        case .failed: return AnyShapeStyle(Color.red)
        default: return AnyShapeStyle(.secondary)
        }
    }

    var body: some View {
        Button {
            AgentSupervisor.shared.primaryAction(for: task)
        } label: {
            Image(systemName: harness.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: task.runState == .running)
        }
        .buttonStyle(.plain)
        .help(task.agentSessionID == nil
              ? "Hand off to \(harness.displayName)"
              : "Open session in \(AgentSettings.openIn.displayName)")
        .contextMenu {
            Button("Start with Claude Code") {
                AgentSupervisor.shared.start(task, harness: .claudeCode)
            }
            .disabled(task.runState.isActive)

            Button("Start with Codex") {
                AgentSupervisor.shared.start(task, harness: .codex)
            }
            .disabled(task.runState.isActive)

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
