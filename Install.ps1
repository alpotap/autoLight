<#
.SYNOPSIS
    Installs AutoLight for the current user.

.DESCRIPTION
    Copies the scripts to %LOCALAPPDATA%\AutoLight\app, registers a hidden
    scheduled task that starts at logon, and starts it right away.
    No administrator rights required.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install.ps1
#>

[CmdletBinding()]
param(
    [string]$TaskName = 'AutoLight'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installDir = Join-Path $env:LOCALAPPDATA 'AutoLight\app'
$source     = Join-Path $PSScriptRoot 'src'
$target     = Join-Path $installDir 'AutoLight.ps1'

if (-not (Test-Path -LiteralPath $source)) {
    throw "Source folder not found: $source"
}

# Stop a previous instance before overwriting its files.
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item -Path (Join-Path $source 'AutoLight.ps1') -Destination $installDir -Force
# Keep an existing config.json so user settings survive a reinstall.
$configTarget = Join-Path $installDir 'config.json'
if (-not (Test-Path -LiteralPath $configTarget)) {
    Copy-Item -Path (Join-Path $source 'config.json') -Destination $installDir -Force
}
Write-Host "Installed to $installDir"

$action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'powershell.exe') `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -DontStopOnIdleEnd `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -Hidden

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Description 'Light theme on AC power, dark theme on battery.' -Force | Out-Null

Write-Host "Scheduled task '$TaskName' registered (starts at logon)."

Start-ScheduledTask -TaskName $TaskName
Write-Host 'AutoLight is running. Log: %LOCALAPPDATA%\AutoLight\autolight.log'
