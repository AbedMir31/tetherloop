# Plan 006: Stop trusting networksetup's exit code — verify hotspot joins actually happened

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat efa3d18..HEAD -- Sources/TetherLoopCore/Core/Network/NetworkSetupClient.swift Sources/TetherLoopCore/App/AppModel.swift Tests/TetherLoopTests/NetworkSetupClientTests.swift Tests/TetherLoopTests/ViewModelTests.swift`
> Plans 001/003/005 modify `AppModel.swift` — that is expected; this plan
> assumes plan 005's `currentNetwork()` API exists. If it does not, treat
> as a STOP condition (or execute plan 005 first).

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW–MED — tightens success criteria; risk is false *negatives* on slow joins, mitigated by a generous confirmation window
- **Depends on**: plans/005-fix-ssid-detection-on-modern-macos.md (post-join confirmation reads the SSID via the fixed path)
- **Category**: bug
- **Planned at**: commit `efa3d18`, 2026-06-11

## Why this matters

`networksetup -setairportnetwork` reports failures as *text on stdout with exit code 0* (e.g. `Failed to join network ...` or `Could not find network ...`). TetherLoop's `ProcessCommandRunner` only checks the exit code, so `join(ssid:)` "succeeds" even when the join failed. Two promises break:

1. **Setup verification can be faked by the OS.** The PRD's central trust mechanism ("a fake setup is worse than no setup" — the app *requires* a successful failover test before protection can arm) marks `isSetupVerified = true` on a join that never happened.
2. **Failure looks like success during a real failover.** The user gets a "TetherLoop switched to hotspot" notification while offline, and the retry loop never engages because no error was thrown.

Fix in two layers: parse the command output for failure markers (cheap, deterministic, unit-testable), and confirm the join by observing the current network until it matches the target (the only ground truth).

## Current state

- `Sources/TetherLoopCore/Core/Network/NetworkSetupClient.swift:72-75` — output discarded:

```swift
@MainActor
public func join(ssid: String, device: String) async throws {
    _ = try await runner.run(executable, arguments: ["-setairportnetwork", device, ssid])
}
```

- Same file, lines 28–30 (`ProcessCommandRunner.run`) — only `terminationStatus != 0` throws. Known `networksetup -setairportnetwork` failure outputs (all with exit 0): `Failed to join network <ssid>.`, `Could not find network <ssid>.`, and strings containing `Error: -3905` / similar `Error:` codes.
- Parsing convention in this file: pure `static func parseX(from output: String)` functions with unit tests in `Tests/TetherLoopTests/NetworkSetupClientTests.swift` (45 lines — e.g. `parseCurrentSSID`, `parseWiFiDevice` tests). Match it.
- `Sources/TetherLoopCore/App/AppModel.swift` — `joinHotspotIfPossible` (lines 280–297 at the planned-at commit) and `verifyHotspotSetup` (lines 299–327) both call `networkAdapter.join(ssid:)` and treat a non-throwing return as success. `returnToWiFi` (lines 216–236) does the same for the trusted network.
- After plan 005: `NetworkAdapter` has `currentNetwork() async throws -> WiFiNetworkState`; `FakeNetworkAdapter.join` sets `current = ssid` on success, so fake-based confirmation succeeds immediately in tests.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| All tests | `swift test` | exit 0 |
| Focused | `swift test --filter NetworkSetupClientTests` | all pass |
| Focused | `swift test --filter ViewModelTests` | all pass |

## Scope

**In scope** (the only files you should modify):
- `Sources/TetherLoopCore/Core/Network/NetworkSetupClient.swift`
- `Sources/TetherLoopCore/Core/Network/NetworkInterfaces.swift` (only if a new error case is needed)
- `Sources/TetherLoopCore/App/AppModel.swift`
- `Tests/TetherLoopTests/NetworkSetupClientTests.swift`
- `Tests/TetherLoopTests/ViewModelTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- Internet reachability / captive-portal checks — joining the right SSID is this plan's success criterion; "online" verification is a future direction item.
- Retry policy values.
- `CoreWLANClient` internals from plan 005.

## Git workflow

- Branch: `advisor/006-join-verification`. Commit per step; messages: short imperative sentences.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Parse join output for failure markers

In `NetworkSetupClient.swift`, add a pure parser following the file's existing `parseX` convention:

```swift
public static func parseJoinFailure(from output: String) -> String? {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let failureMarkers = ["failed to join", "could not find network", "error:"]
    let lowered = trimmed.lowercased()
    for marker in failureMarkers where lowered.contains(marker) {
        return trimmed
    }
    return nil
}
```

Use it in `join`:

```swift
@MainActor
public func join(ssid: String, device: String) async throws {
    let output = try await runner.run(executable, arguments: ["-setairportnetwork", device, ssid])
    if let failure = Self.parseJoinFailure(from: output) {
        throw NetworkAdapterError.commandFailed(failure)
    }
}
```

(A successful join prints nothing, so empty output passes.)

**Verify**: `swift build` → exit 0; `swift test --filter NetworkSetupClientTests` → existing tests pass.

### Step 2: Confirm the join by observing the current network

In `AppModel.swift`, add a private confirmation helper. It polls the adapter until the target SSID is observed or a deadline passes. Inject the timing so tests run instantly:

