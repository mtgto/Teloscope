// SPDX-License-Identifier: MIT

import SwiftUI
import SwiftData

@main
struct TeloscopeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ResourceSpans.self,
            ScopeSpans.self,
            Span.self,
            SpanAttribute.self,
            ResourceAttribute.self,
            ResourceMetrics.self,
            ResourceLogs.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
