# Window Lifecycle Design

**Date:** 2026-04-19  
**Status:** Approved

## Overview

Change the app so that closing the main window does not terminate the app. The app remains running in the Dock, and clicking the Dock icon restores the window.

## Requirements

- Closing the main window keeps the app alive (OTLP server continues running)
- Clicking the Dock icon restores the window if it is not visible
- No menu bar icon
- Single window only (no duplicate windows)

## Architecture

Replace the `Window` scene with `WindowGroup` in `TeloscopeApp`, and add an `AppDelegate` via `@NSApplicationDelegateAdaptor` to control lifecycle behavior.

```
TeloscopeApp
  ├── @NSApplicationDelegateAdaptor → AppDelegate
  └── WindowGroup("Teloscope", id: "main")
        └── MainView (unchanged)

AppDelegate
  ├── applicationShouldTerminateAfterLastWindowClosed → false
  └── applicationShouldHandleReopen → restore window if not visible
```

## Changes

### `Teloscope/TeloscopeApp.swift`

- Add `@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate`
- Change `Window("Teloscope", id: "main")` to `WindowGroup("Teloscope", id: "main")`

### New file: `Teloscope/AppDelegate.swift`

```swift
// SPDX-License-Identifier: MIT
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
```

## Notes

`WindowGroup` technically allows multiple windows, but this app has no "File > New Window" entry point, so duplicate windows are not a concern in practice. If unwanted menu items appear, suppress them with `commandsRemoved()` on the scene.

## Out of Scope

- Menu bar icon / `MenuBarExtra`
- Settings to toggle window-close behavior
