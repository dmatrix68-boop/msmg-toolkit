# ---------------------------------------------------------------------------------------------
# Target: ISO image and bootable USB drives
# ---------------------------------------------------------------------------------------------

function Get-TkOscdimgPath {
    <# Finds oscdimg.exe (setting, Windows ADK "Deployment Tools" or PATH). #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $configured = $script:TK.Settings.OscdimgPath
    if ($configured -and (Test-Path -LiteralPath $configured)) { return $configured }

    $archFolder = switch ($env:PROCESSOR_ARCHITECTURE) { 'ARM64' { 'arm64' } 'x86' { 'x86' } default { 'amd64' } }
    $kitRoots = @()
    try {
        $kitRoot = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -Name KitsRoot10 -ErrorAction Stop).KitsRoot10
        if ($kitRoot) { $kitRoots += $kitRoot }
    }
    catch { $null = $_ }
    $kitRoots += Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\'
    foreach ($root in $kitRoots | Select-Object -Unique) {
        foreach ($arch in @($archFolder, 'amd64', 'x86') | Select-Object -Unique) {
            $candidate = Join-Path $root "Assessment and Deployment Kit\Deployment Tools\$arch\Oscdimg\oscdimg.exe"
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    $cmd = Get-Command -Name oscdimg.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    ''
}

function Get-TkMediaDefaultName {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $release = ''; $arch = ''
    $wim = Join-Path $script:TK.Paths.DVD 'sources\install.wim'
    if (Test-Path -LiteralPath $wim) {
        try {
            $info = Get-TkImageInfo -ImagePath $wim -Index 1
            $release = $info.Release -replace '\s', ''
            $arch = $info.Architecture
        }
        catch { $null = $_ }
    }
    @{
        Label    = Get-TkIsoLabel -Label $script:TK.Settings.IsoLabel -Release $release -Architecture $arch
        FileName = ('Windows11_{0}_{1}_{2:yyyyMMdd}.iso' -f ($(if ($release) { $release } else { 'Custom' })), ($(if ($arch) { $arch } else { 'multi' })), (Get-Date))
    }
}

function New-TkIso {
    <#
    .SYNOPSIS
        Creates a bootable (BIOS + UEFI) ISO image from the DVD folder.
    .DESCRIPTION
        Uses oscdimg.exe from the Windows ADK when available. Without the ADK an IMAPI2
        based fallback is used (built into Windows).
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Label
    )
    if ($script:TK.Session.SourceSelected) { throw 'Images are still mounted. Save or discard them first (Apply menu).' }
    $dvd = $script:TK.Paths.DVD
    if (-not (Test-Path -LiteralPath (Join-Path $dvd 'sources'))) { throw "The DVD folder '$dvd' contains no setup media." }
    $defaults = Get-TkMediaDefaultName
    if (-not $Path) { $Path = Join-Path $script:TK.Paths.ISO $defaults.FileName }
    if (-not $Label) { $Label = $defaults.Label }
    $Label = Get-TkIsoLabel -Label $Label
    $null = New-Item -Path (Split-Path -Parent $Path) -ItemType Directory -Force

    $etfsboot = Join-Path $dvd 'boot\etfsboot.com'
    $efiName = if ($script:TK.Settings.IsoNoPrompt -and (Test-Path -LiteralPath (Join-Path $dvd 'efi\microsoft\boot\efisys_noprompt.bin'))) { 'efisys_noprompt.bin' } else { 'efisys.bin' }
    $efisys = Join-Path $dvd "efi\microsoft\boot\$efiName"
    if (-not (Test-Path -LiteralPath $efisys)) { throw "UEFI boot image '$efisys' not found in the media." }
    $hasBios = Test-Path -LiteralPath $etfsboot

    $oscdimg = Get-TkOscdimgPath
    if ($oscdimg) {
        Write-TkLog "Creating ISO with oscdimg: $Path" -Level Step
        $bootData = if ($hasBios) { "-bootdata:2#p0,e,b$etfsboot#pEF,e,b$efisys" } else { "-bootdata:1#pEF,e,b$efisys" }
        $oscdimgArgs = @('-m', '-o', '-u2', '-udfver102', "-l$Label", $bootData, $dvd, $Path)
        & $oscdimg @oscdimgArgs
        if ($LASTEXITCODE -ne 0) { throw "oscdimg.exe failed with exit code $LASTEXITCODE." }
    }
    else {
        Write-TkLog 'Windows ADK oscdimg.exe not found - using the built-in IMAPI2 fallback.' -Level Warn
        New-TkIsoImapi -SourcePath $dvd -Path $Path -Label $Label -BiosBootFile $(if ($hasBios) { $etfsboot } else { '' }) -UefiBootFile $efisys
    }
    $size = (Get-Item -LiteralPath $Path).Length
    Write-TkLog ("ISO created: {0} ({1:N2} GB)" -f $Path, ($size / 1GB)) -Level Success
}

