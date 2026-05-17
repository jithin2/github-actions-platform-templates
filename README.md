# github-actions-platform-templates

Reusable GitHub Actions workflows for containerised workloads, maintained by a platform team
and consumed by product teams across the organisation. Every workflow here reflects the patterns
used to serve 10+ engineering teams shipping to Azure and GCP.

*Authored by [Jithin Karkera](https://github.com/jithin2)*

---

## Repository layout

```
.github/
  workflows/               # Reusable workflows (workflow_call triggers only)
    container-build-scan-push.yml
    helm-lint-template.yml
    terraform-plan-apply.yml
    argocd-sync.yml
    python-quality.yml
  actions/
    setup-tools/           # Composite action: pin + install shared tooling
examples/                  # How a product team calls these workflows
  app-with-helm/
  terraform-infra/
  ml-model-service/
docs/
  README.md                # Workflow catalogue with input/output/secrets tables
  adoption-guide.md        # Migration guide for teams on bespoke pipelines
  security-model.md        # OIDC setup, secret scopes, permission model
```

---

## Why centralised workflows

When every team writes their own CI pipelines, drift is the default outcome:

- Trivy at three different versions across twelve repos, two with unpatched CVEs
- No SBOM generation because "we'll add it later" — and later never came
- Secret names inconsistent: `DOCKER_USERNAME` here, `ACR_USERNAME` there, `REGISTRY_USER`
  somewhere else — no one can audit what has access to what
- New team spends two days writing CI before shipping a line of product code

Centralised reusable workflows solve the entire class of problem:

| Without central workflows | With this repo |
|---|---|
| Fix Trivy CVE in 12 repos | Fix once, all callers get it on next run |
| Add SBOM gate to 12 repos | Add to the workflow, applies structurally |
| New team CI setup: ~2 days | 3 lines of YAML, done in an hour |
| "Which repos actually scan images?" → manual survey | Structural guarantee |

**The tradeoff is real.** Centralisation creates a blast radius — a bug in a reusable
workflow breaks every caller simultaneously. The mitigation is [semver pinning](#versioning-strategy):
callers control when they upgrade, so a bad patch does not auto-deploy to everyone.

---

## Available workflows

| Workflow | What it does |
|---|---|
| [`container-build-scan-push`](.github/workflows/container-build-scan-push.yml) | Build Docker image, Trivy vulnerability scan, SBOM generation (Syft), push to ACR or GAR |
| [`helm-lint-template`](.github/workflows/helm-lint-template.yml) | `helm lint`, `helm template`, kubeconform schema validation against target k8s version |
| [`terraform-plan-apply`](.github/workflows/terraform-plan-apply.yml) | fmt, validate, tflint, Checkov security scan, plan posted as PR comment, apply on merge to main |
| [`argocd-sync`](.github/workflows/argocd-sync.yml) | Trigger ArgoCD app sync via API after image promotion |
| [`python-quality`](.github/workflows/python-quality.yml) | ruff lint + format check, mypy type checking, pytest with enforced coverage threshold |

Full input/output/secrets tables: [docs/README.md](docs/README.md)

---

## The platform/product contract

Clear ownership is what makes centralised workflows function at scale. Blurred ownership
is what makes them collapse.

### Platform team owns

- All logic inside `.github/workflows/` and `.github/actions/`
- Tool versions and SHA pins, with a published upgrade schedule
- Security gates: Trivy threshold, SBOM generation, secret scanning, OIDC trust configuration
- Breaking-change policy, CHANGELOG, and migration guides
- Deciding which tools to use and when to replace deprecated ones

### Product teams own

- Application code, Dockerfiles, Helm chart values, Terraform root modules
- Trigger conditions: which events fire CI, which branches, which environments
- Secrets registered in their own repo or GitHub Environment
- Decision of when to upgrade to a new major workflow version
- Deployment timing and environment promotion gates

### Where the line sits in practice

| Scenario | Owner |
|---|---|
| Dockerfile builds a broken image | Product team |
| Trivy scan incorrectly blocks a clean image | Platform team |
| Wrong secret name registered in repo | Product team |
| OIDC trust misconfigured, auth fails for all callers | Platform team |
| Consumer's Helm values fail `helm lint` | Product team |
| kubeconform rejects a valid schema (false positive) | Platform team |

---

## OIDC federation

No workflow in this repo uses long-lived credentials. All cloud authentication is via
short-lived OIDC token exchange. Set this up once per cloud account; individual product
teams do not touch it.

### Azure OIDC setup

GitHub Actions issues a short-lived JWT for each job run. Azure validates it against
a **federated identity credential** on an App Registration — no client secret involved.

**One-time setup (run by platform team):**

```bash
# 1. Create App Registration — no password, no secret
APP_ID=$(az ad app create --display-name "github-platform-ci" --query appId -o tsv)

# 2. Create the service principal for it
az ad sp create --id "$APP_ID"

# 3a. Environment-based trust (recommended for production deployments)
#     Job must run inside a GitHub Environment named "production"
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "github-prod-environment",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:environment:production",
    "audiences": ["api://AzureADTokenEndpoint"]
  }'

# 3b. Branch-based trust (for non-environment workflows like container builds)
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "github-main-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenEndpoint"]
  }'

# 4. Assign RBAC — principle of least privilege
az role assignment create \
  --assignee "$APP_ID" \
  --role AcrPush \
  --scope /subscriptions/SUB_ID/resourceGroups/RG/providers/Microsoft.ContainerRegistry/registries/REGISTRY
```

**Required workflow permissions:**

```yaml
permissions:
  id-token: write   # must be explicit — requests the OIDC JWT from GitHub
  contents: read
```

**In the workflow step:**

```yaml
- uses: azure/login@a65d910e851af2ee06a64c6b9c7c73ab3c0e5b5  # v2.2.0
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    # No client-secret. The OIDC JWT is the credential.
```

**Subject claim precision — the most common failure point:**

The `subject` in the federated credential must match exactly what GitHub sends.
A mismatch returns a generic 401 with no indication of which claim failed.

| Configured subject | Matches | Does NOT match |
|---|---|---|
| `repo:ORG/REPO:ref:refs/heads/main` | Push to `main` | PRs, tags, `workflow_dispatch` on a tag |
| `repo:ORG/REPO:environment:production` | Job running inside `production` environment | Any job not in that environment |
| `repo:ORG/REPO:pull_request` | PR triggers | Push triggers, workflow_dispatch |

To debug a mismatch: decode the raw OIDC token in the job and compare the `sub` claim
against your trust rule:

```yaml
- name: Decode OIDC token for debugging
  run: |
    TOKEN=$(curl -sH "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenEndpoint" \
      | jq -r .value)
    echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq .sub
```

---

### GCP OIDC setup

GCP uses Workload Identity Federation with a pool + provider model. The provider maps
GitHub OIDC claims to GCP attributes; a binding then grants a Service Account to a
specific repo.

**One-time setup (run by platform team):**

```bash
PROJECT_ID="your-project-id"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
ORG="YOUR_ORG"
REPO="YOUR_REPO"

# 1. Create the workload identity pool
gcloud iam workload-identity-pools create "github-pool" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions"

# 2. Create the OIDC provider inside the pool
#    attribute-condition restricts to your org — without it, any GitHub repo could attempt exchange
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == '${ORG}'"

# 3. Bind a Service Account to the pool — scoped to a specific repo
#    principalSet scopes to all tokens where attribute.repository matches
gcloud iam service-accounts add-iam-policy-binding \
  "SA_NAME@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/${ORG}/${REPO}"

# 4. Grant the SA the roles it needs
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:SA_NAME@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"
```

**In the workflow step:**

```yaml
permissions:
  id-token: write
  contents: read

- uses: google-github-actions/auth@6fc4af4b145ae7821d527454aa9bd537d1f2dc5f  # v2.1.7
  with:
    workload_identity_provider: "projects/${{ secrets.GCP_PROJECT_NUMBER }}/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
    service_account: "${{ secrets.GCP_SERVICE_ACCOUNT }}"
```

**Why `attribute-condition` is non-negotiable:**

Without the condition `assertion.repository_owner == 'YOUR_ORG'`, any GitHub Actions
workflow in any public or private repository could present a valid GitHub OIDC token and
attempt token exchange against your pool. The condition gates it to tokens issued for
your organisation's repos only.

---

## Versioning strategy

Callers reference workflows by semver tag:

```yaml
jobs:
  build:
    uses: YOUR_ORG/.github/workflows/container-build-scan-push.yml@v1.2.0
    secrets: inherit
```

| Change type | Version bump | What callers must do |
|---|---|---|
| New optional input, backward compatible | Minor `v1.1.0 → v1.2.0` | Nothing — pick up on next explicit bump |
| Input renamed, output removed, new required secret | Major `v1.x → v2.0.0` | Update the `@v1.x` reference and adapt callers |
| Bug fix, tool patch version | Patch `v1.2.0 → v1.2.1` | Nothing |

**Floating major tags** (`v1`, `v2`) are maintained for teams that prefer loose pinning.
Security-sensitive workflows (container build, terraform) should pin to patch.

Breaking changes are announced in [CHANGELOG.md](CHANGELOG.md) with migration notes
at least **two weeks** before the old major is deprecated.

---

## What's hard about this in practice

### 1. Version drift

Teams pin to `@v1` and never upgrade. Two years later you want to deprecate `v1` because
it has a critical security gap, and you discover three teams are still on it because
"nobody broke anything." The fix is not technical — it's governance: track adoption by
version in a dashboard (the GitHub API can query all workflow files across the org),
set a deprecation SLA (six months after a major drop is reasonable), and escalate to
eng leads when teams miss it. Automated Dependabot PRs help surface the upgrade but
don't substitute for the conversation with each team owner.

### 2. Fork PRs and secret access

The `pull_request` event from a forked repo **cannot access secrets** — GitHub blocks it
by design to prevent secret exfiltration by external contributors. This means Trivy
cannot push scan results, and registry auth for SBOM upload fails. The workaround is
`pull_request_target`, which runs with write access to the base repo — but that means
a malicious PR can exfiltrate secrets if the workflow checks out the PR's code in that
context. The correct pattern is to split the workflow: run code-only jobs (lint, unit
tests) on `pull_request` with no secrets; run registry push and scan upload only on
push to a protected branch. All workflows here follow this split.

### 3. OIDC subject claim precision

The `sub` claim encodes the exact trigger context as a tuple of (repo, trigger type).
`repo:ORG/REPO:ref:refs/heads/main` works for a push to `main` but silently fails for
a `workflow_dispatch` on a tag — because the dispatch generates
`repo:ORG/REPO:ref:refs/tags/v1.2.0`, which is a different subject. Teams configure
a broad environment trust, hit a prod deployment via a manual trigger, and get a 401
they cannot explain because the Azure portal shows no detail on which claim mismatched.
Mental model: **the subject is a tuple and must be an exact string match**.

### 4. SHA pinning friction

Pinning actions to commit SHAs (`uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683`)
is the correct security practice. If a maintainer silently rewrites a tag to point to
malicious code, a SHA pin is unaffected — the SHA is immutable. The tradeoff is
readability and maintenance overhead. The answer to "why bother" is the
`tj-actions/changed-files` incident (March 2025): the action's tags were repointed to
code that dumped secrets from runner memory into public workflow logs across thousands
of repos. Repos pinned to SHAs were not affected. After that conversation, engineers
pin. Dependabot handles automated SHA bump PRs if you add:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

### 5. Breaking changes in composite actions

If you rename an output in `setup-tools/action.yml`, every caller silently receives an
empty string instead of the tool path — no error at parse time, a confusing runtime
failure that looks like the tool is not installed. Composite actions are referenced by
path, not by tag, so they cannot be independently versioned in the same way workflows
are. The discipline: treat any output removal or rename as a **major breaking change**,
add the new output while keeping the old name for one full release cycle, then drop the
old name in the next major bump. Document every composite action output as part of its
contract, same as a reusable workflow.

---

## Quick-start for a product team

1. Register the required secrets in your repo (see [docs/README.md](docs/README.md) for the list per workflow)
2. Call the workflow from your `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    uses: YOUR_ORG/.github/workflows/container-build-scan-push.yml@v1.0.0
    with:
      image-name: my-app
      registry: myregistry.azurecr.io
    secrets: inherit
```

3. Pin to a specific version tag, not `@main`
4. Read [docs/adoption-guide.md](docs/adoption-guide.md) if migrating from a bespoke pipeline

---

*Authored by [Jithin Karkera](https://github.com/jithin2)*
