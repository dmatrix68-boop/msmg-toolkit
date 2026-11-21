# ---------------------------------------------------------------------------------------------
# Source: import Windows 11 media into <DVD>, select and mount images
# ---------------------------------------------------------------------------------------------

function Import-TkSource {
    <#
    .SYNOPSIS
        Copies Windows 11 setup media into the toolkit's DVD folder.
    .PARAMETER Path
        An ISO file, a drive (DVD/USB, e.g. "E:\"), an extracted media folder, or an ESD file
        (Media Creation Tool ESD or plain install.esd).
    .PARAMETER Index
        For ESD files: the edition indexes to convert (default: all).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int[]]$Index,
        [switch]$Force
    )
    Initialize-TkDism
    if ($script:TK.Session.SourceSelected) { throw 'A source is selected. Apply or discard it before importing new media.' }
    if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found: $Path" }

    $dvd = $script:TK.Paths.DVD
    if (-not (Test-Path -LiteralPath $dvd)) { $null = New-Item -Path $dvd -ItemType Directory -Force }
    if (Get-ChildItem -LiteralPath $dvd -Force | Select-Object -First 1) {
        if (-not $Force -and -not (Confirm-TkAction "The DVD folder is not empty. Delete its content and import '$Path'?" -Always)) { return }
        Get-ChildItem -LiteralPath $dvd -Force | Remove-Item -Recurse -Force
    }

    $item = Get-Item -LiteralPath $Path -Force
    $extension = if ($item -is [System.IO.FileInfo]) { $item.Extension.ToLowerInvariant() } else { '' }

    if ($extension -in '.esd', '.wim') {
        Import-TkSourceFromEsd -ImagePath $item.FullName -Index $Index
        return
    }

    $isoMounted = $false
    try {
        if ($extension -eq '.iso') {
            Write-TkLog "Mounting ISO '$($item.FullName)'..." -Level Step
            $null = Mount-DiskImage -ImagePath $item.FullName -StorageType ISO -PassThru
            $isoMounted = $true
            $letter = $null
            for ($i = 0; $i -lt 20 -and -not $letter; $i++) {
                $letter = (Get-DiskImage -ImagePath $item.FullName | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
                if (-not $letter) { Start-Sleep -Milliseconds 500 }
            }
            if (-not $letter) { throw 'The mounted ISO did not get a drive letter.' }
            $sourceRoot = "$($letter):\"
        }
        elseif ($item -is [System.IO.DirectoryInfo]) {
            $sourceRoot = $item.FullName
        }
        else {
            throw "Unsupported source '$Path'. Use an ISO file, a drive, a folder or an ESD/WIM file."
        }

        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'sources'))) {
            throw "'$sourceRoot' does not look like Windows setup media (no 'sources' folder)."
        }
        Write-TkLog "Copying setup media from '$sourceRoot' to '$dvd'..." -Level Step
        Invoke-TkRobocopy -Source $sourceRoot -Destination $dvd
        Set-TkFileWritable -Path $dvd
        Write-TkLog 'Source media imported.' -Level Success
    }
    finally {
        if ($isoMounted) { $null = Dismount-DiskImage -ImagePath $item.FullName }
    }

    $sources = Join-Path $dvd 'sources'
    if (-not (Test-Path -LiteralPath (Join-Path $sources 'install.wim')) -and (Test-Path -LiteralPath (Join-Path $sources 'install.esd'))) {
        Write-TkLog 'The media contains install.esd - it will be converted to install.wim when the source is selected.' -Level Warn
    }
}

