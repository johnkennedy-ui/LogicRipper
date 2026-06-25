$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\LogicRipper\LogicRipper.psd1') -Force

$base = Join-Path $env:TEMP 'logic-ripper-demo'
$source = @{
    TenantId = '11111111-1111-1111-1111-111111111111'
    SubscriptionId = '22222222-2222-2222-2222-222222222222'
    ResourceGroupName = 'rg-source-sentinel'
    Location = 'uksouth'
    WorkspaceResourceId = '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-source-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-source'
    WorkspaceCustomerId = '33333333-3333-3333-3333-333333333333'
}

$template = Import-LogicRipperWorkflow -WorkflowPath (Join-Path $PSScriptRoot '..\tests\Fixtures\disable-user-accounts.workflow.json') -BasePath $base -DisplayName 'Disable User Accounts' -Category 'Identity Response' -SourceContext $source
$workspace = New-LogicRipperTargetWorkspace -BasePath $base -CustomerDisplayName 'Contoso' -EnvironmentName 'Production' -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -SubscriptionId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -ResourceGroupName 'rg-contoso-sentinel-prod' -Location 'uksouth' -WorkspaceName 'law-contoso-sentinel-prod' -WorkspaceResourceId '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso-sentinel-prod/providers/Microsoft.OperationalInsights/workspaces/law-contoso-sentinel-prod' -RuntimeIdentityType UserAssigned -RuntimeIdentity @{ resourceId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso-sentinel-prod/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-contoso-soar-prod'; clientId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; principalId = 'dddddddd-dddd-dddd-dddd-dddddddddddd' }
$binding = New-LogicRipperTemplateBinding -BasePath $base -TemplateId $template.TemplateId -TargetWorkspaceProfileId $workspace.ProfileId -TargetLogicAppName 'la-contoso-disable-users-prod' -RuntimeIdentityOverride @{ type = 'UserAssigned'; settings = @{ resourceId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso-sentinel-prod/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-contoso-soar-prod' } }
New-LogicRipperPackage -BasePath $base -TemplateId $template.TemplateId -TargetWorkspaceProfileId $workspace.ProfileId -BindingId $binding.BindingId -Zip
