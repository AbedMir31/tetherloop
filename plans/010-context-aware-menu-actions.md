# Plan 010: Gray out "Return to Wi-Fi" when already on Wi-Fi and "Try Hotspot Now" when already on hotspot

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0056f96..HEAD -- Sources/TetherLoopCore/App/AppModel.swift Sources/TetherLoopCore/UI/MenuBar/TetherLoopMenu.swift Tests/TetherLoopTests/ViewModelTests.swift`
> Written against commit `0056f96` (all of plans 001–009 landed).

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans 001–009 (all DONE)
- **Category**: bug (UX / PRD story 15 clarity)
- **Planned at**: commit `0056f96`, 2026-06-12

## Why this matters

The menu always offers both "Try Hotspot Now" and "Return to Wi-Fi", regardless of where the Mac currently is. A user already on their trusted Wi-Fi can click "Return to Wi-Fi" (a no-op dressed as an action), and a user already on the hotspot can click "Try Hotspot Now" (ditto). Maintainer request: gray out the action that matches the network you are already on, to reduce confusion.

Enabler fix included: the published `currentSSID` is only updated inside `refreshNetworkChoices()` (which runs when the Settings/Setup windows load networks) — `pollNetwork()` computes the current SSID every 5 seconds but never publishes it. The menu therefore has no live signal to base disable-state on. Publishing it from the poll loop is the substantive change; the menu bindings are trivial after that.

## Current state

- `Sources/TetherLoopCore/App/AppModel.swift`:
  - `@Published public private(set) var currentSSID: String?` (line ~16) — written only at `refreshNetworkChoices()` (line ~181: `currentSSID = detectedCurrentSSID`).
  - `pollNetwork()` (line ~330s region) computes a local `current: String?` from `networkAdapter.currentNetwork()` with three branches: `.associated(ssid?)` → `current = ssid`; `.associated(nil)` → early `return` (SSID unreadable, do NOT treat as disconnect); `.disconnected` → `current = nil`.
  - `settings.hotspotSSID: String?`, `settings.trustedSSIDs: Set<String>`.
- `Sources/TetherLoopCore/UI/MenuBar/TetherLoopMenu.swift` — the two buttons today:

```swift
Button("Try Hotspot Now", systemImage: "antenna.radiowaves.left.and.right") {
    model.tryHotspotNow()
}
Button("Return to Wi-Fi", systemImage: "wifi") {
    Task { await model.returnToWiFi() }
}
```

(`Protect Now` directly above already uses `.disabled(!model.settings.isSetupVerified)` — match that pattern.)

- Test conventions (`Tests/TetherLoopTests/ViewModelTests.swift`): `@MainActor` XCTest; `AppModel(...)` constructions pass `locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)`; join-exercising tests pass `joinConfirmationAttempts: 2, joinConfirmationDelay: .zero`; `FakeNetworkAdapter` has `current`, `associatedWithoutSSID`, `joinSetsCurrent`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| All tests | `swift test` | exit 0 (80 baseline + 3 new = 83) |
| Screenshots | `swift run GenerateScreenshots` | exit 0 |

## Scope

**In scope** (the only files you may modify):
- `Sources/TetherLoopCore/App/AppModel.swift`
- `Sources/TetherLoopCore/UI/MenuBar/TetherLoopMenu.swift`
- `Tests/TetherLoopTests/ViewModelTests.swift`
- `assets/screenshots/*` (regenerated only, if the generator produces changes)

**Out of scope** (do NOT touch):
- `pollNetwork()`'s failover/event logic — only ADD the `currentSSID` publication; do not reorder events, guards, or the `.associated(nil)` early return.
- The other menu items' enable/disable behavior ("Pause Protection" etc.).
- `refreshNetworkChoices()`.

## Steps

### Step 1: Publish `currentSSID` from `pollNetwork()` and add placement properties

In `AppModel.swift`, inside `pollNetwork()`, after the `switch state` resolves the local `current` (i.e., in the `.associated(ssid?)` and `.disconnected` paths — NOT the `.associated(nil)` early-return path, where the SSID is unknown and the last known value should stand), publish it:

```swift
currentSSID = current
```

Place this immediately after the `switch` block, before `defer { previousSSID = current }`. The `.associated(nil)` branch `return`s before reaching it, which is exactly the desired behavior.

Then add two public computed properties near the other computed vars (`trustedSSIDs`, `selectableSSIDs`):

```swift
public var isOnHotspot: Bool {
    guard let currentSSID, let hotspot = settings.hotspotSSID else { return false }
    return currentSSID == hotspot
}

public var isOnTrustedWiFi: Bool {
    guard let currentSSID else { return false }
    return settings.trustedSSIDs.contains(currentSSID)
}
```

Semantics: when the SSID is unknown (disconnected or unreadable-and-never-polled), both are `false` and both menu actions stay enabled — the app must never block a recovery action it can't rule out.

**Verify**: `swift build` → exit 0; `swift test` → all 80 existing tests pass.

### Step 2: Bind the menu items

In `TetherLoopMenu.swift`:

```swift
Button("Try Hotspot Now", systemImage: "antenna.radiowaves.left.and.right") {
    model.tryHotspotNow()
}
.disabled(model.isOnHotspot || model.settings.hotspotSSID == nil)

Button("Return to Wi-Fi", systemImage: "wifi") {
    Task { await model.returnToWiFi() }
}
.disabled(model.isOnTrustedWiFi)
```

(The `hotspotSSID == nil` term also grays out "Try Hotspot Now" when no hotspot is configured — same confusion-reduction rationale; the action is guaranteed to no-op today.)

**Verify**: `swift build` → exit 0.

### Step 3: Tests

In `Tests/TetherLoopTests/ViewModelTests.swift`:

1. `testPollNetworkPublishesCurrentSSID` — verified/enabled settings, trusted "Home", hotspot "Phone"; `network.current = "Home"`, poll → assert `model.currentSSID == "Home"`, `model.isOnTrustedWiFi == true`, `model.isOnHotspot == false`. Then `network.current = nil`, poll → assert `model.currentSSID == nil` and both flags false.
2. `testFailoverToHotspotUpdatesPlacementFlags` — same setup; poll on "Home", then `network.current = nil`, poll (failover joins "Phone", fake sets `current = "Phone"`), poll once more → assert `model.currentSSID == "Phone"`, `model.isOnHotspot == true`, `model.isOnTrustedWiFi == false`.
3. `testUnreadableSSIDKeepsLastPublishedSSID` — poll on "Home" (publishes "Home"), then `network.current = nil; network.associatedWithoutSSID = true`, poll → assert `model.currentSSID == "Home"` still (early return leaves the last known value).

**Verify**: `swift test` → exit 0, 83 tests.

### Step 4: Regenerate screenshots

`swift run GenerateScreenshots` → exit 0; commit any changed files under `assets/screenshots/` along with the source.

## Test plan

Covered in Step 3 — three new `ViewModelTests` following the file's existing poll-based pattern. The SwiftUI `.disabled` bindings are not unit-tested (repo convention: no UI tests in V1; the bindings are one-liners over the tested properties).

## Done criteria

- [ ] `swift build` and `swift test` exit 0; the 3 new tests exist and pass (83 total)
- [ ] `grep -n "isOnHotspot\|isOnTrustedWiFi" Sources/TetherLoopCore/UI/MenuBar/TetherLoopMenu.swift` shows both `.disabled` bindings
- [ ] `grep -n "currentSSID = current" Sources/TetherLoopCore/App/AppModel.swift` shows the publication inside `pollNetwork()`
- [ ] `swift run GenerateScreenshots` exits 0
- [ ] Only in-scope files (+ screenshots) in the commit

## STOP conditions

- `pollNetwork()` no longer matches the three-branch shape described in "Current state".
- Any existing test fails after Step 1 — publishing `currentSSID` from the poll loop should be purely additive; a failure means some test asserts `currentSSID` stays nil after polling, which would be a real conflict to report, not patch around.

## Maintenance notes

- `currentSSID` is now updated from two places (poll loop and refresh). They can disagree for up to one poll interval; both converge on the adapter's truth. If a future change adds a third writer, consider centralizing.
- Reviewer should scrutinize the unknown-SSID semantics: both flags `false` → both actions enabled is a deliberate fail-open choice for recovery actions.
- If users report the menu feeling stale (5 s poll lag after a network change), that's another nudge toward the event-driven CWWiFiClient monitoring noted in plan 005's maintenance notes.
