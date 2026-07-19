# Semono

Pixel-art performance HUD overlay for macOS.

## Layout

```
CPU   0%  │ WiFi   -46
MEM   0%  │ ↑       0B
PWR  0.0  │ ↓       0B
```

- **Left column** — CPU, memory, system power draw (watts)
- **Right column** — connection type + RSSI, upload / download speed
- Color-coded metrics: blue → green → yellow → orange → red

## Features

- Departure Mono pixel font at 11 pt — crisp on Retina
- CPU / memory / power / network throughput — 1–5 s refresh
- Wi‑Fi RSSI via CoreWLAN; Ethernet / offline detection
- Transparent floating window, draggable, position remembered across restarts
- Menu bar icon with Settings and Quit
- Optional fullscreen overlay (restart to apply)

## Settings

| Setting | Options | Default |
|---------|---------|---------|
| Refresh interval | 1 / 2 / 3 / 5 s | 2 s |
| Background opacity | 0 – 100 % | 72 % |
| Show in fullscreen | on / off | on |
| Launch at login | on / off | off |

## Build

macOS 15+, Swift 6.

```bash
./build.sh
open .build/Semono.app
```

## License

MIT
