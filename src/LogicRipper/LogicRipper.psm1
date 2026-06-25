Set-StrictMode -Version Latest

$script:SchemaVersion = '2.0'
$script:AllowedDecisions = @('replace','preserve','secret')

function ConvertFrom-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
}

function ConvertTo-StableJson {
    param([Parameter(Mandatory)][object]$InputObject)
    $InputObject | ConvertTo-Json -Depth 100
}

function Write-AtomicJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$InputObject)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = Join-Path $dir ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('n') + '.tmp')
    $json = ConvertTo-StableJson $InputObject
    [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
    try {
        $null = $json | ConvertFrom-Json -Depth 100
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        throw
    }
}

function Get-LogicRipperPath {
    [CmdletBinding()]
    param(
        [ValidateSet('Root','Templates','Workspaces','Bindings','Generated')]
        [string]$Kind = 'Root',
        [string]$BasePath
    )
    if (-not $BasePath) {
        $local = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($local)) { $local = Join-Path $HOME '.local/share' }
        $BasePath = Join-Path $local 'LogicRipper'
    }
    switch ($Kind) {
        'Root' { $BasePath }
        'Templates' { Join-Path $BasePath 'Templates' }
        'Workspaces' { Join-Path $BasePath 'Workspaces' }
        'Bindings' { Join-Path $BasePath 'Bindings' }
        'Generated' { Join-Path $BasePath 'Generated' }
    }
}

function Get-StableId {
    param([Parameter(Mandatory)][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0,16)
}

function Get-JsonLeaf {
    param([Parameter(Mandatory)][object]$Node, [string]$Path = '$')
    if ($null -eq $Node) { return }
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string] -and $Node -isnot [pscustomobject]) {
        $i = 0
        foreach ($v in $Node) { Get-JsonLeaf -Node $v -Path "$Path[$i]"; $i++ }
    } elseif ($Node -is [pscustomobject]) {
        foreach ($p in $Node.PSObject.Properties) { Get-JsonLeaf -Node $p.Value -Path "$Path.$($p.Name)" }
    } else {
        [pscustomobject]@{ path = $Path; value = [string]$Node }
    }
}

function Get-DetectedValueKind {
    param([string]$Value)
    if ($Value -match '(?i)(sig=|code=|client[_-]?secret|password|AccountKey=|Bearer\s+[a-z0-9._~+/=-]+)') { return 'secret' }
    if ($Value -match '^/subscriptions/[^/]+/') { return 'azureResourceId' }
    if ($Value -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return 'guid' }
    if ($Value -match '^https://') { return 'url' }
    if ($Value -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return 'email' }
    if ($Value -match '^(rg-|law-|la-|kv-|uami-|func-)[A-Za-z0-9-]+$') { return 'name' }
    $null
}

function New-Finding {
    param([string]$Path, [string]$Value, [string]$Kind)
    [pscustomobject]@{
        id = Get-StableId "$Path|$Value"
        path = $Path
        value = $Value
        kind = $Kind
        decision = 'review'
        replacementName = (($Kind + '_' + (Get-StableId "$Path|$Value")).ToLowerInvariant())
        guide = Get-ValueGuideText -Kind $Kind
    }
}

function Get-ValueGuideText {
    param([string]$Kind)
    switch ($Kind) {
        'azureResourceId' { 'Azure Portal -> open resource -> Properties -> Resource ID. Replace for customer-specific resources.' }
        'guid' { 'Check whether this is tenant/subscription/workspace/object ID. Preserve only global functional IDs.' }
        'url' { 'Replace customer-specific URLs. Preserve Microsoft Graph and public Microsoft endpoints when they are part of the workflow contract.' }
        'email' { 'Replace customer-specific mailboxes such as SOC notification addresses.' }
        'name' { 'Replace customer-specific resource names such as rg, law, kv, uami, la or func names.' }
        'secret' { 'Do not export. Use Key Vault, Credential Manager or a post-import manual authorisation step.' }
        default { 'Review before generation.' }
    }
}

