# Upstream provenance

Verified on 2026-06-25.

## Primary implementation base

- Repository: `https://github.com/noodlemctwoodle/sentinel.blog`
- Commit used: `2c533501f8f5f6220b9718e8c670897af6ee024b`
- File retained: `MicrosoftSentinel/PowerShell/Playbooks/Invoke-SentinelPlaybookManager/Invoke-SentinelPlaybookManager.ps1`
- Licence: MIT, copyright 2025 noodlemctwoodle
- Local copy: `vendor/noodlemctwoodle-sentinel.blog/Invoke-SentinelPlaybookManager.ps1`

Retained or adapted behaviours:

- `Invoke-TemplateSanitise`: resource API-version normalisation, managed API
  ID normalisation, `parameterValueType: Alternative` for supported managed
  identity connectors, workflow `$connections` normalisation, dependency
  shaping, and workflow parameter passthrough.
- `New-ParameterFile`: ARM parameter-file generation pattern.
- Metadata extraction concepts for trigger type, entities, connector count,
  post-deployment actions and readiness status.

Modified in Logic Ripper:

- Split into testable module commands instead of one monolithic script.
- Deployment is separated from generation and not triggered by package creation.
- Sanitisation classifies source identifiers instead of blindly removing GUIDs.
- Secret scanning is a blocking validation step.
- Local reusable template library, target workspace profiles, and template
  bindings are stored as JSON with atomic writes.

## Secondary implementation and test reference

- Repository: `https://github.com/jeffhollan/LogicAppTemplateCreator`
- Commit used: `9c5dee9fb56543ce37b65659e7c5073d4075cc68`
- Licence: MIT, copyright 2016 Jeff Hollan
- Local retained reference files:
  - `vendor/jeffhollan-LogicAppTemplateCreator/TemplateGenerator.cs`
  - `vendor/jeffhollan-LogicAppTemplateCreator/ParamGenerator.cs`

Retained or adapted behaviours:

- Exact `$connections` extraction from workflow parameters.
- Managed identity handling for system-assigned and user-assigned identities.
- OAuth connection handling as a target-side authorisation problem.
- Function App ID and hostname parameterisation patterns.
- Parameter-file creation behaviour for secure and ordinary parameters.

## Compatibility reference

- Repository: `https://github.com/Azure/Azure-Sentinel`
- Commit recorded: `94b42600709b37e26b2955a8f8b4ed3e5a56f997`
- Reference area: `Tools/Playbook-ARM-Template-Generator`
- Licence: MIT under the Azure/Azure-Sentinel repository notices.

The official repository was used as a compatibility reference only. The MVP
does not copy code from it.

## Official-copy preference check

At implementation time I did not confirm an official Azure/Azure-Sentinel copy
of `Invoke-SentinelPlaybookManager.ps1` with the same or newer functionality.
The primary `noodlemctwoodle/sentinel.blog` copy was therefore retained.
