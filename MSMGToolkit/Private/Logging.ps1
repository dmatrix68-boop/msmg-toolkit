# ---------------------------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------------------------

function Start-TkLogging {
    [CmdletBinding()]
    param()
    if (-not $script:TK.Settings.Logging) { return }
    $name = 'Toolkit_{0:yyyyMMdd_HHmmss}.log' -f (Get-Date)
    $script:TK.LogFile = Join-Path $script:TK.Paths.Logs $name
    Write-TkLog "Log started: $($script:TK.LogFile)" -Level Debug
}

function Write-TkLog {
    <#
    .SYNOPSIS
        Writes a message to the console and (if enabled) to the toolkit log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Message,
        [ValidateSet('Info', 'Step', 'Success', 'Warn', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )

    $colors = @{
        Info    = 'Gray'
        Step    = 'Cyan'
        Success = 'Green'
        Warn    = 'Yellow'
        Error   = 'Red'
        Debug   = 'DarkGray'
    }
    $prefix = switch ($Level) {
        'Step' { '==> ' }
        'Success' { '[OK] ' }
        'Warn' { '[!] ' }
        'Error' { '[X] ' }
        default { '' }
    }

    if ($Level -ne 'Debug' -or $VerbosePreference -eq 'Continue') {
        Write-Host ($prefix + $Message) -ForegroundColor $colors[$Level]
    }

    $ctx = $script:TK
    if ($ctx -and $ctx.LogFile) {
        $line = '{0:yyyy-MM-dd HH:mm:ss} [{1,-7}] {2}' -f (Get-Date), $Level.ToUpperInvariant(), $Message
        try { Add-Content -LiteralPath $ctx.LogFile -Value $line -Encoding utf8 } catch { $null = $_ }
    }
}

function Invoke-TkStep {
    <#
    .SYNOPSIS
        Runs a script block as a named step, logs the result and never lets one failing item abort a batch.
    .OUTPUTS
        $true on success, $false on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    Write-TkLog $Name -Level Step
    try {
        $null = & $ScriptBlock
        return $true
    }
    catch {
        Write-TkLog "$Name failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}
