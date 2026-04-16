// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

enum SidebarItem: String, CaseIterable, Identifiable {
    case traces = "Traces"
    case metrics = "Metrics"
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
}

struct MainView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(OTLPServer.self) private var server
    @State private var selectedItem: SidebarItem? = .traces

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(LocalizedStringKey(item.rawValue), systemImage: item.systemImage)
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
