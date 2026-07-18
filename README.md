# Semono

A pixel-art performance HUD for macOS, rendered as a transparent floating overlay.

<img width="312" alt="screenshot" src="https://github.com/user-attachments/assets/placeholder" />

## Features

- **Pixel HUD** — Departure Mono font at 11 pt for sharp rendering on Retina displays
- **Three-in-one** — CPU usage, memory usage, and network throughput in a compact two-line layout
- **Transparent overlay** — borderless floating window, click-through, stays on all Spaces
- **Color-coded metrics** — blue → green → yellow → orange → red gradient
- **Menu bar icon** — quick access to settings and quit

## Layout

```
CPU  0% | ↑   0B
MEM  0% | ↓   0B
```

Each row shows a system metric paired with the corresponding network direction:
- **CPU** → upload speed
- **MEM** → download speed

## Settings

| Setting | Options | Default |
|---------|---------|---------|
| Refresh interval | 1s / 2s / 3s / 5s | 2s |
| Background opacity | 0% – 100% | 72% |
| Launch at login | on / off | off |

## Build

Requires macOS 15+ and Swift 6.

```bash
./build.sh          # build + bundle .app
open .build/Semono.app
```

Or with SwiftPM directly:

```bash
swift build -c release
```

## License

MIT
