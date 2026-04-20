// SPDX-License-Identifier: MIT
import SwiftUI

struct SetupGuideView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(OTLPServer.self) private var server
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Getting Started")
                .font(.title2)
                .fontWeight(.semibold)

            serverStatusSection

            Text("Add the following to your Claude Code settings to send telemetry here:")
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(setupGuideSnippet(port: settings.port))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            HStack {
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(setupGuideSnippet(port: settings.port), forType: .string)
                }
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 420)
    }

    @ViewBuilder
    private var serverStatusSection: some View {
        if server.isRunning {
            Text("Teloscope is running on port \(settings.port).")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Server is not running.")
                    .foregroundStyle(.secondary)
                Button("Start Server") {
                    NotificationCenter.default.post(name: .startOTLPServer, object: nil)
                }
            }
        }
    }
}

func setupGuideSnippet(port: Int) -> String {
    """
    // ~/.claude/settings.json
    {
      "env": {
        "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
        "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:\(port)",
        "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
        "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",
        "OTEL_METRICS_EXPORTER": "otlp",
        "OTEL_LOGS_EXPORTER": "otlp",
        "OTEL_TRACES_EXPORTER": "otlp"
      }
    }
    """
}

#Preview {
    SetupGuideView()
        .environment(AppSettings())
        .environment(OTLPServer())
}
