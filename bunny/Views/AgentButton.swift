import SwiftUI

extension Color {
    /// `needsInput` tint: yellow mixed toward orange for light-mode contrast (spec §8).
    static var agentNeedsInput: Color { .yellow.mix(with: .orange, by: 0.35) }
}

/// Hand off, the one hover action of a row: starts a background run at once with the note's agent
/// (the one picked in its options card, else Settings' default). The row shows it only while an agent
/// is switched on and the note has no session and no active run, so a click always starts a run.
struct AgentButton: View {
    @Bindable var task: BunnyTask

    /// Bunny tools reach sessions Bunny runs itself; a session reopened in a terminal only sees them via
    /// the global install.
    static let sessionToolsNote = "Bunny tools are available in the opened session only if they're " +
        "installed globally (Settings → Agents → Bunny tools)."

    private var runSettings: RunSettings { AgentSettings.runSettings(for: task) }

    var body: some View {
        Button {
            AgentSupervisor.shared.primaryAction(for: task)
        } label: {
            AgentLogo(harness: runSettings.harness, size: 12)
        }
        .buttonStyle(.bunnyRowIcon.lively())
        .help("Hand off to \(RunSettingsResolver.caption(runSettings))")
    }
}
