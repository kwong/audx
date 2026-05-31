# AGENTS.md — audx

## Project Overview

audx is a macOS menu bar utility for switching audio input/output devices. It provides global hotkey activation, Bluetooth battery display, and idle auto-disconnect for BT audio devices.



The build script compiles all `Sources/audx/*.swift` directly with `swiftc` (not SPM). It links SwiftUI, AppKit, CoreAudio, IOBluetooth, Carbon, and UserNotifications, then produces a `.app` bundle.

Do **not** use `swift build` — there is no `Package.swift`. The project uses direct `swiftc` compilation via `./build.sh`.

## Architecture

- **audxApp.swift** — `@main` entry point, creates `AppState`
- **AppState** (in audxApp.swift) — Central coordinator. Creates all managers, owns the status bar item and popover.
- **AudioManager.swift** — Enumerates CoreAudio devices, monitors default device changes via property listeners, polls playing state (2s timer)
- **BluetoothManager.swift** — Discovers connected BT audio devices via IOBluetooth, fetches battery via `system_profiler SPBluetoothDataType -json`
- **IdleManager.swift** — Polls idle duration per BT device (30s), sends warning notification, disconnects after configurable timeout
- **HotKeyManager.swift** — Singleton using Carbon API for global keyboard shortcut
- **DeviceSelectorView.swift** — SwiftUI views for the popover UI with keyboard navigation
- **FloatingWindowController.swift** — Settings window controller

## Code Conventions

- `camelCase` for variables/functions, `PascalCase` for types
- Data models are structs conforming to `Identifiable`, `Equatable`
- Managers are classes with `ObservableObject` / `@Published`
- User preferences stored with `@AppStorage`
- Weak references used to avoid retain cycles (e.g., `IdleManager` -> `AudioManager`)
- No nested if/else — use early returns and guard clauses
- Keep functions small and single-responsibility

## Testing

No automated test suite. `test_battery.swift` and `test_bt_battery.swift` are standalone exploratory scripts for API investigation, run manually with `swift <file>`.

## Key Decisions

- Direct `swiftc` compilation instead of SPM's xcbuild
- AppKit for menu bar infrastructure, SwiftUI for view content
- Polling-based state monitoring (audio 2s, idle 30s)
- `LSUIElement: true` in Info.plist — no Dock icon, menu bar only
- Menu bar icon drawn programmatically with `NSBezierPath`
