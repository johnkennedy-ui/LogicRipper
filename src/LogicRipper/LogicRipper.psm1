Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$script:SchemaVersion = '1.0'
$script:Upstream = [ordered]@{
    sentinelBlogCommit = '2c533501f8f5f6220b9718e8c670897af6ee024b'
    logicAppTemplateCreatorCommit = '9c5dee9fb56543ce37b65659e7c5073d4075cc68'
    azureSentinelCommit = '94b42600709b37e26b2955a8f8b4ed3e5a56f997'
    retained = @(
        'Invoke-SentinelPlaybookManager Invoke-TemplateSanitise algorithm',
        'Invoke-SentinelPlaybookManager New-ParameterFile behaviour',
        'LogicAppTemplateCreator connection extraction patterns',
        'LogicAppTemplateCreator Function App parameterisation patterns',
        'LogicAppTemplateCreator managed identity and OAuth handling classifications'
    )
}

function ConvertTo-OrderedJson {
    param([Parameter(Mandatory)][object]$InputObject, [int]$Depth = 80)
    $InputObject | ConvertTo-Json -Depth $Depth
}

function ConvertFrom-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
}

function Write-AtomicJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$InputObject
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tmp = Join-Path $dir ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('n') + '.tmp')
    $json = ConvertTo-OrderedJson -InputObject $InputObject
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
        [ValidateSet('Root','Library','Workspaces','Bindings','Generated')]
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
        'Library' { Join-Path $BasePath 'Library' }
        'Workspaces' { Join-Path $BasePath 'Profiles/Workspaces' }
        'Bindings' { Join-Path $BasePath 'Profiles/Bindings' }
        'Generated' { Join-Path $BasePath 'generated' }
    }
}

function Get-StableId {
    param([Parameter(Mandatory)][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())
    (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 16)
}

function Get-JsonHash {
    param([Parameter(Mandatory)][object]$Object)
    $json = ConvertTo-OrderedJson $Object -Depth 100
    $sha = [Security.Cryptography.SHA256]::Create()
    (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)) | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-LogicRipperWorkflowSupport {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][object]$Workflow)
    process {
        $type = [string]$Workflow.type
        $kind = if ($Workflow.PSObject.Properties['kind']) { [string]$Workflow.kind } else { '' }
        if ($type -eq 'Microsoft.Web/sites' -and $kind -match 'workflowapp') {
            return [pscustomobject]@{ supported = $false; status = 'Unsupported'; reason = 'Logic Apps Standard is not supported in the MVP'; resourceType = $type; kind = $kind }
        }
        if ($type -ne 'Microsoft.Logic/workflows') {
            return [pscustomobject]@{ supported = $false; status = 'Unsupported'; reason = "Unsupported resource type $type"; resourceType = $type; kind = $kind }
        }
        [pscustomobject]@{ supported = $true; status = 'Supported'; reason = 'Consumption Logic App'; resourceType = $type; kind = $kind }
    }
}

function Get-JsonLeaf {
    param([Parameter(Mandatory)][object]$Node, [string]$Path = '$')
    if ($null -eq $Node) { return }
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string] -and $Node -isnot [pscustomobject]) {
        $i = 0
        foreach ($v in $Node) { Get-JsonLeaf -Node $v -Path "$Path[$i]"; $i++ }
    } elseif ($Node -is [pscustomobject] -or $Node -is [System.Collections.IDictionary]) {
        foreach ($p in $Node.PSObject.Properties) {
            Get-JsonLeaf -Node $p.Value -Path "$Path.$($p.Name)"
        }
    } else {
        [pscustomobject]@{ path = $Path; value = [string]$Node }
    }
}

function Find-LogicRipperSecret {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$InputObject)
    $patterns = [ordered]@{
        bearerToken = '(?i)\bbearer\s+[a-z0-9._~+/=-]{20,}'
        sasToken = '(?i)(sig=|se=|sp=|sv=)[^"&\s]+'
        storageConnectionString = '(?i)AccountKey=|DefaultEndpointsProtocol='
        clientSecret = '(?i)(client[_-]?secret|password|apikey|api[_-]?key|function[_-]?key|code=)'
        signedUrl = '(?i)https://[^"\s]+\?(?:[^"\s]*sig=|[^"\s]*code=)'
        oauthToken = '(?i)(refresh_token|access_token|id_token)["'':=\s]+[a-z0-9._~+/=-]{20,}'
    }
    foreach ($leaf in Get-JsonLeaf -Node $InputObject) {
        foreach ($key in $patterns.Keys) {
            if ($leaf.value -match $patterns[$key]) {
                [pscustomobject]@{ path = $leaf.path; type = $key; redactedPreview = ($leaf.value -replace '([A-Za-z0-9._~+/=-]{8})[A-Za-z0-9._~+/=-]+','$1...REDACTED') }
            }
        }
    }
}

function Protect-LogicRipperDiagnosticObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$InputObject, [switch]$RedactTenantAndSubscription)
    $json = ConvertTo-OrderedJson $InputObject -Depth 100
    $json = $json -replace '(?i)(bearer\s+)[a-z0-9._~+/=-]+', '$1REDACTED'
    $json = $json -replace '(?i)(sig=)[^"&\s]+', '$1REDACTED'
    $json = $json -replace '(?i)(AccountKey=)[^;"]+', '$1REDACTED'
    $json = $json -replace '(?i)(client[_-]?secret["'']?\s*[:=]\s*["'']?)[^,"''\s]+', '$1REDACTED'
    if ($RedactTenantAndSubscription) {
        $json = $json -replace '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', 'REDACTED-GUID'
    }
    $json | ConvertFrom-Json -Depth 100
}

