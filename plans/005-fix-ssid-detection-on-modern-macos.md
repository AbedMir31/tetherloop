# Plan 005: Fix current-SSID detection on modern macOS so automatic failover actually fires

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat efa3d18..HEAD -- Package.swift Sources/TetherLoopCore/Core/Network Sources/TetherLoopCore/App/AppModel.swift Sources/TetherLoopCore/UI/Onboarding/OnboardingView.swift scripts/package-app.sh Tests/TetherLoopTests`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition. (Plans 001–003 modify
> `AppModel.swift` — expect their gating changes in `pollNetwork`; the
> excerpts below predate them and the integration step explains how to
> compose.)

## Status

- **Priority**: P1 — **launch blocker**
- **Effort**: L
- **Risk**: MED — introduces a system permission flow and changes the network adapter surface
- **Depends on**: plans/001-gate-failover-on-state-machine-verdict.md (land first so the new poll logic composes with the status gate)
- **Category**: bug
- **Planned at**: commit `efa3d18`, 2026-06-11

## Why this matters

TetherLoop's core promise — "when your Mac leaves trusted Wi-Fi, join the saved hotspot" — depends on knowing the current SSID. The only SSID source today is `networksetup -getairportnetwork`, and **on modern macOS that command no longer reports the SSID**. Verified on the maintainer's machine (macOS 26.4.1, build 25E253): with `en0` associated, holding `192.168.1.177`, and owning the default route, the command prints `You are not associated with an AirPort network.` and exits 0. Apple privacy-gated SSID access behind Location Services starting in the macOS 14/15 era; `ipconfig getsummary en0` likewise shows `SSID : <redacted>`.

Consequence in the current code: `currentSSID()` always returns `nil`, so `pollNetwork()` never sees a trusted network, `previousSSID` never becomes non-nil, and **automatic failover never triggers** — while the app looks perfectly healthy (setup, manual test, and menus all work, because joining and listing remembered networks still function). Every user on macOS 15+ ships with a dead core feature.

The fix: read the SSID via CoreWLAN (`CWWiFiClient`), which works when the app has Location Services authorization; ask for that authorization in onboarding; distinguish "associated but SSID unreadable" from "disconnected" so a missing permission can never cause a spurious failover; and surface the permission state in the UI.

## Current state

- `Sources/TetherLoopCore/Core/Network/NetworkInterfaces.swift` — the adapter protocol:

```swift
@MainActor
public protocol NetworkAdapter {
    func currentSSID() async throws -> String?
    func preferredSSIDs() async throws -> [String]
    func join(ssid: String) async throws
}
```

Also contains `NetworkAdapterError` and `FakeNetworkAdapter` (`current: String?`, `preferred: [String]`, `joinResults`, `joinAttempts`, `joinedSSIDs` — used heavily in `Tests/TetherLoopTests/ViewModelTests.swift` and by `AppModel.preview()`).

- `Sources/TetherLoopCore/Core/Network/NetworkSetupClient.swift` — wraps `/usr/sbin/networksetup` through `CommandRunning`/`ProcessCommandRunner`. `currentSSID(device:)` (lines 60–64) parses `-getairportnetwork`; `parseCurrentSSID` (lines 89–99) returns `nil` on "not associated". `preferredSSIDs` and `join` also live here and **still work** — verified: `-listpreferredwirelessnetworks en0` returns the remembered networks list on macOS 26.4.
- `Sources/TetherLoopCore/Core/Network/SystemNetworkAdapter.swift` — production `NetworkAdapter`; delegates everything to `NetworkSetupClient`, caching the Wi-Fi device name.
- `Sources/TetherLoopCore/App/AppModel.swift` — `pollNetwork()` (lines 254–278) treats `currentSSID() == nil` as "disconnected"; `refreshNetworkChoices()` (lines 127–168) publishes `currentSSID` for the UI and auto-defaults the trusted network.
- `Package.swift` — `TetherLoopCore` target links only IOKit (`linkerSettings: [.linkedFramework("IOKit")]`).
- `scripts/package-app.sh` — writes the app bundle `Info.plist` via a heredoc (keys: `CFBundleIdentifier` = `dev.tetherloop.TetherLoop`, `LSUIElement`, etc.). No location-usage keys today.
- `Sources/TetherLoopCore/UI/Onboarding/OnboardingView.swift` — four numbered `setupCard`s in two `HStack` rows.
- Repo conventions: every system effect sits behind a small protocol with a production class + a recording/fake class in the same file (see `PowerAssertionController.swift`, `LoginItemController.swift`). Match that for the location controller. Tests are XCTest, `@MainActor`, constructing `AppModel` with fakes.

Key platform facts for the executor (verified or well-established):
- `CWWiFiClient.shared().interface()?.ssid()` returns the SSID **only when the process has Location Services authorization**; otherwise it returns `nil` even while associated.
- A `CWInterface` that is associated reports a non-nil `wlanChannel()` (and non-nil `bssid()` only with location too — do not rely on bssid). Use `ssid() == nil && wlanChannel() != nil` as "associated, SSID unreadable".
- Location authorization on macOS uses `CLLocationManager`; status `CLAuthorizationStatus.authorized` (macOS-specific case, value also surfaced as `.authorizedAlways`) and `requestWhenInUseAuthorization()` triggers the system prompt **only for bundled apps** with `NSLocationUsageDescription`/`NSLocationWhenInUseUsageDescription` in Info.plist. Unbundled `swift run` cannot show the prompt — that limitation must be documented, not fought.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0 |
| All tests | `swift test` | exit 0 |
| Focused | `swift test --filter ViewModelTests` | all pass |
| Package | `scripts/package-app.sh` | creates `dist/TetherLoop.app` + zip, plutil lint passes |
| Plist check | `plutil -p dist/TetherLoop.app/Contents/Info.plist \| grep -i location` | shows both location usage keys |
| Manual SSID probe (read-only) | `networksetup -getairportnetwork en0` | demonstrates the OS bug ("not associated") while connected |

## Scope

**In scope** (the only files you should modify or create):
- `Package.swift` (link CoreWLAN + CoreLocation)
- `Sources/TetherLoopCore/Core/Network/NetworkInterfaces.swift`
- `Sources/TetherLoopCore/Core/Network/SystemNetworkAdapter.swift`
- `Sources/TetherLoopCore/Core/Network/CoreWLANClient.swift` (create)
- `Sources/TetherLoopCore/Core/Location/LocationAuthorizationController.swift` (create, new directory)
- `Sources/TetherLoopCore/App/AppModel.swift`
- `Sources/TetherLoopCore/UI/Onboarding/OnboardingView.swift`
- `scripts/package-app.sh`
- `Tests/TetherLoopTests/ViewModelTests.swift`
- `README.md` (one short subsection; see Step 8)

**Out of scope** (do NOT touch, even though they look related):
- `NetworkSetupClient.join` / `preferredSSIDs` — they work; join verification is plan 006.
- Replacing the 5-second polling loop with CWWiFiClient event callbacks — attractive follow-up, but it multiplies this plan's risk; see maintenance notes.
- `Sources/GenerateScreenshots` — uses fakes; only adjust if the build breaks because of the protocol change, and then only mechanically.
- The `.untrustedWiFiDisconnected` / state machine logic.

## Git workflow

- Branch: `advisor/005-corewlan-ssid`. Commit per step; messages: short imperative sentences.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Link CoreWLAN and CoreLocation

In `Package.swift`, extend the `TetherLoopCore` target's linker settings:

```swift
linkerSettings: [
    .linkedFramework("IOKit"),
    .linkedFramework("CoreWLAN"),
    .linkedFramework("CoreLocation")
]
```

**Verify**: `swift build` → exit 0.

### Step 2: Model association explicitly in the adapter protocol

In `NetworkInterfaces.swift`, add:

```swift
public enum WiFiNetworkState: Equatable, Sendable {
    case disconnected
    case associated(ssid: String?)   // ssid nil = associated but unreadable (no Location permission)
}
```

Extend the protocol with `func currentNetwork() async throws -> WiFiNetworkState` and keep `currentSSID()` (UI and `refreshNetworkChoices` still use it). Add a protocol extension so implementers only write one:

```swift
public extension NetworkAdapter {
    func currentSSID() async throws -> String? {
        if case .associated(let ssid) = try await currentNetwork() { return ssid }
        return nil
    }
}
```

Update `FakeNetworkAdapter`: add `public var associatedWithoutSSID = false`; implement

```swift
public func currentNetwork() async throws -> WiFiNetworkState {
    if let current { return .associated(ssid: current) }
    return associatedWithoutSSID ? .associated(ssid: nil) : .disconnected
}
```

and delete its now-redundant `currentSSID()` (the extension covers it) — or keep it if `joinResults` logic references `current`; keeping is fine.

**Verify**: `swift build` → exit 0; `swift test` → existing tests still pass.

### Step 3: Create the CoreWLAN client

New file `Sources/TetherLoopCore/Core/Network/CoreWLANClient.swift`:

```swift
import CoreWLAN
import Foundation

