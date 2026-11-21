# Custom

| Path | Content | Menu |
|---|---|---|
| `Files\...` | Files copied into the image root, keeping the folder structure (e.g. `Files\Windows\Web\Wallpaper\Firma\bg.jpg`) | Integrate → Custom files |
| `Fonts\*.ttf\|*.otf\|*.ttc` | Fonts installed for all users | Integrate → Custom fonts |
| `Registry\*.reg` | Registry files; HKLM\SOFTWARE, HKLM\SYSTEM, HKCR, HKCU (= default user) and HKU\.DEFAULT are mapped to the image automatically | Customize → Import registry files |
| `RecoveryImage\winre.wim` | Replacement recovery image | Integrate → Custom recovery image |
| `Autounattend.xml` | Your own answer file | Unattended → Copy personal Autounattend.xml |

The content of this folder is excluded from Git (`.gitignore`) – answer files can contain passwords.
