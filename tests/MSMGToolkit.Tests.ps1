#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Unit tests for the side-effect free parts of MSMG Toolkit PS7.
# Run: Invoke-Pester -Path .\tests

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $manifestPath = Join-Path $root 'MSMGToolkit\MSMGToolkit.psd1'
    Import-Module $manifestPath -Force
}

AfterAll {
    Remove-Module MSMGToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Repository' {
    It 'parses every PowerShell file without errors' {
        $files = Get-ChildItem -Path $root -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
        $files.Count | Should -BeGreaterThan 10
        foreach ($file in $files) {
            $tokens = $null; $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            $errors | Should -BeNullOrEmpty -Because $file.FullName
        }
    }

    It 'has a valid module manifest' {
        Test-ModuleManifest -Path $manifestPath | Should -Not -BeNullOrEmpty
    }

    It 'exports every function listed in the manifest' {
        $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
        $exported = @((Get-Module MSMGToolkit).ExportedFunctions.Keys)
        foreach ($name in $manifest.FunctionsToExport) { $exported | Should -Contain $name }
    }

    It 'ships no third-party binaries any more' {
        $binaries = Get-ChildItem -Path $root -Recurse -File -Include '*.exe', '*.dll', '*.sys', '*.7z', '*.tpk' |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
        $binaries | Should -BeNullOrEmpty
    }
}

Describe 'Selection parsing' {
    It 'parses <Text> with maximum <Max>' -ForEach @(
        @{ Text = '1,3-5'; Max = 6; Expected = @(1, 3, 4, 5) }
        @{ Text = '*'; Max = 3; Expected = @(1, 2, 3) }
        @{ Text = '5-3'; Max = 5; Expected = @(3, 4, 5) }
        @{ Text = '2 2, 2'; Max = 5; Expected = @(2) }
    ) {
        $actual = @(InModuleScope MSMGToolkit -Parameters @{ Text = $Text; Max = $Max } {
                ConvertFrom-TkSelectionString -Selection $Text -Maximum $Max
            })
        ($actual -join ',') | Should -Be ($Expected -join ',')
    }

    It 'returns nothing for an empty selection' {
        InModuleScope MSMGToolkit { @(ConvertFrom-TkSelectionString -Selection '' -Maximum 5).Count } | Should -Be 0
    }

    It 'rejects <Text>' -ForEach @(@{ Text = '7' }, @{ Text = 'abc' }, @{ Text = '0' }) {
        { InModuleScope MSMGToolkit -Parameters @{ Text = $Text } { ConvertFrom-TkSelectionString -Selection $Text -Maximum 5 } } | Should -Throw
    }
}

