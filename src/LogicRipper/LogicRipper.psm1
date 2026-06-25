Set-StrictMode -Version Latest

$script:SchemaVersion = '3.0'
$script:AllowedDecisions = @('replace','preserve','secret')
$script:KnownStableMicrosoftGuids = @(
    '00000003-0000-0000-c000-000000000000', # Microsoft Graph
    '797f4846-ba00-4fd7-ba43-dac1f8f63013', # Azure Service Management
    '1950a258-227b-4e31-a9cf-717495945fc2'  # Azure PowerShell
)

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

function ConvertTo-PlainObject {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    $json = $Value | ConvertTo-Json -Depth 100
    $json | ConvertFrom-Json -Depth 100
}

function Test-ObjectProperty {
    param([object]$Object, [string]$Name)
    $null -ne $Object -and $Object -is [pscustomobject] -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-ObjectPropertyValue {
    param([object]$Object, [string]$Name)
    if (Test-ObjectProperty -Object $Object -Name $Name) { return $Object.PSObject.Properties[$Name].Value }
    $null
}

function Get-LogicRipperCanonicalCodeView {
    [CmdletBinding(DefaultParameterSetName='Json')]
    param(
        [Parameter(Mandatory, ParameterSetName='Json')][string]$CodeViewJson,
        [Parameter(Mandatory, ParameterSetName='Object')][object]$InputObject
    )
    if ($PSCmdlet.ParameterSetName -eq 'Json') { $InputObject = $CodeViewJson | ConvertFrom-Json -Depth 100 }

    $sourceKind = 'pureCodeView'
    $sourceResourceId = $null
    $codeView = $InputObject

    if (Test-ObjectProperty -Object $InputObject -Name 'codeView') {
        $sourceKind = 'savedTemplate'
        $codeView = $InputObject.codeView
    } elseif ((Test-ObjectProperty -Object $InputObject -Name 'properties') -and (Test-ObjectProperty -Object $InputObject.properties -Name 'definition')) {
        $sourceKind = 'workflowResource'
        $sourceResourceId = Get-ObjectPropertyValue -Object $InputObject -Name 'id'
        $codeView = ConvertTo-PlainObject $InputObject.properties.definition
        if ((Test-ObjectProperty -Object $InputObject.properties -Name 'parameters') -and (Test-ObjectProperty -Object $InputObject.properties.parameters -Name '$connections')) {
            if (-not (Test-ObjectProperty -Object $codeView -Name 'parameters')) {
                $codeView | Add-Member -NotePropertyName 'parameters' -NotePropertyValue ([pscustomobject]@{})
            }
            if (-not (Test-ObjectProperty -Object $codeView.parameters -Name '$connections')) {
                $codeView.parameters | Add-Member -NotePropertyName '$connections' -NotePropertyValue ([pscustomobject]@{ type = 'Object' })
            }
            $connections = $InputObject.properties.parameters.PSObject.Properties['$connections'].Value
            if (Test-ObjectProperty -Object $connections -Name 'value') {
                $codeView.parameters.PSObject.Properties['$connections'].Value | Add-Member -NotePropertyName 'value' -NotePropertyValue $connections.value -Force
            }
        }
    }

    if (-not (Test-ObjectProperty -Object $codeView -Name 'triggers')) { throw 'Invalid code view: missing triggers.' }
    if (-not (Test-ObjectProperty -Object $codeView -Name 'actions')) { throw 'Invalid code view: missing actions.' }

    $normalisedJson = ConvertTo-StableJson $codeView
    [pscustomobject]@{
        schemaVersion = $script:SchemaVersion
        sourceKind = $sourceKind
        sourceResourceId = $sourceResourceId
        codeView = ($normalisedJson | ConvertFrom-Json -Depth 100)
        codeViewHash = Get-StableId $normalisedJson
    }
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

function Get-DetectedValueMatches {
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$Path)
    $rules = @(
        @{ kind = 'secret'; regex = '(?i)(sig=|code=|client[_-]?secret|password|AccountKey=|SharedAccessSignature|Bearer\s+[a-z0-9._~+/=-]+|sv=\d{4}-\d{2}-\d{2}&.*\bsig=)' },
        @{ kind = 'apiConnectionId'; regex = '/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\.Web/connections/[^/\s''")?]+' },
        @{ kind = 'managedIdentityId'; regex = '/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\.ManagedIdentity/userAssignedIdentities/[^/\s''")?]+' },
        @{ kind = 'azureResourceId'; regex = '/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/\s''")?]+(?:/providers/[^/\s''")?]+/[^/\s''")?]+/[^/\s''")?]+)+' },
        @{ kind = 'functionUrl'; regex = 'https://[A-Za-z0-9-]+\.azurewebsites\.net/[^\s''"]*' },
        @{ kind = 'keyVaultUrl'; regex = 'https://[A-Za-z0-9-]+\.vault\.azure\.net[^\s''"]*' },
        @{ kind = 'webhookUrl'; regex = 'https://[^\s''"]*(?:webhook|hooks|logic\.azure|workflows)[^\s''"]*' },
        @{ kind = 'email'; regex = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' },
        @{ kind = 'placeholder'; regex = '\{\{[A-Za-z][A-Za-z0-9_]*\}\}' },
        @{ kind = 'guid'; regex = '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b' },
        @{ kind = 'name'; regex = '\b(?:rg|law|la|kv|uami|func)-[A-Za-z0-9-]+\b' }
    )
    foreach ($rule in $rules) {
        foreach ($m in [regex]::Matches($Value, $rule.regex)) {
            $kind = $rule.kind
            $matchValue = $m.Value
            if ($kind -eq 'guid' -and $script:KnownStableMicrosoftGuids -contains $matchValue.ToLowerInvariant()) {
                [pscustomobject]@{ kind = 'stableMicrosoftGuid'; value = $matchValue; decision = 'preserve' }
                continue
            }
            if ($kind -eq 'placeholder') {
                $name = $matchValue.TrimStart('{').TrimEnd('}')
                [pscustomobject]@{ kind = 'placeholder'; value = $matchValue; decision = 'replace'; replacementName = $name }
                continue
            }
            [pscustomobject]@{ kind = $kind; value = $matchValue; decision = 'review' }
        }
    }

    if ($Path -like '*.parameters.$connections.defaultValue.*.connectionId' -or $Path -like '*.parameters.$connections.value.*.connectionId') {
        [pscustomobject]@{ kind = 'apiConnectionId'; value = $Value; decision = 'review' }
    }
    if ($Path -like '*.parameters.$connections.defaultValue.*.connectionName' -or $Path -like '*.parameters.$connections.value.*.connectionName') {
        [pscustomobject]@{ kind = 'apiConnectionName'; value = $Value; decision = 'review' }
    }
    if ($Path -like '*.parameters.$connections.defaultValue.*.id' -or $Path -like '*.parameters.$connections.value.*.id') {
        [pscustomobject]@{ kind = 'managedApiId'; value = $Value; decision = 'review' }
    }
}

function Get-ReplacementName {
    param([string]$Kind, [string]$Path, [string]$Value)
    if ($Value -match '^\{\{(?<name>[A-Za-z][A-Za-z0-9_]*)\}\}$') { return $Matches.name }
    switch ($Kind) {
        'guid' {
            if ($Path -match '(?i)tenant') { return 'tenantId' }
            if ($Path -match '(?i)subscription') { return 'subscriptionId' }
            'guid_' + (Get-StableId "$Path|$Value")
        }
        'email' { 'notificationEmail' }
        'apiConnectionId' { 'sentinelConnectionId' }
        'apiConnectionName' { 'sentinelConnectionName' }
        'managedApiId' { 'sentinelManagedApiId' }
        'keyVaultUrl' { 'keyVaultUri' }
        'functionUrl' { 'functionUrl' }
        'managedIdentityId' { 'runtimeIdentityResourceId' }
        default { (($Kind + '_' + (Get-StableId "$Path|$Value")).ToLowerInvariant()) }
    }
}

function Get-ValueGuideText {
    param([string]$Kind)
    switch ($Kind) {
        'apiConnectionId' { 'Target Logic App -> API connections -> open authorised connection -> Properties -> Resource ID.' }
        'apiConnectionName' { 'Use the target API connection resource name. If OAuth cannot be pre-mapped, mark manual reconnect required.' }
        'managedApiId' { 'Use the target region managed API ID, normally /subscriptions/<sub>/providers/Microsoft.Web/locations/<location>/managedApis/<connector>.' }
        'azureResourceId' { 'Azure Portal -> open target resource -> Properties -> Resource ID.' }
        'managedIdentityId' { 'Managed Identities -> select identity -> Properties -> Resource ID.' }
        'guid' { 'Review unknown GUID. Replace tenant/subscription/workspace/object IDs; preserve only known stable Microsoft IDs.' }
        'functionUrl' { 'Function App -> Functions -> selected function -> Get Function URL. Do not paste keys unless stored as a safe reference.' }
        'keyVaultUrl' { 'Key Vault -> Overview -> Vault URI.' }
        'webhookUrl' { 'Webhook URLs often contain secrets. Replace with a target endpoint or mark secret/do not export.' }
        'email' { 'Enter target customer notification mailbox, for example soc@contoso.example.' }
        'name' { 'Enter the target customer resource name.' }
        'placeholder' { 'Placeholder found in template. Enter the value once in the workspace or binding.' }
        'secret' { 'Do not export. Remove from template or replace with a safe Key Vault/Credential Manager reference.' }
        'stableMicrosoftGuid' { 'Known stable Microsoft application ID. Preserve unless you have a specific reason to replace it.' }
        default { 'Review before generation.' }
    }
}

function New-Finding {
    param([string]$Path, [string]$LeafValue, [object]$Match)
    $replacementName = if (Test-ObjectProperty -Object $Match -Name 'replacementName') { $Match.replacementName } else { Get-ReplacementName -Kind $Match.kind -Path $Path -Value $Match.value }
    [pscustomobject]@{
        id = Get-StableId "$Path|$($Match.value)|$($Match.kind)"
        path = $Path
        value = $Match.value
        leafValue = $LeafValue
        kind = $Match.kind
        decision = $Match.decision
        replacementName = $replacementName
        guide = Get-ValueGuideText -Kind $Match.kind
    }
}

function Invoke-LogicRipperAnalysis {
    [CmdletBinding(DefaultParameterSetName='Json')]
    param(
        [Parameter(Mandatory, ParameterSetName='Json')][string]$CodeViewJson,
        [Parameter(Mandatory, ParameterSetName='Path')][string]$Path
    )
    if ($PSCmdlet.ParameterSetName -eq 'Path') { $CodeViewJson = Get-Content -Raw -LiteralPath $Path }
    $canonical = Get-LogicRipperCanonicalCodeView -CodeViewJson $CodeViewJson
    $seen = @{}
    $findings = foreach ($leaf in Get-JsonLeaf $canonical.codeView) {
        if ([string]::IsNullOrWhiteSpace($leaf.value)) { continue }
        $acceptedValues = @()
        foreach ($match in @(Get-DetectedValueMatches -Value $leaf.value -Path $leaf.path) | Sort-Object { $_.value.Length } -Descending) {
            if (@($acceptedValues | Where-Object { $_.Contains($match.value) }).Count -gt 0) { continue }
            $key = "$($leaf.path)|$($match.value)|$($match.kind)"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $acceptedValues += $match.value
            New-Finding -Path $leaf.path -LeafValue $leaf.value -Match $match
        }
    }
    [pscustomobject]@{
        schemaVersion = $script:SchemaVersion
        analysedAt = (Get-Date).ToUniversalTime().ToString('o')
        sourceKind = $canonical.sourceKind
        sourceResourceId = $canonical.sourceResourceId
        codeViewHash = $canonical.codeViewHash
        codeView = $canonical.codeView
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
    $templateId = Get-StableId $Analysis.codeViewHash
    $template = [ordered]@{
        schemaVersion = $script:SchemaVersion
        templateId = $templateId
        name = $Name
        purpose = $Purpose
        savedAt = (Get-Date).ToUniversalTime().ToString('o')
        sourceKind = $Analysis.sourceKind
        sourceResourceId = $Analysis.sourceResourceId
        codeViewHash = $Analysis.codeViewHash
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

function Assert-NoRawSecret {
    param([string]$Json, [string]$Message)
    if ($Json -match '(?i)(client[_-]?secret|password|AccountKey=|SharedAccessSignature|Bearer\s+|sv=\d{4}-\d{2}-\d{2}&.*\bsig=)') { throw $Message }
}

function New-LogicRipperTargetWorkspace {
    [CmdletBinding()]
    param(
        [string]$BasePath,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][hashtable]$Values
    )
    Assert-NoRawSecret -Json (ConvertTo-StableJson $Values) -Message 'Workspace profiles cannot store raw secrets.'
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
    Assert-NoRawSecret -Json (ConvertTo-StableJson $Values) -Message 'Bindings cannot store raw secrets.'
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
    if ($Binding -and $Binding.values -and $Binding.values.PSObject.Properties[$Name]) { return $Binding.values.$Name }
    if ($Workspace -and $Workspace.values -and $Workspace.values.PSObject.Properties[$Name]) { return $Workspace.values.$Name }
    $null
}

function Get-JsonPathToken {
    param([string]$Path)
    $text = $Path.TrimStart('$').TrimStart('.')
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    $parts = New-Object System.Collections.Generic.List[string]
    $current = ''
    $bracketDepth = 0
    foreach ($ch in $text.ToCharArray()) {
        if ($ch -eq '[') { $bracketDepth++ }
        if ($ch -eq ']') { $bracketDepth-- }
        if ($ch -eq '.' -and $bracketDepth -eq 0) {
            $parts.Add($current)
            $current = ''
        } else {
            $current += $ch
        }
    }
    if ($current.Length -gt 0) { $parts.Add($current) }
    $parts
}

function Get-NodeByPath {
    param([object]$Node, [string]$Path)
    $target = $Node
    foreach ($part in Get-JsonPathToken -Path $Path) {
        if ($part -match '^(?<name>[^\[]+)\[(?<index>\d+)\]$') {
            $target = $target.PSObject.Properties[$Matches.name].Value[[int]$Matches.index]
        } else {
            $target = $target.PSObject.Properties[$part].Value
        }
    }
    $target
}

function Set-NodeByPath {
    param([object]$Node, [string]$Path, [object]$Value)
    $parts = @(Get-JsonPathToken -Path $Path)
    $target = $Node
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $part = $parts[$i]
        if ($part -match '^(?<name>[^\[]+)\[(?<index>\d+)\]$') {
            $target = $target.PSObject.Properties[$Matches.name].Value[[int]$Matches.index]
        } else {
            $target = $target.PSObject.Properties[$part].Value
        }
    }
    $last = $parts[-1]
    if ($last -match '^(?<name>[^\[]+)\[(?<index>\d+)\]$') {
        $target.PSObject.Properties[$Matches.name].Value[[int]$Matches.index] = $Value
    } else {
        $target.PSObject.Properties[$last].Value = $Value
    }
}

function Apply-CodeViewReplacement {
    param([object]$CodeView, [object]$Finding, [string]$NewValue)
    $current = Get-NodeByPath -Node $CodeView -Path $Finding.path
    if ($null -eq $current) { throw "Cannot replace missing JSON path $($Finding.path)" }
    $currentText = [string]$current
    if ($currentText -eq $Finding.value) {
        Set-NodeByPath -Node $CodeView -Path $Finding.path -Value $NewValue
        return
    }
    if ($currentText.Contains($Finding.value)) {
        Set-NodeByPath -Node $CodeView -Path $Finding.path -Value ($currentText.Replace($Finding.value, $NewValue))
        return
    }
    throw "Source value not found at JSON path $($Finding.path)"
}

function Test-ConnectionManualReconnect {
    param([object]$Template, [object]$Binding)
    $manual = @()
    foreach ($finding in @($Template.findings | Where-Object { $_.kind -in @('apiConnectionId','apiConnectionName','managedApiId') })) {
        $value = Resolve-ReplacementValue -Name $finding.replacementName -Workspace $null -Binding $Binding
        if ($value -eq 'Manual reconnect required') { $manual += $finding.path }
    }
    $manual
}

function Test-LogicRipperCodeView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$CodeView,
        [object]$Template,
        [object]$Binding
    )
    $json = ConvertTo-StableJson $CodeView
    $null = $json | ConvertFrom-Json -Depth 100
    if (-not (Test-ObjectProperty -Object $CodeView -Name 'triggers')) { throw 'Generated code view is missing triggers.' }
    if (-not (Test-ObjectProperty -Object $CodeView -Name 'actions')) { throw 'Generated code view is missing actions.' }
    if ($json -match '\{\{[A-Za-z][A-Za-z0-9_]*\}\}') { throw 'Generated code view contains unresolved placeholders.' }
    Assert-NoRawSecret -Json $json -Message 'Generated code view contains probable secrets.'
    if ($Template) {
        foreach ($finding in @($Template.findings | Where-Object decision -eq 'replace')) {
            if ($finding.kind -in @('apiConnectionId','apiConnectionName','managedApiId')) {
                $connectionValue = Resolve-ReplacementValue -Name $finding.replacementName -Workspace $null -Binding $Binding
                if ($connectionValue -eq 'Manual reconnect required') { continue }
            }
            if ($json.Contains([string]$finding.value)) { throw "Generated code view still contains source value at $($finding.path)" }
        }
        $connectionFindings = @($Template.findings | Where-Object { $_.kind -in @('apiConnectionId','apiConnectionName','managedApiId') -and $_.decision -eq 'replace' })
        foreach ($finding in $connectionFindings) {
            $value = Resolve-ReplacementValue -Name $finding.replacementName -Workspace $null -Binding $Binding
            if ($null -eq $value) { throw "Connection needs mapping or Manual reconnect required: $($finding.replacementName)" }
        }
    }
    [pscustomobject]@{ status = 'Valid code view'; manualReconnect = @(Test-ConnectionManualReconnect -Template $Template -Binding $Binding) }
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

    foreach ($finding in @($template.findings | Where-Object decision -eq 'secret')) {
        throw "Needs review: secret / do not export finding remains at $($finding.path)"
    }
    foreach ($finding in @($template.findings | Where-Object decision -eq 'replace')) {
        $value = Resolve-ReplacementValue -Name $finding.replacementName -Workspace $workspace -Binding $binding
        if ($null -eq $value) { throw "Needs review: missing value for $($finding.replacementName)" }
        if ($value -eq 'Manual reconnect required') { continue }
        Apply-CodeViewReplacement -CodeView $codeView -Finding $finding -NewValue ([string]$value)
    }

    $validation = Test-LogicRipperCodeView -CodeView $codeView -Template $template -Binding $binding
    if (-not $OutputPath) { $OutputPath = Get-LogicRipperPath -Kind Generated -BasePath $BasePath }
    $dir = Join-Path (Join-Path $OutputPath ($workspace.displayName -replace '[^A-Za-z0-9._-]+','-')) ($template.name -replace '[^A-Za-z0-9._-]+','-')
    $path = Join-Path $dir 'codeview.json'
    Write-AtomicJson -Path $path -InputObject $codeView
    [pscustomobject]@{ status = 'Generated'; path = $path; validation = $validation }
}

function Get-LogicRipperValueGuide {
    [CmdletBinding()]
    param()
    @(
        [pscustomobject]@{ value = 'Tenant ID'; storedIn = 'Workspace'; guide = 'Azure Portal -> Microsoft Entra ID -> Overview -> Tenant ID.' },
        [pscustomobject]@{ value = 'Subscription ID'; storedIn = 'Workspace'; guide = 'Azure Portal -> Subscriptions -> select subscription -> Overview -> Subscription ID.' },
        [pscustomobject]@{ value = 'Workspace resource ID'; storedIn = 'Workspace'; guide = 'Log Analytics workspace -> Properties -> Resource ID.' },
        [pscustomobject]@{ value = 'API connection ID'; storedIn = 'Binding'; guide = 'Target Logic App resource group -> API connections -> open authorised connection -> Properties -> Resource ID. For OAuth connectors, use Manual reconnect required if not pre-authorised.' },
        [pscustomobject]@{ value = 'Managed API ID'; storedIn = 'Binding'; guide = 'Use /subscriptions/<target-sub>/providers/Microsoft.Web/locations/<target-location>/managedApis/<connector>.' },
        [pscustomobject]@{ value = 'Managed identity object/principal ID'; storedIn = 'Workspace or Binding'; guide = 'Managed Identities -> selected identity -> Overview -> Object/principal ID.' },
        [pscustomobject]@{ value = 'Notification email'; storedIn = 'Binding'; guide = 'Use the target customer mailbox for this specific playbook.' }
    )
}

Export-ModuleMember -Function Get-LogicRipperPath,Get-LogicRipperCanonicalCodeView,Invoke-LogicRipperAnalysis,Set-LogicRipperFindingDecision,Save-LogicRipperTemplate,Get-LogicRipperTemplate,Rename-LogicRipperTemplate,New-LogicRipperTargetWorkspace,Get-LogicRipperTargetWorkspace,New-LogicRipperBinding,Get-LogicRipperBinding,New-LogicRipperCodeView,Test-LogicRipperCodeView,Get-LogicRipperValueGuide
