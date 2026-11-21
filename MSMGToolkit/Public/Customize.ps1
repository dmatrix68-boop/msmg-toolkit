# ---------------------------------------------------------------------------------------------
# Customize: optional features, default app associations, Start layout, registry import, tweaks
# ---------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------
# Optional features
# ---------------------------------------------------------------------------------------------

function Get-TkFeature {
    [CmdletBinding()]
    param([ValidateSet('Enabled', 'Disabled', 'All')][string]$State = 'All')
    Assert-TkSource
    $image = @(Get-TkImage -Kind Install)[0]
    $dp = Get-TkDismParameter
    $features = @(Get-WindowsOptionalFeature -Path $image.Path @dp)
    switch ($State) {
        'Enabled' { $features = @($features | Where-Object { "$($_.State)" -eq 'Enabled' }) }
        'Disabled' { $features = @($features | Where-Object { "$($_.State)" -ne 'Enabled' }) }
    }
    $features | Sort-Object FeatureName
}

function Enable-TkFeature {
    <# Enables optional features (default list: Lists\EnableFeaturesList.txt). #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Name')][string[]]$Name,
        [Parameter(ParameterSetName = 'List')][string]$ListPath = (Join-Path $script:TK.Paths.Lists 'EnableFeaturesList.txt')
    )
    Assert-TkSource
    $dp = Get-TkDismParameter
    $wanted = if ($PSCmdlet.ParameterSetName -eq 'Name') { $Name } else { Read-TkList -Path $ListPath }
    if (@($wanted).Count -eq 0) { Write-TkLog 'The feature list is empty.' -Level Warn; return }
    $sxs = Join-Path $script:TK.Paths.DVD 'sources\sxs'
    foreach ($image in Get-TkImage -Kind Install) {
        foreach ($feature in $wanted) {
            $null = Invoke-TkStep -Name "Enabling feature $feature in image $($image.Index)" -ScriptBlock {
                $params = @{ Path = $image.Path; FeatureName = $feature; All = $true }
                if (Test-Path -LiteralPath $sxs) { $params.Source = $sxs; $params.LimitAccess = $true }
                Enable-WindowsOptionalFeature @params @dp | Out-Null
            }
        }
    }
}

