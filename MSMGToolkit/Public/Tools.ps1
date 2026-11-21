# ---------------------------------------------------------------------------------------------
# Tools: WIM manager, image registry, edition change, cleanup, debug information
# ---------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------
# WIM manager
# ---------------------------------------------------------------------------------------------

function Get-TkWimInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [int]$Index
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter -NoScratch
    if ($Index) { Get-WindowsImage -ImagePath $ImagePath -Index $Index @dp }
    else { Get-WindowsImage -ImagePath $ImagePath @dp }
}

function Remove-TkWimIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int[]]$Index
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter
    # Delete from the highest index down so the remaining numbers stay valid
    foreach ($i in @($Index | Sort-Object -Descending)) {
        $null = Invoke-TkStep -Name "Deleting index $i from $(Split-Path -Leaf $ImagePath)" -ScriptBlock {
            Remove-WindowsImage -ImagePath $ImagePath -Index $i -CheckIntegrity @dp | Out-Null
        }
    }
}

function Rename-TkWimIndex {
    <# Renames an index (DISM has no rename - all indexes are exported into a new file). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$NewName
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter
    $temp = "$ImagePath.rename"
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    foreach ($image in @(Get-WindowsImage -ImagePath $ImagePath @dp)) {
        $name = if ($image.ImageIndex -eq $Index) { $NewName } else { $image.ImageName }
        Write-TkLog "Exporting index $($image.ImageIndex) as '$name'..." -Level Step
        Export-WindowsImage -SourceImagePath $ImagePath -SourceIndex $image.ImageIndex -DestinationImagePath $temp `
            -DestinationName $name -CompressionType $script:TK.Settings.ExportCompression @dp | Out-Null
    }
    Move-Item -LiteralPath $temp -Destination $ImagePath -Force
    Write-TkLog "Index $Index renamed to '$NewName'." -Level Success
}

function Export-TkWimIndex {
    <# Exports indexes into another WIM/ESD file (use an .esd destination for maximum compression). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceImagePath,
        [Parameter(Mandatory)][int[]]$Index,
        [Parameter(Mandatory)][string]$DestinationImagePath,
        [ValidateSet('none', 'fast', 'max', 'recovery')][string]$Compression
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter
    if (-not $Compression) {
        $Compression = if ($DestinationImagePath -match '(?i)\.esd$') { 'recovery' } else { $script:TK.Settings.ExportCompression }
    }
    foreach ($i in $Index) {
        $null = Invoke-TkStep -Name "Exporting index $i to $(Split-Path -Leaf $DestinationImagePath) ($Compression)" -ScriptBlock {
            Export-WindowsImage -SourceImagePath $SourceImagePath -SourceIndex $i -DestinationImagePath $DestinationImagePath `
                -CompressionType $Compression @dp | Out-Null
        }
    }
}

function Convert-TkWim {
    <# Converts all indexes WIM <-> ESD. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceImagePath,
        [Parameter(Mandatory)][string]$DestinationImagePath
    )
    $indexes = @(Get-TkWimInfo -ImagePath $SourceImagePath | ForEach-Object { $_.ImageIndex })
    Export-TkWimIndex -SourceImagePath $SourceImagePath -Index $indexes -DestinationImagePath $DestinationImagePath
}

function Split-TkWim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [string]$DestinationPath = ([System.IO.Path]::ChangeExtension($ImagePath, '.swm')),
        [int]$FileSizeMB = $script:TK.Settings.SwmChunkSizeMB
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter
    Split-WindowsImage -ImagePath $ImagePath -SplitImagePath $DestinationPath -FileSize $FileSizeMB -CheckIntegrity @dp | Out-Null
    Write-TkLog "Split into '$DestinationPath' (+ numbered parts)." -Level Success
}

