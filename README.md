<div align="center">
  <img src="autowallpaper/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="110" height="110" alt="App Icon" />
  <h1>autowallpaper — macOS Aerial Sunrise & Sunset Switcher</h1>
  <p><strong>Automatically switch native macOS Aerial video wallpapers and screen savers based on local astronomical sunrise/sunset times or a customizable 24-hour timeline.</strong></p>
  <p>
    <strong>English</strong> · <a href="./README_zh.md"><strong>简体中文</strong></a>
  </p>
  <p>
    <a href="https://github.com/Firemount-34/autowallpaper/releases/latest">
      <img src="https://img.shields.io/badge/Release-v1.0.0-blue?style=flat-square" alt="Release v1.0.0" />
    </a>
    <img src="https://img.shields.io/badge/Platform-macOS%2014%2B%20%7C%2015%2B-orange?style=flat-square" alt="Platform macOS" />
    <img src="https://img.shields.io/badge/Size-1.9%20MB-success?style=flat-square" alt="App Size" />
    <img src="https://img.shields.io/badge/Idle%20CPU-0.0%25-brightgreen?style=flat-square" alt="CPU Usage" />
    <a href="./LICENSE">
      <img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" alt="MIT License" />
    </a>
  </p>
</div>

---

## 💡 Inspiration & Acknowledgments

This project is built via **Vibe Coding**, inspired by the creative open-source project [**Aerial Switcher (`YnNJU/aerial-switcher`)**](https://github.com/YnNJU/aerial-switcher) shared by **SSPai (少数派)** author **Yin Ying (尹颍, [@YnNJU](https://github.com/YnNJU))** in the article *"App+1 | Aerial Switcher: Schedule Your Mac's Aerial Wallpapers"*.

Because the original application could not run on my current macOS system environment, yet I was deeply fascinated by the idea of having native macOS Aerial wallpapers transition seamlessly throughout the day, I recreated this utility from scratch through Vibe Coding—paying tribute to the original author's concept while extending it with **astronomical sunrise/sunset scheduling based on local coordinates** and **custom cross-location wallpaper groups**.

- **Original Author**: Yin Ying (尹颍, [**@YnNJU**](https://github.com/YnNJU))
- **Original Repository**: [**https://github.com/YnNJU/aerial-switcher**](https://github.com/YnNJU/aerial-switcher)

---

## 🖥️ Screenshots

### 1. Main Dashboard (Aerial Locations · Interactive 24h Solar Timeline · 5 Time-Period Cards)

<div align="center">
  <img src="docs/screenshots/dashboard-preview.png" width="960" alt="Main Dashboard Preview" />
</div>

### 2. Menu Bar Popover & Dedicated Settings Window

<div align="center">
  <img src="docs/screenshots/menubar-and-settings.png" width="900" alt="Menu Bar Popover and Settings Window" />
</div>

---

## ✨ Key Features

| Feature | Description |
| :--- | :--- |
| 🌅 **Astronomical Sunrise & Sunset Engine** | Powered by the NOAA solar position algorithm. Supports **30+ preset cities**, **CoreLocation GPS detection**, or **manual latitude/longitude coordinates** to accurately calculate daily **Sunrise, Solar Noon, Sunset, and Daylight Duration**, dynamically dividing the day into 5 periods (`Sunrise` → `Morning` → `Day` → `Sunset` → `Night`) with `-60 ~ +60 min` offset fine-tuning. |
| 🕒 **Directly Draggable 24h Timeline** | Drag any of the 5 period handles on the 24-hour timeline bar at any time (snapping to 15-minute increments). Dragging a handle automatically switches the schedule into **Custom 24h Timeline Mode**, with one-click realignment back to today's local solar times. |
| 🗂️ **Curated Locations & Custom Mix-and-Match Groups** | Includes 14 multi-period location sets (**Sonoma**, **Sequoia**, **San Francisco & Golden Gate**, **China / Great Wall**, **Yosemite**, **Grand Canyon**, **Monument Valley**, **New York**, **Los Angeles**, **Hong Kong**, **Dubai**, **London**, **Hawaii**, **Greenland**). Also supports **creating, editing, and deleting custom groups** by mixing any shots across all 137+ native macOS Aerial videos. |
| 📥 **Non-Disruptive Background Downloads & Cache Cleanup** | Uses kernel-level `kqueue` (`DispatchSourceFileSystemObject`) to stay 100% synced with `/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS`. Downloads missing videos in the background via HTTP **without exiting or interrupting your active desktop wallpaper**, seamlessly switching only after the file is 100% ready on disk. Includes one-click deletion of cached `.mov` files to reclaim disk space. |
| ⚙️ **Dedicated Settings & Ultra-Lightweight Footprint** | A separate Settings window manages **Dock icon visibility**, **Launch at Login**, **Screen Saver sync**, **live Memory / CPU / Cache size monitoring**, and **one-click original wallpaper restoration**. Compiled app bundle is only **1.9 MB**, using **0.0% CPU at idle** and **~20 MB RAM**. |

---

## 📦 Installation

### Option 1: Pre-built Installer (Recommended)

Download the latest release from [**GitHub Releases**](https://github.com/Firemount-34/autowallpaper/releases/latest) (or the [`release/`](./release/) directory):

- **[`autowallpaper-1.0.dmg`](https://github.com/Firemount-34/autowallpaper/releases/latest)** (**1.6 MB** — open the DMG and drag `autowallpaper.app` into the `Applications` folder)
- **[`autowallpaper-1.0.zip`](https://github.com/Firemount-34/autowallpaper/releases/latest)** (**1.3 MB** — portable archive)

> **First Launch Note**: Because the app is ad-hoc signed without an Apple Developer notarization certificate, if macOS prompts that the developer cannot be verified on first launch, go to **System Settings ➔ Privacy & Security**, scroll down, and click **Open Anyway**.

### Option 2: Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/Firemount-34/autowallpaper.git
   ```
2. Open `autowallpaper.xcodeproj` in Xcode 16+ and press `Cmd + R` to build and run.

---

## 🛠️ How It Works

Native macOS Aerial video wallpapers are stored as separate individual clips in System Settings and do not automatically transition by time of day. `autowallpaper` bridges this gap by:
1. Parsing `/Library/Application Support/com.apple.idleassetsd/Customer/entries.json`, localized strings in `TVIdleScreenStrings.bundle`, and local preview snapshots;
2. Automatically backing up `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` prior to taking over wallpaper management;
3. Updating the `com.apple.wallpaper.choice.aerials` configuration inside `Index.plist` and restarting `WallpaperAgent` at each scheduled solar transition (as well as on system boot, login, and wake from sleep).

---

## 📄 License

Released under the [MIT License](./LICENSE).
