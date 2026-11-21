# ---------------------------------------------------------------------------------------------
# Pure helper functions (no side effects - covered by the Pester tests)
# ---------------------------------------------------------------------------------------------

function Read-TkList {
    <#
    .SYNOPSIS
        Reads a toolkit list file (one entry per line, ';' or '#' start comments).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "List file not found: $Path" }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $fullPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $entries = foreach ($line in [System.IO.File]::ReadAllLines($fullPath)) {
        $entry = ($line -replace '\s[;#].*$', '').Trim()
        if (-not $entry -or $entry.StartsWith(';') -or $entry.StartsWith('#')) { continue }
        if ($seen.Add($entry)) { $entry }
    }
    $entries
}

function Get-TkKbNumber {
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][string]$FileName)
    if ($FileName -match '(?i)kb(\d{6,8})') { return [int]$Matches[1] }
    [int]::MaxValue
}

function Get-TkOrderedUpdateFile {
    <#
    .SYNOPSIS
        Orders update packages for offline servicing:
        1. Servicing stack updates, 2. everything else by KB number ascending
        (checkpoint cumulative updates therefore come before the latest cumulative update),
        3. files without KB number by name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$File)
    $File | Sort-Object -Property @(
        @{ Expression = { if ($_.Name -match '(?i)(^|[-_.])ssu([-_.]|$)|servicingstack') { 0 } else { 1 } } },
        @{ Expression = { Get-TkKbNumber -FileName $_.Name } },
        @{ Expression = { $_.Name } }
    )
}

function Get-TkLanguagePackOrder {
    <# Sort key for language pack cabs: client language pack first, then features on demand. #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][string]$FileName)
    switch -Regex ($FileName) {
        '(?i)Client-Language-Pack|LanguagePack' { return 0 }
        '(?i)LanguageFeatures-Basic' { return 1 }
        '(?i)LanguageFeatures-Fonts' { return 2 }
        '(?i)LanguageFeatures-OCR' { return 3 }
        '(?i)LanguageFeatures-Handwriting' { return 4 }
        '(?i)LanguageFeatures-TextToSpeech' { return 5 }
        '(?i)LanguageFeatures-Speech' { return 6 }
        default { return 9 }
    }
}

function Select-TkWinPELanguageCab {
    <#
    .SYNOPSIS
        Picks the WinPE language cabs that match the optional components installed in a WinPE image.
    .PARAMETER CabName
        File names in the WinPE language folder, e.g. lp.cab, WinPE-Setup_de-de.cab, WinPE-WMI_de-de.cab
    .PARAMETER InstalledPackage
        Package names of the mounted WinPE image, e.g. WinPE-WMI-Package~31bf3856ad364e35~amd64~~10.0.26100.1
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$CabName,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$InstalledPackage
    )
    $installed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pkg in $InstalledPackage) {
        $base = ($pkg -split '~')[0] -replace '(?i)-Package$', ''
        $null = $installed.Add($base)
    }
    $result = [System.Collections.Generic.List[string]]::new()
    $lp = $CabName | Where-Object { $_ -ieq 'lp.cab' } | Select-Object -First 1
    if ($lp) { $result.Add($lp) }
    foreach ($cab in ($CabName | Sort-Object)) {
        if ($cab -ieq 'lp.cab') { continue }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($cab) -replace '(?i)_[a-z]{2,3}-[a-z0-9-]+$', ''
        # WinPE-Setup-Client/-Server language cabs belong to the WinPE-Setup package family
        $family = $base -replace '(?i)^(WinPE-Setup)-(Client|Server)$', '$1'
        if ($installed.Contains($base) -or $installed.Contains($family)) { $result.Add($cab) }
    }
    $result.ToArray()
}

function ConvertFrom-TkDismIntlOutput {
    <# Parses the output of "dism /Get-Intl" into a hashtable. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Line)
    $map = @{
        'Default system UI language' = 'UILanguage'
        'System locale'              = 'SystemLocale'
        'Default time zone'          = 'TimeZone'
        'Active keyboard\(s\)'       = 'InputLocale'
        'Keyboard layered driver'    = 'KeyboardDriver'
        'User locale for default user' = 'UserLocale'
        'Installed language\(s\)'    = 'InstalledLanguages'
    }
    $result = @{}
    foreach ($text in $Line) {
        foreach ($label in $map.Keys) {
            if ($text -match "^\s*$label\s*:\s*(.+?)\s*$") {
                $value = $Matches[1]
                if ($map[$label] -eq 'InputLocale') { $value = ($value -split ',')[0].Trim() }
                if (-not $result.ContainsKey($map[$label])) { $result[$map[$label]] = $value }
            }
        }
    }
    $result
}

function New-TkSetupCompleteScript {
    <#
    .SYNOPSIS
        Generates the content of SetupComplete.cmd that installs the post-setup packages.
    .PARAMETER Item
        Objects with Name (file name) and Arguments (optional silent switches).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Item)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('@echo off')
    $lines.Add('rem Generated by MSMG Toolkit PS7 - installs post-setup packages after Windows Setup.')
    $lines.Add('set "PS_DIR=%~dp0PostSetup"')
    $lines.Add('set "PS_LOG=%WINDIR%\Setup\Scripts\PostSetup.log"')
    $lines.Add('echo [%DATE% %TIME%] Post-setup started>>"%PS_LOG%"')
    foreach ($entry in $Item) {
        $name = $entry.Name
        $arguments = if ($entry.Arguments) { " $($entry.Arguments)" } else { '' }
        $extension = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
        $command = switch ($extension) {
            '.msi' { "msiexec.exe /i `"%PS_DIR%\$name`" /qn /norestart$arguments" }
            '.msu' { "wusa.exe `"%PS_DIR%\$name`" /quiet /norestart$arguments" }
            '.exe' { "`"%PS_DIR%\$name`"$arguments" }
            '.ps1' { "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%PS_DIR%\$name`"$arguments" }
            '.cmd' { "call `"%PS_DIR%\$name`"$arguments" }
            '.bat' { "call `"%PS_DIR%\$name`"$arguments" }
            default { $null }
        }
        if (-not $command) { continue }
        $lines.Add("echo [%DATE% %TIME%] Installing $name>>`"%PS_LOG%`"")
        $lines.Add("$command>>`"%PS_LOG%`" 2>&1")
        $lines.Add("echo [%DATE% %TIME%] $name finished with exit code %ERRORLEVEL%>>`"%PS_LOG%`"")
    }
    $lines.Add('echo [%DATE% %TIME%] Post-setup finished>>"%PS_LOG%"')
    $lines -join "`r`n"
}

function Get-TkTargetReleaseVersion {
    <# TargetReleaseVersionInfo value used to pin Windows Update to the current feature release. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][int]$Build)
    $release = Get-TkReleaseName -Build $Build
    if ($release -like 'Build *') { return '' }
    $release
}

function Get-TkIsoLabel {
    <# Derives a volume label (max. 32 chars, ISO/UDF safe). #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Label,
        [string]$Release,
        [string]$Architecture
    )
    $text = if ($Label) { $Label } elseif ($Release) { "W11_$($Release)_$Architecture" } else { 'W11_CUSTOM' }
    $text = ($text.ToUpperInvariant() -replace '[^A-Z0-9_]', '_')
    if ($text.Length -gt 32) { $text = $text.Substring(0, 32) }
    $text
}
