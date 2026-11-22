# ---------------------------------------------------------------------------------------------
# wimlib integration
#   wimlib-imagex (Bin\<arch>\wimlib-imagex.exe + libwim-15.dll) is the default engine for all
#   operations on WIM/ESD FILES: export/convert, rebuild, split/join, delete, rename, capture,
#   apply and extracting single files. It is usually much faster than DISM for these tasks.
#   If wimlib is disabled (option "WIM engine"), missing or fails, DISM is used as fallback.
#
#   Image SERVICING (mount, packages, drivers, features, apps) always uses DISM -
#   wimlib cannot mount images for servicing on Windows.
# ---------------------------------------------------------------------------------------------

$script:TkLastWimEngine = ''

function Get-TkWimlibPath {
    <# Path of wimlib-imagex.exe (setting "WimlibPath" or Bin\<arch>\), empty if not found. #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $configured = $script:TK.Settings.WimlibPath
    if ($configured) {
        if (Test-Path -LiteralPath $configured) { return $configured }
        return ''
    }
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) { 'ARM64' { 'arm64' } 'x86' { 'x86' } default { 'x64' } }
    # x64 binaries also run on Windows 11 arm64 (emulation)
    foreach ($folder in @($arch, 'x64') | Select-Object -Unique) {
        $candidate = Join-Path $script:TK.Paths.Bin "$folder\wimlib-imagex.exe"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    ''
}

function Test-TkWimlibEnabled {
    <# $true when wimlib is the selected WIM engine and wimlib-imagex.exe is available. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if ("$($script:TK.Settings.WimEngine)" -ne 'wimlib') { return $false }
    if (-not $IsWindows) { return $false }
    [bool](Get-TkWimlibPath)
}

function Get-TkWimlibVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $exe = Get-TkWimlibPath
    if (-not $exe) { return '' }
    try {
        $first = @(& $exe --version 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '\S' })[0]
        "$first".Trim()
    }
    catch { '' }
}

function Invoke-TkWimlib {
    <# Runs wimlib-imagex.exe; output goes to the console, a non-zero exit code throws. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$ArgumentList)
    $exe = Get-TkWimlibPath
    if (-not $exe) { throw 'wimlib-imagex.exe not found.' }
    Write-TkLog "wimlib-imagex $($ArgumentList -join ' ')" -Level Debug
    & $exe @ArgumentList 2>&1 | ForEach-Object { "    $_" } | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "wimlib-imagex $($ArgumentList[0]) failed with exit code $LASTEXITCODE." }
}

function Invoke-TkWimEngine {
    <#
    .SYNOPSIS
        Runs an operation with wimlib (default) and falls back to DISM when wimlib is disabled,
        missing or fails.
    .PARAMETER Cleanup
        Runs after a wimlib failure before the DISM fallback (e.g. delete a half-written file).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][scriptblock]$WimlibAction,
        [Parameter(Mandatory)][scriptblock]$DismAction,
        [scriptblock]$CleanupAction
    )
    if (Test-TkWimlibEnabled) {
        try {
            $null = & $WimlibAction
            $script:TkLastWimEngine = 'wimlib'
            return
        }
        catch {
            Write-TkLog "$Operation with wimlib failed: $($_.Exception.Message) - falling back to DISM." -Level Warn
            if ($CleanupAction) {
                try { $null = & $CleanupAction } catch { Write-TkLog "Cleanup failed: $($_.Exception.Message)" -Level Warn }
            }
        }
    }
    Initialize-TkDism
    $null = & $DismAction
    $script:TkLastWimEngine = 'dism'
}

function ConvertTo-TkWimlibCompression {
    <# Maps DISM compression names to wimlib-imagex options. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Compression)
    switch ($Compression) {
        'none' { '--compress=none' }
        'fast' { '--compress=XPRESS' }
        'recovery' { '--solid' }   # ESD: solid LZMS
        default { '--compress=LZX' } # max
    }
}

function Get-TkWimlibExportArgument {
    <#
    .SYNOPSIS
        Builds the wimlib-imagex "export" arguments. The compression is only set when the
        destination is created (an existing WIM keeps its compression type).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$SourceImagePath,
        [Parameter(Mandatory)][string]$SourceIndex,
        [Parameter(Mandatory)][string]$DestinationImagePath,
        [string]$Compression = 'max',
        [string]$DestinationName,
        [switch]$Bootable,
        [switch]$DestinationExists
    )
    $arguments = @('export', $SourceImagePath, $SourceIndex, $DestinationImagePath)
    if ($DestinationName) { $arguments += $DestinationName }
    if (-not $DestinationExists) { $arguments += ConvertTo-TkWimlibCompression -Compression $Compression }
    if ($Bootable) { $arguments += '--boot' }
    $arguments += '--check'
    $arguments
}