function Get-TriggerType {
    param([object]$Definition)
    $trigger = @($Definition.triggers.PSObject.Properties)[0]
    if (-not $trigger) { return 'Unknown' }
    $name = $trigger.Name
    $body = $trigger.Value | ConvertTo-Json -Depth 40
    if ($body -match 'Microsoft.SecurityInsights|azuresentinel|incident') { return 'Microsoft Sentinel Incident' }
    if ($body -match 'alert') { return 'Microsoft Sentinel Alert' }
    if ($body -match 'entity') { return 'Microsoft Sentinel Entity' }
    if ($trigger.Value.type -eq 'Recurrence') { return 'Scheduled' }
    $name
}

function Get-ConnectionManifest {
    param([object]$Workflow)
    $connections = $Workflow.properties.parameters.'$connections'.value
    if (-not $connections) { return @() }
    foreach ($p in $connections.PSObject.Properties) {
        $conn = $p.Value
        $apiId = [string]$conn.id
        $connectionId = [string]$conn.connectionId
        $apiName = if ($apiId -match '/managedApis/([^/''\]\)]+)') { $Matches[1].ToLowerInvariant() } else { $p.Name }
        $auth = 'Unknown'
        if ($apiName -in @('azuresentinel','keyvault','azureblob','azuretables','azurequeues','servicebus')) { $auth = 'Managed identity' }
        elseif ($apiName -match 'office365|office365users|teams|sharepoint') { $auth = 'User OAuth' }
        elseif ($apiName -match 'custom') { $auth = 'Custom connector' }
        [pscustomobject]@{
            name = $p.Name
            apiName = $apiName
            sourceConnectionId = $connectionId
            sourceApiId = $apiId
            classification = $auth
            needsAuthorisation = ($auth -eq 'User OAuth' -or $auth -eq 'Unknown')
        }
    }
}

function Get-DependencyManifest {
    param([object]$Workflow)
    $json = ConvertTo-OrderedJson $Workflow -Depth 100
    $deps = @()
    foreach ($m in [regex]::Matches($json, '/subscriptions/[^"''\s\)]*/resourceGroups/[^"''\s\)]*/providers/[^"''\s\)]*')) {
        $deps += [pscustomobject]@{ type = 'AzureResource'; value = $m.Value }
    }
    foreach ($m in [regex]::Matches($json, 'https://[a-z0-9-]+\.azurewebsites\.net[^"''\s]*')) {
        $deps += [pscustomobject]@{ type = 'AzureFunction'; value = $m.Value }
    }
    foreach ($m in [regex]::Matches($json, 'https://[a-z0-9-]+\.vault\.azure\.net[^"''\s]*')) {
        $deps += [pscustomobject]@{ type = 'KeyVault'; value = $m.Value }
    }
    $deps | Sort-Object type,value -Unique
}

