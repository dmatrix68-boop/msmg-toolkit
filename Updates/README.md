# Updates

Download updates from the [Microsoft Update Catalog](https://www.catalog.update.microsoft.com/) (search e.g. "2025-11 Cumulative Update Windows 11 Version 25H2 x64").

| Folder | Content | Applied to |
|---|---|---|
| `Install` | Servicing stack update (if separate), cumulative update(s), .NET cumulative update | install.wim |
| `Boot` | Servicing stack update + cumulative update | boot.wim (both indexes) |
| `WinRE` | Servicing stack update + **Safe OS Dynamic Update** | winre.wim |
| `SetupDU` | **Setup Dynamic Update** (`*.cab`) – expanded into the media `sources` folder | DVD\sources |

- Windows 11 24H2 and later use **checkpoint cumulative updates**: put the checkpoint CU and the latest CU into the same
  folder. Files are applied in this order: SSU first, then ascending KB number.
- Integrate updates **after** .NET 3.5, language packs and Features on Demand.
- Microsoft documentation: "Update Windows installation media with Dynamic Update".
