import SwiftUI
import AppKit

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("Bunny")
                .font(.title.bold())

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let url = URL(string: "https://www.nikhilt.dev") {
                HStack(spacing: 0) {
                    Text("Made with ❤️ by ")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("Nikhil Tirunagiri", destination: url)
                        .font(.caption)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