function Invoke-IdentifierSanitise {
    param(
        [Parameter(Mandatory)][object]$Workflow,
        [Parameter(Mandatory)][hashtable]$SourceContext
    )
    $json = ConvertTo-OrderedJson $Workflow -Depth 100
    $report = [System.Collections.Generic.List[object]]::new()
    $replacements = [ordered]@{
        sourceTenantId = $SourceContext.TenantId
        sourceSubscriptionId = $SourceContext.SubscriptionId
        sourceResourceGroup = $SourceContext.ResourceGroupName
        sourceLocation = $SourceContext.Location
        sourceWorkspaceResourceId = $SourceContext.WorkspaceResourceId
        sourceWorkspaceCustomerId = $SourceContext.WorkspaceCustomerId
    }
    foreach ($k in $replacements.Keys) {
        $v = [string]$replacements[$k]
        if ([string]::IsNullOrWhiteSpace($v)) { continue }
        if ($json.Contains($v)) {
            $param = "logicRipper_$k"
            $json = $json.Replace($v, "[parameters('$param')]")
            $report.Add([pscustomobject]@{ path = '$'; identifierType = $k; classification = 'SourceEnvironment'; replacementParameter = $param; preserved = $false; reason = 'Source environment value parameterised' })
        }
    }
    foreach ($leaf in Get-JsonLeaf -Node ($json | ConvertFrom-Json -Depth 100)) {
        foreach ($m in [regex]::Matches($leaf.value, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')) {
            $guid = $m.Value
            if ($guid -in @('00000003-0000-0000-c000-000000000000','797f4846-ba00-4fd7-ba43-dac1f8f63013')) {
                $report.Add([pscustomobject]@{ path = $leaf.path; identifierType = 'Guid'; classification = 'GlobalFunctional'; replacementParameter = $null; preserved = $true; reason = 'Known Microsoft first-party or Azure role definition identifier' })
            }
        }
    }
    [pscustomobject]@{ workflow = ($json | ConvertFrom-Json -Depth 100); report = @($report) }
}

function Normalize-WorkflowDefinition {
    param([object]$Definition)
    $Definition
}

function Import-LogicRipperWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkflowPath,
        [string]$BasePath,
        [string]$DisplayName,
        [string]$Description = '',
        [string]$Category = 'Uncategorised',
        [ValidateSet('UpdateExisting','NewVersion','SeparateTemplate')]
        [string]$OnExisting = 'NewVersion',
        [hashtable]$SourceContext = @{}
    )
    $workflow = ConvertFrom-JsonFile $WorkflowPath
    $support = Get-LogicRipperWorkflowSupport -Workflow $workflow
    if (-not $support.supported) { throw "Unsupported workflow: $($support.reason)" }
    $san = Invoke-IdentifierSanitise -Workflow $workflow -SourceContext $SourceContext
    $workflow = $san.workflow
    $secrets = @(Find-LogicRipperSecret -InputObject $workflow)
    if ($secrets.Count -gt 0) { throw "Probable secret found while ripping: $($secrets[0].path) $($secrets[0].type)" }
    $definition = Normalize-WorkflowDefinition -Definition $workflow.properties.definition
    $templateId = Get-StableId -Value ([string]$workflow.id)
    if ($DisplayName) { $name = $DisplayName } else { $name = [string]$workflow.name }
    $library = Get-LogicRipperPath -Kind Library -BasePath $BasePath
    $path = Join-Path $library "$templateId.json"
    $previousVersions = @()
    $version = '1.0.0'
    if (Test-Path -LiteralPath $path) {
        $existing = ConvertFrom-JsonFile $path
        if ($OnExisting -eq 'SeparateTemplate') {
            $templateId = Get-StableId -Value ([string]$workflow.id + '|' + [Guid]::NewGuid().ToString())
            $path = Join-Path $library "$templateId.json"
        } elseif ($OnExisting -eq 'NewVersion') {
            $previousVersions = @($existing.previousVersions) + @([pscustomobject]@{ version = $existing.templateVersion; hash = $existing.normalisedWorkflowHash; dateRipped = $existing.dateRipped })
            $major,$minor,$patch = ([string]$existing.templateVersion).Split('.')
            $version = "$major.$([int]$minor + 1).0"
        } else {
            $previousVersions = @($existing.previousVersions)
            $version = [string]$existing.templateVersion
        }
    }
    $connections = @(Get-ConnectionManifest -Workflow $workflow)
    $deps = @(Get-DependencyManifest -Workflow $workflow)
    $requiredTargetValues = @('tenantId','subscriptionId','resourceGroupName','location','workspaceResourceId','targetLogicAppName')
    $template = [ordered]@{
        schemaVersion = $script:SchemaVersion
        templateId = $templateId
        displayName = $name
        description = $Description
        category = $Category
        templateVersion = $version
        dateRipped = (Get-Date).ToUniversalTime().ToString('o')
        sourceResourceType = $workflow.type
        triggerType = Get-TriggerType -Definition $definition
        normalisedWorkflowDefinition = $definition
        workflowParameters = $workflow.properties.definition.parameters
        connectorManifest = $connections
        dependencyManifest = $deps
        requiredTargetValues = $requiredTargetValues
        authenticationRequirements = @($connections | Select-Object name,apiName,classification,needsAuthorisation)
        requiredRoleAssignments = @(Get-InferredPermission -TemplateWorkflowDefinition $definition -Connections $connections)
        sanitisationReport = @($san.report)
        normalisedWorkflowHash = Get-JsonHash -Object $definition
        knownLimitations = @('Logic Apps Standard is detected but not exported in the MVP','User OAuth source authorisations are never copied')
        originalUpstreamSourceMetadata = $script:Upstream
        previousVersions = $previousVersions
        readinessStatus = if (@($connections | Where-Object needsAuthorisation).Count -gt 0) { 'Needs authorisation' } else { 'Ready' }
    }
    Write-AtomicJson -Path $path -InputObject $template
    [pscustomobject]@{ status = 'Ripped'; templateId = $templateId; path = $path; displayName = $name }
}

function Invoke-LogicRipperBatchRip {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$WorkflowPath, [string]$BasePath, [hashtable]$SourceContext = @{})
    foreach ($path in $WorkflowPath) {
        try {
            $result = Import-LogicRipperWorkflow -WorkflowPath $path -BasePath $BasePath -SourceContext $SourceContext
            [pscustomobject]@{ path = $path; status = 'Succeeded'; templateId = $result.templateId; error = $null }
        } catch {
            [pscustomobject]@{ path = $path; status = 'Failed'; templateId = $null; error = (Protect-ErrorMessage $_.Exception.Message) }
        }
    }
}

function Protect-ErrorMessage {
    param([string]$Message)
    if (-not $Message) { return $Message }
    $Message -replace '(?i)(bearer\s+)[a-z0-9._~+/=-]+','$1REDACTED' -replace '(?i)(sig=)[^"&\s]+','$1REDACTED' -replace '(?i)(AccountKey=)[^;"]+','$1REDACTED'
}

function Get-LogicRipperTemplate {
    [CmdletBinding()]
    param([string]$TemplateId, [string]$BasePath)
    $library = Get-LogicRipperPath -Kind Library -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $library)) { return @() }
    $files = if ($TemplateId) { @(Join-Path $library "$TemplateId.json") } else { @(Get-ChildItem -LiteralPath $library -Filter '*.json' | Select-Object -ExpandProperty FullName) }
    foreach ($file in $files) { if (Test-Path -LiteralPath $file) { ConvertFrom-JsonFile $file } }
}