public final class CoreWLANClient {
    public init() {}

    public func currentNetwork() -> WiFiNetworkState {
        guard let interface = CWWiFiClient.shared().interface() else {
            return .disconnected
        }
        if let ssid = interface.ssid(), !ssid.isEmpty {
            return .associated(ssid: ssid)
        }
        if interface.wlanChannel() != nil {
            return .associated(ssid: nil)
        }
        return .disconnected
    }
}
```

**Verify**: `swift build` → exit 0.

### Step 4: Use CoreWLAN first in `SystemNetworkAdapter`, with `networksetup` as legacy fallback

In `SystemNetworkAdapter.swift`:

```swift
public func currentNetwork() async throws -> WiFiNetworkState {
    let state = coreWLAN.currentNetwork()
    if case .associated(ssid: nil) = state {
        // Older macOS can still answer via networksetup; try before giving up on the SSID.
        if let legacy = try? await client.currentSSID(device: wifiDevice()), legacy != nil {
            return .associated(ssid: legacy)
        }
    }
    return state
}
```

Inject `coreWLAN: CoreWLANClient = CoreWLANClient()` through the initializer (keep the existing `client` parameter). Remove `SystemNetworkAdapter.currentSSID()` (protocol extension now derives it).

**Verify**: `swift build` → exit 0; `swift test` → pass.

### Step 5: Make `pollNetwork()` permission-aware and never treat "unreadable" as "disconnected"

In `AppModel.swift`, add a published flag `@Published public private(set) var needsLocationPermission = false`, then rework the top of `pollNetwork()`:

```swift
public func pollNetwork() async {
    do {
        let state = try await networkAdapter.currentNetwork()
        let current: String?
        switch state {
        case .associated(let ssid?):
            needsLocationPermission = false
            current = ssid
        case .associated(nil):
            // Associated but SSID unreadable: do NOT treat as a disconnect.
            if !needsLocationPermission {
                needsLocationPermission = true
                record(.networkError, "Wi-Fi SSID is unreadable. Grant TetherLoop Location access in System Settings > Privacy & Security > Location Services so trusted-network detection can work.")
            }
            return
        case .disconnected:
            current = nil
        }
        defer { previousSSID = current }
        // ... existing trusted/disconnect logic unchanged from here on,
        // including the plan-001 `.switching` gate if already landed ...
    } catch {
        record(.networkError, "Network poll failed: \(error.localizedDescription)")
    }
}
```

Important: in the `.associated(nil)` branch we `return` **without** updating `previousSSID`, so a later real disconnect (state `.disconnected`) still sees the last known trusted SSID and fails over correctly.

Also update `refreshNetworkChoices()` (lines 141–152 today): replace the `networkAdapter.currentSSID()` call's result handling so that an `.associated(nil)` state sets `needsLocationPermission = true` (reuse `currentNetwork()` instead of `currentSSID()`).

**Verify**: `swift build` → exit 0; `swift test` → pass.

### Step 6: Location authorization controller + onboarding banner

New file `Sources/TetherLoopCore/Core/Location/LocationAuthorizationController.swift`, following the repo's adapter pattern (protocol + system impl + recording fake in one file):

```swift
import CoreLocation
import Foundation

