@echo off
rem MSMG Toolkit PS7 launcher - starts Start.ps1 with PowerShell 7 (elevates itself)
where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh.exe^) was not found.
    echo Install it with:  winget install Microsoft.PowerShell
    pause
    exit /b 1
)
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start.ps1" %*
