# Plan 001: Make Pause Protection and the protection toggle actually stop automatic failover

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat efa3d18..HEAD -- Sources/TetherLoopCore/App/AppModel.swift Sources/TetherLoopCore/Core/Protection/ProtectionStateMachine.swift Tests/TetherLoopTests/ViewModelTests.swift Tests/TetherLoopTests/ProtectionStateMachineTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `efa3d18`, 2026-06-11

## Why this matters

TetherLoop is a macOS menu bar app that auto-joins a saved hotspot when the Mac leaves trusted Wi-Fi. It offers a "Pause Protection" menu action and an "Enable network protection" settings toggle. Today, **neither actually prevents automatic network switching**: the protection state machine correctly refuses to enter the `switching` state when paused, but `AppModel.pollNetwork()` ignores the state machine's verdict and calls `joinHotspotIfPossible(...)` unconditionally. The same applies when the protection toggle is off (`status == .monitoring`). For an app whose entire pitch is developer trust ("it never changes your network when you told it not to"), this is the most user-visible trust violation in the codebase. The fix is to gate the join side effect on the state machine's resulting status.

## Current state

- `Sources/TetherLoopCore/App/AppModel.swift` — `@MainActor` view model owning all side effects. The bug is in `pollNetwork()` (lines 254–278):

```swift
// AppModel.swift:267-274
if let previousSSID, settings.trustedSSIDs.contains(previousSSID) {
    lastTrustedSSID = previousSSID
    handle(.trustedWiFiDisconnected(previousSSID))
    await joinHotspotIfPossible(reason: "Trusted Wi-Fi disconnected")   // <- unconditional
} else if settings.isGlobalFailoverEnabled, previousSSID != nil {
    handle(.untrustedWiFiDisconnected)
    await joinHotspotIfPossible(reason: "Wi-Fi disconnected in global mode")  // <- unconditional
}
```

- `handle(_:)` (AppModel.swift:338–342) applies the state machine transition but discards the result:

```swift
private func handle(_ event: ProtectionEvent) {
    let result = stateMachine.handle(event)
    status = result.status
    apply(intents: result.intents)
}
```

- `Sources/TetherLoopCore/Core/Protection/ProtectionStateMachine.swift` — pure, deterministic state machine. The disconnect cases (lines 84–94) block `paused` but do **not** check `settings.isProtectionEnabled`:

```swift
case .trustedWiFiDisconnected(let ssid):
    guard canProtect, status != .paused else { break }
    status = .switching
    ...
case .untrustedWiFiDisconnected:
    guard canProtect, settings.isGlobalFailoverEnabled, status != .paused else { break }
    status = .switching
```

- Relevant semantics: `status == .protected` means failover is armed (either `settings.isProtectionEnabled == true`, or the user clicked "Protect Now" which sends `.userProtectNow`). `status == .monitoring` means configured + verified but protection toggle off. `canProtect` = `settings.isConfigured && settings.isSetupVerified`.

- Repo conventions: XCTest with `@MainActor` test classes; fake adapters (`FakeNetworkAdapter`, `RecordingPowerAssertionController`, `InMemorySettingsStore`, `InMemoryDiagnosticLogStore`, `RecordingNotificationDispatcher`, `RecordingLoginItemController`) live in the production target and are constructed directly in tests. Model new tests after `testUntrustedDisconnectDoesNotJoinHotspotWhenGlobalFailoverIsDisabled` in `Tests/TetherLoopTests/ViewModelTests.swift:293-316`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| All tests | `swift test` | exit 0, 35+ tests pass |
| Focused tests | `swift test --filter ViewModelTests` | all pass |
| Focused tests | `swift test --filter ProtectionStateMachineTests` | all pass |

## Scope

**In scope** (the only files you should modify):
- `Sources/TetherLoopCore/App/AppModel.swift`
- `Sources/TetherLoopCore/Core/Protection/ProtectionStateMachine.swift`
- `Tests/TetherLoopTests/ViewModelTests.swift`
- `Tests/TetherLoopTests/ProtectionStateMachineTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- `joinHotspotIfPossible`'s `reason.contains("Manual")` check — known debt, handled by plan 009.
- `ProtectionStateMachine.update(settings:)` paused-reset bug — handled by plan 002.
- Manual actions (`tryHotspotNow`, `returnToWiFi`) — these are explicit user intent and must keep working even when paused.
- UI files.

## Git workflow

- Branch: `advisor/001-gate-failover` (repo has no branch convention beyond `main`; commits are short imperative sentences, e.g. "Build TetherLoop Free V1").
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Require armed protection in the state machine's disconnect transitions

In `ProtectionStateMachine.swift`, change the two disconnect cases so the machine only enters `.switching` when protection is actually armed (status `.protected`). This covers both the paused case and the protection-toggle-off (`.monitoring`) case:

```swift
case .trustedWiFiDisconnected(let ssid):
    guard canProtect, status == .protected else { break }
    status = .switching
    retryAttempt = 0
    intents.append(.record(.trustedNetworkLost, "Trusted Wi-Fi disconnected: \(ssid)"))

case .untrustedWiFiDisconnected:
    guard canProtect, settings.isGlobalFailoverEnabled, status == .protected else { break }
    status = .switching
    retryAttempt = 0
    intents.append(.record(.trustedNetworkLost, "Wi-Fi disconnected in global mode"))