function Disable-TkFeature {
    <# Disables optional features (default list: Lists\DisableFeaturesList.txt). #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Name')][string[]]$Name,
        [Parameter(ParameterSetName = 'List')][string]$ListPath = (Join-Path $script:TK.Paths.Lists 'DisableFeaturesList.txt'),
        # Also removes the payload from the image (the feature cannot be re-enabled without a source)
        [switch]$RemovePayload
    )
    Assert-TkSource
    $dp = Get-TkDismParameter
    $wanted = if ($PSCmdlet.ParameterSetName -eq 'Name') { $Name } else { Read-TkList -Path $ListPath }
    if (@($wanted).Count -eq 0) { Write-TkLog 'The feature list is empty.' -Level Warn; return }
    foreach ($image in Get-TkImage -Kind Install) {
        foreach ($feature in $wanted) {
            $null = Invoke-TkStep -Name "Disabling feature $feature in image $($image.Index)" -ScriptBlock {
                Disable-WindowsOptionalFeature -Path $image.Path -FeatureName $feature -Remove:$RemovePayload -NoRestart @dp | Out-Null
            }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Default app associations and Start layout
# ---------------------------------------------------------------------------------------------

function Import-TkDefaultAppAssociation {
    <# Imports a default app associations XML (default: XMLs\W11_CustomAppsAssociation.xml). #>
    [CmdletBinding()]
    param([string]$Path = (Join-Path $script:TK.Paths.XMLs 'W11_CustomAppsAssociation.xml'))
    Assert-TkSource
    if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }
    $null = [xml](Get-Content -LiteralPath $Path -Raw)
    foreach ($image in Get-TkImage -Kind Install) {
        $null = Invoke-TkStep -Name "Importing default app associations into image $($image.Index)" -ScriptBlock {
            Invoke-TkDismExe -ArgumentList @("/Image:$($image.Path)", "/Import-DefaultAppAssociations:$Path") -Quiet
        }
    }
}

function Export-TkDefaultAppAssociation {
    <# Exports the default app associations of this PC (configure them in Settings first). #>
    [CmdletBinding()]
    param([string]$Path = (Join-Path $script:TK.Paths.XMLs ('Host_AppAssociations_{0:yyyyMMdd}.xml' -f (Get-Date))))
    $null = Invoke-TkDismExe -ArgumentList @('/Online', "/Export-DefaultAppAssociations:$Path") -Quiet
    Write-TkLog "Default app associations exported to '$Path'." -Level Success
}

function Remove-TkDefaultAppAssociation {
    [CmdletBinding()]
    param()
    Assert-TkSource
    foreach ($image in Get-TkImage -Kind Install) {
        $null = Invoke-TkStep -Name "Removing default app associations from image $($image.Index)" -ScriptBlock {
            Invoke-TkDismExe -ArgumentList @("/Image:$($image.Path)", '/Remove-DefaultAppAssociations') -Quiet
        }
    }
}

function Import-TkStartLayout {
    <#
    .SYNOPSIS
        Copies a Start/taskbar layout to the default user profile.
    .DESCRIPTION
        LayoutModification.json -> Start menu pins (Windows 11)
        LayoutModification.xml  -> taskbar pins (Windows 11 22H2+)
        Default: XMLs\LayoutModification.json (empty pin list = clean Start menu).
    #>
    [CmdletBinding()]
    param([string[]]$Path = @(Join-Path $script:TK.Paths.XMLs 'LayoutModification.json'))
    Assert-TkSource
    foreach ($file in $Path) {
        if (-not (Test-Path -LiteralPath $file)) { throw "File not found: $file" }
        $ext = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
        if ($ext -eq '.json') { $null = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json }
        elseif ($ext -eq '.xml') { $null = [xml](Get-Content -LiteralPath $file -Raw) }
        else { throw "Unsupported layout file '$file' (use LayoutModification.json or LayoutModification.xml)." }
        foreach ($image in Get-TkImage -Kind Install) {
            $null = Invoke-TkStep -Name "Importing $([System.IO.Path]::GetFileName($file)) into image $($image.Index)" -ScriptBlock {
                $shell = Join-Path $image.Path 'Users\Default\AppData\Local\Microsoft\Windows\Shell'
                $null = New-Item -Path $shell -ItemType Directory -Force
                Copy-Item -LiteralPath $file -Destination (Join-Path $shell "LayoutModification$ext") -Force
            }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Registry import
# ---------------------------------------------------------------------------------------------

function Import-TkRegistryFile {
    <#
    .SYNOPSIS
        Imports .reg files into the install images. HKLM\SOFTWARE, HKLM\SYSTEM, HKCR, HKCU
        (= default user) and HKU\.DEFAULT are mapped to the offline hives automatically.
    .PARAMETER Path
        A .reg file or a folder (default: Custom\Registry).
    #>
    [CmdletBinding()]
    param([string]$Path = (Join-Path $script:TK.Paths.Custom 'Registry'))
    Assert-TkSource
    $files = if (Test-Path -LiteralPath $Path -PathType Container) {
        @(Get-ChildItem -LiteralPath $Path -Filter '*.reg' -File | Sort-Object Name)
    }
    elseif (Test-Path -LiteralPath $Path) { @(Get-Item -LiteralPath $Path) }
    else { @() }
    if ($files.Count -eq 0) { Write-TkLog "No .reg files found in '$Path'." -Level Warn; return }

    # Validate all files before touching an image
    foreach ($file in $files) { $null = Convert-TkRegFileContent -Content (Get-Content -LiteralPath $file.FullName -Raw) }

    foreach ($image in Get-TkImage -Kind Install) {
        $null = Invoke-TkStep -Name "Importing $($files.Count) registry file(s) into image $($image.Index)" -ScriptBlock {
            Use-TkImageHive -ImagePath $image.Path -ScriptBlock {
                foreach ($file in $files) {
                    Write-TkLog "  $($file.Name)" -Level Info
                    Import-TkRegFileToImage -Path $file.FullName
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Tweaks
# ---------------------------------------------------------------------------------------------

function Get-TkTweak {
    <#
    .SYNOPSIS
        Returns the tweak catalog (Config\Tweaks.psd1), filtered for the selected image build.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Id,
        [int]$Build,
        [string]$CatalogPath = (Join-Path $script:TK.Paths.Config 'Tweaks.psd1')
    )
    $catalog = Import-PowerShellDataFile -LiteralPath $CatalogPath
    $tweaks = @($catalog.Tweaks)
    if (-not $PSBoundParameters.ContainsKey('Build') -and $script:TK.Session.SourceSelected) {
        $Build = [int]$script:TK.Session.ImageInfo.Build
    }
    if ($Build) {
        $tweaks = @($tweaks | Where-Object {
                (-not $_.MinBuild -or $Build -ge $_.MinBuild) -and (-not $_.MaxBuild -or $Build -le $_.MaxBuild)
            })
    }
    if ($Id) {
        foreach ($wanted in $Id) {
            if (-not ($tweaks | Where-Object { $_.Id -eq $wanted })) { Write-TkLog "Tweak '$wanted' is unknown or not applicable to this build." -Level Warn }
        }
        $tweaks = @($tweaks | Where-Object { $Id -contains $_.Id })
    }
    $tweaks
}

function Invoke-TkRegistryOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Operation,
        [Parameter(Mandatory)][hashtable]$ImageInfo,
        [string]$Prefix = 'TK'
    )
    if ($Operation.Architecture -and @($Operation.Architecture) -notcontains $ImageInfo.Architecture) { return }
    if ($Operation.DeleteKey) {
        Remove-TkRegistryEntry -Hive $Operation.Hive -Path $Operation.Path -Prefix $Prefix
        return
    }
    if ($Operation.Delete) {
        Remove-TkRegistryEntry -Hive $Operation.Hive -Path $Operation.Path -Name $Operation.Name -Prefix $Prefix
        return
    }
    $value = $Operation.Value
    if ($value -is [string] -and $value -eq '{TargetRelease}') {
        $value = Get-TkTargetReleaseVersion -Build ([int]$ImageInfo.Build)
        if (-not $value) { throw "Unknown feature release for build $($ImageInfo.Build)." }
    }
    Set-TkRegistryValue -Hive $Operation.Hive -Path $Operation.Path -Name $Operation.Name -Type $Operation.Type -Value $value -Prefix $Prefix
}

function Invoke-TkTweak {
    <#
    .SYNOPSIS
        Applies tweaks from the catalog to the mounted images.
    .EXAMPLE
        Invoke-TkTweak -Id DisableConsumerFeatures, ShowFileExtensions
    .EXAMPLE
        Invoke-TkTweak -Recommended
    #>
    [CmdletBinding(DefaultParameterSetName = 'Id')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Id')][string[]]$Id,
        [Parameter(Mandatory, ParameterSetName = 'Recommended')][switch]$Recommended
    )
    Assert-TkSource
    $tweaks = if ($Recommended) { @(Get-TkTweak | Where-Object { $_.Recommended }) } else { @(Get-TkTweak -Id $Id) }
    if ($tweaks.Count -eq 0) { Write-TkLog 'No applicable tweaks selected.' -Level Warn; return }
    $info = $script:TK.Session.ImageInfo

    foreach ($image in Get-TkImage -Kind Install) {
        Write-TkLog "Applying $($tweaks.Count) tweak(s) to image $($image.Index)..." -Level Step
        Use-TkImageHive -ImagePath $image.Path -ScriptBlock {
            foreach ($tweak in $tweaks) {
                $null = Invoke-TkStep -Name "  $($tweak.Name)" -ScriptBlock {
                    foreach ($operation in @($tweak.Registry)) {
                        if ($operation) { Invoke-TkRegistryOperation -Operation $operation -ImageInfo $info }
                    }
                    if ($tweak.Handler) { & $tweak.Handler -ImagePath $image.Path -ImageInfo $info }
                }
            }
        }
    }

    $bootTweaks = @($tweaks | Where-Object { $_.BootRegistry })
    if ($bootTweaks.Count -gt 0) {
        $bootImages = @(Get-TkImage -Kind Boot)
        if ($bootImages.Count -eq 0) {
            Write-TkLog 'Some tweaks also patch Windows Setup, but boot.wim is not mounted - select the source with boot image servicing.' -Level Warn
        }
        foreach ($image in $bootImages) {
            Write-TkLog "Applying setup tweaks to boot image $($image.Index)..." -Level Step
            Use-TkImageHive -ImagePath $image.Path -Hive SYSTEM -ScriptBlock {
                foreach ($tweak in $bootTweaks) {
                    $null = Invoke-TkStep -Name "  $($tweak.Name)" -ScriptBlock {
                        foreach ($operation in @($tweak.BootRegistry)) { Invoke-TkRegistryOperation -Operation $operation -ImageInfo $info }
                    }
                }
            }
        }
    }
}

function Set-TkPhotoViewerAssociation {
    <# Tweak handler: registers Windows Photo Viewer for common image types (hives must be loaded). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][hashtable]$ImageInfo
    )
    $progIds = [ordered]@{
        '.bmp' = 'Bitmap'; '.dib' = 'Bitmap'; '.gif' = 'Gif'; '.jfif' = 'JFIF'; '.jpe' = 'Jpeg'; '.jpeg' = 'Jpeg'
        '.jpg' = 'Jpeg'; '.jxr' = 'Wdp'; '.png' = 'Png'; '.tif' = 'Tiff'; '.tiff' = 'Tiff'; '.wdp' = 'Wdp'
    }
    $command = '%SystemRoot%\System32\rundll32.exe "%ProgramFiles%\Windows Photo Viewer\PhotoViewer.dll", ImageView_Fullscreen %1'
    foreach ($type in @($progIds.Values | Select-Object -Unique)) {
        $base = "Classes\PhotoViewer.FileAssoc.$type"
        Set-TkRegistryValue -Hive SOFTWARE -Path $base -Name 'ImageOptionFlags' -Type DWord -Value 1
        Set-TkRegistryValue -Hive SOFTWARE -Path "$base\DefaultIcon" -Name '' -Type ExpandString -Value '%SystemRoot%\System32\imageres.dll,-72'
        Set-TkRegistryValue -Hive SOFTWARE -Path "$base\shell\open" -Name 'MuiVerb' -Type ExpandString -Value '@%ProgramFiles%\Windows Photo Viewer\photoviewer.dll,-3043'
        Set-TkRegistryValue -Hive SOFTWARE -Path "$base\shell\open\command" -Name '' -Type ExpandString -Value $command
        Set-TkRegistryValue -Hive SOFTWARE -Path "$base\shell\open\DropTarget" -Name 'Clsid' -Type String -Value '{FFE2A43C-56B9-4bf5-9A79-CC6D4285608A}'
    }
    foreach ($ext in $progIds.Keys) {
        Set-TkRegistryValue -Hive SOFTWARE -Path 'Microsoft\Windows Photo Viewer\Capabilities\FileAssociations' `
            -Name $ext -Type String -Value "PhotoViewer.FileAssoc.$($progIds[$ext])"
    }
}
