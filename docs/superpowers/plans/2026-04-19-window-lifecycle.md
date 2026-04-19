# Window Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the app running after the main window is closed, and restore the window when the user clicks the Dock icon.

**Architecture:** Replace the `Window` scene with `WindowGroup` in `TeloscopeApp`, and add an `AppDelegate` via `@NSApplicationDelegateAdaptor` to return `false` from `applicationShouldTerminateAfterLastWindowClosed` and handle Dock icon clicks.

**Tech Stack:** SwiftUI (`WindowGroup`), AppKit (`NSApplicationDelegate`, `NSApplication`)

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `Teloscope/TeloscopeApp.swift` | Add `@NSApplicationDelegateAdaptor`; change `Window` → `WindowGroup` |
| Create | `Teloscope/AppDelegate.swift` | Prevent app quit on window close; restore window on Dock click |

---

### Task 1: Create AppDelegate

**Files:**
- Create: `Teloscope/AppDelegate.swift`

This file implements two `NSApplicationDelegate` methods:
- `applicationShouldTerminateAfterLastWindowClosed` → return `false` so closing the window does not quit the app
- `applicationShouldHandleReopen(_:hasVisibleWindows:)` → if no window is visible, call `makeKeyAndOrderFront` on the first window to restore it

- [ ] **Step 1: Create `Teloscope/AppDelegate.swift`**

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

- [ ] **Step 2: Verify the file compiles**

Open the project in Xcode and confirm no compile errors, or run:

```bash
xcodebuild -scheme Teloscope build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Teloscope/AppDelegate.swift
git commit -m "feat: add AppDelegate to control window lifecycle"
```

---

### Task 2: Wire AppDelegate into TeloscopeApp and switch to WindowGroup

**Files:**
- Modify: `Teloscope/TeloscopeApp.swift`

Add `@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate` as a property on `TeloscopeApp`, and change `Window("Teloscope", id: "main")` to `WindowGroup("Teloscope", id: "main")`.

- [ ] **Step 1: Edit `Teloscope/TeloscopeApp.swift`**

Apply the following diff (the rest of the file is unchanged):

```swift
@main
struct TeloscopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate  // add this line

    let sharedModelContainer: ModelContainer = { ... }()

    @State private var settings = AppSettings()
    @State private var server = OTLPServer()

    var body: some Scene {
        WindowGroup("Teloscope", id: "main") {  // Window → WindowGroup
            MainView()
                ...
        }
        .modelContainer(sharedModelContainer)
    }
    ...
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild -scheme Teloscope build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual smoke test**

1. Run the app in Xcode.
2. Close the main window (red ✕ button).
3. Confirm the app stays in the Dock (does **not** quit).
4. Click the Dock icon.
5. Confirm the window reappears.

- [ ] **Step 4: Commit**

```bash
git add Teloscope/TeloscopeApp.swift
git commit -m "feat: switch to WindowGroup and wire AppDelegate for persistent window lifecycle"
```
