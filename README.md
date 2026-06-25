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

1. Paste a Logic App code-view JSON into the GUI.
2. Click `Analyse`.
3. Review detected customer/source-specific values.
4. Mark each detected value as `replace`, `preserve`, or `secret / do not export`.
5. Save the reviewed JSON as a named reusable local template.
6. Create or select a saved Target Workspace profile.
7. Enter missing template/workspace values one at a time.
8. Click `Generate`.
9. Copy the generated `codeview.json` from the GUI.
10. Paste it manually into the target Logic App code view.

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
