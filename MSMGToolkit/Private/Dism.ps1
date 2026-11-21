# ---------------------------------------------------------------------------------------------
# DISM helpers - the toolkit uses the inbox DISM PowerShell module of the Windows 11 host
# (no bundled DISM binaries any more) and dism.exe only for operations without a cmdlet.
# ---------------------------------------------------------------------------------------------

function Initialize-TkDism {
    [CmdletBinding()]
    param()
    # Scratch/log folders must exist before DISM cmdlets are called (also when the module is used from scripts)
    if (-not $script:TkFoldersReady) {
        Initialize-TkFolder
        $script:TkFoldersReady = $true
    }
    if (Get-Module -Name Dism) { return }
    try {
        Import-Module -Name Dism -ErrorAction Stop
    }
    catch {
        # Older host builds do not flag the module as Core compatible - it works nevertheless.
        Import-Module -Name Dism -SkipEditionCheck -ErrorAction Stop
    }
}

function Get-TkDismParameter {
    <# Common parameters (log + scratch directory) for splatting into DISM cmdlets. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([switch]$NoScratch)
    Initialize-TkDism
    $p = @{
        LogPath  = $script:TK.Paths.DismLog
        LogLevel = $script:TK.Settings.DismLogLevel
    }
    if (-not $NoScratch) { $p.ScratchDirectory = $script:TK.Paths.Scratch }
    $p
}

function Invoke-TkDismExe {
    <#
    .SYNOPSIS
        Runs the inbox dism.exe with English output and toolkit logging.
    .OUTPUTS
        The console output lines of dism.exe.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [switch]$Quiet
    )
    Initialize-TkDism
    $dism = Join-Path $env:SystemRoot 'System32\dism.exe'
    $allArgs = @('/English') + $ArgumentList + @("/LogPath:$($script:TK.Paths.DismLog)")
    Write-TkLog "dism.exe $($allArgs -join ' ')" -Level Debug
    $output = & $dism @allArgs 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    if (-not $Quiet) { $output | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray } }
    if ($code -ne 0 -and $code -ne 3010) {
        throw "dism.exe failed with exit code $code ($('0x{0:X8}' -f $code))."
    }
    $output
}

function ConvertTo-TkArchitectureName {
    <# Maps the numeric DISM architecture to a name. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Architecture)
    switch ("$Architecture") {
        '0' { 'x86' }
        '5' { 'arm' }
        '9' { 'x64' }
        '12' { 'arm64' }
        'x86' { 'x86' }
        'x64' { 'x64' }
        'amd64' { 'x64' }
        'arm64' { 'arm64' }
        default { "$Architecture" }
    }
}

function Get-TkReleaseName {
    <# Maps a Windows 11 build number to its marketing version. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][int]$Build)
    switch ($Build) {
        22000 { '21H2' }
        22621 { '22H2' }
        22631 { '23H2' }
        26100 { '24H2' }
        26200 { '25H2' }
        28000 { '26H1' }
        default { "Build $Build" }
    }
}

function Test-TkSupportedBuild {
    <# The toolkit services Windows 11 (build 22000 and later) only. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][int]$Build)
    $Build -ge 22000
}

function Get-TkImageInfo {
    <#
    .SYNOPSIS
        Returns normalized information about one index of a WIM/ESD file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int]$Index
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter -NoScratch
    $img = Get-WindowsImage -ImagePath $ImagePath -Index $Index @dp
    $version = [version]$img.Version
    $languages = @($img.Languages)
    $defaultLanguage = if ($languages.Count -gt 0) {
        $idx = [int]$img.DefaultLanguageIndex
        if ($idx -ge 0 -and $idx -lt $languages.Count) { $languages[$idx] } else { $languages[0] }
    }
    else { '' }
    @{
        Index            = $Index
        Name             = $img.ImageName
        Description      = $img.ImageDescription
        Version          = $version.ToString()
        Build            = $version.Build
        Release          = Get-TkReleaseName -Build $version.Build
        Architecture     = ConvertTo-TkArchitectureName $img.Architecture
        EditionId        = $img.EditionId
        InstallationType = $img.InstallationType
        Languages        = $languages
        DefaultLanguage  = "$defaultLanguage"
        SizeGB           = [Math]::Round($img.ImageSize / 1GB, 2)
    }
}

function Get-TkUnattendArchitecture {
    <# processorArchitecture value used in unattend files. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Architecture)
    switch ($Architecture) {
        'x64' { 'amd64' }
        'arm64' { 'arm64' }
        'x86' { 'x86' }
        default { $Architecture }
    }
}

function Set-TkFileWritable {
    <# Clears the read-only attribute (files copied from an ISO are read-only). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item -is [System.IO.DirectoryInfo]) {
        Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.IsReadOnly } |
            ForEach-Object { $_.IsReadOnly = $false }
    }
    elseif ($item.IsReadOnly) {
        $item.IsReadOnly = $false
    }
}

function Invoke-TkRobocopy {
    <# Copies a folder tree with robocopy; exit codes below 8 are success. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string[]]$ExcludeFile = @(),
        [string[]]$ExtraArgument = @()
    )
    # A trailing backslash would escape the closing quote of a quoted argument ("C:\My Dir\").
    $normalize = {
        param([string]$p)
        $t = $p.TrimEnd('\')
        if ($t -match '^[A-Za-z]:$') { "$t\." } else { $t }
    }
    $robocopyArgs = @((& $normalize $Source), (& $normalize $Destination), '/E', '/R:1', '/W:1', '/NP', '/NFL', '/NDL', '/NJH')
    if ($ExcludeFile.Count -gt 0) { $robocopyArgs += '/XF'; $robocopyArgs += $ExcludeFile }
    $robocopyArgs += $ExtraArgument
    $null = & robocopy.exe @robocopyArgs
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE ($Source -> $Destination)." }
}
