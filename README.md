<h1 align="center">MSMG Toolkit PS7</h1>

<p align="center">
Windows-11-Image-Servicing mit PowerShell 7 – eine <strong>inoffizielle Neuentwicklung</strong> auf Basis des MSMG Toolkit 13.7.<br>
Nicht mit MSMG oder Microsoft verbunden.
</p>

---

Das Toolkit passt Windows-11-Installationsmedien an: Treiber, Updates, Sprachpakete und Features
integrieren, Apps und Komponenten entfernen, Tweaks setzen, eine Antwortdatei erzeugen und das
Ergebnis als ISO oder bootfähigen USB-Stick ausgeben. Die Funktionalität des alten Batch-Toolkits
(27.700 Zeilen `Toolkit.cmd` + Drittanbieter-Binaries) wurde als PowerShell-7-Modul neu aufgebaut.
Die Wartung der Images läuft über die DISM-Bordmittel von Windows 11, Operationen auf WIM-Dateien
standardmäßig über das mitgelieferte **wimlib** (mit automatischem Rückfall auf DISM).

## Inhalt

- [Was hat sich gegenüber 13.7 geändert?](#was-hat-sich-gegenüber-137-geändert)
- [Voraussetzungen](#voraussetzungen)
- [Schnellstart](#schnellstart)
- [Ordnerstruktur](#ordnerstruktur)
- [Empfohlener Ablauf](#empfohlener-ablauf)
- [WIM-Engine: wimlib mit DISM-Fallback](#wim-engine-wimlib-mit-dism-fallback)
- [Automatisierung: Build-Profile und Modul](#automatisierung-build-profile-und-modul)
- [Tweaks](#tweaks)
- [Bekannte Einschränkungen](#bekannte-einschränkungen)
- [Entwicklung](#entwicklung)
- [Lizenz](#lizenz)

## Was hat sich gegenüber 13.7 geändert?

| Bereich | MSMG Toolkit 13.7 | MSMG Toolkit PS7 |
|---|---|---|
| Sprache | Batch (`Toolkit.cmd`) | PowerShell-7-Modul `MSMGToolkit` |
| Quell-Images | Windows 7, 8.1, 10, 11, Server 2008 R2 – 2022 | **nur Windows 11** (Build ≥ 22000, x64/arm64) |
| Host-System | Windows 7 – 11 | **Windows 11** |
| Werkzeuge | mitgelieferte DISM-Kopien, NSudo, 7-Zip, wimlib, ToolkitHelper, ResourceHacker, dvdburn, esddecrypt | DISM-Cmdlets des Hosts, wimlib 1.14.5 für WIM-Dateien (Fallback DISM), `oscdimg.exe` aus dem Windows ADK (optional, sonst IMAPI2) |
| Rechte | Start als TrustedInstaller (NSudo) | Administrator; geschützte Registry-Schlüssel über SeBackup/SeRestore-Privilegien, ohne ACL-Änderung |
| Tweaks | fest im Skript | datengetrieben in `Config\Tweaks.psd1`, erweiterbar |
| Automatisierung | – | Build-Profile (`Start.ps1 -Build profil.psd1`) und exportierte Cmdlets |
| Sitzungen | Abbruch = Aufräumen beim nächsten Start | gemountete Images werden erkannt, Sitzung kann fortgesetzt werden |
| Tests | – | Pester-Tests + PSScriptAnalyzer in GitHub Actions |

**Entfernt, weil für Windows 11 überholt:** Integration von IE11, .NET 4.6.2/4.8/4.8.1-Paketen, .NET Core 3.1/6/7,
WMF 5.1, RDP 8.x, Edge Legacy/Chromium/WebView2-Paketen, Win32-Rechner und Skins, Sidebar, Microsoft Games,
DirectX 9.0c, DaRT, Thin-PC-Add-ons, Windows To Go, Mixed Reality, Office-UWP-Apps, Media-Center- und
Vorab-Aktivierungs-Token, Windows-7-ESU-Patch, Terminalserver- und UxTheme-Systemdatei-Patches,
Brennen auf DVD, Kopieren von DVD-Laufwerken ohne Dateisystemzugriff, Entschlüsseln verschlüsselter ESDs,
Tweaks für Cortana/Meet Now/News and Interests sowie die ToolkitHelper-Komponentenentfernung.

**Neu:** Features on Demand aus der LOF-ISO, Setup Dynamic Updates, Post-Setup-Installer per
`SetupComplete.cmd` (z. B. PowerShell 7, VC++-Runtime, eigene Tools), Tweaks für Copilot/Recall/Bing-Suche/Telemetrie,
Unattend-Generator mit lokalem Konto und Hardware-Check-Bypass, WIM↔ESD-Konvertierung, Editionswechsel
per `Set-WindowsEdition`, Build-Profile.

> Ein Fehler des Originals wurde dabei behoben: Der Tweak „Downloads-Ordner nicht nach Datum gruppieren"
> schrieb in `HKLM\SOFTWARE` des **Host-Systems** statt in das Image.

Das ursprüngliche Archiv `Toolkit_v13.7.7z` ist in der Git-Historie (Commit `a7ceccb`) weiterhin verfügbar.

## Voraussetzungen

- **Host:** Windows 11 (x64 oder arm64), Administratorrechte
- **PowerShell 7.4 oder neuer:** `winget install Microsoft.PowerShell`
- **Quelle:** Windows-11-Installationsmedium (ISO, DVD/USB, entpackter Ordner oder MCT-/UUP-ESD), 21H2 bis 25H2
- Optional: **Windows ADK – Deployment Tools** für `oscdimg.exe` (empfohlen für ISO-Erstellung; ohne ADK wird IMAPI2 verwendet)
- Optional: **Windows PE Add-on des ADK** für WinPE-Sprachpakete (Sprachintegration in boot.wim/winre.wim)
- Genügend freier Speicher (ca. 25–40 GB je nach Anzahl der Editionen) und ein kurzer Pfad ohne Leerzeichen, z. B. `C:\Toolkit`

## Schnellstart

1. Repository als ZIP herunterladen, **Eigenschaften → Zulassen** (bzw. `Get-ChildItem -Recurse | Unblock-File`) und nach `C:\Toolkit` entpacken.
2. `Start.cmd` doppelklicken (oder `pwsh -File .\Start.ps1`). Das Skript fordert selbst Administratorrechte an.
3. Haftungshinweis mit **A** bestätigen.
4. **Source → Import media from an ISO file** und danach **Select source from <DVD> folder**.

## Ordnerstruktur

| Ordner | Inhalt |
|---|---|
| `MSMGToolkit` | PowerShell-Modul (`Private` = interne Helfer, `Public` = Funktionsbereiche) |
| `Bin` | `x64\wimlib-imagex.exe` + `libwim-15.dll` (wimlib 1.14.5), Lizenzhinweis in `Bin\LICENSES` |
| `Config` | `Tweaks.psd1` (Tweak-Katalog), `BuildProfile.example.psd1`, `WimScript.ini`, `Settings.user.json` (Optionen) |
| `Lists` | Arbeitslisten für Entfernen/Features; `Lists\Templates` enthält Vorlagen für 22H2/23H2 und 24H2/25H2 |
| `XMLs` | Standard-App-Zuordnungen, Start-/Taskleisten-Layouts |
| `DVD` | entpacktes Installationsmedium (wird angelegt) |
| `Drivers\Install\|Boot\|WinRE` | Treiber (\*.inf, Unterordner erlaubt) |
| `Updates\Install\|Boot\|WinRE\|SetupDU` | \*.msu/\*.cab – siehe [Updates/README.md](Updates/README.md) |
| `Packs` | Sprachpakete, FODs, Apps, Post-Setup-Installer – siehe [Packs/README.md](Packs/README.md) |
| `Custom` | eigene Dateien, Schriften, .reg-Dateien, winre.wim, `Autounattend.xml` – siehe [Custom/README.md](Custom/README.md) |
| `Mount`, `Temp`, `Logs`, `ISO` | Arbeitsordner (werden angelegt, nicht versioniert) |

## Empfohlener Ablauf

| Schritt | Menü |
|---|---|
| 1. Medium importieren und Edition(en) auswählen, optional boot.wim und winre.wim mit bearbeiten | **Source** |
| 2. .NET 3.5 → Sprachpakete → Features on Demand → Treiber → **Updates** → Apps | **Integrate** |
| 3. Apps, Pakete, Capabilities entfernen (Listen vorher aus `Lists\Templates` laden und prüfen) | **Remove** |
| 4. Features, App-Zuordnungen, Startlayout, .reg-Dateien, Tweaks | **Customize** |
| 5. `Autounattend.xml` erzeugen oder eigene kopieren | **Unattended** |
| 6. Komponentenbereinigung, dann speichern (optional mit WIM-Rebuild) | **Apply** |
| 7. ISO oder USB-Stick erstellen | **Target** |

Hinweise:

- Updates **nach** Sprachpaketen/FODs/.NET 3.5 integrieren. Werden nach dem Entfernen von Komponenten noch Updates integriert,
  können entfernte Komponenten zurückkommen.
- Windows 11 24H2+ nutzt Checkpoint-Updates: Checkpoint-CU und aktuelles CU gemeinsam in `Updates\Install` legen – sie werden in KB-Reihenfolge integriert.
- USB-Sticks werden als FAT32 formatiert (MBR = BIOS + UEFI, GPT = nur UEFI); eine `install.wim` > 4 GB wird automatisch in `install.swm`-Teile gesplittet.
- Die erzeugte Antwortdatei automatisiert bewusst **keine** Datenträgerpartitionierung – Setup fragt weiterhin nach dem Ziel.

## WIM-Engine: wimlib mit DISM-Fallback

Alle Operationen auf **WIM-/ESD-Dateien** laufen standardmäßig über [wimlib](https://wimlib.net/) (`Bin\x64\wimlib-imagex.exe`),
das dafür meist deutlich schneller ist als DISM:

| Operation | wimlib | DISM-Fallback |
|---|---|---|
| ESD → WIM, Media-Creation-Tool-ESD importieren, Export, WIM ↔ ESD | `export` / `apply` | `Export-WindowsImage` / `Expand-WindowsImage` |
| WIM nach dem Speichern neu aufbauen (Platz freigeben) | `optimize` (ohne Neukomprimierung) | Export aller Indizes in neue Datei |
| Index umbenennen | `info` (direkt in der Datei) | Export aller Indizes |
| Index löschen, Split/Join (SWM), Capture, Apply | `delete`, `split`, `join`, `capture`/`append`, `apply` | entsprechende DISM-Cmdlets |
| `winre.wim` vor dem Mounten aus `install.wim` holen | `extract` | schreibgeschützt mounten + kopieren |

DISM wird automatisch verwendet, wenn wimlib in den Optionen abgeschaltet ist (**Tools → Options → WIM engine**),
`wimlib-imagex.exe` fehlt oder eine wimlib-Operation fehlschlägt (Meldung im Log, halb geschriebene Dateien werden vorher entfernt).
Das **Mounten und Warten** der Images (Pakete, Treiber, Features, Apps, Registry) läuft immer über DISM – wimlib kann
unter Windows keine Images zum Servicing mounten. Auf arm64-Hosts läuft die x64-Version über die Emulation von Windows 11;
ein anderer Pfad kann unter **Options → wimlib-imagex.exe path** gesetzt werden.

## Automatisierung: Build-Profile und Modul

Ein Build-Profil beschreibt den kompletten Ablauf und macht Builds reproduzierbar:

```powershell
Copy-Item .\Config\BuildProfile.example.psd1 .\Config\Firma-Win11-25H2.psd1
# Profil anpassen, dann:
.\Start.ps1 -Build .\Config\Firma-Win11-25H2.psd1
```

Alle Funktionen stehen auch als Cmdlets zur Verfügung (`Get-Command -Module MSMGToolkit`):

```powershell
Import-Module .\MSMGToolkit\MSMGToolkit.psd1
Import-TkSource -Path D:\ISO\Win11_25H2_German_x64.iso -Force
Get-TkSourceImage | Format-Table ImageIndex, ImageName
Select-TkSource -Index 6 -ServiceBoot -ServiceWinRE
Add-TkDriver
Add-TkUpdate
Remove-TkProvisionedApp -ListPath .\Lists\Templates\RemoveApps_W11_24H2-25H2.txt
Invoke-TkTweak -Recommended
Write-TkUnattendXml -RegionalSource Image -Option @{ AccountName = 'Admin'; BypassNetworkRequirement = $true }
Invoke-TkImageCleanup -ResetBase $true
Save-TkSource -Rebuild $true
New-TkIso
```

## Tweaks

Tweaks sind in `Config\Tweaks.psd1` definiert (Registry-Operationen auf SOFTWARE, SYSTEM, DEFAULT oder dem Standardbenutzer-Profil
`NTUSER`). Eigene Tweaks lassen sich dort ohne Codeänderung ergänzen. „Empfohlen" = Teil von **R** im Menü bzw. `Invoke-TkTweak -Recommended`.

| ID | Beschreibung | Kategorie | Empfohlen | Builds |
|---|---|---|:-:|---|
| `BypassHardwareCheck` | Bypass Windows 11 hardware checks (TPM, Secure Boot, CPU, RAM, storage) | Setup & OOBE |  |  |
| `EnableLocalAccountOobe` | Allow OOBE without network / Microsoft account (BypassNRO) | Setup & OOBE |  |  |
| `DisableBitLockerAutoEncryption` | Disable automatic BitLocker device encryption | Setup & OOBE |  |  |
| `DisableOneDriveSetup` | Do not install OneDrive automatically for new users | Setup & OOBE |  |  |
| `DisableEdgeFirstRun` | Hide the Microsoft Edge first run experience | Setup & OOBE |  |  |
| `DisableConsumerFeatures` | Disable automatic installation of promoted / 3rd party apps | Privacy & AI | ✔ |  |
| `DisableCopilot` | Disable Windows Copilot (policy and taskbar button) | Privacy & AI | ✔ | ab 22621 |
| `DisableRecall` | Disable Recall / AI data analysis | Privacy & AI | ✔ | ab 26100 |
| `DisableWebSearch` | Disable Bing web results in Start / Windows Search | Privacy & AI | ✔ |  |
| `ReduceTelemetry` | Reduce diagnostic data, advertising ID and tailored experiences | Privacy & AI | ✔ |  |
| `DisableDriverUpdates` | Disable automatic driver updates through Windows Update | Windows Update |  |  |
| `PinFeatureRelease` | Stay on the current feature release (block automatic upgrades) | Windows Update |  |  |
| `DisableReservedStorage` | Disable reserved storage for Windows Updates | Windows Update |  |  |
| `EnableFullResetBase` | Allow component cleanup with ResetBase in the installed system | Windows Update |  |  |
| `DisableWindowsUpdate` | Disable Windows Update completely | Windows Update |  |  |
| `DisableDefender` | Disable Microsoft Defender Antivirus | Security |  |  |
| `DisableFirewall` | Disable Windows Firewall (all profiles) | Security |  |  |
| `DisableSmartScreen` | Disable SmartScreen and Smart App Control | Security |  |  |
| `ShowFileExtensions` | Show file name extensions | Explorer & Taskbar | ✔ |  |
| `EnableClassicContextMenu` | Use the classic (full) context menu | Explorer & Taskbar |  |  |
| `DisableDownloadsGrouping` | Do not group the Downloads folder by date | Explorer & Taskbar | ✔ |  |
| `TaskbarAlignLeft` | Align the taskbar to the left | Explorer & Taskbar |  |  |
| `HideSearchBox` | Hide the taskbar search box | Explorer & Taskbar |  |  |
| `HideTaskViewButton` | Hide the taskbar Task View button | Explorer & Taskbar |  |  |
| `HideWidgets` | Disable Widgets (taskbar button and news feed) | Explorer & Taskbar | ✔ |  |
| `HideChatIcon` | Hide the taskbar Chat (Teams) button | Explorer & Taskbar | ✔ | bis 22631 |
| `DisableTeamsAutoInstall` | Do not install Microsoft Teams (personal) automatically | Explorer & Taskbar | ✔ | bis 22631 |
| `EnablePhotoViewer` | Register the classic Windows Photo Viewer for common image types | Multimedia & Compatibility |  |  |
| `EnableFMP3ProCodec` | Use the Fraunhofer IIS MPEG Layer-3 Professional codec | Multimedia & Compatibility |  |  |
| `ForceLatestNetFramework` | Run .NET 2.0-3.5 programs on the newest .NET Framework | Multimedia & Compatibility |  |  |

## Bekannte Einschränkungen

- Die tiefgehende Komponentenentfernung des Originals (`ToolkitHelper.exe`, Closed Source) ist nicht enthalten. Entfernt wird über DISM;
  versteckte Pakete können per **Un-hide** sichtbar gemacht werden. Das ist mächtig, aber riskant – Images vor dem Rollout testen.
- wimlib exportiert keine zwei Images mit gleichem Namen in dieselbe Datei; in diesem Fall übernimmt automatisch DISM.
- `BypassNRO` wird von neueren Windows-11-Builds teilweise ignoriert; zuverlässig ist ein lokales Konto in der Antwortdatei.
- `DisableDefender` ist durch Tamper Protection auf aktuellen Builds nur eingeschränkt wirksam.
- Der IMAPI2-Fallback für ISOs ist eine Notlösung; für produktive Medien das Windows ADK (`oscdimg.exe`) installieren.
- Windows formatiert FAT32 nur bis 32 GB – auf größeren Sticks wird eine 32-GB-Partition angelegt.
- Server-Images (z. B. Server 2025) lassen sich auswählen, die Vorlagen sind aber auf Client-Editionen ausgelegt.

## Entwicklung

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-Pester -Path .\tests -Output Detailed
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

GitHub Actions führt beides bei jedem Push auf einem Windows-Runner aus (`.github/workflows/ci.yml`). Die Integrationstests in
`tests\WimOperations.Integration.Tests.ps1` erzeugen kleine Test-WIMs und prüfen alle WIM-Operationen mit wimlib **und** DISM
(benötigen Administratorrechte, sonst werden sie übersprungen).

## Lizenz

Veränderte Version des MSMG Toolkit – Copyright (c) 2013-2024 MSMG. Es gelten die Bedingungen in [LICENSE.txt](LICENSE.txt).
Das mitgelieferte wimlib steht unter eigener Lizenz (wimlib-imagex: GPLv3+), siehe [Bin/LICENSES/wimlib.txt](Bin/LICENSES/wimlib.txt).
Dieses Projekt ist eine inoffizielle Neuentwicklung und steht in keiner Verbindung zu MSMG oder Microsoft.
Windows ist eine eingetragene Marke der Microsoft Corporation. Nutzung auf eigene Gefahr.
