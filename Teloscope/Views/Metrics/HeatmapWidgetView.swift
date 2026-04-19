// SPDX-License-Identifier: MIT
import SwiftUI

struct HeatmapWidgetView: View {
    let title: LocalizedStringKey
    /// Flat list of (weekday, hour, count) entries. weekday uses Calendar convention: 1=Sun…7=Sat.
    let data: [(weekday: Int, hour: Int, count: Int)]

    @AppStorage("weekStartDay") private var weekStartDay: Int = 2

    // Mon–Sun or Sun–Sat display order depending on weekStartDay.
    private var orderedWeekdays: [(label: String, calValue: Int)] {
        let monFirst = [("Mon", 2), ("Tue", 3), ("Wed", 4), ("Thu", 5), ("Fri", 6), ("Sat", 7), ("Sun", 1)]
        let sunFirst = [("Sun", 1), ("Mon", 2), ("Tue", 3), ("Wed", 4), ("Thu", 5), ("Fri", 6), ("Sat", 7)]
        return weekStartDay == 1 ? sunFirst : monFirst
    }

    private let countMap: [Int: [Int: Int]]
    private let maxCount: Int

    init(title: LocalizedStringKey, data: [(weekday: Int, hour: Int, count: Int)]) {
        self.title = title
        self.data = data
        var map: [Int: [Int: Int]] = [:]
        var maxC = 0
        for entry in data {
            map[entry.weekday, default: [:]][entry.hour] = entry.count
            if entry.count > maxC { maxC = entry.count }
        }
        self.countMap = map
        self.maxCount = max(maxC, 1)
    }

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        GroupBox {
            if redactionReasons.contains(.placeholder) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.3))
                    .frame(height: 86)
            } else if data.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                let map = countMap
                let maxC = maxCount
                VStack(alignment: .leading, spacing: 2) {
                    // Weekday rows — 24 equal-width flexible cells per row
                    ForEach(orderedWeekdays, id: \.calValue) { wd in
                        HStack(spacing: 0) {
                            Text(LocalizedStringKey(wd.label))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)
                                .padding(.trailing, 2)
                            HStack(spacing: 1) {
                                ForEach(0..<24, id: \.self) { hour in
                                    let count = map[wd.calValue]?[hour] ?? 0
                                    let opacity: Double = count == 0
                                        ? 0.08
                                        : max(0.2, Double(count) / Double(maxC))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.accentColor.opacity(opacity))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 10)
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        } label: {
            Text(title).unredacted()
        }
    }
}

// MARK: - Previews

#Preview("Mon first") {
    HeatmapWidgetView(
        title: "Usage by Time",
        data: {
            var entries: [(weekday: Int, hour: Int, count: Int)] = []
            for wd in 2...6 {
                for hr in 9...17 {
                    entries.append((weekday: wd, hour: hr, count: Int.random(in: 1...10)))
                }
            }
            entries.append((weekday: 1, hour: 20, count: 3))
            return entries
        }()
    )
    .frame(width: 300)
    .padding()
}

#Preview("Sun first") {
    HeatmapWidgetView(
        title: "Usage by Time",
        data: {
            var entries: [(weekday: Int, hour: Int, count: Int)] = []
            for wd in 2...6 {
                for hr in 9...17 {
                    entries.append((weekday: wd, hour: hr, count: Int.random(in: 1...10)))
                }
            }
            entries.append((weekday: 1, hour: 20, count: 3))
            return entries
        }()
    )
    .defaultAppStorage(UserDefaults(suiteName: "preview.sunFirst")!)
    .onAppear {
        UserDefaults(suiteName: "preview.sunFirst")!.set(1, forKey: "weekStartDay")
    }
    .frame(width: 300)
    .padding()
}

#Preview("Empty") {
    HeatmapWidgetView(title: "Usage by Time", data: [])
        .frame(width: 300)
        .padding()
}

#Preview("Loading") {
    HeatmapWidgetView(title: "Usage by Time", data: [])
        .redacted(reason: .placeholder)
        .frame(width: 300)
        .padding()
}
