# Semono

Pixel-art performance HUD overlay for macOS.

<p align="center">
  <img src="docs/images/semono-hero.png" alt="Semono HUD, Settings and Device Information" width="100%">
</p>

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
- **Memory pressure** is a three-state kernel signal shown as a right-aligned
  `#N` (normal), `#W` (warning) or `#C` (critical) tag, coloured by level. It
  is not a percentage and not derived from swap usage.

## Features

- Departure Mono pixel font at 11 pt — crisp on Retina, font scale adjustable
- CPU / GPU / memory / power / disk / network — 1 / 2 / 3 / 5 s refresh
- Wi‑Fi RSSI via CoreWLAN; Ethernet / offline detection — 64-bit byte counters
  track the primary service's interface
- Transparent floating window, draggable during a session, with a four-corner
  position setting (top-left / top-right / bottom-left / bottom-right; default
  bottom-left), independent horizontal and vertical margins (default 0), and
  right-edge anchoring for the right corners. Bottom corners use the whole
  display, on either side of the Dock; the chosen position is re-applied on
  launch, margin changes and content resizes.
- Menu bar icon with a live readout (CPU / GPU / power / memory / memory
  pressure / network status with up/down speed / icon only), a Show HUD switch,
  Device Information, Settings and Quit
- Device Information window: a sidebar of curated `system_profiler` data types
  (hardware, displays, storage, network, software, security, …) with a hardware
  summary, human-readable grouped fields, search, lazy per-category loading and
  collapsible long lists (applications, fonts, extensions, frameworks)
- Optional overlay in full-screen apps: macOS gives every full-screen app a
  Space of its own, and this setting decides whether the HUD joins them (on =
  visible on every desktop, the full-screen ones included; off = ordinary
  desktops only)
- UI-driven sampling: what is on screen decides what is read. With the HUD
  hidden only the menu bar metric is sampled; with the menu bar showing only
  the Semono mark, or with the menu bar itself hidden by a full-screen Space,
  a hidden HUD stops sampling entirely. A hidden status item does not stop the
  HUD columns, and a hidden HUD never reads another column.
- UI languages, in picker order: Emoji 🎉 (an Easter egg whose interface text
  contains no English), Simplified Chinese, Traditional Chinese, English,
  Japanese, Korean and Spanish. The default follows the system's primary
  language (including the Traditional/Simplified Chinese script) and falls
  back to English when unsupported.
- Single resident stats helper process serves all GPU / power / disk reads —
  no per-tick subprocess spawning, so the HUD measures the system, not itself

## Settings

| Setting | Options | Default |
|---------|---------|---------|
| Refresh interval | 1 / 2 / 3 / 5 s | 3 s |
| Background opacity | 0 – 100 % | 60 % |
| Show HUD | on / off (menu bar or settings) | on |
| HUD position | top-left / top-right / bottom-left / bottom-right | bottom-left |
| HUD horizontal margin | 0 – 40 pt | 0 pt |
| HUD vertical margin | 0 – 40 pt | 0 pt |
| Show in fullscreen | on / off | on |
| Block display | on / off | off |
| Font | system monospaced fonts | Departure Mono |
| Font scale | −5 … +10 | 0 |
| Columns | Compute / Memory / Storage / Network | all on |
| Menu bar metric | CPU / GPU / PWR / MEM / PRS / NET / icon only | CPU |
| Launch at login | on / off | off |
| Language | Emoji 🎉 / 简体中文 / 繁體中文 / English / 日本語 / 한국어 / Español | system, then English |

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