public protocol LocationAuthorizing {
    var isAuthorized: Bool { get }
    func requestAuthorization()
}

public final class SystemLocationAuthorization: NSObject, LocationAuthorizing {
    private let manager = CLLocationManager()

    public override init() { super.init() }

    public var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways: true
        default: false
        }
    }

    public func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
}

public final class RecordingLocationAuthorization: LocationAuthorizing {
    public var isAuthorized: Bool
    public private(set) var requestCount = 0

    public init(isAuthorized: Bool = false) {
        self.isAuthorized = isAuthorized
    }

    public func requestAuthorization() {
        requestCount += 1
    }
}
```

(If the compiler reports `.authorized` and `.authorizedAlways` are the same case on macOS, keep just the one it accepts.)

Wire it into `AppModel`: new private `let locationAuthorization: LocationAuthorizing` init parameter (default-free — update `live()` to pass `SystemLocationAuthorization()` and `preview()` plus all test call sites to pass `RecordingLocationAuthorization(isAuthorized: true)`), and a public method:

```swift
public func requestLocationPermission() {
    locationAuthorization.requestAuthorization()
    record(.settingsChanged, "Requested Location access for Wi-Fi network detection")
}
```

In `OnboardingView.swift`, above the first `HStack` of cards, add a conditional banner:

```swift
if model.needsLocationPermission {
    HStack(spacing: 10) {
        Image(systemName: "location.slash")
            .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
            Text("Location access needed").font(.headline)
            Text("macOS hides Wi-Fi network names from apps without Location access. TetherLoop only reads the network name; it never tracks location.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Grant Access") { model.requestLocationPermission() }
    }
    .padding(12)
    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
}
```

**Verify**: `swift build` → exit 0; `swift test` → compile errors in tests fixed by adding the new parameter (`RecordingLocationAuthorization(isAuthorized: true)`) to every `AppModel(...)` construction.

### Step 7: Add the Info.plist usage strings to the packaging script

In `scripts/package-app.sh`, inside the Info.plist heredoc, add before `</dict>`:

```xml
  <key>NSLocationUsageDescription</key>
  <string>TetherLoop reads the current Wi-Fi network name to detect when you leave a trusted network. It does not track or store your location.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>TetherLoop reads the current Wi-Fi network name to detect when you leave a trusted network. It does not track or store your location.</string>
