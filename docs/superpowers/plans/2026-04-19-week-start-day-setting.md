# Week Start Day Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users choose Sunday or Monday as the heatmap week start, defaulting to their OS locale setting.

**Architecture:** `weekStartDay` (Int, Calendar convention: 1=Sun / 2=Mon) is added to `AppSettings` with `register(defaults:)` seeding the OS value. `HeatmapWidgetView` reads the same UserDefaults key via `@AppStorage` and computes `orderedWeekdays` dynamically. `SettingsView` exposes a Picker in a new "Display" section.

**Tech Stack:** Swift, SwiftUI (`@AppStorage`), Swift Testing

---

### Task 1: Add weekStartDay to AppSettings

**Files:**
- Modify: `Teloscope/Settings/AppSettings.swift`
- Modify: `TeloscopeTests/Settings/AppSettingsTests.swift`

- [ ] **Step 1: Write failing tests for weekStartDay**

Add to `TeloscopeTests/Settings/AppSettingsTests.swift` after the existing `persistsValues` test:

```swift
@Test func weekStartDayDefaultsToSystemCalendar() {
    let defaults = UserDefaults(suiteName: "test.AppSettingsTests.\(UUID().uuidString)")!
    let settings = AppSettings(defaults: defaults)
    #expect(settings.weekStartDay == Calendar.current.firstWeekday)
}

@Test func weekStartDayPersists() {
    let suiteName = "test.AppSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let settings = AppSettings(defaults: defaults)
    settings.weekStartDay = 1
    settings.save()

    let settings2 = AppSettings(defaults: defaults)
    #expect(settings2.weekStartDay == 1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

In Xcode: Product → Test (⌘U), or run `xcodebuild test -scheme Teloscope -destination 'platform=macOS'` and confirm the two new tests fail with "weekStartDay not found".

- [ ] **Step 3: Implement weekStartDay in AppSettings**

Replace the entire content of `Teloscope/Settings/AppSettings.swift`:

```swift
// SPDX-License-Identifier: MIT
import Foundation
import Observation

@Observable
final class AppSettings {
    var port: Int
    var autoStart: Bool
    var retentionDays: Int
    var weekStartDay: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["weekStartDay": Calendar.current.firstWeekday])
        port = defaults.object(forKey: "serverPort") as? Int ?? 4318
        autoStart = defaults.bool(forKey: "autoStart")
        retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 180
        weekStartDay = defaults.object(forKey: "weekStartDay") as? Int ?? Calendar.current.firstWeekday
    }

    func save() {
        defaults.set(port, forKey: "serverPort")
        defaults.set(autoStart, forKey: "autoStart")
        defaults.set(retentionDays, forKey: "retentionDays")
        defaults.set(weekStartDay, forKey: "weekStartDay")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run ⌘U and confirm `weekStartDayDefaultsToSystemCalendar` and `weekStartDayPersists` both pass.

- [ ] **Step 5: Commit**

```bash
git add Teloscope/Settings/AppSettings.swift TeloscopeTests/Settings/AppSettingsTests.swift
git commit -m "feat: add weekStartDay to AppSettings with OS locale default"
```

---

### Task 2: Make HeatmapWidgetView week-start-aware

**Files:**
- Modify: `Teloscope/Views/Metrics/HeatmapWidgetView.swift`

- [ ] **Step 1: Replace orderedWeekdays with @AppStorage-driven computed var**

Replace the entire content of `Teloscope/Views/Metrics/HeatmapWidgetView.swift`:

```swift
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
```

- [ ] **Step 2: Build and verify in Xcode previews**

Open `HeatmapWidgetView.swift` in Xcode, switch to Canvas, and confirm:
- "Mon first" preview starts with Mon at top
- "Sun first" preview starts with Sun at top

- [ ] **Step 3: Commit**

```bash
git add Teloscope/Views/Metrics/HeatmapWidgetView.swift
git commit -m "feat: make HeatmapWidgetView week-start-aware via @AppStorage"
```

---

### Task 3: Add Display section to SettingsView

**Files:**
- Modify: `Teloscope/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Add Display section with Picker**

Replace the entire content of `Teloscope/Views/Settings/SettingsView.swift`:

```swift
// SPDX-License-Identifier: MIT
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(OTLPServer.self) private var server

    private let portFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 1
        f.maximum = 65535
        f.allowsFloats = false
        f.usesGroupingSeparator = false
        return f
    }()

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Server") {
                TextField("Port", value: $settings.port, formatter: portFormatter, prompt: Text("4318"))
                    .onChange(of: settings.port) { settings.save() }
                Toggle("Start server on app launch", isOn: $settings.autoStart)
                    .onChange(of: settings.autoStart) { settings.save() }
            }
            Section("Data") {
                TextField("Retention (days)", value: $settings.retentionDays, format: .number, prompt: Text("180"))
                    .onChange(of: settings.retentionDays) { settings.save() }
            }
            Section("Display") {
                Picker("Week starts on", selection: $settings.weekStartDay) {
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                }
                .onChange(of: settings.weekStartDay) { settings.save() }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
        .environment(OTLPServer())
}
```

- [ ] **Step 2: Build and run in Xcode**

Run the app (⌘R), open Settings, and verify the "Display" section shows the "Week starts on" picker with Sunday/Monday options. Changing it should immediately update the heatmap in MetricsView.

- [ ] **Step 3: Commit**

```bash
git add Teloscope/Views/Settings/SettingsView.swift
git commit -m "feat: add week start day picker to SettingsView"
```

---

### Task 4: Add i18n strings

**Files:**
- Modify: `Teloscope/Localizable.xcstrings`

- [ ] **Step 1: Add four new Japanese translations**

In `Teloscope/Localizable.xcstrings`, add the following four entries in alphabetical key order:

After `"Data"` entry, add `"Display"`:
```json
"Display" : {
  "localizations" : {
    "ja" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "表示"
      }
    }
  }
},
```

After `"Model:"` entry, add `"Monday"`:
```json
"Monday" : {
  "localizations" : {
    "ja" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "月曜日"
      }
    }
  }
},
```

After `"Sun"` entry, add `"Sunday"`:
```json
"Sunday" : {
  "localizations" : {
    "ja" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "日曜日"
      }
    }
  }
},
```

After `"Value"` entry, add `"Week starts on"`:
```json
"Week starts on" : {
  "localizations" : {
    "ja" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "週の始まりの曜日"
      }
    }
  }
}
```

- [ ] **Step 2: Build and verify**

Run ⌘B. If the macOS system language is Japanese, confirm the Settings view shows Japanese labels. If English, confirm English labels appear.

- [ ] **Step 3: Commit**

```bash
git add Teloscope/Localizable.xcstrings
git commit -m "i18n: add Japanese translations for week start day setting"
```
