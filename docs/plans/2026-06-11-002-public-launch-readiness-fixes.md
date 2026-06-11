---
title: TetherLoop Public Launch Readiness Fixes
type: fix
date: 2026-06-11
execution: code
origin: docs/plans/2026-06-11-tetherloop-v1.md
---

# TetherLoop Public Launch Readiness Fixes

## Summary

This plan closes the launch blockers found during the pre-publish review of TetherLoop Free V1. The work turns the current source preview into a GitHub-usable release by adding a real app packaging path, wiring runtime retry and return-to-Wi-Fi behavior, making global failover match the UI, and preserving the pending settings-window layout edits.

---

## Problem Frame

The current branch builds and passes tests, but several user-facing promises are incomplete. A public GitHub launch needs first-time users to find an installable app path, recover from transient hotspot join failures, return to a trusted Wi-Fi network through the advertised menu action, and trust that visible toggles do what they claim.

---

## Requirements

- R1. The repository must include a repeatable release packaging path that creates a macOS `.app` bundle with the expected menu-bar metadata.
- R2. GitHub Actions must be able to build the app bundle as a downloadable artifact for public users or release preparation.
- R3. The README must tell users how to download/build/run the app without requiring them to infer SwiftPM internals.
- R4. `Return to Wi-Fi` must attempt to rejoin a known trusted Wi-Fi network when the app has switched to a hotspot.
- R5. Hotspot join failures must schedule and execute bounded retry attempts using the existing retry policy.
- R6. Global failover must trigger when Wi-Fi disconnects even when the previous SSID was not trusted.
- R7. Existing uncommitted settings-window edits must be preserved and pushed as part of this readiness branch.
- R8. Existing privacy boundaries must remain intact: no hotspot passwords, no terminal scraping, no telemetry.

---

## Scope Boundaries

In scope:

- Shell packaging script and CI workflow updates for a zipped `.app` artifact.
- README release, install, and first-run instructions.
- Runtime app-model changes for retry scheduling and return-to-Wi-Fi joins.
- Tests for retry, return, and global failover behavior.
- The pending smaller settings window and scrollable settings tab layout.

Out of scope:

- Apple Developer ID signing, notarization, Sparkle auto-updates, or a paid Pro distribution channel.
- Privileged helper or closed-lid mode.
- Multi-hotspot fallback.
- CoreWLAN scanning beyond the current remembered-network approach.
- App Store submission.

---

## Key Technical Decisions

- **Package from SwiftPM output:** Keep the repo source-first and add a script that wraps `swift build -c release --product TetherLoop` output into a valid `.app` bundle. This avoids introducing an Xcode project only for packaging.
- **Ad-hoc local signing:** Use ad-hoc signing in the packaging script and document Gatekeeper expectations. This is acceptable for a free open-source GitHub artifact, while Developer ID signing remains a later distribution upgrade.
- **Retry scheduling in `AppModel`:** The state machine already records retry intent, but delay execution belongs in `AppModel` because it owns tasks and side effects.
- **Return target from trusted SSIDs:** Rejoin the last known trusted SSID when available, otherwise use the first configured trusted SSID. This keeps the action deterministic without adding new settings.
- **Global failover from nil SSID:** Treat a transition to no associated network as a failover trigger when global failover is enabled, regardless of whether the previous SSID was trusted.

---

## Implementation Units

### U1. Release Packaging and Documentation

- **Goal:** Add a repeatable `.app` packaging path and public-user README instructions.
- **Files:** Create `scripts/package-app.sh`; create `.github/workflows/release-artifact.yml`; modify `README.md`.
- **Patterns to follow:** Keep the manual bundle shape consistent with the local test bundle used during development: `LSUIElement`, `CFBundleIdentifier`, `CFBundleExecutable`, and macOS 14 minimum version.
- **Test scenarios:**
  - Running the packaging script produces `dist/TetherLoop.app` and `dist/TetherLoop.zip`.
  - The packaged app has executable permissions and a valid `Info.plist`.
  - GitHub workflow exposes a zipped app artifact.
- **Verification:** `scripts/package-app.sh`; `plutil -lint dist/TetherLoop.app/Contents/Info.plist`; `codesign --verify --deep --strict dist/TetherLoop.app`.

### U2. Return-to-Wi-Fi Runtime Behavior

- **Goal:** Make the menu action rejoin a trusted Wi-Fi network instead of only changing state.
- **Files:** Modify `Sources/TetherLoopCore/App/AppModel.swift`; modify `Tests/TetherLoopTests/ViewModelTests.swift`.
- **Patterns to follow:** Keep network side effects behind `NetworkAdapter` and use `FakeNetworkAdapter` for tests.
- **Test scenarios:**
  - After setup verification returns to the original trusted SSID, `Return to Wi-Fi` joins that trusted SSID.
  - If no last trusted SSID is known, `Return to Wi-Fi` joins the first configured trusted SSID.
  - If no trusted SSID exists, the action records a failure and does not call join.
- **Verification:** `swift test --filter ViewModelTests`.

### U3. Runtime Retry Scheduling

- **Goal:** Execute bounded retry attempts after hotspot join failure.
- **Files:** Modify `Sources/TetherLoopCore/Core/Protection/ProtectionStateMachine.swift`; modify `Sources/TetherLoopCore/App/AppModel.swift`; modify `Tests/TetherLoopTests/ProtectionStateMachineTests.swift`; modify `Tests/TetherLoopTests/ViewModelTests.swift`.
- **Patterns to follow:** Preserve the state machine as an intent producer and keep sleep/timer side effects in `AppModel`.
- **Test scenarios:**
  - A failed automatic hotspot join schedules a retry delay.
  - Retry timer firing attempts the hotspot join again.
  - A successful later retry transitions to `onHotspot`.
  - Pausing protection cancels pending retry work.
- **Verification:** `swift test --filter ProtectionStateMachineTests`; `swift test --filter ViewModelTests`.

### U4. Global Failover and Settings Layout

- **Goal:** Make the global failover toggle functional and preserve the pending settings-window layout changes.
- **Files:** Modify `Sources/TetherLoopCore/App/AppModel.swift`; modify `Sources/TetherLoop/TetherLoopApp.swift`; modify `Sources/TetherLoopCore/UI/Settings/SettingsView.swift`; modify `Tests/TetherLoopTests/ViewModelTests.swift`.
- **Patterns to follow:** Emit `.untrustedWiFiDisconnected` from `pollNetwork()` only when the observed transition is a disconnection and the previous SSID was not trusted.
- **Test scenarios:**
  - Trusted disconnect still joins the hotspot.
  - Untrusted disconnect joins the hotspot only when global failover is enabled.
  - Untrusted disconnect does not join when global failover is disabled.
  - Settings still fits in the smaller scrollable window.
- **Verification:** `swift test --filter ViewModelTests`; `swift test`; screenshot or live launch smoke test.

---

## Risks and Dependencies

- Packaging without Developer ID signing will still require the standard macOS trust flow for downloaded apps. The README should be explicit so users are not surprised.
- `networksetup -setairportnetwork` behavior can vary with remembered Personal Hotspot state. Retry scheduling reduces this risk but does not guarantee phone-side hotspot activation.
- Wi-Fi SSIDs are user-visible identifiers. Diagnostics must continue to stay local and avoid secrets.

---

## Documentation and Operational Notes

The public README should position the first release as an open-source GitHub build, not an App Store-style polished installer. The release artifact should be easy to download and inspect, with source build instructions adjacent to binary instructions.
