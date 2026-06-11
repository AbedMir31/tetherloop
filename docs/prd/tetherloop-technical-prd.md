# TetherLoop Technical PRD

Created: 2026-06-11
Status: Ready for agent
Triage label: ready-for-agent

## Problem Statement

Developers increasingly run long-lived AI agent work in local terminals and desktop apps such as Claude Code, Codex, Terminal, iTerm2, Warp, Cursor, and VS Code. These sessions can continue for minutes or hours while the developer moves around. Existing keep-awake utilities help with idle sleep, but they do not solve the connectivity failure that happens when the Mac leaves a trusted Wi-Fi network.

The user wants a native macOS menu bar app that protects these long-running jobs by switching to a previously configured mobile hotspot when the Mac fully disconnects from Wi-Fi. The app must be trustworthy enough for developers because it touches networking, sleep prevention, notifications, and eventually privileged sleep behavior. The first public release should be free and open source for X/GitHub growth, with a later paid Pro version that adds automation and advanced safeguards without neutering the free version.

## Solution

TetherLoop is a native macOS 14+ menu bar app that monitors trusted Wi-Fi disconnects and attempts to join one previously configured hotspot target without storing hotspot passwords. The Free V1 release provides the core protection loop: trusted network selection, hotspot target setup, failover verification, menu bar status, standard idle-sleep prevention, local-only logs, and meaningful notifications.

V1 is distributed as an MIT-licensed open-source project. It intentionally avoids telemetry, terminal scraping, password storage, privileged helper installation, auto-updates, and Pro licensing. The Pro V2 plan adds a 7-day trial and a low-friction paid unlock for advanced closed-lid mode, richer automation, multi-hotspot fallback, hotspot data guard, smart auto-return, session detection, CLI/Shortcuts support, and signed/notarized official builds.

## User Stories

1. As a developer running a long AI job, I want TetherLoop to detect when I leave my trusted Wi-Fi, so that my agent run is not stranded offline.
2. As a developer leaving home Wi-Fi, I want TetherLoop to join my saved phone hotspot, so that Claude Code, Codex, or a terminal job can continue.
3. As a developer, I want to use my macOS remembered hotspot profile, so that TetherLoop never stores my Wi-Fi password.
4. As a developer, I want to select my trusted Wi-Fi networks, so that failover only arms in places where I expect it.
5. As a developer, I want to support more than one trusted Wi-Fi network, so that home, office, and coworking environments can all be protected.
6. As a developer, I want to configure one hotspot target in V1, so that setup remains simple and reliable.
7. As a developer, I want setup to require a successful failover test, so that I know protection actually works before relying on it.
8. As a developer, I want the failover test to tell me before it changes networks, so that I am not surprised by a temporary disconnect.
9. As a developer, I want TetherLoop to offer to return to my prior Wi-Fi after a test, so that onboarding does not leave me on hotspot.
10. As a developer, I want TetherLoop to retry hotspot joins with bounded backoff, so that temporary hotspot visibility delays do not immediately fail protection.
11. As a developer, I want a manual Try Hotspot Now action, so that I can recover from a failed automatic attempt.
12. As a developer, I want a manual Protect Now action, so that I can arm protection even before the app has inferred the right state.
13. As a developer, I want a Pause Protection action, so that I can stop automatic network switching when I do not want it.
14. As a developer, I want the app to show a compact menu bar icon only, so that it does not clutter the menu bar.
15. As a developer, I want the menu to show current status, so that I can quickly see whether TetherLoop is protected, monitoring, switching, on hotspot, failed, or paused.
16. As a developer, I want meaningful notifications on state changes, so that I know when TetherLoop switches networks or fails.
17. As a developer, I want no constant monitoring notifications, so that the app does not become noisy.
18. As a developer, I want standard idle sleep prevention in Free V1, so that my Mac is less likely to suspend an active job while protection is armed.
19. As a developer on battery, I want sleep prevention to be separately toggleable, so that I can choose whether preserving the session is worth the battery tradeoff.
20. As a developer, I want launch at login to be user-controlled, so that the app does not register background behavior without my consent.
21. As a developer, I want local-only event logs, so that I can diagnose what happened without sending telemetry anywhere.
22. As a privacy-conscious developer, I want logs to exclude passwords, full Wi-Fi scans, terminal contents, and command output, so that TetherLoop remains safe to share and inspect.
23. As an open-source user, I want the core app to be MIT licensed, so that I can audit and build it myself.
24. As a contributor, I want the networking, power, process, settings, and diagnostics logic split into testable modules, so that future work can change behavior without rewriting the app.
25. As a developer, I want the README to show screenshots of the app, so that I can quickly understand the onboarding and menu bar flow.
26. As a launch reader on X, I want a concise demo-focused explanation, so that I understand the pain and the payoff immediately.
27. As a future Pro user, I want a 7-day trial, so that I can test advanced protection before buying.
28. As a future Pro user, I want advanced closed-lid mode separated from the free app, so that privileged behavior is explicit and optional.
29. As a future Pro user, I want process/app guard automation, so that protection can arm only when AI or terminal work is actually running.
30. As a future Pro user, I want global failover, so that I can protect against any Wi-Fi disconnect, not just trusted network disconnects.
31. As a future Pro user, I want multi-hotspot fallback, so that a backup hotspot can be tried if my primary phone is unavailable.
32. As a future Pro user, I want smart auto-return, so that the app can return to Wi-Fi only after stability checks and cooldowns.
33. As a future Pro user, I want hotspot data guard, so that a failover does not let background apps burn cellular data.
34. As a future Pro user, I want smarter agent session detection, so that the app can distinguish an idle open app from active work.
35. As a future Pro user, I want a preflight check, so that I can verify hotspot, sleep, process, and battery readiness before leaving Wi-Fi.
36. As a future Pro user, I want CLI and Shortcuts support, so that I can automate protection from scripts and workflows.
37. As a future Pro user, I want session timeline export, so that I can diagnose a protected run after the fact.
38. As a future Pro user, I want signed/notarized official builds and auto-updates, so that I can run the app with less friction.

