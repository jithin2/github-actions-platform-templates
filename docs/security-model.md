# Security model

Where secrets live, what permissions each workflow requests, and the complete
OIDC trust setup for Azure and GCP. This document is written for the platform
engineer setting up a new environment and for the product team engineer who
needs to understand why their auth is failing.

---

## 1. Secret scopes and storage

GitHub provides two places to register secrets. Choosing the wrong one is the
most common misconfiguration that causes auth failures.

### Repository secrets vs Environment secrets

| | Repository secrets | Environment secrets |
|---|---|---|
| Scope | Available to all jobs in the repo | Available only to jobs that run inside the named Environment |
| OIDC subject claim | `repo:ORG/REPO:ref:refs/heads/main` | `repo:ORG/REPO:environment:production` |
| Use for | CI builds, container pushes, non-prod | Production deploys, applies, syncs |
| Protection | None beyond repo access | Can require approval gates before job starts |

**Rule of thumb:** anything that writes to production — `terraform apply`, an
ArgoCD sync to the prod cluster, a push to a prod registry — should use
Environment secrets with an approval gate. Builds and PR checks use Repository
secrets.

### What to register where

```
Repository secrets (no environment)
  AZURE_CLIENT_ID           ← for CI builds pushing to ACR
  AZURE_TENANT_ID
  AZURE_SUBSCRIPTION_ID
  GCP_PROJECT_NUMBER        ← for CI builds pushing to GAR
  GCP_SERVICE_ACCOUNT

GitHub Environment: "production"
  AZURE_CLIENT_ID           ← separate App Registration scoped to prod resources
  AZURE_TENANT_ID
  AZURE_SUBSCRIPTION_ID
  ARGOCD_SERVER
  ARGOCD_AUTH_TOKEN
```

The prod App Registration is a *different* registration from the CI one — with
narrower RBAC (Contributor on the prod resource group only, not the whole
subscription). The federated credential on the prod registration uses
`environment:production` as the subject, so it only matches jobs running inside
that GitHub Environment.

### Rotating a compromised OIDC credential

There is no long-lived password to rotate. If you suspect the OIDC trust is
compromised (e.g. the federated credential was misconfigured to be too broad):

**Azure:**
```bash
# Delete the federated credential — the trust is severed immediately.
# The App Registration and its RBAC assignments remain intact.
az ad app federated-credential delete \
  --id <APP_ID> \
  --federated-credential-id <CREDENTIAL_ID>

# Re-create with corrected subject claim
az ad app federated-credential create --id <APP_ID> --parameters '{ ... }'
```

**GCP:**
```bash
# Delete and recreate the pool binding — the SA itself is unaffected
gcloud iam service-accounts remove-iam-policy-binding \
  "SA@PROJECT.iam.gserviceaccount.com" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/..." \
  --role="roles/iam.workloadIdentityUser"
```

Neither rotation requires touching GitHub secrets — there are none to rotate.

---

## 2. Workflow permission model

Every workflow in this repo declares the minimum permissions required. The
`permissions:` block at the job level overrides the default `GITHUB_TOKEN`
permissions for that job only.

GitHub's default for new repos is `permissions: read-all`. For orgs that set
the default to `none`, the calling workflow must explicitly grant permissions
(see the example workflows in `examples/`).

### Per-workflow permission table

| Workflow | `id-token` | `contents` | `pull-requests` | `security-events` |
|---|---|---|---|---|
| `container-build-scan-push` | `write` | `read` | — | `write` |
| `helm-lint-template` | — | `read` | — | — |
| `terraform-plan-apply` | `write` | `read` | `write` | — |
| `argocd-sync` | — | `read` | — | — |
| `python-quality` | — | `read` | — | — |

### Why each permission is needed

**`id-token: write`**
Allows the job to call `$ACTIONS_ID_TOKEN_REQUEST_URL` and receive a signed
JWT from GitHub's OIDC provider. Without this, the OIDC token request returns
a 403. This is intentionally not granted by default — it must be explicit.

**`security-events: write`**
Required to upload SARIF files to GitHub Advanced Security via
`github/codeql-action/upload-sarif`. Without it, the upload step fails with
a 403. The results will not appear in the repository's Security tab.

