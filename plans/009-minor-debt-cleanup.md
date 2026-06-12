# Plan 009: Remove string-typed join triggers, dead code, and a misleading diagnostic message

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat efa3d18..HEAD -- Sources/TetherLoopCore/App/AppModel.swift Sources/TetherLoopCore/Core/Protection/ProtectionCoordinator.swift Tests/TetherLoopTests/ViewModelTests.swift`
> Plans 001/003/005/006/007 modify `AppModel.swift` heavily — execute this
> plan LAST. Locate code by symbol name; the excerpts below predate the
> other plans.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/001, 006, 007 (this plan refactors the join entry point they touch — land them first to avoid churn)
- **Category**: tech-debt
- **Planned at**: commit `efa3d18`, 2026-06-11

## Why this matters

Three small smells, each cheap now and expensive later:

1. `joinHotspotIfPossible` decides whether to bypass the setup-verification requirement by checking `reason.contains("Manual")` — a human-readable log string doubling as control flow. Anyone rewording a log message can silently change security-relevant gating.
2. `ProtectionCoordinator` is an empty public struct with no references — dead weight that suggests architecture that doesn't exist.
3. When no hotspot is configured, the diagnostic says "Hotspot is not verified" — wrong message for the actual condition, which costs users debugging time during setup.

## Current state

- `Sources/TetherLoopCore/App/AppModel.swift:280-284` (at planned-at commit):

```swift
private func joinHotspotIfPossible(reason: String) async {
    guard let hotspot = settings.hotspotSSID, settings.isSetupVerified || reason.contains("Manual") else {
        record(.hotspotJoinFailed, "Hotspot is not verified")
        return
    }
```

Call sites (verify with `grep -n "joinHotspotIfPossible" Sources/TetherLoopCore/App/AppModel.swift`):
- `tryHotspotNow()` → `reason: "Manual hotspot attempt"` (the only intended verification bypass)
- `pollNetwork()` × 2 → `"Trusted Wi-Fi disconnected"`, `"Wi-Fi disconnected in global mode"`
- `retryHotspotJoin()` → `"Retry hotspot attempt"`

- `Sources/TetherLoopCore/Core/Protection/ProtectionCoordinator.swift` — the entire file:

```swift
import Foundation

public struct ProtectionCoordinator {
    public init() {}
}
```

Confirm zero references: `grep -rn "ProtectionCoordinator" Sources Tests` → only the definition.

- Conventions: enums for closed sets (`ProtectionEvent`, `ProtectionIntent`); diagnostics messages are user-facing sentences.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| All tests | `swift test` | exit 0 |
| Dead-code check | `grep -rn "ProtectionCoordinator" Sources Tests` | no matches after Step 2 |

## Scope

**In scope** (the only files you should modify):
- `Sources/TetherLoopCore/App/AppModel.swift`
- `Sources/TetherLoopCore/Core/Protection/ProtectionCoordinator.swift` (delete)
- `Tests/TetherLoopTests/ViewModelTests.swift` (only if assertions reference the changed message)

**Out of scope** (do NOT touch):
- `Sources/TetherLoopCore/Core/Process/ProcessSnapshotProvider.swift` — also unreferenced by the app, but it is documented PRD groundwork for Pro process detection. Leave it.
- Any behavior change beyond the bypass-gating refactor being semantics-preserving.

## Git workflow

- Branch: `advisor/009-debt-cleanup`. Commit messages: short imperative sentences.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Replace the string check with an explicit trigger type

In `AppModel.swift`, introduce a private enum and thread it through:

```swift
private enum JoinTrigger {
    case automatic(reason: String)   // requires verified setup
    case manual                      // user-initiated; bypasses verification
    case retry                       // requires verified setup

    var logReason: String {
        switch self {
        case .automatic(let reason): reason
        case .manual: "Manual hotspot attempt"
        case .retry: "Retry hotspot attempt"
        }
    }

    var bypassesVerification: Bool {
        if case .manual = self { return true }
        return false
    }
}

private func joinHotspotIfPossible(trigger: JoinTrigger) async {
    guard let hotspot = settings.hotspotSSID else {
        record(.hotspotJoinFailed, "No hotspot target is configured")
        return
    }
    guard settings.isSetupVerified || trigger.bypassesVerification else {
        record(.hotspotJoinFailed, "Hotspot setup is not verified")
        return
    }
    record(.hotspotJoinStarted, "\(trigger.logReason): \(hotspot)")
    ...
}
```

Update the four call sites: `tryHotspotNow()` → `.manual`; `pollNetwork()` → `.automatic(reason: "Trusted Wi-Fi disconnected")` / `.automatic(reason: "Wi-Fi disconnected in global mode")`; `retryHotspotJoin()` → `.retry`. Keep every emitted log string byte-identical to today's output except the two corrected guard messages above.

**Verify**: `swift build` → exit 0; `swift test` → pass (fix any test asserting the old `"Hotspot is not verified"` string).

### Step 2: Delete the dead coordinator

`git rm Sources/TetherLoopCore/Core/Protection/ProtectionCoordinator.swift` after confirming `grep -rn "ProtectionCoordinator" Sources Tests` matches only the definition.

**Verify**: `swift build` → exit 0; `grep -rn "ProtectionCoordinator" Sources Tests` → no matches.

### Step 3: Tests

Add to `ViewModelTests.swift`:

1. `testAutomaticJoinRequiresVerifiedSetup` — configured but unverified settings; trusted disconnect via polls; assert `network.joinAttempts.isEmpty` and a diagnostic message contains `"not verified"`.
2. `testManualTryBypassesVerification` — configured but unverified; `model.tryHotspotNow()`; brief sleep for the spawned Task (existing 50ms pattern); assert one join attempt.
3. `testJoinWithoutHotspotRecordsConfigurationMessage` — no hotspot set; `model.tryHotspotNow()`; assert diagnostic message contains `"No hotspot target"`.

**Verify**: `swift test` → all pass.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` and `swift test` exit 0; the 3 new tests exist and pass
- [ ] `grep -n 'contains("Manual")' Sources/TetherLoopCore/App/AppModel.swift` → no matches
- [ ] `grep -rn "ProtectionCoordinator" Sources Tests` → no matches
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `joinHotspotIfPossible` has structurally changed beyond recognition (plans 006/007 add confirmation and notification logic inside it) and mapping the trigger refactor onto it is ambiguous — describe the conflict instead of guessing.
- `ProtectionCoordinator` has gained references since the planned-at commit.

## Maintenance notes

- The `JoinTrigger` enum is the natural seam for Pro features (process-guard automation will want its own trigger case with its own gating).
- Reviewer should scrutinize: log-string stability — `DiagnosticsTests`/`ViewModelTests` assert on messages, and users may grep their local logs; only the two intentionally corrected messages should differ.
