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

## Windows and HUD position

- With another app frontmost, open Device Information and Settings from the
  menu bar. Both windows must come to the front instead of opening behind the
  other app.
- Choose each HUD corner in Settings and confirm the HUD moves there
  immediately. Quit/relaunch and confirm the chosen corner persists.
- Bottom corners must sit on the bottom of the whole display, beside a bottom
  Dock, not above the Dock's reserved area.
- Right corners must anchor by their right edge: widen the HUD (more columns or
  a larger font scale) and confirm it grows leftwards without crossing the
  right screen edge.
- Set horizontal and vertical margins independently (0 by default) and confirm
  the HUD moves by exactly that many points from the anchored edges.
- Change columns or font scale; the auto-sized HUD must stay anchored in the
  chosen corner. A manual drag is a session adjustment and is discarded on
  relaunch or when the HUD is hidden and shown again.
- Multi-display: the corner is the area of the display the HUD is on.

## Refresh gating

- HUD hidden, menu bar metric CPU: only CPU is read. GPU/disk stay dashes and
  no `stats_helper` read is issued.
- HUD hidden, menu bar metric icon-only: no `stats_helper` process, app CPU
  near zero, and no metric changes. This is the fully paused state.
- HUD visible, menu bar hidden by a full-screen Space (Show in fullscreen on):
  the HUD columns keep refreshing; the status bar metric does not.
- Show in fullscreen off, inside a full-screen Space, HUD hidden:
  - menu bar visible with a metric: only that metric is sampled;
  - menu bar visible with the Semono mark: nothing is sampled;
  - menu bar itself hidden: nothing is sampled.
- Toggle Show HUD from the menu bar; the checkmark, window visibility, and
  sampling scope must all change together, and the state must survive relaunch.
- Menu bar metrics: CPU/GPU/PWR/MEM, PRS (#N/#W/#C), NET (connection type,
  Wi-Fi RSSI, down/up speed), and icon-only. The network item is allowed to be
  wider than the other readouts.
- Settings: the sidebar pages (HUD, Appearance, Columns, Menu Bar, General)
  use the same card/header language as Device Information; every control must
  apply immediately.

## Power / thermal / memory

- Battery and AC, including charging; desktop with no battery.
- Low Power Mode.
- Thermal pressure: idle, sustained CPU load, and a full-screen video.
- Memory pressure: normal, warning, and critical if it can be induced safely.
  The PRS tag must show #N, #W or #C with the matching colour; normal must
  not show a warning level.

## Device Information

- Open it from the menu bar icon (Device Information…); the window must come
  to the front while the HUD stays visible.
- Visit every sidebar category. Empty data types must show the localized
  “No Data” state, not a blank window or an error.
- Compare a few rows against `system_profiler -json <DataType>`; byte counts,
  install dates and vendor tokens (yes/no, spdisplays_*, spairport_*) must
  be formatted, not shown raw.
- Applications, Fonts, Extensions and Frameworks are large: the first 20 rows
  must render quickly, “Show All” must expand the list, and typing in Filter
  must narrow both labels and values.
- Refresh the visible category and switch away/back: the cached report must
  update without flashing an empty state.
- Repeat with each UI language: 🎉, 简体中文, 繁體中文, English, 日本語, 한국어
  and Español. Category names, menus and settings must follow the selected
  language while device names and paths stay verbatim. system_profiler
  technical field labels fall back to English for Spanish/Japanese/Korean.
- The language picker order must be Emoji, Simplified Chinese, Traditional
  Chinese, English, Japanese, Korean, Spanish.
- In Emoji mode, all localized interface strings contain emoji only (no Latin
  letters or digits); the language menu uses flags. Margins show an emoji unit
  and refresh intervals show an emoji unit.
- With system language zh-Hant / zh-TW / zh-HK, Traditional Chinese is the
  default; zh-Hans / zh-CN / zh defaults to Simplified Chinese. An unsupported
  primary system language defaults to English. A legacy stored "zh" resolves
  to Simplified Chinese and a legacy "lzh" resolves to Traditional Chinese.

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
