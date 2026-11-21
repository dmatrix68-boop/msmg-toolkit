# ---------------------------------------------------------------------------------------------
# MSMG Toolkit PS7 - example build profile
#
#   .\Start.ps1 -Build .\Config\BuildProfile.example.psd1
#
# Copy this file, adjust it and run it to build the same image again and again.
# Relative paths are resolved against the toolkit folder. Remove or empty what you don't need.
# ---------------------------------------------------------------------------------------------
@{
    Source    = @{
        # ISO file, drive/folder or ESD file to import into <DVD> first. Empty = use <DVD> as it is.
        Path         = ''
        # Editions to convert when Path is an ESD file (empty = all)
        EsdIndex     = @()
        # install.wim index(es) to service (see Source menu or Get-TkSourceImage)
        Index        = @(1)
        ServiceBoot  = $true
        ServiceWinRE = $true
    }

    Integrate = @{
        NetFx3              = $false
        LanguagePacks       = @()          # e.g. @('de-de') -> Packs\LanguagePacks\de-de
        DefaultLanguage     = ''           # e.g. 'de-de'
        Capabilities        = @()          # e.g. @('OpenSSH.Server~~~~0.0.1.0')
        Drivers             = $true        # Drivers\Install|Boot|WinRE
        Updates             = $true        # Updates\Install|Boot|WinRE|SetupDU
        InboxApps           = $false       # Packs\Apps
        CustomFiles         = $false       # Custom\Files
        CustomFonts         = $false       # Custom\Fonts
        CustomRecoveryImage = $false       # Custom\RecoveryImage\winre.wim
        PostSetup           = $false       # Packs\PostSetup -> SetupComplete.cmd
    }

    Remove    = @{
        AppsList         = 'Lists\RemoveAppsList.txt'
        PackagesList     = ''
        UnhidePackages   = $false
        CapabilitiesList = ''
    }

    Customize = @{
        EnableFeaturesList     = ''
        DisableFeaturesList    = ''
        DefaultAppAssociations = ''        # e.g. 'XMLs\W11_CustomAppsAssociation.xml'
        StartLayout            = @()       # e.g. @('XMLs\LayoutModification.json', 'XMLs\LayoutModification.xml')
        RegistryFiles          = $false    # Custom\Registry\*.reg
        # Tweak IDs from Config\Tweaks.psd1, 'Recommended' = all recommended tweaks
        Tweaks                 = @('Recommended')
    }

    Unattend  = @{
        Mode                  = 'None'     # None | Copy (Custom\Autounattend.xml) | Generate
        RegionalSource        = 'Image'    # Image | Host
        PromptAccountPassword = $false
        Options               = @{
            # Parameters of New-TkUnattendXml, e.g.:
            # AccountName              = 'Admin'
            # BypassNetworkRequirement = $true
            # PreventDeviceEncryption  = $true
        }
    }

    Apply     = @{
        Cleanup   = $true
        ResetBase = $true
        Rebuild   = $true
    }

    Target    = @{
        Iso     = $true
        IsoPath = ''                       # empty = ISO\Windows11_<release>_<arch>_<date>.iso
        Label   = ''
    }
}
