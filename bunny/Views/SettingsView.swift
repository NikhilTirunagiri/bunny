import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(isOn: $launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at login")
                                .font(.system(size: 13))
                            Text("Start Bunny automatically when you log in")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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

                Section("Appearance") {
                    Picker("", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("About") {
                    HStack(alignment: .center, spacing: 8) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 72, height: 72)
                        if let url = URL(string: "https://www.nikhilt.dev") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Version 0.9.0")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 0) {
                                    Text("Made with ❤️ ")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Link("Nikhil Tirunagiri", destination: url)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Text("Quit Bunny")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(.red)
            .padding(12)
        }
        .frame(minHeight: 360)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
