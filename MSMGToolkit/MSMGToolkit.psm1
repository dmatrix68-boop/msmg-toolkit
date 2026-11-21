# ---------------------------------------------------------------------------------------------
# MSMG Toolkit PS7 - module loader
# Unofficial PowerShell 7 rewrite of MSMG Toolkit 13.7 (c) 2013-2024 MSMG. See LICENSE.txt.
# ---------------------------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

$script:ModuleRoot = $PSScriptRoot
$script:ToolkitRoot = Split-Path -Parent $PSScriptRoot

foreach ($folder in 'Private', 'Public') {
    $path = Join-Path $PSScriptRoot $folder
    foreach ($file in Get-ChildItem -LiteralPath $path -Filter '*.ps1' -File | Sort-Object Name) {
        . $file.FullName
    }
}

Initialize-TkContext
if (Test-Path -LiteralPath $script:TK.Paths.SessionFile) { $null = Restore-TkSession }

$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'MSMGToolkit.psd1')
Export-ModuleMember -Function $manifest.FunctionsToExport
