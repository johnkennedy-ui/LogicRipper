$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\src\LogicRipper\LogicRipper.psd1') -Force

Describe 'Logic Ripper local code-view transformer' {
    BeforeEach {
        $script:Base = Join-Path ([IO.Path]::GetTempPath()) ("logic-ripper-test-" + [guid]::NewGuid().ToString('n'))
        $script:CodeView = Get-Content -Raw "$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json" | ConvertFrom-Json | Select-Object -ExpandProperty properties | Select-Object -ExpandProperty definition | ConvertTo-Json -Depth 100
    }
    AfterEach {
        if (Test-Path $script:Base) { Remove-Item $script:Base -Recurse -Force }
    }

    It 'analyses pasted code-view JSON and detects customer-specific values' {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $CodeView
        @($analysis.findings).Count | Should -BeGreaterThan 0
        $analysis.status | Should -Be 'Needs review'
        $analysis.findings.kind | Should -Contain 'email'
        $analysis.findings.kind | Should -Contain 'azureResourceId'
    }

    It 'blocks template save until every finding is reviewed' {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $CodeView
        { Save-LogicRipperTemplate -Name 'Disable User Accounts' -Analysis $analysis -BasePath $Base } | Should -Throw -ExpectedMessage '*Needs review*'
    }

    It 'lets the user mark findings replace or preserve and save a template' {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $CodeView
        foreach ($f in $analysis.findings) {
            $decision = if ($f.value -match 'graph.microsoft.com|workflowdefinition.json') { 'preserve' } else { 'replace' }
            Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision $decision -ReplacementName $f.replacementName | Out-Null
        }
        $template = Save-LogicRipperTemplate -Name 'Disable User Accounts' -Purpose 'Disable Entra users from Sentinel incident' -Analysis $analysis -BasePath $Base
        (Get-LogicRipperTemplate -TemplateId $template.TemplateId -BasePath $Base).name | Should -Be 'Disable User Accounts'
    }

    It 'saves secret decisions but blocks generation until the value is removed or replaced safely' {
        $secretCodeView = (Get-Content -Raw "$PSScriptRoot\..\Fixtures\secret.workflow.json" | ConvertFrom-Json).properties.definition | ConvertTo-Json -Depth 100
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $secretCodeView
        foreach ($f in $analysis.findings) {
            Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision secret | Out-Null
        }
        $template = Save-LogicRipperTemplate -Name 'Secret Template' -Analysis $analysis -BasePath $Base
        $workspace = New-LogicRipperTargetWorkspace -BasePath $Base -DisplayName 'Contoso Production' -Values @{}
        $binding = New-LogicRipperBinding -BasePath $Base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -Values @{}
        { New-LogicRipperCodeView -BasePath $Base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -BindingId $binding.BindingId } | Should -Throw -ExpectedMessage '*secret*'
    }

    It 'saves workspace values without raw secrets' {
        $workspace = New-LogicRipperTargetWorkspace -BasePath $Base -DisplayName 'Contoso Production' -Values @{
            tenantId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            subscriptionId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
            workspaceResourceId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso/providers/Microsoft.OperationalInsights/workspaces/law-contoso'
        }
        (Get-LogicRipperTargetWorkspace -ProfileId $workspace.ProfileId -BasePath $Base).displayName | Should -Be 'Contoso Production'
        { New-LogicRipperTargetWorkspace -BasePath $Base -DisplayName Bad -Values @{ password = 'do-not-store' } } | Should -Throw
    }

    It 'saves template-to-workspace bindings and generates copy-pasteable code-view JSON' {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $CodeView
        foreach ($f in $analysis.findings) {
            if ($f.value -match 'graph.microsoft.com|workflowdefinition.json') {
                Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision preserve | Out-Null
            } else {
                Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision replace -ReplacementName $f.replacementName | Out-Null
            }
        }
        $template = Save-LogicRipperTemplate -Name 'Disable User Accounts' -Analysis $analysis -BasePath $Base
        $workspaceValues = @{}
        foreach ($f in $analysis.findings | Where-Object decision -eq 'replace') {
            $workspaceValues[$f.replacementName] = switch ($f.kind) {
                'email' { 'soc@contoso.example' }
                'url' { if ($f.value -match 'vault') { 'https://kv-contoso.vault.azure.net' } else { $f.value } }
                'guid' { 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
                'name' { 'contoso-value' }
                default { $f.value -replace 'source','contoso' }
            }
        }
        $workspace = New-LogicRipperTargetWorkspace -BasePath $Base -DisplayName 'Contoso Production' -Values $workspaceValues
        $binding = New-LogicRipperBinding -BasePath $Base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -Values @{}
        $generated = New-LogicRipperCodeView -BasePath $Base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -BindingId $binding.BindingId
        $json = Get-Content -Raw $generated.Path
        $json | Should -Match 'graph.microsoft.com'
        $json | Should -Match 'soc@contoso.example'
        $json | Should -Not -Match 'source.example'
    }

    It 'blocks generation when a replacement value is missing' {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $CodeView
        foreach ($f in $analysis.findings) {
            Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision replace -ReplacementName $f.replacementName | Out-Null
        }
        $template = Save-LogicRipperTemplate -Name 'Disable User Accounts' -Analysis $analysis -BasePath $Base
        $workspace = New-LogicRipperTargetWorkspace -BasePath $Base -DisplayName 'Empty' -Values @{}
        $binding = New-LogicRipperBinding -BasePath $Base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -Values @{}
        { New-LogicRipperCodeView -BasePath $Base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -BindingId $binding.BindingId } | Should -Throw -ExpectedMessage '*Needs review*'
    }

    It 'renames a saved template' {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $CodeView
        foreach ($f in $analysis.findings) { Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision preserve | Out-Null }
        $template = Save-LogicRipperTemplate -Name 'Old Name' -Analysis $analysis -BasePath $Base
        Rename-LogicRipperTemplate -TemplateId $template.TemplateId -Name 'New Name' -BasePath $Base | Out-Null
        (Get-LogicRipperTemplate -TemplateId $template.TemplateId -BasePath $Base).name | Should -Be 'New Name'
    }

    It 'returns a simple value guide' {
        $guide = @(Get-LogicRipperValueGuide)
        $guide.value | Should -Contain 'Tenant ID'
        $guide.value | Should -Contain 'runtimeIdentityResourceId'
    }

    It 'normalises pure code view, full workflow resources and saved templates' {
        $pure = Get-LogicRipperCanonicalCodeView -CodeViewJson $CodeView
        $resourceJson = Get-Content -Raw "$PSScriptRoot\..\Fixtures\disable-user-accounts.workflow.json"
        $resource = Get-LogicRipperCanonicalCodeView -CodeViewJson $resourceJson
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $CodeView
        foreach ($f in $analysis.findings) { Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision preserve | Out-Null }
        $template = Save-LogicRipperTemplate -Name 'Disable User Accounts' -Analysis $analysis -BasePath $Base
        $saved = Get-LogicRipperCanonicalCodeView -InputObject (Get-LogicRipperTemplate -TemplateId $template.TemplateId -BasePath $Base)

        $pure.sourceKind | Should -Be 'pureCodeView'
        $resource.sourceKind | Should -Be 'workflowResource'
        $saved.sourceKind | Should -Be 'savedTemplate'
        $pure.codeViewHash | Should -Be $saved.codeViewHash
    }

    It 'uses explicit placeholders and fails when any remain unresolved' {
        $placeholderCodeView = @{
            '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
            contentVersion = '1.0.0.0'
            parameters = @{}
            triggers = @{ manual = @{ type = 'Request'; kind = 'Http'; inputs = @{ schema = @{} } } }
            actions = @{ Notify = @{ type = 'Http'; inputs = @{ method = 'POST'; uri = 'https://graph.microsoft.com/v1.0/users'; body = @{ email = '{{notificationEmail}}' } }; runAfter = @{} } }
            outputs = @{}
        } | ConvertTo-Json -Depth 20
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $placeholderCodeView
        $template = Save-LogicRipperTemplate -Name 'Placeholder Template' -Analysis $analysis -BasePath $Base
        $workspace = New-LogicRipperTargetWorkspace -BasePath $Base -DisplayName 'Contoso Production' -Values @{}
        $binding = New-LogicRipperBinding -BasePath $Base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -Values @{}
        { New-LogicRipperCodeView -BasePath $Base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -BindingId $binding.BindingId } | Should -Throw -ExpectedMessage '*missing value*'
    }

    It 'maps $connections values from a saved binding' {
        $connectionCodeView = @{
            '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
            contentVersion = '1.0.0.0'
            parameters = @{
                '$connections' = @{
                    type = 'Object'
                    value = @{
                        azuresentinel = @{
                            connectionId = '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-source/providers/Microsoft.Web/connections/azuresentinel-source'
                            connectionName = 'azuresentinel-source'
                            id = '/subscriptions/22222222-2222-2222-2222-222222222222/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel'
                        }
                    }
                }
            }
            triggers = @{ Incident = @{ type = 'ApiConnectionWebhook'; inputs = @{ host = @{ connection = @{ name = "@parameters('$connections')['azuresentinel']['connectionId']" } }; path = '/incident' } } }
            actions = @{ Comment = @{ type = 'ApiConnection'; inputs = @{ host = @{ connection = @{ name = "@parameters('$connections')['azuresentinel']['connectionId']" } }; method = 'post'; path = '/comments' }; runAfter = @{} } }
            outputs = @{}
        } | ConvertTo-Json -Depth 30
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $connectionCodeView
        foreach ($f in $analysis.findings) {
            $name = switch ($f.kind) {
                'connectorReferenceId' { 'sentinelConnectionId' }
                'connectorReferenceName' { 'sentinelConnectionName' }
                'managedApiId' { 'sentinelManagedApiId' }
                default { $f.replacementName }
            }
            Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision replace -ReplacementName $name | Out-Null
        }
        $template = Save-LogicRipperTemplate -Name 'Connection Template' -Analysis $analysis -BasePath $Base
        $workspace = New-LogicRipperTargetWorkspace -BasePath $Base -DisplayName 'Contoso Production' -Values @{}
        $binding = New-LogicRipperBinding -BasePath $Base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -Values @{
            sentinelConnectionId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso/providers/Microsoft.Web/connections/azuresentinel-contoso'
            sentinelConnectionName = 'azuresentinel-contoso'
            sentinelManagedApiId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel'
        }
        $generated = New-LogicRipperCodeView -BasePath $Base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -BindingId $binding.BindingId
        $json = Get-Content -Raw $generated.Path
        $json | Should -Match 'azuresentinel-contoso'
        $json | Should -Not -Match 'azuresentinel-source'
        $json | Should -Not -Match '22222222-2222-2222-2222-222222222222'
    }
}
