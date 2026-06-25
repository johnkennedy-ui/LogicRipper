#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status','guide','test')]
    [string]$Command = 'status',
    [string]$BasePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'LogicRipper' 'LogicRipper.psd1') -Force

switch ($Command) {
    'status' {
        [ordered]@{
            module = 'LogicRipper'
            mode = 'local code-view transformer'
            root = Get-LogicRipperPath -Kind Root -BasePath $BasePath
            templates = @(Get-LogicRipperTemplate -BasePath $BasePath).Count
            targetWorkspaces = @(Get-LogicRipperTargetWorkspace -BasePath $BasePath).Count
            bindings = @(Get-LogicRipperBinding -BasePath $BasePath).Count
            outOfScope = @('live login','live discovery','deployment','ARM/Bicep','what-if','live API calls')
        } | ConvertTo-Json -Depth 8
    }
    'guide' {
        Get-LogicRipperValueGuide | ConvertTo-Json -Depth 8
    }
    'test' {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
        & (Join-Path $repoRoot 'build.ps1') -Test
    }
}
