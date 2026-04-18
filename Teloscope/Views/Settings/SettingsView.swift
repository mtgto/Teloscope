// SPDX-License-Identifier: MIT
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(OTLPServer.self) private var server
    @State private var portText = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Server") {
                TextField("Port", text: $portText, prompt: Text("4318"))
                    .onSubmit { applyPort() }
                    .onChange(of: portText) { applyPort() }
                Toggle("Start server on app launch", isOn: $settings.autoStart)
                    .onChange(of: settings.autoStart) { settings.save() }
            }
            Section("Data") {
                TextField("Retention (days)", value: $settings.retentionDays, format: .number, prompt: Text("180"))
                    .onChange(of: settings.retentionDays) { settings.save() }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            portText = "\(settings.port)"
        }
    }

    private func applyPort() {
        if let port = Int(portText), port > 0, port <= 65535 {
            settings.port = port
            settings.save()
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
        .environment(OTLPServer())
}
