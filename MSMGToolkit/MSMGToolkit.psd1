@{
    RootModule           = 'MSMGToolkit.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '1da4c30c-80c7-4719-b6d7-3930685fecab'
    Author               = 'MSMG Toolkit PS7 contributors'
    CompanyName          = 'Community'
    Copyright            = 'Based on MSMG Toolkit (c) 2013-2024 MSMG. Altered PowerShell 7 rewrite - see LICENSE.txt.'
    Description          = 'Unofficial PowerShell 7 rewrite of MSMG Toolkit for servicing and customizing Windows 11 installation images (DISM based).'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        # Entry points
        'Start-Toolkit', 'Invoke-TkBuild',
        # Source
        'Import-TkSource', 'Import-TkSourceFromEsd', 'Convert-TkInstallEsd', 'Get-TkSourceImage', 'Select-TkSource', 'Get-TkImage',
        # Integrate
        'Add-TkDriver', 'Export-TkHostDriver', 'Add-TkUpdate', 'Enable-TkNetFx3', 'Get-TkLanguagePackFolder', 'Add-TkLanguagePack',
        'Get-TkCapability', 'Add-TkCapability', 'Add-TkInboxApp', 'Add-TkCustomFile', 'Add-TkCustomFont', 'Set-TkCustomRecoveryImage',
        'Add-TkPostSetupInstaller',
        # Remove
        'Get-TkProvisionedApp', 'Remove-TkProvisionedApp', 'Get-TkPackage', 'Remove-TkPackage', 'Show-TkHiddenPackage', 'Remove-TkCapability',
        # Customize
        'Get-TkFeature', 'Enable-TkFeature', 'Disable-TkFeature', 'Import-TkDefaultAppAssociation', 'Export-TkDefaultAppAssociation',
        'Remove-TkDefaultAppAssociation', 'Import-TkStartLayout', 'Import-TkRegistryFile', 'Get-TkTweak', 'Invoke-TkTweak',
        # Unattended
        'Copy-TkPersonalUnattend', 'Get-TkHostRegionalSetting', 'Get-TkImageRegionalSetting', 'New-TkUnattendXml', 'Write-TkUnattendXml',
        'Test-TkUnattendXml',
        # Apply
        'Invoke-TkImageCleanup', 'Optimize-TkWim', 'Save-TkSource', 'Undo-TkSource',
        # Target
        'Get-TkOscdimgPath', 'New-TkIso', 'Get-TkUsbDisk', 'Format-TkUsbDrive', 'Copy-TkMediaToUsb', 'New-TkUsbMedia',
        # Tools
        'Get-TkWimInfo', 'Remove-TkWimIndex', 'Rename-TkWimIndex', 'Export-TkWimIndex', 'Convert-TkWim', 'Split-TkWim', 'Join-TkSwm',
        'New-TkWimCapture', 'Expand-TkWim', 'Get-TkEditionTarget', 'Set-TkImageEdition', 'Mount-TkImageRegistry', 'Dismount-TkImageRegistry',
        'Clear-TkMountPoint', 'Get-TkDebugInfo'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Windows11', 'DISM', 'WIM', 'Deployment', 'ImageServicing', 'MSMG')
            ReleaseNotes = 'See CHANGELOG.md'
        }
    }
}
