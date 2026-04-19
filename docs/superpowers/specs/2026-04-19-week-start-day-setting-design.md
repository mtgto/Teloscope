# Week Start Day Setting

**Date:** 2026-04-19

## Overview

Allow users to choose whether the heatmap (and future MetricsView widgets) starts the week on Sunday or Monday. Default to the user's OS locale setting via `Calendar.current.firstWeekday`.

## Data Layer — AppSettings

Add `weekStartDay: Int` (Calendar convention: 1=Sunday, 2=Monday) to `AppSettings`.

In `AppSettings.init`, register the OS-derived default before reading UserDefaults:

```swift
UserDefaults.standard.register(defaults: ["weekStartDay": Calendar.current.firstWeekday])
weekStartDay = defaults.object(forKey: "weekStartDay") as? Int ?? Calendar.current.firstWeekday
```

Add `weekStartDay` to `AppSettings.save()`.

`register(defaults:)` only applies when the key has never been explicitly set, so existing users are unaffected.

## HeatmapWidgetView

Replace the hardcoded `let orderedWeekdays` with a computed `var` that reads `@AppStorage("weekStartDay")`:

```swift
@AppStorage("weekStartDay") private var weekStartDay: Int = 2

private var orderedWeekdays: [(label: String, calValue: Int)] {
    let monFirst = [("Mon",2),("Tue",3),("Wed",4),("Thu",5),("Fri",6),("Sat",7),("Sun",1)]
    let sunFirst = [("Sun",1),("Mon",2),("Tue",3),("Wed",4),("Thu",5),("Fri",6),("Sat",7)]
    return weekStartDay == 1 ? sunFirst : monFirst
}
```

The widget is self-contained — no new parameters needed. When the setting changes, SwiftUI re-renders automatically.

## SettingsView

Add a "Display" section with a `Picker`:

```swift
Section("Display") {
    Picker("Week starts on", selection: $settings.weekStartDay) {
        Text("Sunday").tag(1)
        Text("Monday").tag(2)
    }
    .onChange(of: settings.weekStartDay) { settings.save() }
}
```

## i18n (Localizable.xcstrings)

| Key | Japanese |
|-----|----------|
| `"Week starts on"` | `"週の始まりの曜日"` |
| `"Sunday"` | `"日曜日"` |
| `"Monday"` | `"月曜日"` |
| `"Display"` | `"表示"` |

## Future Use

Other MetricsView widgets that need week-awareness can use `@AppStorage("weekStartDay")` directly with the same key, or read it from `AppSettings` via environment — both stay in sync through UserDefaults.
