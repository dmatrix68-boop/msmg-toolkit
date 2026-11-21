# ---------------------------------------------------------------------------------------------
# Interactive console menus
# ---------------------------------------------------------------------------------------------

function Assert-TkPrerequisite {
    [CmdletBinding()]
    param([switch]$SkipHostCheck)
    if (-not $IsWindows) { throw 'MSMG Toolkit PS7 runs on Windows only.' }
    if ($PSVersionTable.PSVersion -lt [version]'7.4') { throw "PowerShell 7.4 or later is required (current: $($PSVersionTable.PSVersion))." }
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'The toolkit must be run as Administrator.'
    }
    if (-not $SkipHostCheck) {
        $build = [int](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
        if ($build -lt 22000) { throw "Windows 11 is required as host operating system (current build: $build)." }
    }
    if ($script:TK.Paths.Root -match '\s') {
        Write-TkLog "The toolkit path '$($script:TK.Paths.Root)' contains spaces - oscdimg.exe may fail. A short path like C:\Toolkit is recommended." -Level Warn
    }
}

function Show-TkEula {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    Show-TkHeader -Title 'Disclaimer'
    @(
        ' MSMG Toolkit PS7 services, customizes, adds or removes features and components'
        ' of Windows 11 installation images.'
        ''
        ' This is an UNOFFICIAL PowerShell 7 rewrite based on MSMG Toolkit 13.7'
        ' (c) 2013-2024 MSMG. It is not affiliated with or endorsed by MSMG or Microsoft.'
        ''
        ' Use it with licensed Microsoft Windows operating systems only.'
        ' The software is provided "as is", without warranty of any kind. Removing'
        ' components or applying tweaks can break Windows features - test your images'
        ' before deploying them.'
        ''
        ' Windows is a registered trademark of Microsoft Corporation.'
    ) | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-TkLine
    while ($true) {
        $answer = (Read-Host -Prompt "[A]ccept / [R]eject").Trim()
        if ($answer -ieq 'A') { return $true }
        if ($answer -ieq 'R') { return $false }
    }
}

function Resume-TkPreviousSession {
    <# Offers to resume or discard a session that was left with mounted images. #>
    [CmdletBinding()]
    param()
    $dp = Get-TkDismParameter -NoScratch
    $mountRoot = $script:TK.Paths.Mount
    $mounted = @(Get-WindowsImage -Mounted @dp | Where-Object { $_.Path -like "$mountRoot*" })
    $hasSession = Restore-TkSession

    if ($hasSession -and $script:TK.Session.SourceSelected) {
        $expected = @(Get-TkImage | ForEach-Object { $_.Path })
        $healthy = @($mounted | Where-Object { "$($_.MountStatus)" -eq 'Ok' } | ForEach-Object { $_.Path })
        $complete = $expected.Count -gt 0 -and -not ($expected | Where-Object { $healthy -notcontains $_ })
        if ($complete) {
            Write-TkLog "A previous session with $($expected.Count) mounted image(s) was found: $(Get-TkStatusLine)" -Level Warn
            if (Confirm-TkAction 'Resume this session? (No = discard all changes)' -Always -Default $true) {
                $script:TK.Session.RegistryLoaded = $false
                Save-TkSession
                return
            }
        }
        else {
            Write-TkLog 'A previous session was found, but its images are not (correctly) mounted any more.' -Level Warn
        }
        Clear-TkMountPoint
        return
    }
    if ($mounted.Count -gt 0) {
        Write-TkLog "$($mounted.Count) image(s) are still mounted below '$mountRoot' without a session." -Level Warn
        if (Confirm-TkAction 'Discard them now?' -Always -Default $true) { Clear-TkMountPoint }
    }
}

function Start-Toolkit {
    <#
    .SYNOPSIS
        Starts the interactive MSMG Toolkit PS7 console.
    #>
    [CmdletBinding()]
    param(
        [switch]$AcceptEula,
        [switch]$SkipHostCheck
    )
    Assert-TkPrerequisite -SkipHostCheck:$SkipHostCheck
    Initialize-TkFolder
    Start-TkLogging
    Initialize-TkDism
    try { $Host.UI.RawUI.WindowTitle = 'MSMG Toolkit PS7' } catch { $null = $_ }

    if (-not $AcceptEula -and -not (Show-TkEula)) { return }
    Show-TkHeader -Title 'Start Up'
    Write-TkLog 'Checking for a previous session...' -Level Step
    Resume-TkPreviousSession
    Show-TkMainMenu

    if ($script:TK.Session.SourceSelected) {
        Write-TkLog 'Images are still mounted. The next start offers to resume the session.' -Level Warn
    }
    Write-TkLog 'Bye.' -Level Info
}