function Import-TkSourceFromEsd {
    <#
    .SYNOPSIS
        Builds setup media from an ESD (e.g. Media Creation Tool / UUP ESD) or a plain install image.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [int[]]$Index
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter
    $dvd = $script:TK.Paths.DVD
    $sources = Join-Path $dvd 'sources'
    $images = @(Get-WindowsImage -ImagePath $ImagePath @dp)
    $isMediaEsd = $images.Count -ge 4 -and $images[0].ImageName -match 'Windows Setup Media'

    if ($isMediaEsd) {
        Write-TkLog 'Media ESD detected: extracting setup media files (index 1)...' -Level Step
        Expand-WindowsImage -ImagePath $ImagePath -Index 1 -ApplyPath $dvd @dp | Out-Null
        $bootWim = Join-Path $sources 'boot.wim'
        Write-TkLog 'Creating boot.wim (WinPE + Windows Setup)...' -Level Step
        Export-WindowsImage -SourceImagePath $ImagePath -SourceIndex 2 -DestinationImagePath $bootWim -CompressionType max @dp | Out-Null
        Export-WindowsImage -SourceImagePath $ImagePath -SourceIndex 3 -DestinationImagePath $bootWim -CompressionType max -Setbootable @dp | Out-Null
        $editions = @($images | Where-Object { $_.ImageIndex -ge 4 })
    }
    else {
        if (-not (Test-Path -LiteralPath $sources)) { $null = New-Item -Path $sources -ItemType Directory -Force }
        Write-TkLog 'Plain install image detected - only install.wim will be created (copy the remaining media files manually).' -Level Warn
        $editions = $images
    }

    if ($Index) { $editions = @($editions | Where-Object { $Index -contains $_.ImageIndex }) }
    if ($editions.Count -eq 0) { throw 'No editions selected for export.' }

    $installWim = Join-Path $sources 'install.wim'
    foreach ($edition in $editions) {
        Write-TkLog "Exporting index $($edition.ImageIndex): $($edition.ImageName)..." -Level Step
        Export-WindowsImage -SourceImagePath $ImagePath -SourceIndex $edition.ImageIndex -DestinationImagePath $installWim `
            -CompressionType $script:TK.Settings.ExportCompression @dp | Out-Null
    }
    Write-TkLog "Created '$installWim' with $($editions.Count) edition(s)." -Level Success
}

function Convert-TkInstallEsd {
    <# Converts DVD\sources\install.esd to install.wim (all indexes) and removes the ESD. #>
    [CmdletBinding()]
    param()
    Initialize-TkDism
    $dp = Get-TkDismParameter
    $sources = Join-Path $script:TK.Paths.DVD 'sources'
    $esd = Join-Path $sources 'install.esd'
    $wim = Join-Path $sources 'install.wim'
    if (-not (Test-Path -LiteralPath $esd)) { throw "No install.esd found in '$sources'." }
    Set-TkFileWritable -Path $esd
    foreach ($image in @(Get-WindowsImage -ImagePath $esd @dp)) {
        Write-TkLog "Converting index $($image.ImageIndex): $($image.ImageName)..." -Level Step
        Export-WindowsImage -SourceImagePath $esd -SourceIndex $image.ImageIndex -DestinationImagePath $wim `
            -CompressionType $script:TK.Settings.ExportCompression @dp | Out-Null
    }
    Remove-Item -LiteralPath $esd -Force
    Write-TkLog 'install.esd converted to install.wim.' -Level Success
}

function Get-TkSourceImage {
    <# Lists the indexes of DVD\sources\install.wim. #>
    [CmdletBinding()]
    param()
    Initialize-TkDism
    $wim = Join-Path $script:TK.Paths.DVD 'sources\install.wim'
    if (-not (Test-Path -LiteralPath $wim)) { throw "install.wim not found in '$($script:TK.Paths.DVD)\sources'." }
    $dp = Get-TkDismParameter -NoScratch
    Get-WindowsImage -ImagePath $wim @dp
}

