import SwiftUI

/// The harness's brand mark (`ClaudeLogo` / `CodexLogo` in Assets.xcassets), used wherever an SF
/// Symbol previously stood in for the harness (row `AgentButton`, the panel header, Settings'
/// default-agent picker, onboarding).
struct AgentLogo: View {
    let harness: AgentHarness
    var size: CGFloat = 12

    var body: some View {
        Image(harness == .claudeCode ? "ClaudeLogo" : "CodexLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
