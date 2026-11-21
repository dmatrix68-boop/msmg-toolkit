# ---------------------------------------------------------------------------------------------
# Integrate: drivers, updates, language packs, features on demand, .NET 3.5, inbox apps,
# custom files/fonts/recovery image and post-setup installers.
#
# Recommended order (Microsoft): .NET 3.5 -> language packs -> features on demand ->
# drivers -> updates -> apps. Integrate updates last, otherwise packages added afterwards
# may need the cumulative update again.
# ---------------------------------------------------------------------------------------------

function Get-TkPayloadFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Include,
        [switch]$Recurse
    )
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    @(Get-ChildItem -LiteralPath $Path -File -Recurse:$Recurse -ErrorAction SilentlyContinue |
            Where-Object { $ext = $_.Extension.ToLowerInvariant(); $Include -contains $ext })
}

# ---------------------------------------------------------------------------------------------
# Drivers
# ---------------------------------------------------------------------------------------------

function Add-TkDriver {
    <#
    .SYNOPSIS
        Adds the drivers from Drivers\Install, Drivers\Boot and Drivers\WinRE to the matching images.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Install', 'Boot', 'WinRE')]
        [string[]]$Target = @('Install', 'Boot', 'WinRE')
    )
    Assert-TkSource
    $dp = Get-TkDismParameter
    $any = $false
    foreach ($kind in $Target) {
        $folder = Join-Path $script:TK.Paths.Drivers $kind
        if (-not (Get-TkPayloadFile -Path $folder -Include '.inf' -Recurse)) { continue }
        foreach ($image in Get-TkImage -Kind $kind) {
            $any = $true
            $null = Invoke-TkStep -Name "Adding drivers from '$folder' to $kind image $($image.Index)" -ScriptBlock {
                Add-WindowsDriver -Path $image.Path -Driver $folder -Recurse -ForceUnsigned:([bool]$script:TK.Settings.ForceUnsignedDrivers) @dp | Out-Null
            }
        }
    }
    if (-not $any) { Write-TkLog 'No drivers (*.inf) found for the mounted images in <Drivers\Install|Boot|WinRE>.' -Level Warn }
}

function Export-TkHostDriver {
    <# Exports the third-party drivers of this PC to Drivers\Install\Host_<date>. #>
    [CmdletBinding()]
    param()
    Initialize-TkDism
    $dest = Join-Path $script:TK.Paths.Drivers ('Install\Host_{0:yyyyMMdd}' -f (Get-Date))
    $null = New-Item -Path $dest -ItemType Directory -Force
    Write-TkLog "Exporting host drivers to '$dest'..." -Level Step
    $dp = Get-TkDismParameter -NoScratch
    $drivers = @(Export-WindowsDriver -Online -Destination $dest @dp)
    Write-TkLog "$($drivers.Count) driver package(s) exported." -Level Success
}

# ---------------------------------------------------------------------------------------------
# Updates
# ---------------------------------------------------------------------------------------------

function Add-TkUpdate {
    <#
    .SYNOPSIS
        Integrates updates (*.msu / *.cab) from Updates\Install, Updates\Boot and Updates\WinRE,
        and expands Setup Dynamic Updates from Updates\SetupDU into DVD\sources.
    .NOTES
        Windows 11 24H2+ uses checkpoint cumulative updates: put the checkpoint and the latest
        cumulative update into the same folder - they are applied in KB order.
        Folder usage according to Microsoft's "Update Windows installation media with Dynamic Update":
          Install : SSU + LCU (+ .NET CU)
          Boot    : SSU + LCU
          WinRE   : SSU + Safe OS Dynamic Update
          SetupDU : Setup Dynamic Update (cab) -> expanded into the media "sources" folder
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Install', 'Boot', 'WinRE', 'SetupDU')]
        [string[]]$Target = @('Install', 'Boot', 'WinRE', 'SetupDU')
    )
    Assert-TkSource
    $dp = Get-TkDismParameter
    $any = $false

    foreach ($kind in @($Target | Where-Object { $_ -ne 'SetupDU' })) {
        $folder = Join-Path $script:TK.Paths.Updates $kind
        $files = @(Get-TkPayloadFile -Path $folder -Include '.msu', '.cab')
        if ($files.Count -eq 0) { continue }
        $ordered = @(Get-TkOrderedUpdateFile -File $files)
        foreach ($image in Get-TkImage -Kind $kind) {
            $any = $true
            foreach ($file in $ordered) {
                $null = Invoke-TkStep -Name "Adding $($file.Name) to $kind image $($image.Index)" -ScriptBlock {
                    Add-WindowsPackage -Path $image.Path -PackagePath $file.FullName @dp | Out-Null
                }
            }
        }
    }

    if ($Target -contains 'SetupDU') {
        $folder = Join-Path $script:TK.Paths.Updates 'SetupDU'
        $sources = Join-Path $script:TK.Paths.DVD 'sources'
        foreach ($cab in Get-TkPayloadFile -Path $folder -Include '.cab') {
            $any = $true
            $null = Invoke-TkStep -Name "Expanding Setup Dynamic Update $($cab.Name) into media sources" -ScriptBlock {
                $null = & expand.exe $cab.FullName -F:* $sources 2>&1
                if ($LASTEXITCODE -ne 0) { throw "expand.exe failed with exit code $LASTEXITCODE." }
            }
        }
    }
    if (-not $any) { Write-TkLog 'No updates found in <Updates\Install|Boot|WinRE|SetupDU>.' -Level Warn }
}

