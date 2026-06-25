# Logic Ripper

## Run these Alex

```bash
git clone https://github.com/johnkennedy-ui/LogicRipper.git
cd LogicRipper
bash ./scripts/install-ubuntu.sh
~/.local/bin/logic-ripper status
```

Logic Ripper is a PowerShell 7.4 Windows desktop utility and CLI module for
ripping Microsoft Sentinel playbooks and Azure Consumption Logic Apps into a
local, sanitised template library, then exporting clean `codeview.json` files
for saved target workspaces.

The MVP supports `Microsoft.Logic/workflows` Consumption Logic Apps. Logic Apps
Standard resources are detected and reported as unsupported.

## Install for local development

```powershell
Import-Module .\src\LogicRipper\LogicRipper.psd1 -Force
```

## Ubuntu VM one-shot install and startup

The WPF GUI is Windows-only. On Ubuntu, use the CLI wrapper installed by the
one-shot installer.

Install from a checkout:

```bash
git clone https://github.com/johnkennedy-ui/LogicRipper.git
cd LogicRipper
bash ./scripts/install-ubuntu.sh
```

Start:

```bash
~/.local/bin/logic-ripper status
```

Export a saved template as Logic App code-view JSON:

```bash
~/.local/bin/logic-ripper export-codeview -TemplateId <template-id> -TargetWorkspaceProfileId <profile-id> -BindingId <binding-id>
```

Show the simplified value guide for the form:

```bash
~/.local/bin/logic-ripper guide -TemplateId <template-id>
```

Run tests:

```bash
~/.local/bin/logic-ripper-test
```

The installer is user-local and does not require `sudo`. It downloads the
official PowerShell 7.4 package, extracts it under
`~/.local/share/logic-ripper/powershell`, installs Pester under
`~/.local/share/logic-ripper/modules`, and creates the wrapper commands in
`~/.local/bin`.

## GUI

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\src\LogicRipper.Gui\Start-LogicRipper.ps1
```

The GUI is a thin WPF wrapper over the module commands. The primary export
button writes a `codeview.json` file suitable for Logic App code-view reuse.
Deployment remains a separate explicit action.

## CLI example

```powershell
$base = Join-Path $env:TEMP 'logic-ripper-demo'

$source = @{
  TenantId = '11111111-1111-1111-1111-111111111111'
  SubscriptionId = '22222222-2222-2222-2222-222222222222'
  ResourceGroupName = 'rg-source-sentinel'
  Location = 'uksouth'
  WorkspaceResourceId = '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-source-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-source'
  WorkspaceCustomerId = '33333333-3333-3333-3333-333333333333'
}

$template = Import-LogicRipperWorkflow `
  -WorkflowPath .\tests\Fixtures\disable-user-accounts.workflow.json `
  -BasePath $base `
  -DisplayName 'Disable User Accounts' `
  -Description 'Disable Entra users identified in a Sentinel incident' `
  -Category 'Identity Response' `
  -SourceContext $source

$workspace = New-LogicRipperTargetWorkspace `
  -BasePath $base `
  -CustomerDisplayName 'Contoso' `
  -EnvironmentName 'Production' `
  -TenantId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' `
  -SubscriptionId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' `
  -ResourceGroupName 'rg-contoso-sentinel-prod' `
  -Location 'uksouth' `
  -WorkspaceName 'law-contoso-sentinel-prod' `
  -WorkspaceResourceId '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso-sentinel-prod/providers/Microsoft.OperationalInsights/workspaces/law-contoso-sentinel-prod' `
  -DefaultNamingPrefix 'la-contoso' `
  -DefaultNamingSuffix 'prod' `
  -RuntimeIdentityType UserAssigned `
  -RuntimeIdentity @{
    resourceId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso-sentinel-prod/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-contoso-soar-prod'
    clientId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
    principalId = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
  }

$binding = New-LogicRipperTemplateBinding `
  -BasePath $base `
  -TemplateId $template.TemplateId `
  -TargetWorkspaceProfileId $workspace.ProfileId `
  -TargetLogicAppName 'la-contoso-disable-users-prod' `
  -TemplateParameterValues @{ notificationAddress = 'soc@contoso.example' } `
  -RuntimeIdentityOverride @{
    type = 'UserAssigned'
    settings = @{
      resourceId = '/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso-sentinel-prod/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-contoso-soar-prod'
    }
  }

Export-LogicRipperCodeView `
  -BasePath $base `
  -TemplateId $template.TemplateId `
  -TargetWorkspaceProfileId $workspace.ProfileId `
  -BindingId $binding.BindingId
```

## Tests

```powershell
.\build.ps1 -Test
```

## Known MVP limitations

- Azure live discovery is represented by module seams and fixtures in this MVP;
  production Azure calls should use Az or ARM REST with the same connection-ID
  extraction rules retained from upstream.
- The primary operator output is `codeview.json`; ARM package generation remains
  available for validation/packaging but is no longer the simplest path.
- Value collection guidance is available in `docs/VALUE_GUIDE.md` and through
  `logic-ripper guide`.
- User OAuth connector authorisations are never copied. They are emitted as
  post-deployment authorisation actions or require a target connection mapping.
- Function App source code is not exported; Function Apps are recorded as
  external prerequisites.
- ARM what-if and live resource existence validation are marked offline unless
  the operator runs with target Azure access.