## Implementation Decisions

- Product name is TetherLoop. Primary domain target is tetherloop.dev. Public positioning is: "Keep long-running AI jobs online when your Mac leaves Wi-Fi."
- Free V1 is the first implementation target. Pro V2 is documented for product architecture boundaries but is out of implementation scope for V1.
- V1 is native macOS 14+ using Swift, SwiftUI, and AppKit where needed for menu bar integration.
- V1 is a menu bar app with icon-only default presentation, a settings window, onboarding, local diagnostics, and system notifications.
- V1 supports multiple trusted source SSIDs and one target hotspot SSID.
- V1 only attempts automatic failover after the Mac disconnects from Wi-Fi while the previously connected source network is trusted, or when manual protection is active.
- V1 does not treat transient internet health failures as failover triggers. The target scenario is physically leaving the trusted Wi-Fi area.
- V1 includes an advanced opt-in global mode in product documentation, but implementation may defer it if needed to keep Free V1 reliable.
- V1 does not store hotspot passwords. Users must connect to the hotspot once through macOS so the system owns credential storage.
- The join backend should be abstracted. The initial implementation can use system-supported network configuration commands for saved network joins and CoreWLAN for interface observation where public APIs are suitable.
- Setup must include a destructive-but-user-initiated failover test that briefly switches to the hotspot and then offers to return to the prior Wi-Fi.
- Protection cannot be enabled until the user has completed setup and the app has recorded a successful test.
- Retry behavior uses bounded backoff. Suggested V1 cadence: immediate attempt, then 15 seconds, 30 seconds, 60 seconds, then every 2 minutes up to a finite session limit.
- Standard idle sleep prevention is implemented with public APIs only and exposed as a separate toggle.
- Advanced closed-lid mode is not implemented in Free V1. It is reserved for Pro V2 because it requires a privileged helper, admin approval, stronger QA, and explicit restore behavior.
- Local logs are append-only diagnostic events with a bounded retention policy. They must never include passwords, terminal contents, full command output, or full ambient network scan dumps.
- Process allowlist automation is documented as a Pro feature. If any V1 process support is included, it must be basic and optional, matching process/app names only without reading terminal content.
- Launch at login is user controlled and must not be silently enabled.
- The codebase should use deep modules with narrow interfaces:
  - Network state and join orchestration module.
  - Protection state machine module.
  - Power assertion module.
  - Settings persistence module.
  - Process detection module.
  - Diagnostics event log module.
  - Notification module.
  - UI composition layer for menu bar, onboarding, and settings.
- The protection state machine should be deterministic and testable independently from CoreWLAN, shell commands, notifications, and SwiftUI views.
- External effects should sit behind protocols/adapters so unit tests can cover behavior without changing the developer's real network state.
- README must include app screenshots. If real app screenshots cannot be captured in CI, generated/local screenshots from the running app are acceptable for the repo until release-quality screenshots are captured.
- X launch work stops at copywriting. No post should be published automatically.
- Pricing plan for future Pro: 7-day free trial, $9 one-time launch price, later $14.99 one-time when mature, optional $29 supporter license.

## Testing Decisions

- Tests should focus on external behavior and state transitions, not private implementation details.
- Network behavior must be tested through fake adapters. Unit tests must not disconnect real Wi-Fi, join real hotspots, or mutate real preferred network settings.
- The protection state machine must be unit tested for trusted disconnect, untrusted disconnect, manual protection, paused state, retry backoff, success, failure, and cooldown behavior.
- Settings persistence must be tested for trusted SSID storage, hotspot target storage, setup verification, launch-at-login preference storage, sleep prevention preference storage, and privacy-safe defaults.
- Diagnostics logging must be tested to verify event ordering, bounded retention, and redaction of sensitive fields.
- Power assertion behavior must be tested through an adapter that records requested assertion changes without invoking real power APIs.
- Process detection must be tested through injected process snapshots rather than live process enumeration.
- Notification behavior must be tested through an adapter that records notification requests and ensures only meaningful state changes notify.
- UI tests are optional for Free V1 but should be considered for onboarding and settings once the app shell is stable.
- Build verification should include Swift tests and at least one local macOS app build.
- Manual verification should include a checklist for current SSID display, setup flow, failover test, hotspot failure message, sleep prevention toggle, logs, notifications, and README screenshots.

## Out of Scope

- Publishing the X post.
- Paid licensing implementation in V1.
- 7-day trial implementation in V1.
- Advanced closed-lid mode in V1.
- Privileged helper installation in V1.
- Sparkle auto-updates in V1.
- App Store distribution in V1.
- Telemetry or remote analytics.
- Terminal contents, command output, or agent transcript inspection.
- Captive portal handling beyond visible failure state.
- Multiple hotspot priority lists in Free V1.
- Hotspot data guard in Free V1.
- Smart auto-return in Free V1.
- CLI and Shortcuts automation in Free V1.
- Background upload of diagnostics.

## Further Notes

TetherLoop's launch wedge is developer trust. The free app must solve the core pain without feeling crippled: a developer should be able to install it, verify hotspot failover, and trust it during long-running AI work. Pro should later monetize automation, advanced system integration, and edge-case safety rather than hiding the basic protection loop.

The README and launch copy should avoid generic "network utility" framing. The strongest hook is practical: developers are running Claude Code, Codex, and terminal agents for long sessions, and TetherLoop helps those jobs survive leaving Wi-Fi.
