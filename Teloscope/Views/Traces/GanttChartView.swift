// SPDX-License-Identifier: MIT
import SwiftUI
import Charts

struct GanttChartView: View {
    let spans: [OTLPSpan]
    @State private var selectedSpan: OTLPSpan?

    private var traceStart: Date {
        spans.map(\.startTime).min() ?? Date()
    }

    private func msOffset(_ date: Date) -> Double {
        date.timeIntervalSince(traceStart) * 1000
    }

    private func indentLevel(for span: OTLPSpan) -> Int {
        var level = 0
        var currentId = span.parentSpanId
        while let parentId = currentId {
            level += 1
            currentId = spans.first { $0.spanId == parentId }?.parentSpanId
            if level > 20 { break }
        }
        return level
    }

    var body: some View {
        ScrollView(.vertical) {
            Chart(spans, id: \.spanId) { span in
                BarMark(
                    xStart: .value("Start", msOffset(span.startTime)),
                    xEnd: .value("End", max(msOffset(span.endTime), msOffset(span.startTime) + 1)),
                    y: .value("Span", spanLabel(span))
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
                                selectedSpan = spans.first { spanLabel($0) == label }
                            }
                        }
                }
            }
            .frame(height: CGFloat(Set(spans.map { spanLabel($0) }).count) * 28 + 60)
            .padding()
        }
        .popover(item: $selectedSpan) { span in
            SpanDetailView(span: span)
        }
    }

    private func spanLabel(_ span: OTLPSpan) -> String {
        let indent = String(repeating: "  ", count: indentLevel(for: span))
        return "\(indent)\(span.name)"
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
