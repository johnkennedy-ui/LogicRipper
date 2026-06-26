#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status','guide','test','analyse','generate','api')]
    [string]$Command = 'status',
    [string]$BasePath,
    [string]$InputPath,
    [string]$OutputPath,
    [string]$TemplateId,
    [Alias('TargetWorkspaceProfileId')]
    [string]$ProfileId,
    [string]$BindingId,
    [string]$PayloadPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'LogicRipper' 'LogicRipper.psd1') -Force

function Write-JsonResult {
    param([Parameter(Mandatory)][object]$InputObject)
    $InputObject | ConvertTo-Json -Depth 100
}

function ConvertTo-Hashtable {
    param([object]$InputObject)
    $hash = @{}
    if ($null -eq $InputObject) { return $hash }
    foreach ($p in $InputObject.PSObject.Properties) { $hash[$p.Name] = $p.Value }
    $hash
}

function Read-Payload {
    if (-not $PayloadPath) { throw 'PayloadPath is required for api command.' }
    Get-Content -Raw -LiteralPath $PayloadPath | ConvertFrom-Json -Depth 100
}

function Invoke-LogicRipperApi {
    $payload = Read-Payload
    $action = [string]$payload.action
    $apiBasePath = if ($payload.basePath) { [string]$payload.basePath } else { $BasePath }

    switch ($action) {
        'analyse' {
            $json = if ($payload.inputPath) { Get-Content -Raw -LiteralPath ([string]$payload.inputPath) } else { [string]$payload.codeViewJson }
            Invoke-LogicRipperAnalysis -CodeViewJson $json
        }
        'setDecision' {
            $analysis = $payload.analysis
            Set-LogicRipperFindingDecision -Analysis $analysis -FindingId ([string]$payload.findingId) -Decision ([string]$payload.decision).ToLowerInvariant() -ReplacementName ([string]$payload.replacementName)
        }
        'saveTemplate' {
            Save-LogicRipperTemplate -BasePath $apiBasePath -Name ([string]$payload.name) -Purpose ([string]$payload.purpose) -Analysis $payload.analysis
        }
        'listTemplates' { @(Get-LogicRipperTemplate -BasePath $apiBasePath) }
        'getTemplate' { Get-LogicRipperTemplate -BasePath $apiBasePath -TemplateId ([string]$payload.templateId) }
        'renameTemplate' { Rename-LogicRipperTemplate -BasePath $apiBasePath -TemplateId ([string]$payload.templateId) -Name ([string]$payload.name) -Purpose ([string]$payload.purpose) }
        'deleteTemplate' { Remove-LogicRipperTemplate -BasePath $apiBasePath -TemplateId ([string]$payload.templateId) }
        'saveWorkspace' {
            Save-LogicRipperTargetWorkspace -BasePath $apiBasePath -ProfileId ([string]$payload.profileId) -DisplayName ([string]$payload.displayName) -Values (ConvertTo-Hashtable $payload.values)
        }
        'listWorkspaces' { @(Get-LogicRipperTargetWorkspace -BasePath $apiBasePath) }
        'getWorkspace' { Get-LogicRipperTargetWorkspace -BasePath $apiBasePath -ProfileId ([string]$payload.profileId) }
        'cloneWorkspace' { Copy-LogicRipperTargetWorkspace -BasePath $apiBasePath -ProfileId ([string]$payload.profileId) -DisplayName ([string]$payload.displayName) }
        'deleteWorkspace' { Remove-LogicRipperTargetWorkspace -BasePath $apiBasePath -ProfileId ([string]$payload.profileId) }
        'saveBinding' {
            Save-LogicRipperBinding -BasePath $apiBasePath -BindingId ([string]$payload.bindingId) -TemplateId ([string]$payload.templateId) -ProfileId ([string]$payload.profileId) -Values (ConvertTo-Hashtable $payload.values)
        }
        'listBindings' { @(Get-LogicRipperBinding -BasePath $apiBasePath -TemplateId ([string]$payload.templateId) -ProfileId ([string]$payload.profileId)) }
        'getBinding' { Get-LogicRipperBinding -BasePath $apiBasePath -BindingId ([string]$payload.bindingId) }
        'deleteBinding' { Remove-LogicRipperBinding -BasePath $apiBasePath -BindingId ([string]$payload.bindingId) }
        'generate' {
            New-LogicRipperCodeView -BasePath $apiBasePath -TemplateId ([string]$payload.templateId) -ProfileId ([string]$payload.profileId) -BindingId ([string]$payload.bindingId) -OutputPath ([string]$payload.outputPath)
        }
        default { throw "Unknown api action: $action" }
    }
}

switch ($Command) {
    'status' {
        Write-JsonResult ([ordered]@{
            module = 'LogicRipper'
            mode = 'local code-view transformer'
            root = Get-LogicRipperPath -Kind Root -BasePath $BasePath
            templates = @(Get-LogicRipperTemplate -BasePath $BasePath).Count
            targetWorkspaces = @(Get-LogicRipperTargetWorkspace -BasePath $BasePath).Count
            bindings = @(Get-LogicRipperBinding -BasePath $BasePath).Count
            outOfScope = @('live login','live discovery','deployment','ARM/Bicep','what-if','live API calls')
        })
    }
    'guide' { Write-JsonResult (Get-LogicRipperValueGuide) }
    'test' {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
        & (Join-Path $repoRoot 'build.ps1') -Test
    }
    'analyse' {
        if (-not $InputPath) { throw 'InputPath is required for analyse.' }
        $analysis = Invoke-LogicRipperAnalysis -Path $InputPath
        if ($OutputPath) {
            $analysis | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        }
        Write-JsonResult $analysis
    }
    'generate' {
        if (-not $TemplateId) { throw 'TemplateId is required for generate.' }
        if (-not $ProfileId) { throw 'ProfileId is required for generate.' }
        Write-JsonResult (New-LogicRipperCodeView -BasePath $BasePath -TemplateId $TemplateId -ProfileId $ProfileId -BindingId $BindingId -OutputPath $OutputPath)
    }
    'api' { Write-JsonResult (Invoke-LogicRipperApi) }
}
