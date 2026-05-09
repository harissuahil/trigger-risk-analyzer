param(
    [Parameter(Mandatory = $true)]
    [string]$TargetOrgAlias,

    [Parameter(Mandatory = $true)]
    [string]$MyDomainUrl,

    [SecureString]$ConsumerKey,

    [SecureString]$ConsumerSecret,

    [switch]$Deploy
)

$ErrorActionPreference = "Stop"

function Convert-SecureStringToPlainText {
    param(
        [Parameter(Mandatory = $true)]
        [SecureString]$SecureValue
    )

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function New-MetadataFromTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateFile,

        [Parameter(Mandatory = $true)]
        [string]$OutputFile,

        [Parameter(Mandatory = $true)]
        [hashtable]$Replacements
    )

    $content = Get-Content $TemplateFile -Raw

    foreach ($key in $Replacements.Keys) {
        $content = $content.Replace($key, $Replacements[$key])
    }

    $remainingPlaceholders = [regex]::Matches($content, "__[A-Z0-9_]+__")
    if ($remainingPlaceholders.Count -gt 0) {
        $names = ($remainingPlaceholders | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ", "
        throw "Unresolved placeholders remain in ${OutputFile}: $names"
    }

    Set-Content -Path $OutputFile -Value $content -Encoding utf8
}

$repoRootPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$templateDir = Join-Path $repoRootPath "post-install\templates"

$normalizedMyDomainUrl = $MyDomainUrl.TrimEnd("/")

if ($normalizedMyDomainUrl -notmatch '^https://[^/]+\.salesforce\.com$') {
    throw "MyDomainUrl must be a Salesforce org URL that starts with https://, ends with .salesforce.com, and has no path. Got: $MyDomainUrl"
}

$ignoredOutputDirs = @(
    "post-install/authproviders/",
    "post-install/externalCredentials/",
    "post-install/namedCredentials/"
)

foreach ($relativePath in $ignoredOutputDirs) {
    & git -C $repoRootPath check-ignore -q -- $relativePath

    if ($LASTEXITCODE -eq 128) {
        throw "Git could not verify ignore status for $relativePath. Make sure you are running this from a valid Git checkout."
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Refusing to write OAuth metadata: $relativePath is not gitignored. Add it to .gitignore before re-running."
    }
}

if (-not $ConsumerKey) {
    $ConsumerKey = Read-Host "External Client App Consumer Key" -AsSecureString
}

if (-not $ConsumerSecret) {
    $ConsumerSecret = Read-Host "External Client App Consumer Secret" -AsSecureString
}

$plainConsumerKey = Convert-SecureStringToPlainText -SecureValue $ConsumerKey
$plainConsumerSecret = Convert-SecureStringToPlainText -SecureValue $ConsumerSecret

if ([string]::IsNullOrWhiteSpace($plainConsumerKey)) {
    throw "Consumer Key is empty. Re-run and paste the key when prompted."
}

if ([string]::IsNullOrWhiteSpace($plainConsumerSecret)) {
    throw "Consumer Secret is empty. Re-run and paste the secret when prompted."
}

$authProviderDir = Join-Path $repoRootPath "post-install\authproviders"
$externalCredentialDir = Join-Path $repoRootPath "post-install\externalCredentials"
$namedCredentialDir = Join-Path $repoRootPath "post-install\namedCredentials"

New-Item -ItemType Directory -Force $authProviderDir | Out-Null
New-Item -ItemType Directory -Force $externalCredentialDir | Out-Null
New-Item -ItemType Directory -Force $namedCredentialDir | Out-Null

$replacements = @{
    "__TARGET_ORG_MY_DOMAIN_URL__"      = $normalizedMyDomainUrl
    "__CONNECTED_APP_CONSUMER_KEY__"    = $plainConsumerKey
    "__CONNECTED_APP_CONSUMER_SECRET__" = $plainConsumerSecret
}

New-MetadataFromTemplate `
    -TemplateFile (Join-Path $templateDir "TRA_SF_AuthProvider.authprovider-meta.xml.template") `
    -OutputFile (Join-Path $authProviderDir "TRA_SF_AuthProvider.authprovider-meta.xml") `
    -Replacements $replacements

New-MetadataFromTemplate `
    -TemplateFile (Join-Path $templateDir "TRA_SF_External_Cred.externalCredential-meta.xml.template") `
    -OutputFile (Join-Path $externalCredentialDir "TRA_SF_External_Cred.externalCredential-meta.xml") `
    -Replacements $replacements

New-MetadataFromTemplate `
    -TemplateFile (Join-Path $templateDir "SF_TOOLING.namedCredential-meta.xml.template") `
    -OutputFile (Join-Path $namedCredentialDir "SF_TOOLING.namedCredential-meta.xml") `
    -Replacements $replacements

# Secrets are now persisted to the gitignored generated metadata files.
# Clear plaintext values before optional deploy or later script output.
$plainConsumerKey = $null
$plainConsumerSecret = $null
$replacements = $null
[GC]::Collect()

Write-Host ""
Write-Host "Generated deployable credential metadata:"
Write-Host " - post-install/authproviders/TRA_SF_AuthProvider.authprovider-meta.xml"
Write-Host " - post-install/externalCredentials/TRA_SF_External_Cred.externalCredential-meta.xml"
Write-Host " - post-install/namedCredentials/SF_TOOLING.namedCredential-meta.xml"
Write-Host ""
Write-Host "These generated files are org-specific and should stay uncommitted."

if ($Deploy) {
    Write-Host ""
    Write-Host "Deploying generated credential metadata to $TargetOrgAlias..."

    sf project deploy start `
        --source-dir post-install/authproviders `
        --source-dir post-install/externalCredentials `
        --source-dir post-install/namedCredentials `
        --target-org $TargetOrgAlias `
        --wait 10

    if ($LASTEXITCODE -ne 0) {
        throw "sf project deploy start failed with exit code $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "Deploy complete."
}

Write-Host ""
Write-Host "Next manual step:"
Write-Host "1. Open Setup in the target org."
Write-Host "2. Go to External Credentials."
Write-Host "3. Open TRA_SF_External_Cred."
Write-Host "4. Authenticate/reconnect the SF_Tooling_Principal principal."
Write-Host ""
Write-Host "After principal authentication succeeds, run:"
Write-Host "sf project deploy start --source-dir post-install/permissionsets --target-org $TargetOrgAlias --wait 10"
Write-Host "sf org assign permset --name TRA_Integration_Access --target-org $TargetOrgAlias"
Write-Host ""
Write-Host "Then smoke test TRA by loading the trigger list from the app."
