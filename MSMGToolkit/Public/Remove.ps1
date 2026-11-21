# ---------------------------------------------------------------------------------------------
# Remove: provisioned apps, Windows packages and capabilities (list based or interactive)
#
# The closed-source "ToolkitHelper.exe" component removal engine of the original toolkit is
# not part of this rewrite. Component removal uses DISM only (optionally after un-hiding
# packages in the offline component store registry).
# ---------------------------------------------------------------------------------------------

function Get-TkListPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$FileName)
    Join-Path $script:TK.Paths.Lists $FileName
}

# ---------------------------------------------------------------------------------------------
# Provisioned apps
# ---------------------------------------------------------------------------------------------

function Get-TkProvisionedApp {
    [CmdletBinding()]
    param()
    Assert-TkSource
    $image = @(Get-TkImage -Kind Install)[0]
    $dp = Get-TkDismParameter
    @(Get-AppxProvisionedPackage -Path $image.Path @dp | Sort-Object DisplayName)
}

function Remove-TkProvisionedApp {
    <#
    .SYNOPSIS
        Removes provisioned apps from the install images.
    .PARAMETER Name
        App display names (e.g. Microsoft.BingNews). Wildcards are allowed.
    .PARAMETER ListPath
        List file with one display name per line (default: Lists\RemoveAppsList.txt).
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Name')][string[]]$Name,
        [Parameter(ParameterSetName = 'List')][string]$ListPath = (Get-TkListPath 'RemoveAppsList.txt')
    )
    Assert-TkSource
    $dp = Get-TkDismParameter
    $wanted = if ($PSCmdlet.ParameterSetName -eq 'Name') { $Name } else { Read-TkList -Path $ListPath }
    if (@($wanted).Count -eq 0) { Write-TkLog 'The app list is empty.' -Level Warn; return }

    foreach ($image in Get-TkImage -Kind Install) {
        $apps = @(Get-AppxProvisionedPackage -Path $image.Path @dp)
        foreach ($entry in $wanted) {
            $found = @($apps | Where-Object { $_.DisplayName -like $entry })
            if ($found.Count -eq 0) { Write-TkLog "App '$entry' is not provisioned in image $($image.Index)." -Level Debug; continue }
            foreach ($app in $found) {
                $null = Invoke-TkStep -Name "Removing app $($app.DisplayName) from image $($image.Index)" -ScriptBlock {
                    Remove-AppxProvisionedPackage -Path $image.Path -PackageName $app.PackageName @dp | Out-Null
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Windows packages
# ---------------------------------------------------------------------------------------------

function Show-TkHiddenPackage {
    <#
    .SYNOPSIS
        Makes hidden component store packages visible (and removable) for DISM by setting
        Visibility=1 and removing their "Owners" key in the offline SOFTWARE hive.
    .PARAMETER Name
        Package name prefixes (without version), e.g. Microsoft-Windows-StepsRecorder-Package.
    .OUTPUTS
        Number of modified packages.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][string[]]$Name
    )
    # Script blocks run in a child scope: use a reference type for the counter
    $state = @{ Count = 0; Prefixes = @($Name) }
    Use-TkImageHive -ImagePath $ImagePath -Hive SOFTWARE -ScriptBlock {
        $cbs = 'TK_SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
        $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($cbs)
        if (-not $root) { throw 'Component Based Servicing key not found in the offline image.' }
        try { $keys = $root.GetSubKeyNames() } finally { $root.Dispose() }

        foreach ($keyName in $keys) {
            $match = $state.Prefixes | Where-Object { $keyName -like "$_~*" } | Select-Object -First 1
            if (-not $match) { continue }
            $sub = "$cbs\$keyName"
            if (-not (Grant-TkRegistryKeyAccess -SubKey $sub)) { continue }
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($sub, $true)
            try {
                $key.SetValue('Visibility', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
                if ($key.GetSubKeyNames() -contains 'Owners') {
                    $null = Grant-TkRegistryKeyAccess -SubKey "$sub\Owners"
                    $key.DeleteSubKeyTree('Owners', $false)
                }
            }
            finally { $key.Dispose() }
            $state.Count++
        }
    }
    $state.Count
}

function Get-TkPackage {
    [CmdletBinding()]
    param()
    Assert-TkSource
    $image = @(Get-TkImage -Kind Install)[0]
    $dp = Get-TkDismParameter
    @(Get-WindowsPackage -Path $image.Path @dp | Sort-Object PackageName)
}

function Remove-TkPackage {
    <#
    .SYNOPSIS
        Removes Windows packages listed by name prefix (default list: Lists\RemovePackagesList.txt).
    .PARAMETER Unhide
        Un-hides matching packages first, so that DISM can remove packages that are not listed
        as removable (use with care - this is how most "component removal" tools work).
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Name')][string[]]$Name,
        [Parameter(ParameterSetName = 'List')][string]$ListPath = (Get-TkListPath 'RemovePackagesList.txt'),
        [switch]$Unhide
    )
    Assert-TkSource
    $dp = Get-TkDismParameter
    $wanted = if ($PSCmdlet.ParameterSetName -eq 'Name') { $Name } else { Read-TkList -Path $ListPath }
    if (@($wanted).Count -eq 0) { Write-TkLog 'The package list is empty.' -Level Warn; return }
    $prefixes = @($wanted | ForEach-Object { ($_ -split '~')[0] })

    foreach ($image in Get-TkImage -Kind Install) {
        if ($Unhide) {
            $modified = Show-TkHiddenPackage -ImagePath $image.Path -Name $prefixes
            Write-TkLog "$modified package(s) made visible in image $($image.Index)." -Level Info
        }
        $packages = @(Get-WindowsPackage -Path $image.Path @dp)
        foreach ($prefix in $prefixes) {
            $found = @($packages | Where-Object { $_.PackageName -like "$prefix~*" })
            if ($found.Count -eq 0) { Write-TkLog "Package '$prefix' not found in image $($image.Index)." -Level Debug; continue }
            foreach ($package in $found) {
                $null = Invoke-TkStep -Name "Removing package $($package.PackageName) from image $($image.Index)" -ScriptBlock {
                    Remove-WindowsPackage -Path $image.Path -PackageName $package.PackageName -NoRestart @dp | Out-Null
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Capabilities (Features on Demand)
# ---------------------------------------------------------------------------------------------

function Remove-TkCapability {
    <#
    .SYNOPSIS
        Removes installed capabilities (default list: Lists\RemoveCapabilitiesList.txt).
        Entries are matched as prefix, e.g. "App.StepsRecorder" matches "App.StepsRecorder~~~~0.0.1.0".
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Name')][string[]]$Name,
        [Parameter(ParameterSetName = 'List')][string]$ListPath = (Get-TkListPath 'RemoveCapabilitiesList.txt')
    )
    Assert-TkSource
    $dp = Get-TkDismParameter
    $wanted = if ($PSCmdlet.ParameterSetName -eq 'Name') { $Name } else { Read-TkList -Path $ListPath }
    if (@($wanted).Count -eq 0) { Write-TkLog 'The capability list is empty.' -Level Warn; return }

    foreach ($image in Get-TkImage -Kind Install) {
        $installed = @(Get-WindowsCapability -Path $image.Path @dp | Where-Object { "$($_.State)" -eq 'Installed' })
        foreach ($entry in $wanted) {
            $found = @($installed | Where-Object { $_.Name -eq $entry -or $_.Name -like "$entry~*" -or $_.Name -like $entry })
            if ($found.Count -eq 0) { Write-TkLog "Capability '$entry' is not installed in image $($image.Index)." -Level Debug; continue }
            foreach ($capability in $found) {
                $null = Invoke-TkStep -Name "Removing capability $($capability.Name) from image $($image.Index)" -ScriptBlock {
                    Remove-WindowsCapability -Path $image.Path -Name $capability.Name @dp | Out-Null
                }
            }
        }
    }
}
