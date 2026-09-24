import SwiftUI
import ServiceManagement
import AppKit

struct GeneralSettingsView: View {
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
                    .onChange(of: appearance) { _, value in WindowManager.applyAppearance(value) }
                }

                Section {
                    Button("Show Welcome Guide…") {
                        WindowManager.shared.showOnboarding()
                    }
                }
            }
            .formStyle(.grouped)

            Button("Quit Bunny", role: .destructive) {
                NSApp.terminate(nil)
            }
            .buttonStyle(.glass)
            .tint(.red)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
