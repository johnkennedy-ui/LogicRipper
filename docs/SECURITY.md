# Security decisions

- Client secrets, access tokens, SAS tokens, function keys, storage connection
  strings and signed URLs are treated as blocking findings.
- Target workspace profiles store secret references only. Raw secrets are
  rejected.
- User OAuth source authorisations are never copied into generated output.
- Generation and deployment are separate. The MVP does not deploy on package
  generation.
- Diagnostic redaction can remove tokens and optionally tenant/subscription
  GUIDs.
- Runtime identity and deployment authentication are modelled separately.
