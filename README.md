# Teloscope

A macOS 14+ app that acts as an OpenTelemetry collector. It receives OTLP/HTTP signals from Claude Code, stores them in SwiftData, and visualizes Traces as a Gantt chart.

> **Name:** Telos (purpose/end) + scope (observation) — a pun on "telescope"

## Features

- OTLP/HTTP server on a configurable port (default: 4318)
- Receives Traces, Metrics, and Logs from Claude Code
- Stores data in SwiftData with configurable retention period (default: 180 days)
- Visualizes Traces as a Gantt chart with span hierarchy and detail popover
- Configurable auto-start on app launch

## Requirements

- macOS 14+
- Xcode 16+

## Getting Started

1. Clone the repository and open `Teloscope.xcodeproj` in Xcode
2. Resolve Swift packages: **File → Packages → Resolve Package Versions**
3. Build and run (`Cmd+R`)
4. Click **Start Server** in the toolbar to start the OTLP server on port 4318
5. Configure Claude Code to send telemetry to the app:

```json
// ~/.claude/settings.json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_TRACES_EXPORTER": "otlp"
  }
}
```

## Developer Guide

### Dependencies

| Package | Version | Purpose |
|---|---|---|
| [swift-nio](https://github.com/apple/swift-nio) | 2.65.0+ | OTLP/HTTP server |
| [swift-protobuf](https://github.com/apple/swift-protobuf) | 1.28.0+ | Protobuf decoding |

### App Sandbox

The app runs under App Sandbox with **incoming connections** (`com.apple.security.network.server`) enabled to accept OTLP/HTTP traffic. Outgoing connections (`com.apple.security.network.client`) are **disabled in Release** but **enabled in Debug** to allow `OTLPServerTests` to make `URLSession` requests to the local test server. The Release build has no outgoing network capability.

### Regenerating Protobuf Swift files

The files under `Teloscope/Generated/` are generated from the [opentelemetry-proto](https://github.com/open-telemetry/opentelemetry-proto) definitions (v1.3.2). To regenerate them, install `protoc` and `protoc-gen-swift`, then run:

```bash
# Download opentelemetry-proto
git clone --depth 1 --branch v1.3.2 https://github.com/open-telemetry/opentelemetry-proto.git /tmp/opentelemetry-proto

# Generate Swift files
protoc \
  --proto_path=/tmp/opentelemetry-proto \
  --swift_out=Teloscope/Generated \
  opentelemetry/proto/common/v1/common.proto \
  opentelemetry/proto/resource/v1/resource.proto \
  opentelemetry/proto/trace/v1/trace.proto \
  opentelemetry/proto/metrics/v1/metrics.proto \
  opentelemetry/proto/logs/v1/logs.proto \
  opentelemetry/proto/collector/trace/v1/trace_service.proto \
  opentelemetry/proto/collector/metrics/v1/metrics_service.proto \
  opentelemetry/proto/collector/logs/v1/logs_service.proto
```

Install dependencies via Homebrew if needed:

```bash
brew install protobuf
brew install swift-protobuf  # installs protoc-gen-swift
```