**`pull-requests: write`**
Required to post or update comments on pull requests via the GitHub REST API.
Used by `terraform-plan-apply` to publish the plan output as a PR comment.
Without it, the comment step fails silently (or with a 403) and the plan is
only visible in the raw job logs.

**`contents: read`**
Required to check out the repository with `actions/checkout`. It is also
required to resolve composite action paths (`.github/actions/setup-tools`)
when calling `uses:` with a local path.

---

## 3. Azure OIDC — complete setup

### How it works

GitHub's OIDC provider issues a signed JWT for each job run. The JWT contains
claims about the repo, branch, and trigger context. Azure validates this JWT
against a **federated identity credential** on an App Registration. If the
`iss`, `aud`, and `sub` claims match the credential's configuration, Azure
issues a short-lived access token. No password is exchanged at any point.

```
GitHub runner
    │
    ├─ Request OIDC JWT from GitHub's token endpoint
    │   (requires id-token: write permission)
    │
    ▼
GitHub OIDC provider
    │  issues signed JWT with claims:
    │  iss: https://token.actions.githubusercontent.com
    │  aud: api://AzureADTokenEndpoint
    │  sub: repo:ORG/REPO:ref:refs/heads/main
    │
    ▼
azure/login action
    │  presents JWT to Azure AD token endpoint
    │
    ▼
Azure AD
    │  validates: iss matches issuer on federated credential
    │             aud matches audience
    │             sub matches subject exactly
    │
    ▼
    issues short-lived access token (valid ~1 hour)
    │
    ▼
GitHub runner uses token for subsequent Azure CLI / SDK calls
```

### One-time setup

```bash
# Variables
APP_NAME="github-platform-ci"
ORG="your-github-org"
REPO="your-repo"
SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"

# 1. Create the App Registration — no password, no client secret
APP_ID=$(az ad app create \
  --display-name "$APP_NAME" \
  --query appId \
  --output tsv)
echo "App ID: $APP_ID"

# 2. Create the service principal (required for RBAC assignments)
az ad sp create --id "$APP_ID"

# 3a. Federated credential for branch-based trust (CI builds, container pushes)
#     Matches: push to main, workflow_dispatch on main
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"github-main-branch\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${ORG}/${REPO}:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenEndpoint\"]
  }"

# 3b. Federated credential for PR trust (plan runs on PRs)
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"github-pull-request\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${ORG}/${REPO}:pull_request\",
    \"audiences\": [\"api://AzureADTokenEndpoint\"]
  }"

# 3c. Federated credential for environment-based trust (production deploys)
#     Job MUST run inside a GitHub Environment named "production"
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"github-prod-environment\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${ORG}/${REPO}:environment:production\",
    \"audiences\": [\"api://AzureADTokenEndpoint\"]
  }"

# 4. Assign RBAC — least privilege, scoped as narrow as possible
#    Example: push to a specific ACR
az role assignment create \
  --assignee "$APP_ID" \
  --role "AcrPush" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-platform/providers/Microsoft.ContainerRegistry/registries/myregistry"

#    Example: Terraform apply (Contributor on resource group, not subscription)
az role assignment create \
  --assignee "$APP_ID" \
  --role "Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-platform-dev"

#    Example: read/write Terraform state in storage account
az role assignment create \
  --assignee "$APP_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/stplatformtfstate"
```

### Required workflow configuration

```yaml
permissions:
  id-token: write   # Must be explicit — not granted by default
  contents: read

steps:
  - uses: azure/login@a65d910e851af2ee06a64c6b9c7c73ab3c0e5b5  # v2.2.0
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}       # App Registration appId
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}       # Azure AD tenant ID
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      # No client-secret. The OIDC JWT IS the credential.
```

### Subject claim reference

The `sub` claim in the GitHub JWT encodes the exact trigger context. It must
match the subject in the federated credential **exactly** — Azure does not do
prefix matching or wildcards.

| Trigger | Subject claim |
|---|---|
| Push to `main` | `repo:ORG/REPO:ref:refs/heads/main` |
| Push to `feature/xyz` | `repo:ORG/REPO:ref:refs/heads/feature/xyz` |
| Tag push `v1.0.0` | `repo:ORG/REPO:ref:refs/tags/v1.0.0` |
| Pull request (any branch) | `repo:ORG/REPO:pull_request` |
| `workflow_dispatch` on `main` | `repo:ORG/REPO:ref:refs/heads/main` |
| Job in Environment `production` | `repo:ORG/REPO:environment:production` |
| Scheduled trigger | `repo:ORG/REPO:ref:refs/heads/main` (default branch) |

