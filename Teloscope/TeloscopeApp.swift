// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

@main
struct TeloscopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ResourceSpans.self,
            ScopeSpans.self,
            OTLPSpan.self,
            SpanAttribute.self,
            ResourceAttribute.self,
            ResourceMetrics.self,
            ResourceLogs.self,
            LogEvent.self,
            MetricDataPoint.self,
            MetricAttribute.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var settings = AppSettings(
        defaults: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            ? UserDefaults(suiteName: UUID().uuidString)!
            : .standard
    )
    @State private var server = OTLPServer()

    var body: some Scene {
        Window("Teloscope", id: "main") {
            MainView()
                .environment(settings)
                .environment(server)
                .task {
                    startBackgroundMaintenance()
                    if settings.autoStart {
                        await startServer()
                    }
                    for await _ in NotificationCenter.default.notifications(named: .startOTLPServer) {
                        await startServer()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(before: .windowList) {
                ShowMainWindowCommand()
                Divider()
            }
        }
    }

    private func startServer() async {
        guard !server.isRunning else { return }
        await MainActor.run { server.lastError = nil }
        let ingestion = OTLPIngestionService(modelContainer: sharedModelContainer)
        do {
            try await server.start(port: settings.port) { request in
                Task { await ingestion.ingest(request) }
            }
        } catch {
            await MainActor.run {
                server.lastError = error.localizedDescription
            }
        }
    }

    /// Runs the one-off schema backfill and starts the retention sweep. Both go through
    /// the ingestion actor so neither touches the main thread.
    private func startBackgroundMaintenance() {
        let service = OTLPIngestionService(modelContainer: sharedModelContainer)
        let retentionDays = settings.retentionDays
        Task {
            await service.backfillMetricTypes()
            await service.deleteOldData(retentionDays: retentionDays)
        }
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { await service.deleteOldData(retentionDays: retentionDays) }
        }
    }
}

extension Notification.Name {
    static let startOTLPServer = Notification.Name("startOTLPServer")
}

private struct ShowMainWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Teloscope") {
            openWindow(id: "main")
        }
        .keyboardShortcut("0", modifiers: .command)
    }
}