```

Also harden `.retryTimerFired` (it shares a case with `.userTryNow` at line 120). Split them so the timer respects pause but the user action stays manual:

```swift
case .userTryNow:
    guard canProtect else {
        status = .unconfigured
        break
    }
    status = .switching
    intents.append(.record(.hotspotJoinStarted, "Retrying hotspot join"))

case .retryTimerFired:
    guard canProtect, status != .paused else { break }
    status = .switching
    intents.append(.record(.hotspotJoinStarted, "Retrying hotspot join"))
```

**Verify**: `swift build` → exit 0.

### Step 2: Return the transition result from `handle(_:)` and gate the join on it

In `AppModel.swift`, make `handle` return the result:

```swift
@discardableResult
private func handle(_ event: ProtectionEvent) -> ProtectionTransitionResult {
    let result = stateMachine.handle(event)
    status = result.status
    apply(intents: result.intents)
    return result
}
```

Then in `pollNetwork()`, only join when the machine entered `.switching`:

```swift
if let previousSSID, settings.trustedSSIDs.contains(previousSSID) {
    lastTrustedSSID = previousSSID
    let result = handle(.trustedWiFiDisconnected(previousSSID))
    if result.status == .switching {
        await joinHotspotIfPossible(reason: "Trusted Wi-Fi disconnected")
    }
} else if settings.isGlobalFailoverEnabled, previousSSID != nil {
    let result = handle(.untrustedWiFiDisconnected)
    if result.status == .switching {
        await joinHotspotIfPossible(reason: "Wi-Fi disconnected in global mode")
    }
}
```

Do NOT add the same gate to `tryHotspotNow()` or `retryHotspotJoin()` joins beyond what exists — `tryHotspotNow` is manual, and `retryHotspotJoin` is already cancelled on pause via `cancelRetry()`; the state machine guard from Step 1 is defense in depth.

**Verify**: `swift test` → all existing tests pass (every existing failover test arms protection with `isProtectionEnabled: true`, so the resulting status is `.protected` and behavior is unchanged for them).

### Step 3: Add regression tests

See test plan below.

**Verify**: `swift test --filter ViewModelTests` and `swift test --filter ProtectionStateMachineTests` → all pass, including the new tests.

## Test plan

New tests in `Tests/TetherLoopTests/ViewModelTests.swift` (model after `testUntrustedDisconnectDoesNotJoinHotspotWhenGlobalFailoverIsDisabled`, lines 293–316 — settings via `InMemorySettingsStore`, `FakeNetworkAdapter`, two `pollNetwork()` calls with `network.current` flipped to `nil` in between, assert on `network.joinAttempts`):

1. `testPausedProtectionDoesNotJoinHotspotOnTrustedDisconnect` — verified + enabled settings, `pollNetwork()` on trusted SSID, then `model.pauseProtection()`, then `network.current = nil`, `pollNetwork()`. Assert `network.joinAttempts.isEmpty` and `model.status == .paused`.
2. `testDisabledProtectionDoesNotJoinHotspotOnTrustedDisconnect` — same but settings start with `isProtectionEnabled: false` (status `.monitoring`). Assert no join attempts and status is NOT `.switching`/`.onHotspot`.
3. `testProtectNowArmsFailoverEvenWhenToggleIsOff` — settings `isProtectionEnabled: false` but verified/configured; call `model.protectNow()`, poll on trusted SSID, then disconnect. Assert `network.joinAttempts == ["Phone"]` (manual arming still fails over).
4. `testPausedGlobalFailoverDoesNotJoinHotspot` — global failover enabled, pause, untrusted disconnect → no join.

New tests in `Tests/TetherLoopTests/ProtectionStateMachineTests.swift` (follow the existing style there — construct `ProtectionStateMachine(settings:)`, call `handle`, assert on `status`/`intents`):

5. Paused machine receiving `.trustedWiFiDisconnected` stays `.paused` with `[.none]` intents.
6. Monitoring machine (verified, `isProtectionEnabled: false`) receiving `.trustedWiFiDisconnected` stays `.monitoring`.
7. Paused machine receiving `.retryTimerFired` stays `.paused`.

Verification: `swift test` → exit 0, all tests (35 existing + 7 new) pass.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` exits 0
- [ ] `swift test` exits 0; the 7 new tests above exist and pass
- [ ] In `AppModel.pollNetwork()`, no call to `joinHotspotIfPossible` remains that is not guarded by a `.switching` status check: `grep -n "joinHotspotIfPossible" Sources/TetherLoopCore/App/AppModel.swift` shows the two poll-path calls inside `if result.status == .switching` blocks
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts in "Current state" don't match the live code (drift).
- Any *existing* test fails after Step 1 or Step 2 and the failure is not explained by the test arming protection some way other than `isProtectionEnabled: true` or `.userProtectNow` — that would mean the armed-status model in this plan is wrong.
- You find additional call sites of `joinHotspotIfPossible` beyond `pollNetwork`, `tryHotspotNow`, and `retryHotspotJoin` — the plan's analysis would be incomplete.

## Maintenance notes

- Plan 002 (paused-state preservation) and plan 008 (test sweep) build directly on this gating; land this first.
- Reviewer should scrutinize: the `.protected`-only guard means failover never fires from `.monitoring`. That is the intended semantics of the "Enable network protection" toggle; if the maintainer instead wants trusted-disconnect failover even with the toggle off, that is a product decision to make explicitly — today's behavior (always fire) was unintentional.
- Deferred: replacing `reason.contains("Manual")` string matching (plan 009).
