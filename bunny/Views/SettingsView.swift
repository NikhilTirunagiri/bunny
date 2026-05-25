import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // General section
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("General")

                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                            .font(.system(size: 13))
                        Text("Start Bunny automatically when you log in")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 16)

            // Appearance section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Appearance")

                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            // About section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("About")

                HStack(alignment: .center, spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let url = URL(string: "https://www.nikhilt.dev") {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bunny")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Version 0.9.0")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Link("by Nikhil Tirunagiri", destination: url)
                                .font(.system(size: 11))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Spacer()

            Divider().padding(.horizontal, 16)

            // Quit button
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Text("Quit Bunny")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minHeight: 360)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
