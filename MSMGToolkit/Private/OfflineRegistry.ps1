# ---------------------------------------------------------------------------------------------
# Offline registry of mounted images
#   Hives are loaded to HKLM\<Prefix>_<HIVE> (default prefix "TK", e.g. HKLM\TK_SOFTWARE).
#   All writes use the .NET registry API (the PowerShell provider treats "/" as a separator,
#   which breaks keys such as "...WindowsUpdateClient/Operational").
# ---------------------------------------------------------------------------------------------

$script:TkHiveFiles = [ordered]@{
    SOFTWARE = 'Windows\System32\config\SOFTWARE'
    SYSTEM   = 'Windows\System32\config\SYSTEM'
    DEFAULT  = 'Windows\System32\config\DEFAULT'
    NTUSER   = 'Users\Default\NTUSER.DAT'
}

function Mount-TkImageHive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [ValidateSet('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER')]
        [string[]]$Hive = @('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER'),
        [string]$Prefix = 'TK'
    )
    foreach ($name in $Hive) {
        $file = Join-Path $ImagePath $script:TkHiveFiles[$name]
        $key = "HKLM\$($Prefix)_$name"
        if ($script:TK.LoadedHives -contains $key) { continue }
        if (-not (Test-Path -LiteralPath $file)) { throw "Registry hive file not found: $file" }
        $null = & reg.exe load $key $file 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Could not load registry hive '$file' to '$key'." }
        $script:TK.LoadedHives.Add($key)
        Write-TkLog "Loaded hive $key" -Level Debug
    }
}

function Dismount-TkImageHive {
    [CmdletBinding()]
    param([string]$Prefix = 'TK')
    $keys = @($script:TK.LoadedHives | Where-Object { $_ -like "HKLM\$($Prefix)_*" })
    foreach ($key in $keys) {
        $ok = $false
        for ($attempt = 1; $attempt -le 6 -and -not $ok; $attempt++) {
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            $null = & reg.exe unload $key 2>&1
            if ($LASTEXITCODE -eq 0) { $ok = $true } else { Start-Sleep -Seconds 1 }
        }
        if ($ok) {
            $null = $script:TK.LoadedHives.Remove($key)
            Write-TkLog "Unloaded hive $key" -Level Debug
        }
        else {
            Write-TkLog "Could not unload hive $key - close all programs using it (e.g. regedit) and use Tools -> Cleanup." -Level Error
        }
    }
}

function Use-TkImageHive {
    <#
    .SYNOPSIS
        Loads the hives of an image, runs the script block and always unloads them again.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [string[]]$Hive = @('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER'),
        [string]$Prefix = 'TK'
    )
    try {
        Mount-TkImageHive -ImagePath $ImagePath -Hive $Hive -Prefix $Prefix
        & $ScriptBlock
    }
    finally {
        Dismount-TkImageHive -Prefix $Prefix
    }
}

function Resolve-TkHiveSubKey {
    <# Builds the HKLM sub key of an offline hive path; maps CurrentControlSet to ControlSet001. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateSet('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER')][string]$Hive,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [string]$Prefix = 'TK'
    )
    $sub = $Path.Trim('\')
    if ($Hive -eq 'SYSTEM') { $sub = $sub -replace '^(?i)CurrentControlSet(?=\\|$)', 'ControlSet001' }
    if ($sub) { "$($Prefix)_$Hive\$sub" } else { "$($Prefix)_$Hive" }
}

function ConvertTo-TkRegistryData {
    <#
        Converts a value from a tweak definition into the .NET type expected for the value kind.
        Arrays are returned with the unary comma so byte[] / string[] keep their type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('String', 'ExpandString', 'DWord', 'QWord', 'Binary', 'MultiString')][string]$Type,
        [AllowNull()][object]$Value
    )
    switch ($Type) {
        'DWord' {
            $n = [int64]$Value
            if ($n -gt [int32]::MaxValue) { return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$n), 0) }
            return [int32]$n
        }
        'QWord' { return [int64]$Value }
        'Binary' {
            if ($Value -is [byte[]]) { return , $Value }
            $hex = ("$Value" -replace '[\s,]', '')
            if ($hex.Length % 2) { throw "Invalid binary value '$Value'." }
            return , [byte[]]@(for ($i = 0; $i -lt $hex.Length; $i += 2) { [Convert]::ToByte($hex.Substring($i, 2), 16) })
        }
        'MultiString' { return , [string[]]@($Value) }
        default { return [string]$Value }
    }
}

function Set-TkRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER')][string]$Hive,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][ValidateSet('String', 'ExpandString', 'DWord', 'QWord', 'Binary', 'MultiString')][string]$Type,
        [AllowNull()][object]$Value,
        [string]$Prefix = 'TK'
    )
    $sub = Resolve-TkHiveSubKey -Hive $Hive -Path $Path -Prefix $Prefix
    $data = ConvertTo-TkRegistryData -Type $Type -Value $Value
    $key = Open-TkWritableKey -SubKey $sub
    try {
        $key.SetValue($Name, $data, [Microsoft.Win32.RegistryValueKind]::$Type)
    }
    finally {
        $key.Dispose()
    }
}

function Remove-TkRegistryEntry {
    <# Removes a value (when -Name is given) or a whole key. Missing entries are ignored. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER')][string]$Hive,
        [Parameter(Mandatory)][string]$Path,
        [string]$Name,
        [string]$Prefix = 'TK'
    )
    $sub = Resolve-TkHiveSubKey -Hive $Hive -Path $Path -Prefix $Prefix
    $existing = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($sub)
    if (-not $existing) { return }
    $existing.Dispose()
    if ($PSBoundParameters.ContainsKey('Name')) {
        $key = Open-TkWritableKey -SubKey $sub
        try { $key.DeleteValue($Name, $false) } finally { $key.Dispose() }
    }
    else {
        [Microsoft.Win32.Registry]::LocalMachine.DeleteSubKeyTree($sub, $false)
    }
}

