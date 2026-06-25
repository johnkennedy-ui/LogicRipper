# Logic Ripper

## Run these Alex

```bash
git clone https://github.com/johnkennedy-ui/LogicRipper.git
cd LogicRipper
bash ./scripts/install-ubuntu.sh
~/.local/bin/logic-ripper status
```

LogicRipper is an offline local code-view transformer. It does not authenticate
to Azure, Microsoft Graph, Defender, Intune or any customer environment. It
does not connect to any API.

All target values are manually supplied and stored locally. Generated code view
must be reviewed and manually pasted into the target Logic App by the operator.

## Supported MVP Workflow

On startup the GUI offers two paths:

- `Import new template`
- `Export saved template`

Import path:

1. `Paste code view`
2. `Analyse local JSON`
3. Mark detected local JSON values as `replace`, `preserve`, or `secret / do not export`.
4. `Save local template`

Export path:

1. Select one saved local template.
2. Select or create `Target workspace variables`.
3. Enter `Binding values` for that template and workspace.
4. Save the binding.
5. `Generate code view`
6. `Copy generated JSON`
7. Manually paste the generated JSON into the target Logic App code view.

Accepted local input forms:

- Pure Logic App code-view JSON with `$schema`, `contentVersion`, `parameters`,
  `triggers`, `actions`, and optional `outputs`.
- A full `Microsoft.Logic/workflows` JSON document, normalised down to local code view.
- A saved Logic Ripper template.

Local validation only checks:

- JSON parses.
- `triggers` exists.
- `actions` exists.
- Source values marked `replace` do not remain after generation.
- `{{tokens}}` are resolved.
- Probable secrets are not exported.
- `$connections` connector reference values are supplied or explicitly marked
  `Manual edit required`.

## GUI

The GUI is WPF and runs on Windows:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\src\LogicRipper.Gui\Start-LogicRipper.ps1
```

The Ubuntu install command is included so a VM can install PowerShell and run
tests/status checks. The product workflow is the GUI.

## Tests

```bash
~/.local/bin/logic-ripper-test
```

or:

```powershell
.\build.ps1 -Test
```

## Limitations

- Does not verify target IDs.
- Does not create connectors.
- Does not authorise OAuth connectors.
- Does not deploy.
- Does not check permissions.
- Does not guarantee the workflow will run.
- Only guarantees local JSON transformation and configured source-value replacement.

## Out Of Scope

- Any live API call.
- Cloud authentication.
- Live source discovery.
- Live target/resource validation.
- Connector creation.
- Connector authorisation.
- Direct deployment.
- ARM/Bicep output.
- What-if.
