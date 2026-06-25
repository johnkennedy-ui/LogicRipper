# Security Notes

- Logic Ripper is local-only. It does not log in to any cloud service or deploy resources.
- Values marked `secret / do not export` block generation.
- Workspace profiles and bindings reject likely raw secrets.
- The generated output is code-view JSON only.
- If a detected value is still marked `review`, generation is blocked.
- The operator remains responsible for manually pasting the generated JSON into
  the target Logic App and handling connector setup outside Logic Ripper.