</dict>
```

**Verify**: `scripts/package-app.sh` → exits 0; `plutil -p dist/TetherLoop.app/Contents/Info.plist | grep -ci location` → `2`.

### Step 8: Document the requirement

In `README.md`, add one bullet under "Requirements" — "Location Services access for TetherLoop (macOS hides Wi-Fi network names from apps without it; TetherLoop reads the network name only)" — and one step in "First-Time App Setup" after launching: grant Location access when prompted (or via System Settings > Privacy & Security > Location Services). Also note under "Build From Source" that `swift run TetherLoop` cannot show the Location prompt (unbundled processes can't), so trusted-network detection requires the packaged app from `scripts/package-app.sh`.

**Verify**: `grep -ci "location" README.md` → ≥ 3.

## Test plan

In `Tests/TetherLoopTests/ViewModelTests.swift` (after mechanically adding the new `locationAuthorization` parameter to existing constructions):

1. `testAssociatedWithoutSSIDDoesNotTriggerFailover` — verified/enabled settings; poll on trusted SSID ("Home"); then set `network.current = nil; network.associatedWithoutSSID = true`; poll. Assert `network.joinAttempts.isEmpty`, `model.needsLocationPermission == true`, and `model.status` unchanged (still `.protected`).
2. `testUnreadableSSIDThenRealDisconnectStillFailsOver` — continue from the same setup: after the unreadable poll, set `network.associatedWithoutSSID = false` (state becomes `.disconnected`); poll. Assert `network.joinAttempts == ["Phone"]` — proving `previousSSID` survived the unreadable interval.
3. `testReadableSSIDClearsLocationPermissionFlag` — set `needsLocationPermission` via an unreadable poll, then `network.current = "Home"`, poll, assert flag is false.
4. `testRequestLocationPermissionCallsController` — `model.requestLocationPermission()`; assert `recordingLocation.requestCount == 1`.

Model all four after existing `pollNetwork`-based tests (e.g. lines 230–254). The `CoreWLANClient` and `SystemLocationAuthorization` classes are thin system wrappers and are NOT unit-tested (repo convention: system adapters are exercised manually; logic lives behind protocols).

Manual verification checklist (requires the maintainer's machine, packaged app):
- `scripts/package-app.sh && open dist/TetherLoop.app` → Setup window → Location banner appears → Grant Access → macOS prompt appears → after granting, current network shows in Setup and the banner disappears.
- With protection verified+enabled: turn Wi-Fi off (or walk out of range) → hotspot join attempt fires.

Verification: `swift test` → exit 0, all tests pass.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` and `swift test` exit 0; the 4 new tests exist and pass
- [ ] `grep -n "CoreWLAN" Package.swift` shows the linked framework
- [ ] `grep -n "associated(ssid: nil)" Sources/TetherLoopCore/App/AppModel.swift` (or equivalent pattern match) shows the unreadable branch returning early without failover
- [ ] `plutil -p dist/TetherLoop.app/Contents/Info.plist | grep -ci location` → `2` after running `scripts/package-app.sh`
- [ ] `grep -ci "location" README.md` ≥ 3
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- **CoreWLAN still returns a nil SSID in the packaged app after Location access is granted** (manual check). That would mean macOS 26 demands something beyond location authorization (e.g. an entitlement unavailable to ad-hoc-signed apps); the fallback strategy needs a human decision — do not invent one.
- `CWWiFiClient.shared().interface()` requires main-thread-only access patterns that conflict with the `@MainActor` protocol — report the exact compiler/runtime error.
- The protocol change breaks `Sources/GenerateScreenshots` in a way that needs more than adding the new fake parameter.
- Existing tests fail for any reason other than the added `AppModel` init parameter.

## Maintenance notes

- **Follow-up worth planning next**: replace the 5-second `pollNetwork` timer with `CWWiFiClient` event callbacks (`CWEventDelegate`, `startMonitoringEvent(with: .ssidDidChange)`); this cuts failover latency and removes a process spawn per poll. It was deliberately excluded to keep this plan reviewable.
- Plan 006 (join verification) builds on `currentNetwork()` to confirm a join actually landed; land 005 first.
- Reviewer should scrutinize: the `.associated(nil)` early-return in `pollNetwork` — it must not update `previousSSID`, or failover-after-permission-revocation breaks (covered by test 2); and the privacy story in README/banner copy — the app must clearly state that location access is used only to read the SSID, consistent with its no-telemetry positioning.
- If users on macOS ≤ 14 report regressions, the legacy `networksetup` fallback in Step 4 is the suspect — it only engages when CoreWLAN reports associated-without-SSID.