**Common failure pattern:** You configure trust for `environment:production`
but the workflow_dispatch runs without an environment set. The subject is
`ref:refs/heads/main`, not `environment:production`. Azure returns 401 with no
indication of which claim mismatched.

### Debugging auth failures

When Azure returns a 401 and the error message is not helpful, decode the raw
OIDC token to compare the `sub` claim against your federated credential:

```yaml
- name: Debug — decode OIDC token subject claim
  run: |
    TOKEN=$(curl -sH \
      "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenEndpoint" \
      | jq -r .value)
    # The JWT is base64url encoded in three parts: header.payload.signature
    PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)
    # Add padding if needed and decode
    python3 -c "
    import base64, json, sys
    p = sys.argv[1]
    p += '=' * (4 - len(p) % 4)
    print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=2))
    " "$PAYLOAD"
  env:
    ACTIONS_ID_TOKEN_REQUEST_TOKEN: ${{ env.ACTIONS_ID_TOKEN_REQUEST_TOKEN }}
    ACTIONS_ID_TOKEN_REQUEST_URL: ${{ env.ACTIONS_ID_TOKEN_REQUEST_URL }}
```

Look at the `sub` field in the output. Compare it character-for-character with
the subject in your federated credential. They must be identical.

---

## 4. GCP OIDC — complete setup

### How it works

GCP uses a **Workload Identity Federation** model with a pool and provider.
The pool acts as a trust boundary; the provider defines how external tokens are
validated and which claims are mapped to GCP attributes.

```
GitHub runner
    │
    ├─ Request OIDC JWT from GitHub (same as Azure flow)
    │
    ▼
google-github-actions/auth
    │  calls GCP Security Token Service (STS) with the JWT
    │  STS validates: issuer matches the pool's OIDC provider
    │                 attribute-condition passes (e.g. correct org)
    │                 attribute.repository matches the pool binding
    │
    ▼
GCP STS issues a federated token
    │
    ▼
Service Account impersonation
    │  federated token exchanged for SA access token
    │  (requires roles/iam.workloadIdentityUser binding on the SA)
    │
    ▼
GitHub runner uses SA access token for gcloud / client library calls
```

### One-time setup

```bash
PROJECT_ID="your-gcp-project"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" \
  --format="value(projectNumber)")
ORG="your-github-org"
REPO="your-repo"
SA_NAME="github-platform-ci"

# 1. Create the Workload Identity Pool
gcloud iam workload-identity-pools create "github-pool" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions"

# 2. Create the OIDC provider inside the pool
#
# attribute-mapping: maps GitHub JWT claims to GCP attributes.
#   google.subject      = assertion.sub       (the full subject string)
#   attribute.repository = assertion.repository (e.g. "ORG/REPO")
#   attribute.repository_owner = assertion.repository_owner (e.g. "ORG")
#
# attribute-condition: gates which tokens the provider will even accept.
#   Without this, ANY GitHub Actions workflow from ANY repo could attempt
#   token exchange against your pool. Always restrict to your org at minimum.
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == '${ORG}'"

# 3. Create a dedicated Service Account for CI
gcloud iam service-accounts create "$SA_NAME" \
  --project="$PROJECT_ID" \
  --display-name="GitHub Actions platform CI"

# 4. Grant the SA the roles it needs
#    Example: push to Artifact Registry
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# 5. Bind the SA to the pool — scoped to a specific repo
#    principalSet scopes to all tokens where attribute.repository matches.
#    A different product team repo gets its own binding on a different SA.
gcloud iam service-accounts add-iam-policy-binding \
  "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/${ORG}/${REPO}"

# Retrieve the provider resource name — this is what goes in the workflow secret
echo "Workload Identity Provider:"
echo "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
```

### `principal` vs `principalSet` — when each applies

| Binding type | Member format | Matches |
|---|---|---|
| `principalSet` on `attribute.repository` | `principalSet://.../attribute.repository/ORG/REPO` | Any token from that repo, any branch, any trigger |
| `principalSet` on `attribute.repository_owner` | `principalSet://.../attribute.repository_owner/ORG` | Any token from any repo in the org |
| `principal` on `google.subject` | `principal://.../subject/repo:ORG/REPO:ref:refs/heads/main` | Exactly that subject — equivalent to Azure's per-subject trust |

