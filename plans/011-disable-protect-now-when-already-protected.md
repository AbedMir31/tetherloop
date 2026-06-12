# Plan 011: Gray out "Protect Now" when protection is already engaged

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 5b23370..HEAD -- Sources/TetherLoopCore/App/AppModel.swift Sources/TetherLoopCore/UI/MenuBar/TetherLoopMenu.swift Tests/TetherLoopTests/ViewModelTests.swift`
> Written against commit `5b23370` (plan 010 landed). If those files already
> differ in the area this plan touches, re-read them before editing.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plan 010 (DONE, commit `5b23370`) — same menu file and the same "gray out the action that is already true" pattern
- **Category**: bug (UX inconsistency + latent status-corruption)
- **Planned at**: commit `5b23370`, 2026-06-12

## Why this matters

The menu header shows the live protection status ("Protected", "On Hotspot",
etc.), but the **"Protect Now"** command stays enabled in those states. The
maintainer observed this directly: the menu reads **Protected / Verified for
Abed's iPhone** while "Protect Now" is still clickable. Offering "Protect Now"
when you are already protected is a no-op dressed as an action — the exact
confusion plan 010 just removed for "Return to Wi-Fi" and "Try Hotspot Now".
This is the matching third case.

It is **not purely cosmetic.** `protectNow()` calls
`handle(.userProtectNow)`, and the state machine handles that event by
**unconditionally** setting `status = .protected` (when setup is verified),
regardless of the current state:

```swift
// ProtectionStateMachine.handle(_:)
case .userProtectNow:
    guard canProtect else { ... }
    status = .protected      // <-- forces .protected even from .onHotspot / .switching
    retryAttempt = 0
    ...
