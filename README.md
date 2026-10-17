# Semono

Pixel-art performance HUD overlay for macOS.

## Layout

```
CPU   0%  │ WiFi   -46
MEM   0%  │ ↑       0B
PWR  0.0  │ ↓       0B
```

Four configurable columns:

- **Compute** — CPU / GPU / power draw (watts), percentage or bar mode
- **Memory** — usage, pressure level, swap
- **Storage** — disk read / write throughput, thermal state
- **Network** — connection type + RSSI, upload / download speed
- Color-coded metrics: blue → green → yellow → orange → red

## Data semantics

- A dash (`—`) means the sensor is unavailable or has not produced a baseline
  yet. It is not a zero. A real zero and a failed read are deliberately shown
  differently.
- **Power** comes from `AppleSmartBattery → PowerTelemetryData → SystemLoad`.
  Desktops and batteries without that key show `—`, not `0.0 W`.
- **Disk** is the aggregate of all `IOBlockStorageDriver` statistics — system
  and external block devices — not a single APFS volume.
- **Thermal** is `ProcessInfo.thermalState` (thermal pressure), not a
  temperature sensor.
- **Network** reads the primary service's interface from the kernel's interface
  MIB in 64 bits; the refresh is a rate over a monotonic clock.
- **Memory pressure** maps the system's normal/warning/critical levels to the
  HUD's N/M/H/C scale. Normal does not draw a warning bar.

## Features

- Departure Mono pixel font at 11 pt — crisp on Retina, font scale adjustable
- CPU / GPU / memory / power / disk / network — 1 / 2 / 3 / 5 s refresh
- Wi‑Fi RSSI via CoreWLAN; Ethernet / offline detection — 64-bit byte counters
  track the primary service's interface
- Transparent floating window, draggable anywhere (including tucking under
  the Dock), position remembered across restarts
- Menu bar icon with live metric readout, Open Monitor, Settings and Quit
- Optional overlay in full-screen apps: macOS gives every full-screen app a
  Space of its own, and this setting decides whether the HUD joins them (on =
  visible on every desktop, the full-screen ones included; off = ordinary
  desktops only)
- Sampling sleeps with the HUD: while the HUD is off screen only the menu bar
  metric is still read. With “Show in fullscreen” on (the default) the HUD is
  visible over full-screen apps too, so the sleep path mainly matters when the
  HUD is excluded from a full-screen Space or the monitor is closed.
- Monitor window: double-click the HUD (or use “Open Monitor” in the menu bar)
  for per-metric time-series charts (per-core CPU, GPU, memory, storage,
  network, thermal). History is a 30-point window: ~30 s at 1 s refresh, ~150 s
  at 5 s. The monitor keeps sampling independently of the HUD's Space.
- Chinese / English UI language switch
- Single resident stats helper process serves all GPU / power / disk reads —
  no per-tick subprocess spawning, so the HUD measures the system, not itself

## Settings

| Setting | Options | Default |
|---------|---------|---------|
| Refresh interval | 1 / 2 / 3 / 5 s | 3 s |
| Background opacity | 0 – 100 % | 60 % |
| Show in fullscreen | on / off | on |
| Block display | on / off | off |
| Font | system monospaced fonts | Departure Mono |
| Font scale | −5 … +10 | 0 |
| Columns | Compute / Memory / Storage / Network | all on |
| Menu bar metric | CPU / GPU / PWR / MEM | CPU |
| Launch at login | on / off | off |
| Language | English / 中文 | system |

## Build

macOS 26+ (Tahoe design language), Swift 6, Xcode or Xcode beta
(CommandLineTools lacks the SwiftUI macro plugin used by the macOS 27 SDK).

```bash
./build.sh debug    # builds the app + stats_helper, assembles .build/Semono.app
open .build/Semono.app
swift test          # unit tests (requires an Xcode toolchain, not CommandLineTools)
```

The bundled `stats_helper` executable (GPU / power / disk sampling) is built
and copied into the app bundle automatically. `build.sh` smoke-tests its
protocol, lints the Info.plist, signs the bundle, and verifies the signature.
The script builds for the host architecture; if you distribute to Intel as
well, build both slices for the app **and** the helper and verify with
`lipo -info`.
Release builds refuse a dirty worktree and use the commit count as
`CFBundleVersion` (offset above the legacy scheme), so patch releases
cannot collide with the next minor and updates still sort newer.

For distribution, set a Developer ID Application identity (and Hardened
Runtime signing) instead of ad-hoc:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh release
```

`scripts/notarize.sh` builds, zips, submits with `notarytool`, staples the
ticket, and runs `spctl`. It needs `SIGN_IDENTITY`, `APPLE_ID`, `TEAM_ID`
and `APP_PASSWORD` in the environment. CI (GitHub Actions) runs the tests and
a debug bundle build on every push and pull request.

## License

MIT