function Export-TkWimImage {
    <#
    .SYNOPSIS
        Exports one index (or 'all') into a WIM/ESD file - wimlib with DISM fallback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceImagePath,
        [Parameter(Mandatory)][string]$SourceIndex,
        [Parameter(Mandatory)][string]$DestinationImagePath,
        [ValidateSet('none', 'fast', 'max', 'recovery')][string]$Compression = 'max',
        [string]$DestinationName,
        [switch]$Bootable
    )
    $existedBefore = Test-Path -LiteralPath $DestinationImagePath
    Invoke-TkWimEngine -Operation "Export of index $SourceIndex" -WimlibAction {
        $wimArgs = Get-TkWimlibExportArgument -SourceImagePath $SourceImagePath -SourceIndex $SourceIndex `
            -DestinationImagePath $DestinationImagePath -Compression $Compression -DestinationName $DestinationName `
            -Bootable:$Bootable -DestinationExists:$existedBefore
        Invoke-TkWimlib -ArgumentList $wimArgs
    } -CleanupAction {
        # wimlib appends atomically; only a newly created file can be left half-written
        if (-not $existedBefore) { Remove-Item -LiteralPath $DestinationImagePath -Force -ErrorAction SilentlyContinue }
    } -DismAction {
        $dp = Get-TkDismParameter
        $indexes = if ($SourceIndex -eq 'all') {
            @(Get-WindowsImage -ImagePath $SourceImagePath @dp | ForEach-Object { $_.ImageIndex })
        }
        else { @([int]$SourceIndex) }
        foreach ($i in $indexes) {
            $params = @{
                SourceImagePath      = $SourceImagePath
                SourceIndex          = $i
                DestinationImagePath = $DestinationImagePath
                CompressionType      = $Compression
                CheckIntegrity       = $true
            }
            if ($DestinationName) { $params.DestinationName = $DestinationName }
            if ($Bootable) { $params.Setbootable = $true }
            Export-WindowsImage @params @dp | Out-Null
        }
    }
}

function Export-TkFileFromWim {
    <#
    .SYNOPSIS
        Extracts one file from a WIM index without mounting it for servicing
        (wimlib "extract"; DISM fallback: read-only mount + copy).
    .OUTPUTS
        Full path of the extracted file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$DestinationFolder
    )
    $null = New-Item -Path $DestinationFolder -ItemType Directory -Force
    $relative = $FilePath.TrimStart('\', '/') -replace '/', '\'
    $target = Join-Path $DestinationFolder (Split-Path -Leaf $relative)
    if (Test-Path -LiteralPath $target) {
        [System.IO.File]::SetAttributes($target, [System.IO.FileAttributes]::Normal)
        Remove-Item -LiteralPath $target -Force
    }

    Invoke-TkWimEngine -Operation "Extracting $relative" -WimlibAction {
        Invoke-TkWimlib -ArgumentList @('extract', $ImagePath, "$Index", ('/' + ($relative -replace '\\', '/')), "--dest-dir=$DestinationFolder", '--no-acls')
        if (-not (Test-Path -LiteralPath $target)) { throw "'$relative' was not extracted." }
    } -CleanupAction {
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    } -DismAction {
        $dp = Get-TkDismParameter
        $mount = Join-Path $script:TK.Paths.Mount 'Extract'   # below <Mount>: covered by Tools -> Cleanup
        $null = New-Item -Path $mount -ItemType Directory -Force
        Mount-WindowsImage -ImagePath $ImagePath -Index $Index -Path $mount -ReadOnly @dp | Out-Null
        try {
            $source = Join-Path $mount $relative
            if (-not (Test-Path -LiteralPath $source)) { throw "'$relative' does not exist in index $Index." }
            [System.IO.File]::Copy($source, $target, $true)
        }
        finally {
            Dismount-WindowsImage -Path $mount -Discard @dp | Out-Null
        }
    }
    [System.IO.File]::SetAttributes($target, [System.IO.FileAttributes]::Normal)
    $target
}