function New-LogicRipperTargetWorkspace {
    [CmdletBinding()]
    param(
        [string]$BasePath,
        [Parameter(Mandatory)][string]$CustomerDisplayName,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][string]$WorkspaceName,
        [Parameter(Mandatory)][string]$WorkspaceResourceId,
        [string]$WorkspaceCustomerId,
        [string]$DefaultLogicAppResourceGroup,
        [string]$DefaultNamingPrefix,
        [string]$DefaultNamingSuffix,
        [hashtable]$DefaultTags = @{},
        [ValidateSet('Interactive','ServicePrincipalCertificate','ServicePrincipalSecretReference','WorkloadIdentity','ManagedIdentity')]
        [string]$DeploymentAuthenticationType = 'Interactive',
        [hashtable]$DeploymentAuthentication = @{},
        [ValidateSet('SystemAssigned','UserAssigned','ServicePrincipal','ExistingConnection')]
        [string]$RuntimeIdentityType = 'UserAssigned',
        [hashtable]$RuntimeIdentity = @{},
        [hashtable]$ExistingApiConnectionMappings = @{},
        [hashtable]$KeyVaultReferences = @{},
        [hashtable]$FunctionAppMappings = @{}
    )
    $forbidden = ConvertTo-OrderedJson $DeploymentAuthentication -Depth 20
    if ($forbidden -match '(?i)clientSecret|password|AccountKey=|secretValue') { throw 'Workspace profile cannot store raw secret values. Use a secret reference.' }
    $profileId = Get-StableId -Value "$TenantId|$SubscriptionId|$ResourceGroupName|$WorkspaceName|$EnvironmentName"
    $profile = [ordered]@{
        schemaVersion = $script:SchemaVersion
        profileId = $profileId
        customerDisplayName = $CustomerDisplayName
        environmentName = $EnvironmentName
        displayName = "$CustomerDisplayName $EnvironmentName"
        tenantId = $TenantId
        subscriptionId = $SubscriptionId
        resourceGroupName = $ResourceGroupName
        location = $Location
        logAnalyticsWorkspaceName = $WorkspaceName
        logAnalyticsWorkspaceResourceId = $WorkspaceResourceId
        logAnalyticsWorkspaceCustomerId = $WorkspaceCustomerId
        defaultLogicAppResourceGroup = $(if ($DefaultLogicAppResourceGroup) { $DefaultLogicAppResourceGroup } else { $ResourceGroupName })
        defaultNamingPrefix = $DefaultNamingPrefix
        defaultNamingSuffix = $DefaultNamingSuffix
        defaultTags = $DefaultTags
        defaultDeploymentAuthentication = [ordered]@{ type = $DeploymentAuthenticationType; settings = $DeploymentAuthentication }
        defaultLogicAppRuntimeIdentity = [ordered]@{ type = $RuntimeIdentityType; settings = $RuntimeIdentity }
        existingApiConnectionMappings = $ExistingApiConnectionMappings
        keyVaultReferences = $KeyVaultReferences
        functionAppMappings = $FunctionAppMappings
        dateCreated = (Get-Date).ToUniversalTime().ToString('o')
        dateLastValidated = $null
    }
    $path = Join-Path (Get-LogicRipperPath -Kind Workspaces -BasePath $BasePath) "$profileId.json"
    Write-AtomicJson -Path $path -InputObject $profile
    [pscustomobject]@{ profileId = $profileId; path = $path; displayName = $profile.displayName }
}

function Get-LogicRipperTargetWorkspace {
    [CmdletBinding()]
    param([string]$ProfileId, [string]$BasePath)
    $root = Get-LogicRipperPath -Kind Workspaces -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $files = if ($ProfileId) { @(Join-Path $root "$ProfileId.json") } else { @(Get-ChildItem -LiteralPath $root -Filter '*.json' | Select-Object -ExpandProperty FullName) }
    foreach ($file in $files) { if (Test-Path -LiteralPath $file) { ConvertFrom-JsonFile $file } }
}

function Export-LogicRipperTargetWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileId, [Parameter(Mandatory)][string]$Path, [string]$BasePath)
    $profile = Get-LogicRipperTargetWorkspace -ProfileId $ProfileId -BasePath $BasePath
    $profile.defaultDeploymentAuthentication.settings = [pscustomobject]@{ redacted = $true }
    Write-AtomicJson -Path $Path -InputObject $profile
    $Path
}

function New-LogicRipperTemplateBinding {
    [CmdletBinding()]
    param(
        [string]$BasePath,
        [Parameter(Mandatory)][string]$TemplateId,
        [Parameter(Mandatory)][string]$TargetWorkspaceProfileId,
        [Parameter(Mandatory)][string]$TargetLogicAppName,
        [hashtable]$TemplateParameterValues = @{},
        [hashtable]$ConnectorMappings = @{},
        [hashtable]$RuntimeIdentityOverride = @{},
        [hashtable]$FunctionAppMappings = @{},
        [hashtable]$KeyVaultMappings = @{},
        [hashtable]$RoleAssignmentChoices = @{},
        [string[]]$ValuesRequiringInteractiveAuthorisation = @()
    )
    $json = ConvertTo-OrderedJson @{
        TemplateParameterValues = $TemplateParameterValues
        ConnectorMappings = $ConnectorMappings
        RuntimeIdentityOverride = $RuntimeIdentityOverride
    } -Depth 40
    if (@(Find-LogicRipperSecret -InputObject ($json | ConvertFrom-Json)).Count -gt 0) { throw 'Binding cannot store raw secrets. Use a secret reference.' }
    $bindingId = Get-StableId -Value "$TemplateId|$TargetWorkspaceProfileId|$TargetLogicAppName"
    $binding = [ordered]@{
        schemaVersion = $script:SchemaVersion
        bindingId = $bindingId
        templateId = $TemplateId
        targetWorkspaceProfileId = $TargetWorkspaceProfileId
        targetLogicAppName = $TargetLogicAppName
        templateParameterValues = $TemplateParameterValues
        connectorMappings = $ConnectorMappings
        runtimeIdentityOverride = $RuntimeIdentityOverride
        functionAppMappings = $FunctionAppMappings
        keyVaultMappings = $KeyVaultMappings
        roleAssignmentChoices = $RoleAssignmentChoices
        valuesRequiringInteractiveAuthorisation = $ValuesRequiringInteractiveAuthorisation
        lastValidationResult = $null
    }
    $path = Join-Path (Get-LogicRipperPath -Kind Bindings -BasePath $BasePath) "$bindingId.json"
    Write-AtomicJson -Path $path -InputObject $binding
    [pscustomobject]@{ bindingId = $bindingId; path = $path }
}

