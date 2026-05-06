# TRA Post-Install Setup

This folder contains setup items that are intentionally kept outside the core `tra-package` deployment.

## Why this folder exists

The core TRA package should deploy cleanly into a new org without requiring org-specific authentication setup.

`TRA_Integration_Access.permissionset-meta.xml` is kept here because it grants access to an External Credential Principal:

```text
TRA_SF_External_Cred-SF_Tooling_Principal
```

That principal must exist in the target org before this permission set can be deployed or assigned. In a clean org, deploying this permission set before the External Credential Principal exists causes this error:

```text
PermissionSet TRA_Integration_Access invalid cross reference id
```

## Core package validation

Deploy the core package first:

```powershell
sf project deploy start --source-dir tra-package/main/default --target-org <org-alias> --test-level RunLocalTests --wait 30
```

Expected clean-org result:

```text
Components deploy successfully
All local tests pass
No TRA_Integration_Access cross-reference error
```

## Integration setup sequence

After the core package is deployed, complete the integration setup in the target org:

1. Create or deploy the required External Credential.
2. Create or deploy the required Principal.
3. Create or deploy the related Named Credential.
4. Authenticate or reconnect the Principal in the target org.
5. Deploy or assign `TRA_Integration_Access`.

## Current permission set location

```text
post-install/permissionsets/TRA_Integration_Access.permissionset-meta.xml
```

Do not move this permission set back into `tra-package` unless the External Credential and Principal metadata are also included and clean-org validation proves the full package deploys successfully.
