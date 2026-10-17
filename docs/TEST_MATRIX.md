# Device & regression matrix

Run this before calling a build “trustworthy”. The unit tests cover the pure
math, protocol parsing, and sampling policy; this matrix covers the parts that
only real hardware and Spaces can exercise.

## Hardware

| Machine | Why |
|---|---|
| Apple Silicon laptop (M-series) | Battery power telemetry, Wi-Fi RSSI |
| Apple Silicon desktop (Mac mini / Studio) | No `AppleSmartBattery`: power must show `—`, not 0.0 W |
| Intel Mac (if supported by the target macOS) | GPU/telemetry paths differ |
| Multi-GPU / eGPU machine | `IOAccelerator` order and `Device Utilization %` availability |

## Network

- Wi-Fi, Ethernet, iPhone USB/Bluetooth tethering, VPN (`utun`), offline.
- Switch interfaces while the HUD is visible; the first tick after a switch
  must be a dash/zero and never a spike.
- 1 GbE and 10 GbE (or as close as available). Leave a large transfer running
  for several minutes and compare against `netstat -ib`; the counter must not
  wrap every ~34 s (1 GbE) or ~3.4 s (10 GbE).
- Sleep/wake, screen lock/unlock, and a manual clock change: rates must not
  jump or become negative.

## Displays / Spaces

- Multiple displays with different scale factors.
- Full-screen app with “Show in fullscreen” on and off.
- Stage Manager / Mission Control Space changes.

## Power / thermal / memory

- Battery and AC, including charging; desktop with no battery.
- Low Power Mode.
- Thermal pressure: idle, sustained CPU load, and a full-screen video.
- Memory pressure: normal, warning, and critical if it can be induced safely.
  The PRS tag must show #N, #W or #C with the matching colour; normal must
  not show a warning level.

## Release

- Clean worktree, tag `vX.Y.Z`, `./build.sh release`.
- Developer ID signature, Hardened Runtime, notarization, stapling, `spctl`.
- Fresh Mac install: Gatekeeper launch, login item, HUD, settings, uninstall.
- Kill/restart `stats_helper` while the app runs; GPU/power/disk must become
  `—` and recover, with no spike.

## Long run

- 24 h and, ideally, 30 days of uptime with the HUD visible.
- Simulated CPU counters near `UInt32.max` (covered by `CPUUsageTests`).
- Repeated settings open/close, Space switching, helper restarts, and display
  hot-plug; check `leaks`/Instruments for growth.