function New-TkIsoImapi {
    <# ISO creation with the Windows IMAPI2 COM API (fallback without Windows ADK). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [string]$BiosBootFile,
        [Parameter(Mandatory)][string]$UefiBootFile
    )
    Initialize-TkNative
    $newBootOption = {
        param([string]$File, [int]$PlatformId)
        $stream = New-Object -ComObject ADODB.Stream
        $stream.Open()
        $stream.Type = 1   # binary
        $stream.LoadFromFile($File)
        $option = New-Object -ComObject IMAPI2FS.BootOptions
        $option.AssignBootImage($stream)
        $option.PlatformId = $PlatformId   # 0 = BIOS (x86), 0xEF = UEFI
        $option.Emulation = 0              # no emulation
        $option.Manufacturer = 'Microsoft'
        $option
    }

    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.ChooseImageDefaultsForMediaType(18)   # BD-R: allows images larger than a DVD
    $largeFile = Get-ChildItem -LiteralPath $SourcePath -Recurse -File | Where-Object { $_.Length -ge 4GB } | Select-Object -First 1
    $fsi.FileSystemsToCreate = if ($largeFile) { 4 } else { 7 }   # 4 = UDF only (files > 4 GB), 7 = ISO9660 + Joliet + UDF
    $fsi.UDFRevision = 0x102
    $fsi.VolumeName = $Label

    $options = @()
    if ($BiosBootFile) { $options += & $newBootOption $BiosBootFile 0 }
    $options += & $newBootOption $UefiBootFile 0xEF
    try {
        $fsi.BootImageOptionsArray = [object[]]$options
    }
    catch {
        Write-TkLog 'IMAPI2 does not accept multiple boot entries here - creating a UEFI-only ISO.' -Level Warn
        $fsi.BootImageOptions = $options[-1]
    }

    Write-TkLog 'Adding files to the ISO file system (this can take a while)...' -Level Step
    $fsi.Root.AddTree($SourcePath, $false)
    $result = $fsi.CreateResultImage()
    Write-TkLog "Writing $Path ..." -Level Step
    $null = [MsmgToolkitPS.ComStreamWriter]::WriteToFile($result.ImageStream, $Path)
    foreach ($com in @($result, $fsi) + $options) {
        if ($com) { $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($com) }
    }
}

# ---------------------------------------------------------------------------------------------
# USB
# ---------------------------------------------------------------------------------------------

function Get-TkUsbDisk {
    <# Lists USB disks (candidates for bootable media). #>
    [CmdletBinding()]
    param()
    @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsBoot -and -not $_.IsSystem } | Sort-Object Number)
}

function Format-TkUsbDrive {
    <#
    .SYNOPSIS
        Erases a USB disk and creates one FAT32 partition (boots on UEFI, and on BIOS with MBR).
    .OUTPUTS
        The drive letter of the new volume.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][int]$DiskNumber,
        [string]$Label = 'WIN11',
        [ValidateSet('MBR', 'GPT')][string]$PartitionStyle = $script:TK.Settings.UsbPartitionStyle,
        [switch]$Force
    )
    $disk = Get-Disk -Number $DiskNumber
    if ($disk.IsBoot -or $disk.IsSystem) { throw "Disk $DiskNumber is the system/boot disk - refusing to format it." }
    if ($disk.BusType -ne 'USB' -and -not $Force) { throw "Disk $DiskNumber is not a USB disk (bus type $($disk.BusType)). Use -Force to override." }
    $description = '{0} - {1} ({2:N1} GB)' -f $disk.Number, $disk.FriendlyName, ($disk.Size / 1GB)
    if (-not $Force) {
        Write-TkLog "ALL DATA on disk $description will be deleted!" -Level Warn
        $typed = Read-Host -Prompt "Type the disk number ($DiskNumber) to confirm"
        if ($typed -ne "$DiskNumber") { throw 'Aborted by user.' }
    }

    Write-TkLog "Erasing disk $description..." -Level Step
    if ($disk.IsOffline) { Set-Disk -Number $DiskNumber -IsOffline $false }
    if ($disk.IsReadOnly) { Set-Disk -Number $DiskNumber -IsReadOnly $false }
    if ($disk.PartitionStyle -ne 'RAW') {
        Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
    }
    $disk = Get-Disk -Number $DiskNumber
    if ($disk.PartitionStyle -eq 'RAW') {
        Initialize-Disk -Number $DiskNumber -PartitionStyle $PartitionStyle
    }
    else {
        Set-Disk -Number $DiskNumber -PartitionStyle $PartitionStyle
    }

    # Windows formats FAT32 volumes up to 32 GB only
    $partitionParams = @{ DiskNumber = $DiskNumber; AssignDriveLetter = $true }
    if ($disk.Size -gt 32GB) { $partitionParams.Size = 32GB - 1MB } else { $partitionParams.UseMaximumSize = $true }
    if ($PartitionStyle -eq 'MBR') { $partitionParams.IsActive = $true }
    $partition = New-Partition @partitionParams
    $volumeLabel = $Label.ToUpperInvariant() -replace '[^A-Z0-9_]', ''
    if ($volumeLabel.Length -gt 11) { $volumeLabel = $volumeLabel.Substring(0, 11) }   # FAT32 limit
    $null = Format-Volume -Partition $partition -FileSystem FAT32 -NewFileSystemLabel $volumeLabel -Confirm:$false
    $letter = (Get-Partition -DiskNumber $DiskNumber -PartitionNumber $partition.PartitionNumber).DriveLetter
    if (-not $letter) { throw 'The new partition did not get a drive letter.' }
    Write-TkLog "USB drive formatted as $($letter): (FAT32, $PartitionStyle)." -Level Success
    "$letter"
}

