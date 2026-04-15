// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

@main
struct TeloscopeApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ResourceSpans.self,
            ScopeSpans.self,
            OTLPSpan.self,
            SpanAttribute.self,
            ResourceAttribute.self,
            ResourceMetrics.self,
            ResourceLogs.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var settings = AppSettings()
    @State private var server = OTLPServer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(server)
                .task {
                    startRetentionTimer()
                    if settings.autoStart {
                        await startServer()
                    }
                    for await _ in NotificationCenter.default.notifications(named: .startOTLPServer) {
                        await startServer()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func startServer() async {
        guard !server.isRunning else { return }
        let context = ModelContext(sharedModelContainer)
        let ingestion = OTLPIngestionService(modelContext: context)
        do {
            try await server.start(port: settings.port) { request in
                Task { @MainActor in
                    ingestion.ingest(request)
                }
            }
        } catch {
            await MainActor.run {
                server.lastError = error.localizedDescription
            }
        }
    }

    private func startRetentionTimer() {
        let context = ModelContext(sharedModelContainer)
        let service = OTLPIngestionService(modelContext: context)
        service.deleteOldData(retentionDays: settings.retentionDays)
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            let ctx = ModelContext(self.sharedModelContainer)
            let svc = OTLPIngestionService(modelContext: ctx)
            svc.deleteOldData(retentionDays: self.settings.retentionDays)
        }
    }
}

extension Notification.Name {
    static let startOTLPServer = Notification.Name("startOTLPServer")
}
