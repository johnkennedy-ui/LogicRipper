$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\src\LogicRipper\LogicRipper.psd1') -Force

function New-TestWorkspace {
    param([string]$Customer = 'Contoso', [string]$Sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
    New-LogicRipperTargetWorkspace -BasePath $script:Base -CustomerDisplayName $Customer -EnvironmentName 'Production' -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId $Sub -ResourceGroupName "rg-$($Customer.ToLower())" -Location 'uksouth' -WorkspaceName "law-$($Customer.ToLower())" -WorkspaceResourceId "/subscriptions/$Sub/resourceGroups/rg-$($Customer.ToLower())/providers/Microsoft.OperationalInsights/workspaces/law-$($Customer.ToLower())" -RuntimeIdentityType UserAssigned -RuntimeIdentity @{ resourceId = "/subscriptions/$Sub/resourceGroups/rg-$($Customer.ToLower())/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-$($Customer.ToLower())"; clientId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; principalId = 'dddddddd-dddd-dddd-dddd-dddddddddddd' }
}

Describe 'Logic Ripper MVP' {
    BeforeAll {
        function New-TestWorkspace {
            param([string]$Customer = 'Contoso', [string]$Sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
            New-LogicRipperTargetWorkspace -BasePath $script:Base -CustomerDisplayName $Customer -EnvironmentName 'Production' -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId $Sub -ResourceGroupName "rg-$($Customer.ToLower())" -Location 'uksouth' -WorkspaceName "law-$($Customer.ToLower())" -WorkspaceResourceId "/subscriptions/$Sub/resourceGroups/rg-$($Customer.ToLower())/providers/Microsoft.OperationalInsights/workspaces/law-$($Customer.ToLower())" -RuntimeIdentityType UserAssigned -RuntimeIdentity @{ resourceId = "/subscriptions/$Sub/resourceGroups/rg-$($Customer.ToLower())/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-$($Customer.ToLower())"; clientId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; principalId = 'dddddddd-dddd-dddd-dddd-dddddddddddd' }
        }
    }
    BeforeEach {
        $script:Base = Join-Path ([IO.Path]::GetTempPath()) ("logic-ripper-test-" + [guid]::NewGuid().ToString('n'))
        $script:Source = @{
            TenantId = '11111111-1111-1111-1111-111111111111'
            SubscriptionId = '22222222-2222-2222-2222-222222222222'
            ResourceGroupName = 'rg-source-sentinel'
            Location = 'uksouth'
            WorkspaceResourceId = '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-source-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-source'
            WorkspaceCustomerId = '33333333-3333-3333-3333-333333333333'
        }
    }
    AfterEach {
        if (Test-Path $script:Base) { Remove-Item $script:Base -Recurse -Force }
    }

    It 'rips a Sentinel incident playbook using managed identity' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json" -BasePath $Base -DisplayName 'Disable User Accounts' -Category 'Identity Response' -SourceContext $Source
        $t = Get-LogicRipperTemplate -TemplateId $r.TemplateId -BasePath $Base
        $t.triggerType | Should -Be 'Microsoft Sentinel Incident'
        @($t.connectorManifest).Count | Should -Be 2
        $t.authenticationRequirements.classification | Should -Contain 'Managed identity'
    }

    It 'proves Disable User Accounts sanitisation and Graph preservation' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json" -BasePath $Base -DisplayName 'Disable User Accounts' -Category 'Identity Response' -SourceContext $Source
        $json = Get-Content -Raw (Join-Path (Get-LogicRipperPath -Kind Library -BasePath $Base) "$($r.TemplateId).json")
        $json | Should -Not -Match '22222222-2222-2222-2222-222222222222'
        $json | Should -Not -Match 'rg-source-sentinel'
        $json | Should -Match 'graph.microsoft.com'
        $template = Get-LogicRipperTemplate -TemplateId $r.TemplateId -BasePath $Base
        ($template.requiredRoleAssignments | ConvertTo-Json -Depth 20) | Should -Match 'User.ReadWrite.All'
    }

    It 'supports scheduled playbooks' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\scheduled.workflow.json" -BasePath $Base -SourceContext $Source
        (Get-LogicRipperTemplate -TemplateId $r.TemplateId -BasePath $Base).triggerType | Should -Be 'Scheduled'
    }

    It 'detects Key Vault connector using managed identity' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json" -BasePath $Base -SourceContext $Source
        $t = Get-LogicRipperTemplate -TemplateId $r.TemplateId -BasePath $Base
        ($t.connectorManifest | Where-Object apiName -eq 'keyvault').classification | Should -Be 'Managed identity'
    }

    It 'detects Azure Function dependencies' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\function-dependency.workflow.json" -BasePath $Base -SourceContext $Source
        $t = Get-LogicRipperTemplate -TemplateId $r.TemplateId -BasePath $Base
        $t.dependencyManifest.type | Should -Contain 'AzureFunction'
    }

    It 'models user-assigned and system-assigned managed identities' {
        $uami = New-LogicRipperTargetWorkspace -BasePath $Base -CustomerDisplayName 'Contoso' -EnvironmentName 'Production' -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -ResourceGroupName 'rg-contoso' -Location 'uksouth' -WorkspaceName 'law-contoso' -WorkspaceResourceId '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso/providers/Microsoft.OperationalInsights/workspaces/law-contoso' -RuntimeIdentityType UserAssigned -RuntimeIdentity @{ resourceId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-contoso'; clientId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; principalId = 'dddddddd-dddd-dddd-dddd-dddddddddddd' }
        $sami = New-LogicRipperTargetWorkspace -BasePath $Base -CustomerDisplayName 'Fabrikam' -EnvironmentName 'Test' -TenantId 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' -SubscriptionId 'ffffffff-ffff-ffff-ffff-ffffffffffff' -ResourceGroupName 'rg-fabrikam' -Location 'uksouth' -WorkspaceName 'law-fabrikam' -WorkspaceResourceId '/subscriptions/ffffffff-ffff-ffff-ffff-ffffffffffff/resourceGroups/rg-fabrikam/providers/Microsoft.OperationalInsights/workspaces/law-fabrikam' -RuntimeIdentityType SystemAssigned
        (Get-LogicRipperTargetWorkspace -ProfileId $uami.ProfileId -BasePath $Base).defaultLogicAppRuntimeIdentity.type | Should -Be 'UserAssigned'
        (Get-LogicRipperTargetWorkspace -ProfileId $sami.ProfileId -BasePath $Base).defaultLogicAppRuntimeIdentity.type | Should -Be 'SystemAssigned'
    }

    It 'allows service-principal secret references but rejects raw secrets' {
        { New-LogicRipperTargetWorkspace -BasePath $Base -CustomerDisplayName 'Bad' -EnvironmentName 'Prod' -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -ResourceGroupName 'rg' -Location 'uksouth' -WorkspaceName 'law' -WorkspaceResourceId '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law' -DeploymentAuthenticationType ServicePrincipalSecretReference -DeploymentAuthentication @{ clientSecret = 'plain-text-secret' } } | Should -Throw
        { New-LogicRipperTargetWorkspace -BasePath $Base -CustomerDisplayName 'Good' -EnvironmentName 'Prod' -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -ResourceGroupName 'rg' -Location 'uksouth' -WorkspaceName 'law' -WorkspaceResourceId '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law' -DeploymentAuthenticationType ServicePrincipalSecretReference -DeploymentAuthentication @{ secretReference = 'env:LOGIC_RIPPER_SP_SECRET' } } | Should -Not -Throw
    }

    It 'marks Office 365 OAuth connections as needing authorisation' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\oauth.workflow.json" -BasePath $Base -SourceContext $Source
        $t = Get-LogicRipperTemplate -TemplateId $r.TemplateId -BasePath $Base
        $t.readinessStatus | Should -Be 'Needs authorisation'
    }

    It 'handles multiple connectors and existing target connection mappings' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json" -BasePath $Base -SourceContext $Source
        $w = New-TestWorkspace
        $b = New-LogicRipperTemplateBinding -BasePath $Base -TemplateId $r.TemplateId -TargetWorkspaceProfileId $w.ProfileId -TargetLogicAppName 'la-contoso-disable-users-prod' -ConnectorMappings @{ azuresentinel = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso/providers/Microsoft.Web/connections/azuresentinel-target' }
        (Get-LogicRipperTemplateBinding -BindingId $b.BindingId -BasePath $Base).connectorMappings.azuresentinel | Should -Match 'azuresentinel-target'
    }

    It 'continues batch ripping when one export fails' {
        $results = Invoke-LogicRipperBatchRip -WorkflowPath @("$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json","$PSScriptRoot\..\Fixtures\standard.workflow.json") -BasePath $Base -SourceContext $Source
        $results.status | Should -Contain 'Succeeded'
        $results.status | Should -Contain 'Failed'
    }

    It 're-rips and versions a template' {
        $one = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\scheduled.workflow.json" -BasePath $Base -SourceContext $Source
        $two = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\scheduled.workflow.json" -BasePath $Base -SourceContext $Source -OnExisting NewVersion
        $t = Get-LogicRipperTemplate -TemplateId $two.TemplateId -BasePath $Base
        $t.templateVersion | Should -Be '1.1.0'
        @($t.previousVersions).Count | Should -BeGreaterThan 0
    }

    It 'renames a saved template after code-view import' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\scheduled.workflow.json" -BasePath $Base -SourceContext $Source
        Rename-LogicRipperTemplate -TemplateId $r.TemplateId -DisplayName 'Renamed Scheduled Template' -BasePath $Base | Out-Null
        (Get-LogicRipperTemplate -TemplateId $r.TemplateId -BasePath $Base).displayName | Should -Be 'Renamed Scheduled Template'
    }

    It 'reuses saved Target Workspaces and Template Bindings' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\scheduled.workflow.json" -BasePath $Base -SourceContext $Source
        $w = New-TestWorkspace
        $b = New-LogicRipperTemplateBinding -BasePath $Base -TemplateId $r.TemplateId -TargetWorkspaceProfileId $w.ProfileId -TargetLogicAppName 'la-contoso-scheduled-prod'
        (Get-LogicRipperTargetWorkspace -ProfileId $w.ProfileId -BasePath $Base).displayName | Should -Be 'Contoso Production'
        (Get-LogicRipperTemplateBinding -BindingId $b.BindingId -BasePath $Base).targetLogicAppName | Should -Be 'la-contoso-scheduled-prod'
    }

    It 'detects secrets and source identifier leaks' {
        { Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\secret.workflow.json" -BasePath $Base -SourceContext $Source } | Should -Throw
        @(Find-LogicRipperSecret -InputObject (Get-Content -Raw "$PSScriptRoot\..\Fixtures\secret.workflow.json" | ConvertFrom-Json)).Count | Should -BeGreaterThan 0
    }

    It 'preserves a global GUID and removes an environment-specific GUID' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json" -BasePath $Base -SourceContext $Source
        $json = Get-Content -Raw (Join-Path (Get-LogicRipperPath -Kind Library -BasePath $Base) "$($r.TemplateId).json")
        $json | Should -Not -Match '22222222-2222-2222-2222-222222222222'
        $json | Should -Match 'graph.microsoft.com'
    }

    It 'generates deterministic packages and two customer outputs from one template' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json" -BasePath $Base -DisplayName 'Disable User Accounts' -Category 'Identity Response' -SourceContext $Source
        $w1 = New-TestWorkspace -Customer Contoso -Sub 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        $b1 = New-LogicRipperTemplateBinding -BasePath $Base -TemplateId $r.TemplateId -TargetWorkspaceProfileId $w1.ProfileId -TargetLogicAppName 'la-contoso-disable-users-prod' -RuntimeIdentityOverride @{ type = 'UserAssigned'; settings = @{ resourceId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-contoso' } }
        $p1 = New-LogicRipperPackage -BasePath $Base -TemplateId $r.TemplateId -TargetWorkspaceProfileId $w1.ProfileId -BindingId $b1.BindingId
        $h1 = Get-FileHash (Join-Path $p1.Path 'azuredeploy.json')
        $p1b = New-LogicRipperPackage -BasePath $Base -TemplateId $r.TemplateId -TargetWorkspaceProfileId $w1.ProfileId -BindingId $b1.BindingId
        (Get-FileHash (Join-Path $p1b.Path 'azuredeploy.json')).Hash | Should -Be $h1.Hash
        $w2 = New-TestWorkspace -Customer Fabrikam -Sub 'ffffffff-ffff-ffff-ffff-ffffffffffff'
        $b2 = New-LogicRipperTemplateBinding -BasePath $Base -TemplateId $r.TemplateId -TargetWorkspaceProfileId $w2.ProfileId -TargetLogicAppName 'la-fabrikam-disable-users-prod'
        $p2 = New-LogicRipperPackage -BasePath $Base -TemplateId $r.TemplateId -TargetWorkspaceProfileId $w2.ProfileId -BindingId $b2.BindingId
        Test-Path (Join-Path $p2.Path 'permissions.json') | Should -BeTrue
    }

    It 'exports code-view JSON for a selected template and workspace binding' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json" -BasePath $Base -DisplayName 'Disable User Accounts' -Category 'Identity Response' -SourceContext $Source
        $w = New-TestWorkspace -Customer Contoso -Sub 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        $b = New-LogicRipperTemplateBinding -BasePath $Base -TemplateId $r.TemplateId -TargetWorkspaceProfileId $w.ProfileId -TargetLogicAppName 'la-contoso-disable-users-prod' -TemplateParameterValues @{ notificationAddress = 'soc@contoso.example' }
        $export = Export-LogicRipperCodeView -BasePath $Base -TemplateId $r.TemplateId -TargetWorkspaceProfileId $w.ProfileId -BindingId $b.BindingId
        $json = Get-Content -Raw $export.Path
        $json | Should -Match 'graph.microsoft.com'
        $json | Should -Match 'soc@contoso.example'
        $json | Should -Not -Match '22222222-2222-2222-2222-222222222222'
        $json | Should -Not -Match 'rg-source-sentinel'
    }

    It 'returns a simplified guide for stored and required values' {
        $r = Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json" -BasePath $Base -DisplayName 'Disable User Accounts' -Category 'Identity Response' -SourceContext $Source
        $guide = @(Get-LogicRipperRequiredValueGuide -BasePath $Base -TemplateId $r.TemplateId)
        $guide.name | Should -Contain 'tenantId'
        $guide.name | Should -Contain 'runtimeIdentity.clientId'
        $guide.name | Should -Contain 'runtimeIdentity.principalId'
        $guide.name | Should -Contain 'connector.azuresentinel'
        ($guide | Where-Object name -eq 'tenantId').storedIn | Should -Be 'Workspace profile'
        ($guide | Where-Object name -eq 'targetLogicAppName').storedIn | Should -Be 'Binding'
    }

    It 'fails semantic comparison when workflow logic changes' {
        $a = (Get-Content -Raw "$PSScriptRoot\..\Fixtures\scheduled.workflow.json" | ConvertFrom-Json).properties.definition
        $b = ($a | ConvertTo-Json -Depth 40 | ConvertFrom-Json)
        $b.actions.Noop.inputs = 'changed'
        (Compare-LogicRipperWorkflowSemantic -SourceDefinition $a -GeneratedDefinition $b).equivalent | Should -BeFalse
    }

    It 'detects and rejects Logic Apps Standard' {
        $wf = Get-Content -Raw "$PSScriptRoot\..\Fixtures\standard.workflow.json" | ConvertFrom-Json
        (Get-LogicRipperWorkflowSupport -Workflow $wf).status | Should -Be 'Unsupported'
        { Import-LogicRipperWorkflow -WorkflowPath "$PSScriptRoot\..\Fixtures\standard.workflow.json" -BasePath $Base } | Should -Throw
    }
}
