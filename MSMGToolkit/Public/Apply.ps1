# ---------------------------------------------------------------------------------------------
# Apply: component cleanup, save (commit) or discard the mounted images
# ---------------------------------------------------------------------------------------------

function Invoke-TkImageCleanup {
    <#
    .SYNOPSIS
        Runs DISM component store cleanup on the mounted images.
    .PARAMETER ResetBase
        Removes superseded component versions permanently (smaller image, updates cannot be uninstalled).
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Install', 'Boot', 'WinRE')]
        [string[]]$Target = @('Install', 'Boot', 'WinRE'),
        [Nullable[bool]]$ResetBase
    )
    Assert-TkSource
    if ($null -eq $ResetBase) { $ResetBase = [bool]$script:TK.Settings.CleanupResetBase }
    $dp = Get-TkDismParameter
    foreach ($image in Get-TkImage -Kind $Target) {
        $null = Invoke-TkStep -Name "Component cleanup of $($image.Kind) image $($image.Index)$(if ($ResetBase) { ' (ResetBase)' })" -ScriptBlock {
            Repair-WindowsImage -Path $image.Path -StartComponentCleanup -ResetBase:$ResetBase @dp | Out-Null
        }
    }
}

function Optimize-TkWim {
    <#
    .SYNOPSIS
        Rebuilds a WIM file and reclaims unused space (wimlib "optimize"; DISM fallback: export
        all indexes into a new file).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [ValidateSet('none', 'fast', 'max')][string]$Compression = $script:TK.Settings.ExportCompression
    )
    if (-not (Test-Path -LiteralPath $ImagePath)) { throw "Image not found: $ImagePath" }
    $before = (Get-Item -LiteralPath $ImagePath).Length
    $temp = "$ImagePath.rebuild"
    # wimlib only recompresses when a compression was requested explicitly - a plain rebuild
    # copies the compressed data and is much faster.
    $recompress = $PSBoundParameters.ContainsKey('Compression')
    Invoke-TkWimEngine -Operation "Rebuild of $(Split-Path -Leaf $ImagePath)" -WimlibAction {
        $wimArgs = @('optimize', $ImagePath, '--check')
        if ($recompress) { $wimArgs += ConvertTo-TkWimlibCompression -Compression $Compression }
        Invoke-TkWimlib -ArgumentList $wimArgs
    } -DismAction {
        $dp = Get-TkDismParameter
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        foreach ($image in @(Get-WindowsImage -ImagePath $ImagePath @dp)) {
            Write-TkLog "Exporting index $($image.ImageIndex): $($image.ImageName)..." -Level Step
            $bootable = (Split-Path -Leaf $ImagePath) -ieq 'boot.wim' -and $image.ImageIndex -eq 2
            Export-WindowsImage -SourceImagePath $ImagePath -SourceIndex $image.ImageIndex -DestinationImagePath $temp `
                -CompressionType $Compression -Setbootable:$bootable -CheckIntegrity @dp | Out-Null
        }
        Move-Item -LiteralPath $temp -Destination $ImagePath -Force
    }
    $after = (Get-Item -LiteralPath $ImagePath).Length
    Write-TkLog ("{0}: {1:N0} MB -> {2:N0} MB" -f (Split-Path -Leaf $ImagePath), ($before / 1MB), ($after / 1MB)) -Level Success
}

function Save-TkSource {
    <#
    .SYNOPSIS
        Commits and unmounts all images (WinRE -> install -> boot) and optionally rebuilds the WIM files.
    #>
    [CmdletBinding()]
    param([Nullable[bool]]$Rebuild)
    Assert-TkSource
    if ($null -eq $Rebuild) { $Rebuild = [bool]$script:TK.Settings.RebuildOnSave }
    $dp = Get-TkDismParameter
    $session = $script:TK.Session
    $failed = $false

    # 1. Recovery image first - it lives inside the install image(s)
    foreach ($image in Get-TkImage -Kind WinRE) {
        $ok = Invoke-TkStep -Name 'Saving recovery image (winre.wim)' -ScriptBlock {
            Dismount-WindowsImage -Path $image.Path -Save @dp | Out-Null
        }
        if (-not $ok) { $failed = $true; continue }
        if ($Rebuild) { $null = Invoke-TkStep -Name 'Rebuilding winre.wim' -ScriptBlock { Optimize-TkWim -ImagePath $image.ImageFile -Compression max } }
        foreach ($install in Get-TkImage -Kind Install) {
            $null = Invoke-TkStep -Name "Copying winre.wim into install image $($install.Index)" -ScriptBlock {
                Copy-TkRecoveryImage -Source $image.ImageFile -ImagePath $install.Path
            }
        }
        $session.Images = @($session.Images | Where-Object { $_.Kind -ne 'WinRE' })
        Save-TkSession
    }

    # 2. Install and boot images
    foreach ($kind in 'Install', 'Boot') {
        foreach ($image in Get-TkImage -Kind $kind) {
            $ok = Invoke-TkStep -Name "Saving $kind image $($image.Index)" -ScriptBlock {
                Dismount-WindowsImage -Path $image.Path -Save @dp | Out-Null
            }
            if ($ok) {
                $session.Images = @($session.Images | Where-Object { $_.Path -ne $image.Path })
                Save-TkSession
            }
            else { $failed = $true }
        }
    }

    if ($failed) {
        Write-TkLog 'Some images could not be saved. They are still mounted - check the log, then retry or discard (Tools -> Cleanup).' -Level Error
        return
    }

    # 3. Rebuild WIM files to drop unused data
    if ($Rebuild) {
        $null = Invoke-TkStep -Name 'Rebuilding install.wim' -ScriptBlock { Optimize-TkWim -ImagePath $session.InstallWim }
        if ($session.ServiceBoot -and $session.BootWim) {
            $null = Invoke-TkStep -Name 'Rebuilding boot.wim' -ScriptBlock { Optimize-TkWim -ImagePath $session.BootWim -Compression max }
        }
    }

    Remove-Item -LiteralPath (Join-Path $script:TK.Paths.WinReStage 'winre.wim') -Force -ErrorAction SilentlyContinue
    Reset-TkSession
    Write-TkLog 'All images saved. You can now create an ISO or USB drive (Target menu).' -Level Success
}

function Undo-TkSource {
    <# Discards all changes and unmounts all images of the session. #>
    [CmdletBinding()]
    param([switch]$Force)
    if (-not $script:TK.Session.SourceSelected -and -not $Force) { throw 'No source selected.' }
    if ($script:TK.Session.RegistryLoaded) { Dismount-TkImageRegistry }
    $dp = Get-TkDismParameter
    foreach ($image in @(Get-TkImage -Kind WinRE) + @(Get-TkImage -Kind Install) + @(Get-TkImage -Kind Boot)) {
        $null = Invoke-TkStep -Name "Discarding $($image.Kind) image $($image.Index)" -ScriptBlock {
            Dismount-WindowsImage -Path $image.Path -Discard @dp | Out-Null
        }
    }
    Remove-Item -LiteralPath (Join-Path $script:TK.Paths.WinReStage 'winre.wim') -Force -ErrorAction SilentlyContinue
    Reset-TkSession
    Write-TkLog 'All changes discarded.' -Level Success
}