For most use cases, bind on `attribute.repository` — it is repo-scoped without
requiring a new binding for every branch. For production environments where you
want branch-level restriction, bind on `google.subject` with the exact `main`
ref subject string.

### Required workflow configuration

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: google-github-actions/auth@6fc4af4b145ae7821d527454aa9bd537d1f2dc5f  # v2.1.7
    id: auth
    with:
      workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      # Format: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL/providers/PROVIDER
      service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}
      # Format: SA_NAME@PROJECT_ID.iam.gserviceaccount.com
```

### Debugging token exchange failures

GCP's STS error messages are more descriptive than Azure's 401 responses, but
the most common failure is the `attribute-condition` rejecting the token:

```
Error: google-github-actions/auth failed with: error calling "iamcredentials.generateAccessToken":
  caller does not have permission or the resource may not exist
```

This usually means either:
1. The `attribute-condition` rejected the token (wrong org name)
2. The SA binding uses `attribute.repository` but the token's `repository` claim
   format does not match (`ORG/REPO` vs full path)
3. The SA does not have `roles/iam.workloadIdentityUser` — easy to miss

To inspect what the GitHub token actually contains:

```bash
# Decode the JWT payload (same technique as Azure debug above)
# Look specifically at: repository, repository_owner, sub, iss, aud
```

To test the binding directly:

```bash
gcloud iam service-accounts get-iam-policy \
  "SA_NAME@PROJECT_ID.iam.gserviceaccount.com" \
  --format=json | jq '.bindings[] | select(.role == "roles/iam.workloadIdentityUser")'
```

---

## 5. Fork PR and secret access

### The problem

When an external contributor opens a pull request from a fork, the `pull_request`
event runs in the context of the **base repository** but with a token scoped to
the **fork**. GitHub intentionally blocks this token from accessing base
repository secrets. This prevents a malicious PR from exfiltrating credentials.

The practical consequence: any platform workflow that needs cloud credentials
(container-build-scan-push with `push: true`, terraform-plan-apply) will fail on
fork PRs because `AZURE_CLIENT_ID` and equivalent secrets are unavailable.

### The wrong fix — `pull_request_target`

`pull_request_target` runs with the base repository's full token, including
secrets. It is designed for exactly this case — but it is dangerous if misused.

**Never check out the PR's code in a `pull_request_target` job that uses
secrets.** A malicious PR can modify workflow files or scripts that the
`pull_request_target` job then executes, giving the attacker full access to
every secret in the repo.

The GitHub security advisory [GHSA-mfwh-5m23-j46w](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/)
covers this class of vulnerability in detail.

### The correct split

Separate what needs secrets from what does not:

```yaml
# Runs on pull_request — no secrets available, no cloud access needed
on:
  pull_request:
jobs:
  # Safe: read-only, no credentials
  quality:
    uses: .../python-quality.yml@v1.0.0
  helm-validate:
    uses: .../helm-lint-template.yml@v1.0.0
  container-scan-only:
    uses: .../container-build-scan-push.yml@v1.0.0
    with:
      push: false   # Build and scan; skip the registry push entirely
      registry-type: acr
      registry: placeholder  # Not used when push=false
```

```yaml
# Runs on push to main — secrets available, registry push happens
on:
  push:
    branches: [main]
jobs:
  build-and-push:
    uses: .../container-build-scan-push.yml@v1.0.0
    with:
      push: true
    secrets: inherit
```

This gives PR authors scan feedback without needing secrets. The actual push
happens only after the PR is merged.

---

## 6. Action SHA pinning

### The threat model

Every `uses: owner/repo@ref` in a workflow fetches code from GitHub and
executes it on the runner with full access to the job's environment — including
all secrets. A tag (`@v4`) is a mutable pointer. If a maintainer's account is
compromised and the tag is repointed to malicious code, every workflow using
that tag runs the attacker's code on its next trigger.

A commit SHA is immutable. Once a commit exists, its SHA cannot be reused for
different content. Pinning to a SHA means the action code is fixed regardless
of what happens to the tag.

### Real incident: tj-actions/changed-files (March 2025)

The `tj-actions/changed-files` action — used in thousands of repositories —
had its version tags repointed to a malicious commit that printed runner memory
(including secrets) to workflow logs. Repositories pinned to specific SHAs were
unaffected. Repositories using tag references (`@v45`, `@main`) executed the
malicious code.

This is why every `uses:` in this repo is pinned to a SHA with a version
comment:

```yaml
# Pattern used throughout this repo:
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
# ↑ immutable SHA                                                  ↑ human-readable version
```

### How to get the SHA for a tag

```bash
# For lightweight tags (most common):
gh api repos/actions/checkout/git/ref/tags/v4.2.2 --jq '.object.sha'

