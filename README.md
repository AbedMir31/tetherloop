# TetherLoop

Keep long-running AI jobs online when your Mac leaves Wi-Fi.

TetherLoop is a native macOS menu bar app for developers running Claude Code, Codex, terminal agents, and other long-lived local jobs. When your Mac disconnects from a trusted Wi-Fi network, TetherLoop can attempt to join a hotspot that macOS already remembers.

TetherLoop does not store hotspot passwords, read terminal contents, or send telemetry.

![TetherLoop onboarding](assets/screenshots/onboarding.png)

## What It Does

- Monitors trusted Wi-Fi disconnects
- Fails over to one saved hotspot target
- Requires a setup test before protection can be enabled
- Provides manual Protect Now, Pause Protection, Try Hotspot Now, and Return to Wi-Fi actions
- Includes optional standard idle-sleep prevention
- Keeps local diagnostic logs only
- Shows meaningful state-change notifications
- Runs as an icon-only menu bar app

![TetherLoop menu](assets/screenshots/menu.png)

## What It Does Not Do

- It does not store Wi-Fi or hotspot passwords
- It does not turn on your phone hotspot by force
- It does not read terminal contents or agent output
- It does not send analytics or telemetry
- It does not promise closed-lid operation in Free V1
- It does not install a privileged helper in Free V1

## Requirements

- macOS 14 or newer
- A hotspot that has already been connected to from macOS
- A trusted Wi-Fi network configured in TetherLoop

## Build

```sh
swift build
swift test
```

Run the app from SwiftPM:

```sh
swift run TetherLoop
```

Generate README screenshots:

```sh
swift run GenerateScreenshots
```

## Architecture

TetherLoop keeps system effects behind small adapters so the important behavior can be tested without changing your real network state.

- `Settings`: trusted SSIDs, hotspot target, verification, and toggles
- `Protection`: deterministic state machine and retry policy
- `Network`: saved-network join abstraction backed by macOS network tooling
- `Power`: standard idle-sleep assertion adapter
- `Diagnostics`: bounded local event log with redaction
- `Notifications`: state-change notifications
- `UI`: menu bar, onboarding, settings, and logs

![TetherLoop settings](assets/screenshots/settings.png)

## Free vs Pro Roadmap

Free V1 is the open-source core: trusted Wi-Fi failover, one hotspot target, standard idle-sleep prevention, local logs, and manual controls.

Future Pro work may add a 7-day trial, advanced closed-lid mode, process/app guard automation, multi-hotspot fallback, smart auto-return, hotspot data guard, session detection, CLI/Shortcuts support, timeline export, signed builds, and auto-updates.

## Privacy

TetherLoop is designed for developer trust:

- No telemetry
- No password storage
- No terminal scraping
- No cloud diagnostics
- Local logs only

## License

MIT
