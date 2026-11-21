# ---------------------------------------------------------------------------------------------
# Tweak catalog of MSMG Toolkit PS7 (Windows 11 offline images)
#
# Each tweak:
#   Id           Unique identifier (used in build profiles)
#   Name         Menu text
#   Category     Group in the menu
#   Recommended  $true = part of "apply recommended tweaks"
#   MinBuild / MaxBuild   Optional build range (e.g. 26100 = 24H2)
#   Warning      Optional text shown before applying
#   Registry     Registry operations on the install image:
#                  @{ Hive = 'SOFTWARE|SYSTEM|DEFAULT|NTUSER'; Path = '...'; Name = '...'; Type = 'DWord|String|ExpandString|QWord|Binary|MultiString'; Value = ... }
#                  @{ Hive = ...; Path = ...; Name = ...; Delete = $true }   deletes a value
#                  @{ Hive = ...; Path = ...; DeleteKey = $true }            deletes a key
#                  Optional per operation: Architecture = @('x64', 'arm64')
#                  Value placeholder '{TargetRelease}' = feature release of the image (e.g. 25H2)
#   BootRegistry Registry operations on the SYSTEM hive of the mounted boot images (Windows Setup)
#   Handler      Name of an internal toolkit function for complex tweaks
#
# NTUSER = default user profile (all new users), DEFAULT = HKU\.DEFAULT (logon screen / system)
# SYSTEM paths may use CurrentControlSet - it is mapped to ControlSet001.
# ---------------------------------------------------------------------------------------------
@{
    Tweaks = @(
        # ---------------------------------------------------------------- Windows Setup / OOBE
        @{
            Id          = 'BypassHardwareCheck'
            Name        = 'Bypass Windows 11 hardware checks (TPM, Secure Boot, CPU, RAM, storage)'
            Category    = 'Setup & OOBE'
            Recommended = $false
            Warning     = 'Installing on unsupported hardware is not supported by Microsoft. Mount boot.wim to also patch Windows Setup.'
            Registry    = @(
                @{ Hive = 'SYSTEM'; Path = 'Setup\LabConfig'; Name = 'BypassTPMCheck'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SYSTEM'; Path = 'Setup\LabConfig'; Name = 'BypassSecureBootCheck'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SYSTEM'; Path = 'Setup\LabConfig'; Name = 'BypassCPUCheck'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SYSTEM'; Path = 'Setup\LabConfig'; Name = 'BypassRAMCheck'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SYSTEM'; Path = 'Setup\LabConfig'; Name = 'BypassStorageCheck'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SYSTEM'; Path = 'Setup\MoSetup'; Name = 'AllowUpgradesWithUnsupportedTPMOrCPU'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'DEFAULT'; Path = 'Control Panel\UnsupportedHardwareNotificationCache'; Name = 'SV1'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'DEFAULT'; Path = 'Control Panel\UnsupportedHardwareNotificationCache'; Name = 'SV2'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Control Panel\UnsupportedHardwareNotificationCache'; Name = 'SV1'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Control Panel\UnsupportedHardwareNotificationCache'; Name = 'SV2'; Type = 'DWord'; Value = 0 }
            )
            BootRegistry = @(
                @{ Hive = 'SYSTEM'; Path = 'Setup\LabConfig'; Name = 'BypassTPMCheck'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SYSTEM'; Path = 'Setup\LabConfig'; Name = 'BypassSecureBootCheck'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SYSTEM'; Path = 'Setup\LabConfig'; Name = 'BypassCPUCheck'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SYSTEM'; Path = 'Setup\LabConfig'; Name = 'BypassRAMCheck'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SYSTEM'; Path = 'Setup\LabConfig'; Name = 'BypassStorageCheck'; Type = 'DWord'; Value = 1 }
            )
        }
        @{
            Id          = 'EnableLocalAccountOobe'
            Name        = 'Allow OOBE without network / Microsoft account (BypassNRO)'
            Category    = 'Setup & OOBE'
            Recommended = $false
            Warning     = 'Newer Windows 11 builds may ignore BypassNRO. A local account in Autounattend.xml (Unattended menu) is the reliable way.'
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows\CurrentVersion\OOBE'; Name = 'BypassNRO'; Type = 'DWord'; Value = 1 }
            )
        }
        @{
            Id          = 'DisableBitLockerAutoEncryption'
            Name        = 'Disable automatic BitLocker device encryption'
            Category    = 'Setup & OOBE'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'SYSTEM'; Path = 'CurrentControlSet\Control\BitLocker'; Name = 'PreventDeviceEncryption'; Type = 'DWord'; Value = 1 }
            )
        }
        @{
            Id          = 'DisableOneDriveSetup'
            Name        = 'Do not install OneDrive automatically for new users'
            Category    = 'Setup & OOBE'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Run'; Name = 'OneDriveSetup'; Delete = $true }
            )
        }
        @{
            Id          = 'DisableEdgeFirstRun'
            Name        = 'Hide the Microsoft Edge first run experience'
            Category    = 'Setup & OOBE'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Edge'; Name = 'HideFirstRunExperience'; Type = 'DWord'; Value = 1 }
            )
        }

        # ---------------------------------------------------------------- Privacy & AI
        @{
            Id          = 'DisableConsumerFeatures'
            Name        = 'Disable automatic installation of promoted / 3rd party apps'
            Category    = 'Privacy & AI'
            Recommended = $true
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'OemPreInstalledAppsEnabled'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'PreInstalledAppsEnabled'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'DisableCopilot'
            Name        = 'Disable Windows Copilot (policy and taskbar button)'
            Category    = 'Privacy & AI'
            Recommended = $true
            MinBuild    = 22621
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'NTUSER'; Path = 'Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'DisableRecall'
            Name        = 'Disable Recall / AI data analysis'
            Category    = 'Privacy & AI'
            Recommended = $true
            MinBuild    = 26100
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsAI'; Name = 'AllowRecallEnablement'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Software\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Type = 'DWord'; Value = 1 }
            )
        }
        @{
            Id          = 'DisableWebSearch'
            Name        = 'Disable Bing web results in Start / Windows Search'
            Category    = 'Privacy & AI'
            Recommended = $true
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\Windows Search'; Name = 'ConnectedSearchUseWeb'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCloudSearch'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Software\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'ReduceTelemetry'
            Name        = 'Reduce diagnostic data, advertising ID and tailored experiences'
            Category    = 'Privacy & AI'
            Recommended = $true
            Registry    = @(
                # 0 = "Security" (Enterprise/Education); other editions use the minimum "Required" level
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\DataCollection'; Name = 'DoNotShowFeedbackNotifications'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\DataCollection'; Name = 'AllowDeviceNameInTelemetry'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\AdvertisingInfo'; Name = 'DisabledByGroupPolicy'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitInkCollection'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitTextCollection'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\InputPersonalization\TrainedDataStore'; Name = 'HarvestContacts'; Type = 'DWord'; Value = 0 }
            )
        }

        # ---------------------------------------------------------------- Windows Update
        @{
            Id          = 'DisableDriverUpdates'
            Name        = 'Disable automatic driver updates through Windows Update'
            Category    = 'Windows Update'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate'; Name = 'ExcludeWUDriversInQualityUpdate'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\Device Metadata'; Name = 'PreventDeviceMetadataFromNetwork'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\DriverSearching'; Name = 'DontPromptForWindowsUpdate'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\DriverSearching'; Name = 'DontSearchWindowsUpdate'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\DriverSearching'; Name = 'DriverUpdateWizardWuSearchEnabled'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows\CurrentVersion\DriverSearching'; Name = 'SearchOrderConfig'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'PinFeatureRelease'
            Name        = 'Stay on the current feature release (block automatic upgrades)'
            Category    = 'Windows Update'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate'; Name = 'ProductVersion'; Type = 'String'; Value = 'Windows 11' }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate'; Name = 'TargetReleaseVersion'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate'; Name = 'TargetReleaseVersionInfo'; Type = 'String'; Value = '{TargetRelease}' }
            )
        }
        @{
            Id          = 'DisableReservedStorage'
            Name        = 'Disable reserved storage for Windows Updates'
            Category    = 'Windows Update'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows\CurrentVersion\ReserveManager'; Name = 'ShippedWithReserves'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'EnableFullResetBase'
            Name        = 'Allow component cleanup with ResetBase in the installed system'
            Category    = 'Windows Update'
            Recommended = $false
            Warning     = 'Installed updates can no longer be uninstalled after a ResetBase cleanup.'
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows\CurrentVersion\SideBySide\Configuration'; Name = 'DisableResetbase'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'DisableWindowsUpdate'
            Name        = 'Disable Windows Update completely'
            Category    = 'Windows Update'
            Recommended = $false
            Warning     = 'The system will not receive any security updates.'
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoUpdate'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'AUOptions'; Type = 'DWord'; Value = 2 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'UseWUServer'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate'; Name = 'WUServer'; Type = 'String'; Value = ' ' }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate'; Name = 'WUStatusServer'; Type = 'String'; Value = ' ' }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate'; Name = 'UpdateServiceUrlAlternate'; Type = 'String'; Value = ' ' }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate'; Name = 'DoNotConnectToWindowsUpdateInternetLocations'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate'; Name = 'DisableWindowsUpdateAccess'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\DeliveryOptimization'; Name = 'DODownloadMode'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\WindowsStore'; Name = 'AutoDownload'; Type = 'DWord'; Value = 2 }
            )
        }

        # ---------------------------------------------------------------- Security
        @{
            Id          = 'DisableDefender'
            Name        = 'Disable Microsoft Defender Antivirus'
            Category    = 'Security'
            Recommended = $false
            Warning     = 'Leaves the system without antivirus protection. Tamper Protection can revert parts of this on current builds.'
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender'; Name = 'DisableAntiSpyware'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender'; Name = 'PUAProtection'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableBehaviorMonitoring'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableIOAVProtection'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableOnAccessProtection'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableRealtimeMonitoring'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableScanOnRealtimeEnable'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender\Spynet'; Name = 'SpyNetReporting'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender\Spynet'; Name = 'SubmitSamplesConsent'; Type = 'DWord'; Value = 2 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender Security Center\Notifications'; Name = 'DisableNotifications'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\MRT'; Name = 'DontOfferThroughWUAU'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\MRT'; Name = 'DontReportInfectionInformation'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows Defender\Features'; Name = 'TamperProtection'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SYSTEM'; Path = 'CurrentControlSet\Services\WinDefend'; Name = 'Start'; Type = 'DWord'; Value = 4 }
                @{ Hive = 'SYSTEM'; Path = 'CurrentControlSet\Services\WdBoot'; Name = 'Start'; Type = 'DWord'; Value = 4 }
                @{ Hive = 'SYSTEM'; Path = 'CurrentControlSet\Services\WdFilter'; Name = 'Start'; Type = 'DWord'; Value = 4 }
                @{ Hive = 'SYSTEM'; Path = 'CurrentControlSet\Services\WdNisDrv'; Name = 'Start'; Type = 'DWord'; Value = 4 }
                @{ Hive = 'SYSTEM'; Path = 'CurrentControlSet\Services\WdNisSvc'; Name = 'Start'; Type = 'DWord'; Value = 4 }
                @{ Hive = 'SYSTEM'; Path = 'CurrentControlSet\Services\Sense'; Name = 'Start'; Type = 'DWord'; Value = 4 }
            )
        }
        @{
            Id          = 'DisableFirewall'
            Name        = 'Disable Windows Firewall (all profiles)'
            Category    = 'Security'
            Recommended = $false
            Warning     = 'Only use this in networks protected by other means.'
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\WindowsFirewall\DomainProfile'; Name = 'EnableFirewall'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\WindowsFirewall\PrivateProfile'; Name = 'EnableFirewall'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\WindowsFirewall\PublicProfile'; Name = 'EnableFirewall'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\WindowsFirewall\StandardProfile'; Name = 'EnableFirewall'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'DisableSmartScreen'
            Name        = 'Disable SmartScreen and Smart App Control'
            Category    = 'Security'
            Recommended = $false
            Warning     = 'Downloaded programs are no longer checked for reputation.'
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\System'; Name = 'EnableSmartScreen'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows\CurrentVersion\Explorer'; Name = 'SmartScreenEnabled'; Type = 'String'; Value = 'Off' }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Edge'; Name = 'SmartScreenEnabled'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows Defender\SmartScreen'; Name = 'ConfigureAppInstallControlEnabled'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\AppHost'; Name = 'EnableWebContentEvaluation'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'SYSTEM'; Path = 'CurrentControlSet\Control\CI\Policy'; Name = 'VerifiedAndReputablePolicyState'; Type = 'DWord'; Value = 0 }
            )
        }

        # ---------------------------------------------------------------- Explorer & taskbar
        @{
            Id          = 'ShowFileExtensions'
            Name        = 'Show file name extensions'
            Category    = 'Explorer & Taskbar'
            Recommended = $true
            Registry    = @(
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'EnableClassicContextMenu'
            Name        = 'Use the classic (full) context menu'
            Category    = 'Explorer & Taskbar'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'NTUSER'; Path = 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; Name = ''; Type = 'String'; Value = '' }
            )
        }
        @{
            Id          = 'DisableDownloadsGrouping'
            Name        = 'Do not group the Downloads folder by date'
            Category    = 'Explorer & Taskbar'
            Recommended = $true
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}'; Name = 'GroupBy'; Type = 'String'; Value = 'System.None' }
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}'; Name = 'PrimaryProperty'; Type = 'String'; Value = 'System.ItemNameDisplay' }
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}'; Name = 'SortByList'; Type = 'String'; Value = 'prop:System.ItemNameDisplay' }
            )
        }
        @{
            Id          = 'TaskbarAlignLeft'
            Name        = 'Align the taskbar to the left'
            Category    = 'Explorer & Taskbar'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAl'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'HideSearchBox'
            Name        = 'Hide the taskbar search box'
            Category    = 'Explorer & Taskbar'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'SearchboxTaskbarMode'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'HideTaskViewButton'
            Name        = 'Hide the taskbar Task View button'
            Category    = 'Explorer & Taskbar'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'HideWidgets'
            Name        = 'Disable Widgets (taskbar button and news feed)'
            Category    = 'Explorer & Taskbar'
            Recommended = $true
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Type = 'DWord'; Value = 0 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'HideChatIcon'
            Name        = 'Hide the taskbar Chat (Teams) button'
            Category    = 'Explorer & Taskbar'
            Recommended = $true
            MaxBuild    = 22631
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\Windows Chat'; Name = 'ChatIcon'; Type = 'DWord'; Value = 3 }
                @{ Hive = 'NTUSER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMn'; Type = 'DWord'; Value = 0 }
            )
        }
        @{
            Id          = 'DisableTeamsAutoInstall'
            Name        = 'Do not install Microsoft Teams (personal) automatically'
            Category    = 'Explorer & Taskbar'
            Recommended = $true
            MaxBuild    = 22631
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows\CurrentVersion\Communications'; Name = 'ConfigureChatAutoInstall'; Type = 'DWord'; Value = 0 }
            )
        }

        # ---------------------------------------------------------------- Multimedia & compatibility
        @{
            Id          = 'EnablePhotoViewer'
            Name        = 'Register the classic Windows Photo Viewer for common image types'
            Category    = 'Multimedia & Compatibility'
            Recommended = $false
            Handler     = 'Set-TkPhotoViewerAssociation'
        }
        @{
            Id          = 'EnableFMP3ProCodec'
            Name        = 'Use the Fraunhofer IIS MPEG Layer-3 Professional codec'
            Category    = 'Multimedia & Compatibility'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows NT\CurrentVersion\Drivers32'; Name = 'msacm.l3acm'; Type = 'ExpandString'; Value = '%SystemRoot%\System32\l3codecp.acm' }
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\Windows NT\CurrentVersion\drivers.desc'; Name = '%SystemRoot%\System32\l3codecp.acm'; Type = 'String'; Value = 'Fraunhofer IIS MPEG Layer-3 Codec (Professional)' }
                @{ Hive = 'SOFTWARE'; Path = 'WOW6432Node\Microsoft\Windows NT\CurrentVersion\Drivers32'; Name = 'msacm.l3acm'; Type = 'ExpandString'; Value = '%SystemRoot%\SysWOW64\l3codecp.acm'; Architecture = @('x64', 'arm64') }
                @{ Hive = 'SOFTWARE'; Path = 'WOW6432Node\Microsoft\Windows NT\CurrentVersion\drivers.desc'; Name = '%SystemRoot%\SysWOW64\l3codecp.acm'; Type = 'String'; Value = 'Fraunhofer IIS MPEG Layer-3 Codec (Professional)'; Architecture = @('x64', 'arm64') }
            )
        }
        @{
            Id          = 'ForceLatestNetFramework'
            Name        = 'Run .NET 2.0-3.5 programs on the newest .NET Framework'
            Category    = 'Multimedia & Compatibility'
            Recommended = $false
            Registry    = @(
                @{ Hive = 'SOFTWARE'; Path = 'Microsoft\.NETFramework'; Name = 'OnlyUseLatestCLR'; Type = 'DWord'; Value = 1 }
                @{ Hive = 'SOFTWARE'; Path = 'WOW6432Node\Microsoft\.NETFramework'; Name = 'OnlyUseLatestCLR'; Type = 'DWord'; Value = 1; Architecture = @('x64', 'arm64') }
            )
        }
    )
}
