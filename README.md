<p align="center">
<img src="https://raw.githubusercontent.com/mertizci/duckows/refs/heads/main/Duckows/Assets.xcassets/AppIcon.appiconset/AppIcon-128.png" width="128" />
</p>

<h1 align="center">Duckows</h1>

<p align="center">
A native <b>Windows-style taskbar</b> for macOS — a full-width bar on every display with a Start menu, your open windows <em>by name</em>, and a system tray.
</p>

<p align="center">
<img src="https://img.shields.io/badge/macOS-14.0%2B-000000?logo=apple&logoColor=white" alt="macOS 14.0+" />
<img src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-Universal-555555" alt="Universal binary" />
<img src="https://img.shields.io/badge/Signed%20%26%20Notarized-Apple-brightgreen" alt="Signed & notarized" />
<a href="https://github.com/mertizci/duckows/releases/latest"><img src="https://img.shields.io/github/v/release/mertizci/duckows?label=download&color=blue" alt="Latest release" /></a>
</p>

---

## Why Duckows?

The Dock is centred, icon-only, and tells you nothing about which window is which. Duckows gives you the Windows model instead: one bar spanning the full width of **every** screen, a Start button that opens a searchable, categorised launcher, a button per open window **with its title**, and a tray with the clock, battery, volume and Wi-Fi.

## Install

> A **universal build** that runs natively on Apple Silicon and Intel Macs (macOS 14.0+). Every release is signed with a Developer ID certificate and **notarized by Apple**, so it opens without Gatekeeper warnings.

### 1. DMG — recommended

1. Download `Duckows-X.Y.Z.dmg` from the **[latest release](https://github.com/mertizci/duckows/releases/latest)**.
2. Open the DMG and drag **Duckows** into your **Applications** folder.
3. Launch it from Applications.

### 2. Homebrew

```bash
brew install --cask mertizci/tap/duckows
```

### First launch

macOS marks anything downloaded — including notarized apps — with a quarantine
flag, and holds the app on its first launch until you confirm. Open Duckows
from Applications and click **Open**.

This matters more for Duckows than for most apps: it has no Dock icon and no
window of its own, so if that prompt is missed the app looks like it did
nothing, when it is really just sitting there waiting for an answer. It happens
exactly once.

> Keep Duckows in `/Applications`. macOS App Translocation gives an app run from `~/Downloads` or a mounted disk image a randomised read-only path, which breaks both the login item and the built-in updater.

## Features

- 🪟 **A real taskbar** — full width, on every display, at the bottom or the top.
- 🏷️ **Windows by name** — one button per open window with its title, or grouped per app.
- 🚀 **Start menu** — every installed app, grouped by category, with fuzzy search, pinned and recent apps, settings shortcuts and power actions.
- 🔔 **System tray** — clock and calendar, battery, volume and output switching, Wi-Fi, Bluetooth, brightness, CPU/RAM.
- 🎨 **Themeable** — Liquid Glass on macOS 26, vibrancy on 14–15, or a solid fill; custom tint, opacity, height and corner radius, with a live preview.
- 🫥 **Auto-hide** — slides away until you reach for the screen edge.
- 📐 **Reserves its space** — maximized windows stop at the bar instead of sliding under it.
- 🖥️ **Multi-display** — an independent bar per screen, surviving hot-plug and resolution changes.
- 🔄 **Self-updating** — checks GitHub on launch and installs signature-verified updates in place.

## Permissions

| Permission | Why it's needed | Required? |
| --- | --- | --- |
| **Accessibility** | Read window titles, and raise, minimize and resize windows from the taskbar. | Yes |
| **Screen Recording** | Live window previews on hover. | Optional |
| **Location** | macOS withholds the Wi-Fi network *name* from apps without it. | Optional |
| **Automation** | Sleep, Restart, Shut Down and Log Out from the Start menu. | Optional |

Without Accessibility, Duckows falls back to a per-app bar with no window titles. Nothing is requested at launch except Accessibility.

Duckows sends nothing anywhere. Its only network request is the GitHub release check, which you can turn off.

## The macOS Dock

Duckows takes the Dock's place while it runs and **puts it back exactly as it was** when you quit — including its size, position, magnification and auto-hide setting. That state is saved before anything is changed, so even a crash or a force-quit is recoverable on the next launch.

If the Dock is ever left in a strange state:

```bash
open -a Duckows --args --restore-dock
```

## Requirements

**To run:** macOS 14.0 (Sonoma) or later, Apple Silicon or Intel.

**To build:** Xcode 16+ and an Apple Development signing certificate. A stable signature matters more here than in most projects — the Accessibility grant is keyed to it, so an ad-hoc signature means re-granting the permission after every rebuild.

## Build

```bash
brew install xcodegen   # once
xcodegen generate
xcodebuild -scheme Duckows -destination 'platform=macOS' -configuration Debug build
```

Or open `Duckows.xcodeproj` in Xcode and press ⌘R.

Regenerate the app icon after editing the generator:

```bash
swift scripts/make-app-icon.swift
```

## Configuration

Open settings from the Duckows menu bar item, or by running `open -a Duckows`
while it is already running.

Everything is stored as JSON at:

```
~/Library/Application Support/Duckows/config.json
```

## Uninstall

```bash
brew uninstall --cask duckows
```

Quit Duckows first (or let the cask do it) so the Dock is restored. `brew zap --cask duckows` also removes the configuration.

## Contact

Developed by **Mert IZCI** — [mertizci@gmail.com](mailto:mertizci@gmail.com).

## License

MIT — see [LICENSE](LICENSE).
