#Requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$Test,
    [switch]$Zip,
    [switch]$Gui,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'artifacts')
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion -lt [version]'7.4') { throw 'PowerShell 7.4 or later is required.' }

if ($Test) {
    & (Join-Path $PSScriptRoot 'tests/Run-LogicRipperTests.ps1')
}

if ($Zip) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    if ($Gui) {
        & (Join-Path $PSScriptRoot 'scripts/build-ubuntu-gui.sh')
    }
    $zipPath = Join-Path $OutputPath 'LogicRipper-mvp.zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    $zipSource = Join-Path $OutputPath 'LogicRipper-mvp'
    if (Test-Path $zipSource) { Remove-Item $zipSource -Recurse -Force }
    New-Item -ItemType Directory -Path $zipSource -Force | Out-Null
    foreach ($dir in @('src','scripts','docs')) {
        $sourcePath = Join-Path $PSScriptRoot $dir
        if (Test-Path -LiteralPath $sourcePath) {
            Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $zipSource $dir) -Recurse
            Get-ChildItem -LiteralPath (Join-Path $zipSource $dir) -Recurse -Directory |
                Where-Object { $_.Name -in @('bin','obj') } |
                Remove-Item -Recurse -Force
        }
    }
    foreach ($file in @('README.md','LICENSE','LogicRipper.sln')) {
        $sourcePath = Join-Path $PSScriptRoot $file
        if (Test-Path -LiteralPath $sourcePath) {
            Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $zipSource $file)
        }
    }
    Compress-Archive -Path (Join-Path $zipSource '*') -DestinationPath $zipPath
    Remove-Item $zipSource -Recurse -Force
    $zipPath
}