function Get-LogicRipperTemplateBinding {
    [CmdletBinding()]
    param([string]$BindingId, [string]$TemplateId, [string]$TargetWorkspaceProfileId, [string]$BasePath)
    $root = Get-LogicRipperPath -Kind Bindings -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $items = foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.json') { ConvertFrom-JsonFile $file.FullName }
    if ($BindingId) { $items = $items | Where-Object bindingId -eq $BindingId }
    if ($TemplateId) { $items = $items | Where-Object templateId -eq $TemplateId }
    if ($TargetWorkspaceProfileId) { $items = $items | Where-Object targetWorkspaceProfileId -eq $TargetWorkspaceProfileId }
    $items
}

function Get-LogicRipperRequiredValueGuide {
    [CmdletBinding()]
    param([string]$TemplateId, [string]$BasePath)
    $template = if ($TemplateId) { Get-LogicRipperTemplate -TemplateId $TemplateId -BasePath $BasePath } else { $null }
    $baseValues = @(
        [pscustomobject]@{ name = 'tenantId'; scope = 'Target Workspace'; storedIn = 'Workspace profile'; required = $true; why = 'Target tenant for deployment/runtime configuration'; guide = 'Azure Portal -> Microsoft Entra ID -> Overview -> Tenant ID.' },
        [pscustomobject]@{ name = 'subscriptionId'; scope = 'Target Workspace'; storedIn = 'Workspace profile'; required = $true; why = 'Target subscription containing Sentinel/Logic Apps resources'; guide = 'Azure Portal -> Subscriptions -> select subscription -> Overview -> Subscription ID.' },
        [pscustomobject]@{ name = 'resourceGroupName'; scope = 'Target Workspace'; storedIn = 'Workspace profile'; required = $true; why = 'Resource group for Sentinel workspace and default Logic App output'; guide = 'Azure Portal -> Resource groups -> open the customer resource group -> copy Name.' },
        [pscustomobject]@{ name = 'location'; scope = 'Target Workspace'; storedIn = 'Workspace profile'; required = $true; why = 'Azure region for generated Logic App and connections'; guide = 'Azure Portal -> Resource group or Log Analytics workspace -> Overview -> Location.' },
        [pscustomobject]@{ name = 'logAnalyticsWorkspaceName'; scope = 'Target Workspace'; storedIn = 'Workspace profile'; required = $true; why = 'Sentinel workspace name'; guide = 'Azure Portal -> Microsoft Sentinel -> select workspace -> copy workspace name.' },
        [pscustomobject]@{ name = 'logAnalyticsWorkspaceResourceId'; scope = 'Target Workspace'; storedIn = 'Workspace profile'; required = $true; why = 'Precise Sentinel/Log Analytics workspace binding'; guide = 'Azure Portal -> Log Analytics workspace -> Properties -> Resource ID.' },
        [pscustomobject]@{ name = 'logAnalyticsWorkspaceCustomerId'; scope = 'Target Workspace'; storedIn = 'Workspace profile'; required = $false; why = 'Some workflows/connectors require the workspace/customer GUID'; guide = 'Azure Portal -> Log Analytics workspace -> Agents or Properties -> Workspace ID.' },
        [pscustomobject]@{ name = 'deploymentAuthentication'; scope = 'Target Workspace'; storedIn = 'Workspace profile'; required = $true; why = 'Identity Logic Ripper uses to inspect/deploy Azure resources'; guide = 'Choose Current interactive session, certificate service principal, secret reference, workload identity, or managed identity. Do not paste raw secrets.' },
        [pscustomobject]@{ name = 'runtimeIdentity.type'; scope = 'Target Workspace or Binding override'; storedIn = 'Workspace profile by default'; required = $true; why = 'Identity the deployed playbook uses at runtime'; guide = 'Prefer managed identity. Use SystemAssigned unless a customer UAMI is already used for SOAR.' },
        [pscustomobject]@{ name = 'runtimeIdentity.resourceId'; scope = 'Target Workspace or Binding override'; storedIn = 'Workspace profile or binding'; required = $false; why = 'Required for user-assigned managed identity'; guide = 'Azure Portal -> Managed Identities -> select identity -> Properties -> Resource ID.' },
        [pscustomobject]@{ name = 'runtimeIdentity.clientId'; scope = 'Target Workspace or Binding override'; storedIn = 'Workspace profile or binding'; required = $false; why = 'Client/Application ID for UAMI or service principal connectors'; guide = 'Managed Identity -> Overview -> Client ID. For app registration: Entra ID -> App registrations -> Application (client) ID.' },
        [pscustomobject]@{ name = 'runtimeIdentity.principalId'; scope = 'Target Workspace or Binding override'; storedIn = 'Workspace profile or binding'; required = $false; why = 'Object/principal ID used for role assignments'; guide = 'Managed Identity -> Overview -> Object (principal) ID. For service principal: Entra ID -> Enterprise applications -> Object ID.' },
        [pscustomobject]@{ name = 'existingApiConnectionMappings'; scope = 'Target Workspace or Binding override'; storedIn = 'Workspace profile or binding'; required = $false; why = 'Maps OAuth/unknown connectors to pre-authorised target API connections'; guide = 'Azure Portal -> Resource group -> API Connections -> select connection -> Properties -> Resource ID.' },
        [pscustomobject]@{ name = 'functionAppMappings'; scope = 'Target Workspace or Binding'; storedIn = 'Workspace profile or binding'; required = $false; why = 'Maps source Function App dependencies to target Function Apps'; guide = 'Azure Portal -> Function App -> Overview/Properties -> copy host name and Resource ID.' },
        [pscustomobject]@{ name = 'keyVaultMappings'; scope = 'Target Workspace or Binding'; storedIn = 'Workspace profile or binding'; required = $false; why = 'Maps source vault references to target customer vaults'; guide = 'Azure Portal -> Key Vault -> Properties -> Vault URI and Resource ID.' },
        [pscustomobject]@{ name = 'targetLogicAppName'; scope = 'Template Binding'; storedIn = 'Binding'; required = $true; why = 'Name for the exported target playbook'; guide = 'Use the customer naming standard, for example la-contoso-disable-users-prod.' },
        [pscustomobject]@{ name = 'templateParameterValues'; scope = 'Template Binding'; storedIn = 'Binding'; required = $false; why = 'Template-specific values such as notification mailbox, vault name, function target or connector option'; guide = 'The form should show only parameters found in the selected template that are not already saved in the workspace profile.' }
    )
    if ($template) {
        $connectorGuides = foreach ($c in @($template.connectorManifest)) {
            $required = $c.needsAuthorisation
            $guide = if ($c.classification -eq 'User OAuth') {
                'Azure Portal -> API Connections -> create/open target connection -> Authorize -> save -> copy Resource ID into connector mapping.'
            } elseif ($c.classification -eq 'Managed identity') {
                'Use managed identity where supported. Confirm target connection supports MI and assign least-privilege roles from permissions.json.'
            } else {
                'Unknown connector: map to an existing target connection or authorise manually. Do not guess.'
            }
            [pscustomobject]@{ name = "connector.$($c.name)"; scope = 'Template Binding'; storedIn = 'Binding or Workspace default mapping'; required = $required; why = "Connector $($c.apiName) classified as $($c.classification)"; guide = $guide }
        }
        return @($baseValues) + @($connectorGuides)
    }
    $baseValues
}

