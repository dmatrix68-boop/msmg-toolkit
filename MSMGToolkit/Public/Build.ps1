# ---------------------------------------------------------------------------------------------
# Build profiles: run a complete, repeatable image build without the menus
# ---------------------------------------------------------------------------------------------

function Resolve-TkProfilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Path)
    if (-not $Path) { return '' }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    Join-Path $script:TK.Paths.Root $Path
}

function Invoke-TkBuild {
    <#
    .SYNOPSIS
        Runs a build profile (see Config\BuildProfile.example.psd1).
    .PARAMETER DiscardOnError
        Discards all mounted images when a fatal error occurs (default: keep them for inspection).
    .EXAMPLE
        .\Start.ps1 -Build .\Config\MyBuild.psd1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [switch]$DiscardOnError
    )
    $ProfilePath = Resolve-TkProfilePath $ProfilePath
    if (-not (Test-Path -LiteralPath $ProfilePath)) { throw "Build profile not found: $ProfilePath" }
    $buildProfile = Import-PowerShellDataFile -LiteralPath $ProfilePath
    $section = {
        param([string]$Name)
        if ($buildProfile.ContainsKey($Name) -and $buildProfile[$Name]) { $buildProfile[$Name] } else { @{} }
    }

    Initialize-TkFolder
    if (-not $script:TK.LogFile) { Start-TkLogging }
    Initialize-TkDism
    $previousConfirm = $script:TK.Settings.ConfirmActions
    $script:TK.Settings.ConfirmActions = $false
    $started = Get-Date
    Write-TkLog "Build profile: $ProfilePath" -Level Step

    try {
        # ------------------------------------------------------------------ Source
        $source = & $section 'Source'
        if ($source.Path) {
            Import-TkSource -Path (Resolve-TkProfilePath $source.Path) -Index $source.EsdIndex -Force
        }
        if (-not $source.Index) { throw 'The build profile must define Source.Index.' }
        Select-TkSource -Index $source.Index -ServiceBoot:([bool]$source.ServiceBoot) -ServiceWinRE:([bool]$source.ServiceWinRE)

        # ------------------------------------------------------------------ Integrate
        $integrate = & $section 'Integrate'
        if ($integrate.NetFx3) { Enable-TkNetFx3 }
        foreach ($language in @($integrate.LanguagePacks)) {
            if ($language) { Add-TkLanguagePack -Language $language -SetDefault:($language -eq $integrate.DefaultLanguage) }
        }
        $capabilities = @($integrate.Capabilities | Where-Object { $_ })
        if ($capabilities.Count -gt 0) { Add-TkCapability -Name $capabilities }
        if ($integrate.Drivers) { Add-TkDriver }
        if ($integrate.Updates) { Add-TkUpdate }
        if ($integrate.InboxApps) { Add-TkInboxApp }
        if ($integrate.CustomFiles) { Add-TkCustomFile }
        if ($integrate.CustomFonts) { Add-TkCustomFont }
        if ($integrate.CustomRecoveryImage) { Set-TkCustomRecoveryImage }
        if ($integrate.PostSetup) { Add-TkPostSetupInstaller }

        # ------------------------------------------------------------------ Remove
        $remove = & $section 'Remove'
        if ($remove.AppsList) { Remove-TkProvisionedApp -ListPath (Resolve-TkProfilePath $remove.AppsList) }
        if ($remove.PackagesList) { Remove-TkPackage -ListPath (Resolve-TkProfilePath $remove.PackagesList) -Unhide:([bool]$remove.UnhidePackages) }
        if ($remove.CapabilitiesList) { Remove-TkCapability -ListPath (Resolve-TkProfilePath $remove.CapabilitiesList) }

        # ------------------------------------------------------------------ Customize
        $customize = & $section 'Customize'
        if ($customize.EnableFeaturesList) { Enable-TkFeature -ListPath (Resolve-TkProfilePath $customize.EnableFeaturesList) }
        if ($customize.DisableFeaturesList) { Disable-TkFeature -ListPath (Resolve-TkProfilePath $customize.DisableFeaturesList) }
        if ($customize.DefaultAppAssociations) { Import-TkDefaultAppAssociation -Path (Resolve-TkProfilePath $customize.DefaultAppAssociations) }
        if ($customize.StartLayout) { Import-TkStartLayout -Path @($customize.StartLayout | ForEach-Object { Resolve-TkProfilePath $_ }) }
        if ($customize.RegistryFiles) { Import-TkRegistryFile }
        $tweakIds = @($customize.Tweaks | Where-Object { $_ })
        if ($tweakIds -contains 'Recommended') {
            Invoke-TkTweak -Recommended
            $tweakIds = @($tweakIds | Where-Object { $_ -ne 'Recommended' })
        }
        if ($tweakIds.Count -gt 0) { Invoke-TkTweak -Id $tweakIds }

        # ------------------------------------------------------------------ Unattended
        $unattend = & $section 'Unattend'
        switch ("$($unattend.Mode)") {
            'Copy' { Copy-TkPersonalUnattend -Path (Resolve-TkProfilePath $(if ($unattend.Path) { $unattend.Path } else { 'Custom\Autounattend.xml' })) }
            'Generate' {
                $options = @{}
                if ($unattend.Options) { foreach ($key in @($unattend.Options.Keys)) { $options[$key] = $unattend.Options[$key] } }
                if ($unattend.PromptAccountPassword -and $options.AccountName) {
                    $options.AccountPassword = Read-Host -Prompt "Password for '$($options.AccountName)'" -AsSecureString
                }
                $regionalSource = if ($unattend.RegionalSource) { $unattend.RegionalSource } else { 'Image' }
                Write-TkUnattendXml -RegionalSource $regionalSource -Option $options
            }
        }

        # ------------------------------------------------------------------ Apply
        $apply = & $section 'Apply'
        if ($apply.Cleanup) { Invoke-TkImageCleanup -ResetBase ([bool]$apply.ResetBase) }
        $rebuild = if ($apply.ContainsKey('Rebuild')) { [bool]$apply.Rebuild } else { [bool]$script:TK.Settings.RebuildOnSave }
        Save-TkSource -Rebuild $rebuild
        if ($script:TK.Session.SourceSelected) { throw 'Saving the images failed - see the log.' }

        # ------------------------------------------------------------------ Target
        $target = & $section 'Target'
        if ($target.Iso) {
            New-TkIso -Path (Resolve-TkProfilePath $target.IsoPath) -Label $target.Label
        }
        Write-TkLog ("Build finished in {0:hh\:mm\:ss}." -f ((Get-Date) - $started)) -Level Success
    }
    catch {
        Write-TkLog "Build failed: $($_.Exception.Message)" -Level Error
        if ($script:TK.Session.SourceSelected) {
            if ($DiscardOnError) { Undo-TkSource -Force }
            else { Write-TkLog 'Images stay mounted for inspection. Use Apply -> Discard or Tools -> Cleanup afterwards.' -Level Warn }
        }
        throw
    }
    finally {
        $script:TK.Settings.ConfirmActions = $previousConfirm
    }
}
