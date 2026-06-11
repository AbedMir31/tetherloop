---
title: TetherLoop Free V1 Native macOS App
date: 2026-06-11
status: ready-for-agent
execution: code
origin: docs/prd/tetherloop-technical-prd.md
---

# TetherLoop Free V1 Native macOS App

## Problem Frame

TetherLoop Free V1 needs to prove the core promise from the PRD: a developer running long-lived Claude Code, Codex, or terminal work can leave a trusted Wi-Fi network and have the Mac attempt to join a previously configured hotspot without TetherLoop storing the hotspot password. The release should be credible as a free, open-source developer utility, with Pro V2 boundaries left clean for later.

The implementation must prioritize trust, testability, and clear failure states over private APIs or aggressive system mutation.

## Scope Boundaries

In scope:

- Native macOS 14+ menu bar app using Swift, SwiftUI, and AppKit.
- Swift Package layout that builds locally and in GitHub Actions.
- Multiple trusted source SSIDs.
- One saved hotspot target SSID.
- Setup flow that blocks enabling protection until a test succeeds.
- Manual Protect Now, Pause Protection, Try Hotspot Now, and Return to Wi-Fi actions.
- Basic trusted-network disconnect failover state machine with bounded retries.
- Standard idle-sleep prevention via public power assertion adapter.
- Local-only diagnostics log with redaction.
- Meaningful notifications through an adapter.
- README, MIT license, GitHub issue template, app screenshots, and X launch copy draft.

Out of scope:

- Pro licensing, trial, or payment system.
- Advanced closed-lid helper or privileged daemon.
- Sparkle auto-updates.
- Telemetry.
- Terminal contents, command output, or transcript inspection.
- Multi-hotspot fallback.
- Hotspot data guard.
- Smart auto-return.
- CLI and Shortcuts.
- Publishing the X post.

## Implementation Units

### U1: Repository and Package Foundation

Goal: Create the buildable project shell, documentation scaffolding, license, and CI foundation for a new open-source macOS app.

Files:

- Create `Package.swift`
- Create `Sources/TetherLoop/App/TetherLoopApp.swift`
- Create `Sources/TetherLoop/App/AppDelegate.swift`
- Create `Sources/TetherLoop/App/AppState.swift`
- Create `Tests/TetherLoopTests/PackageFoundationTests.swift`
- Create `.gitignore`
- Create `LICENSE`
- Create `.github/workflows/ci.yml`

Approach:

- Use a Swift Package executable product named `TetherLoop`.
- Set macOS platform to v14.
- Keep UI entry points thin and move behavior into library-like modules under `Sources/TetherLoop/Core`.
- Use Swift Testing or XCTest depending on local support; prefer XCTest if package compatibility is simpler.
- Add GitHub Actions that run `swift test` on macOS.

Test scenarios:

- Package resolves and test target imports the app modules.
- The app state initializes with safe defaults.
- CI workflow has a macOS runner and runs Swift tests.

Verification:

- `swift test` passes.
- `swift build` passes.

### U2: Settings and Domain Model

Goal: Implement durable local settings and core domain types for trusted networks, hotspot target, protection mode, and setup verification.

Files:

- Create `Sources/TetherLoop/Core/Settings/TetherLoopSettings.swift`
- Create `Sources/TetherLoop/Core/Settings/SettingsStore.swift`
- Create `Sources/TetherLoop/Core/Settings/UserDefaultsSettingsStore.swift`
- Create `Sources/TetherLoop/Core/Model/ProtectionModels.swift`
- Create `Tests/TetherLoopTests/SettingsStoreTests.swift`

Approach:

- Model settings as a Codable value type.
- Store trusted SSIDs as a set.
- Store one optional hotspot target SSID.
- Track setup verification separately from raw configuration.
- Keep launch-at-login, standard sleep prevention, global failover, and manual protection toggles explicit.
- Provide an in-memory store for tests.

Test scenarios:

- Defaults are privacy-safe and protection disabled.
- Trusted SSIDs can be added and removed without duplicates.
- Hotspot target can be set, cleared, and persisted.
- Setup verification is invalidated when hotspot target changes.
- Settings round-trip through persistence.

Verification:

- `swift test --filter SettingsStoreTests` passes.

### U3: Protection State Machine

Goal: Implement the deterministic failover state machine independent from real network, power, notification, and UI side effects.

Files:

- Create `Sources/TetherLoop/Core/Protection/ProtectionStateMachine.swift`
- Create `Sources/TetherLoop/Core/Protection/RetryPolicy.swift`
- Create `Sources/TetherLoop/Core/Protection/ProtectionCoordinator.swift`
- Create `Tests/TetherLoopTests/ProtectionStateMachineTests.swift`
- Create `Tests/TetherLoopTests/RetryPolicyTests.swift`

Approach:

- Define states: unconfigured, monitoring, protected, paused, switching, onHotspot, failed.
- Define events: settingsChanged, userProtectNow, userPause, trustedWiFiConnected, trustedWiFiDisconnected, untrustedWiFiDisconnected, hotspotJoinSucceeded, hotspotJoinFailed, retryTimerFired, userTryNow, userReturnToWiFi.
- The state machine returns intents rather than performing side effects directly.
- Retry policy uses bounded backoff: immediate, 15s, 30s, 60s, then 120s intervals up to a finite cap.

Test scenarios:

- Unverified setup cannot enter active protection.
- Trusted disconnect while monitoring emits a hotspot join intent.
- Untrusted disconnect does not fail over unless global mode or manual protection applies.
- Pause suppresses automatic failover.
- Failed join schedules the correct next retry.
- Successful join transitions to onHotspot.
- Try Now emits a join intent from failed state.

Verification:

- `swift test --filter ProtectionStateMachineTests` passes.
- `swift test --filter RetryPolicyTests` passes.

### U4: Network Adapters

Goal: Add network observation and join abstractions that support real macOS behavior while remaining testable.

Files:

- Create `Sources/TetherLoop/Core/Network/NetworkInterfaces.swift`
- Create `Sources/TetherLoop/Core/Network/SystemNetworkAdapter.swift`
- Create `Sources/TetherLoop/Core/Network/NetworkSetupClient.swift`
- Create `Tests/TetherLoopTests/NetworkSetupClientTests.swift`
- Create `Tests/TetherLoopTests/NetworkAdapterFakeTests.swift`

Approach:

- Expose a narrow interface for current SSID, Wi-Fi service/device name, preferred networks, scan visibility when available, and join target SSID.
- Use system-supported mechanisms for saved Wi-Fi joins without storing a password.
- Parse command output behind a dedicated client so parsing can be tested from sample strings.
- Keep any CoreWLAN usage behind the adapter so it can be replaced or limited if macOS permission behavior differs across machines.
- Do not mutate real networks in automated tests.

Test scenarios:

- Current SSID parser handles connected, disconnected, and unexpected command outputs.
- Preferred network parser extracts SSIDs without retaining command headers.
- Join command builder never includes a password.
- Adapter fakes can simulate disconnect, join success, and join failure.

Verification:

- `swift test --filter NetworkSetupClientTests` passes.

### U5: Power, Process, Diagnostics, and Notifications

Goal: Implement side-effect adapters for idle sleep prevention, optional process snapshots, local logs, and system notifications.

Files:

- Create `Sources/TetherLoop/Core/Power/PowerAssertionController.swift`
- Create `Sources/TetherLoop/Core/Power/SystemPowerAssertionController.swift`
- Create `Sources/TetherLoop/Core/Process/ProcessSnapshotProvider.swift`
- Create `Sources/TetherLoop/Core/Diagnostics/DiagnosticEvent.swift`
- Create `Sources/TetherLoop/Core/Diagnostics/DiagnosticLogStore.swift`
- Create `Sources/TetherLoop/Core/Notifications/NotificationDispatcher.swift`
- Create `Tests/TetherLoopTests/PowerAssertionTests.swift`
- Create `Tests/TetherLoopTests/DiagnosticsTests.swift`
- Create `Tests/TetherLoopTests/NotificationDispatcherTests.swift`

Approach:

- Power assertions are standard idle-sleep prevention only.
- Process support is basic and local; no terminal content inspection.
- Diagnostics are local-only, bounded, and redacted.
- Notifications are emitted only for meaningful state changes and failures.

