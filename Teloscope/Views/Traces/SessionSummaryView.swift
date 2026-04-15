// SPDX-License-Identifier: MIT
import SwiftUI

// MARK: - Attribute helpers

private func int64Attr(_ span: OTLPSpan, _ key: String) -> Int64? {
    guard case .int64(let v) = span.attributes.first(where: { $0.key == key })?.value else { return nil }
    return v
}

private func stringAttr(_ span: OTLPSpan, _ key: String) -> String? {
    guard case .string(let v) = span.attributes.first(where: { $0.key == key })?.value else { return nil }
    return v
}

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
        var hasDecisionData = false

        let approvedValues = Set(["accept"])
        let rejectedValues = Set(["reject"])

        for span in spans {
            if span.name.hasPrefix("claude_code.llm_request") {
                inputTokens += int64Attr(span, "input_tokens") ?? 0
                outputTokens += int64Attr(span, "output_tokens") ?? 0
                cacheReadTokens += int64Attr(span, "cache_read_tokens") ?? 0
                llmRequestCount += 1
            } else if span.name.hasPrefix("claude_code.tool.blocked_on_user") {
                hasDecisionData = true
                let decision = stringAttr(span, "decision")?.lowercased() ?? ""
                if approvedValues.contains(decision) {
                    approvedCount += 1
                } else if rejectedValues.contains(decision) {
                    rejectedCount += 1
                }
            } else if span.name == "claude_code.tool" {
                if let toolName = stringAttr(span, "tool_name") {
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
        self.hasDecisionData = hasDecisionData
        self.totalSpanCount = spans.count

        let start = spans.map(\.startTime).min() ?? Date()
        let end = spans.map(\.endTime).max() ?? Date()
        self.sessionDuration = end.timeIntervalSince(start)
    }
}

// MARK: - SessionSummaryView

struct SessionSummaryView: View {
    let spans: [OTLPSpan]

    private var summary: SessionSummary { SessionSummary(spans: spans) }

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
                        LabeledValue(label: tool.name, value: "\(tool.count)")
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
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).font(.caption)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }
}
