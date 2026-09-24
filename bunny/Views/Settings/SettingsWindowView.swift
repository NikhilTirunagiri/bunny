import SwiftUI

struct SettingsWindowView: View {
    @Environment(SettingsSelection.self) private var selection

    var body: some View {
        @Bindable var selection = selection
        TabView(selection: $selection.tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(WindowManager.SettingsTab.general)

            AgentSettingsSection()
                .tabItem { Label("Agents", systemImage: "sparkle") }
                .tag(WindowManager.SettingsTab.agents)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(WindowManager.SettingsTab.about)
        }
        .frame(minWidth: 560, minHeight: 460)
    }
}
