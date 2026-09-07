# AutoLight

Windows switches to **light theme on AC power** and **dark theme on battery** — automatically, from logon onward.

Plain Windows PowerShell 5.1 and the .NET Framework that already ships with Windows. No modules, no downloads, no admin rights, no third-party dependencies.

## Install

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

That's it. The installer copies the script to `%LOCALAPPDATA%\AutoLight\app`, registers a hidden per-user scheduled task that starts at logon, and starts it immediately.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1          # keeps the log
powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1 -RemoveData
```

The theme is left exactly as it is at that moment.

## How it works

- Power source is read with `GetSystemPowerStatus` (kernel32).
- Theme is set through `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize`
  (`AppsUseLightTheme`, `SystemUsesLightTheme`), followed by a `WM_SETTINGCHANGE` broadcast so
  Explorer and running apps repaint right away.
- It reacts to `SystemEvents.PowerModeChanged` and `SessionSwitch`, with a 15 second poll as a
  safety net, so a missed event can never leave the theme stuck.
- One instance per session (named mutex), automatic restart on failure, and it keeps running on
  battery and while idle.
- If the power state is unknown (a desktop without a battery), it stays on light.

## Configuration

Edit `%LOCALAPPDATA%\AutoLight\app\config.json`, then restart the task
(`Stop-ScheduledTask AutoLight; Start-ScheduledTask AutoLight`).

| Setting | Default | Meaning |
| --- | --- | --- |
| `ApplyToApps` | `true` | Switch app/window colors |
| `ApplyToSystem` | `true` | Switch taskbar and Start menu |
| `Inverted` | `false` | `true` = dark on AC, light on battery |
| `PollSeconds` | `15` | Fallback check interval (minimum 5) |

A reinstall keeps your existing `config.json`.

## Troubleshooting

Log file: `%LOCALAPPDATA%\AutoLight\autolight.log` (auto-trimmed).

Apply the current state once, with a visible console:

```powershell
powershell -ExecutionPolicy Bypass -File .\src\AutoLight.ps1 -Once -ShowConsole -Verbose
```

## License

MIT
