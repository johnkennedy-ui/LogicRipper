#Requires -Version 7.4
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status','rip','workspace','bind','guide','export-codeview','generate','test')]
    [string]$Command = 'status',

    [string]$BasePath,
    [string]$WorkflowPath,
    [string]$TemplateId,
    [string]$TargetWorkspaceProfileId,
    [string]$BindingId,
    [string]$OutputPath,
    [switch]$Zip
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'LogicRipper' 'LogicRipper.psd1') -Force

switch ($Command) {
    'status' {
        [ordered]@{
            module = 'LogicRipper'
            root = Get-LogicRipperPath -Kind Root -BasePath $BasePath
            library = Get-LogicRipperPath -Kind Library -BasePath $BasePath
            workspaces = Get-LogicRipperPath -Kind Workspaces -BasePath $BasePath
            bindings = Get-LogicRipperPath -Kind Bindings -BasePath $BasePath
            generated = Get-LogicRipperPath -Kind Generated -BasePath $BasePath
            templates = @(Get-LogicRipperTemplate -BasePath $BasePath).Count
            targetWorkspaces = @(Get-LogicRipperTargetWorkspace -BasePath $BasePath).Count
            bindingsCount = @(Get-LogicRipperTemplateBinding -BasePath $BasePath).Count
        } | ConvertTo-Json -Depth 8
    }
    'rip' {
        if (-not $WorkflowPath) { throw 'Use -WorkflowPath <workflow.json>.' }
        Import-LogicRipperWorkflow -WorkflowPath $WorkflowPath -BasePath $BasePath | ConvertTo-Json -Depth 20
    }
    'workspace' {
        Get-LogicRipperTargetWorkspace -BasePath $BasePath | ConvertTo-Json -Depth 20
    }
    'bind' {
        Get-LogicRipperTemplateBinding -BasePath $BasePath -TemplateId $TemplateId -TargetWorkspaceProfileId $TargetWorkspaceProfileId | ConvertTo-Json -Depth 20
    }
    'guide' {
        Get-LogicRipperRequiredValueGuide -BasePath $BasePath -TemplateId $TemplateId | ConvertTo-Json -Depth 20
    }
    'generate' {
        if (-not $TemplateId -or -not $TargetWorkspaceProfileId) { throw 'Use -TemplateId and -TargetWorkspaceProfileId.' }
        New-LogicRipperPackage -TemplateId $TemplateId -TargetWorkspaceProfileId $TargetWorkspaceProfileId -BindingId $BindingId -BasePath $BasePath -OutputPath $OutputPath -Zip:$Zip | ConvertTo-Json -Depth 20
    }
    'export-codeview' {
        if (-not $TemplateId -or -not $TargetWorkspaceProfileId) { throw 'Use -TemplateId and -TargetWorkspaceProfileId.' }
        Export-LogicRipperCodeView -TemplateId $TemplateId -TargetWorkspaceProfileId $TargetWorkspaceProfileId -BindingId $BindingId -BasePath $BasePath -OutputPath $OutputPath | ConvertTo-Json -Depth 20
    }
    'test' {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
        & (Join-Path $repoRoot 'build.ps1') -Test
    }
}
