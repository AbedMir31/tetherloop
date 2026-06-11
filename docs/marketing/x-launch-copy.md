# X Launch Copy Drafts

Do not publish automatically. These are drafts for manual posting.

## Primary Post

I got tired of long Claude Code/Codex runs dying the second I left Wi-Fi.

So I built TetherLoop: a free, open-source Mac menu bar app that switches to your saved hotspot when a trusted Wi-Fi network disconnects.

No password storage.
No telemetry.
No terminal scraping.

It is built for the exact moment where your Mac is still awake, your agent is still working, but your network just disappeared.

GitHub: [link]

## Short Version

Built a free Mac app for a stupidly specific developer problem:

You leave Wi-Fi while Claude Code/Codex is still running.

TetherLoop watches trusted Wi-Fi disconnects and fails over to your saved hotspot.

Open source. No telemetry. No password storage.

GitHub: [link]

## Builder Story Thread

1/ I kept hitting the same problem with AI coding agents.

Keeping the Mac awake is solved. Amphetamine, caffeinate, power settings, whatever.

But when I left Wi-Fi, the run still lost internet.

2/ So I built TetherLoop.

It is a native Mac menu bar app that watches trusted Wi-Fi networks and switches to a saved hotspot when they disconnect.

The goal is simple: keep long-running Claude Code/Codex jobs online when you leave your desk.

3/ The trust boundary matters.

TetherLoop does not store hotspot passwords. You connect to the hotspot once in macOS, then TetherLoop uses the saved network path.

It also has no telemetry and does not read terminal contents.

4/ Free V1 includes:

- trusted Wi-Fi failover
- one hotspot target
- setup verification
- idle sleep prevention
- local logs
- state-change notifications
- manual controls

5/ Later Pro features I am considering:

- closed-lid mode
- hotspot data guard
- multi-hotspot fallback
- smart return to Wi-Fi
- process/session detection
- CLI/Shortcuts

But the core is free and open source.

6/ If you run Claude Code, Codex, or long terminal jobs on a Mac, this is for that awkward moment where you need to leave but the run is still cooking.

GitHub: [link]

## Launch Reply

Known limitation: Free V1 does not force your phone hotspot on and does not promise closed-lid behavior.

The intended setup is: connect to your hotspot once through macOS, verify it in TetherLoop, then use it as a failover target.

## GitHub Description

Native macOS menu bar app that keeps long-running AI jobs online by failing over from trusted Wi-Fi to a saved hotspot.