function Open-TkWritableKey {
    <#
    .SYNOPSIS
        Opens (or creates) a writable key below HKLM. Falls back to backup/restore semantics for
        keys protected by TrustedInstaller, without changing their ACL.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SubKey)
    try {
        return [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($SubKey, $true)
    }
    catch {
        $base = $_.Exception.GetBaseException()
        if ($base -isnot [System.UnauthorizedAccessException] -and $base -isnot [System.Security.SecurityException]) { throw }
        Enable-TkPrivilege -Name 'SeBackupPrivilege', 'SeRestorePrivilege'
        return [MsmgToolkitPS.BackupRegistry]::CreateKey($SubKey)
    }
}

function Grant-TkRegistryKeyAccess {
    <#
    .SYNOPSIS
        Takes ownership of a protected key (e.g. Component Based Servicing) and grants
        Administrators full control, so the toolkit can modify it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SubKey)

    Enable-TkPrivilege
    $hklm = [Microsoft.Win32.Registry]::LocalMachine
    $admins = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $check = [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree

    $key = $hklm.OpenSubKey($SubKey, $check, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
    if (-not $key) { return $false }
    try {
        $owner = [System.Security.AccessControl.RegistrySecurity]::new()
        $owner.SetOwner($admins)
        $key.SetAccessControl($owner)
    }
    finally { $key.Dispose() }

    $key = $hklm.OpenSubKey($SubKey, $check, [System.Security.AccessControl.RegistryRights]::ChangePermissions -bor [System.Security.AccessControl.RegistryRights]::ReadPermissions)
    try {
        $acl = $key.GetAccessControl()
        $rule = [System.Security.AccessControl.RegistryAccessRule]::new(
            $admins,
            [System.Security.AccessControl.RegistryRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow)
        $acl.SetAccessRule($rule)
        $key.SetAccessControl($acl)
    }
    finally { $key.Dispose() }
    $true
}

# ---------------------------------------------------------------------------------------------
# .reg file conversion: maps live registry roots onto the loaded offline hives
# ---------------------------------------------------------------------------------------------

function Convert-TkRegistryPath {
    <#
    .SYNOPSIS
        Maps a live registry path (as used in .reg files) onto the loaded offline hives.
    .EXAMPLE
        Convert-TkRegistryPath 'HKEY_CURRENT_USER\Software\Test'   # HKEY_LOCAL_MACHINE\TK_NTUSER\Software\Test
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Path,
        [string]$Prefix = 'TK'
    )
    $hklm = 'HKEY_LOCAL_MACHINE'
    $rules = @(
        @{ Pattern = '^(HKEY_LOCAL_MACHINE|HKLM)\\SYSTEM\\(CurrentControlSet|ControlSet\d{3})(?=\\|$)'; Target = "$hklm\$($Prefix)_SYSTEM\ControlSet001" }
        @{ Pattern = '^(HKEY_LOCAL_MACHINE|HKLM)\\SOFTWARE(?=\\|$)'; Target = "$hklm\$($Prefix)_SOFTWARE" }
        @{ Pattern = '^(HKEY_LOCAL_MACHINE|HKLM)\\SYSTEM(?=\\|$)'; Target = "$hklm\$($Prefix)_SYSTEM" }
        @{ Pattern = '^(HKEY_CLASSES_ROOT|HKCR)(?=\\|$)'; Target = "$hklm\$($Prefix)_SOFTWARE\Classes" }
        @{ Pattern = '^(HKEY_CURRENT_USER|HKCU)(?=\\|$)'; Target = "$hklm\$($Prefix)_NTUSER" }
        @{ Pattern = '^(HKEY_USERS|HKU)\\\.DEFAULT(?=\\|$)'; Target = "$hklm\$($Prefix)_DEFAULT" }
    )
    foreach ($rule in $rules) {
        if ($Path -match "(?i)$($rule.Pattern)") {
            return [regex]::Replace($Path, "(?i)$($rule.Pattern)", $rule.Target.Replace('$', '$$'))
        }
    }
    throw "Registry path '$Path' cannot be mapped to the offline image (supported: HKLM\SOFTWARE, HKLM\SYSTEM, HKCR, HKCU, HKU\.DEFAULT)."
}

function Convert-TkRegFileContent {
    <#
    .SYNOPSIS
        Rewrites the key headers of a .reg file so it can be imported into the offline hives.
        Values are left untouched; comments are kept.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [string]$Prefix = 'TK'
    )
    $lines = $Content -split '\r?\n'
    $out = foreach ($line in $lines) {
        if ($line -match '^\s*\[(-?)([^\]]+)\]\s*$') {
            $delete = $Matches[1]
            $mapped = Convert-TkRegistryPath -Path $Matches[2].Trim() -Prefix $Prefix
            "[$delete$mapped]"
        }
        else {
            $line
        }
    }
    ($out -join "`r`n")
}

function Import-TkRegFileToImage {
    <# Converts and imports one .reg file into the currently loaded offline hives. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $content = Get-Content -LiteralPath $Path -Raw
    $converted = Convert-TkRegFileContent -Content $content
    $temp = Join-Path $script:TK.Paths.Temp ("import_{0}.reg" -f [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($temp, $converted, [System.Text.Encoding]::Unicode)
        $null = & reg.exe import $temp 2>&1
        if ($LASTEXITCODE -ne 0) { throw "reg.exe import failed for '$Path'." }
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}
