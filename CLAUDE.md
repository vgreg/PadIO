# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a native macOS app with no Makefile or package manager. All builds go through Xcode:

- **Build:** Use the `BuildProject` MCP tool, or open `PadIO.xcodeproj` and press ⌘B
- **Run:** ⌘R in Xcode — launches as a menu bar app (no main window)
- **Validate code quickly:** Use `XcodeRefreshCodeIssuesInFile` for fast compiler feedback without a full build
- **Test snippets:** Use `ExecuteSnippet` to run code in the context of a specific file

There are no automated tests. The app requires Accessibility permission at runtime to emit synthetic events.

The live config file is `~/.config/padio/config.json` — it hot-reloads automatically when saved. A sample config is at `config.json` in the repo root.

## Architecture Overview

PadIO is a **menu bar daemon** that maps game controller inputs to synthetic macOS events. It has no main window — the entire UI is a menu bar dropdown (`MenuBarExtra`).

### Entry Point & Ownership

`PadIOApp.swift` creates a single `ControllerManager` as a `@StateObject`. All sub-components live inside `ControllerManager` and are injected into SwiftUI as environment objects.

### Core Data Flow

```
GCController (GameController framework)
  ↓  [60Hz polling timer in ControllerManager]
pollControllers()
  ├─ Edge-detect button presses → handleMappedButton()
  │     ├─ Overlay priority: helpOverlay → modePicker → customMenu → menu button
  │     ├─ MappingResolver.resolve(heldButtons:) — applies cascade:
  │     │     1–3. combo keys (modifier+button) through global → profile → mode
  │     │     4–6. plain keys through global → profile → mode
  │     └─ executeAction() → InputHandler / overlays / HapticController
  └─ pollAxes() — continuous axis → mouse/scroll emission (skipped when overlay visible)
```

### Component Responsibilities

| File | Role |
|------|------|
| `ControllerManager.swift` | Central orchestrator — owns all sub-components, drives the 60Hz loop, resolves and executes actions |
| `MappingResolver.swift` | Pure translation layer — config → `Action` enum; contains all key name and modifier mappings |
| `MappingConfig.swift` | Codable config types + `ConfigLoader` (hot-reload via `DispatchSource`) |
| `InputHandler.swift` | Low-level CGEvent emission — keystrokes, text injection, mouse, scroll, media keys, input source cycling |
| `HapticController.swift` | `CHHapticEngine` management per controller + `HapticEventObserver` for system beep / notification triggers |
| `AppObserver.swift` | Tracks frontmost app bundle ID via `NSWorkspace`; publishes changes to trigger profile re-resolution |
| `ButtonIdentifier.swift` | `ButtonID` and `AxisID` enums; maps `GCControllerElement` references to canonical names |
| `ContentView.swift` | Menu bar dropdown UI — status display, permission grant, reload/quit |
| `*Overlay.swift` files | Floating `NSPanel` HUDs, each with a SwiftUI view + `@Observable` view model + controller class |

### Config Resolution Cascade

Profile is selected by matching the frontmost app's bundle ID against `profile.apps[]`, falling back to the `"default"` profile. Within a profile, bindings resolve in this priority order (highest wins):

1. Combo key (`modifier+button`) in top-level `config.global`
2. Combo key in `profile.global`
3. Combo key in active mode bindings
4. Plain key in top-level `config.global`
5. Plain key in `profile.global`
6. Plain key in active mode bindings (`profile.modes[activeModeString]`)

Combo keys use the syntax `"<modifier>+<button>"` (e.g., `"X+dpad_up"`) in any bindings dictionary. When multiple buttons are held, `ButtonID.allCases` order determines which modifier is tried first.

Mode state is stored in `ControllerManager.profileModes: [profileName: modeName]`.

### Overlay Priority

While an overlay is visible, input is consumed before reaching the mapping pipeline:

1. `HelpController` — blocks **all** input while visible
2. `ModePickerController` — blocks input while visible
3. `CustomMenuController` — blocks input while visible
4. `menu` button always opens Help (checked before any mapping)

Axis events (`pollAxes`) are suppressed entirely while any overlay is visible.

### Action Types

`Action` is an enum in `MappingResolver.swift`. `buildAction(from: ActionConfig)` converts JSON config into `Action` values. Adding a new action type requires:

1. New `case` in the `Action` enum
2. New `case` in `buildAction()` switch
3. New `case` in `describe()` switch
4. New `case` in `ControllerManager.executeAction()` switch

### Haptics

`HapticController` caches `CHHapticEngine` instances keyed by `(ObjectIdentifier(controller), GCHapticsLocality)`. Engines are created via `GCDeviceHaptics.createEngine(withLocality:)` — not `CHHapticEngine()` directly. `HapticEventObserver` listens to `DistributedNotificationCenter` for system beep (`com.apple.sound.alert.played`) and notification (`com.apple.usernotifications.notification-posted`) events.

## Documentation

When making changes to config format, action types, button names, or any user-facing behavior, always update:

1. **`README.md`** — if the change affects the quick-start or feature list
2. **`docs/`** — the relevant MkDocs documentation page(s)
3. **`config.json`** — the sample config in the repo root, if applicable

The docs site is built with MkDocs Material (`mkdocs.yml`). Preview locally with `uv run --with mkdocs-material mkdocs serve`.

## Key Conventions

- All UI and state manipulation is `@MainActor`. Use `MainActor.assumeIsolated { }` inside completion handlers (e.g. `NSAnimationContext`, `DispatchWorkItem`) that need access to main-actor state.
- `Combine` is used only for reactive bindings in `ControllerManager.init()` (config reload, frontmost app changes). New async work should use Swift async/await, not Combine.
- Overlay controllers follow the pattern: `@Observable` view model + SwiftUI view + `@MainActor` controller class owning an `NSPanel`.
- `AxisID` raw values (`"left_stick"`, `"right_stick"`, `"dpad"`) are used as binding keys in the config alongside `ButtonID` raw values — they share the same bindings dictionary.
