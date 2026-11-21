# ---------------------------------------------------------------------------------------------
# Console user interface helpers
# ---------------------------------------------------------------------------------------------

$script:TkLineWidth = 79

function Write-TkLine {
    [CmdletBinding()]
    param([char]$Char = '=', [string]$Color = 'DarkCyan')
    Write-Host ([string]$Char * $script:TkLineWidth) -ForegroundColor $Color
}

function Show-TkHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [switch]$NoClear
    )
    if (-not $NoClear) { Clear-Host }
    Write-TkLine
    $text = "MSMG Toolkit PS7 - $Title"
    $pad = [Math]::Max(0, [int](($script:TkLineWidth - $text.Length) / 2))
    Write-Host ((' ' * $pad) + $text) -ForegroundColor White
    Write-TkLine
    $status = Get-TkStatusLine
    if ($status) { Write-Host $status -ForegroundColor DarkGray; Write-TkLine -Char '-' -Color DarkGray }
    Write-Host ''
}

function Get-TkStatusLine {
    [CmdletBinding()]
    param()
    $ctx = $script:TK
    if (-not $ctx) { return '' }
    $s = $ctx.Session
    if (-not $s.SourceSelected) { return ' Source: (none selected)' }
    $info = $s.ImageInfo
    $parts = @(" Source: Windows 11 $($info.Release) ($($info.Version)) $($info.Architecture) $($info.DefaultLanguage)")
    $parts += "Index: $(@($s.Indexes) -join ',')"
    if ($s.ServiceBoot) { $parts += 'Boot' }
    if ($s.ServiceWinRE) { $parts += 'WinRE' }
    if ($s.RegistryLoaded) { $parts += 'REGISTRY LOADED' }
    $parts -join ' | '
}

function Wait-TkKey {
    [CmdletBinding()]
    param([string]$Message = 'Press any key to continue...')
    Write-Host ''
    Write-Host $Message -NoNewline -ForegroundColor DarkGray
    try {
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
    catch {
        $null = Read-Host
    }
    Write-Host ''
}

function Read-TkInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default = ''
    )
    $suffix = if ($Default) { " [$Default]" } else { '' }
    $value = Read-Host -Prompt "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    $value.Trim()
}

function Confirm-TkAction {
    <#
    .SYNOPSIS
        Asks a yes/no question. Returns $true without asking when confirmations are disabled
        (unless -Force is used for really destructive operations).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$Always,
        [bool]$Default = $false
    )
    if (-not $Always -and -not $script:TK.Settings.ConfirmActions) { return $true }
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = Read-Host -Prompt "$Message $hint"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        switch -Regex ($answer.Trim()) {
            '^(y|yes|j|ja)$' { return $true }
            '^(n|no|nein)$' { return $false }
        }
    }
}

function ConvertFrom-TkSelectionString {
    <#
    .SYNOPSIS
        Parses a selection like "1,3,5-7" or "*" into a sorted list of unique numbers.
    .EXAMPLE
        ConvertFrom-TkSelectionString -Selection '1,3-4' -Maximum 5   # 1,3,4
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Selection,
        [Parameter(Mandatory)][int]$Maximum
    )
    $result = [System.Collections.Generic.SortedSet[int]]::new()
    $text = $Selection.Trim()
    if ($text -eq '') { return }
    if ($text -eq '*' -or $text -ieq 'all') {
        return 1..$Maximum
    }
    foreach ($token in ($text -split '[,;\s]+' | Where-Object { $_ })) {
        if ($token -match '^(\d+)-(\d+)$') {
            $from = [int]$Matches[1]; $to = [int]$Matches[2]
            if ($from -gt $to) { $from, $to = $to, $from }
            foreach ($n in $from..$to) {
                if ($n -lt 1 -or $n -gt $Maximum) { throw "Selection '$n' is out of range (1-$Maximum)." }
                $null = $result.Add($n)
            }
        }
        elseif ($token -match '^\d+$') {
            $n = [int]$token
            if ($n -lt 1 -or $n -gt $Maximum) { throw "Selection '$n' is out of range (1-$Maximum)." }
            $null = $result.Add($n)
        }
        else {
            throw "Invalid selection '$token'. Use e.g. 1,3,5-7 or *."
        }
    }
    $result
}

function Read-TkSelection {
    <#
    .SYNOPSIS
        Shows a numbered list and returns the selected items (wrap the call in @() at the caller).
    .PARAMETER Label
        Script block that turns an item into its display text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [scriptblock]$Label = { param($i) "$i" },
        [string]$Prompt = 'Select (e.g. 1,3,5-7 or * for all, empty = cancel)',
        [switch]$Single
    )
    if ($Items.Count -eq 0) {
        Write-TkLog 'Nothing to select.' -Level Warn
        return
    }
    $width = "$($Items.Count)".Length
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $num = "$($i + 1)".PadLeft($width)
        Write-Host ("  [{0}] {1}" -f $num, (& $Label $Items[$i]))
    }
    Write-Host ''
    while ($true) {
        $text = Read-Host -Prompt $Prompt
        try {
            $numbers = @(ConvertFrom-TkSelectionString -Selection $text -Maximum $Items.Count)
            if ($Single -and $numbers.Count -gt 1) { throw 'Please select exactly one entry.' }
            return $numbers | ForEach-Object { $Items[$_ - 1] }
        }
        catch {
            Write-TkLog $_.Exception.Message -Level Warn
        }
    }
}

function Invoke-TkMenu {
    <#
    .SYNOPSIS
        Renders a menu and runs the selected action until the user goes back.
    .PARAMETER Items
        Array of hashtables: @{ Key = '1'; Label = 'Text'; Action = { ... }; NoPause = $false }
        An item with only a Label renders as a section caption.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object]$Items,
        [string]$BackLabel = 'Go Back'
    )
    while ($true) {
        $menuItems = if ($Items -is [scriptblock]) { @(& $Items) } else { @($Items) }
        Show-TkHeader -Title $Title
        foreach ($item in $menuItems) {
            if (-not $item.Key) {
                Write-Host ''
                Write-Host "  $($item.Label)" -ForegroundColor DarkYellow
                continue
            }
            Write-Host ("  [{0}] {1}" -f $item.Key.PadLeft(2), $item.Label)
        }
        Write-Host ''
        Write-Host ("  [{0}] {1}" -f ' X', $BackLabel)
        Write-Host ''
        Write-TkLine
        $choice = (Read-Host -Prompt 'Enter your choice').Trim()
        if ($choice -ieq 'X') { return }
        $selected = $menuItems | Where-Object { $_.Key -and $_.Key -ieq $choice } | Select-Object -First 1
        if (-not $selected) { continue }

        Show-TkHeader -Title $selected.Label
        $result = $null
        $failed = $false
        try {
            $result = & $selected.Action
        }
        catch {
            $failed = $true
            Write-TkLog $_.Exception.Message -Level Error
            if ($_.ScriptStackTrace) { Write-TkLog $_.ScriptStackTrace -Level Debug }
        }
        if ($failed -or -not $selected.NoPause) { Wait-TkKey }
        if (@($result) -contains 'Exit') { return }
    }
}