# ---------------------------------------------------------------------------------------------
# Menus
# ---------------------------------------------------------------------------------------------

function Show-TkMainMenu {
    [CmdletBinding()]
    param()
    Invoke-TkMenu -Title 'Main Menu' -BackLabel 'Quit' -Items @(
        @{ Key = '1'; Label = 'Source'; Action = { Show-TkSourceMenu }; NoPause = $true }
        @{ Key = '2'; Label = 'Integrate'; Action = { Show-TkIntegrateMenu }; NoPause = $true }
        @{ Key = '3'; Label = 'Remove'; Action = { Show-TkRemoveMenu }; NoPause = $true }
        @{ Key = '4'; Label = 'Customize'; Action = { Show-TkCustomizeMenu }; NoPause = $true }
        @{ Key = '5'; Label = 'Unattended'; Action = { Show-TkUnattendMenu }; NoPause = $true }
        @{ Key = '6'; Label = 'Apply'; Action = { Show-TkApplyMenu }; NoPause = $true }
        @{ Key = '7'; Label = 'Target'; Action = { Show-TkTargetMenu }; NoPause = $true }
        @{ Key = '8'; Label = 'Tools'; Action = { Show-TkToolsMenu }; NoPause = $true }
    )
}

function Show-TkSourceMenu {
    [CmdletBinding()]
    param()
    Invoke-TkMenu -Title 'Source' -Items @(
        @{ Key = '1'; Label = 'Select source from <DVD> folder and mount images'; Action = { Select-TkSource -Interactive } }
        @{ Key = '2'; Label = 'Import media from an ISO file'; Action = {
                $path = Read-TkInput -Prompt 'Path of the Windows 11 ISO file'
                if ($path) { Import-TkSource -Path $path.Trim('"') }
            }
        }
        @{ Key = '3'; Label = 'Import media from a drive or folder (DVD, USB, extracted ISO)'; Action = {
                $path = Read-TkInput -Prompt 'Drive or folder (e.g. E:\)'
                if ($path) { Import-TkSource -Path $path.Trim('"') }
            }
        }
        @{ Key = '4'; Label = 'Import media from an ESD file (Media Creation Tool / UUP)'; Action = {
                $path = (Read-TkInput -Prompt 'Path of the ESD file').Trim('"')
                if (-not $path) { return }
                $images = @(Get-TkWimInfo -ImagePath $path)
                $editions = if ($images.Count -ge 4 -and $images[0].ImageName -match 'Windows Setup Media') { @($images | Select-Object -Skip 3) } else { $images }
                Write-Host '  Editions to convert:' -ForegroundColor White
                $selected = @(Read-TkSelection -Items $editions -Label { param($i) '{0} (Index {1})' -f $i.ImageName, $i.ImageIndex })
                if ($selected.Count -gt 0) { Import-TkSource -Path $path -Index @($selected | ForEach-Object { $_.ImageIndex }) }
            }
        }
        @{ Key = '5'; Label = 'Convert <DVD>\sources\install.esd to install.wim'; Action = { Convert-TkInstallEsd } }
    )
}

