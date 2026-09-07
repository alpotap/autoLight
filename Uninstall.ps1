<#
.SYNOPSIS
    Removes AutoLight for the current user.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1
#>

[CmdletBinding()]
param(
    [string]$TaskName = 'AutoLight',

    # Also delete the log file and stored settings.
    [switch]$RemoveData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Scheduled task '$TaskName' removed."
}
else {
    Write-Host "Scheduled task '$TaskName' was not registered."
}

Get-Process -Name 'powershell' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.MainWindowHandle -eq 0 } |
    ForEach-Object {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine
        if ($cmd -and $cmd -like '*AutoLight.ps1*') {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped running instance (PID $($_.Id))."
        }
    }

$dataDir = Join-Path $env:LOCALAPPDATA 'AutoLight'
if ($RemoveData) {
    if (Test-Path -LiteralPath $dataDir) {
        Remove-Item -LiteralPath $dataDir -Recurse -Force
        Write-Host "Removed $dataDir"
    }
}
else {
    $appDir = Join-Path $dataDir 'app'
    if (Test-Path -LiteralPath $appDir) {
        Remove-Item -LiteralPath $appDir -Recurse -Force
        Write-Host "Removed $appDir (log kept in $dataDir)."
    }
}

Write-Host 'AutoLight uninstalled. The current theme is left as-is.'
