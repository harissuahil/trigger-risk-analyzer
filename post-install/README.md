# TRA Post-Install Setup

This folder contains setup items that are intentionally kept outside the core `tra-package` deployment.

The core package should deploy cleanly into a new org. Post-install setup is only for org-specific integration work that cannot be fully completed until the target org exists.

## Current install status

The core package has been validated in a clean org with this result:

```text
Components: 95/95 deployed
Tests: 110/110 passing
Status: Succeeded
```

The remaining runtime dependency is the Tooling API connection used by `ToolingApiClient`.

The Apex code expects this Named Credential API name:

```text
SF_TOOLING
```

If `SF_TOOLING` does not exist or the user does not have access to its External Credential Principal, TRA can show this runtime error:

```text
The callout couldn't access the endpoint. You might not have the required permissions, or the named credential "SF_TOOLING" might not exist.
```

## Why this folder exists

`TRA_Integration_Access.permissionset-meta.xml` is kept here because it grants access to an External Credential Principal:

```text
TRA_SF_External_Cred-SF_Tooling_Principal
```

That principal must exist in the target org before this permission set can be deployed or assigned. In a clean org, deploying this permission set before the External Credential Principal exists causes this error:

```text
PermissionSet TRA_Integration_Access invalid cross reference id
```

For that reason, the integration permission set is intentionally outside `tra-package`.

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

## Manual post-install setup

Complete these steps after the core package is deployed.

### 1. Create the integration credential setup

In the target org, create/configure the integration pieces needed by the Tooling API callout:

```text
Named Credential API Name: SF_TOOLING
External Credential: TRA_SF_External_Cred
Principal: SF_Tooling_Principal
```

The exact authentication setup may require an admin to authenticate or reconnect the Principal in the target org.

### 2. Confirm the Named Credential name

The Named Credential must be named exactly:

```text
SF_TOOLING
```

The Apex callout uses this endpoint pattern:

```text
callout:SF_TOOLING/services/data/v61.0/tooling/query/?q=...
```

If this name changes, `ToolingApiClient.cls` must also be changed.

### 3. Deploy or assign integration access

After the External Credential Principal exists, deploy or assign:

```text
post-install/permissionsets/TRA_Integration_Access.permissionset-meta.xml
```

This permission set should not be deployed before the External Credential Principal exists.

### 4. Validate the runtime connection

Open the TRA app and click the runner page.

Expected behavior:

```text
Trigger list loads successfully
No SF_TOOLING / callout endpoint error appears
```

## Current permission set location

```text
post-install/permissionsets/TRA_Integration_Access.permissionset-meta.xml
```

Do not move this permission set back into `tra-package` unless the External Credential and Principal metadata are also included and clean-org validation proves the full package deploys successfully.

## Future install automation plan

For large-scale installs across many orgs, manual work should be limited to the authentication step that truly requires human/admin approval.

Recommended direction:

1. Keep `tra-package` as the clean core package.
2. Add a package-safe `TRA_User_Access` permission set inside `tra-package` for app, tab, object, field, Apex, and LWC access.
3. Keep `TRA_Integration_Access` separate unless the External Credential and Principal are also packaged and validated.
4. Create a scripted post-install command sequence for repeatable setup.
5. Document the only manual step as: authenticate/reconnect the External Credential Principal in the target org.

Target future flow:

```text
1. Install/deploy core TRA package
2. Assign TRA_User_Access
3. Deploy/create Named Credential and External Credential metadata
4. Admin authenticates the Principal
5. Deploy/assign TRA_Integration_Access
6. Run a smoke test that loads triggers through SF_TOOLING
```

The long-term goal is a fast install where the admin only performs the authentication step, and everything else is packaged or scripted.
