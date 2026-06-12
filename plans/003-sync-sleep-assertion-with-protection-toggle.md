# Plan 003: Keep the idle-sleep assertion in sync with the protection toggle

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat efa3d18..HEAD -- Sources/TetherLoopCore/App/AppModel.swift Tests/TetherLoopTests/ViewModelTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition. (Plans 001/002 touch AppModel —
> their changes are in `pollNetwork`/`handle` and do not conflict with the
> setters edited here.)

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (compatible with 001/002 in any order)
- **Category**: bug
- **Planned at**: commit `efa3d18`, 2026-06-11

## Why this matters

TetherLoop offers "Prevent idle sleep while protected" — a macOS `kIOPMAssertionTypeNoIdleSleep` power assertion. Two bugs break it:

1. **Assertion never starts when protection is enabled via the Settings toggle.** `setProtectionEnabled(true)` sends `.settingsChanged` to the state machine, which emits no power intents; only the "Protect Now" menu action (`.userProtectNow`) emits `.startSleepPrevention`. So a user who enables both toggles in Settings believes their Mac won't idle-sleep — and it does, potentially killing the long AI job the app exists to protect.
2. **Assertion leaks when protection is disabled.** After "Protect Now" starts the assertion, `setProtectionEnabled(false)` emits no `.stopSleepPrevention`, so the Mac is kept awake indefinitely (battery drain) until pause/quit.

The fix is one call: make `setProtectionEnabled` run the existing `applySleepPreventionIfNeeded()` reconciliation, and make that reconciliation respect the paused state.

## Current state

- `Sources/TetherLoopCore/App/AppModel.swift:170-177` — the protection setter (note: it does not touch the power controller):

```swift
public func setProtectionEnabled(_ enabled: Bool) {
    if !enabled {
        cancelRetry()
    }
    updateSettings { $0.isProtectionEnabled = enabled }
    handle(.settingsChanged)
    record(enabled ? .protectionEnabled : .protectionPaused, enabled ? "Protection enabled" : "Protection disabled")
}
```

- `Sources/TetherLoopCore/App/AppModel.swift:179-182` — the sleep setter, the only caller of the reconciler:

```swift
public func setSleepPreventionEnabled(_ enabled: Bool) {
    updateSettings { $0.isSleepPreventionEnabled = enabled }
    applySleepPreventionIfNeeded()
}
```

- `Sources/TetherLoopCore/App/AppModel.swift:361-367` — the reconciler (note: it ignores `.paused`):

```swift
private func applySleepPreventionIfNeeded() {
    if settings.isSleepPreventionEnabled && settings.isProtectionEnabled {
        try? powerController.enable(reason: "TetherLoop protection is active")
    } else {
        try? powerController.disable()
    }
}
```

- Intent-driven paths that already work and must keep working: `.userProtectNow` emits `.startSleepPrevention` when `isSleepPreventionEnabled` (ProtectionStateMachine.swift:66-68); `.userPause` emits `.stopSleepPrevention` (line 73). `apply(intents:)` in AppModel (lines 344–359) maps them to `powerController.enable/disable`.
- `SystemPowerAssertionController` is idempotent (`guard !isEnabled` / `guard isEnabled`), so double enable/disable is safe.
- Test fake: `RecordingPowerAssertionController` (in `Sources/TetherLoopCore/Core/Power/PowerAssertionController.swift`) records `enableReasons: [String]` and `disableCount: Int`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| All tests | `swift test` | exit 0 |
| Focused | `swift test --filter ViewModelTests` | all pass |

## Scope

