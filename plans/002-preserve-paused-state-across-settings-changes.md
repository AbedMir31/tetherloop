# Plan 002: Stop settings changes from silently un-pausing protection

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat efa3d18..HEAD -- Sources/TetherLoopCore/Core/Protection/ProtectionStateMachine.swift Sources/TetherLoopCore/App/AppModel.swift Tests/TetherLoopTests/ProtectionStateMachineTests.swift Tests/TetherLoopTests/ViewModelTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition. (Plan 001 intentionally touches
> these files — its changes are compatible; the excerpts below mark what
> plan 001 alters.)

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/001-gate-failover-on-state-machine-verdict.md (recommended order; not a hard compile dependency)
- **Category**: bug
- **Planned at**: commit `efa3d18`, 2026-06-11

## Why this matters

When the user clicks "Pause Protection", TetherLoop must not switch networks until the user re-arms it. But `ProtectionStateMachine.update(settings:)` resets a `.paused` status back to `.protected`/`.monitoring` whenever settings change — and `AppModel.updateSettings(_:)` runs on *every* settings mutation, including ones the user doesn't perceive as "settings changes": toggling sleep prevention, adding a trusted network, and even `defaultTrustedSSIDIfNeeded` which fires automatically when the Settings or Setup window loads network choices. Net effect: a paused app silently re-arms itself. This plan makes pause sticky until an explicit re-arm action.

## Current state

- `Sources/TetherLoopCore/Core/Protection/ProtectionStateMachine.swift:44-49` — the bug:

```swift
public mutating func update(settings: TetherLoopSettings) {
    self.settings = settings
    if status == .unconfigured || status == .monitoring || status == .protected || status == .paused {
        status = Self.initialStatus(for: settings)
    }
}
```

`initialStatus(for:)` (lines 144–149) returns `.protected` when configured+verified+`isProtectionEnabled`, else `.monitoring`, else `.unconfigured`. It never returns `.paused`, so the `.paused` branch above always un-pauses.

- `Sources/TetherLoopCore/App/AppModel.swift:329-336` — every setter funnels through:

```swift
private func updateSettings(_ mutate: (inout TetherLoopSettings) -> Void) {
    var copy = settings
    mutate(&copy)
    settings = copy
    stateMachine.update(settings: copy)
    try? settingsStore.save(copy)
    status = stateMachine.status
}
```

- Explicit re-arm paths that SHOULD clear pause and already do: `protectNow()` sends `.userProtectNow`; `setProtectionEnabled(_:)` (AppModel.swift:170–177) sends `.settingsChanged`, whose case in the state machine unconditionally recomputes `status = Self.initialStatus(for: settings)`. Keep both behaviors.
- The `.trustedWiFiConnected` case (state machine line 76–82) already guards `status != .paused`, so pause survives network polls — only `update(settings:)` breaks it.
- Repo conventions: pure state machine tests in `Tests/TetherLoopTests/ProtectionStateMachineTests.swift` (64 lines — construct machine, call `handle`/`update`, assert `status` and `intents`); AppModel behavior tests in `Tests/TetherLoopTests/ViewModelTests.swift` using `InMemorySettingsStore` + `FakeNetworkAdapter`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| All tests | `swift test` | exit 0 |
| Focused | `swift test --filter ProtectionStateMachineTests` | all pass |
| Focused | `swift test --filter ViewModelTests` | all pass |

## Scope

**In scope** (the only files you should modify):
- `Sources/TetherLoopCore/Core/Protection/ProtectionStateMachine.swift`
- `Tests/TetherLoopTests/ProtectionStateMachineTests.swift`
- `Tests/TetherLoopTests/ViewModelTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- `AppModel.updateSettings` — the funnel is correct; the fix belongs in the state machine.
- Persisting pause across app restarts — `.paused` is runtime-only state today (a restart re-arms). That is a product decision; see maintenance notes.
- `defaultTrustedSSIDIfNeeded` auto-trust behavior — questionable UX but separate concern; it logs a diagnostic event and is visible to the user.
- The `.settingsChanged` *event* case — explicit protection-toggle and verification flows intentionally reset status through it.

## Git workflow

- Branch: `advisor/002-sticky-pause` (or continue on the plan-001 branch if the operator is batching). Commit messages: short imperative sentences.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Remove `.paused` from the reset list in `update(settings:)`

```swift
public mutating func update(settings: TetherLoopSettings) {
    self.settings = settings
    if status == .unconfigured || status == .monitoring || status == .protected {
        status = Self.initialStatus(for: settings)
    }
}
```

One subtlety to preserve: if settings change makes the app unconfigured while paused (e.g. the user clears the hotspot target), the machine stays `.paused`. That is safe because every transition out of paused is guarded by `canProtect`, and `setHotspotSSID` invalidates verification so `canProtect` becomes false. Do not add special handling for it.

**Verify**: `swift build` → exit 0; `swift test` → all pass.

### Step 2: Add regression tests

See test plan.

**Verify**: `swift test --filter ProtectionStateMachineTests && swift test --filter ViewModelTests` → all pass including new tests.

## Test plan

In `Tests/TetherLoopTests/ProtectionStateMachineTests.swift`:

1. `testUpdateSettingsKeepsPausedStatus` — verified/enabled settings, `handle(.userPause)`, then `update(settings:)` with a mutated copy (e.g. `isSleepPreventionEnabled` flipped). Assert `status == .paused`.
2. `testSettingsChangedEventClearsPause` — same setup, then `handle(.settingsChanged)`. Assert `status == .protected` (documents that the explicit event still re-arms).

In `Tests/TetherLoopTests/ViewModelTests.swift` (model after existing tests, e.g. `testUntrustedDisconnectDoesNotJoinHotspotWhenGlobalFailoverIsDisabled` at lines 293–316):

3. `testPauseSurvivesUnrelatedSettingsChanges` — build model with verified/enabled settings, `model.pauseProtection()`, then `model.setSleepPreventionEnabled(true)` and `model.addTrustedSSID("Office")`. Assert `model.status == .paused` after each.
4. `testPauseSurvivesNetworkChoicesRefresh` — paused model with empty `trustedSSIDs` replaced by: settings with one trusted SSID; call `await model.refreshNetworkChoices()` (FakeNetworkAdapter with a current SSID). Assert still `.paused`.
5. `testEnableProtectionToggleClearsPause` — paused model, `model.setProtectionEnabled(true)`. Assert `model.status == .protected` (explicit re-arm).

Verification: `swift test` → exit 0, all tests pass.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` exits 0
- [ ] `swift test` exits 0; the 5 new tests exist and pass
- [ ] `grep -n "status == .paused" Sources/TetherLoopCore/Core/Protection/ProtectionStateMachine.swift` shows no occurrence inside `update(settings:)`
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `update(settings:)` no longer matches the excerpt (drift — possibly plan 001 or other work restructured it; re-read and reconcile before changing anything).
- Removing `.paused` from the reset list breaks an existing test — that would mean some flow depends on settings-driven un-pausing, which contradicts this plan's premise.

## Maintenance notes

- Pause remains runtime-only: quitting and relaunching the app while paused re-arms protection (initial status is computed from persisted settings). If users report surprise, persist a `isPaused` flag in `TetherLoopSettings` — that is a deliberate follow-up, not part of this fix.
- Reviewer should scrutinize the interaction with `setProtectionEnabled`, which calls BOTH `updateSettings` (no longer un-pauses) and `handle(.settingsChanged)` (still un-pauses) — the toggle must keep clearing pause, covered by test 5.
