#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Integration tests for the WIM file operations with both engines (wimlib and DISM).
# They create small test images and need Windows + administrator rights (GitHub's Windows
# runners provide both); otherwise they are skipped.

BeforeDiscovery {
    $canRun = $false
    if ($IsWindows) {
        $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        $canRun = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
}

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $root 'MSMGToolkit\MSMGToolkit.psd1') -Force
}

AfterAll {
    Remove-Module MSMGToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'WIM operations with engine <Engine>' -Tag 'Integration' -Skip:(-not $canRun) -ForEach @(
    @{ Engine = 'wimlib' }
    @{ Engine = 'dism' }
) {
    BeforeAll {
        InModuleScope MSMGToolkit -Parameters @{ E = $Engine } {
            $script:TK.Settings.WimEngine = $E
            $script:TK.Settings.ConfirmActions = $false
            $script:TK.Settings.ExportCompression = 'max'
        }
        $work = Join-Path $TestDrive $Engine
        $source = Join-Path $work 'source'
        $null = New-Item -Path (Join-Path $source 'Windows\System32\Recovery') -ItemType Directory -Force
        # Incompressible data so that splitting into 1 MB parts creates several parts
        $random = [System.Random]::new(42)
        foreach ($n in 1..3) {
            $bytes = [byte[]]::new(1MB)
            $random.NextBytes($bytes)
            [System.IO.File]::WriteAllBytes((Join-Path $source "data$n.bin"), $bytes)
        }
        Set-Content -LiteralPath (Join-Path $source 'Windows\System32\Recovery\winre.wim') -Value 'fake recovery image'
        $wim = Join-Path $work 'test.wim'

        function Get-Engine { InModuleScope MSMGToolkit { $script:TkLastWimEngine } }
        function Get-ImageNames([string]$Path) { @(Get-TkWimInfo -ImagePath $Path | Sort-Object ImageIndex | ForEach-Object { $_.ImageName }) -join '|' }
    }

    It 'uses the expected engine' {
        InModuleScope MSMGToolkit { [bool](Get-TkWimlibPath) } | Should -BeTrue
        InModuleScope MSMGToolkit { Test-TkWimlibEnabled } | Should -Be ($Engine -eq 'wimlib')
    }

    It 'captures a folder' {
        New-TkWimCapture -CapturePath $source -ImagePath $wim -Name 'First'
        Get-Engine | Should -Be $Engine
        Get-ImageNames $wim | Should -Be 'First'
    }

    It 'appends a second image' {
        New-TkWimCapture -CapturePath $source -ImagePath $wim -Name 'Second' -Append
        Get-Engine | Should -Be $Engine
        Get-ImageNames $wim | Should -Be 'First|Second'
    }

    It 'renames an index' {
        Rename-TkWimIndex -ImagePath $wim -Index 2 -NewName 'Renamed'
        Get-Engine | Should -Be $Engine
        Get-ImageNames $wim | Should -Be 'First|Renamed'
    }

    It 'extracts a single file' {
        $dest = Join-Path $work 'extract'
        $file = Export-TkFileFromWim -ImagePath $wim -Index 1 -FilePath 'Windows\System32\Recovery\winre.wim' -DestinationFolder $dest
        Get-Engine | Should -Be $Engine
        (Get-Content -LiteralPath $file -Raw).Trim() | Should -Be 'fake recovery image'
    }

    It 'exports to ESD and converts back to WIM' {
        $esd = Join-Path $work 'test.esd'
        $back = Join-Path $work 'back.wim'
        Export-TkWimIndex -SourceImagePath $wim -Index 1, 2 -DestinationImagePath $esd
        Get-Engine | Should -Be $Engine
        Get-ImageNames $esd | Should -Be 'First|Renamed'
        Convert-TkWim -SourceImagePath $esd -DestinationImagePath $back
        Get-ImageNames $back | Should -Be 'First|Renamed'
    }

    It 'splits and joins' {
        $swm = Join-Path $work 'split\test.swm'
        $null = New-Item -Path (Split-Path -Parent $swm) -ItemType Directory -Force
        Split-TkWim -ImagePath $wim -DestinationPath $swm -FileSizeMB 1
        Get-Engine | Should -Be $Engine
        @(Get-ChildItem -Path (Split-Path -Parent $swm) -Filter '*.swm').Count | Should -BeGreaterThan 1
        $joined = Join-Path $work 'joined.wim'
        Join-TkSwm -SwmPath $swm -DestinationImagePath $joined
        Get-Engine | Should -Be $Engine
        Get-ImageNames $joined | Should -Be 'First|Renamed'
    }

    It 'deletes an index' {
        Remove-TkWimIndex -ImagePath $wim -Index 1
        Get-Engine | Should -Be $Engine
        Get-ImageNames $wim | Should -Be 'Renamed'
    }

    It 'rebuilds the WIM' {
        Optimize-TkWim -ImagePath $wim
        Get-Engine | Should -Be $Engine
        Get-ImageNames $wim | Should -Be 'Renamed'
    }

    It 'applies an index' {
        $apply = Join-Path $work 'apply'
        Expand-TkWim -ImagePath $wim -Index 1 -ApplyPath $apply
        Get-Engine | Should -Be $Engine
        (Get-Item -LiteralPath (Join-Path $apply 'data2.bin')).Length | Should -Be 1MB
    }
}