function Invoke-LogicRipperAnalysis {
    [CmdletBinding(DefaultParameterSetName='Json')]
    param(
        [Parameter(Mandatory, ParameterSetName='Json')][string]$CodeViewJson,
        [Parameter(Mandatory, ParameterSetName='Path')][string]$Path
    )
    if ($PSCmdlet.ParameterSetName -eq 'Path') { $CodeViewJson = Get-Content -Raw -LiteralPath $Path }
    $definition = $CodeViewJson | ConvertFrom-Json -Depth 100
    $findings = foreach ($leaf in Get-JsonLeaf $definition) {
        if ([string]::IsNullOrWhiteSpace($leaf.value)) { continue }
        $kind = Get-DetectedValueKind $leaf.value
        if ($kind) { New-Finding -Path $leaf.path -Value $leaf.value -Kind $kind }
    }
    [pscustomobject]@{
        schemaVersion = $script:SchemaVersion
        analysedAt = (Get-Date).ToUniversalTime().ToString('o')
        codeView = $definition
        findings = @($findings)
        status = if (@($findings | Where-Object decision -eq 'review').Count -gt 0) { 'Needs review' } else { 'Ready' }
    }
}

function Set-LogicRipperFindingDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Analysis,
        [Parameter(Mandatory)][string]$FindingId,
        [Parameter(Mandatory)][ValidateSet('replace','preserve','secret')][string]$Decision,
        [string]$ReplacementName
    )
    $finding = $Analysis.findings | Where-Object id -eq $FindingId | Select-Object -First 1
    if (-not $finding) { throw "Finding not found: $FindingId" }
    $finding.decision = $Decision
    if ($ReplacementName) { $finding.replacementName = $ReplacementName }
    $Analysis.status = if (@($Analysis.findings | Where-Object decision -eq 'review').Count -gt 0) { 'Needs review' } else { 'Ready' }
    $Analysis
}

function Assert-ReviewedFindings {
    param([object[]]$Findings)
    $unreviewed = @($Findings | Where-Object { $_.decision -notin $script:AllowedDecisions })
    if ($unreviewed.Count -gt 0) { throw "Needs review: $($unreviewed[0].path)" }
}

function Save-LogicRipperTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Analysis,
        [string]$Purpose = '',
        [string]$BasePath
    )
    Assert-ReviewedFindings $Analysis.findings
    if (@($Analysis.findings | Where-Object decision -eq 'secret').Count -gt 0) {
        throw 'Template contains values marked secret / do not export. Remove or replace them before saving.'
    }
    $templateId = Get-StableId $Name
    $template = [ordered]@{
        schemaVersion = $script:SchemaVersion
        templateId = $templateId
        name = $Name
        purpose = $Purpose
        savedAt = (Get-Date).ToUniversalTime().ToString('o')
        codeView = $Analysis.codeView
        findings = @($Analysis.findings)
    }
    $path = Join-Path (Get-LogicRipperPath -Kind Templates -BasePath $BasePath) "$templateId.json"
    Write-AtomicJson -Path $path -InputObject $template
    [pscustomobject]@{ templateId = $templateId; path = $path; name = $Name }
}

function Get-LogicRipperTemplate {
    [CmdletBinding()]
    param([string]$TemplateId, [string]$BasePath)
    $root = Get-LogicRipperPath -Kind Templates -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $files = if ($TemplateId) { @(Join-Path $root "$TemplateId.json") } else { @(Get-ChildItem -LiteralPath $root -Filter '*.json' | Select-Object -ExpandProperty FullName) }
    foreach ($file in $files) { if (Test-Path -LiteralPath $file) { ConvertFrom-JsonFile $file } }
}

function Rename-LogicRipperTemplate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TemplateId, [Parameter(Mandatory)][string]$Name, [string]$Purpose, [string]$BasePath)
    $path = Join-Path (Get-LogicRipperPath -Kind Templates -BasePath $BasePath) "$TemplateId.json"
    if (-not (Test-Path -LiteralPath $path)) { throw "Template not found: $TemplateId" }
    $template = ConvertFrom-JsonFile $path
    $template.name = $Name
    if ($PSBoundParameters.ContainsKey('Purpose')) { $template.purpose = $Purpose }
    Write-AtomicJson -Path $path -InputObject $template
    [pscustomobject]@{ status = 'Renamed'; templateId = $TemplateId; name = $Name }
}

