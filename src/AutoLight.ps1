<#
.SYNOPSIS
    Switches Windows between light and dark theme based on the power source.

.DESCRIPTION
    On AC power  -> light theme.
    On battery   -> dark theme.

    Runs as a hidden background process, started at logon by a per-user
    scheduled task. Uses only Windows PowerShell 5.1 and the .NET Framework
    that ships with Windows - no modules, no packages, no admin rights.
#>

[CmdletBinding()]
param(
    # Apply the current state once and exit (used for testing / first run).
    [switch]$Once,

    # Keep the console window visible (used for testing).
    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName     = 'AutoLight'
$script:DataDir     = Join-Path $env:LOCALAPPDATA $script:AppName
$script:LogFile     = Join-Path $script:DataDir 'autolight.log'
$script:ConfigFile  = Join-Path $PSScriptRoot 'config.json'
$script:PersonalizeKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'

# --------------------------------------------------------------------------
# Native helpers (console hiding, power status, settings broadcast)
# --------------------------------------------------------------------------
if (-not ('AutoLight.Native' -as [type])) {
    Add-Type -Namespace 'AutoLight' -Name 'Native' -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct SYSTEM_POWER_STATUS
{
    public byte ACLineStatus;
    public byte BatteryFlag;
    public byte BatteryLifePercent;
    public byte SystemStatusFlag;
    public int  BatteryLifeTime;
    public int  BatteryFullLifeTime;
}

[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);

[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);

[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(
    System.IntPtr hWnd, uint msg, System.IntPtr wParam, string lParam,
    uint flags, uint timeout, out System.IntPtr result);

public static int GetAcLineStatus()
{
    SYSTEM_POWER_STATUS s;
    if (!GetSystemPowerStatus(out s)) { return -1; }
    return (int)s.ACLineStatus; // 0 = battery, 1 = AC, 255 = unknown
}

public static void HideConsole()
{
    System.IntPtr h = GetConsoleWindow();
    if (h != System.IntPtr.Zero) { ShowWindow(h, 0); }
}

public static void BroadcastThemeChange()
{
    const uint WM_SETTINGCHANGE = 0x001A;
    System.IntPtr HWND_BROADCAST = new System.IntPtr(0xFFFF);
    System.IntPtr result;
    foreach (string topic in new[] { "ImmersiveColorSet", "WindowsThemeElement", "UserPreferenceChanged" })
    {
        SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, System.IntPtr.Zero, topic, 2, 1000, out result);
    }
}
'@
}

# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Verbose $line
    try {
        if (-not (Test-Path -LiteralPath $script:DataDir)) {
            New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
        }
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
        $file = Get-Item -LiteralPath $script:LogFile
        if ($file.Length -gt 256KB) {
            $keep = Get-Content -LiteralPath $script:LogFile -Tail 500
            Set-Content -LiteralPath $script:LogFile -Value $keep -Encoding UTF8
        }
    }
    catch {
        # Logging must never take the service down.
    }
}

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------
function Get-Config {
    $config = [pscustomobject]@{
        ApplyToApps   = $true   # window/app colors
        ApplyToSystem = $true   # taskbar and Start menu
        Inverted      = $false  # battery -> light, AC -> dark
        PollSeconds   = 15      # safety net next to the power event
    }

    if (Test-Path -LiteralPath $script:ConfigFile) {
        try {
            $user = Get-Content -LiteralPath $script:ConfigFile -Raw | ConvertFrom-Json
            foreach ($name in $config.PSObject.Properties.Name) {
                if ($user.PSObject.Properties.Name -contains $name) {
                    $config.$name = $user.$name
                }
            }
        }
        catch {
            Write-Log "Ignoring unreadable config.json: $($_.Exception.Message)" 'WARN'
        }
    }

    if ($config.PollSeconds -lt 5) { $config.PollSeconds = 5 }
    return $config
}

# --------------------------------------------------------------------------
# Power / theme
# --------------------------------------------------------------------------
function Test-OnAcPower {
    $status = [AutoLight.Native]::GetAcLineStatus()
    # Unknown (255) or failure (-1): assume AC, a desktop should not go dark.
    return ($status -ne 0)
}

function Get-CurrentTheme {
    try {
        $value = Get-ItemPropertyValue -Path $script:PersonalizeKey -Name 'AppsUseLightTheme' -ErrorAction Stop
        if ($value -eq 1) { return 'Light' } else { return 'Dark' }
    }
    catch {
        return 'Unknown'
    }
}

function Set-Theme {
    param(
        [ValidateSet('Light', 'Dark')][string]$Theme,
        [Parameter(Mandatory)]$Config
    )

    $value = if ($Theme -eq 'Light') { 1 } else { 0 }

    if (-not (Test-Path -LiteralPath $script:PersonalizeKey)) {
        New-Item -Path $script:PersonalizeKey -Force | Out-Null
    }
    if ($Config.ApplyToApps) {
        New-ItemProperty -Path $script:PersonalizeKey -Name 'AppsUseLightTheme' -Value $value -PropertyType DWord -Force | Out-Null
    }
    if ($Config.ApplyToSystem) {
        New-ItemProperty -Path $script:PersonalizeKey -Name 'SystemUsesLightTheme' -Value $value -PropertyType DWord -Force | Out-Null
    }

    [AutoLight.Native]::BroadcastThemeChange()
    Write-Log "Theme set to $Theme."
}

function Sync-Theme {
    param([Parameter(Mandatory)]$Config, [switch]$Force)

    $onAc = Test-OnAcPower
    $wanted = if ($onAc -xor [bool]$Config.Inverted) { 'Light' } else { 'Dark' }

    if ($Force -or (Get-CurrentTheme) -ne $wanted) {
        Set-Theme -Theme $wanted -Config $Config
    }
    return $wanted
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
if (-not $ShowConsole) { [AutoLight.Native]::HideConsole() }

$config = Get-Config

if ($Once) {
    $theme = Sync-Theme -Config $config -Force
    Write-Log "Ran once, applied $theme."
    return
}

# Only one instance per user session.
$mutex = New-Object System.Threading.Mutex($false, "Local\$script:AppName")
if (-not $mutex.WaitOne(0)) {
    Write-Log 'Another instance is already running, exiting.' 'WARN'
    return
}

Write-Log "Started (PID $PID)."

try {
    Sync-Theme -Config $config -Force | Out-Null

    # SystemEvents raises these on AC/battery transitions, resume and unlock.
    $null = Register-ObjectEvent -InputObject ([Microsoft.Win32.SystemEvents]) `
        -EventName 'PowerModeChanged' -SourceIdentifier 'AutoLight.PowerModeChanged'
    $null = Register-ObjectEvent -InputObject ([Microsoft.Win32.SystemEvents]) `
        -EventName 'SessionSwitch' -SourceIdentifier 'AutoLight.SessionSwitch'

    while ($true) {
        # Wakes on a power event, otherwise falls through on the poll interval.
        $null = Wait-Event -Timeout $config.PollSeconds
        Get-Event | Remove-Event -ErrorAction SilentlyContinue

        try {
            Sync-Theme -Config $config | Out-Null
        }
        catch {
            Write-Log "Sync failed: $($_.Exception.Message)" 'ERROR'
        }
    }
}
catch {
    Write-Log "Fatal: $($_.Exception.Message)" 'ERROR'
    throw
}
finally {
    foreach ($id in 'AutoLight.PowerModeChanged', 'AutoLight.SessionSwitch') {
        Unregister-Event -SourceIdentifier $id -ErrorAction SilentlyContinue
    }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    Write-Log 'Stopped.'
}