# For annotated tags (some repos use these — the above returns the tag object SHA,
# not the commit SHA; you need to dereference):
gh api repos/actions/checkout/git/tags/<tag-object-sha> --jq '.object.sha'

# Or use git directly (always returns the commit SHA):
git ls-remote https://github.com/actions/checkout refs/tags/v4.2.2^{}
```

### Keeping SHAs current with Dependabot

SHA pins become stale — new versions fix bugs and CVEs. Dependabot handles
automated SHA bump PRs when configured with the `github-actions` ecosystem:

```yaml
# .github/dependabot.yml (already present in this repo)
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

Dependabot opens a PR that updates both the SHA and the version comment. The
platform team reviews and merges. Product teams do not manage SHA pins in
the platform repo — they consume workflow versions via `@v1.x.x` tags.

### The ergonomics tradeoff

SHA pins are harder to read (`11bd71901bbe5b1630ceea73d27597364c9af683`
vs `v4`). The version comment mitigates this. The maintenance overhead is
handled by Dependabot. The security gain is a hard guarantee that tag
repointing cannot inject code into this pipeline.

Teams that push back on SHA pinning need to understand the threat is not
theoretical — the tj-actions incident affected real production pipelines. After
that conversation, pinning is adopted.

---

## 7. SARIF upload and code scanning

Trivy scan results are uploaded to GitHub Advanced Security in SARIF format.
This surfaces findings in two places: the repository's Security tab (persistent,
filterable by severity and state) and the PR diff view (inline annotations on
the affected lines).

### Required configuration

```yaml
permissions:
  security-events: write   # Required for SARIF upload

- uses: github/codeql-action/upload-sarif@<SHA>  # v3.x
  if: always()  # Upload even when the scan step fails
  with:
    sarif_file: trivy-results.sarif
    category: container-scan  # Distinguishes multiple scan sources in the Security tab
```

`if: always()` is deliberate. If the scan fails (findings found, exit code 1),
the default behaviour would skip all subsequent steps including the upload.
Without `always()`, a failing scan produces no visible output in the Security
tab — the team sees a red check but has no way to view the findings without
digging into raw logs.

### GitHub Advanced Security requirement

SARIF upload to the Security tab requires **GitHub Advanced Security** to be
enabled on the repository. This is available by default on public repositories.
Private repositories require a GitHub Advanced Security licence.

### What appears where

| Location | What it shows |
|---|---|
| Security tab → Code scanning | All findings, filterable by severity, state (open/fixed/dismissed), and tool |
| PR diff view | Inline annotations on affected files (only if the finding maps to a specific file/line) |
| Workflow logs | Raw Trivy table output (always visible regardless of SARIF upload) |

---

## 8. Secrets in composite actions

Composite actions (like `setup-tools`) cannot declare a `secrets:` block —
this is a GitHub Actions limitation. If a composite action needs a secret, it
must receive it as an `input`.

```yaml
# In the composite action's action.yml
inputs:
  registry-token:
    description: Token for authenticated registry pull (if needed)
    required: false

runs:
  using: composite
  steps:
    - name: Authenticated pull
      shell: bash
      run: |
        echo "${{ inputs.registry-token }}" | docker login ...
```

**Masking:** Any value passed as an input to a composite action is automatically
masked in logs if it was originally sourced from a secret context. GitHub's
runner intercepts the value and replaces it with `***` in all log output.

**Never do this:**
```yaml
- name: Debug
  shell: bash
  run: echo "Token is ${{ inputs.registry-token }}"  # Masked in logs but still bad practice
```

Even if the value is masked in the GitHub UI, printing secrets to stdout is
bad practice — log aggregation tools, third-party log shippers, and debug
captures may not apply the same masking.
