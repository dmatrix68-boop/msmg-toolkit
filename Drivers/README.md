# Drivers

Extracted drivers (`*.inf` + files, sub folders are allowed):

| Folder | Applied to |
|---|---|
| `Install` | install.wim – e.g. chipset, storage, network, graphics drivers |
| `Boot` | boot.wim (Windows Setup / WinPE) – storage and network drivers needed during setup |
| `WinRE` | winre.wim (recovery environment) – storage drivers |

`Integrate -> Export drivers of this PC` copies the third-party drivers of the current PC to `Install\Host_<date>`.
Unsigned drivers are only added when the option "Allow unsigned drivers" is enabled.