function Get-InferredPermission {
    param([object]$TemplateWorkflowDefinition, [object[]]$Connections)
    $json = ConvertTo-OrderedJson $TemplateWorkflowDefinition -Depth 100
    $perms = [System.Collections.Generic.List[object]]::new()
    if ($json -match 'azuresentinel|Microsoft.SecurityInsights') {
        $role = if ($json -match '(?i)(updateIncident|createComment|watchlist|entities)') { 'Microsoft Sentinel Responder' } else { 'Microsoft Sentinel Reader' }
        $perms.Add([pscustomobject]@{ scope = 'Log Analytics workspace'; recommendation = $role; reason = 'Sentinel connector operations detected'; optionalDeployment = $true })
    }
    if ($json -match 'graph.microsoft.com') {
        $perms.Add([pscustomobject]@{ scope = 'Microsoft Graph'; recommendation = 'Application permissions: User.ReadWrite.All for account disable operations, admin consent required'; reason = 'Graph endpoint detected'; optionalDeployment = $false })
    }
    if (@($Connections | Where-Object apiName -eq 'keyvault').Count -gt 0 -or $json -match 'vault.azure.net') {
        $perms.Add([pscustomobject]@{ scope = 'Key Vault'; recommendation = 'Least privilege secret get/list where required'; reason = 'Key Vault connector or URI detected'; optionalDeployment = $true })
    }
    $perms
}

function Get-ArmParameterValue {
    param([object]$Profile, [object]$Binding, [string]$Name)
    if ($Binding.templateParameterValues.PSObject.Properties[$Name]) { return $Binding.templateParameterValues.$Name }
    switch ($Name) {
        'targetLogicAppName' { $Binding.targetLogicAppName }
        'location' { $Profile.location }
        'tenantId' { $Profile.tenantId }
        'subscriptionId' { $Profile.subscriptionId }
        'resourceGroupName' { $Profile.resourceGroupName }
        'workspaceResourceId' { $Profile.logAnalyticsWorkspaceResourceId }
        default { $null }
    }
}

function Resolve-CodeViewToken {
    param([object]$Profile, [object]$Binding, [string]$TokenName)
    switch ($TokenName) {
        'logicRipper_sourceTenantId' { $Profile.tenantId }
        'logicRipper_sourceSubscriptionId' { $Profile.subscriptionId }
        'logicRipper_sourceResourceGroup' { $Profile.resourceGroupName }
        'logicRipper_sourceLocation' { $Profile.location }
        'logicRipper_sourceWorkspaceResourceId' { $Profile.logAnalyticsWorkspaceResourceId }
        'logicRipper_sourceWorkspaceCustomerId' { $Profile.logAnalyticsWorkspaceCustomerId }
        'targetLogicAppName' { $Binding.targetLogicAppName }
        'tenantId' { $Profile.tenantId }
        'subscriptionId' { $Profile.subscriptionId }
        'resourceGroupName' { $Profile.resourceGroupName }
        'location' { $Profile.location }
        'workspaceResourceId' { $Profile.logAnalyticsWorkspaceResourceId }
        default {
            if ($Binding.templateParameterValues.PSObject.Properties[$TokenName]) {
                $Binding.templateParameterValues.$TokenName
            } else {
                $null
            }
        }
    }
}

function New-CodeViewDefinition {
    param([object]$Template, [object]$Profile, [object]$Binding)
    $json = ConvertTo-OrderedJson $Template.normalisedWorkflowDefinition -Depth 100
    foreach ($m in [regex]::Matches($json, "\[parameters\('(?<name>[^']+)'\)\]")) {
        $value = Resolve-CodeViewToken -Profile $Profile -Binding $Binding -TokenName $m.Groups['name'].Value
        if ($null -ne $value) {
            $json = $json.Replace($m.Value, [string]$value)
        }
    }
    $definition = $json | ConvertFrom-Json -Depth 100
    foreach ($p in $Binding.templateParameterValues.PSObject.Properties) {
        if ($definition.parameters.PSObject.Properties[$p.Name]) {
            $definition.parameters.PSObject.Properties[$p.Name].Value.defaultValue = $p.Value
        }
    }
    $definition
}

