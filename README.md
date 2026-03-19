# CirqueFix

Restores TrackPoint middle-button scroll on Lenovo laptops with Cirque/Sensel touchpads after Windows lock/unlock or sleep/wake.

## The problem

Lenovo ThinkPads with Cirque/Sensel touchpads have a setting "Use top zone as TrackPoint buttons" that enables middle-button scrolling via the TrackPoint. This setting is stored in the driver but resets to its default (disabled) every time the screen locks and unlocks, or the system wakes from sleep. The official Sensel Control Panel UI re-applies the setting when its window is focused — but only if the UI is open and visible.

## How it works

CirqueFix watches for Windows session unlock events and re-writes the relevant HID registers directly to the touchpad firmware via the Sensel serial pipe protocol (HID report ID 9, usage page 0xFF00). It reads your current settings from the registry (`HKCU\Software\Cirque\Touchpad\Current`) so it always applies whatever you have configured in the Sensel UI.

The mechanism was discovered by decompiling `SenselSerialDevice.dll` from the Cirque Touchpad Custom Settings app, which uses the open-source [HidSharp](https://github.com/IntergatedCircuits/HidSharp) library internally.

## Requirements

- Windows 11 (tested), Windows 10 should work
- Lenovo laptop with Cirque/Sensel touchpad (VID `0x2C2F` or `0x17EF`)
- [Cirque Touchpad Custom Settings](https://apps.microsoft.com/detail/CirqueCorporation.CirqueTouchpadCustomSettings) installed and configured at least once
- [.NET 10 runtime](https://dotnet.microsoft.com/download/dotnet/10.0) (or use the standalone build)

## Installation

### Option A — installer (recommended)

1. Download `CirqueFix-x.x.x-Setup.exe` from [Releases](../../releases)
2. Run it — UAC will prompt for admin (needed to install to Program Files)
3. Follow the wizard — leave "Start automatically at logon" checked
4. Done. CirqueFix starts immediately and after every future logon

To uninstall: **Add/Remove Programs** → CirqueFix → Uninstall.

### Option B — manual (no installer)

Download `CirqueFix.exe` from Releases and run it directly:

```powershell
# Apply once and exit
CirqueFix.exe --once

# Run in background, re-applies after every unlock/wake
CirqueFix.exe --watch
```

To register the startup task manually:
```powershell
schtasks /create /tn "CirqueFix" /tr "\"C:\path\to\CirqueFix.exe\" --watch" /sc onlogon /ru "%USERNAME%" /f /rl limited
```

## Compatibility

Tested on:
- Lenovo ThinkPad with Cirque touchpad, VID `0x2C2F` (Sensel) [Lenovo ThinkPad X1 2-in-1 Aura Edition 21NU-007XPG]
- Windows 11 23H2+

Should work on any device matched by the Cirque Touchpad Custom Settings app (VID `0x2C2F` or `0x17EF`).


## Building from source

```powershell
git clone https://github.com/YOUR_USERNAME/CirqueFix
cd CirqueFix
dotnet build src/CirqueFix.csproj -c Release

# Run tests
dotnet test tests/CirqueFix.Tests.csproj

# Debug build (verbose logging)
dotnet build src/CirqueFix.csproj -c Debug
```

## Legal

CirqueFix is an independent tool and is **not affiliated with, endorsed by, or supported by Cirque Corporation, Sensel, or Lenovo**. "Cirque" and "Sensel" are trademarks of their respective owners, used here solely to identify hardware compatibility.

The protocol implemented here was discovered through lawful reverse engineering for interoperability purposes, consistent with EU Directive 2009/24/EC Article 6 and established US case law (*Sega v. Accolade*, *Sony v. Connectix*). No proprietary source code or copyrighted expression from Cirque or Sensel is included in this project.

## License

MIT — see [LICENSE](LICENSE)

## Contributing

Issues and PRs welcome. If you have a different Cirque/Sensel device and it works (or doesn't), please open an issue with your VID/PID.
