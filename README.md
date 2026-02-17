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
  <img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" alt="Swift">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Erel3/lidguard?style=flat-square" alt="License"></a>
</p>

<p align="center">
  A menu bar app that detects lid close and power disconnect events,<br>
  then tracks your device and sends alerts via Telegram and Pushover.
</p>

---

## How It Works

```
┌──────────┐     lid close / power disconnect     ┌────────────┐
│ Disabled │ ──────────────────────────────────▶  │ Theft Mode │
│          │ ◀──────────────────────────────────  │            │
└──────────┘     Touch ID / Telegram /stop        └────────────┘
                                                        │
                                                        ▼
                                                  📍 Location
                                                  📶 WiFi & IP
                                                  🔋 Battery
                                                  🔔 Telegram alert
                                                  🚨 Siren alarm
                                                  🔒 Lock screen
```

When theft mode activates, LidGuard sends **tracking updates every 20 seconds** with location, IP, WiFi, and battery status — all controllable remotely via Telegram.

## Features

🛡️ **Theft Detection** — lid close, power disconnect, power button press\
📍 **Device Tracking** — location, IP, WiFi, battery every 20s\
📲 **Telegram & Pushover** — instant alerts with full device info\
🎮 **Remote Control** — enable, disable, alarm, status via Telegram bot\
🚨 **Alarm** — siren or system sounds at max volume (enforced, can't be silenced)\
😴 **Sleep Prevention** — IOKit assertions + `pmset disablesleep`\
🔒 **Lock Screen** — fullscreen overlay via SkyLight private API\
⌨️ **Global Shortcut** — system-wide hotkey to arm/disarm\
🔐 **Touch ID** — biometric auth for sensitive actions\
🛑 **Shutdown Blocking** — prevents force quit during theft mode

## Install

### Download

Grab the latest `.zip` from [**Releases**](https://github.com/Erel3/lidguard/releases/latest), unzip, and move `LidGuard.app` to `/Applications`.

### Build from Source

```bash
git clone https://github.com/Erel3/lidguard.git
cd lidguard
make run            # build .app with -dev suffix and open
make install        # install to /Applications
make release        # bump version, build, tag, push, create GitHub release
```

## Setup

On first launch, LidGuard opens Settings automatically.

### Telegram Bot (required)

LidGuard uses a Telegram bot to send alerts and receive remote commands.

1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot`, pick a name and username
3. Copy the **bot token** (looks like `123456789:ABCdefGHI...`)
4. Send any message to your new bot, then open `https://api.telegram.org/bot<TOKEN>/getUpdates`
5. Find your **chat ID** in the response JSON (`"chat":{"id":123456789}`)
6. Paste both into LidGuard Settings → Telegram

> The bot only responds to your chat ID — no one else can control it.

### Pushover (optional)

[Pushover](https://pushover.net) delivers instant push notifications to your phone. Useful as a fast backup channel alongside Telegram.

1. Create an account at [pushover.net](https://pushover.net) and install the mobile app
2. Copy your **User Key** from the Pushover dashboard
3. [Create an application](https://pushover.net/apps/build) to get an **API Token**
4. Paste both into LidGuard Settings → Pushover

### Other Settings

- **Triggers** — which events activate theft mode (lid close, power disconnect, power button)
- **Behaviors** — sleep prevention, shutdown blocking, lock screen, alarm
- **Global Shortcut** — system-wide hotkey to arm/disarm protection

> Credentials are stored locally in `~/.config/lidguard/credentials.json` — never synced or uploaded.

## Remote Commands

Control LidGuard from anywhere via your Telegram bot:

| Command | Action |
|:--------|:-------|
| `/enable` | Arm protection |
| `/disable` | Disarm protection |
| `/status` | Device info + current state |
| `/alarm` | Trigger siren |
| `/stopalarm` | Stop siren |

## Permissions

LidGuard requires these macOS permissions:

| Permission | Why |
|:-----------|:----|
| **Accessibility** | Global keyboard shortcut + power button monitoring |
| **Location Services** | Device tracking in theft mode |

The app is **not sandboxed** — it needs direct access to IOKit, CoreAudio, and `pmset` for full theft protection.

## License

[MIT](LICENSE) — do whatever you want with it.
