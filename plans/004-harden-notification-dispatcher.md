# Plan 004: Make notifications safe when the app runs unbundled, and request authorization once

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat efa3d18..HEAD -- Sources/TetherLoopCore/Core/Notifications/NotificationDispatcher.swift Tests/TetherLoopTests/NotificationDispatcherTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `efa3d18`, 2026-06-11

## Why this matters

`UserNotificationDispatcher.notify` calls `UNUserNotificationCenter.current()`, which raises an Objective-C `NSInternalInconsistencyException` ("bundleProxyForCurrentProcess is nil") when the process has no app bundle. The README documents `swift run TetherLoop` as a primary way to run the app — that produces an unbundled executable, so the first state-change notification (e.g. a hotspot switch) crashes the whole app mid-failover. Additionally, the dispatcher calls `requestAuthorization` on *every* notify and immediately enqueues the notification without waiting, so the first notification after a fresh install races the permission grant and is typically dropped. Both fixes are small and keep the trust promise ("meaningful notifications on state changes") honest for source-built users.

## Current state

- `Sources/TetherLoopCore/Core/Notifications/NotificationDispatcher.swift:18-32`:

```swift
public final class UserNotificationDispatcher: NotificationDispatching {
    public init() {}

    public func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
```

- The protocol (same file, lines 4–6) is `NotificationDispatching { func notify(title: String, body: String) }`; `RecordingNotificationDispatcher` (lines 8–16) is the test fake.
- The live dispatcher is constructed in `AppModel.live()` (`Sources/TetherLoopCore/App/AppModel.swift:47-56`).
- `Tests/TetherLoopTests/NotificationDispatcherTests.swift` (15 lines) currently tests only the recording fake.
- Packaged builds get a real bundle ID (`dev.tetherloop.TetherLoop`, written by `scripts/package-app.sh`), so notifications work there; the problem is exclusive to unbundled runs (`swift run`, `swift test`).
- Repo conventions: adapters expose dependency-injectable initializers with production defaults (see `NetworkSetupClient.init(runner:executable:)` in `Sources/TetherLoopCore/Core/Network/NetworkSetupClient.swift:41-44`). Match that pattern.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| All tests | `swift test` | exit 0 |
| Focused | `swift test --filter NotificationDispatcherTests` | all pass |
| Manual smoke (optional, requires GUI session) | `swift run TetherLoop` | app launches; no crash when a notification would fire |

## Scope

**In scope** (the only files you should modify):
- `Sources/TetherLoopCore/Core/Notifications/NotificationDispatcher.swift`
- `Tests/TetherLoopTests/NotificationDispatcherTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- `AppModel` notification call sites — the dispatch decision logic is not changing.
- Notification *content/frequency* (retry spam) — that is plan 007.
- `scripts/package-app.sh` — bundled builds already work.

## Git workflow

- Branch: `advisor/004-notification-hardening`. Commit messages: short imperative sentences.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Guard on bundle identity and request authorization once

Rewrite `UserNotificationDispatcher` to (a) detect bundle availability via an injectable `bundleIdentifier` so the guard is unit-testable, (b) never touch `UNUserNotificationCenter` when unbundled, (c) request authorization only on first use:

```swift
public final class UserNotificationDispatcher: NotificationDispatching {
    private let bundleIdentifier: String?
    private var hasRequestedAuthorization = false

    public init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.bundleIdentifier = bundleIdentifier
    }

    public func notify(title: String, body: String) {
        guard bundleIdentifier != nil else {
            NSLog("TetherLoop notification skipped (no app bundle): %@ — %@", title, body)
            return
        }

        let center = UNUserNotificationCenter.current()
        if !hasRequestedAuthorization {
            hasRequestedAuthorization = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
```

Notes for the executor:
- Keep the class non-Sendable/non-actor as it is today; it is only used from the main actor via `AppModel`.
- `import Foundation` and `import UserNotifications` already exist at the top of the file; `NSLog` needs only Foundation.
- Do NOT try to await the authorization result before adding the request — that would change `notify` to async and ripple through the protocol. The first-notification race is acceptable once authorization is requested exactly once (subsequent notifications work); fully solving it (request at app startup) is listed in maintenance notes.

**Verify**: `swift build` → exit 0.

### Step 2: Add tests for the unbundled guard

See test plan. The key constraint: unit tests run unbundled (SwiftPM test runner), so calling the *system* path of `notify` in tests would hit the very crash this plan fixes. Tests must only exercise the `bundleIdentifier: nil` path.

**Verify**: `swift test --filter NotificationDispatcherTests` → all pass.

## Test plan

In `Tests/TetherLoopTests/NotificationDispatcherTests.swift` (extend the existing 15-line file; keep its style):

1. `testUnbundledDispatcherDoesNotCrashOnNotify` — `UserNotificationDispatcher(bundleIdentifier: nil).notify(title: "t", body: "b")` completes without crashing (the test passing IS the assertion).
2. Keep the existing recording-dispatcher test untouched.

Do NOT write a test that constructs `UserNotificationDispatcher()` with the real default and calls `notify` — under `swift test` the default bundle identifier may be non-nil (xctest host) or nil depending on runner, making it flaky, and the non-nil path would touch the real notification center.

Verification: `swift test` → exit 0.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` exits 0
- [ ] `swift test` exits 0; `testUnbundledDispatcherDoesNotCrashOnNotify` exists and passes
- [ ] `grep -n "requestAuthorization" Sources/TetherLoopCore/Core/Notifications/NotificationDispatcher.swift` shows exactly one call site, guarded by `hasRequestedAuthorization`
- [ ] `grep -n "bundleIdentifier" Sources/TetherLoopCore/Core/Notifications/NotificationDispatcher.swift` shows the injectable initializer and the nil guard
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The dispatcher no longer matches the excerpt (drift).
- You find that `notify` is called from off the main actor anywhere (grep call sites of `notificationDispatcher.notify`) — the `hasRequestedAuthorization` flag would then need synchronization; report instead of adding locks.

## Maintenance notes

- Proper fix for the first-notification race: request notification authorization once during app startup (e.g. in `TetherLoopAppDelegate.applicationDidFinishLaunching`) and only for bundled runs. Deferred to keep this plan minimal; do it alongside plan 005's Location-permission onboarding step, which establishes a permission-request flow.
- Reviewer should scrutinize: the guard means `swift run` users get *no* notifications (logged to console instead). That is intentional — README positions `swift run` as a developer path; the packaged app is the user path.
