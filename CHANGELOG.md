# Changelog

## 1.1.0 – wimlib as default WIM engine

### Added
- wimlib 1.14.5 (`Bin\x64\wimlib-imagex.exe`, `libwim-15.dll`) as default engine for all operations on WIM/ESD files:
  ESD import/conversion, export, rebuild (`optimize`), rename, delete, split/join, capture, apply and file extraction.
- Automatic DISM fallback when wimlib is disabled, missing or fails (half-written files are removed first).
- Options "WIM engine" (wimlib | dism) and "wimlib-imagex.exe path"; wimlib version in the debug information.
- `Export-TkFileFromWim` extracts single files without a read/write mount; `winre.wim` is now taken directly from
  install.wim before any image is mounted.
- Integration tests that run every WIM operation with wimlib and DISM on the CI Windows runner.

## 1.0.0 – PowerShell 7 rewrite (based on MSMG Toolkit 13.7)

### Removed
- Support for Windows 7, 8.1, 10 and Windows Server 2008 R2 – 2022 (source images and host).
- All bundled binaries: DISM copies (DISM81/DISM10), NSudo, 7-Zip, wimlib, ToolkitHelper, ResourceHacker,
  dvdburn, esddecrypt, PSFExtractor, oscdimg/imagex copies and the app license files.
- Obsolete integrations: IE11, .NET Framework 4.6.2/4.8/4.8.1 packs, .NET Core 3.1/6/7, WMF 5.1, RDP 8.x,
  Edge Legacy/Chromium/WebView2 packs, Win32 Calculator and skins, Sidebar, Microsoft Games, DirectX 9.0c,
  DaRT, Thin PC add-ons, Windows To Go, Windows Mixed Reality, Office UWP apps, Portable Devices, Braille pack,
  Media Center and pre-activation tokens, Windows 7 ESU, Terminal Server and UxTheme system file patches.
- DVD burning, DVD copy without file system access, decryption of encrypted ESDs.
- Tweaks for Cortana, Meet Now and News and Interests (not present in Windows 11).
- ToolkitHelper based component removal (closed source).

### Added
- PowerShell 7 module `MSMGToolkit` with exported cmdlets (`*-Tk*`) and an interactive menu (`Start.ps1`/`Start.cmd`).
- Build profiles for unattended, repeatable builds (`Start.ps1 -Build profile.psd1`).
- Session recovery: mounted images are detected after a restart and can be resumed or discarded.
- Features on Demand integration (LOF ISO), Setup Dynamic Update expansion, update ordering for checkpoint CUs.
- Post-setup installers via `SetupComplete.cmd` (MSI/EXE/PS1/CMD with optional silent arguments).
- Data driven tweak catalog (`Config\Tweaks.psd1`) incl. Copilot, Recall, Bing web search, telemetry, Widgets,
  BitLocker auto encryption, OneDrive setup and file extension tweaks.
- Unattend generator (local account, auto logon, hardware check / network requirement bypass) and validator.
- WIM manager: info, delete, rename, export, WIM↔ESD conversion, split/merge, capture, apply, rebuild.
- Edition upgrade of mounted images (`Set-WindowsEdition`).
- Offline registry writes to TrustedInstaller-protected keys via backup/restore semantics (no ACL changes).
- ISO creation with Windows ADK oscdimg or the built-in IMAPI2 API; USB media with automatic install.wim split.
- Windows 11 list templates for 22H2/23H2 and 24H2/25H2 (apps, packages, capabilities, features).
- Pester tests, PSScriptAnalyzer settings and a GitHub Actions workflow.

### Fixed
- The "Downloads folder grouping" tweak wrote to the host registry instead of the image.