function Show-TkIntegrateMenu {
    [CmdletBinding()]
    param()
    Assert-TkSource
    Invoke-TkMenu -Title 'Integrate' -Items @(
        @{ Label = 'Recommended order: .NET 3.5 / languages / FODs -> drivers -> updates -> apps' }
        @{ Key = '1'; Label = 'Microsoft .NET Framework 3.5 (from media sources\sxs)'; Action = { Enable-TkNetFx3 } }
        @{ Key = '2'; Label = 'Language pack           <Packs\LanguagePacks\<lang>>'; Action = {
                $folders = @(Get-TkLanguagePackFolder)
                if ($folders.Count -eq 0) { throw "No language folders (e.g. de-de) in '$(Join-Path $script:TK.Paths.Packs 'LanguagePacks')'." }
                $selected = @(Read-TkSelection -Items $folders -Label { param($f) $f.Name } -Single)
                if ($selected.Count -eq 0) { return }
                $default = Confirm-TkAction "Make '$($selected[0].Name)' the default language?" -Always
                Add-TkLanguagePack -Language $selected[0].Name -SetDefault:$default
            }
        }
        @{ Key = '3'; Label = 'Features on Demand      <Packs\FOD>'; Action = {
                $caps = @(Get-TkCapability -State NotPresent)
                $selected = @(Read-TkSelection -Items $caps -Label { param($c) $c.Name })
                if ($selected.Count -gt 0) { Add-TkCapability -Name @($selected | ForEach-Object { $_.Name }) }
            }
        }
        @{ Key = '4'; Label = 'Drivers                 <Drivers\Install|Boot|WinRE>'; Action = { Add-TkDriver } }
        @{ Key = '5'; Label = 'Export drivers of this PC to <Drivers\Install>'; Action = { Export-TkHostDriver } }
        @{ Key = '6'; Label = 'Updates                 <Updates\Install|Boot|WinRE|SetupDU>'; Action = { Add-TkUpdate } }
        @{ Key = '7'; Label = 'Inbox / Store apps      <Packs\Apps>'; Action = { Add-TkInboxApp } }
        @{ Key = '8'; Label = 'Custom files            <Custom\Files>'; Action = { Add-TkCustomFile } }
        @{ Key = '9'; Label = 'Custom fonts            <Custom\Fonts>'; Action = { Add-TkCustomFont } }
        @{ Key = '10'; Label = 'Custom recovery image   <Custom\RecoveryImage\winre.wim>'; Action = { Set-TkCustomRecoveryImage } }
        @{ Key = '11'; Label = 'Post-setup installers   <Packs\PostSetup> (SetupComplete.cmd)'; Action = { Add-TkPostSetupInstaller } }
    )
}

