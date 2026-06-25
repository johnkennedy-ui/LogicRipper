#Requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$Test,
    [switch]$Zip,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'artifacts')
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion -lt [version]'7.4') { throw 'PowerShell 7.4 or later is required.' }

if ($Test) {
    Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
    Invoke-Pester -Path (Join-Path $PSScriptRoot 'tests') -CI
}

if ($Zip) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $zipPath = Join-Path $OutputPath 'LogicRipper-mvp.zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path @(
        (Join-Path $PSScriptRoot 'src'),
        (Join-Path $PSScriptRoot 'scripts'),
        (Join-Path $PSScriptRoot 'docs'),
        (Join-Path $PSScriptRoot 'README.md'),
        (Join-Path $PSScriptRoot 'LICENSE')
    ) -DestinationPath $zipPath
    $zipPath
}
