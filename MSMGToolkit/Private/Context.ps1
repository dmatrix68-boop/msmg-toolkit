# ---------------------------------------------------------------------------------------------
# Toolkit context: folder layout, settings and the servicing session (state of mounted images).
# ---------------------------------------------------------------------------------------------

function Initialize-TkContext {
    [CmdletBinding()]
    param(
        [string]$Root = $script:ToolkitRoot
    )

    $paths = [ordered]@{
        Root         = $Root
        Bin          = Join-Path $Root 'Bin'
        Config       = Join-Path $Root 'Config'
        Custom       = Join-Path $Root 'Custom'
        Drivers      = Join-Path $Root 'Drivers'
        DVD          = Join-Path $Root 'DVD'
        ISO          = Join-Path $Root 'ISO'
        Lists        = Join-Path $Root 'Lists'
        Logs         = Join-Path $Root 'Logs'
        Mount        = Join-Path $Root 'Mount'
        Packs        = Join-Path $Root 'Packs'
        Temp         = Join-Path $Root 'Temp'
        Updates      = Join-Path $Root 'Updates'
        XMLs         = Join-Path $Root 'XMLs'
    }
    $paths.Scratch      = Join-Path $paths.Temp 'Scratch'
    $paths.WinReStage   = Join-Path $paths.Temp 'WinRE'
    $paths.MountInstall = Join-Path $paths.Mount 'Install'
    $paths.MountBoot    = Join-Path $paths.Mount 'Boot'
    $paths.MountWinRE   = Join-Path $paths.Mount 'WinRE'
    $paths.SessionFile  = Join-Path $paths.Temp 'session.json'
    $paths.DismLog      = Join-Path $paths.Logs 'Dism.log'

    $script:TK = @{
        Paths       = $paths
        Settings    = Get-TkSetting -ConfigPath $paths.Config
        Session     = New-TkSession
        LoadedHives = [System.Collections.Generic.List[string]]::new()
        LogFile     = $null
    }
}

function Get-TkContext {
    [CmdletBinding()]
    param()
    if (-not $script:TK) { Initialize-TkContext }
    $script:TK
}

function Initialize-TkFolder {
    <# Creates the working folders of the toolkit (only called by Start-Toolkit / Invoke-TkBuild). #>
    [CmdletBinding()]
    param()
    $p = $script:TK.Paths
    $folders = @(
        $p.Custom, $p.DVD, $p.ISO, $p.Logs, $p.Mount, $p.MountInstall, $p.MountBoot, $p.MountWinRE,
        $p.Packs, $p.Temp, $p.Scratch, $p.WinReStage,
        (Join-Path $p.Drivers 'Install'), (Join-Path $p.Drivers 'Boot'), (Join-Path $p.Drivers 'WinRE'),
        (Join-Path $p.Updates 'Install'), (Join-Path $p.Updates 'Boot'), (Join-Path $p.Updates 'WinRE'), (Join-Path $p.Updates 'SetupDU'),
        (Join-Path $p.Packs 'LanguagePacks'), (Join-Path $p.Packs 'FOD'), (Join-Path $p.Packs 'Apps'),
        (Join-Path $p.Packs 'Apps\Dependencies'), (Join-Path $p.Packs 'PostSetup'),
        (Join-Path $p.Custom 'Files'), (Join-Path $p.Custom 'Fonts'), (Join-Path $p.Custom 'Registry'), (Join-Path $p.Custom 'RecoveryImage')
    )
    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder)) {
            $null = New-Item -Path $folder -ItemType Directory -Force
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------------

function Get-TkDefaultSetting {
    [CmdletBinding()]
    param()
    [ordered]@{
        Logging              = $true          # Write a toolkit log file to <Logs>
        ConfirmActions       = $true          # Ask before destructive operations
        DismLogLevel         = 'WarningsInfo' # Errors | Warnings | WarningsInfo
        CleanupResetBase     = $true          # Use /ResetBase during component cleanup
        RebuildOnSave        = $true          # Re-export WIM files after saving (reclaims space)
        ExportCompression    = 'max'          # none | fast | max
        ForceUnsignedDrivers = $false         # Add-WindowsDriver -ForceUnsigned
        IsoLabel             = ''             # Empty = derived from the image (e.g. W11_25H2_X64)
        IsoNoPrompt          = $true          # Use efisys_noprompt.bin (no "Press any key to boot from CD")
        OscdimgPath          = ''             # Empty = auto-detect Windows ADK oscdimg.exe
        UsbPartitionStyle    = 'MBR'          # MBR (BIOS + UEFI) | GPT (UEFI only)
        SwmChunkSizeMB       = 3800           # Split size for install.wim on FAT32 media
        WimEngine            = 'wimlib'       # wimlib (default, DISM as fallback) | dism - for operations on WIM files
        WimlibPath           = ''             # Empty = Bin\<arch>\wimlib-imagex.exe
    }
}

function Get-TkSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath
    )
    $settings = Get-TkDefaultSetting
    $userFile = Join-Path $ConfigPath 'Settings.user.json'
    if (Test-Path -LiteralPath $userFile) {
        try {
            $user = Get-Content -LiteralPath $userFile -Raw | ConvertFrom-Json -AsHashtable
            foreach ($key in @($user.Keys)) {
                if ($settings.Contains($key)) { $settings[$key] = $user[$key] }
            }
        }
        catch {
            Write-Warning "Ignoring invalid settings file '$userFile': $($_.Exception.Message)"
        }
    }
    $settings
}

