// SPDX-License-Identifier: MIT
import SwiftUI

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
