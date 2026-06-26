#Requires -Version 7.4
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $env:DOTNET_CLI_HOME) {
    $env:DOTNET_CLI_HOME = Join-Path ([IO.Path]::GetTempPath()) 'logic-ripper-dotnet-home'
    New-Item -ItemType Directory -Path $env:DOTNET_CLI_HOME -Force | Out-Null
}
Import-Module (Join-Path $repoRoot 'src/LogicRipper/LogicRipper.psd1') -Force

$script:Passed = 0
$script:Failed = 0

function New-TestBase {
    Join-Path ([IO.Path]::GetTempPath()) ("logic-ripper-test-" + [guid]::NewGuid().ToString('n'))
}

function Get-TestCodeView {
    Get-Content -Raw (Join-Path $repoRoot 'tests/Fixtures/disable-user-accounts.workflow.json') |
        ConvertFrom-Json |
        Select-Object -ExpandProperty properties |
        Select-Object -ExpandProperty definition |
        ConvertTo-Json -Depth 100
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-Contains {
    param([object[]]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -notcontains $Expected) { throw "$Message Missing '$Expected'." }
}

function Assert-Match {
    param([string]$Actual, [string]$Pattern, [string]$Message)
    if ($Actual -notmatch $Pattern) { throw "$Message Pattern '$Pattern' was not found." }
}

function Assert-NotMatch {
    param([string]$Actual, [string]$Pattern, [string]$Message)
    if ($Actual -match $Pattern) { throw "$Message Pattern '$Pattern' was found." }
}

function Assert-ThrowsLike {
    param([scriptblock]$Script, [string]$Pattern, [string]$Message)
    try {
        & $Script
    } catch {
        if ($_.Exception.Message -like $Pattern) { return }
        throw "$Message Wrong exception: $($_.Exception.Message)"
    }
    throw "$Message No exception was thrown."
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Script)
    try {
        & $Script
        $script:Passed++
        Write-Host "[PASS] $Name"
    } catch {
        $script:Failed++
        Write-Host "[FAIL] $Name"
        Write-Host "       $($_.Exception.Message)"
    }
}

Invoke-Test 'manifest does not require cloud PowerShell modules' {
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $repoRoot 'src/LogicRipper/LogicRipper.psd1')
    $required = @()
    if ($manifest.ContainsKey('RequiredModules')) { $required += @($manifest.RequiredModules) }
    if ($manifest.ContainsKey('NestedModules')) { $required += @($manifest.NestedModules) }
    Assert-NotMatch (($required | ConvertTo-Json -Depth 10) ?? '') '(^|[^A-Za-z0-9.])(Az|Microsoft\.Graph|ExchangeOnlineManagement)([^A-Za-z0-9.]|$)' 'Manifest must not require cloud modules.'
}

Invoke-Test 'production code has no banned live API commands' {
    $productionRoots = @((Join-Path $repoRoot 'src'), (Join-Path $repoRoot 'scripts'))
    $productionFiles = foreach ($root in $productionRoots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Recurse -File |
                Where-Object { $_.Extension -in @('.ps1','.psm1','.psd1','.xaml','.axaml','.sh','.cs','.csproj') }
        }
    }
    $productionFiles += Get-Item -LiteralPath (Join-Path $repoRoot 'build.ps1')
    $bannedPatterns = @(
        'Connect-AzAccount',
        '\bGet-Az[A-Za-z0-9]*\b',
        '\bNew-Az[A-Za-z0-9]*\b',
        '\bSet-Az[A-Za-z0-9]*\b',
        '\bRemove-Az[A-Za-z0-9]*\b',
        'Connect-MgGraph',
        '\bGet-Mg[A-Za-z0-9]*\b',
        'Invoke-MgGraphRequest',
        'Invoke-RestMethod',
        'Invoke-WebRequest',
        '\baz\s+login\b',
        '\baz\s+account\b',
        '\baz\s+deployment\b',
        'graph\.microsoft\.com',
        'management\.azure\.com'
    )
    $matches = foreach ($file in $productionFiles) {
        $text = Get-Content -Raw -LiteralPath $file.FullName
        foreach ($pattern in $bannedPatterns) {
            if ($text -match $pattern) { "$($file.FullName.Substring($repoRoot.Path.Length + 1)) -> $pattern" }
        }
    }
    Assert-True (@($matches).Count -eq 0) ("Banned live command strings found: " + (@($matches) -join '; '))
}