function Copy-TkMediaToUsb {
    <#
    .SYNOPSIS
        Copies setup media to a (formatted) USB drive. install.wim files larger than 4 GB are split
        into install.swm parts on FAT32 drives.
    .PARAMETER SourcePath
        Media root (default: DVD folder).
    .PARAMETER ImagesOnly
        Only refreshes sources\boot.wim, sources\install.* and Autounattend.xml (sync mode).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z]$')][string]$DriveLetter,
        [string]$SourcePath = $script:TK.Paths.DVD,
        [switch]$ImagesOnly
    )
    Initialize-TkDism
    $target = "$($DriveLetter):\"
    $volume = Get-Volume -DriveLetter $DriveLetter
    $fat32 = $volume.FileSystem -eq 'FAT32'
    $sources = Join-Path $SourcePath 'sources'
    $installWim = Join-Path $sources 'install.wim'
    $split = $fat32 -and (Test-Path -LiteralPath $installWim) -and (Get-Item -LiteralPath $installWim).Length -ge 4GB
    $exclude = @()
    if ($split) { $exclude += 'install.wim' }

    if ($ImagesOnly) {
        $targetSources = Join-Path $target 'sources'
        Get-ChildItem -LiteralPath $targetSources -Filter 'install*' -File -ErrorAction SilentlyContinue | Remove-Item -Force
        foreach ($file in 'boot.wim', 'install.wim', 'install.esd') {
            $src = Join-Path $sources $file
            if ((Test-Path -LiteralPath $src) -and -not ($split -and $file -eq 'install.wim')) {
                Write-TkLog "Copying sources\$file ..." -Level Step
                Copy-Item -LiteralPath $src -Destination $targetSources -Force
            }
        }
        $answer = Join-Path $SourcePath 'Autounattend.xml'
        if (Test-Path -LiteralPath $answer) { Copy-Item -LiteralPath $answer -Destination $target -Force }
    }
    else {
        Write-TkLog "Copying setup media to $target ..." -Level Step
        Invoke-TkRobocopy -Source $SourcePath -Destination $target -ExcludeFile $exclude
    }

    if ($split) {
        Write-TkLog "install.wim is larger than 4 GB - splitting into $($script:TK.Settings.SwmChunkSizeMB) MB parts..." -Level Step
        $dp = Get-TkDismParameter
        Split-WindowsImage -ImagePath $installWim -SplitImagePath (Join-Path $target 'sources\install.swm') `
            -FileSize ([int]$script:TK.Settings.SwmChunkSizeMB) -CheckIntegrity @dp | Out-Null
    }
    Write-TkLog "Setup media copied to $target" -Level Success
}

function New-TkUsbMedia {
    <#
    .SYNOPSIS
        Formats a USB disk and copies the media from the DVD folder or an ISO file to it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$DiskNumber,
        [string]$IsoPath,
        [switch]$Force
    )
    if (-not $IsoPath -and $script:TK.Session.SourceSelected) { throw 'Images are still mounted. Save or discard them first (Apply menu).' }
    $letter = Format-TkUsbDrive -DiskNumber $DiskNumber -Force:$Force
    if ($IsoPath) {
        $null = Mount-DiskImage -ImagePath $IsoPath -StorageType ISO -PassThru
        try {
            $isoLetter = $null
            for ($i = 0; $i -lt 20 -and -not $isoLetter; $i++) {
                $isoLetter = (Get-DiskImage -ImagePath $IsoPath | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
                if (-not $isoLetter) { Start-Sleep -Milliseconds 500 }
            }
            if (-not $isoLetter) { throw 'The mounted ISO did not get a drive letter.' }
            Copy-TkMediaToUsb -DriveLetter $letter -SourcePath "$($isoLetter):\"
        }
        finally {
            $null = Dismount-DiskImage -ImagePath $IsoPath
        }
    }
    else {
        Copy-TkMediaToUsb -DriveLetter $letter
    }
}
