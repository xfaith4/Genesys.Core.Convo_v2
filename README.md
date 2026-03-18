# Genesys Conversation Analysis

Desktop analytics workbench for **Genesys Cloud conversation detail analysis** built in PowerShell/WPF. The root of this repository is the only supported app layout and entrypoint.

## Repo Layout

```text
Genesys.Core.ConversationAnalytics_v2/
├── App.ps1
├── App.Config.psm1
├── App.Auth.psm1
├── App.CoreAdapter.psm1
├── App.Index.psm1
├── App.Export.psm1
├── App.Reporting.psm1
├── App.Database.psm1
├── App.UI.ps1
├── XAML/
│   └── MainWindow.xaml
├── tests/
│   ├── Invoke-AllTests.ps1
│   └── Test-Compliance.ps1
├── lib/
│   └── System.Data.SQLite.dll
└── *.md
```

## Canonical Entrypoint

Launch the app from the repo root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ./App.ps1
```

`App.ps1` imports the root modules, initializes the Core adapter, initializes the optional SQLite-backed case store, loads `XAML/MainWindow.xaml`, and dot-sources `App.UI.ps1`.

## Prerequisites

- Windows 10 or 11
- PowerShell 7.2+
- A sibling `Genesys.Core` checkout or equivalent paths configured in app settings
- Genesys Cloud OAuth credentials for interactive use

Expected sibling layout:

```text
<workspace>/
├── Genesys.Core/
└── Genesys.Core.ConversationAnalytics_v2/
```

## Configuration

The app persists user configuration under `%LOCALAPPDATA%\GenesysConversationAnalysis\config.json`.

Important settings:

- `CoreModulePath`
- `CatalogPath`
- `SchemaPath`
- `OutputRoot`
- `DatabasePath`
- `SqliteDllPath`
- `Region`
- `PkceClientId`
- `PkceRedirectUri`

Environment variables override the persisted Core paths at runtime:

- `GENESYS_CORE_MODULE`
- `GENESYS_CORE_CATALOG`
- `GENESYS_CORE_SCHEMA`

## Main Capabilities

- Preview and full conversation-detail runs via `Genesys.Core`
- Indexed paging and drilldown without re-querying the API
- Page, run, and single-conversation export paths
- SQLite-backed case management for imports, notes, findings, bookmarks, tags, saved views, and report snapshots
- Impact-report generation over the currently filtered conversation set

## Tests

Run the full repo guardrail suite from the root:

```powershell
pwsh -NoProfile -File ./tests/Invoke-AllTests.ps1
```

That runner executes:

- Static compliance checks in `tests/Test-Compliance.ps1`
- Architecture/layout invariants for startup, boundaries, indexing, export, reporting, and case-store design

## Design Intent

- `App.CoreAdapter.psm1` is the only module allowed to interact with `Genesys.Core`
- `App.Auth.psm1` contains all direct OAuth calls
- `App.Index.psm1` and `App.Export.psm1` are streaming-oriented and avoid large full-file reads
- `App.Database.psm1` owns the case-store schema and persistence
- `App.Reporting.psm1` computes filtered aggregate reports without re-reading raw data files
