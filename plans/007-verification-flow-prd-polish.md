# Plan 007: Close the PRD gaps in the verification flow — warn before the test, offer the return, log truthfully, stop retry notification spam

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat efa3d18..HEAD -- Sources/TetherLoopCore/App/AppModel.swift Sources/TetherLoopCore/UI/Onboarding/OnboardingView.swift Tests/TetherLoopTests/ViewModelTests.swift`
> Plans 001/003/005/006 modify `AppModel.swift`; expect their changes. The
> excerpts below are from the planned-at commit — locate the corresponding
> code by symbol name, not line number, if earlier plans landed.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: plans/006-verify-hotspot-join-success.md (the verification flow it polishes should be the confirmed-join version)
- **Category**: bug (PRD coverage)
- **Planned at**: commit `efa3d18`, 2026-06-11

## Why this matters

Three PRD user stories about the setup-verification experience are unmet or half-met:

- **Story 8** — "I want the failover test to tell me before it changes networks." The onboarding "Run Verification Test" button switches networks immediately, with no warning. A user mid-videocall gets disconnected without consent.
- **Story 9** — "I want TetherLoop to offer to return to my prior Wi-Fi after a test." The app auto-returns silently; worse, the diagnostic log records "Returned to Wi-Fi: X" *even when the return join failed* (`try?` swallows the error, then the success line is recorded unconditionally), and if the test started while not on Wi-Fi the user is silently left on the hotspot.
- **Story 17** — "I want no constant monitoring notifications." Every failed retry posts a system notification; with the default retry policy (`[0, 15, 30, 60, 120, 120, 120, 120, 120]`) a dead hotspot produces ~10 failure notifications in ~10 minutes.

## Current state

- `Sources/TetherLoopCore/App/AppModel.swift` — `verifyHotspotSetup()` (lines 299–327 at planned-at commit). The buggy return path:

```swift
// AppModel.swift:315-321
if let originalSSID, originalSSID != hotspot {
    try? await networkAdapter.join(ssid: originalSSID)     // failure swallowed
    if settings.trustedSSIDs.contains(originalSSID) {
        lastTrustedSSID = originalSSID
    }
    record(.manualAction, "Returned to Wi-Fi: \(originalSSID)")  // recorded even on failure
}
```

- `joinHotspotIfPossible` (lines 280–297) — failure branch notifies on every call:

```swift
} catch {
    handle(.hotspotJoinFailed(error.localizedDescription))
    record(.hotspotJoinFailed, "Could not join \(hotspot): \(error.localizedDescription)")
    notificationDispatcher.notify(title: "TetherLoop could not join hotspot", body: error.localizedDescription)
}
```

Retries arrive via `retryHotspotJoin()` → `joinHotspotIfPossible(reason: "Retry hotspot attempt")`, so each retry failure re-notifies. The state machine emits `.scheduleRetry(delay)` only while the policy has delays left (`ProtectionStateMachine.swift:105-118`); when exhausted, status is `.failed` with no retry intent — and the user is never told retries stopped.

- `Sources/TetherLoopCore/UI/Onboarding/OnboardingView.swift:50-57` — the test button:

```swift
Button("Run Verification Test", systemImage: "checkmark.seal") {
    Task { await model.runSetupVerificationTest() }
}
```

- Conventions: UI state lives in `AppModel` `@Published` properties; views bind via `@ObservedObject`. SwiftUI confirmation uses `.confirmationDialog`/`.alert` modifiers. Tests: `Tests/TetherLoopTests/ViewModelTests.swift`, fakes throughout; `RecordingNotificationDispatcher.notifications` is the notification assertion surface.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| All tests | `swift test` | exit 0 |
| Focused | `swift test --filter ViewModelTests` | all pass |
| Screenshots (after UI change) | `swift run GenerateScreenshots` | regenerates `assets/screenshots/*.png` without error |

## Scope

**In scope** (the only files you should modify):
- `Sources/TetherLoopCore/App/AppModel.swift`
- `Sources/TetherLoopCore/UI/Onboarding/OnboardingView.swift`
- `Tests/TetherLoopTests/ViewModelTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- `RetryPolicy` delays — cadence is per PRD.
- The notification dispatcher implementation (plan 004).
- `assets/screenshots/*` regeneration is allowed (repo convention: run `swift run GenerateScreenshots` after UI changes — README "Before changing behavior" section), but do not hand-edit images.

## Git workflow

- Branch: `advisor/007-verification-polish`. Commit per step; messages: short imperative sentences.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Pre-test confirmation dialog (story 8)

In `OnboardingView.swift`, add `@State private var isConfirmingTest = false` and change the button to set it, with a `.confirmationDialog` that names the hotspot and warns about the temporary switch:

```swift
Button("Run Verification Test", systemImage: "checkmark.seal") {
    isConfirmingTest = true
}
.confirmationDialog(
    "Test failover to \(model.settings.hotspotSSID ?? "your hotspot")?",
    isPresented: $isConfirmingTest
) {
    Button("Switch and Test") {
        Task { await model.runSetupVerificationTest() }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("Your Mac will briefly leave the current Wi-Fi network and join the hotspot. Active downloads or calls may be interrupted. TetherLoop offers to return to your Wi-Fi afterwards.")
}
```

Disable the button when `model.settings.hotspotSSID == nil` (`.disabled(model.settings.hotspotSSID == nil)`).

**Verify**: `swift build` → exit 0.

### Step 2: Truthful return handling and a post-test offer (story 9)

In `AppModel.swift`, rework the success branch of `verifyHotspotSetup()`:

1. Add published state for the post-test offer:

```swift
public enum PostVerificationReturn: Equatable {
    case offered(originalSSID: String)
    case stayedOnHotspot          // test started while not on Wi-Fi
}
@Published public private(set) var postVerificationReturn: PostVerificationReturn?
```

2. After a successful (confirmed) test join, **do not auto-join the original network**. Instead set `postVerificationReturn = .offered(originalSSID: originalSSID)` when `originalSSID != nil && originalSSID != hotspot`, else `.stayedOnHotspot` — and record a diagnostic either way (e.g. `"Setup test complete; still on \(hotspot)"`).

3. Add the accept/decline methods:

```swift
public func acceptPostVerificationReturn() async {
    guard case .offered(let original) = postVerificationReturn else { return }
    postVerificationReturn = nil
    do {
        try await networkAdapter.join(ssid: original)
        if settings.trustedSSIDs.contains(original) { lastTrustedSSID = original }
        previousSSID = original
        record(.manualAction, "Returned to Wi-Fi: \(original)")
    } catch {
        record(.networkError, "Could not return to \(original): \(error.localizedDescription)")
    }
}

public func dismissPostVerificationReturn() {
    postVerificationReturn = nil
}
```

(If plan 006 landed, run its `confirmJoin` after the join and route an unconfirmed return into the failure branch.) Note the success log line now only appears when the join did not throw — fixing the truthfulness bug regardless of UI.

4. In `OnboardingView.swift`, present the offer with an `.alert` bound to the published state:

```swift
.alert(
    "Verification succeeded",
    isPresented: Binding(
        get: { model.postVerificationReturn != nil },
        set: { if !$0 { model.dismissPostVerificationReturn() } }
    )
) {
    if case .offered = model.postVerificationReturn {
        Button("Return to Wi-Fi") { Task { await model.acceptPostVerificationReturn() } }
        Button("Stay on Hotspot", role: .cancel) {}
    } else {
        Button("OK", role: .cancel) {}
    }
} message: {
    if case .offered(let ssid) = model.postVerificationReturn {
        Text("Your hotspot works. Return to \(ssid) now?")
    } else {
        Text("Your hotspot works. You were not on Wi-Fi before the test, so TetherLoop stayed on the hotspot. Use Return to Wi-Fi in the menu when ready.")
    }
}
```

Attach both modifiers at the top-level `VStack` of `OnboardingView.body`.

**Verify**: `swift build` → exit 0; `swift test` → existing verification tests may fail if they asserted the auto-return join — update them to the new contract (the original-network join now only happens through `acceptPostVerificationReturn`).

### Step 3: Notify once per failure episode, plus a final exhaustion notice (story 17)

In `AppModel.swift`:

1. Add `private var hasNotifiedJoinFailure = false`. Reset it to `false` on join success (in the success branch of `joinHotspotIfPossible`), on `protectNow()`, `pauseProtection()`, and `returnToWiFi()`.
2. In the failure branch of `joinHotspotIfPossible`, capture the transition result (after plan 001, `handle` returns it):

```swift
} catch {
    let result = handle(.hotspotJoinFailed(error.localizedDescription))
    record(.hotspotJoinFailed, "Could not join \(hotspot): \(error.localizedDescription)")
    let willRetry = result.intents.contains { if case .scheduleRetry = $0 { return true } else { return false } }
    if !hasNotifiedJoinFailure {
        hasNotifiedJoinFailure = true
        notificationDispatcher.notify(
            title: "TetherLoop could not join hotspot",
            body: willRetry ? "\(error.localizedDescription) — retrying automatically." : error.localizedDescription
        )
    } else if !willRetry {
        notificationDispatcher.notify(
            title: "TetherLoop stopped retrying",
            body: "Could not join \(hotspot). Use Try Hotspot Now after checking the hotspot."
        )
    }
}
```

Diagnostic *log* entries remain per-attempt (logs are the detailed record; notifications are the interrupt).

**Verify**: `swift build` → exit 0; `swift test` → pass.

### Step 4: Regenerate screenshots

Run `swift run GenerateScreenshots` (repo convention after UI changes).

**Verify**: command exits 0; `git status` shows only expected screenshot changes plus in-scope source files.

## Test plan

In `Tests/TetherLoopTests/ViewModelTests.swift`:

1. `testVerificationDoesNotAutoReturnToOriginalNetwork` — verified test run from trusted SSID "Home": after `runSetupVerificationTest()`, assert `network.current == "Phone"` (still on hotspot) and `model.postVerificationReturn == .offered(originalSSID: "Home")`.
2. `testAcceptingReturnOfferJoinsOriginalNetwork` — continue: `await model.acceptPostVerificationReturn()`; assert `network.joinedSSIDs.last == "Home"` and `model.postVerificationReturn == nil`.
3. `testFailedReturnOfferLogsErrorNotSuccess` — make the second join fail (`network.joinResults = [.success(()), .failure(...)]`); accept the offer; assert no diagnostic event message contains `"Returned to Wi-Fi"` and one contains `"Could not return"`.
4. `testVerificationFromNoWiFiSetsStayedOnHotspot` — `network.current = nil` before the test; after success assert `model.postVerificationReturn == .stayedOnHotspot`.
5. `testOnlyFirstRetryFailureNotifies` — dead hotspot (`joinResults` all failures); trusted disconnect, then sleep past two zero/short retries (existing pattern: `try await Task.sleep(nanoseconds: 50_000_000)` after polls — see `testTrustedDisconnectRetriesHotspotAfterFailure`); assert `notifications.count` related to join failure is exactly 1 while retries are still scheduled.
6. `testRetryExhaustionSendsFinalNotification` — construct the model's state machine path to exhaustion by using a short `RetryPolicy` — if the policy is not injectable through `AppModel`, drive `.hotspotJoinFailed` until `delay(forAttempt:)` returns nil (9 failures with default policy; zero-delay only for attempt 0, so instead inject `RetryPolicy(delays: [0])` — `ProtectionStateMachine.init` accepts a `retryPolicy`; `AppModel` currently builds its own machine, so add an internal init parameter `retryPolicy: RetryPolicy = RetryPolicy()` passed through to the machine). Assert the last notification title is `"TetherLoop stopped retrying"`.

Model setup/teardown after existing retry tests (`ViewModelTests.swift:256-291`).

Verification: `swift test` → exit 0, all tests pass.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` and `swift test` exit 0; the 6 new tests exist and pass
- [ ] `grep -n "confirmationDialog" Sources/TetherLoopCore/UI/Onboarding/OnboardingView.swift` → present
- [ ] `grep -n "postVerificationReturn" Sources/TetherLoopCore/App/AppModel.swift` → published property + accept/dismiss methods
- [ ] `grep -n "Returned to Wi-Fi" Sources/TetherLoopCore/App/AppModel.swift` shows the message recorded only inside non-throwing paths (inspect each match)
- [ ] No files outside the in-scope list modified except `assets/screenshots/*` from the generator (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Plan 001's `@discardableResult handle` is absent (Step 3 needs the transition result) — execute plan 001 first or report.
- Existing verification tests encode the auto-return as the *required* contract in a way that suggests the maintainer wants auto-return kept — the PRD says "offer", but if tests/docs explicitly insist otherwise, surface the conflict instead of choosing.
- `GenerateScreenshots` fails after the UI change.

## Maintenance notes

- The post-test offer means a user who ignores the alert stays on the hotspot (burning cellular data). The menu's "Return to Wi-Fi" action covers recovery; Pro's "hotspot data guard" is the eventual systematic answer.
- Reviewer should scrutinize: notification *frequency* semantics — per-episode flag resets (`protectNow`, `pause`, `returnToWiFi`, success) are the contract; a missed reset means a permanently silenced failure notification.
- Deferred: a progress indicator on the verification button while the test runs (double-click currently launches two tests; low harm since joins are idempotent, but worth a `@Published isVerifying` guard someday).
