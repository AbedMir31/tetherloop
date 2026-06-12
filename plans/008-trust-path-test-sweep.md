# Plan 008: Add the missing tests around trust-critical protection paths

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat efa3d18..HEAD -- Tests/TetherLoopTests Sources/TetherLoopCore/App/AppModel.swift`
> This plan REQUIRES plans 001, 002, and 003 to be DONE (check
> `plans/README.md`). It tests their behavior; written against the
> pre-fix codebase it would assert bugs.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (test-only)
- **Depends on**: plans/001, plans/002, plans/003 (DONE); benefits from 005/006 but does not require them
- **Category**: tests
- **Planned at**: commit `efa3d18`, 2026-06-11

## Why this matters

The audit found that every pre-existing failover test arms protection (`isProtectionEnabled: true`) and none exercises pause, the protection toggle off, retry cancellation, or the sleep-assertion lifecycle — exactly where three real bugs lived (fixed by plans 001–003, each of which adds its own regression tests). This plan adds the *remaining* characterization tests so the next refactor of `AppModel`/`ProtectionStateMachine` can't silently reintroduce trust violations. It deliberately overlaps nothing with the tests specified in plans 001–003, 006, 007 — read those plans' "Test plan" sections first and skip anything already present.

## Current state

- `Tests/TetherLoopTests/ViewModelTests.swift` — 16 tests at the planned-at commit (~406 lines), all fake-based, `@MainActor`. Canonical pattern (lines 293–316): build `InMemorySettingsStore` + `FakeNetworkAdapter`, construct `AppModel` with recording fakes, drive `pollNetwork()` and assert on `network.joinAttempts` / `model.status`.
- `Tests/TetherLoopTests/ProtectionStateMachineTests.swift` — 64 lines; pure transition tests.
- Async timing convention: after a failure-triggered retry, tests sleep `try await Task.sleep(nanoseconds: 50_000_000)` to let the zero-delay first retry fire (see `testTrustedDisconnectRetriesHotspotAfterFailure`).
- Untested behaviors (verified absent by grep at planned-at commit; re-verify since plans 001–003 added some):
  - `pauseProtection()` cancels a pending retry task (`AppModel.pauseProtection` calls `cancelRetry()`).
  - `stopMonitoring()` cancels both the monitor and retry tasks; `startMonitoring()` is idempotent (`guard monitorTask == nil`).
  - `returnWiFiTarget()` ordering: last trusted SSID preferred; falls back to alphabetically-first configured trusted SSID; `returnToWiFi()` with zero trusted networks records a failure and performs no join.
  - `defaultTrustedSSIDIfNeeded`: auto-adds the current SSID as trusted only when the trusted set is empty and the SSID differs from the hotspot target.
  - State machine: `.hotspotJoinFailed` increments attempts so the 9-delay policy eventually yields no `.scheduleRetry` intent; `.hotspotJoinSucceeded` resets the attempt counter.
  - `setHotspotSSID` cancels a pending retry (it calls `cancelRetry()`).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| All tests | `swift test` | exit 0 |
| Focused | `swift test --filter ViewModelTests` | all pass |
| Focused | `swift test --filter ProtectionStateMachineTests` | all pass |

## Scope

**In scope** (the only files you should modify):
- `Tests/TetherLoopTests/ViewModelTests.swift`
- `Tests/TetherLoopTests/ProtectionStateMachineTests.swift`

**Out of scope** (do NOT touch):
- Any production source file. If a behavior can't be tested without a production change, record it in your final report instead of changing source.
- UI snapshot/UI tests — PRD marks them optional for V1.

## Git workflow

- Branch: `advisor/008-test-sweep`. Commit messages: short imperative sentences.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Read the current test files and the test plans of 001–003/006/007

List which of the behaviors below are already covered; skip those.

**Verify**: `swift test` → exit 0 (baseline green before adding anything).

### Step 2: Add AppModel behavior tests

In `ViewModelTests.swift`, following the existing pattern:

1. `testPauseCancelsPendingRetry` — dead hotspot (`joinResults` failures), trusted disconnect schedules a retry; immediately `model.pauseProtection()`; sleep 100ms; assert `network.joinAttempts.count == 1` (no retry fired).
2. `testSettingHotspotCancelsPendingRetry` — same setup; `model.setHotspotSSID("Other")` after the first failure; sleep; assert no further join attempts on the old target.
3. `testStopMonitoringCancelsRetry` — same; `model.stopMonitoring()`; sleep; assert join attempts stop.
4. `testReturnToWiFiPrefersLastTrustedSSID` — trusted {"Home", "Annex"}; poll on "Annex" (becomes last trusted), disconnect to hotspot; `await model.returnToWiFi()`; assert `network.joinedSSIDs.last == "Annex"`.
5. `testReturnToWiFiFallsBackToFirstConfiguredTrusted` — trusted {"Beta", "Alpha"}, no poll history; `await model.returnToWiFi()`; assert join target `"Alpha"` (localized-standard sort).
6. `testReturnToWiFiWithNoTrustedNetworksRecordsFailure` — empty trusted set; `await model.returnToWiFi()`; assert `network.joinAttempts.isEmpty` and a diagnostic event message contains `"no trusted Wi-Fi"`.
7. `testRefreshDefaultsTrustedSSIDOnlyWhenEmptyAndNotHotspot` — (a) empty trusted set, current SSID "Cafe", hotspot "Phone" → after `refreshNetworkChoices()`, trusted contains "Cafe"; (b) current SSID equals hotspot "Phone" → trusted stays empty; (c) trusted already has "Home" → "Cafe" is NOT added.

### Step 3: Add state machine tests

In `ProtectionStateMachineTests.swift`:

8. `testRetrySchedulingStopsAfterPolicyExhaustion` — machine with `RetryPolicy(delays: [0, 1])`; send `.hotspotJoinFailed` three times; assert the first two results contain a `.scheduleRetry` intent and the third does not, with `status == .failed` throughout.
9. `testHotspotJoinSuccessResetsRetryAttempts` — fail once, succeed (`.hotspotJoinSucceeded`), fail again; assert the post-success failure gets the policy's *first* delay again (a `.scheduleRetry(0)` intent with the policy above).

**Verify**: `swift test` → exit 0; new tests pass.

## Test plan

This plan *is* a test plan; see steps. Expected net addition: ~9 tests (minus any already covered by earlier plans' regression tests).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift test` exits 0
- [ ] Each behavior listed in Step 2/3 is covered by a test (named as above or equivalent), or explicitly reported as already covered by an earlier plan's tests
- [ ] No production source files modified (`git status` shows only the two test files)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `plans/README.md` shows 001, 002, or 003 not DONE.
- A test you write fails and code-reading says the *production behavior* is wrong (not the test) — that is a new finding; report it rather than encoding the bug as expected behavior.
- Flakiness: if a timing-based test needs sleeps beyond ~200ms to pass reliably, report it — the fix is injectable timing in production code, which is out of scope here.

## Maintenance notes

- The sleep-based retry tests inherit the repo's existing 50ms-sleep pattern; they are mildly timing-sensitive on slow CI. If they flake, the right fix is injecting a clock/scheduler into `AppModel.scheduleRetry` — a small production refactor worth its own pass.
- Reviewer should scrutinize test 7's case (b)/(c) — they encode `defaultTrustedSSIDIfNeeded`'s guard conditions, which is behavior the maintainer may want to remove entirely someday (auto-trusting a network the user never confirmed is debatable UX; see plans/README.md rejected-findings notes).