function Copy-TkListTemplate {
    [CmdletBinding()]
    param()
    $templates = @(Get-ChildItem -LiteralPath (Join-Path $script:TK.Paths.Lists 'Templates') -Filter '*.txt' -File | Sort-Object Name)
    Write-Host '  Templates:' -ForegroundColor White
    $template = @(Read-TkSelection -Items $templates -Label { param($t) $t.Name } -Single)
    if ($template.Count -eq 0) { return }
    $targets = @('RemoveAppsList.txt', 'RemovePackagesList.txt', 'RemoveCapabilitiesList.txt', 'EnableFeaturesList.txt', 'DisableFeaturesList.txt')
    Write-Host ''
    Write-Host '  Copy to:' -ForegroundColor White
    $target = @(Read-TkSelection -Items $targets -Single)
    if ($target.Count -eq 0) { return }
    $dest = Join-Path $script:TK.Paths.Lists $target[0]
    if (-not (Confirm-TkAction "Overwrite '$dest' with '$($template[0].Name)'?" -Always)) { return }
    Copy-Item -LiteralPath $template[0].FullName -Destination $dest -Force
    Write-TkLog "List '$($target[0])' replaced. Review and edit it before using it." -Level Success
    if (Confirm-TkAction 'Open the list in Notepad now?' -Always -Default $true) { Start-Process -FilePath notepad.exe -ArgumentList "`"$dest`"" -Wait }
}

function Show-TkRemoveMenu {
    [CmdletBinding()]
    param()
    Assert-TkSource
    Invoke-TkMenu -Title 'Remove' -Items @(
        @{ Key = '1'; Label = 'Remove apps using list          <Lists\RemoveAppsList.txt>'; Action = { Remove-TkProvisionedApp } }
        @{ Key = '2'; Label = 'Remove apps (select)'; Action = {
                $apps = @(Get-TkProvisionedApp)
                $selected = @(Read-TkSelection -Items $apps -Label { param($a) $a.DisplayName })
                if ($selected.Count -gt 0) { Remove-TkProvisionedApp -Name @($selected | ForEach-Object { $_.DisplayName }) }
            }
        }
        @{ Key = '3'; Label = 'Remove packages using list      <Lists\RemovePackagesList.txt>'; Action = {
                $unhide = Confirm-TkAction 'Un-hide matching hidden packages first (needed for most components)?' -Always
                Remove-TkPackage -Unhide:$unhide
            }
        }
        @{ Key = '4'; Label = 'Remove packages (select)'; Action = {
                $packages = @(Get-TkPackage)
                $selected = @(Read-TkSelection -Items $packages -Label { param($p) $p.PackageName })
                if ($selected.Count -gt 0) { Remove-TkPackage -Name @($selected | ForEach-Object { $_.PackageName }) }
            }
        }
        @{ Key = '5'; Label = 'Remove capabilities using list  <Lists\RemoveCapabilitiesList.txt>'; Action = { Remove-TkCapability } }
        @{ Key = '6'; Label = 'Remove capabilities (select)'; Action = {
                $caps = @(Get-TkCapability -State Installed)
                $selected = @(Read-TkSelection -Items $caps -Label { param($c) $c.Name })
                if ($selected.Count -gt 0) { Remove-TkCapability -Name @($selected | ForEach-Object { $_.Name }) }
            }
        }
        @{ Key = '7'; Label = 'Load a list template from <Lists\Templates>'; Action = { Copy-TkListTemplate } }
    )
}

function Show-TkTweakMenu {
    [CmdletBinding()]
    param()
    Assert-TkSource
    $tweaks = @(Get-TkTweak | Sort-Object { $_.Category }, { $_.Name })
    $category = ''
    for ($i = 0; $i -lt $tweaks.Count; $i++) {
        if ($tweaks[$i].Category -ne $category) {
            $category = $tweaks[$i].Category
            Write-Host ''
            Write-Host "  $category" -ForegroundColor DarkYellow
        }
        $mark = if ($tweaks[$i].Recommended) { '*' } else { ' ' }
        Write-Host ('  [{0,2}]{1} {2}' -f ($i + 1), $mark, $tweaks[$i].Name)
    }
    Write-Host ''
    Write-Host '  * = recommended.  Enter numbers (e.g. 1,4,7-9), R = all recommended, empty = back' -ForegroundColor DarkGray
    $text = (Read-Host -Prompt 'Tweaks').Trim()
    if (-not $text) { return }
    $selected = @(
        if ($text -ieq 'R') { $tweaks | Where-Object { $_.Recommended } }
        else { @(ConvertFrom-TkSelectionString -Selection $text -Maximum $tweaks.Count) | ForEach-Object { $tweaks[$_ - 1] } }
    )
    if ($selected.Count -eq 0) { return }
    foreach ($tweak in @($selected | Where-Object { $_.Warning })) { Write-TkLog "$($tweak.Name): $($tweak.Warning)" -Level Warn }
    if (-not (Confirm-TkAction "Apply $($selected.Count) tweak(s)?" -Default $true)) { return }
    Invoke-TkTweak -Id @($selected | ForEach-Object { $_.Id })
}

function Show-TkCustomizeMenu {
    [CmdletBinding()]
    param()
    Assert-TkSource
    Invoke-TkMenu -Title 'Customize' -Items @(
        @{ Key = '1'; Label = 'Enable features using list   <Lists\EnableFeaturesList.txt>'; Action = { Enable-TkFeature } }
        @{ Key = '2'; Label = 'Disable features using list  <Lists\DisableFeaturesList.txt>'; Action = { Disable-TkFeature } }
        @{ Key = '3'; Label = 'Enable features (select)'; Action = {
                $features = @(Get-TkFeature -State Disabled)
                $selected = @(Read-TkSelection -Items $features -Label { param($f) "$($f.FeatureName) [$($f.State)]" })
                if ($selected.Count -gt 0) { Enable-TkFeature -Name @($selected | ForEach-Object { $_.FeatureName }) }
            }
        }
        @{ Key = '4'; Label = 'Disable features (select)'; Action = {
                $features = @(Get-TkFeature -State Enabled)
                $selected = @(Read-TkSelection -Items $features -Label { param($f) $f.FeatureName })
                if ($selected.Count -gt 0) { Disable-TkFeature -Name @($selected | ForEach-Object { $_.FeatureName }) }
            }
        }
        @{ Key = '5'; Label = 'Import default app associations (XML)'; Action = {
                $path = Read-TkInput -Prompt 'XML file' -Default (Join-Path $script:TK.Paths.XMLs 'W11_CustomAppsAssociation.xml')
                Import-TkDefaultAppAssociation -Path $path.Trim('"')
            }
        }
        @{ Key = '6'; Label = 'Export default app associations of this PC to <XMLs>'; Action = { Export-TkDefaultAppAssociation } }
        @{ Key = '7'; Label = 'Remove default app associations from the image'; Action = { Remove-TkDefaultAppAssociation } }
        @{ Key = '8'; Label = 'Import Start / taskbar layout (LayoutModification.json / .xml)'; Action = {
                $path = Read-TkInput -Prompt 'Layout file' -Default (Join-Path $script:TK.Paths.XMLs 'LayoutModification.json')
                Import-TkStartLayout -Path $path.Trim('"')
            }
        }
        @{ Key = '9'; Label = 'Import registry files        <Custom\Registry\*.reg>'; Action = { Import-TkRegistryFile } }
        @{ Key = '10'; Label = 'Apply tweaks'; Action = { Show-TkTweakMenu } }
    )
}

function Read-TkUnattendOption {
    <# Small wizard collecting the options for Write-TkUnattendXml. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $source = 'Host'
    if ($script:TK.Session.SourceSelected -and -not (Confirm-TkAction 'Use the regional settings of this PC? (No = use those of the mounted image)' -Always -Default $true)) {
        $source = 'Image'
    }
    $regional = if ($source -eq 'Image') { Get-TkImageRegionalSetting } else { Get-TkHostRegionalSetting }
    $option = @{}
    Write-Host ''
    Write-Host '  Press Enter to keep the suggested value.' -ForegroundColor DarkGray
    foreach ($key in 'UILanguage', 'SystemLocale', 'UserLocale', 'InputLocale', 'TimeZone') {
        $option[$key] = Read-TkInput -Prompt "  $key" -Default "$($regional[$key])"
    }
    $option.ComputerName = Read-TkInput -Prompt '  Computer name (empty = random)'
    $option.Organization = Read-TkInput -Prompt '  Organization (optional)'
    $option.Owner = Read-TkInput -Prompt '  Registered owner (optional)'
    $option.AccountName = Read-TkInput -Prompt '  Local administrator account (empty = create it during OOBE)'
    if ($option.AccountName) {
        $option.AccountPassword = Read-Host -Prompt '  Password (empty = no password)' -AsSecureString
        $option.AutoLogon = [switch](Confirm-TkAction '  Log on automatically once after setup?' -Always)
    }
    $option.BypassNetworkRequirement = [switch](Confirm-TkAction '  Allow OOBE without network / Microsoft account?' -Always -Default ([bool]$option.AccountName))
    $option.BypassHardwareCheck = [switch](Confirm-TkAction '  Bypass the Windows 11 hardware checks during setup?' -Always)
    $option.PreventDeviceEncryption = [switch](Confirm-TkAction '  Prevent automatic BitLocker device encryption?' -Always)
    @{ RegionalSource = $source; Option = $option }
}

function Show-TkUnattendMenu {
    [CmdletBinding()]
    param()
    Invoke-TkMenu -Title 'Unattended' -Items @(
        @{ Key = '1'; Label = 'Copy personal <Custom\Autounattend.xml> to <DVD>'; Action = { Copy-TkPersonalUnattend } }
        @{ Key = '2'; Label = 'Generate <DVD>\Autounattend.xml (wizard)'; Action = {
                $wizard = Read-TkUnattendOption
                Write-TkUnattendXml -RegionalSource $wizard.RegionalSource -Option $wizard.Option
            }
        }
        @{ Key = '3'; Label = 'Validate <DVD>\Autounattend.xml'; Action = {
                $issues = @(Test-TkUnattendXml -Path (Join-Path $script:TK.Paths.DVD 'Autounattend.xml'))
                if ($issues.Count -eq 0) { Write-TkLog 'No problems found.' -Level Success }
                foreach ($issue in $issues) { Write-TkLog $issue -Level Warn }
            }
        }
        @{ Key = '4'; Label = 'Delete <DVD>\Autounattend.xml'; Action = {
                $file = Join-Path $script:TK.Paths.DVD 'Autounattend.xml'
                if ((Test-Path -LiteralPath $file) -and (Confirm-TkAction "Delete '$file'?" -Always)) {
                    Remove-Item -LiteralPath $file -Force
                    Write-TkLog 'Deleted.' -Level Success
                }
            }
        }
    )
}

function Show-TkApplyMenu {
    [CmdletBinding()]
    param()
    Assert-TkSource
    Invoke-TkMenu -Title 'Apply' -Items @(
        @{ Key = '1'; Label = 'Cleanup images (DISM StartComponentCleanup)'; Action = {
                $reset = Confirm-TkAction 'Use /ResetBase (smaller image, integrated updates cannot be removed)?' -Always -Default ([bool]$script:TK.Settings.CleanupResetBase)
                Invoke-TkImageCleanup -ResetBase $reset
            }
        }
        @{ Key = '2'; Label = 'Save changes and unmount images'; Action = {
                $rebuild = Confirm-TkAction 'Rebuild the WIM files afterwards (reclaims space, takes a while)?' -Always -Default ([bool]$script:TK.Settings.RebuildOnSave)
                Save-TkSource -Rebuild $rebuild
                if (-not $script:TK.Session.SourceSelected) { return 'Exit' }
            }
        }
        @{ Key = '3'; Label = 'Discard changes and unmount images'; Action = {
                if (Confirm-TkAction 'Discard ALL changes?' -Always) {
                    Undo-TkSource
                    return 'Exit'
                }
            }
        }
    )
}

function Read-TkUsbDiskNumber {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    $disks = @(Get-TkUsbDisk)
    if ($disks.Count -eq 0) { throw 'No USB disk found.' }
    $selected = @(Read-TkSelection -Items $disks -Single -Label { param($d) '{0} - {1} ({2:N1} GB, {3})' -f $d.Number, $d.FriendlyName, ($d.Size / 1GB), $d.PartitionStyle })
    if ($selected.Count -eq 0) { return -1 }
    [int]$selected[0].Number
}

function Show-TkTargetMenu {
    [CmdletBinding()]
    param()
    Invoke-TkMenu -Title 'Target' -Items @(
        @{ Key = '1'; Label = 'Create ISO image from <DVD>'; Action = {
                $defaults = Get-TkMediaDefaultName
                $path = Read-TkInput -Prompt 'ISO file' -Default (Join-Path $script:TK.Paths.ISO $defaults.FileName)
                $label = Read-TkInput -Prompt 'Volume label' -Default $defaults.Label
                New-TkIso -Path $path.Trim('"') -Label $label
            }
        }
        @{ Key = '2'; Label = 'Create bootable USB drive from <DVD>'; Action = {
                $disk = Read-TkUsbDiskNumber
                if ($disk -ge 0) { New-TkUsbMedia -DiskNumber $disk }
            }
        }
        @{ Key = '3'; Label = 'Create bootable USB drive from an ISO file'; Action = {
                $iso = (Read-TkInput -Prompt 'ISO file').Trim('"')
                if (-not $iso) { return }
                $disk = Read-TkUsbDiskNumber
                if ($disk -ge 0) { New-TkUsbMedia -DiskNumber $disk -IsoPath $iso }
            }
        }
        @{ Key = '4'; Label = 'Update boot/install images on an existing USB drive'; Action = {
                $letter = (Read-TkInput -Prompt 'Drive letter of the USB drive (e.g. F)').TrimEnd(':', '\')
                if ($letter) { Copy-TkMediaToUsb -DriveLetter $letter -ImagesOnly }
            }
        }
        @{ Key = '5'; Label = 'Format a USB drive (FAT32)'; Action = {
                $disk = Read-TkUsbDiskNumber
                if ($disk -ge 0) { $null = Format-TkUsbDrive -DiskNumber $disk }
            }
        }
    )
}

function Show-TkWimManagerMenu {
    [CmdletBinding()]
    param()
    $default = Join-Path $script:TK.Paths.DVD 'sources\install.wim'
    $readImage = { (Read-TkInput -Prompt 'WIM/ESD file' -Default $default).Trim('"') }
    $readIndexes = {
        param([string]$wim)
        $images = @(Get-TkWimInfo -ImagePath $wim)
        Read-TkSelection -Items $images -Label { param($i) '{0} (Index {1}, {2:N2} GB)' -f $i.ImageName, $i.ImageIndex, ($i.ImageSize / 1GB) }
    }
    Invoke-TkMenu -Title 'WIM Manager' -Items @(
        @{ Key = '1'; Label = 'Show image information'; Action = {
                $wim = & $readImage
                Get-TkWimInfo -ImagePath $wim | ForEach-Object { Get-TkWimInfo -ImagePath $wim -Index $_.ImageIndex } |
                    Format-List ImageIndex, ImageName, ImageDescription, Version, Architecture, EditionId, Languages, @{ n = 'SizeGB'; e = { [Math]::Round($_.ImageSize / 1GB, 2) } } |
                    Out-Host
            }
        }
        @{ Key = '2'; Label = 'Delete index(es)'; Action = {
                $wim = & $readImage
                $sel = @(& $readIndexes $wim)
                if ($sel.Count -gt 0 -and (Confirm-TkAction "Delete $($sel.Count) index(es)?" -Always)) { Remove-TkWimIndex -ImagePath $wim -Index @($sel | ForEach-Object { $_.ImageIndex }) }
            }
        }
        @{ Key = '3'; Label = 'Rename index'; Action = {
                $wim = & $readImage
                $sel = @(& $readIndexes $wim)
                if ($sel.Count -ne 1) { throw 'Select exactly one index.' }
                $name = Read-TkInput -Prompt 'New name' -Default $sel[0].ImageName
                Rename-TkWimIndex -ImagePath $wim -Index $sel[0].ImageIndex -NewName $name
            }
        }
        @{ Key = '4'; Label = 'Export index(es) to another file'; Action = {
                $wim = & $readImage
                $sel = @(& $readIndexes $wim)
                if ($sel.Count -eq 0) { return }
                $dest = (Read-TkInput -Prompt 'Destination file (.wim or .esd)').Trim('"')
                Export-TkWimIndex -SourceImagePath $wim -Index @($sel | ForEach-Object { $_.ImageIndex }) -DestinationImagePath $dest
            }
        }
        @{ Key = '5'; Label = 'Convert WIM <-> ESD (all indexes)'; Action = {
                $wim = & $readImage
                $suggest = if ($wim -match '(?i)\.esd$') { [System.IO.Path]::ChangeExtension($wim, '.wim') } else { [System.IO.Path]::ChangeExtension($wim, '.esd') }
                $dest = (Read-TkInput -Prompt 'Destination file' -Default $suggest).Trim('"')
                Convert-TkWim -SourceImagePath $wim -DestinationImagePath $dest
            }
        }
        @{ Key = '6'; Label = 'Split WIM into SWM parts'; Action = { Split-TkWim -ImagePath (& $readImage) } }
        @{ Key = '7'; Label = 'Merge SWM parts into a WIM'; Action = {
                $swm = (Read-TkInput -Prompt 'First part (e.g. ...\install.swm)').Trim('"')
                if ($swm) { Join-TkSwm -SwmPath $swm }
            }
        }
        @{ Key = '8'; Label = 'Capture a folder/volume into a WIM'; Action = {
                $capture = (Read-TkInput -Prompt 'Folder or volume to capture (e.g. D:\)').Trim('"')
                $wim = (Read-TkInput -Prompt 'WIM file').Trim('"')
                $name = Read-TkInput -Prompt 'Image name'
                $append = (Test-Path -LiteralPath $wim) -and (Confirm-TkAction 'Append to the existing file?' -Always -Default $true)
                New-TkWimCapture -CapturePath $capture -ImagePath $wim -Name $name -Append:$append
            }
        }
        @{ Key = '9'; Label = 'Apply an index to a folder/volume'; Action = {
                $wim = & $readImage
                $sel = @(& $readIndexes $wim)
                if ($sel.Count -ne 1) { throw 'Select exactly one index.' }
                $target = (Read-TkInput -Prompt 'Target folder or volume (e.g. W:\)').Trim('"')
                Expand-TkWim -ImagePath $wim -Index $sel[0].ImageIndex -ApplyPath $target
            }
        }
        @{ Key = '10'; Label = 'Rebuild (optimize) a WIM file'; Action = { Optimize-TkWim -ImagePath (& $readImage) } }
    )
}

function Show-TkOptionsMenu {
    [CmdletBinding()]
    param()
    $s = $script:TK.Settings
    $cycle = {
        param([string]$key, [string[]]$values)
        $i = [array]::IndexOf($values, "$($s[$key])")
        $s[$key] = $values[($i + 1) % $values.Count]
    }
    $onOff = { param($v) if ($v) { 'On' } else { 'Off' } }
    Invoke-TkMenu -Title 'Options' -Items {
        @(
            @{ Key = '1'; Label = "Logging to <Logs>                    : $(& $onOff $s.Logging)"; Action = { $s.Logging = -not $s.Logging }; NoPause = $true }
            @{ Key = '2'; Label = "Confirm actions                      : $(& $onOff $s.ConfirmActions)"; Action = { $s.ConfirmActions = -not $s.ConfirmActions }; NoPause = $true }
            @{ Key = '3'; Label = "Cleanup with ResetBase               : $(& $onOff $s.CleanupResetBase)"; Action = { $s.CleanupResetBase = -not $s.CleanupResetBase }; NoPause = $true }
            @{ Key = '4'; Label = "Rebuild WIM files on save            : $(& $onOff $s.RebuildOnSave)"; Action = { $s.RebuildOnSave = -not $s.RebuildOnSave }; NoPause = $true }
            @{ Key = '5'; Label = "Export compression                   : $($s.ExportCompression)"; Action = { & $cycle 'ExportCompression' @('max', 'fast', 'none') }; NoPause = $true }
            @{ Key = '6'; Label = "DISM log level                       : $($s.DismLogLevel)"; Action = { & $cycle 'DismLogLevel' @('WarningsInfo', 'Warnings', 'Errors') }; NoPause = $true }
            @{ Key = '7'; Label = "Allow unsigned drivers               : $(& $onOff $s.ForceUnsignedDrivers)"; Action = { $s.ForceUnsignedDrivers = -not $s.ForceUnsignedDrivers }; NoPause = $true }
            @{ Key = '8'; Label = "ISO without 'Press any key' prompt   : $(& $onOff $s.IsoNoPrompt)"; Action = { $s.IsoNoPrompt = -not $s.IsoNoPrompt }; NoPause = $true }
            @{ Key = '9'; Label = "ISO volume label                     : $(if ($s.IsoLabel) { $s.IsoLabel } else { '(automatic)' })"; Action = { $s.IsoLabel = Read-TkInput -Prompt 'Label (empty = automatic)' }; NoPause = $true }
            @{ Key = '10'; Label = "oscdimg.exe path                     : $(if ($s.OscdimgPath) { $s.OscdimgPath } else { '(auto-detect)' })"; Action = { $s.OscdimgPath = (Read-TkInput -Prompt 'Path (empty = auto-detect)').Trim('"') }; NoPause = $true }
            @{ Key = '11'; Label = "USB partition style                  : $($s.UsbPartitionStyle)"; Action = { & $cycle 'UsbPartitionStyle' @('MBR', 'GPT') }; NoPause = $true }
            @{ Key = '12'; Label = "SWM part size (MB)                   : $($s.SwmChunkSizeMB)"; Action = { $s.SwmChunkSizeMB = [int](Read-TkInput -Prompt 'Size in MB' -Default "$($s.SwmChunkSizeMB)") }; NoPause = $true }
            @{ Key = 'S'; Label = 'Save options'; Action = { Save-TkSettings } }
        )
    }
}

function Show-TkToolsMenu {
    [CmdletBinding()]
    param()
    Invoke-TkMenu -Title 'Tools' -Items @(
        @{ Key = '1'; Label = 'WIM manager'; Action = { Show-TkWimManagerMenu }; NoPause = $true }
        @{ Key = '2'; Label = 'Change edition of the mounted image'; Action = {
                $targets = @(Get-TkEditionTarget)
                if ($targets.Count -eq 0) { throw 'No upgrade targets available for this edition.' }
                $selected = @(Read-TkSelection -Items $targets -Single)
                if ($selected.Count -gt 0) { Set-TkImageEdition -Edition $selected[0] }
            }
        }
        @{ Key = '3'; Label = 'Load image registry (HKLM\TK_*) for manual editing'; Action = { Mount-TkImageRegistry } }
        @{ Key = '4'; Label = 'Unload image registry'; Action = { Dismount-TkImageRegistry } }
        @{ Key = '5'; Label = 'Cleanup: discard stale mounts, unload hives, empty scratch'; Action = {
                if (Confirm-TkAction 'This discards all mounted images of the toolkit. Continue?' -Always) { Clear-TkMountPoint }
            }
        }
        @{ Key = '6'; Label = 'Run a build profile (automation)'; Action = {
                $path = (Read-TkInput -Prompt 'Build profile (.psd1)' -Default (Join-Path $script:TK.Paths.Config 'BuildProfile.example.psd1')).Trim('"')
                Invoke-TkBuild -ProfilePath $path
            }
        }
        @{ Key = '7'; Label = 'Debug information'; Action = { Get-TkDebugInfo | Format-Table -HideTableHeaders -Wrap | Out-Host } }
        @{ Key = '8'; Label = 'Options'; Action = { Show-TkOptionsMenu }; NoPause = $true }
    )
}
