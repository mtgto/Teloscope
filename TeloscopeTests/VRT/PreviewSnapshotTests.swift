// SPDX-License-Identifier: MIT
import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Teloscope

@Suite @MainActor struct PreviewSnapshotTests {
    // Fixed reference date for deterministic snapshots.
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14

    // NSTemporaryDirectory is writable inside the App Sandbox (redirects to container tmp).
    static let outputDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VRTSnapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        print("VRT output: \(dir.path)")
        return dir
    }()

    private func renderSnapshot<V: View>(_ view: V, name: String) {
        let renderer = ImageRenderer(content: view.preferredColorScheme(.light))
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Rendering failed for \(name)")
            return
        }
        let dest = Self.outputDir.appendingPathComponent("\(name).png")
        do {
            try png.write(to: dest)
        } catch {
            Issue.record("Write failed for \(name): \(error)")
        }
    }

    // MARK: - PieWidgetView

    @Test func pieWidgetView_default() {
        renderSnapshot(
            PieWidgetView(
                title: "Approval Rate",
                slices: [
                    PieSlice(label: "Approved (35)", value: 35, color: .green),
                    PieSlice(label: "Rejected (10)", value: 10, color: .red),
                ],
                centerLabel: "78%"
            )
            .frame(width: 260)
            .padding(),
            name: "pieWidgetView_default"
        )
    }

    @Test func pieWidgetView_noData() {
        renderSnapshot(
            PieWidgetView(title: "Approval Rate", slices: [], centerLabel: nil)
                .frame(width: 260)
                .padding(),
            name: "pieWidgetView_noData"
        )
    }

    @Test func pieWidgetView_loading() {
        renderSnapshot(
            PieWidgetView(title: "Approval Rate", slices: [], centerLabel: nil)
                .redacted(reason: .placeholder)
                .frame(width: 260)
                .padding(),
            name: "pieWidgetView_loading"
        )
    }

    // MARK: - LineWidgetView

    private var lineSampleDates: [Date] {
        (0..<24).map {
            Calendar.current.date(byAdding: .hour, value: $0,
                                  to: Calendar.current.startOfDay(for: referenceDate))!
        }
    }

    @Test func lineWidgetView_multiSeries() {
        let dates = lineSampleDates
        renderSnapshot(
            LineWidgetView(
                title: "Tokens Over Time",
                series: [
                    LineSeries(label: "Input Tokens", color: .blue,
                               dataPoints: dates.enumerated().map { i, d in (date: d, value: Double(i * 1200 + 800)) }),
                    LineSeries(label: "Output Tokens", color: .green,
                               dataPoints: dates.enumerated().map { i, d in (date: d, value: Double(i * 400 + 200)) }),
                ],
                yAxisLabel: "tokens",
                granularity: .hourly,
                xDomain: dates.first!...dates.last!
            )
            .frame(width: 300)
            .padding(),
            name: "lineWidgetView_multiSeries"
        )
    }

    @Test func lineWidgetView_singleSeries() {
        let dates = lineSampleDates
        renderSnapshot(
            LineWidgetView(
                title: "Cost Over Time",
                series: [
                    LineSeries(label: "Cost", color: .orange,
                               dataPoints: dates.enumerated().map { i, d in (date: d, value: Double(i) * 0.012) }),
                ],
                yAxisLabel: "USD",
                granularity: .hourly,
                xDomain: dates.first!...dates.last!
            )
            .frame(width: 300)
            .padding(),
            name: "lineWidgetView_singleSeries"
        )
    }

    @Test func lineWidgetView_withGaps() {
        let dates = lineSampleDates
        let gapped: [(date: Date, value: Double)] = dates.enumerated().compactMap { i, d in
            guard !(0...3).contains(i), !(10...13).contains(i), !(20...23).contains(i) else { return nil }
            return (date: d, value: Double(i * 1200 + 800))
        }
        renderSnapshot(
            LineWidgetView(
                title: "Tokens Over Time",
                series: [LineSeries(label: "Input Tokens", color: .blue, dataPoints: gapped)],
                yAxisLabel: "tokens",
                granularity: .hourly,
                xDomain: dates.first!...dates.last!
            )
            .frame(width: 300)
            .padding(),
            name: "lineWidgetView_withGaps"
        )
    }

    @Test func lineWidgetView_loading() {
        let dates = lineSampleDates
        renderSnapshot(
            LineWidgetView(
                title: "Tokens Over Time",
                series: [],
                yAxisLabel: "tokens",
                granularity: .hourly,
                xDomain: dates.first!...dates.last!
            )
            .redacted(reason: .placeholder)
            .frame(width: 300)
            .padding(),
            name: "lineWidgetView_loading"
        )
    }

    // MARK: - BarWidgetView

    @Test func barWidgetView_default() {
        renderSnapshot(
            BarWidgetView(
                title: "Tool Usage",
                items: [
                    (name: "bash",  count: 42),
                    (name: "read",  count: 38),
                    (name: "write", count: 21),
                    (name: "edit",  count: 17),
                    (name: "grep",  count: 9),
                ]
            )
            .frame(width: 220)
            .padding(),
            name: "barWidgetView_default"
        )
    }

    @Test func barWidgetView_empty() {
        renderSnapshot(
            BarWidgetView(title: "Tool Usage", items: [])
                .frame(width: 220)
                .padding(),
            name: "barWidgetView_empty"
        )
    }

    @Test func barWidgetView_loading() {
        renderSnapshot(
            BarWidgetView(title: "Tool Usage", items: [])
                .redacted(reason: .placeholder)
                .frame(width: 220)
                .padding(),
            name: "barWidgetView_loading"
        )
    }

    // MARK: - StatWidgetView

    @Test func statWidgetView_default() {
        renderSnapshot(
            StatWidgetView(
                title: "Total Tokens",
                primaryValue: "1,234,567",
                rows: [
                    (label: "Input",      value: "800,000"),
                    (label: "Output",     value: "400,000"),
                    (label: "Cache Read", value: "34,567"),
                ]
            )
            .frame(width: 220)
            .padding(),
            name: "statWidgetView_default"
        )
    }

    @Test func statWidgetView_emptyRows() {
        renderSnapshot(
            StatWidgetView(title: "Total Cost", primaryValue: "$12.34", rows: [])
                .frame(width: 220)
                .padding(),
            name: "statWidgetView_emptyRows"
        )
    }

    @Test func statWidgetView_loading() {
        renderSnapshot(
            StatWidgetView(
                title: "Total Tokens",
                primaryValue: "000,000",
                rows: [
                    (label: "Input",      value: "000,000"),
                    (label: "Output",     value: "000,000"),
                    (label: "Cache Read", value: "000,000"),
                ]
            )
            .redacted(reason: .placeholder)
            .frame(width: 220)
            .padding(),
            name: "statWidgetView_loading"
        )
    }

    // MARK: - HeatmapWidgetView

    // Fixed counts to keep snapshots deterministic (avoids Int.random).
    private var heatmapFixedEntries: [(weekday: Int, hour: Int, count: Int)] {
        let counts = [3, 7, 2, 8, 5, 1, 9, 4, 6, 10]
        var entries: [(weekday: Int, hour: Int, count: Int)] = []
        var i = 0
        for wd in 2...6 {
            for hr in 9...17 {
                entries.append((weekday: wd, hour: hr, count: counts[i % counts.count]))
                i += 1
            }
        }
        entries.append((weekday: 1, hour: 20, count: 3))
        return entries
    }

    @Test func heatmapWidgetView_monFirst() {
        renderSnapshot(
            HeatmapWidgetView(title: "Usage by Time", data: heatmapFixedEntries)
                .frame(width: 300)
                .padding(),
            name: "heatmapWidgetView_monFirst"
        )
    }

    @Test func heatmapWidgetView_sunFirst() {
        let store = UserDefaults(suiteName: "vrt.preview.sunFirst")!
        store.set(1, forKey: "weekStartDay")
        defer { store.removePersistentDomain(forName: "vrt.preview.sunFirst") }
        renderSnapshot(
            HeatmapWidgetView(title: "Usage by Time", data: heatmapFixedEntries)
                .defaultAppStorage(store)
                .frame(width: 300)
                .padding(),
            name: "heatmapWidgetView_sunFirst"
        )
    }

    @Test func heatmapWidgetView_empty() {
        renderSnapshot(
            HeatmapWidgetView(title: "Usage by Time", data: [])
                .frame(width: 300)
                .padding(),
            name: "heatmapWidgetView_empty"
        )
    }

    @Test func heatmapWidgetView_loading() {
        renderSnapshot(
            HeatmapWidgetView(title: "Usage by Time", data: [])
                .redacted(reason: .placeholder)
                .frame(width: 300)
                .padding(),
            name: "heatmapWidgetView_loading"
        )
    }

    // MARK: - SetupGuideView

    @Test func setupGuideView_default() {
        renderSnapshot(
            SetupGuideView()
                .environment(AppSettings())
                .environment(OTLPServer()),
            name: "setupGuideView_default"
        )
    }

    // MARK: - SettingsView

    @Test func settingsView_default() {
        renderSnapshot(
            SettingsView()
                .environment(AppSettings())
                .environment(OTLPServer()),
            name: "settingsView_default"
        )
    }

    // MARK: - GanttChartView

    @Test func ganttChartView_default() {
        let spans = [
            OTLPSpan(traceId: "t1", spanId: "s1", name: "root", kind: .server,
                     startTime: referenceDate, endTime: referenceDate.addingTimeInterval(0.5),
                     status: .ok),
            OTLPSpan(traceId: "t1", spanId: "s2", parentSpanId: "s1", name: "child-1",
                     kind: .internal, startTime: referenceDate.addingTimeInterval(0.05),
                     endTime: referenceDate.addingTimeInterval(0.2)),
            OTLPSpan(traceId: "t1", spanId: "s3", parentSpanId: "s1", name: "child-2",
                     kind: .client, startTime: referenceDate.addingTimeInterval(0.25),
                     endTime: referenceDate.addingTimeInterval(0.45), status: .error),
        ]
        renderSnapshot(
            GanttChartView(spans: spans)
                .frame(width: 600, height: 300),
            name: "ganttChartView_default"
        )
    }

    // MARK: - TraceListView

    @Test func traceListView_default() throws {
        let container = try ModelContainer(
            for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
                ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self, LogEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        renderSnapshot(
            TraceListView()
                .modelContainer(container)
                .frame(width: 800, height: 500),
            name: "traceListView_default"
        )
    }

    // MARK: - MetricsView

    @Test func metricsView_default() throws {
        let container = try ModelContainer(
            for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
                ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self, LogEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        renderSnapshot(
            MetricsView()
                .modelContainer(container)
                .frame(width: 900, height: 600),
            name: "metricsView_default"
        )
    }
}
