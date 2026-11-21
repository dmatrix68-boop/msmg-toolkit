<#
.SYNOPSIS
    Starts MSMG Toolkit PS7 (interactive menu or build profile).
.DESCRIPTION
    Unofficial PowerShell 7 rewrite of MSMG Toolkit for Windows 11 image servicing.
    Requires Windows 11, PowerShell 7.4+ and administrator rights (the script elevates itself).
.PARAMETER Build
    Runs a build profile (.psd1) without the menus, e.g. .\Start.ps1 -Build .\Config\MyBuild.psd1
.PARAMETER AcceptEula
    Skips the disclaimer screen.
.EXAMPLE
    .\Start.ps1
.EXAMPLE
    .\Start.ps1 -Build .\Config\BuildProfile.example.psd1
#>
[CmdletBinding()]
param(
    [string]$Build,
    [switch]$AcceptEula,
    [switch]$DiscardOnError
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'MSMG Toolkit PS7 requires PowerShell 7.4 or later: winget install Microsoft.PowerShell' -ForegroundColor Red
    exit 1
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($Build) { $arguments += '-NoExit' }   # keep the elevated window open to show the build result
    $arguments += @('-File', "`"$PSCommandPath`"")
    if ($Build) { $arguments += @('-Build', "`"$Build`"") }
    if ($AcceptEula) { $arguments += '-AcceptEula' }
    if ($DiscardOnError) { $arguments += '-DiscardOnError' }
    Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -Verb RunAs
    exit 0
}

Import-Module (Join-Path $PSScriptRoot 'MSMGToolkit\MSMGToolkit.psd1') -Force

if ($Build) {
    Invoke-TkBuild -ProfilePath $Build -DiscardOnError:$DiscardOnError
}
else {
    Start-Toolkit -AcceptEula:$AcceptEula
}