Test scenarios:

- Enabling sleep prevention acquires one assertion and repeated enables do not leak assertions.
- Disabling releases any active assertion.
- Diagnostics redact sensitive strings and bound retention.
- Notifications are requested for switch success, failure, and return events only.

Verification:

- `swift test --filter PowerAssertionTests` passes.
- `swift test --filter DiagnosticsTests` passes.
- `swift test --filter NotificationDispatcherTests` passes.

### U6: Menu Bar, Onboarding, and Settings UI

Goal: Build the user-facing native macOS interface for setup, status, and control actions.

Files:

- Create `Sources/TetherLoop/UI/MenuBar/TetherLoopMenu.swift`
- Create `Sources/TetherLoop/UI/Onboarding/OnboardingView.swift`
- Create `Sources/TetherLoop/UI/Settings/SettingsView.swift`
- Create `Sources/TetherLoop/UI/Diagnostics/DiagnosticsView.swift`
- Create `Sources/TetherLoop/UI/Shared/StatusViews.swift`
- Create `Tests/TetherLoopTests/ViewModelTests.swift`

Approach:

- Use `MenuBarExtra` where practical and AppKit delegate glue where needed.
- Keep view models testable and free of real network side effects.
- Onboarding steps: choose trusted Wi-Fi, choose hotspot target, run failover test, choose protection preferences.
- Menu states: Protected, Monitoring, Switching, On Hotspot, Failed, Paused.
- Icon-only menu bar presentation by default.

Test scenarios:

- View model disables protection until required setup fields and verification are present.
- Menu actions dispatch the expected coordinator intents.
- Settings changes persist through the settings store.
- Diagnostics view reads local diagnostic entries without exposing sensitive fields.

Verification:

- `swift test --filter ViewModelTests` passes.
- Manual launch opens menu bar app and settings window.

### U7: Screenshots, README, and Marketing Copy

Goal: Prepare launch-ready open-source repository materials, including screenshots and X copy drafts without publishing.

Files:

- Create `README.md`
- Create `docs/marketing/x-launch-copy.md`
- Create `docs/marketing/positioning.md`
- Create `assets/screenshots/onboarding.png`
- Create `assets/screenshots/settings.png`
- Create `assets/screenshots/menu.png`
- Create `Scripts/generate-screenshots.swift`

Approach:

- README uses the TetherLoop positioning and embeds screenshots.
- Screenshots can be generated from app views or a lightweight screenshot renderer if local automation cannot capture the real menu bar reliably.
- X copy uses developer pain framing: long-running Claude Code/Codex jobs leaving Wi-Fi.
- Copy stops at draft artifacts. Do not publish.

Test scenarios:

- README references existing screenshot asset paths.
- Screenshot generator produces non-empty PNG files.
- Marketing copy contains clear free V1 positioning and does not overclaim closed-lid support.

Verification:

- Screenshot files exist and are non-empty.
- README renders with screenshot links.

## Sequencing

1. U1 establishes the package and CI foundation.
2. U2 creates persistent configuration.
3. U3 builds the protection state machine.
4. U4 adds network adapters behind testable boundaries.
5. U5 adds system side-effect adapters.
6. U6 wires the app UI to the coordinator.
7. U7 creates repository launch materials and screenshots.

## Risks and Mitigations

- macOS saved hotspot joins may behave differently across machines. Mitigation: isolate join backend, fail clearly, and require a user-initiated setup test.
- CoreWLAN permission behavior can be inconsistent. Mitigation: limit CoreWLAN coupling and keep command-backed fallbacks behind adapters.
- Menu bar UI is hard to screenshot in automation. Mitigation: include a screenshot generator for representative app views and manually update release screenshots later.
- Sleep prevention can be overclaimed. Mitigation: V1 says standard idle-sleep prevention only; closed-lid mode is Pro V2.
- Open-source trust can be hurt by hidden behavior. Mitigation: no telemetry, no password storage, no terminal scraping, local logs only.

## Verification Summary

- Run `swift test`.
- Run `swift build`.
- Generate screenshots and verify files are non-empty.
- Manually launch the app locally if possible.
- Confirm README and X copy do not claim Pro-only features as Free V1 behavior.
