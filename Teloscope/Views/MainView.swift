// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

enum SidebarItem: String, CaseIterable, Identifiable {
    case metrics = "Metrics"
    case traces = "Traces"
    case logs = "Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .traces: return "chart.bar.doc.horizontal"
        case .metrics: return "chart.line.uptrend.xyaxis"
        case .logs: return "doc.text"
        case .settings: return "gear"
        }
    }

    var localizedName: LocalizedStringKey {
        switch self {
        case .traces:  "Traces"
        case .metrics: "Metrics"
        case .logs:    "Logs"
        case .settings: "Settings"
        }
    }
}

struct MainView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(OTLPServer.self) private var server
    @State private var selectedItem: SidebarItem? = .metrics
    @State private var serverErrorMessage: String?

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.localizedName, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selectedItem {
            case .traces: TraceListView()
            case .metrics: MetricsView()
            case .logs: ContentUnavailableView("Logs", systemImage: "doc.text", description: Text("Coming soon"))
            case .settings: SettingsView()
            case nil: ContentUnavailableView("Select an item", systemImage: "sidebar.left")
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                serverToggleButton
            }
        }
        .onChange(of: server.lastError) { _, newValue in
            serverErrorMessage = newValue
        }
        .alert(
            "Failed to Start OpenTelemetry Server",
            isPresented: Binding(
                get: { serverErrorMessage != nil },
                set: { if !$0 { serverErrorMessage = nil } }
            )
        ) {
            Button("OK") { serverErrorMessage = nil }
        } message: {
            if let msg = serverErrorMessage {
                Text(msg)
            }
        }
    }

    @ViewBuilder
    private var serverToggleButton: some View {
        if server.isRunning {
            Button {
                Task { try? await server.stop() }
            } label: {
                Label("Stop Server", systemImage: "stop.circle.fill")
                    .foregroundStyle(.green)
            }
            .help("OTLP server running on port \(settings.port). Click to stop.")
        } else {
            Button {
                NotificationCenter.default.post(name: .startOTLPServer, object: nil)
            } label: {
                Label("Start Server", systemImage: "play.circle")
            }
            .help("Click to start OTLP server on port \(settings.port)")
        }
    }
}

#Preview {
    MainView()
        .environment(AppSettings())
        .environment(OTLPServer())
        .modelContainer(
            for: [ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
                  ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self],
            inMemory: true
        )
}