Invoke-Test 'analyses pasted code-view JSON and detects customer-specific values' {
    $analysis = Invoke-LogicRipperAnalysis -CodeViewJson (Get-TestCodeView)
    Assert-True (@($analysis.findings).Count -gt 0) 'Expected findings.'
    Assert-Equal $analysis.status 'Needs review' 'Analysis status mismatch.'
    Assert-Contains $analysis.findings.kind 'email' 'Expected email finding.'
    Assert-Contains $analysis.findings.kind 'azureResourceId' 'Expected resource ID finding.'
}

Invoke-Test 'Avalonia source tree is covered by the offline-only guard' {
    $avaloniaRoot = Join-Path $repoRoot 'src/LogicRipper.Gui.Avalonia'
    Assert-True (Test-Path -LiteralPath $avaloniaRoot) 'Avalonia GUI source tree is missing.'
    $guardText = Get-Content -Raw -LiteralPath $PSCommandPath
    Assert-Match $guardText '\.axaml' 'Offline guard must scan Avalonia AXAML files.'
    Assert-Match $guardText '\.cs' 'Offline guard must scan Avalonia C# files.'
    Assert-Match $guardText '\.csproj' 'Offline guard must scan Avalonia project files.'
}

Invoke-Test 'Avalonia project builds on Ubuntu when dotnet SDK is available' {
    Assert-True ($null -ne (Get-Command dotnet -ErrorAction SilentlyContinue)) 'dotnet SDK is required for the Avalonia build test.'
    & dotnet build (Join-Path $repoRoot 'src/LogicRipper.Gui.Avalonia/LogicRipper.Gui.Avalonia.csproj') -c Release
    Assert-Equal $LASTEXITCODE 0 'dotnet build failed.'
}

Invoke-Test 'Linux GUI publish succeeds and version command runs' {
    Assert-True ($null -ne (Get-Command dotnet -ErrorAction SilentlyContinue)) 'dotnet SDK is required for the Linux publish test.'
    & bash (Join-Path $repoRoot 'scripts/build-ubuntu-gui.sh')
    Assert-Equal $LASTEXITCODE 0 'Linux GUI publish failed.'
    $gui = Join-Path $repoRoot 'artifacts/LogicRipper.Gui-linux-x64/LogicRipper.Gui'
    Assert-True (Test-Path -LiteralPath $gui) 'Published GUI binary missing.'
    $version = & $gui --version
    Assert-Equal $LASTEXITCODE 0 'logic-ripper-gui --version failed.'
    Assert-Match ($version -join "`n") 'LogicRipper\.Gui' 'Version output mismatch.'
}