function Join-TkSwm {
    <# Merges split images (install.swm, install2.swm, ...) into one WIM file. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SwmPath,
        [string]$DestinationImagePath = ([System.IO.Path]::ChangeExtension($SwmPath, '.wim'))
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter
    $folder = Split-Path -Parent $SwmPath
    $pattern = Join-Path $folder ('{0}*.swm' -f [System.IO.Path]::GetFileNameWithoutExtension($SwmPath))
    foreach ($image in @(Get-WindowsImage -ImagePath $SwmPath @dp)) {
        $null = Invoke-TkStep -Name "Merging index $($image.ImageIndex): $($image.ImageName)" -ScriptBlock {
            Export-WindowsImage -SourceImagePath $SwmPath -SplitImageFilePattern $pattern -SourceIndex $image.ImageIndex `
                -DestinationImagePath $DestinationImagePath -CompressionType $script:TK.Settings.ExportCompression @dp | Out-Null
        }
    }
}

function New-TkWimCapture {
    <# Captures a folder/volume into a new or existing WIM file (uses Config\WimScript.ini exclusions). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CapturePath,
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][string]$Name,
        [string]$Description = $Name,
        [switch]$Append
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter
    $params = @{ CapturePath = $CapturePath; ImagePath = $ImagePath; Name = $Name; Description = $Description; CheckIntegrity = $true }
    $config = Join-Path $script:TK.Paths.Config 'WimScript.ini'
    if (Test-Path -LiteralPath $config) { $params.ConfigFilePath = $config }
    if ($Append) {
        Add-WindowsImage @params @dp | Out-Null
    }
    else {
        New-WindowsImage @params -CompressionType $script:TK.Settings.ExportCompression @dp | Out-Null
    }
    Write-TkLog "Captured '$CapturePath' to '$ImagePath'." -Level Success
}

function Expand-TkWim {
    <# Applies an index to a folder or volume. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$ApplyPath
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter
    if (-not (Test-Path -LiteralPath $ApplyPath)) { $null = New-Item -Path $ApplyPath -ItemType Directory -Force }
    Expand-WindowsImage -ImagePath $ImagePath -Index $Index -ApplyPath $ApplyPath -CheckIntegrity @dp | Out-Null
    Write-TkLog "Index $Index applied to '$ApplyPath'." -Level Success
}

# ---------------------------------------------------------------------------------------------
# Edition
# ---------------------------------------------------------------------------------------------

function Get-TkEditionTarget {
    [CmdletBinding()]
    param()
    Assert-TkSource
    $image = @(Get-TkImage -Kind Install)[0]
    $dp = Get-TkDismParameter
    @(Get-WindowsEdition -Path $image.Path -Target @dp | ForEach-Object { $_.Edition })
}

function Set-TkImageEdition {
    <# Upgrades the mounted install image(s) to a higher edition (e.g. Core -> Professional). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Edition)
    Assert-TkSource
    $dp = Get-TkDismParameter
    foreach ($image in Get-TkImage -Kind Install) {
        $null = Invoke-TkStep -Name "Changing edition of image $($image.Index) to $Edition" -ScriptBlock {
            Set-WindowsEdition -Path $image.Path -Edition $Edition @dp | Out-Null
        }
    }
    Write-TkLog 'Edition changed. Rename the index afterwards (WIM manager) so the setup shows the right name.' -Level Info
}

# ---------------------------------------------------------------------------------------------
# Image registry (manual editing with regedit)
# ---------------------------------------------------------------------------------------------

function Mount-TkImageRegistry {
    <# Loads the hives of the first install image to HKLM\TK_* for manual editing. #>
    [CmdletBinding()]
    param()
    Assert-TkSource
    if ($script:TK.Session.RegistryLoaded) { Write-TkLog 'The image registry is already loaded.' -Level Warn; return }
    $image = @(Get-TkImage -Kind Install)[0]
    Mount-TkImageHive -ImagePath $image.Path
    $script:TK.Session.RegistryLoaded = $true
    Save-TkSession
    Write-TkLog "Hives of image $($image.Index) loaded to HKLM\TK_SOFTWARE, TK_SYSTEM, TK_DEFAULT, TK_NTUSER. Close regedit before unloading." -Level Success
}

function Dismount-TkImageRegistry {
    [CmdletBinding()]
    param()
    Dismount-TkImageHive
    $script:TK.Session.RegistryLoaded = $false
    Save-TkSession
    Write-TkLog 'Image registry unloaded.' -Level Success
}

# ---------------------------------------------------------------------------------------------
# Cleanup and diagnostics
# ---------------------------------------------------------------------------------------------

function Clear-TkMountPoint {
    <#
    .SYNOPSIS
        Cleans up after crashes: unloads leftover TK_* hives, discards images mounted below the
        toolkit's Mount folder, repairs corrupt mount points and empties the scratch folder.
    #>
    [CmdletBinding()]
    param()
    Initialize-TkDism
    $dp = Get-TkDismParameter -NoScratch

    foreach ($name in @('TK_SOFTWARE', 'TK_SYSTEM', 'TK_DEFAULT', 'TK_NTUSER')) {
        if (Test-Path -LiteralPath "Registry::HKEY_LOCAL_MACHINE\$name") {
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
            $null = & reg.exe unload "HKLM\$name" 2>&1
            if ($LASTEXITCODE -eq 0) { Write-TkLog "Unloaded leftover hive HKLM\$name" -Level Info }
        }
    }
    $script:TK.LoadedHives.Clear()

    $mountRoot = $script:TK.Paths.Mount
    foreach ($mounted in @(Get-WindowsImage -Mounted @dp)) {
        if ($mounted.Path -like "$mountRoot*") {
            $null = Invoke-TkStep -Name "Discarding mounted image $($mounted.Path)" -ScriptBlock {
                Dismount-WindowsImage -Path $mounted.Path -Discard @dp | Out-Null
            }
        }
    }
    $null = Invoke-TkStep -Name 'Repairing corrupt mount points' -ScriptBlock { Clear-WindowsCorruptMountPoint @dp | Out-Null }
    Get-ChildItem -LiteralPath $script:TK.Paths.Scratch -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Reset-TkSession
    Write-TkLog 'Cleanup finished.' -Level Success
}

function Get-TkDebugInfo {
    [CmdletBinding()]
    param()
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $dismVersion = (Get-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\dism.exe')).VersionInfo.ProductVersion
    [ordered]@{
        'Toolkit root'     = $script:TK.Paths.Root
        'Toolkit version'  = (Get-Module -Name MSMGToolkit).Version.ToString()
        'Host OS'          = "$($os.Caption) $($cv.DisplayVersion) ($($cv.CurrentBuild).$($cv.UBR)) $env:PROCESSOR_ARCHITECTURE"
        'PowerShell'       = $PSVersionTable.PSVersion.ToString()
        'DISM'             = $dismVersion
        'oscdimg.exe'      = $(if ($p = Get-TkOscdimgPath) { $p } else { '(not found - IMAPI2 fallback)' })
        'Log file'         = "$($script:TK.LogFile)"
        'Source selected'  = $script:TK.Session.SourceSelected
        'Mounted images'   = (@(Get-TkImage) | ForEach-Object { "$($_.Kind):$($_.Index)" }) -join ', '
        'Loaded hives'     = ($script:TK.LoadedHives -join ', ')
    }
}