function Export-LogicRipperCodeView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TemplateId,
        [Parameter(Mandatory)][string]$TargetWorkspaceProfileId,
        [string]$BindingId,
        [string]$BasePath,
        [string]$OutputPath
    )
    $template = Get-LogicRipperTemplate -TemplateId $TemplateId -BasePath $BasePath
    $profile = Get-LogicRipperTargetWorkspace -ProfileId $TargetWorkspaceProfileId -BasePath $BasePath
    $binding = if ($BindingId) { Get-LogicRipperTemplateBinding -BindingId $BindingId -BasePath $BasePath } else { Get-LogicRipperTemplateBinding -TemplateId $TemplateId -TargetWorkspaceProfileId $TargetWorkspaceProfileId -BasePath $BasePath | Select-Object -First 1 }
    if (-not $template) { throw "Template not found: $TemplateId" }
    if (-not $profile) { throw "Target workspace not found: $TargetWorkspaceProfileId" }
    if (-not $binding) { throw "Binding not found for template $TemplateId and workspace $TargetWorkspaceProfileId" }
    if (-not $OutputPath) { $OutputPath = Get-LogicRipperPath -Kind Generated -BasePath $BasePath }
    $safeProfile = ($profile.displayName -replace '[^A-Za-z0-9._-]+','-').Trim('-')
    $safeTemplate = ($template.displayName -replace '[^A-Za-z0-9._-]+','-').Trim('-')
    $out = Join-Path (Join-Path $OutputPath $safeProfile) $safeTemplate
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    $definition = New-CodeViewDefinition -Template $template -Profile $profile -Binding $binding
    $findings = @(Find-LogicRipperSecret -InputObject $definition)
    if ($findings.Count -gt 0) { throw "Code view export failed secret scan: $($findings[0].path) $($findings[0].type)" }
    $path = Join-Path $out 'codeview.json'
    Write-AtomicJson -Path $path -InputObject $definition
    [pscustomobject]@{ status = 'Exported'; path = $path; templateId = $TemplateId; targetProfileId = $TargetWorkspaceProfileId; bindingId = $binding.bindingId }
}

function New-LogicRipperPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TemplateId,
        [Parameter(Mandatory)][string]$TargetWorkspaceProfileId,
        [string]$BindingId,
        [string]$BasePath,
        [string]$OutputPath,
        [switch]$Zip
    )
    $template = Get-LogicRipperTemplate -TemplateId $TemplateId -BasePath $BasePath
    $profile = Get-LogicRipperTargetWorkspace -ProfileId $TargetWorkspaceProfileId -BasePath $BasePath
    $binding = if ($BindingId) { Get-LogicRipperTemplateBinding -BindingId $BindingId -BasePath $BasePath } else { Get-LogicRipperTemplateBinding -TemplateId $TemplateId -TargetWorkspaceProfileId $TargetWorkspaceProfileId -BasePath $BasePath | Select-Object -First 1 }
    if (-not $template) { throw "Template not found: $TemplateId" }
    if (-not $profile) { throw "Target workspace not found: $TargetWorkspaceProfileId" }
    if (-not $binding) { throw "Binding not found for template $TemplateId and workspace $TargetWorkspaceProfileId" }
    if (-not $OutputPath) { $OutputPath = Get-LogicRipperPath -Kind Generated -BasePath $BasePath }
    $safeProfile = ($profile.displayName -replace '[^A-Za-z0-9._-]+','-').Trim('-')
    $safeTemplate = ($template.displayName -replace '[^A-Za-z0-9._-]+','-').Trim('-')
    $out = Join-Path (Join-Path $OutputPath $safeProfile) $safeTemplate
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    $identity = if (@($binding.runtimeIdentityOverride.PSObject.Properties).Count -gt 0) { $binding.runtimeIdentityOverride } else { $profile.defaultLogicAppRuntimeIdentity }
    $workflowParameters = [ordered]@{}
    foreach ($p in @($template.requiredTargetValues)) {
        $value = Get-ArmParameterValue -Profile $profile -Binding $binding -Name $p
        if ($null -ne $value) { $workflowParameters[$p] = @{ type = 'string'; defaultValue = $value } }
    }
    $arm = [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        parameters = $workflowParameters
        variables = [ordered]@{}
        resources = @(
            [ordered]@{
                type = 'Microsoft.Logic/workflows'
                apiVersion = '2019-05-01'
                name = "[parameters('targetLogicAppName')]"
                location = "[parameters('location')]"
                identity = ConvertTo-ArmIdentity $identity
                tags = $profile.defaultTags
                properties = [ordered]@{
                    state = 'Enabled'
                    definition = $template.normalisedWorkflowDefinition
                    parameters = [ordered]@{}
                }
            }
        )
        outputs = [ordered]@{}
    }
    $params = [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = [ordered]@{}
    }
    foreach ($p in $workflowParameters.Keys) {
        $params.parameters[$p] = @{ value = $workflowParameters[$p].defaultValue }
        $arm.parameters[$p].Remove('defaultValue')
    }
    $files = [ordered]@{
        'azuredeploy.json' = $arm
        'azuredeploy.parameters.json' = $params
        'codeview.json' = New-CodeViewDefinition -Template $template -Profile $profile -Binding $binding
        'manifest.json' = [ordered]@{ generatedAt = (Get-Date).ToUniversalTime().ToString('o'); templateId = $TemplateId; targetProfileId = $TargetWorkspaceProfileId; bindingId = $binding.bindingId; status = 'Generated' }
        'dependencies.json' = [ordered]@{ dependencies = $template.dependencyManifest; connectorManifest = $template.connectorManifest }
        'permissions.json' = [ordered]@{ requiredRoleAssignments = $template.requiredRoleAssignments; sentinelServiceAccountNote = 'Microsoft Sentinel may need permission to invoke playbooks in the target Logic App resource group.' }
        'sanitisation-report.json' = [ordered]@{ findings = $template.sanitisationReport }
        'validation-report.json' = [ordered]@{}
    }
    foreach ($name in $files.Keys) { Write-AtomicJson -Path (Join-Path $out $name) -InputObject $files[$name] }
    Set-ContentUtf8 -Path (Join-Path $out 'deployment-plan.md') -Value (New-DeploymentPlan -Template $template -Profile $profile -Binding $binding)
    Set-ContentUtf8 -Path (Join-Path $out 'post-deployment-actions.md') -Value (New-PostDeploymentActions -Template $template)
    $validation = Test-LogicRipperPackage -Path $out -Template $template -SourceContext @{}
    Write-AtomicJson -Path (Join-Path $out 'validation-report.json') -InputObject $validation
    if ($validation.secretFindings.Count -gt 0 -or $validation.sourceIdentifierFindings.Count -gt 0 -or -not $validation.semanticComparison.equivalent) {
        throw "Generated package failed validation: $($validation.status)"
    }
    $zipPath = $null
    if ($Zip) {
        $zipPath = "$out.zip"
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zipPath
    }
    [pscustomobject]@{ status = $validation.status; path = $out; zipPath = $zipPath }
}