function New-LogicRipperTargetWorkspace {
    [CmdletBinding()]
    param(
        [string]$BasePath,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][hashtable]$Values
    )
    $json = ConvertTo-StableJson $Values
    if ($json -match '(?i)(client[_-]?secret|password|AccountKey=|Bearer\s+)') { throw 'Workspace profiles cannot store raw secrets.' }
    $profileId = Get-StableId $DisplayName
    $profile = [ordered]@{ schemaVersion = $script:SchemaVersion; profileId = $profileId; displayName = $DisplayName; values = $Values; savedAt = (Get-Date).ToUniversalTime().ToString('o') }
    $path = Join-Path (Get-LogicRipperPath -Kind Workspaces -BasePath $BasePath) "$profileId.json"
    Write-AtomicJson -Path $path -InputObject $profile
    [pscustomobject]@{ profileId = $profileId; path = $path; displayName = $DisplayName }
}

function Get-LogicRipperTargetWorkspace {
    [CmdletBinding()]
    param([string]$ProfileId, [string]$BasePath)
    $root = Get-LogicRipperPath -Kind Workspaces -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $files = if ($ProfileId) { @(Join-Path $root "$ProfileId.json") } else { @(Get-ChildItem -LiteralPath $root -Filter '*.json' | Select-Object -ExpandProperty FullName) }
    foreach ($file in $files) { if (Test-Path -LiteralPath $file) { ConvertFrom-JsonFile $file } }
}

function New-LogicRipperBinding {
    [CmdletBinding()]
    param(
        [string]$BasePath,
        [Parameter(Mandatory)][string]$TemplateId,
        [Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][hashtable]$Values
    )
    $json = ConvertTo-StableJson $Values
    if ($json -match '(?i)(client[_-]?secret|password|AccountKey=|Bearer\s+)') { throw 'Bindings cannot store raw secrets.' }
    $bindingId = Get-StableId "$TemplateId|$ProfileId"
    $binding = [ordered]@{ schemaVersion = $script:SchemaVersion; bindingId = $bindingId; templateId = $TemplateId; profileId = $ProfileId; values = $Values; savedAt = (Get-Date).ToUniversalTime().ToString('o') }
    $path = Join-Path (Get-LogicRipperPath -Kind Bindings -BasePath $BasePath) "$bindingId.json"
    Write-AtomicJson -Path $path -InputObject $binding
    [pscustomobject]@{ bindingId = $bindingId; path = $path }
}

function Get-LogicRipperBinding {
    [CmdletBinding()]
    param([string]$BindingId, [string]$TemplateId, [string]$ProfileId, [string]$BasePath)
    $root = Get-LogicRipperPath -Kind Bindings -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $items = foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.json') { ConvertFrom-JsonFile $file.FullName }
    if ($BindingId) { $items = $items | Where-Object bindingId -eq $BindingId }
    if ($TemplateId) { $items = $items | Where-Object templateId -eq $TemplateId }
    if ($ProfileId) { $items = $items | Where-Object profileId -eq $ProfileId }
    $items
}

function Resolve-ReplacementValue {
    param([string]$Name, [object]$Workspace, [object]$Binding)
    if ($Binding.values.PSObject.Properties[$Name]) { return $Binding.values.$Name }
    if ($Workspace.values.PSObject.Properties[$Name]) { return $Workspace.values.$Name }
    $null
}

function Replace-CodeViewValue {
    param([object]$Node, [object]$Finding, [string]$NewValue)
    $parts = $Finding.path.TrimStart('$').TrimStart('.').Split('.')
    $target = $Node
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $part = $parts[$i]
        if ($part -match '^(?<name>[^\[]+)\[(?<index>\d+)\]$') {
            $target = $target.$($Matches.name)[$Matches.index]
        } else {
            $target = $target.$part
        }
    }
    $last = $parts[-1]
    if ($last -match '^(?<name>[^\[]+)\[(?<index>\d+)\]$') {
        $target.$($Matches.name)[$Matches.index] = $NewValue
    } else {
        $target.$last = $NewValue
    }
}

