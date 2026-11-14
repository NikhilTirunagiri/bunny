import AppKit
import SwiftUI

struct AboutSettingsPage: View {
    private let updates = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            Text("Bunny")
                .font(.title2.bold())
            Text("Version \(UpdateChecker.currentVersion)")
                .font(.callout)
                .foregroundStyle(BunnyTheme.secondary)
            Text("By Nikhil Tirunagiri and Rahul Sharma")
                .font(.callout)
                .foregroundStyle(BunnyTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)

        SettingsCard {
            SettingsRow(.repository, caption: "github.com/NikhilTirunagiri/bunny") {
                Button("Open") { NSWorkspace.shared.open(UpdateChecker.repositoryPage) }
                    .buttonStyle(.bunny)
            }
            SettingsRow(.checkForUpdates, caption: updateCaption) {
                HStack(spacing: 8) {
                    if updates.state == .checking { ProgressView().controlSize(.small) }
                    if case .available(_, let page) = updates.state {
                        Button("Download") { NSWorkspace.shared.open(page) }
                            .buttonStyle(.bunnyProminent)
                    } else {
                        Button("Check Now") { updates.check() }
                            .buttonStyle(.bunny)
                            .disabled(updates.state == .checking)
                    }
                }
            }
        }
    }

    private var updateCaption: String {
        switch updates.state {
        case .idle: return "Asks GitHub for the latest release. Nothing installs by itself."
        case .checking: return "Checking…"
        case .upToDate: return "You have the latest version."
        case .available(let version, _): return "Version \(version) is available."
        case .failed(let message): return message
        }
    }
}
