<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="LidGuard icon">
</p>

<h1 align="center">LidGuard</h1>

<p align="center">
  <strong>Laptop theft protection for macOS</strong>
</p>

<p align="center">
  <a href="https://github.com/Erel3/lidguard/releases/latest"><img src="https://img.shields.io/github/v/release/Erel3/lidguard?style=flat-square&color=blue" alt="Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS_14%2B-black?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.2-orange?style=flat-square" alt="Swift">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Erel3/lidguard?style=flat-square" alt="License"></a>
</p>

<p align="center">
  A menu bar app that detects lid close and power disconnect events,<br>
  then tracks your device and sends alerts via Telegram.
</p>

---

## How It Works

```
 Disabled ──arm──▶ Enabled ──trigger──▶ Theft Mode
    ◀──disarm───    ◀──authenticate───
                                          ├─ 📍 Location
    arm: menu, shortcut, BT auto-arm      ├─ 📶 WiFi & IP
    trigger: lid close, power disconnect, ├─ 🔋 Battery
             motion (pickup/carry),       ├─ 🔔 Telegram alerts
             power button                 ├─ 🚨 Siren alarm
    authenticate: Touch ID, Telegram      └─ 🔒 Lock screen overlay
    disarm: Touch ID
```

When theft mode activates, LidGuard sends **tracking updates every 20 seconds** with location, IP, WiFi, and battery status — all controllable remotely via Telegram.

## Features

🛡️ **Theft Detection** — lid close, power disconnect, power button press\
🤚 **Motion Detection** — pickup, tilt, and walking via Apple Silicon accelerometer (helper required)\
📡 **Bluetooth Auto-Arm** — arms when trusted devices (phone, watch) leave range, disarms when they return\
📍 **Device Tracking** — location, IP, WiFi, battery every 20s\
📲 **Telegram Alerts** — instant notifications with full device info\
🎮 **Remote Control** — enable, disable, alarm, status via Telegram bot\
🚨 **Alarm** — synthesized siren or system sounds at max volume (enforced, can't be silenced)\
😴 **Sleep Prevention** — IOKit assertions + `pmset disablesleep`\
🔒 **Lock Screen** — fullscreen "STOLEN DEVICE" overlay with owner contact info\
⌨️ **Global Shortcuts** — system-wide hotkeys for protection toggle and Bluetooth auto-arm toggle\
🔐 **Touch ID** — biometric auth for settings, disable, and quit\
🛑 **Shutdown Blocking** — prevents force quit and shutdown during theft mode\
🔄 **Auto-Update** — checks for new versions and installs with one click\
🚀 **Launch at Login** — start protection automatically via macOS login items

## Install

### Download

Grab the latest `.zip` from [**Releases**](https://github.com/Erel3/lidguard/releases/latest), unzip, and move `LidGuard.app` to `/Applications`.

### Build from Source

```bash
git clone https://github.com/Erel3/lidguard.git
cd lidguard
just run            # build .app with -dev suffix and open
just lint           # run swiftlint
just install        # install to /Applications
```

## Setup

On first launch, LidGuard opens Settings automatically if no notification service is configured.

### Telegram Bot

LidGuard uses a Telegram bot to send alerts and receive remote commands.

1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot`, pick a name and username
3. Copy the **bot token** (looks like `123456789:ABCdefGHI...`)
4. Send any message to your new bot, then open `https://api.telegram.org/bot<TOKEN>/getUpdates`
5. Find your **chat ID** in the response JSON (`"chat":{"id":123456789}`)
6. Paste both into LidGuard Settings → Notifications → Telegram

> The bot only responds to your chat ID — no one else can control it.

### Settings

Settings are organized into five tabs:

| Tab | What's there |
|:----|:-------------|
| **General** | Contact name & phone (shown on lock screen overlay), launch at login, auto-update, reset |
| **Triggers** | Lid close, power disconnect, power button, motion detection toggles; global shortcut for protection toggle |
| **Protection** | Sleep prevention, shutdown blocking, lock screen, alarm sound & volume, auto-alarm |
| **Bluetooth** | Trusted device picker, auto-arm toggle, lock-on-arm option, dedicated global shortcut |
| **Notifications** | Telegram bot token & chat ID, alert and tracking toggles |

> Credentials are stored in macOS Keychain — never synced or uploaded.

## Remote Commands

Control LidGuard from anywhere via your Telegram bot:

| Command | Action |
|:--------|:-------|
| `/stop` or `/safe` | Deactivate theft mode |
| `/enable` | Arm protection |
| `/disable` | Disarm protection |
| `/status` | Device info + current state |
| `/alarm` | Trigger siren |
| `/stopalarm` | Stop siren |

Telegram replies include context-aware button keyboards — no need to type commands manually.

## Menu Bar

LidGuard lives in the menu bar with a custom laptop icon:

| Icon | State |
|:-----|:------|
| Closed eye (dark) | Disabled |
| Open eye (green) | Protection enabled |
| Open eye (red) | Theft mode active |

**Left-click** opens the full menu. **Right-click** quick-toggles protection.\
Hold **Option** while the menu is open to reveal hidden items (test alert, activity log).

## Permissions

| Permission | Why |
|:-----------|:----|
| **Input Monitoring** | Global keyboard shortcuts (protection + Bluetooth toggles) |
| **Accessibility** | Power button monitoring (via helper) |
| **Location Services** | Device tracking in theft mode |
| **Bluetooth** | Trusted-device proximity for auto-arm |
| **Contacts** *(optional)* | Auto-fill owner phone number from your Me card |

The app is **not sandboxed** — it needs direct access to IOKit, CoreAudio, and `pmset` for full theft protection.

## License

[MIT](LICENSE)
