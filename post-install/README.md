# TRA Fresh Install and Post-Install Setup

This guide explains how to deploy TRA into a fresh Salesforce org and complete the required post-install setup for the Tooling API connection.

## Purpose

TRA is split into two setup layers.

### Core package

The core package is under:

```text
tra-package/main/default
```

It contains the product metadata that should deploy cleanly into a new org:

```text
TRA app
Apex classes and tests
LWC runner
Deployment Analysis objects and fields
Custom metadata rules
Tabs and FlexiPages
TRA_User_Access permission set
```

### Post-install setup

The post-install setup is under:

```text
post-install/
```

It contains org-specific integration setup for the Tooling API connection:

```text
Credential templates
Generated credential metadata folders
TRA_Integration_Access permission set
```

`TRA_Integration_Access` stays outside the core package because it grants access to an External Credential Principal that does not exist until the credential metadata is deployed in the target org.

## Validation status

A full fresh-install validation passed in a new org with this result:

```text
Core package deploy: PASSED
RunLocalTests: 110/110 passing
TRA_User_Access assignment: PASSED
Post-install credential metadata deploy: 3/3 components deployed
External Credential Principal authentication: PASSED
TRA_Integration_Access deploy and assignment: PASSED
Runtime smoke test: PASSED
Run Analysis smoke test: PASSED
Run Status: Done
Overall Risk: Low
Release Recommendation: APPROVED WITH CONDITIONS
```

## Required names

The Apex code expects this Named Credential API name:

```text
SF_TOOLING
```

The credential setup uses these names:

```text
Named Credential: SF_TOOLING
External Credential: TRA_SF_External_Cred
Auth Provider: TRA_SF_AuthProvider
Principal: SF_Tooling_Principal
Integration Permission Set: TRA_Integration_Access
User Permission Set: TRA_User_Access
```

Do not rename `SF_TOOLING` unless `ToolingApiClient.cls` is also updated.

## Full install sequence

Run these steps from the project root unless noted otherwise.

### 1. Log in to the target org

```powershell
sf org login web --alias <org-alias> --set-default
```

Log in with the target org username and password when the browser opens.

### 2. Confirm the org is connected

```powershell
sf org list
```

Expected result:

```text
<org-alias>    Connected
```

### 3. Confirm Salesforce CLI can communicate with the org

```powershell
sf org display --target-org <org-alias>
```

### 4. Confirm the repo is clean

```powershell
git status
```

Expected result:

```text
nothing to commit, working tree clean
```

### 5. Deploy the clean core package

```powershell
sf project deploy start --source-dir tra-package/main/default --target-org <org-alias> --test-level RunLocalTests --wait 30
```

Expected result:

```text
Status: Succeeded
Tests passing
```

Do not run the post-install credential script until this core package deployment succeeds.

### 6. Assign normal TRA user access

```powershell
sf org assign permset --name TRA_User_Access --target-org <org-alias>
```

After this step, the TRA app should be available to the assigned user.

### 7. Get the target org base URL

Open the org:

```powershell
sf org open --target-org <org-alias>
```

Copy the base org URL from the browser. It should look similar to:

```text
https://<mydomain>.my.salesforce.com
```

or another Salesforce org URL ending in:

```text
.salesforce.com
```

Use the base URL only. Do not include any path after `.salesforce.com`.

### 8. Create the External Client App

In Salesforce Setup, go to:

```text
Setup → External Client App Manager → New External Client App
```

Use values similar to these:

```text
External Client App Name: TRA SF Tooling Client
API Name: TRA_SF_Tooling_Client
Contact Email: <admin email>
```

Enable OAuth and add a temporary callback URL:

```text
https://login.salesforce.com/services/authcallback/TRA_SF_AuthProvider
```

This temporary callback URL is replaced later after `TRA_SF_AuthProvider` is deployed and the real callback URL is available.

Add these OAuth scopes:

```text
Manage user data via APIs (api)
Perform requests at any time (refresh_token, offline_access)
Full access (full)
```

Configure these OAuth settings:

```text
Require Proof Key for Code Exchange (PKCE): unchecked
Require Secret for Web Server Flow: checked
Require Secret for Refresh Token Flow: checked
Permitted Users: All users may self-authorize
Refresh Token Policy: Refresh token is valid until revoked
```

Save the External Client App.

### 9. Get the Consumer Key and Consumer Secret

Go back to:

```text
Setup → External Client App Manager
```

Open the External Client App created above, then go to:

```text
Settings → OAuth Settings → Consumer Key and Secret
```

Copy these values:

```text
Consumer Key
Consumer Secret
```

Do not commit or share real values.

### 10. Generate and deploy credential metadata

A helper script generates deployable metadata from sanitized templates in:

```text
post-install/templates/
```

The generated files are written to gitignored folders:

```text
post-install/authproviders/
post-install/externalCredentials/
post-install/namedCredentials/
```

These generated files are org-specific and must not be committed.

Use the safer `SecureString` variable method below. Paste the real key and secret only into your local terminal.

```powershell
$ckPlain = @'
PASTE_CONSUMER_KEY_HERE
'@.Trim()

$csPlain = @'
PASTE_CONSUMER_SECRET_HERE
'@.Trim()

$ck = ConvertTo-SecureString -String $ckPlain -AsPlainText -Force
$cs = ConvertTo-SecureString -String $csPlain -AsPlainText -Force

$ckPlain = $null
$csPlain = $null

.\scripts\prepare-post-install.ps1 `
  -TargetOrgAlias <org-alias> `
  -MyDomainUrl "https://<mydomain>.my.salesforce.com" `
  -ConsumerKey $ck `
  -ConsumerSecret $cs `
  -Deploy

$ck = $null
$cs = $null
[GC]::Collect()
```

Expected result:

```text
Generated deployable credential metadata
Deploying generated credential metadata
Deploy complete
```

### 11. Replace the temporary callback URL

After the credential metadata deploys, open:

```text
Setup → Auth. Providers → TRA_SF_AuthProvider
```

Copy the generated Callback URL.

Then open:

```text
Setup → External Client App Manager → TRA SF Tooling Client → Settings → OAuth Settings
```

Replace the temporary callback URL with the exact Callback URL from `TRA_SF_AuthProvider`.

Save the External Client App.

### 12. Authenticate the External Credential Principal

Go to:

```text
Setup → Named Credentials → External Credentials → TRA_SF_External_Cred
```

Find:

```text
SF_Tooling_Principal
```

Click:

```text
Authenticate
```

or:

```text
Reconnect
```

Use the same Salesforce user that will run TRA.

### 13. Deploy and assign integration access

After the Principal authentication succeeds, deploy the integration permission set:

```powershell
sf project deploy start --source-dir post-install/permissionsets --target-org <org-alias> --wait 10
```

Then assign it:

```powershell
sf org assign permset --name TRA_Integration_Access --target-org <org-alias>
```

### 14. Smoke test TRA

Open the org:

```powershell
sf org open --target-org <org-alias>
```

Open the TRA app and go to the runner page.

Expected result:

```text
No SF_TOOLING / credential access error appears
Trigger list loads successfully
```

If the org has no Apex triggers, the trigger selector may be empty even when the integration is working. For validation only, deploy a temporary trigger, run analysis, and remove the trigger after testing.

Expected run result after selecting a trigger:

```text
Run is created
Status: Done
Open Run works
Findings display correctly
Release Gate displays correctly
```

## Troubleshooting

### `The callout couldn't access the endpoint... SF_TOOLING might not exist`

Check that:

```text
SF_TOOLING Named Credential exists
TRA_SF_External_Cred exists
SF_Tooling_Principal is authenticated
TRA_Integration_Access is deployed and assigned
```

### `We couldn't access the credential(s)`

This usually means the user does not have access to the External Credential Principal.

Run:

```powershell
sf project deploy start --source-dir post-install/permissionsets --target-org <org-alias> --wait 10
sf org assign permset --name TRA_Integration_Access --target-org <org-alias>
```

Then refresh the TRA app.

### `redirect_uri_mismatch`

The callback URL in the External Client App does not match the Callback URL generated by `TRA_SF_AuthProvider`.

Fix the External Client App callback URL and try Principal authentication again.

### `invalid XML character Unicode: 0x16`

Some terminals may not paste cleanly into a secure prompt. Use the `SecureString` variable method in step 10 instead of pasting into the script prompt.

### `PermissionSet TRA_Integration_Access invalid cross reference id`

This means `TRA_Integration_Access` was deployed before the External Credential Principal existed.

Deploy the credential metadata first, authenticate the Principal, then deploy and assign `TRA_Integration_Access`.

## Security notes

Do not commit generated credential metadata from these folders:

```text
post-install/authproviders/
post-install/externalCredentials/
post-install/namedCredentials/
```

These folders are intentionally gitignored.

If a Consumer Secret is exposed during testing, rotate or regenerate it after validation.

## Future install automation plan

For large-scale installs across many orgs, manual work should be limited to the authentication step that truly requires human or admin approval.

Target future flow:

```text
1. Install/deploy core TRA package
2. Assign TRA_User_Access
3. Generate credential metadata from templates
4. Deploy Named Credential / External Credential / Auth Provider metadata
5. Admin authenticates the Principal
6. Deploy/assign TRA_Integration_Access
7. Run a smoke test that loads triggers through SF_TOOLING
```

The long-term goal is a fast install where the admin only performs the authentication step, and everything else is packaged or scripted.
