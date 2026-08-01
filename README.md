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

## Features

- Departure Mono pixel font at 11 pt — crisp on Retina, font scale adjustable
- CPU / GPU / memory / power / disk / network — 1–5 s refresh
- Wi‑Fi RSSI via CoreWLAN; Ethernet / offline detection
- Transparent floating window, draggable anywhere (including tucking under
  the Dock), position remembered across restarts
- Menu bar icon with live metric readout, Settings and Quit
- Optional fullscreen overlay (restart to apply)
- Monitor window: double-click the HUD for per-metric time-series charts
  (per-core CPU, GPU, memory, storage, network, thermal) with pause-free
  live history
- Chinese / English UI language switch

## Settings

| Setting | Options | Default |
|---------|---------|---------|
| Refresh interval | 1 / 2 / 3 / 5 s | 2 s |
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

macOS 26+ (Tahoe design language), Swift 6, Xcode (CommandLineTools lacks the
SwiftUI macro plugin used by the macOS 27 SDK).

```bash
./build.sh
open .build/Semono.app
```

## License

MIT