function Save-TkSetting {
    [CmdletBinding()]
    param()
    $file = Join-Path $script:TK.Paths.Config 'Settings.user.json'
    $script:TK.Settings | ConvertTo-Json | Set-Content -LiteralPath $file -Encoding utf8
    Write-TkLog "Settings saved to '$file'." -Level Success
}

# ---------------------------------------------------------------------------------------------
# Session (selected source and mounted images)
# ---------------------------------------------------------------------------------------------

function New-TkSession {
    [CmdletBinding()]
    param()
    @{
        SourceSelected = $false
        InstallWim     = ''
        BootWim        = ''
        Indexes        = @()
        ServiceBoot    = $false
        ServiceWinRE   = $false
        ImageInfo      = $null
        Images         = @()
        RegistryLoaded = $false
    }
}

function Save-TkSession {
    [CmdletBinding()]
    param()
    $s = $script:TK.Session
    if (-not $s.SourceSelected) {
        Remove-Item -LiteralPath $script:TK.Paths.SessionFile -Force -ErrorAction SilentlyContinue
        return
    }
    $s | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:TK.Paths.SessionFile -Encoding utf8
}

function Restore-TkSession {
    <# Re-reads a saved session (used after a restart while images are still mounted). #>
    [CmdletBinding()]
    param()
    $file = $script:TK.Paths.SessionFile
    if (-not (Test-Path -LiteralPath $file)) { return $false }
    try {
        $data = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
        $session = New-TkSession
        foreach ($key in @($data.Keys)) { $session[$key] = $data[$key] }
        $session.Images = @($session.Images)
        $session.Indexes = @($session.Indexes)
        $script:TK.Session = $session
        return $true
    }
    catch {
        Write-TkLog "Could not read saved session: $($_.Exception.Message)" -Level Warn
        return $false
    }
}

function Reset-TkSession {
    [CmdletBinding()]
    param()
    $script:TK.Session = New-TkSession
    Save-TkSession
}

function Get-TkImage {
    <#
    .SYNOPSIS
        Returns the mounted images of the current session.
    .PARAMETER Kind
        Install, Boot, WinRE or All.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Install', 'Boot', 'WinRE', 'All')]
        [string[]]$Kind = 'All'
    )
    $images = @($script:TK.Session.Images)
    if ($Kind -contains 'All') { return $images }
    @($images | Where-Object { $Kind -contains $_.Kind })
}

function Assert-TkSource {
    <# Throws when no source is selected or the image registry is loaded for manual editing. #>
    [CmdletBinding()]
    param(
        [switch]$AllowRegistryLoaded
    )
    if (-not $script:TK.Session.SourceSelected) {
        throw 'No source selected. Please select a source in the "Source" menu first.'
    }
    if (-not $AllowRegistryLoaded -and $script:TK.Session.RegistryLoaded) {
        throw 'The image registry is loaded for manual editing. Unload it via Tools -> Image registry first.'
    }
}
