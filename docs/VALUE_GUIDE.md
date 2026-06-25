# Logic Ripper Value Guide

The operator should not re-enter customer-wide details every time. Save these
once in the Target Workspace profile:

- Tenant ID
- Subscription ID
- Resource group name
- Azure location
- Log Analytics workspace name
- Log Analytics workspace resource ID
- Log Analytics workspace customer/workspace ID when a connector needs it
- Default Logic App resource group
- Default naming prefix/suffix
- Default tags
- Deployment authentication type and non-secret references
- Default runtime identity
- Existing API connection mappings
- Key Vault references
- Function App mappings

Save these per template + workspace in the Template Binding:

- Target Logic App name
- Template parameter values
- Connector mappings that differ from workspace defaults
- Runtime identity override
- Function App mappings that differ from workspace defaults
- Key Vault mappings that differ from workspace defaults
- Role-assignment choices
- Values requiring interactive authorisation

## Identity fields

For a user-assigned managed identity:

1. Go to Azure Portal -> Managed Identities.
2. Open the customer SOAR identity.
3. Copy Resource ID from Properties.
4. Copy Client ID from Overview.
5. Copy Object/principal ID from Overview.

For a service principal:

1. Go to Microsoft Entra ID -> App registrations.
2. Open the app registration.
3. Copy Application/client ID.
4. Go to Enterprise applications -> find the service principal.
5. Copy Object ID.
6. Store credentials only as references: certificate thumbprint, Key Vault URI,
   Windows Credential Manager name, or environment variable name.

For Sentinel workspace IDs:

1. Go to Azure Portal -> Microsoft Sentinel.
2. Select the customer workspace.
3. Open the underlying Log Analytics workspace.
4. Copy Resource ID from Properties.
5. Copy Workspace ID/customer ID from Agents or Properties when required.

For OAuth/API connections:

1. Go to Azure Portal -> Resource groups.
2. Open the target Logic App/API connection resource group.
3. Open API Connections.
4. Authorise the required connection or select an existing authorised one.
5. Copy the connection Resource ID into the binding connector mapping.