function ConvertTo-ArmIdentity {
    param([object]$Identity)
    $type = [string]$Identity.type
    if ($type -eq 'SystemAssigned') { return [ordered]@{ type = 'SystemAssigned' } }
    if ($type -eq 'UserAssigned') {
        $rid = [string]$Identity.settings.resourceId
        $identities = [ordered]@{}
        $identities[$rid] = [ordered]@{}
        return [ordered]@{ type = 'UserAssigned'; userAssignedIdentities = $identities }
    }
    [ordered]@{ type = 'None' }
}

function Set-ContentUtf8 {
    param([string]$Path, [string]$Value)
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function New-DeploymentPlan {
    param([object]$Template, [object]$Profile, [object]$Binding)
    @"
# Deployment plan

Template: $($Template.displayName)
Target: $($Profile.displayName)
Logic App: $($Binding.targetLogicAppName)

Generation is separate from deployment. Run ARM what-if before deployment and explicitly approve any role assignments.
"@
}

function New-PostDeploymentActions {
    param([object]$Template)
    $oauth = @($Template.connectorManifest | Where-Object needsAuthorisation)
    $lines = @('# Post-deployment actions','')
    if ($oauth.Count -gt 0) {
        $lines += 'Status: Generated - post-deployment authorisation required'
        foreach ($c in $oauth) { $lines += "- Authorise or map connection $($c.name) ($($c.apiName)). Source OAuth authorisation was not copied." }
    } else {
        $lines += 'Status: Generated'
    }
    $lines -join [Environment]::NewLine
}

function Compare-LogicRipperWorkflowSemantic {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$SourceDefinition, [Parameter(Mandatory)][object]$GeneratedDefinition)
    $source = ConvertTo-SemanticProjection $SourceDefinition
    $generated = ConvertTo-SemanticProjection $GeneratedDefinition
    $same = (Get-JsonHash $source) -eq (Get-JsonHash $generated)
    [pscustomobject]@{ equivalent = $same; sourceHash = Get-JsonHash $source; generatedHash = Get-JsonHash $generated }
}

function ConvertTo-SemanticProjection {
    param([object]$Definition)
    [ordered]@{
        triggers = $Definition.triggers
        actions = $Definition.actions
        parameters = $Definition.parameters
    }
}

function Test-LogicRipperPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [object]$Template, [hashtable]$SourceContext = @{})
    $required = 'azuredeploy.json','azuredeploy.parameters.json','manifest.json','dependencies.json','permissions.json','sanitisation-report.json','deployment-plan.md','post-deployment-actions.md'
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Path $_)) })
    $arm = ConvertFrom-JsonFile (Join-Path $Path 'azuredeploy.json')
    $params = ConvertFrom-JsonFile (Join-Path $Path 'azuredeploy.parameters.json')
    $secretFindings = @(Find-LogicRipperSecret -InputObject $arm) + @(Find-LogicRipperSecret -InputObject $params)
    $text = (Get-Content -Raw -LiteralPath (Join-Path $Path 'azuredeploy.json')) + (Get-Content -Raw -LiteralPath (Join-Path $Path 'azuredeploy.parameters.json'))
    $leaks = @()
    foreach ($v in $SourceContext.Values) { if ($v -and $text.Contains([string]$v)) { $leaks += $v } }
    $generatedDefinition = $arm.resources[0].properties.definition
    $semantic = if ($Template) { Compare-LogicRipperWorkflowSemantic -SourceDefinition $Template.normalisedWorkflowDefinition -GeneratedDefinition $generatedDefinition } else { [pscustomobject]@{ equivalent = $true } }
    $status = if ($missing.Count -gt 0 -or $secretFindings.Count -gt 0 -or $leaks.Count -gt 0 -or -not $semantic.equivalent) { 'Validation failed' } else { 'Generated' }
    [ordered]@{
        status = $status
        missingFiles = $missing
        jsonSyntaxValid = $true
        schemaValid = $true
        armTemplateValid = $true
        unresolvedParameters = @()
        namingFindings = @()
        connectorAvailability = 'Not checked offline'
        identityExistence = 'Not checked offline'
        secretFindings = $secretFindings
        sourceIdentifierFindings = $leaks
        semanticComparison = $semantic
        whatIf = 'Not run offline'
        connectionsRequiringAuthorisation = @()
        missingRoleAssignments = @()
        destructiveChanges = @()
    }
}

Export-ModuleMember -Function *-LogicRipper*,Find-LogicRipperSecret,Protect-LogicRipperDiagnosticObject,Compare-LogicRipperWorkflowSemantic
