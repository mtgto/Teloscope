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
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("4318", text: $portText)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onSubmit { applyPort() }
                        .onChange(of: portText) { applyPort() }
                }
                Toggle("Start server on app launch", isOn: $settings.autoStart)
                    .onChange(of: settings.autoStart) { settings.save() }
            }
            Section("Data") {
                HStack {
                    Text("Retention (days)")
                    Spacer()
                    TextField("180", value: $settings.retentionDays, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: settings.retentionDays) { settings.save() }
                }
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
