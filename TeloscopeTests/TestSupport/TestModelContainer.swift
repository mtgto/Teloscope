// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
@testable import Teloscope

/// An in-memory container holding the same schema as `TeloscopeApp.sharedModelContainer`.
///
/// Tests used to declare their own partial schemas, which let a test pass against a model
/// graph the app never builds. Mirroring the app's schema here keeps that gap from reopening.
func makeTestModelContainer() throws -> ModelContainer {
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
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
