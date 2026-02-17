# LidGuard

macOS menu bar app for laptop theft protection. Detects lid close and power disconnect events, then sends device tracking (location, IP, WiFi, battery) to Telegram and Pushover.

## Features

- **Theft detection** — monitors lid close, power disconnect, and power button press
- **Device tracking** — collects location, IP address, WiFi info, and battery status every 20s in theft mode
- **Notifications** — sends alerts and tracking data via Telegram and Pushover
- **Remote control** — enable/disable protection, trigger alarm, check status via Telegram commands
- **Alarm** — plays siren or system sounds at max volume with volume enforcement
- **Sleep prevention** — blocks system sleep via IOKit assertions and pmset
- **Shutdown blocking** — prevents app termination during theft mode
- **Lock screen overlay** — fullscreen lock message via SkyLight private API
- **Global shortcut** — system-wide hotkey to toggle protection
- **Touch ID** — biometric authentication for sensitive actions

## Requirements

- macOS 14.0+
- Swift 5.9
- Accessibility permission (for global event monitoring)
- Location Services permission
- Not sandboxed (requires IOKit, sudo, Accessibility)

## Build

```bash
make build          # Release build
make run            # Dev build + open
make bundle-prod    # Production .app bundle in dist/
make install        # Install to /Applications
```

## Setup

On first launch, open Settings and configure:

1. **Telegram** — bot token and chat ID for notifications and remote control
2. **Pushover** (optional) — user key and app token for push notifications
3. **Triggers** — choose which events activate theft mode
4. **Behaviors** — sleep prevention, shutdown blocking, lock screen, alarm

Credentials are stored in `~/.config/lidguard/credentials.json`.

## Remote Commands

Send these to your Telegram bot:

| Command | Description |
|---------|-------------|
| `/enable` | Enable protection |
| `/disable` | Disable protection |
| `/status` | Get current status and device info |
| `/alarm` | Trigger alarm |
| `/stopalarm` | Stop alarm |
| `/stop` | Disable protection (alias) |

## License

[MIT](LICENSE)
