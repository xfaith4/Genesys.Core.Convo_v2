#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Genesys Conversation Analysis – entry point.
.DESCRIPTION
    1. Loads WPF assemblies.
    2. Imports app modules (never Genesys.Core directly – Gate D).
    3. Resolves Core paths from config + env overrides.
    4. Calls Initialize-CoreAdapter (Gate A).
    5. Loads XAML\MainWindow.xaml.
    6. Dot-sources App.UI.ps1.
    7. Wires Window.Closing to persist last date/time filters.
    8. Runs the WPF message loop.
#>

$AppDir = $PSScriptRoot
if (-not $AppDir) { $AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

# ── 1. WPF assemblies ─────────────────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName Microsoft.Win32.Primitives  -ErrorAction SilentlyContinue

# ── 2. Import app modules ─────────────────────────────────────────────────────
# Order matters: Config → Auth → CoreAdapter → Index → Export → Reporting → Database
Import-Module (Join-Path $AppDir 'App.Config.psm1')      -Force -ErrorAction Stop
Import-Module (Join-Path $AppDir 'App.Auth.psm1')         -Force -ErrorAction Stop
Import-Module (Join-Path $AppDir 'App.CoreAdapter.psm1')  -Force -ErrorAction Stop
Import-Module (Join-Path $AppDir 'App.Index.psm1')        -Force -ErrorAction Stop -DisableNameChecking
Import-Module (Join-Path $AppDir 'App.Export.psm1')       -Force -ErrorAction Stop
Import-Module (Join-Path $AppDir 'App.Reporting.psm1')    -Force -ErrorAction Stop
Import-Module (Join-Path $AppDir 'App.Database.psm1')     -Force -ErrorAction Stop

# ── 3. Resolve Core paths (env overrides take precedence) ────────────────────
$cfg = Get-AppConfig

$corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $cfg.CoreModulePath }
$catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $cfg.CatalogPath    }
$schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $cfg.SchemaPath     }
$outputRoot  = $cfg.OutputRoot

# ── 4. Gate A: Initialize CoreAdapter ────────────────────────────────────────
try {
    Initialize-CoreAdapter `
        -CoreModulePath $corePath `
        -CatalogPath    $catalogPath `
        -OutputRoot     $outputRoot `
        -SchemaPath     $schemaPath
} catch {
    $errMsg = "Fatal startup error (Gate A – CoreAdapter init failed):`n`n$_`n`nVerify paths:`n  Core   : $corePath`n  Catalog: $catalogPath`n`nFix configuration via Settings or set GENESYS_CORE_MODULE / GENESYS_CORE_CATALOG env vars."
    [System.Windows.MessageBox]::Show($errMsg, 'Genesys Conversation Analysis – Startup Error',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
    exit 1
}

# ── 4b. Gate F: Initialize Database (non-fatal – missing DLL shown in status bar) ──
$script:DatabaseWarning = ''
try {
    Initialize-Database `
        -DatabasePath  $cfg.DatabasePath `
        -SqliteDllPath $cfg.SqliteDllPath `
        -AppDir        $AppDir
} catch {
    $script:DatabaseWarning = "Case store unavailable: $_"
    Write-Warning $script:DatabaseWarning
}

# ── 5. Load XAML ──────────────────────────────────────────────────────────────
$xamlPath = Join-Path $AppDir 'XAML\MainWindow.xaml'
if (-not [System.IO.File]::Exists($xamlPath)) {
    [System.Windows.MessageBox]::Show(
        "XAML file not found: $xamlPath",
        'Startup Error') | Out-Null
    exit 1
}

$xamlContent = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
# Remove x:Class attribute so WPF doesn't try to find a compiled backing class
$xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''

$reader = New-Object System.IO.StringReader($xamlContent)
$xmlReader = [System.Xml.XmlReader]::Create($reader)
try {
    $script:Window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
} catch {
    [System.Windows.MessageBox]::Show(
        "Failed to load XAML: $_",
        'Startup Error') | Out-Null
    exit 1
} finally {
    $xmlReader.Dispose()
    $reader.Dispose()
}

# ── 6. Dot-source App.UI.ps1 ─────────────────────────────────────────────────
. (Join-Path $AppDir 'App.UI.ps1')

# ── 7. Wire Window.Closing – persist dates and stop background run ────────────
$script:Window.Add_Closing({
    param($sender, $e)

    # Stop polling timer
    if ($null -ne $script:State.PollingTimer) {
        try { $script:State.PollingTimer.Stop() } catch { }
    }

    # Stop background runspace
    if ($null -ne $script:State.BackgroundRunJob) {
        try { $script:State.BackgroundRunJob.Ps.Stop() } catch { }
    }
    if ($null -ne $script:State.BackgroundRunspace) {
        try { $script:State.BackgroundRunspace.Close() } catch { }
    }

    # Persist last query range
    try {
        $startDate = $script:DtpStartDate.SelectedDate
        $endDate   = $script:DtpEndDate.SelectedDate
        $cfg2 = Get-AppConfig
        if ($null -ne $startDate) {
            $cfg2 | Add-Member -NotePropertyName 'LastStartDate' -NotePropertyValue $startDate.Value.ToString('o') -Force
        }
        if ($null -ne $endDate) {
            $cfg2 | Add-Member -NotePropertyName 'LastEndDate' -NotePropertyValue $endDate.Value.ToString('o') -Force
        }
        $cfg2 | Add-Member -NotePropertyName 'LastStartTime' -NotePropertyValue $script:TxtStartTime.Text.Trim() -Force
        $cfg2 | Add-Member -NotePropertyName 'LastEndTime' -NotePropertyValue $script:TxtEndTime.Text.Trim() -Force
        Save-AppConfig -Config $cfg2
    } catch { <# non-fatal #> }
})

# ── 8. Run WPF message loop ───────────────────────────────────────────────────
$script:Window.ShowDialog() | Out-Null
