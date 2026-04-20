// SPDX-License-Identifier: MIT
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(OTLPServer.self) private var server
    @State private var showingSetupGuide = false

    private let portFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 1
        f.maximum = 65535
        f.allowsFloats = false
        f.usesGroupingSeparator = false
        return f
    }()

    var body: some View {
        @Bindable var settings = settings
        ZStack(alignment: .bottomTrailing) {
            Form {
                Section("Server") {
                    TextField("Port", value: $settings.port, formatter: portFormatter, prompt: Text("4318"))
                        .onChange(of: settings.port) { settings.save() }
                    Toggle("Start server on app launch", isOn: $settings.autoStart)
                        .onChange(of: settings.autoStart) { settings.save() }
                }
                Section("Data") {
                    TextField("Retention (days)", value: $settings.retentionDays, format: .number, prompt: Text("180"))
                        .onChange(of: settings.retentionDays) { settings.save() }
                }
                Section("Display") {
                    Picker("Week starts on", selection: $settings.weekStartDay) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                    }
                    .onChange(of: settings.weekStartDay) { settings.save() }
                }
            }
            .formStyle(.grouped)

            Button {
                showingSetupGuide = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(16)
            .help("Show setup guide")
        }
        .sheet(isPresented: $showingSetupGuide) {
            SetupGuideView()
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
        .environment(OTLPServer())
}