```

So clicking "Protect Now" while the Mac is **failed over on the hotspot**
(`status == .onHotspot`) silently relabels the status as "Protected" even
though you are really on the hotspot, and resets `retryAttempt`. Disabling the
button whenever protection is already engaged fixes both the cosmetic
inconsistency and this latent state-corruption in one change.

The states where "Protect Now" *is* still meaningful stay enabled:
`.monitoring` (protection off but setup verified — arm it), `.paused` (resume),
and `.failed` (manual re-arm / recovery after a failed join). `.unconfigured`
remains disabled through the existing `!isSetupVerified` guard.

## Current state

`Sources/TetherLoopCore/UI/MenuBar/TetherLoopMenu.swift` — the button today
(lines ~30–33):

```swift
Button("Protect Now", systemImage: "shield") {
    model.protectNow()
}
.disabled(!model.settings.isSetupVerified)
```

`Sources/TetherLoopCore/App/AppModel.swift`:

- `@Published public private(set) var status: ProtectionStatus = .unconfigured` (line ~13) — already published, so the menu re-renders on every status change.
- Existing sibling computed properties added by plan 010 (lines ~116–124), which this plan mirrors:

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

`Sources/TetherLoopCore/Core/Model/ProtectionModels.swift` — the status enum
has cases `.unconfigured, .monitoring, .protected, .paused, .switching,
.onHotspot, .failed`.

Test conventions (`Tests/TetherLoopTests/ViewModelTests.swift`): `@MainActor`
XCTest; every `AppModel(...)` construction passes
`locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)`;
join-exercising tests also pass `joinConfirmationAttempts: 2, joinConfirmationDelay: .zero`.
`model.protectNow()` and `model.pauseProtection()` are synchronous; the
failover path is driven by `await model.pollNetwork()`. See
`testProtectNowArmsFailoverEvenWhenToggleIsOff` and
`testConfirmedJoinStillSucceeds` for the exact patterns reused below.

`AppModel.preview()` (used by the screenshot generator) builds a model with
`isSetupVerified: true, isProtectionEnabled: true`, whose initial status
resolves to `.protected` — so `menu.png` is rendered in exactly the state this
plan fixes (see Step 4).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| All tests | `swift test` | exit 0 (83 baseline + 2 new = 85) |
| Screenshots | `swift run GenerateScreenshots` | exit 0 |

## Scope

**In scope** (the only files you may modify):
- `Sources/TetherLoopCore/App/AppModel.swift`
- `Sources/TetherLoopCore/UI/MenuBar/TetherLoopMenu.swift`
- `Tests/TetherLoopTests/ViewModelTests.swift`
- `assets/screenshots/menu.png` (regenerated only — see Step 4)

**Out of scope** (do NOT touch):
- `ProtectionStateMachine` — do **not** change how `.userProtectNow` is
  handled. The state machine's force-to-`.protected` behavior is relied on by
  `testProtectNowArmsFailoverEvenWhenToggleIsOff` and is correct for the states
  where the button stays enabled. This plan only prevents the button from being
  *clickable* in states where that behavior is wrong. (See STOP conditions if
  you feel tempted to "fix it properly" in the state machine.)
- The **"Pause Protection"** button's enable/disable behavior. It is always
  enabled today; leaving it so is fine and out of scope. A symmetric pass
  (disable Pause when not currently protected) is noted as a follow-up in
  Maintenance notes — do not implement it here.
- The other menu items and `pollNetwork()` / `protectNow()` logic.

## Steps

### Step 1: Add an `isProtectionActive` computed property

In `AppModel.swift`, immediately after the `isOnTrustedWiFi` property (around
line 124), add:

```swift
/// True when protection is already engaged on a network — the states where
/// "Protect Now" would be a no-op (`.protected`) or would wrongly relabel the
/// status (`.switching`, `.onHotspot`). `.monitoring`, `.paused`, and `.failed`
/// are intentionally excluded: arming / re-arming protection is meaningful there.
public var isProtectionActive: Bool {
    switch status {
    case .protected, .switching, .onHotspot:
        return true
    case .unconfigured, .monitoring, .paused, .failed:
        return false
    }
}
```

Use an exhaustive `switch` (no `default:`) so that if a future `ProtectionStatus`
case is added, the compiler forces a decision here.

**Verify**: `swift build` → exit 0; `swift test` → all 83 existing tests pass.

### Step 2: Bind the menu button

In `TetherLoopMenu.swift`, extend the existing `.disabled` on "Protect Now":

```swift
Button("Protect Now", systemImage: "shield") {
    model.protectNow()
}
.disabled(!model.settings.isSetupVerified || model.isProtectionActive)
```

Leave the other buttons unchanged.

**Verify**: `swift build` → exit 0.

### Step 3: Tests

In `Tests/TetherLoopTests/ViewModelTests.swift`, add two tests following the
file's existing patterns.

1. `testProtectionActiveTracksManualProtectAndPause` — verified setup, protection
   toggle **off** so the initial status is `.monitoring`:

   - Store: `TetherLoopSettings(trustedSSIDs: ["Home"], hotspotSSID: "Phone", isSetupVerified: true, isProtectionEnabled: false)`, `FakeNetworkAdapter()`, all the standard recording doubles, `locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)`.
   - Assert `model.status == .monitoring` and `XCTAssertFalse(model.isProtectionActive)`.
   - `model.protectNow()` → assert `model.status == .protected` and `XCTAssertTrue(model.isProtectionActive)`.
   - `model.pauseProtection()` → assert `model.status == .paused` and `XCTAssertFalse(model.isProtectionActive)`.

2. `testProtectionActiveTrueWhileOnHotspot` — drive a real failover to `.onHotspot`
   (mirror `testConfirmedJoinStillSucceeds`):

   - Store: `TetherLoopSettings(trustedSSIDs: ["Home"], hotspotSSID: "Phone", isSetupVerified: true, isProtectionEnabled: true)`, `FakeNetworkAdapter(currentSSID: "Home")`, `joinConfirmationAttempts: 2, joinConfirmationDelay: .zero`.
   - `await model.pollNetwork()`; then `network.current = nil`; `await model.pollNetwork()`.
   - Assert `model.status == .onHotspot` and `XCTAssertTrue(model.isProtectionActive)`.

`.switching` is included in `isProtectionActive` for completeness but is not
asserted on its own: `pollNetwork()` awaits the hotspot join within the same
call, so the state resolves to `.onHotspot` or `.failed` before control returns
— it is not deterministically observable from a test without injecting a hang.
That is expected; do not add timing hacks to catch it.

**Verify**: `swift test` → exit 0, 85 tests.

### Step 4: Regenerate the menu screenshot

`AppModel.preview()` renders in the `.protected` state, so this change makes
"Protect Now" appear grayed out in the generated menu image. Regenerate it:

`swift run GenerateScreenshots` → exit 0.

Expect `assets/screenshots/menu.png` to change (the README embeds it). Include
the regenerated `menu.png` in the commit. `onboarding.png` and `settings.png`
should be byte-identical — if either also changes, that is unrelated drift;
note it in your report and do not stage them.

## Test plan

Two new `ViewModelTests` (Step 3) covering `isProtectionActive == true` for
`.protected` and `.onHotspot`, and `== false` for `.monitoring` and `.paused`.
The SwiftUI `.disabled` binding itself is not unit-tested (repo convention: no
UI tests in V1; the binding is a one-liner over the tested property, identical
in form to plan 010's bindings).

## Done criteria

- [ ] `swift build` exits 0
- [ ] `swift test` exits 0 with 85 tests (83 baseline + 2 new)
- [ ] `grep -n "isProtectionActive" Sources/TetherLoopCore/App/AppModel.swift Sources/TetherLoopCore/UI/MenuBar/TetherLoopMenu.swift` shows the property definition and the `.disabled` use
- [ ] The `isProtectionActive` switch is exhaustive (no `default:` case)
- [ ] `swift run GenerateScreenshots` exits 0; `assets/screenshots/menu.png` updated
- [ ] Only in-scope files in the commit (no `ProtectionStateMachine` changes, no "Pause Protection" change)

## STOP conditions

- The "Protect Now" button in `TetherLoopMenu.swift` no longer matches the
  `.disabled(!model.settings.isSetupVerified)` shape in "Current state" (plan
  010 or later work changed it) — re-read and reconcile before editing.
- An existing test fails after Step 1. Adding a read-only computed property is
  purely additive; a failure means something unexpected — report it, do not
  patch around it.
- You conclude the *real* fix is to stop `ProtectionStateMachine` from forcing
  `.protected` on `.userProtectNow` from `.onHotspot`/`.switching`. That is a
  defensible larger change, but it is **out of scope** here and would touch
  trust-critical state-machine logic covered by
  `ProtectionStateMachineTests` and `testProtectNowArmsFailoverEvenWhenToggleIsOff`.
  STOP and report it as a follow-up recommendation instead of implementing it.

## Maintenance notes

- `isProtectionActive` is the third member of the menu's "gray out what's
  already true" family (`isOnHotspot`, `isOnTrustedWiFi` from plan 010). If a
  new `ProtectionStatus` case is added, the exhaustive switch will fail to
  compile until you classify it — decide deliberately whether "Protect Now"
  should be available in that state.
- **Symmetric follow-up (not done here):** "Pause Protection" is always enabled,
  including in `.monitoring` / `.paused` / `.unconfigured` where pausing is a
  no-op. A future change could disable it when `!isProtectionActive && status != .failed`
  for full menu consistency. Left out to keep this change scoped to the reported issue.
- **Deeper follow-up:** the underlying `ProtectionStateMachine` still force-sets
  `.protected` on `.userProtectNow` regardless of state; this plan only gates the
  UI. If a future entry point calls `protectNow()` programmatically from
  `.onHotspot`, the status corruption returns. Worth a state-machine guard then.