Invoke-Test 'GUI backend command bridge can analyse save load and generate fixture code view' {
    Assert-True ($null -ne (Get-Command dotnet -ErrorAction SilentlyContinue)) 'dotnet SDK is required for the GUI backend bridge test.'
    $pwshPath = Join-Path $PSHOME 'pwsh'
    Assert-True (Test-Path -LiteralPath $pwshPath) 'PowerShell is required for the GUI backend bridge test.'
    $gui = Join-Path $repoRoot 'artifacts/LogicRipper.Gui-linux-x64/LogicRipper.Gui'
    if (-not (Test-Path -LiteralPath $gui)) { & bash (Join-Path $repoRoot 'scripts/build-ubuntu-gui.sh') }
    $base = New-TestBase
    $old = $env:LOGIC_RIPPER_CLI
    if ($old) {
        $wrapper = $old
    } else {
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        $wrapper = Join-Path $base 'logic-ripper'
        $cli = [string](Join-Path $repoRoot 'src/LogicRipper.Cli/Start-LogicRipperCli.ps1')
        Set-Content -LiteralPath $wrapper -Encoding utf8 -Value @(
            '#!/usr/bin/env bash',
            'set -euo pipefail',
            ('exec "{0}" -NoLogo -NoProfile -File "{1}" "$@"' -f $pwshPath, $cli)
        )
        & chmod 755 $wrapper
    }
    try {
        $env:LOGIC_RIPPER_CLI = $wrapper
        & $gui --bridge-smoke --fixture (Join-Path $repoRoot 'tests/Fixtures/disable-user-accounts.workflow.json') --base-path $base
        Assert-Equal $LASTEXITCODE 0 'GUI backend bridge smoke failed.'
        Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $base 'Templates') -Filter '*.json').Count -gt 0) 'Bridge did not save/load template data.'
        Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $base 'Workspaces') -Filter '*.json').Count -gt 0) 'Bridge did not save/load workspace data.'
        Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $base 'Bindings') -Filter '*.json').Count -gt 0) 'Bridge did not save/load binding data.'
        Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $base 'Generated') -Filter 'codeview.json' -Recurse).Count -gt 0) 'Bridge did not generate code view.'
    } finally {
        $env:LOGIC_RIPPER_CLI = $old
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Invoke-Test 'blocks template save until every finding is reviewed' {
    $base = New-TestBase
    try {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson (Get-TestCodeView)
        Assert-ThrowsLike { Save-LogicRipperTemplate -Name 'Disable User Accounts' -Analysis $analysis -BasePath $base } '*Needs review*' 'Unreviewed findings should block template saving.'
    } finally {
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Invoke-Test 'lets the user mark findings replace or preserve and save a template' {
    $base = New-TestBase
    try {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson (Get-TestCodeView)
        foreach ($f in $analysis.findings) {
            $decision = if ($f.value -match 'graph.microsoft.com|workflowdefinition.json') { 'preserve' } else { 'replace' }
            Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision $decision -ReplacementName $f.replacementName | Out-Null
        }
        $template = Save-LogicRipperTemplate -Name 'Disable User Accounts' -Purpose 'Disable Entra users from Sentinel incident' -Analysis $analysis -BasePath $base
        Assert-Equal (Get-LogicRipperTemplate -TemplateId $template.TemplateId -BasePath $base).name 'Disable User Accounts' 'Template was not saved.'
    } finally {
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Invoke-Test 'saves secret decisions but blocks generation until the value is removed or replaced safely' {
    $base = New-TestBase
    try {
        $secretCodeView = (Get-Content -Raw (Join-Path $repoRoot 'tests/Fixtures/secret.workflow.json') | ConvertFrom-Json).properties.definition | ConvertTo-Json -Depth 100
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $secretCodeView
        foreach ($f in $analysis.findings) { Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision secret | Out-Null }
        $template = Save-LogicRipperTemplate -Name 'Secret Template' -Analysis $analysis -BasePath $base
        $workspace = New-LogicRipperTargetWorkspace -BasePath $base -DisplayName 'Contoso Production' -Values @{}
        $binding = New-LogicRipperBinding -BasePath $base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -Values @{}
        Assert-ThrowsLike { New-LogicRipperCodeView -BasePath $base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -BindingId $binding.BindingId } '*secret*' 'Secret findings should block generation.'
    } finally {
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Invoke-Test 'saves workspace values without raw secrets' {
    $base = New-TestBase
    try {
        $workspace = New-LogicRipperTargetWorkspace -BasePath $base -DisplayName 'Contoso Production' -Values @{
            tenantId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            subscriptionId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
            workspaceResourceId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso/providers/Microsoft.OperationalInsights/workspaces/law-contoso'
        }
        Assert-Equal (Get-LogicRipperTargetWorkspace -ProfileId $workspace.ProfileId -BasePath $base).displayName 'Contoso Production' 'Workspace was not saved.'
        Assert-ThrowsLike { New-LogicRipperTargetWorkspace -BasePath $base -DisplayName Bad -Values @{ password = 'do-not-store' } } '*' 'Raw secret should be rejected.'
    } finally {
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Invoke-Test 'saves template-to-workspace bindings and generates copy-pasteable code-view JSON' {
    $base = New-TestBase
    try {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson (Get-TestCodeView)
        foreach ($f in $analysis.findings) {
            if ($f.value -match 'graph.microsoft.com|workflowdefinition.json') {
                Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision preserve | Out-Null
            } else {
                Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision replace -ReplacementName $f.replacementName | Out-Null
            }
        }
        $template = Save-LogicRipperTemplate -Name 'Disable User Accounts' -Analysis $analysis -BasePath $base
        $workspaceValues = @{}
        foreach ($f in $analysis.findings | Where-Object decision -eq 'replace') {
            $workspaceValues[$f.replacementName] = switch ($f.kind) {
                'email' { 'soc@contoso.example' }
                'guid' { 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
                'name' { 'contoso-value' }
                default { $f.value -replace 'source','contoso' }
            }
        }
        $workspace = New-LogicRipperTargetWorkspace -BasePath $base -DisplayName 'Contoso Production' -Values $workspaceValues
        $binding = New-LogicRipperBinding -BasePath $base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -Values @{}
        $generated = New-LogicRipperCodeView -BasePath $base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -BindingId $binding.BindingId
        $json = Get-Content -Raw $generated.Path
        Assert-Match $json 'graph.microsoft.com' 'Functional endpoint should remain.'
        Assert-Match $json 'soc@contoso.example' 'Target notification email missing.'
        Assert-NotMatch $json 'source.example' 'Source email remained.'
    } finally {
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Invoke-Test 'blocks generation when a replacement value is missing' {
    $base = New-TestBase
    try {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson (Get-TestCodeView)
        foreach ($f in $analysis.findings) { Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision replace -ReplacementName $f.replacementName | Out-Null }
        $template = Save-LogicRipperTemplate -Name 'Disable User Accounts' -Analysis $analysis -BasePath $base
        $workspace = New-LogicRipperTargetWorkspace -BasePath $base -DisplayName 'Empty' -Values @{}
        $binding = New-LogicRipperBinding -BasePath $base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -Values @{}
        Assert-ThrowsLike { New-LogicRipperCodeView -BasePath $base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -BindingId $binding.BindingId } '*Needs review*' 'Missing replacement value should block generation.'
    } finally {
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Invoke-Test 'renames a saved template' {
    $base = New-TestBase
    try {
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson (Get-TestCodeView)
        foreach ($f in $analysis.findings) { Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision preserve | Out-Null }
        $template = Save-LogicRipperTemplate -Name 'Old Name' -Analysis $analysis -BasePath $base
        Rename-LogicRipperTemplate -TemplateId $template.TemplateId -Name 'New Name' -BasePath $base | Out-Null
        Assert-Equal (Get-LogicRipperTemplate -TemplateId $template.TemplateId -BasePath $base).name 'New Name' 'Template rename failed.'
    } finally {
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Invoke-Test 'returns a simple value guide' {
    $guide = @(Get-LogicRipperValueGuide)
    Assert-Contains $guide.value 'Tenant ID' 'Guide should include Tenant ID.'
    Assert-Contains $guide.value 'runtimeIdentityResourceId' 'Guide should include runtimeIdentityResourceId.'
}

Invoke-Test 'normalises pure code view, full workflow resources and saved templates' {
    $base = New-TestBase
    try {
        $codeView = Get-TestCodeView
        $pure = Get-LogicRipperCanonicalCodeView -CodeViewJson $codeView
        $resourceJson = Get-Content -Raw (Join-Path $repoRoot 'tests/Fixtures/disable-user-accounts.workflow.json')
        $resource = Get-LogicRipperCanonicalCodeView -CodeViewJson $resourceJson
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $codeView
        foreach ($f in $analysis.findings) { Set-LogicRipperFindingDecision -Analysis $analysis -FindingId $f.id -Decision preserve | Out-Null }
        $template = Save-LogicRipperTemplate -Name 'Disable User Accounts' -Analysis $analysis -BasePath $base
        $saved = Get-LogicRipperCanonicalCodeView -InputObject (Get-LogicRipperTemplate -TemplateId $template.TemplateId -BasePath $base)
        Assert-Equal $pure.sourceKind 'pureCodeView' 'Pure source kind mismatch.'
        Assert-Equal $resource.sourceKind 'workflowResource' 'Resource source kind mismatch.'
        Assert-Equal $saved.sourceKind 'savedTemplate' 'Saved source kind mismatch.'
        Assert-Equal $pure.codeViewHash $saved.codeViewHash 'Saved template hash mismatch.'
    } finally {
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Invoke-Test 'uses explicit placeholders and fails when any remain unresolved' {
    $base = New-TestBase
    try {
        $placeholderCodeView = @{
            '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
            contentVersion = '1.0.0.0'
            parameters = @{}
            triggers = @{ manual = @{ type = 'Request'; kind = 'Http'; inputs = @{ schema = @{} } } }
            actions = @{ Notify = @{ type = 'Http'; inputs = @{ method = 'POST'; uri = 'https://graph.microsoft.com/v1.0/users'; body = @{ email = '{{notificationEmail}}' } }; runAfter = @{} } }
            outputs = @{}
        } | ConvertTo-Json -Depth 20
        $analysis = Invoke-LogicRipperAnalysis -CodeViewJson $placeholderCodeView
        $template = Save-LogicRipperTemplate -Name 'Placeholder Template' -Analysis $analysis -BasePath $base
        $workspace = New-LogicRipperTargetWorkspace -BasePath $base -DisplayName 'Contoso Production' -Values @{}
        $binding = New-LogicRipperBinding -BasePath $base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -Values @{}
        Assert-ThrowsLike { New-LogicRipperCodeView -BasePath $base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -BindingId $binding.BindingId } '*missing value*' 'Unresolved placeholder should block generation.'
    } finally {
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Invoke-Test 'maps $connections values from a saved binding' {
    $base = New-TestBase
    try {
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
        $template = Save-LogicRipperTemplate -Name 'Connection Template' -Analysis $analysis -BasePath $base
        $workspace = New-LogicRipperTargetWorkspace -BasePath $base -DisplayName 'Contoso Production' -Values @{}
        $binding = New-LogicRipperBinding -BasePath $base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -Values @{
            sentinelConnectionId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso/providers/Microsoft.Web/connections/azuresentinel-contoso'
            sentinelConnectionName = 'azuresentinel-contoso'
            sentinelManagedApiId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel'
        }
        $generated = New-LogicRipperCodeView -BasePath $base -TemplateId $template.TemplateId -ProfileId $workspace.ProfileId -BindingId $binding.BindingId
        $json = Get-Content -Raw $generated.Path
        Assert-Match $json 'azuresentinel-contoso' 'Target connector reference missing.'
        Assert-NotMatch $json 'azuresentinel-source' 'Source connector reference remained.'
        Assert-NotMatch $json '22222222-2222-2222-2222-222222222222' 'Source subscription ID remained.'
    } finally {
        if (Test-Path $base) { Remove-Item $base -Recurse -Force }
    }
}

Write-Host "Tests passed: $script:Passed"
if ($script:Failed -gt 0) {
    Write-Host "Tests failed: $script:Failed"
    exit 1
}
