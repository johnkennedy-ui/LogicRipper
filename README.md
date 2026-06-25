# Logic Ripper

## Run these Alex

```bash
git clone https://github.com/johnkennedy-ui/LogicRipper.git
cd LogicRipper
bash ./scripts/install-ubuntu.sh
~/.local/bin/logic-ripper status
```

Logic Ripper is a local Logic App code-view transformer. It does not log in to
Azure, discover resources, deploy anything, create ARM/Bicep, run what-if, or
validate live Azure resources.

## Supported MVP Workflow

On startup the user chooses one of two paths:

- `Import new template`
- `Export saved template`

Import path:

1. Paste a Logic App code-view JSON into the GUI.
2. Click `Analyse`.
3. Review detected customer/source-specific values.
4. Mark each detected value as `replace`, `preserve`, or `secret / do not export`.
5. Save the reviewed JSON as a named reusable local template.

Export path:

1. Select a saved template.
2. Select or create a saved Target Workspace profile.
3. Enter workspace or template-specific binding values one at a time.
4. Save the binding for that template and workspace.
5. Click `Generate`.
6. Confirm the generated code-view JSON has no unresolved placeholders or source values.
7. Copy the generated `codeview.json` from the GUI.
8. Paste it manually into the target Logic App code view.

Accepted input forms:

- Pure Logic App code-view JSON with `$schema`, `contentVersion`, `parameters`,
  `triggers`, `actions`, and optional `outputs`.
- A full `Microsoft.Logic/workflows` resource JSON, normalised down to code view.
- A saved Logic Ripper template.

Validation is code-view only:

- JSON parses.
- `triggers` and `actions` exist.
- Source values marked `replace` do not remain after generation.
- `{{placeholders}}` are resolved.
- Probable secrets are not exported.
- `$connections` values are mapped, or explicitly marked `Manual reconnect required`.

The example template is `Disable User Accounts`, a Sentinel incident response
playbook that disables one or more Entra user accounts.

## GUI

The GUI is WPF and runs on Windows:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\src\LogicRipper.Gui\Start-LogicRipper.ps1
```

The Ubuntu install command is included so a VM can install PowerShell and run
tests/status checks, but the product UX is the GUI.

## Tests

```bash
~/.local/bin/logic-ripper-test
```

or:

```powershell
.\build.ps1 -Test
```

## Out Of Scope

- Azure source discovery
- Azure login
- subscription/resource-group browsing
- Logic App export from Azure
- direct deployment
- ARM/Bicep output
- Azure what-if
- live target validation
- broad connector automation
