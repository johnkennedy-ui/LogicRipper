# Security Notes

- Logic Ripper is local-only. It does not log in to Azure or deploy resources.
- Values marked `secret / do not export` block template saving and generation.
- Workspace profiles and bindings reject likely raw secrets.
- The generated output is code-view JSON only.
- If a detected value is still marked `review`, generation is blocked.
- The operator remains responsible for manually pasting the generated JSON into
  the target Logic App and authorising any connectors in Azure.
