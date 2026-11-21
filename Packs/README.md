# Packs

Content you download yourself (Microsoft does not allow redistributing it). The folders are created on first start.

| Folder | Content | Menu |
|---|---|---|
| `LanguagePacks\<lang>\*.cab` | `Microsoft-Windows-Client-Language-Pack_x64_<lang>.cab` and `Microsoft-Windows-LanguageFeatures-*-<lang>-Package~*.cab` from the **Languages and Optional Features ISO** (LOF) | Integrate → Language pack |
| `LanguagePacks\<lang>\WinPE\*.cab` | `lp.cab` and `WinPE-*_<lang>.cab` from the **Windows ADK – Windows PE add-on** (`Windows Preinstallation Environment\<arch>\WinPE_OCs\<lang>`) | Integrate → Language pack |
| `FOD` | Complete content of the LOF ISO (folder `LanguagesAndOptionalFeatures`) | Integrate → Features on Demand |
| `Apps\*.appx\|*.msixbundle` | Store/inbox apps to provision; optional license `<package name>.xml` next to it | Integrate → Inbox apps |
| `Apps\Dependencies` | Framework packages (VCLibs, UI.Xaml, WindowsAppRuntime ...) | Integrate → Inbox apps |
| `PostSetup` | Installers run silently at the end of setup (`*.msi`, `*.msu`, `*.exe`, `*.ps1`, `*.cmd`); silent switches in `<file>.args`; prefix with `01_`, `02_` to control the order | Integrate → Post-setup installers |

Example `PostSetup`:

```
PostSetup\01_PowerShell-7.5.4-win-x64.msi
PostSetup\01_PowerShell-7.5.4-win-x64.msi.args      -> ADD_PATH=1 ENABLE_PSREMOTING=0
PostSetup\02_VC_redist.x64.exe
PostSetup\02_VC_redist.x64.exe.args                 -> /install /quiet /norestart
```

The installers log to `%WINDIR%\Setup\Scripts\PostSetup.log` on the installed system.