**In scope** (the only files you should modify):
- `Sources/TetherLoopCore/App/AppModel.swift`
- `Tests/TetherLoopTests/ViewModelTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- `ProtectionStateMachine` intents for `.userProtectNow`/`.userPause` — they work; leave them.
- `SystemPowerAssertionController` — correct as-is.
- Releasing the assertion on app termination — the OS releases IOPM assertions on process exit.

## Git workflow

- Branch: `advisor/003-sleep-assertion-sync`. Commit messages: short imperative sentences.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Reconcile the assertion in `setProtectionEnabled` and respect pause

Append `applySleepPreventionIfNeeded()` to `setProtectionEnabled` after `handle(.settingsChanged)`, and add the paused check to the reconciler:

```swift
public func setProtectionEnabled(_ enabled: Bool) {
    if !enabled {
        cancelRetry()
    }
    updateSettings { $0.isProtectionEnabled = enabled }
    handle(.settingsChanged)
    applySleepPreventionIfNeeded()
    record(enabled ? .protectionEnabled : .protectionPaused, enabled ? "Protection enabled" : "Protection disabled")
}

private func applySleepPreventionIfNeeded() {
    if settings.isSleepPreventionEnabled && settings.isProtectionEnabled && status != .paused {
        try? powerController.enable(reason: "TetherLoop protection is active")
    } else {
        try? powerController.disable()
    }
}
```

Ordering matters: `applySleepPreventionIfNeeded` must run *after* `handle(.settingsChanged)` so `status` reflects the new toggle value.

**Verify**: `swift build` → exit 0; `swift test` → all existing tests pass.

### Step 2: Add regression tests

See test plan.

**Verify**: `swift test --filter ViewModelTests` → all pass including new tests.

## Test plan

New tests in `Tests/TetherLoopTests/ViewModelTests.swift`. Pattern: build the model with `RecordingPowerAssertionController` kept in a local variable (existing tests construct it inline — bind it to `let power = RecordingPowerAssertionController()` instead and pass it in), use verified settings (`isSetupVerified: true`, one trusted SSID, hotspot set):

1. `testEnablingProtectionStartsSleepAssertionWhenSleepPreventionIsOn` — settings start `isProtectionEnabled: false, isSleepPreventionEnabled: true`; call `model.setProtectionEnabled(true)`; assert `power.enableReasons.count == 1`.
2. `testDisablingProtectionStopsSleepAssertion` — settings start enabled+sleep-on; `model.protectNow()` (assert `enableReasons.count >= 1`), then `model.setProtectionEnabled(false)`; assert `power.disableCount >= 1`.
3. `testEnablingProtectionWithoutSleepPreventionDoesNotStartAssertion` — `isSleepPreventionEnabled: false`; `model.setProtectionEnabled(true)`; assert `power.enableReasons.isEmpty`.
4. `testTogglingSleepPreventionWhilePausedDoesNotStartAssertion` — verified/enabled settings, `model.pauseProtection()`, then `model.setSleepPreventionEnabled(true)`; assert `power.enableReasons.isEmpty` (only the disable from pause is recorded).

Verification: `swift test` → exit 0, all tests pass.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` exits 0
- [ ] `swift test` exits 0; the 4 new tests exist and pass
- [ ] `grep -n "applySleepPreventionIfNeeded" Sources/TetherLoopCore/App/AppModel.swift` shows a call inside `setProtectionEnabled`
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The setters or reconciler don't match the excerpts (drift).
- Test 4 fails because `pauseProtection()` did not leave `status == .paused` — that points at the plan-002 bug territory; report rather than working around it.
- An existing test asserts power behavior that contradicts the new reconciliation (none should — current tests don't assert power state on the protection toggle).

## Maintenance notes

- If a future change re-arms protection automatically (e.g. smart auto-return in Pro), it must call `applySleepPreventionIfNeeded()` or emit the power intents — grep for both before merging such work.
- Reviewer should scrutinize the `status != .paused` condition: after plan 002 lands, pause is sticky across settings changes, so this condition is what keeps a paused app from re-acquiring the assertion when the user flips toggles.
- Deferred: surfacing assertion-creation failures to the UI (currently `try?` swallows them; the failure mode is rare and low-stakes).