# ---------------------------------------------------------------------------------------------
# .NET Framework 3.5
# ---------------------------------------------------------------------------------------------

function Enable-TkNetFx3 {
    <# Enables .NET Framework 3.5 from the media's sources\sxs folder. Integrate it before updates. #>
    [CmdletBinding()]
    param()
    Assert-TkSource
    $dp = Get-TkDismParameter
    $sxs = Join-Path $script:TK.Paths.DVD 'sources\sxs'
    if (-not (Test-Path -LiteralPath $sxs)) { throw "Source folder '$sxs' not found (it is part of the Windows 11 media)." }
    foreach ($image in Get-TkImage -Kind Install) {
        $null = Invoke-TkStep -Name "Enabling .NET Framework 3.5 in image $($image.Index)" -ScriptBlock {
            Enable-WindowsOptionalFeature -Path $image.Path -FeatureName NetFx3 -All -LimitAccess -Source $sxs @dp | Out-Null
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Language packs
# ---------------------------------------------------------------------------------------------

function Get-TkLanguagePackFolder {
    [CmdletBinding()]
    param()
    $root = Join-Path $script:TK.Paths.Packs 'LanguagePacks'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    @(Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -match '^[a-z]{2,3}-[a-z0-9-]+$' })
}

function Add-TkLanguagePack {
    <#
    .SYNOPSIS
        Integrates a language from Packs\LanguagePacks\<language>.
    .DESCRIPTION
        Expected layout (files from the "Languages and Optional Features" ISO and the ADK WinPE add-on):
          Packs\LanguagePacks\de-de\*.cab        Client language pack + LanguageFeatures-* (install image)
          Packs\LanguagePacks\de-de\WinPE\*.cab  lp.cab + WinPE-*_de-de.cab (boot and recovery image)
    .PARAMETER SetDefault
        Makes the language the default UI/locale of the images and of Windows Setup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Language,
        [switch]$SetDefault
    )
    Assert-TkSource
    $dp = Get-TkDismParameter
    $folder = Join-Path (Join-Path $script:TK.Paths.Packs 'LanguagePacks') $Language
    if (-not (Test-Path -LiteralPath $folder)) { throw "Language folder '$folder' not found." }

    $installCabs = @(Get-TkPayloadFile -Path $folder -Include '.cab' |
            Sort-Object @{ Expression = { Get-TkLanguagePackOrder -FileName $_.Name } }, Name)
    if ($installCabs.Count -gt 0) {
        foreach ($image in Get-TkImage -Kind Install) {
            foreach ($cab in $installCabs) {
                $null = Invoke-TkStep -Name "Adding $($cab.Name) to image $($image.Index)" -ScriptBlock {
                    Add-WindowsPackage -Path $image.Path -PackagePath $cab.FullName @dp | Out-Null
                }
            }
            if ($SetDefault) {
                $null = Invoke-TkStep -Name "Setting '$Language' as default language of image $($image.Index)" -ScriptBlock {
                    Invoke-TkDismExe -ArgumentList @("/Image:$($image.Path)", "/Set-SKUIntlDefaults:$Language") -Quiet
                }
            }
        }
    }
    else {
        Write-TkLog "No language pack cabs found in '$folder'." -Level Warn
    }

    $winPeFolder = Join-Path $folder 'WinPE'
    $winPeCabs = @(Get-TkPayloadFile -Path $winPeFolder -Include '.cab')
    $peImages = @(Get-TkImage -Kind Boot, WinRE)
    if ($peImages.Count -gt 0 -and $winPeCabs.Count -eq 0) {
        Write-TkLog "No WinPE language cabs in '$winPeFolder' - boot/recovery images keep their language." -Level Warn
    }
    if ($winPeCabs.Count -gt 0) {
        foreach ($image in $peImages) {
            $installed = @(Get-WindowsPackage -Path $image.Path @dp | ForEach-Object { $_.PackageName })
            $names = Select-TkWinPELanguageCab -CabName @($winPeCabs.Name) -InstalledPackage $installed
            foreach ($name in $names) {
                $cab = Join-Path $winPeFolder $name
                $null = Invoke-TkStep -Name "Adding $name to $($image.Kind) image $($image.Index)" -ScriptBlock {
                    Add-WindowsPackage -Path $image.Path -PackagePath $cab @dp | Out-Null
                }
            }
            if ($SetDefault) {
                $null = Invoke-TkStep -Name "Setting '$Language' as default language of $($image.Kind) image $($image.Index)" -ScriptBlock {
                    Invoke-TkDismExe -ArgumentList @("/Image:$($image.Path)", "/Set-AllIntl:$Language") -Quiet
                }
            }
        }

        # Windows Setup (boot.wim index 2): copy the localized setup resources and regenerate lang.ini
        $setupImage = Get-TkImage -Kind Boot | Where-Object { Test-Path -LiteralPath (Join-Path $_.Path 'sources\setup.exe') } | Select-Object -First 1
        if ($setupImage) {
            $null = Invoke-TkStep -Name 'Updating Windows Setup languages (lang.ini)' -ScriptBlock {
                $resources = Join-Path $setupImage.Path "sources\$Language"
                if (Test-Path -LiteralPath $resources) {
                    Invoke-TkRobocopy -Source $resources -Destination (Join-Path $script:TK.Paths.DVD "sources\$Language")
                }
                Invoke-TkDismExe -ArgumentList @("/Image:$($setupImage.Path)", '/Gen-LangINI', "/Distribution:$($script:TK.Paths.DVD)") -Quiet
                if ($SetDefault) {
                    Invoke-TkDismExe -ArgumentList @("/Image:$($setupImage.Path)", "/Set-SetupUILang:$Language", "/Distribution:$($script:TK.Paths.DVD)") -Quiet
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Features on Demand (capabilities)
# ---------------------------------------------------------------------------------------------

function Get-TkCapability {
    <# Lists the capabilities of the first install image. #>
    [CmdletBinding()]
    param([ValidateSet('Installed', 'NotPresent', 'All')][string]$State = 'All')
    Assert-TkSource
    $image = @(Get-TkImage -Kind Install)[0]
    $dp = Get-TkDismParameter
    $caps = @(Get-WindowsCapability -Path $image.Path @dp)
    if ($State -ne 'All') { $caps = @($caps | Where-Object { "$($_.State)" -eq $State }) }
    $caps | Sort-Object Name
}

function Add-TkCapability {
    <#
    .SYNOPSIS
        Adds Features on Demand. Source: Packs\FOD (content of the "Languages and Optional Features" ISO).
    .EXAMPLE
        Add-TkCapability -Name 'Language.Basic~~~de-DE~0.0.1.0', 'NetFx3~~~~'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Name,
        [string]$Source = (Join-Path $script:TK.Paths.Packs 'FOD')
    )
    Assert-TkSource
    $dp = Get-TkDismParameter
    $sourceArgs = @{}
    if ($Source -and (Test-Path -LiteralPath $Source) -and (Get-ChildItem -LiteralPath $Source -Force | Select-Object -First 1)) {
        $sourceArgs = @{ Source = $Source; LimitAccess = $true }
    }
    else {
        Write-TkLog "FOD source '$Source' is empty - DISM can only add capabilities whose payload is already in the image." -Level Warn
    }
    foreach ($image in Get-TkImage -Kind Install) {
        foreach ($capability in $Name) {
            $null = Invoke-TkStep -Name "Adding capability $capability to image $($image.Index)" -ScriptBlock {
                Add-WindowsCapability -Path $image.Path -Name $capability @sourceArgs @dp | Out-Null
            }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Inbox / Store apps (provisioned appx packages)
# ---------------------------------------------------------------------------------------------

function Add-TkInboxApp {
    <#
    .SYNOPSIS
        Provisions apps from Packs\Apps (*.appx, *.appxbundle, *.msix, *.msixbundle).
    .DESCRIPTION
        Dependencies (VCLibs, UI.Xaml, WindowsAppRuntime ...) go to Packs\Apps\Dependencies.
        A license file named like the package with .xml extension is used if present,
        otherwise the app is provisioned with -SkipLicense.
    #>
    [CmdletBinding()]
    param([string[]]$Name)
    Assert-TkSource
    $dp = Get-TkDismParameter
    $folder = Join-Path $script:TK.Paths.Packs 'Apps'
    $apps = @(Get-TkPayloadFile -Path $folder -Include '.appx', '.appxbundle', '.msix', '.msixbundle')
    if ($Name) { $apps = @($apps | Where-Object { $n = $_.BaseName; $Name | Where-Object { $n -like "$_*" } }) }
    if ($apps.Count -eq 0) { Write-TkLog "No app packages found in '$folder'." -Level Warn; return }

    # x64 images also need x86 dependencies, arm64 images also arm dependencies
    $archPattern = if ($script:TK.Session.ImageInfo.Architecture -eq 'arm64') { 'arm64|arm' } else { 'x64|x86' }
    $depFolder = Join-Path $folder 'Dependencies'
    $deps = @(Get-TkPayloadFile -Path $depFolder -Include '.appx', '.msix' |
            Where-Object { $_.Name -notmatch '(?i)[_.-](x86|x64|arm|arm64)[_.-]' -or $_.Name -match "(?i)[_.-]($archPattern)[_.-]" })

    foreach ($image in Get-TkImage -Kind Install) {
        foreach ($app in $apps) {
            $null = Invoke-TkStep -Name "Provisioning $($app.Name) in image $($image.Index)" -ScriptBlock {
                $params = @{ Path = $image.Path; PackagePath = $app.FullName }
                if ($deps.Count -gt 0) { $params.DependencyPackagePath = @($deps.FullName) }
                $license = Join-Path $app.DirectoryName "$($app.BaseName).xml"
                if (Test-Path -LiteralPath $license) { $params.LicensePath = $license } else { $params.SkipLicense = $true }
                Add-AppxProvisionedPackage @params @dp | Out-Null
            }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Custom content
# ---------------------------------------------------------------------------------------------

function Add-TkCustomFile {
    <# Copies Custom\Files\* into the root of every install image (keeps the folder structure). #>
    [CmdletBinding()]
    param()
    Assert-TkSource
    $source = Join-Path $script:TK.Paths.Custom 'Files'
    if (-not (Get-ChildItem -LiteralPath $source -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        Write-TkLog "'$source' is empty. Place files there using the image folder structure (e.g. Windows\Web\Wallpaper\...)." -Level Warn
        return
    }
    foreach ($image in Get-TkImage -Kind Install) {
        $null = Invoke-TkStep -Name "Copying custom files to image $($image.Index)" -ScriptBlock {
            Invoke-TkRobocopy -Source $source -Destination $image.Path
        }
    }
}

function Get-TkFontName {
    <# Returns the registry value name of a font file, e.g. "Fira Code (TrueType)". #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)
    $kind = if ($File.Extension -ieq '.otf') { 'OpenType' } else { 'TrueType' }
    try {
        Add-Type -AssemblyName System.Drawing
        $collection = [System.Drawing.Text.PrivateFontCollection]::new()
        try {
            $collection.AddFontFile($File.FullName)
            $family = @($collection.Families)[0].Name
            if ($family) { return "$family ($kind)" }
        }
        finally { $collection.Dispose() }
    }
    catch { $null = $_ }
    "$($File.BaseName) ($kind)"
}

function Add-TkCustomFont {
    <# Installs the fonts from Custom\Fonts (*.ttf, *.otf, *.ttc) into every install image. #>
    [CmdletBinding()]
    param()
    Assert-TkSource
    $fonts = @(Get-TkPayloadFile -Path (Join-Path $script:TK.Paths.Custom 'Fonts') -Include '.ttf', '.otf', '.ttc')
    if ($fonts.Count -eq 0) { Write-TkLog 'No fonts found in <Custom\Fonts>.' -Level Warn; return }
    foreach ($image in Get-TkImage -Kind Install) {
        $null = Invoke-TkStep -Name "Installing $($fonts.Count) font(s) into image $($image.Index)" -ScriptBlock {
            $target = Join-Path $image.Path 'Windows\Fonts'
            Use-TkImageHive -ImagePath $image.Path -Hive SOFTWARE -ScriptBlock {
                foreach ($font in $fonts) {
                    Copy-Item -LiteralPath $font.FullName -Destination $target -Force
                    Set-TkRegistryValue -Hive SOFTWARE -Path 'Microsoft\Windows NT\CurrentVersion\Fonts' `
                        -Name (Get-TkFontName -File $font) -Type String -Value $font.Name
                }
            }
        }
    }
}

function Set-TkCustomRecoveryImage {
    <# Replaces winre.wim of every install image with Custom\RecoveryImage\winre.wim. #>
    [CmdletBinding()]
    param()
    Assert-TkSource
    if ($script:TK.Session.ServiceWinRE) { throw 'The recovery image is mounted for servicing - a custom winre.wim cannot be integrated in the same session.' }
    $custom = Join-Path $script:TK.Paths.Custom 'RecoveryImage\winre.wim'
    if (-not (Test-Path -LiteralPath $custom)) { throw "'$custom' not found." }
    foreach ($image in Get-TkImage -Kind Install) {
        $null = Invoke-TkStep -Name "Replacing winre.wim in image $($image.Index)" -ScriptBlock {
            Copy-TkRecoveryImage -Source $custom -ImagePath $image.Path
        }
    }
}

function Copy-TkRecoveryImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$ImagePath
    )
    $folder = Join-Path $ImagePath 'Windows\System32\Recovery'
    $null = New-Item -Path $folder -ItemType Directory -Force
    $target = Join-Path $folder 'winre.wim'
    if (Test-Path -LiteralPath $target) { (Get-Item -LiteralPath $target -Force).Attributes = 'Normal' }
    Copy-Item -LiteralPath $Source -Destination $target -Force
    (Get-Item -LiteralPath $target -Force).Attributes = 'Hidden, System, Archive'
}

function Add-TkPostSetupInstaller {
    <#
    .SYNOPSIS
        Copies installers from Packs\PostSetup into the image and runs them silently at the end of
        Windows Setup via %WINDIR%\Setup\Scripts\SetupComplete.cmd.
    .DESCRIPTION
        Supported: *.msi, *.msu, *.exe, *.ps1, *.cmd, *.bat
        Optional silent switches: a text file "<installer>.args" next to the installer,
        e.g. "PowerShell-7.5.0-win-x64.msi.args" containing "ADD_PATH=1 ENABLE_PSREMOTING=0".
        Files are executed in alphabetical order (prefix them with 01_, 02_ ... to control the order).
        An existing SetupComplete.cmd in the image is kept and called first.
    #>
    [CmdletBinding()]
    param()
    Assert-TkSource
    $source = Join-Path $script:TK.Paths.Packs 'PostSetup'
    $files = @(Get-TkPayloadFile -Path $source -Include '.msi', '.msu', '.exe', '.ps1', '.cmd', '.bat' | Sort-Object Name)
    if ($files.Count -eq 0) { Write-TkLog "No installers found in '$source'." -Level Warn; return }

    $items = foreach ($file in $files) {
        $argsFile = "$($file.FullName).args"
        $arguments = if (Test-Path -LiteralPath $argsFile) { (Get-Content -LiteralPath $argsFile -Raw).Trim() } else { '' }
        [pscustomobject]@{ Name = $file.Name; Arguments = $arguments }
    }
    $setupScript = New-TkSetupCompleteScript -Item @($items)

    foreach ($image in Get-TkImage -Kind Install) {
        $null = Invoke-TkStep -Name "Adding $($files.Count) post-setup installer(s) to image $($image.Index)" -ScriptBlock {
            $scripts = Join-Path $image.Path 'Windows\Setup\Scripts'
            $payload = Join-Path $scripts 'PostSetup'
            $null = New-Item -Path $payload -ItemType Directory -Force
            foreach ($file in $files) { Copy-Item -LiteralPath $file.FullName -Destination $payload -Force }

            # Keep an existing (foreign) SetupComplete.cmd and call it first
            $setupComplete = Join-Path $scripts 'SetupComplete.cmd'
            $original = Join-Path $scripts 'SetupComplete.original.cmd'
            if (Test-Path -LiteralPath $setupComplete) {
                $existing = Get-Content -LiteralPath $setupComplete -Raw
                if ($existing -notmatch 'Generated by MSMG Toolkit PS7') {
                    Move-Item -LiteralPath $setupComplete -Destination $original -Force
                }
            }
            $content = $setupScript
            if (Test-Path -LiteralPath $original) {
                $content = $setupScript -replace '(?m)^(set "PS_LOG=[^\r\n]*)', "`$1`r`ncall `"%~dp0SetupComplete.original.cmd`""
            }
            [System.IO.File]::WriteAllText($setupComplete, $content, [System.Text.Encoding]::ASCII)
        }
    }
}
