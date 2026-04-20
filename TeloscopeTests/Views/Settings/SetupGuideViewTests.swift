// SPDX-License-Identifier: MIT
import Testing
@testable import Teloscope

struct SetupGuideViewTests {
    @Test func snippetContainsPort() {
        let snippet = setupGuideSnippet(port: 9999)
        #expect(snippet.contains("http://localhost:9999"))
    }

    @Test func snippetContainsDefaultPort() {
        let snippet = setupGuideSnippet(port: 4318)
        #expect(snippet.contains("http://localhost:4318"))
    }

    @Test func snippetContainsRequiredKeys() {
        let snippet = setupGuideSnippet(port: 4318)
        #expect(snippet.contains("CLAUDE_CODE_ENABLE_TELEMETRY"))
        #expect(snippet.contains("OTEL_EXPORTER_OTLP_ENDPOINT"))
        #expect(snippet.contains("OTEL_EXPORTER_OTLP_PROTOCOL"))
        #expect(snippet.contains("CLAUDE_CODE_ENHANCED_TELEMETRY_BETA"))
        #expect(snippet.contains("OTEL_METRICS_EXPORTER"))
        #expect(snippet.contains("OTEL_LOGS_EXPORTER"))
        #expect(snippet.contains("OTEL_TRACES_EXPORTER"))
    }
}