function New-LogicRipperCodeView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TemplateId,
        [Parameter(Mandatory)][string]$ProfileId,
        [string]$BindingId,
        [string]$BasePath,
        [string]$OutputPath
    )
    $template = Get-LogicRipperTemplate -TemplateId $TemplateId -BasePath $BasePath
    $workspace = Get-LogicRipperTargetWorkspace -ProfileId $ProfileId -BasePath $BasePath
    $binding = if ($BindingId) { Get-LogicRipperBinding -BindingId $BindingId -BasePath $BasePath } else { Get-LogicRipperBinding -TemplateId $TemplateId -ProfileId $ProfileId -BasePath $BasePath | Select-Object -First 1 }
    if (-not $template) { throw "Template not found: $TemplateId" }
    if (-not $workspace) { throw "Workspace not found: $ProfileId" }
    if (-not $binding) { throw "Binding not found for template and workspace." }
    $codeView = ConvertTo-StableJson $template.codeView | ConvertFrom-Json -Depth 100
    foreach ($finding in @($template.findings | Where-Object decision -eq 'replace')) {
        $value = Resolve-ReplacementValue -Name $finding.replacementName -Workspace $workspace -Binding $binding
        if ($null -eq $value) { throw "Needs review: missing value for $($finding.replacementName)" }
        Replace-CodeViewValue -Node $codeView -Finding $finding -NewValue ([string]$value)
    }
    foreach ($finding in @($template.findings | Where-Object decision -eq 'secret')) {
        throw "Needs review: secret finding remains at $($finding.path)"
    }
    if (-not $OutputPath) { $OutputPath = Get-LogicRipperPath -Kind Generated -BasePath $BasePath }
    $dir = Join-Path (Join-Path $OutputPath ($workspace.displayName -replace '[^A-Za-z0-9._-]+','-')) ($template.name -replace '[^A-Za-z0-9._-]+','-')
    $path = Join-Path $dir 'codeview.json'
    Write-AtomicJson -Path $path -InputObject $codeView
    [pscustomobject]@{ status = 'Generated'; path = $path }
}

function Get-LogicRipperValueGuide {
    [CmdletBinding()]
    param()
    @(
        [pscustomobject]@{ value = 'Tenant ID'; storedIn = 'Workspace'; guide = 'Azure Portal -> Microsoft Entra ID -> Overview -> Tenant ID.' },
        [pscustomobject]@{ value = 'Subscription ID'; storedIn = 'Workspace'; guide = 'Azure Portal -> Subscriptions -> select subscription -> Overview -> Subscription ID.' },
        [pscustomobject]@{ value = 'Workspace resource ID'; storedIn = 'Workspace'; guide = 'Log Analytics workspace -> Properties -> Resource ID.' },
        [pscustomobject]@{ value = 'Managed identity client ID'; storedIn = 'Workspace or Binding'; guide = 'Managed Identities -> select identity -> Overview -> Client ID.' },
        [pscustomobject]@{ value = 'Managed identity object/principal ID'; storedIn = 'Workspace or Binding'; guide = 'Managed Identities -> select identity -> Overview -> Object/principal ID.' },
        [pscustomobject]@{ value = 'Template-specific values'; storedIn = 'Binding'; guide = 'The form prompts for one missing value at a time after a template and workspace are selected.' }
    )
}

Export-ModuleMember -Function Get-LogicRipperPath,Invoke-LogicRipperAnalysis,Set-LogicRipperFindingDecision,Save-LogicRipperTemplate,Get-LogicRipperTemplate,Rename-LogicRipperTemplate,New-LogicRipperTargetWorkspace,Get-LogicRipperTargetWorkspace,New-LogicRipperBinding,Get-LogicRipperBinding,New-LogicRipperCodeView,Get-LogicRipperValueGuide
