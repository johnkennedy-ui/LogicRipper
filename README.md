# LogicRipper

LogicRipper is a strictly local/offline Logic App code-view transformer and variable store. It does not authenticate to Azure, Microsoft Graph, Defender, Intune, or any customer environment, and it does not call cloud APIs.

## Ubuntu GUI

```bash
git clone https://github.com/johnkennedy-ui/LogicRipper.git
cd LogicRipper
bash ./scripts/install-ubuntu.sh
logic-ripper-gui
```

The GUI is an Avalonia desktop app for Ubuntu. It replaces the old WPF-first GUI because WPF is Windows-only and is not suitable for the Ubuntu VM deployment target.

The GUI supports the local workflow:

- paste or load Logic App code-view JSON;
- analyse local JSON;
- review detected values as Replace, Preserve, Secret, or ReviewRequired;
- save reusable local templates;
- add, edit, clone, delete, and select target workspace profiles;
- add and edit binding values one at a time;
- generate target code-view JSON;
- view validation status;
- copy generated JSON;
- save generated JSON to a file;
- open the local output folder.

## Ubuntu CLI

```bash
logic-ripper status
logic-ripper analyse -InputPath ./tests/Fixtures/disable-user-accounts.workflow.json
logic-ripper generate -TemplateId <template-id> -TargetWorkspaceProfileId <profile-id> -BindingId <binding-id>
logic-ripper-test
```

The CLI remains the local business-logic layer used by the GUI bridge.

## Build And Package

```bash
bash ./scripts/build-ubuntu-gui.sh
./artifacts/LogicRipper.Gui-linux-x64/LogicRipper.Gui --version
./artifacts/LogicRipper.Gui-linux-x64/LogicRipper.Gui
```

Expected artifacts:

- `artifacts/LogicRipper-mvp.zip`
- `artifacts/LogicRipper.Gui-linux-x64/`
- `artifacts/LogicRipper.Gui-linux-x64.tar.gz`

## Tests

```bash
./build.ps1 -Test -Zip
bash ./scripts/smoke-ubuntu-gui-visible.sh
```

The test suite includes an offline-only guard that scans production PowerShell, shell, Avalonia C#, AXAML, and project files for banned Azure, Graph, REST, web, and deployment commands.

`scripts/smoke-ubuntu-gui-visible.sh` must be run from an Ubuntu desktop session. It fails clearly when `DISPLAY` and `WAYLAND_DISPLAY` are missing, starts `logic-ripper-gui`, checks the process stays open, uses `xdotool` when available to find the `LogicRipper` window, and captures a screenshot when `gnome-screenshot` or ImageMagick `import` is installed.

## Windows

Windows GUI is not the primary MVP target. The supported MVP GUI launch path is Ubuntu with Avalonia. The old WPF GUI is retained only as legacy source and should not be treated as the product launch path.

## Limitations

- Does not verify target IDs.
- Does not create connectors.
- Does not authorise OAuth connectors.
- Does not deploy.
- Does not check permissions.
- Does not run what-if or live validation.
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