```swift
private func confirmJoin(
    to target: String,
    attempts: Int = 10,
    delay: Duration = .seconds(1)
) async -> Bool {
    for attempt in 0..<attempts {
        if let state = try? await networkAdapter.currentNetwork() {
            switch state {
            case .associated(let ssid?) where ssid == target:
                return true
            case .associated(nil):
                // SSID unreadable (no Location permission): we cannot disprove
                // the join; trust the command result rather than failing falsely.
                return true
            default:
                break
            }
        }
        if attempt < attempts - 1 {
            try? await Task.sleep(for: delay)
        }
    }
    return false
}
```

Make `attempts`/`delay` configurable via stored properties set in `init` (e.g. `joinConfirmationAttempts: Int = 10`, `joinConfirmationDelay: Duration = .seconds(1)` parameters with defaults) so tests pass `attempts: 2, delay: .zero`. Follow the existing pattern of constructor injection used for all adapters.

Then wire it into `joinHotspotIfPossible` — after `try await networkAdapter.join(ssid: hotspot)` and before declaring success:

```swift
try await networkAdapter.join(ssid: hotspot)
guard await confirmJoin(to: hotspot) else {
    handle(.hotspotJoinFailed("Join command completed but \(hotspot) never became the current network"))
    record(.hotspotJoinFailed, "Could not confirm join to \(hotspot)")
    notificationDispatcher.notify(title: "TetherLoop could not join hotspot", body: "\(hotspot) did not become the current network")
    return
}
cancelRetry()
handle(.hotspotJoinSucceeded(hotspot))
...
```

Apply the same confirmation in `verifyHotspotSetup` (treat an unconfirmed join as verification failure — `isSetupVerified` stays false) and in `returnToWiFi` (an unconfirmed return triggers the existing `.trustedWiFiJoinFailed` path).

**Verify**: `swift build` → exit 0; `swift test` → all existing tests pass (FakeNetworkAdapter sets `current = ssid` on successful join, so confirmation passes on the first attempt with zero added latency... only if the model's confirmation delay is reached — see STOP conditions if existing async tests time out; constructing test models with `joinConfirmationDelay: .zero` is acceptable everywhere).

### Step 3: Tests

See test plan.

**Verify**: `swift test` → all pass.

## Test plan

In `Tests/TetherLoopTests/NetworkSetupClientTests.swift` (model after the existing parser tests):

1. `testParseJoinFailureDetectsFailedToJoin` — input `"Failed to join network MyPhone."` → returns the message.
2. `testParseJoinFailureDetectsCouldNotFind` — input `"Could not find network MyPhone."` → returns the message.
3. `testParseJoinFailureDetectsErrorCode` — input `"Error: -3905 ..."` → returns the message.
4. `testParseJoinFailureAcceptsEmptyOutput` — `""` and `"\n"` → nil.
5. `testJoinThrowsOnFailureOutputWithZeroExit` — `RecordingCommandRunner` with `outputs["-setairportnetwork en0 Phone": "Failed to join network Phone."]` (key format: arguments joined by spaces); `client.join(ssid: "Phone", device: "en0")` throws `NetworkAdapterError.commandFailed`.

In `Tests/TetherLoopTests/ViewModelTests.swift` (construct models with `joinConfirmationAttempts: 2, joinConfirmationDelay: .zero`):

6. `testHotspotJoinIsNotSuccessUntilNetworkConfirms` — `FakeNetworkAdapter` modified scenario: make join "succeed" but leave `current` unchanged. The fake's `join` sets `current = ssid` on success, so add a knob to the fake: `public var joinSetsCurrent = true`, and skip the assignment when false (this is an in-scope edit to `NetworkInterfaces.swift`). With `joinSetsCurrent = false`, trusted disconnect → join attempt → assert `model.status == .failed` and no "switched to hotspot" success notification recorded.
7. `testSetupVerificationFailsWhenJoinDoesNotConfirm` — same knob during `runSetupVerificationTest()`; assert `settings.isSetupVerified == false`.
8. `testConfirmedJoinStillSucceeds` — default fake behavior; trusted disconnect → assert `.onHotspot` (regression guard on the happy path).

Verification: `swift test` → exit 0, all tests pass including 8 new.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` and `swift test` exit 0; the 8 new tests exist and pass
- [ ] `grep -n "parseJoinFailure" Sources/TetherLoopCore/Core/Network/NetworkSetupClient.swift` shows the parser and its use in `join`
- [ ] `grep -n "confirmJoin" Sources/TetherLoopCore/App/AppModel.swift` shows calls in `joinHotspotIfPossible`, `verifyHotspotSetup`, and `returnToWiFi`
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Plan 005's `currentNetwork()` does not exist on `NetworkAdapter` (dependency not landed).
- Existing `ViewModelTests` hang or exceed ~10s after Step 2 — the confirmation delay is leaking real sleeps into tests; fix by injecting `.zero` delays, and if that requires touching files out of scope, stop.
- You find the actual `networksetup -setairportnetwork` failure strings differ from the markers above on the target macOS (check is welcome but requires changing real network state — do NOT run the join command against real networks; rely on the documented markers and report doubts instead).

## Maintenance notes

- The `.associated(nil)` → "trust the command" branch in `confirmJoin` is a deliberate compromise: without Location permission the app cannot read SSIDs, and failing every join would make the app unusable in that state. Once plan 005's permission flow is adopted by users, consider tightening this.
- Future direction (deliberately out of scope): after a confirmed join, probe actual internet reachability and surface "joined but offline" as a distinct state — the PRD allows a visible failure state for captive portals.
- Reviewer should scrutinize: the confirmation window (10 × 1s) versus real hotspot join latency; iPhone hotspots can take several seconds to hand out DHCP, but SSID association (what we check) is fast. If field reports show false failures, raise `attempts`, don't remove the check.