function Select-TkSource {
    <#
    .SYNOPSIS
        Selects and mounts Windows 11 install image indexes (and optionally boot.wim and winre.wim).
    .EXAMPLE
        Select-TkSource -Index 6 -ServiceBoot -ServiceWinRE
    #>
    [CmdletBinding()]
    param(
        [int[]]$Index,
        [switch]$ServiceBoot,
        [switch]$ServiceWinRE,
        [switch]$Interactive
    )
    Initialize-TkDism
    $dp = Get-TkDismParameter
    $p = $script:TK.Paths
    if ($script:TK.Session.SourceSelected) { throw 'A source is already selected. Apply or discard it first (Apply menu).' }

    $sources = Join-Path $p.DVD 'sources'
    $installWim = Join-Path $sources 'install.wim'
    $bootWim = Join-Path $sources 'boot.wim'

    if (-not (Test-Path -LiteralPath $installWim)) {
        if (Test-Path -LiteralPath (Join-Path $sources 'install.esd')) {
            if ($Interactive -and -not (Confirm-TkAction 'The source contains install.esd. Convert it to install.wim now?' -Always -Default $true)) { return }
            Convert-TkInstallEsd
        }
        else {
            throw "No install.wim found in '$sources'. Import Windows 11 media first (Source menu)."
        }
    }
    Set-TkFileWritable -Path $installWim
    Set-TkFileWritable -Path $bootWim

    if (-not $Index) {
        if (-not $Interactive) { throw 'Please specify the image index(es) with -Index.' }
        $images = @(Get-WindowsImage -ImagePath $installWim @dp)
        Write-Host '  Available images in install.wim:' -ForegroundColor White
        Write-Host ''
        $selected = @(Read-TkSelection -Items $images -Label { param($i) '{0} (Index {1})' -f $i.ImageName, $i.ImageIndex })
        if ($selected.Count -eq 0) { return }
        $Index = @($selected | ForEach-Object { $_.ImageIndex })
        Write-Host ''
        $ServiceBoot = [switch](Confirm-TkAction 'Also service the setup boot image (boot.wim)?' -Always)
        $ServiceWinRE = [switch](Confirm-TkAction 'Also service the recovery image (winre.wim)?' -Always)
    }

    $infos = @(foreach ($i in $Index) { Get-TkImageInfo -ImagePath $installWim -Index $i })
    foreach ($info in $infos) {
        if (-not (Test-TkSupportedBuild -Build $info.Build)) {
            throw "Index $($info.Index) '$($info.Name)' is build $($info.Build). This toolkit supports Windows 11 (build 22000 and later) only."
        }
        if ($info.InstallationType -notmatch 'Client') {
            Write-TkLog "Index $($info.Index) is a '$($info.InstallationType)' image - the templates target Windows 11 client editions." -Level Warn
        }
    }
    if (@($infos | ForEach-Object { "$($_.Build)/$($_.Architecture)" } | Select-Object -Unique).Count -gt 1) {
        throw 'The selected indexes have different builds or architectures. Please select images of one build/architecture.'
    }

    $session = $script:TK.Session
    $session.SourceSelected = $true
    $session.InstallWim = $installWim
    $session.BootWim = if (Test-Path -LiteralPath $bootWim) { $bootWim } else { '' }
    $session.Indexes = @($Index)
    $session.ImageInfo = $infos[0]
    $session.ServiceBoot = [bool]$ServiceBoot -and [bool]$session.BootWim
    $session.ServiceWinRE = [bool]$ServiceWinRE
    $session.Images = @()
    Save-TkSession

    $winReStaged = $false
    try {
        foreach ($info in $infos) {
            $mountPath = Join-Path $p.MountInstall $info.Index
            $null = New-Item -Path $mountPath -ItemType Directory -Force
            Write-TkLog "Mounting install.wim index $($info.Index): $($info.Name)..." -Level Step
            Mount-WindowsImage -ImagePath $installWim -Index $info.Index -Path $mountPath @dp | Out-Null
            $session.Images += @{ Kind = 'Install'; Index = $info.Index; Path = $mountPath; ImageFile = $installWim; Name = $info.Name }
            Save-TkSession
            # Copy winre.wim while only ONE image is mounted: once further indexes of the same WIM
            # are mounted, WIM-backed files of the first mount can fail with "cannot access the file" (1920).
            if ($session.ServiceWinRE -and -not $winReStaged) {
                $winReStaged = Copy-TkStagedRecoveryImage -ImagePath $mountPath
                if (-not $winReStaged) { $session.ServiceWinRE = $false; Save-TkSession }
            }
        }

        if ($session.ServiceBoot) {
            foreach ($bootImage in @(Get-WindowsImage -ImagePath $bootWim @dp)) {
                $mountPath = Join-Path $p.MountBoot $bootImage.ImageIndex
                $null = New-Item -Path $mountPath -ItemType Directory -Force
                Write-TkLog "Mounting boot.wim index $($bootImage.ImageIndex): $($bootImage.ImageName)..." -Level Step
                Mount-WindowsImage -ImagePath $bootWim -Index $bootImage.ImageIndex -Path $mountPath @dp | Out-Null
                $session.Images += @{ Kind = 'Boot'; Index = $bootImage.ImageIndex; Path = $mountPath; ImageFile = $bootWim; Name = $bootImage.ImageName }
                Save-TkSession
            }
        }
        elseif ($ServiceBoot) {
            Write-TkLog 'boot.wim not found - the boot image will not be serviced.' -Level Warn
        }

        if ($session.ServiceWinRE -and $winReStaged) {
            $stage = Join-Path $p.WinReStage 'winre.wim'
            $null = New-Item -Path $p.MountWinRE -ItemType Directory -Force
            Write-TkLog 'Mounting recovery image (winre.wim)...' -Level Step
            Mount-WindowsImage -ImagePath $stage -Index 1 -Path $p.MountWinRE @dp | Out-Null
            $session.Images += @{ Kind = 'WinRE'; Index = 1; Path = $p.MountWinRE; ImageFile = $stage; Name = 'Windows Recovery Environment' }
            Save-TkSession
        }
    }
    catch {
        Write-TkLog "Mounting failed: $($_.Exception.Message)" -Level Error
        Write-TkLog 'Discarding already mounted images...' -Level Warn
        Undo-TkSource -Force
        throw
    }

    Save-TkSession
    $i = $session.ImageInfo
    Write-TkLog ("Source selected: Windows 11 {0} ({1}) {2} {3}, index {4}" -f $i.Release, $i.Version, $i.Architecture, $i.DefaultLanguage, ($session.Indexes -join ',')) -Level Success
}

function Copy-TkStagedRecoveryImage {
    <#
    .SYNOPSIS
        Copies winre.wim out of a mounted install image to Temp\WinRE for servicing.
    .OUTPUTS
        $true when the recovery image was staged, otherwise $false (servicing continues without WinRE).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$ImagePath)
    $p = $script:TK.Paths
    $source = Join-Path $ImagePath 'Windows\System32\Recovery\winre.wim'
    if (-not (Test-Path -LiteralPath $source)) {
        Write-TkLog 'The install image contains no winre.wim - the recovery image will not be serviced.' -Level Warn
        return $false
    }
    $stage = Join-Path $p.WinReStage 'winre.wim'
    $null = New-Item -Path $p.WinReStage -ItemType Directory -Force
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Force }
    Write-TkLog 'Copying recovery image (winre.wim) out of the install image...' -Level Step
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            [System.IO.File]::Copy($source, $stage, $true)
            (Get-Item -LiteralPath $stage -Force).Attributes = 'Normal'
            return $true
        }
        catch {
            $message = $_.Exception.GetBaseException().Message
            if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
        }
    }
    Write-TkLog "Could not copy winre.wim ($message) - continuing without servicing the recovery image." -Level Warn
    $false
}
