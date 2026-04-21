// SPDX-License-Identifier: MIT
import SwiftUI

private func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds >= 3600 {
        let h = Int(seconds / 3600)
        let m = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(h)h \(m)m"
    } else if seconds >= 60 {
        let m = Int(seconds / 60)
        let s = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(m)m \(s)s"
    } else if seconds >= 1 {
        return String(format: "%.1fs", seconds)
    } else {
        return String(format: "%.0fms", seconds * 1000)
    }
}

// MARK: - SessionSummary

struct SessionSummary {
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let llmRequestCount: Int
    let topTools: [(name: String, count: Int)]
    let approvedCount: Int
    let rejectedCount: Int
    let unknownCount: Int
    let hasDecisionData: Bool
    let sessionDuration: TimeInterval
    let totalSpanCount: Int

    init(spans: [OTLPSpan]) {
        var inputTokens: Int64 = 0
        var outputTokens: Int64 = 0
        var cacheReadTokens: Int64 = 0
        var llmRequestCount = 0
        var toolCounts: [String: Int] = [:]
        var approvedCount = 0
        var rejectedCount = 0
        var unknownCount = 0
        var hasDecisionData = false

        for span in spans {
            if span.name.hasPrefix("claude_code.llm_request") {
                inputTokens += span.inputTokens ?? 0
                outputTokens += span.outputTokens ?? 0
                cacheReadTokens += span.cacheReadTokens ?? 0
                llmRequestCount += 1
            } else if span.name.hasPrefix("claude_code.tool.blocked_on_user") {
                hasDecisionData = true
                switch span.decision?.lowercased() {
                case "accept": approvedCount += 1
                case "reject": rejectedCount += 1
                case nil:      break
                default:       unknownCount += 1
                }
            } else if span.name == "claude_code.tool" {
                // tool_name is not a typed column; fall back to SpanAttribute for display.
                if let attr = span.attributes.first(where: { $0.key == "tool_name" }),
                   case .string(let toolName) = attr.value {
                    toolCounts[toolName, default: 0] += 1
                }
            }
        }

        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.llmRequestCount = llmRequestCount
        self.topTools = toolCounts.sorted { $0.value > $1.value }.prefix(5).map { (name: $0.key, count: $0.value) }
        self.approvedCount = approvedCount
        self.rejectedCount = rejectedCount
        self.unknownCount = unknownCount
        self.hasDecisionData = hasDecisionData
        self.totalSpanCount = spans.count

        let start = spans.map(\.startTime).min() ?? Date()
        let end = spans.map(\.endTime).max() ?? Date()
        self.sessionDuration = end.timeIntervalSince(start)
    }
}

// MARK: - SessionSummaryView

struct SessionSummaryView: View {
    private let spans: [OTLPSpan]
    private let summary: SessionSummary

    init(spans: [OTLPSpan]) {
        self.spans = spans
        self.summary = SessionSummary(spans: spans)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tokensCard
            topToolsCard
            decisionsCard
            sessionInfoCard
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxHeight: 120)
    }

    private var tokensCard: some View {
        GroupBox("Tokens") {
            VStack(spacing: 2) {
                LabeledValue(label: "Input", value: summary.inputTokens.formatted(.number))
                LabeledValue(label: "Output", value: summary.outputTokens.formatted(.number))
                LabeledValue(label: "Cache read", value: summary.cacheReadTokens.formatted(.number))
                LabeledValue(label: "Requests", value: "\(summary.llmRequestCount)")
            }
        }
    }

    private var topToolsCard: some View {
        GroupBox("Top Tools") {
            if summary.topTools.isEmpty {
                Text("No data").foregroundStyle(.secondary).font(.caption)
            } else {
                VStack(spacing: 2) {
                    ForEach(summary.topTools, id: \.name) { tool in
                        HStack {
                            Text(tool.name).foregroundStyle(.secondary).font(.caption)
                            Spacer()
                            Text("\(tool.count)").font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    private var decisionsCard: some View {
        GroupBox("User Decisions") {
            if !summary.hasDecisionData {
                Text("No data").foregroundStyle(.secondary).font(.caption)
            } else {
                VStack(spacing: 2) {
                    LabeledValue(label: "Approved", value: "\(summary.approvedCount)")
                    LabeledValue(label: "Rejected", value: "\(summary.rejectedCount)")
                    if summary.unknownCount > 0 {
                        LabeledValue(label: "Unknown", value: "\(summary.unknownCount)")
                    }
                }
            }
        }
    }

    private var sessionInfoCard: some View {
        GroupBox("Session") {
            VStack(spacing: 2) {
                LabeledValue(label: "Duration", value: formatDuration(summary.sessionDuration))
                LabeledValue(label: "Spans", value: summary.totalSpanCount.formatted(.number))
            }
        }
    }
}

// MARK: - LabeledValue

private struct LabeledValue: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).font(.caption)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }
}
