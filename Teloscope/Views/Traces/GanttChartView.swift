// SPDX-License-Identifier: MIT
import SwiftUI
import Charts

struct GanttChartView: View {
    let spans: [OTLPSpan]
    @State private var selectedSpan: OTLPSpan?

    var body: some View {
        // Precompute all span data once per render to avoid O(n²) complexity.
        // Previously, indentLevel() did an O(n) linear scan per parent hop per span.
        let traceStart = spans.map(\.startTime).min() ?? Date()
        let labelMap = buildLabelMap()
        let uniqueLabelCount = Set(labelMap.values).count

        Chart(spans, id: \.spanId) { span in
            let label = labelMap[span.spanId] ?? span.name
            BarMark(
                xStart: .value("Start", span.startTime.timeIntervalSince(traceStart) * 1000),
                xEnd: .value("End", max(span.endTime.timeIntervalSince(traceStart) * 1000,
                                       span.startTime.timeIntervalSince(traceStart) * 1000 + 1)),
                y: .value("Span", label)
            )
            .foregroundStyle(barColor(for: span))
            .cornerRadius(2)
        }
        .chartXAxisLabel("Time (ms)", alignment: .center)
        .chartYAxis {
            AxisMarks(preset: .aligned) { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        let y = location.y - geo[proxy.plotFrame!].minY
                        if let label = proxy.value(atY: y, as: String.self) {
                            selectedSpan = spans.first { (labelMap[$0.spanId] ?? $0.name) == label }
                        }
                    }
            }
        }
        .frame(height: CGFloat(uniqueLabelCount) * 28 + 60)
        .padding()
        .popover(item: $selectedSpan) { span in
            SpanDetailView(span: span)
        }
    }

    // Builds a map of spanId → indented label string in O(n) using memoized recursion.
    private func buildLabelMap() -> [String: String] {
        // Map spanId → parentSpanId for spans that have a parent
        let parentMap: [String: String] = spans.reduce(into: [:]) { dict, span in
            if let parentId = span.parentSpanId {
                dict[span.spanId] = parentId
            }
        }
        var indentCache: [String: Int] = [:]
        return spans.reduce(into: [:]) { dict, span in
            let level = computeIndentLevel(spanId: span.spanId, parentMap: parentMap, cache: &indentCache)
            let indent = String(repeating: "  ", count: level)
            dict[span.spanId] = "\(indent)\(span.name)"
        }
    }

    // Computes indent level using memoization. The sentinel value (cache[spanId] = 0 before
    // recursing) breaks any unexpected cycles in the span parent chain.
    private func computeIndentLevel(
        spanId: String,
        parentMap: [String: String],
        cache: inout [String: Int]
    ) -> Int {
        if let cached = cache[spanId] { return cached }
        cache[spanId] = 0  // Sentinel: breaks cycles, default root level
        let level: Int
        if let parentId = parentMap[spanId] {
            level = min(computeIndentLevel(spanId: parentId, parentMap: parentMap, cache: &cache) + 1, 20)
        } else {
            level = 0
        }
        cache[spanId] = level
        return level
    }

    private func barColor(for span: OTLPSpan) -> Color {
        // Error status always overrides name-based color
        if span.status == .error { return .red.opacity(0.8) }
        return spanNameColor(span.name).opacity(0.75)
    }

    private func spanNameColor(_ name: String) -> Color {
        switch true {
        case name.hasPrefix("claude_code.llm_request"):
            return .orange
        case name.hasPrefix("claude_code.tool.blocked_on_user"):
            return .purple
        case name.hasPrefix("claude_code.tool.execution"):
            return .teal
        case name.hasPrefix("claude_code.tool"):
            return .cyan
        default:
            // Hash the name to a stable color from a palette for unknown span types
            let palette: [Color] = [.blue, .green, .yellow, .pink, .indigo, .mint]
            let index = abs(name.hashValue) % palette.count
            return palette[index]
        }
    }
}

#Preview {
    let now = Date()
    let spans = [
        OTLPSpan(traceId: "t1", spanId: "s1", name: "root", kind: .server,
                 startTime: now, endTime: now.addingTimeInterval(0.5), status: .ok),
        OTLPSpan(traceId: "t1", spanId: "s2", parentSpanId: "s1", name: "child-1", kind: .internal,
                 startTime: now.addingTimeInterval(0.05), endTime: now.addingTimeInterval(0.2)),
        OTLPSpan(traceId: "t1", spanId: "s3", parentSpanId: "s1", name: "child-2", kind: .client,
                 startTime: now.addingTimeInterval(0.25), endTime: now.addingTimeInterval(0.45), status: .error),
    ]
    GanttChartView(spans: spans)
        .frame(width: 600, height: 300)
}