Describe 'Offline registry path mapping' {
    It 'maps <Path>' -ForEach @(
        @{ Path = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\X'; Expected = 'HKEY_LOCAL_MACHINE\TK_SOFTWARE\Policies\X' }
        @{ Path = 'HKEY_LOCAL_MACHINE\SOFTWARE'; Expected = 'HKEY_LOCAL_MACHINE\TK_SOFTWARE' }
        @{ Path = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\X'; Expected = 'HKEY_LOCAL_MACHINE\TK_SYSTEM\ControlSet001\Services\X' }
        @{ Path = 'HKEY_LOCAL_MACHINE\SYSTEM\ControlSet002\Control'; Expected = 'HKEY_LOCAL_MACHINE\TK_SYSTEM\ControlSet001\Control' }
        @{ Path = 'HKEY_LOCAL_MACHINE\SYSTEM\Setup\LabConfig'; Expected = 'HKEY_LOCAL_MACHINE\TK_SYSTEM\Setup\LabConfig' }
        @{ Path = 'HKEY_CURRENT_USER\Software\X'; Expected = 'HKEY_LOCAL_MACHINE\TK_NTUSER\Software\X' }
        @{ Path = 'HKEY_CLASSES_ROOT\.txt'; Expected = 'HKEY_LOCAL_MACHINE\TK_SOFTWARE\Classes\.txt' }
        @{ Path = 'HKEY_USERS\.DEFAULT\Control Panel'; Expected = 'HKEY_LOCAL_MACHINE\TK_DEFAULT\Control Panel' }
        @{ Path = 'hkey_current_user\Software\Y'; Expected = 'HKEY_LOCAL_MACHINE\TK_NTUSER\Software\Y' }
    ) {
        InModuleScope MSMGToolkit -Parameters @{ Path = $Path } { Convert-TkRegistryPath -Path $Path } | Should -Be $Expected
    }

    It 'rejects unsupported roots: <Path>' -ForEach @(
        @{ Path = 'HKEY_LOCAL_MACHINE\HARDWARE\X' }
        @{ Path = 'HKEY_LOCAL_MACHINE\SOFTWAREX\Y' }
        @{ Path = 'HKEY_USERS\S-1-5-21\Software' }
    ) {
        { InModuleScope MSMGToolkit -Parameters @{ Path = $Path } { Convert-TkRegistryPath -Path $Path } } | Should -Throw
    }

    It 'rewrites only key headers of a .reg file' {
        $content = @(
            'Windows Registry Editor Version 5.00'
            ''
            '; comment HKEY_CURRENT_USER'
            '[HKEY_CURRENT_USER\Software\Test]'
            '"Text"="HKEY_CURRENT_USER stays text"'
            ''
            '[-HKEY_LOCAL_MACHINE\SOFTWARE\Old]'
        ) -join "`r`n"
        $result = InModuleScope MSMGToolkit -Parameters @{ Content = $content } { Convert-TkRegFileContent -Content $Content }
        $lines = $result -split "`r`n"
        $lines | Should -Contain '[HKEY_LOCAL_MACHINE\TK_NTUSER\Software\Test]'
        $lines | Should -Contain '"Text"="HKEY_CURRENT_USER stays text"'
        $lines | Should -Contain '[-HKEY_LOCAL_MACHINE\TK_SOFTWARE\Old]'
        $lines | Should -Contain '; comment HKEY_CURRENT_USER'
        $lines[0] | Should -Be 'Windows Registry Editor Version 5.00'
    }

    It 'maps CurrentControlSet in hive sub keys' {
        InModuleScope MSMGToolkit { Resolve-TkHiveSubKey -Hive SYSTEM -Path 'CurrentControlSet\Control\BitLocker' } |
            Should -Be 'TK_SYSTEM\ControlSet001\Control\BitLocker'
        InModuleScope MSMGToolkit { Resolve-TkHiveSubKey -Hive SOFTWARE -Path 'CurrentControlSet\X' -Prefix 'TK_BOOT' } |
            Should -Be 'TK_BOOT_SOFTWARE\CurrentControlSet\X'
    }

    It 'converts registry data' {
        InModuleScope MSMGToolkit { ConvertTo-TkRegistryData -Type DWord -Value 4294967295 } | Should -Be -1
        InModuleScope MSMGToolkit { ConvertTo-TkRegistryData -Type DWord -Value 1 } | Should -BeOfType [int]
        $binary = InModuleScope MSMGToolkit { $v = ConvertTo-TkRegistryData -Type Binary -Value '030000'; , $v }
        , $binary | Should -BeOfType [byte[]]
        ($binary -join ',') | Should -Be '3,0,0'
        $multi = InModuleScope MSMGToolkit { $v = ConvertTo-TkRegistryData -Type MultiString -Value 'single'; , $v }
        , $multi | Should -BeOfType [string[]]
        $multi.Count | Should -Be 1
        { InModuleScope MSMGToolkit { ConvertTo-TkRegistryData -Type Binary -Value '123' } } | Should -Throw
    }
}

Describe 'List files' {
    It 'reads entries and ignores comments, blanks and duplicates' {
        $file = Join-Path $TestDrive 'list.txt'
        @(
            '; comment'
            '## section'
            ''
            'Microsoft.BingNews'
            '  Microsoft.BingWeather  '
            'Microsoft.BingNews'
            'Clipchamp.Clipchamp ; inline comment'
            '# Microsoft.WindowsStore'
        ) | Set-Content -LiteralPath $file
        $entries = @(InModuleScope MSMGToolkit -Parameters @{ File = $file } { Read-TkList -Path $File })
        ($entries -join '|') | Should -Be 'Microsoft.BingNews|Microsoft.BingWeather|Clipchamp.Clipchamp'
    }

    It 'reads every template' {
        foreach ($template in Get-ChildItem -Path (Join-Path $root 'Lists') -Recurse -Filter '*.txt') {
            { InModuleScope MSMGToolkit -Parameters @{ File = $template.FullName } { Read-TkList -Path $File } } | Should -Not -Throw
        }
    }
}

Describe 'Update ordering' {
    It 'puts servicing stack updates first and sorts by KB number' {
        $files = @(
            [pscustomobject]@{ Name = 'windows11.0-kb5068861-x64.msu' }
            [pscustomobject]@{ Name = 'readme-extra.cab' }
            [pscustomobject]@{ Name = 'windows11.0-kb5043080-x64.msu' }
            [pscustomobject]@{ Name = 'ssu-26100.4652-x64.cab' }
        )
        $ordered = InModuleScope MSMGToolkit -Parameters @{ Files = $files } { Get-TkOrderedUpdateFile -File $Files }
        (@($ordered.Name) -join '|') | Should -Be 'ssu-26100.4652-x64.cab|windows11.0-kb5043080-x64.msu|windows11.0-kb5068861-x64.msu|readme-extra.cab'
    }

    It 'orders language pack cabs' {
        $names = @(
            'Microsoft-Windows-LanguageFeatures-Speech-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-Client-Language-Pack_x64_de-de.cab'
            'Microsoft-Windows-LanguageFeatures-TextToSpeech-de-de-Package~31bf3856ad364e35~amd64~~.cab'
        )
        $sorted = @(InModuleScope MSMGToolkit -Parameters @{ Names = $names } {
                $Names | Sort-Object { Get-TkLanguagePackOrder -FileName $_ }
            })
        $sorted[0] | Should -Be 'Microsoft-Windows-Client-Language-Pack_x64_de-de.cab'
        $sorted[1] | Should -Match 'Basic'
        $sorted[2] | Should -Match 'TextToSpeech'
        $sorted[3] | Should -Match 'LanguageFeatures-Speech'
    }

    It 'selects WinPE language cabs for installed components only' {
        $cabs = @('lp.cab', 'WinPE-Setup_de-de.cab', 'WinPE-Setup-Client_de-de.cab', 'WinPE-WMI_de-de.cab', 'WinPE-HTA_de-de.cab')
        $installed = @(
            'WinPE-Setup-Package~31bf3856ad364e35~amd64~~10.0.26100.1'
            'WinPE-Setup-Client-Package~31bf3856ad364e35~amd64~~10.0.26100.1'
            'WinPE-WMI-Package~31bf3856ad364e35~amd64~~10.0.26100.1'
            'Microsoft-Windows-WinPE-Package~31bf3856ad364e35~amd64~~10.0.26100.1'
        )
        $selected = @(InModuleScope MSMGToolkit -Parameters @{ Cabs = $cabs; Installed = $installed } {
                Select-TkWinPELanguageCab -CabName $Cabs -InstalledPackage $Installed
            })
        $selected[0] | Should -Be 'lp.cab'
        $selected | Should -HaveCount 4
        $selected | Should -Contain 'WinPE-Setup-Client_de-de.cab'
        $selected | Should -Not -Contain 'WinPE-HTA_de-de.cab'
    }
}

Describe 'Version helpers' {
    It 'maps build <Build> to <Expected>' -ForEach @(
        @{ Build = 22621; Expected = '22H2' }
        @{ Build = 22631; Expected = '23H2' }
        @{ Build = 26100; Expected = '24H2' }
        @{ Build = 26200; Expected = '25H2' }
        @{ Build = 12345; Expected = 'Build 12345' }
    ) {
        InModuleScope MSMGToolkit -Parameters @{ Build = $Build } { Get-TkReleaseName -Build $Build } | Should -Be $Expected
    }

    It 'supports Windows 11 builds only' {
        InModuleScope MSMGToolkit { Test-TkSupportedBuild -Build 19045 } | Should -BeFalse
        InModuleScope MSMGToolkit { Test-TkSupportedBuild -Build 22000 } | Should -BeTrue
        InModuleScope MSMGToolkit { Test-TkSupportedBuild -Build 26200 } | Should -BeTrue
    }

    It 'maps DISM architectures' {
        InModuleScope MSMGToolkit { ConvertTo-TkArchitectureName 9 } | Should -Be 'x64'
        InModuleScope MSMGToolkit { ConvertTo-TkArchitectureName 12 } | Should -Be 'arm64'
        InModuleScope MSMGToolkit { Get-TkUnattendArchitecture -Architecture 'x64' } | Should -Be 'amd64'
    }

    It 'builds ISO labels' {
        InModuleScope MSMGToolkit { Get-TkIsoLabel -Label 'w11 25h2/x64' } | Should -Be 'W11_25H2_X64'
        InModuleScope MSMGToolkit { Get-TkIsoLabel -Release '24H2' -Architecture 'arm64' } | Should -Be 'W11_24H2_ARM64'
        InModuleScope MSMGToolkit { (Get-TkIsoLabel -Label ('x' * 40)).Length } | Should -Be 32
    }
}

Describe 'DISM output parsing' {
    It 'parses dism /Get-Intl' {
        $lines = @(
            'Reporting offline international settings.'
            'Default system UI language : de-DE'
            'System locale : de-DE'
            'Default time zone : W. Europe Standard Time'
            'Active keyboard(s) : 0407:00000407, 0409:00000409'
            'Keyboard layered driver : PC/AT Enhanced Keyboard (101/102-Key)'
            'Installed language(s): de-DE'
        )
        $intl = InModuleScope MSMGToolkit -Parameters @{ Lines = $lines } { ConvertFrom-TkDismIntlOutput -Line $Lines }
        $intl.UILanguage | Should -Be 'de-DE'
        $intl.SystemLocale | Should -Be 'de-DE'
        $intl.TimeZone | Should -Be 'W. Europe Standard Time'
        $intl.InputLocale | Should -Be '0407:00000407'
        $intl.InstalledLanguages | Should -Be 'de-DE'
    }
}

Describe 'SetupComplete.cmd generator' {
    It 'creates silent install commands' {
        $items = @(
            [pscustomobject]@{ Name = '01_PowerShell-7.5.4-win-x64.msi'; Arguments = 'ADD_PATH=1' }
            [pscustomobject]@{ Name = '02_Tool.exe'; Arguments = '/S' }
            [pscustomobject]@{ Name = '03_Config.ps1'; Arguments = '' }
            [pscustomobject]@{ Name = 'readme.txt'; Arguments = '' }
        )
        $script = InModuleScope MSMGToolkit -Parameters @{ Items = $items } { New-TkSetupCompleteScript -Item $Items }
        $script | Should -Match ([regex]::Escape('msiexec.exe /i "%PS_DIR%\01_PowerShell-7.5.4-win-x64.msi" /qn /norestart ADD_PATH=1'))
        $script | Should -Match ([regex]::Escape('"%PS_DIR%\02_Tool.exe" /S'))
        $script | Should -Match ([regex]::Escape('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_DIR%\03_Config.ps1"'))
        $script | Should -Not -Match 'readme\.txt'
        $script | Should -Match 'Generated by MSMG Toolkit PS7'
    }
}

Describe 'Unattend generator' {
    BeforeAll {
        $password = ConvertTo-SecureString -String 'Secret1' -AsPlainText -Force
        $xmlText = InModuleScope MSMGToolkit -Parameters @{ Password = $password } {
            New-TkUnattendXml -Architecture arm64 -UILanguage 'de-DE' -SystemLocale 'de-DE' -UserLocale 'de-DE' `
                -InputLocale '0407:00000407' -TimeZone 'W. Europe Standard Time' -Organization 'A&B <Corp>' `
                -AccountName 'Admin' -AccountPassword $Password -AutoLogon -BypassHardwareCheck -BypassNetworkRequirement -PreventDeviceEncryption
        }
        $doc = [xml]$xmlText
        $ns = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
        $ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    }

    It 'creates well-formed XML with the unattend namespace' {
        $doc.DocumentElement.LocalName | Should -Be 'unattend'
        $doc.DocumentElement.NamespaceURI | Should -Be 'urn:schemas-microsoft-com:unattend'
    }

    It 'uses the requested architecture for every component' {
        $archs = @($doc.SelectNodes('//u:component', $ns) | ForEach-Object { $_.GetAttribute('processorArchitecture') } | Select-Object -Unique)
        ($archs -join ',') | Should -Be 'arm64'
    }

    It 'escapes values' {
        $doc.SelectSingleNode('//u:settings[@pass="specialize"]//u:RegisteredOrganization', $ns).InnerText | Should -Be 'A&B <Corp>'
    }

    It 'encodes the account password like Windows SIM' {
        $expected = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes('Secret1Password'))
        $doc.SelectSingleNode('//u:LocalAccount/u:Password/u:Value', $ns).InnerText | Should -Be $expected
        $doc.SelectSingleNode('//u:LocalAccount/u:Password/u:PlainText', $ns).InnerText | Should -Be 'false'
        $doc.SelectSingleNode('//u:AutoLogon/u:Username', $ns).InnerText | Should -Be 'Admin'
    }

    It 'adds the hardware check bypass to the windowsPE pass' {
        $doc.SelectNodes('//u:settings[@pass="windowsPE"]//u:RunSynchronousCommand', $ns).Count | Should -Be 5
    }

    It 'does not configure disks' {
        $doc.SelectNodes('//u:DiskConfiguration', $ns).Count | Should -Be 0
    }

    It 'passes the validator' {
        $file = Join-Path $TestDrive 'Autounattend.xml'
        [System.IO.File]::WriteAllText($file, $xmlText)
        $issues = @(InModuleScope MSMGToolkit -Parameters @{ File = $file } { Test-TkUnattendXml -Path $File -Architecture 'arm64' })
        $issues.Count | Should -Be 0
        $issues = @(InModuleScope MSMGToolkit -Parameters @{ File = $file } { Test-TkUnattendXml -Path $File -Architecture 'amd64' })
        $issues.Count | Should -BeGreaterThan 0
    }

    It 'reports invalid XML' {
        $file = Join-Path $TestDrive 'broken.xml'
        Set-Content -LiteralPath $file -Value '<unattend><settings>'
        $issues = @(InModuleScope MSMGToolkit -Parameters @{ File = $file } { Test-TkUnattendXml -Path $File })
        $issues[0] | Should -Match 'Invalid XML'
    }
}

Describe 'Tweak catalog' {
    BeforeAll {
        $catalog = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'Config\Tweaks.psd1')
        $tweaks = @($catalog.Tweaks)
    }

    It 'has unique ids' {
        $tweaks.Count | Should -BeGreaterThan 20
        @($tweaks.Id | Select-Object -Unique).Count | Should -Be $tweaks.Count
    }

    It 'defines valid operations for <Id>' -ForEach @(
        (Import-PowerShellDataFile -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Config\Tweaks.psd1')).Tweaks
    ) {
        $Name | Should -Not -BeNullOrEmpty
        $Category | Should -Not -BeNullOrEmpty
        if ($Handler) {
            InModuleScope MSMGToolkit -Parameters @{ Handler = $Handler } { Get-Command -Name $Handler -ErrorAction SilentlyContinue } | Should -Not -BeNullOrEmpty
        }
        else {
            @($Registry).Count | Should -BeGreaterThan 0
        }
        foreach ($op in @($Registry) + @($BootRegistry) | Where-Object { $_ }) {
            $op.Hive | Should -BeIn @('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER')
            $op.Path | Should -Not -BeNullOrEmpty
            if (-not $op.DeleteKey) { $op.ContainsKey('Name') | Should -BeTrue }
            if (-not $op.Delete -and -not $op.DeleteKey) {
                $op.Type | Should -BeIn @('String', 'ExpandString', 'DWord', 'QWord', 'Binary', 'MultiString')
                if ($op.Value -ne '{TargetRelease}') {
                    { InModuleScope MSMGToolkit -Parameters @{ Op = $op } { ConvertTo-TkRegistryData -Type $Op.Type -Value $Op.Value } } | Should -Not -Throw
                }
            }
        }
        foreach ($op in @($BootRegistry) | Where-Object { $_ }) { $op.Hive | Should -Be 'SYSTEM' }
    }

    It 'filters tweaks by build' {
        $catalogPath = Join-Path $root 'Config\Tweaks.psd1'
        $ids24 = InModuleScope MSMGToolkit -Parameters @{ P = $catalogPath } { @(Get-TkTweak -Build 26100 -CatalogPath $P).Id }
        $ids23 = InModuleScope MSMGToolkit -Parameters @{ P = $catalogPath } { @(Get-TkTweak -Build 22631 -CatalogPath $P).Id }
        $ids24 | Should -Contain 'DisableRecall'
        $ids24 | Should -Not -Contain 'HideChatIcon'
        $ids23 | Should -Contain 'HideChatIcon'
        $ids23 | Should -Not -Contain 'DisableRecall'
    }

    It 'knows the target release of supported builds' {
        InModuleScope MSMGToolkit { Get-TkTargetReleaseVersion -Build 26200 } | Should -Be '25H2'
        InModuleScope MSMGToolkit { Get-TkTargetReleaseVersion -Build 1 } | Should -Be ''
    }
}

Describe 'Settings' {
    It 'merges user settings over defaults' {
        $config = Join-Path $TestDrive 'Config'
        $null = New-Item -Path $config -ItemType Directory -Force
        '{ "Logging": false, "UnknownKey": 1, "SwmChunkSizeMB": 2000 }' | Set-Content -LiteralPath (Join-Path $config 'Settings.user.json')
        $settings = InModuleScope MSMGToolkit -Parameters @{ C = $config } { Get-TkSettings -ConfigPath $C }
        $settings.Logging | Should -BeFalse
        $settings.SwmChunkSizeMB | Should -Be 2000
        $settings.Contains('UnknownKey') | Should -BeFalse
        $settings.ConfirmActions | Should -BeTrue
    }
}
