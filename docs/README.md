# Workflow catalogue

Complete input/output/secrets reference for every reusable workflow in this repository.

---

## container-build-scan-push

**File:** `.github/workflows/container-build-scan-push.yml`  
**Purpose:** Build Docker image, Trivy vulnerability scan (exit 1 on findings),
CycloneDX SBOM generation, SARIF upload to GitHub Advanced Security, push to
ACR or GAR via OIDC. Scan-before-push: a vulnerable image is never published.

### Inputs

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `image-name` | string | yes | — | Image name without registry prefix |
| `registry` | string | yes | — | Registry hostname |
| `registry-type` | string | no | `acr` | `acr` or `gar` |
| `context` | string | no | `.` | Docker build context |
| `dockerfile` | string | no | `Dockerfile` | Path to Dockerfile |
| `image-tag` | string | no | 8-char git SHA | Tag to apply |
| `trivy-severity` | string | no | `CRITICAL,HIGH` | Severities that fail the scan |
| `trivy-ignore-unfixed` | boolean | no | `false` | Skip findings with no fix |
| `push` | boolean | no | `true` | Push after passing scan |
| `platforms` | string | no | `linux/amd64` | Build platform(s) |

### Outputs

| Name | Description |
|---|---|
| `image-digest` | SHA256 digest of the pushed image |
| `image-ref` | Full reference: `registry/name:tag` |
| `sbom-artifact` | Name of uploaded SBOM artifact in GitHub Actions |

### Secrets

| Secret | Required when | Description |
|---|---|---|
| `AZURE_CLIENT_ID` | `registry-type=acr` | App Registration client ID (OIDC) |
| `AZURE_TENANT_ID` | `registry-type=acr` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | `registry-type=acr` | Subscription containing the ACR |
| `GCP_PROJECT_NUMBER` | `registry-type=gar` | GCP project number for WIF provider path |
| `GCP_SERVICE_ACCOUNT` | `registry-type=gar` | SA email with Artifact Registry Writer role |

---

## helm-lint-template

**File:** `.github/workflows/helm-lint-template.yml`  
**Purpose:** `helm lint --strict`, render with `helm template`, validate rendered
manifests offline against Kubernetes JSON schemas via kubeconform. No cloud
credentials — runs entirely in the runner.

### Inputs

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `chart-path` | string | yes | — | Path to the Helm chart directory |
| `values-file` | string | no | `""` | Additional values file |
| `release-name` | string | no | `ci-release` | Release name for template render |
| `kubernetes-version` | string | no | `1.29.0` | Target k8s version for schema validation |
| `kubeconform-strict` | boolean | no | `true` | Fail on unknown fields |
| `helm-args` | string | no | `""` | Extra flags for lint and template |

### Outputs

None — validation only, no artifact produced.

### Secrets

None — no cloud or registry authentication required.

---

## terraform-plan-apply

**File:** `.github/workflows/terraform-plan-apply.yml`  
**Purpose:** fmt → validate → tflint → Checkov → plan. Plan output posted as
a PR comment (updated on each commit, not duplicated). Apply runs on push to
the apply branch (default: `main`). Re-plans on apply — never reuses a stale
plan file from the PR run.

### Inputs

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `working-directory` | string | yes | — | Directory containing .tf files |
| `terraform-version` | string | no | `1.9.8` | Terraform version |
| `cloud-provider` | string | no | `azure` | `azure` or `gcp` for OIDC |
| `backend-config-file` | string | no | `""` | Path to backend .tfvars |
| `var-file` | string | no | `""` | Path to .tfvars for plan/apply |
| `apply-on-branch` | string | no | `main` | Branch that triggers apply |
| `tflint-soft-fail` | boolean | no | `false` | tflint findings as warnings |
| `checkov-soft-fail` | boolean | no | `false` | Checkov findings as warnings |

### Outputs

| Name | Description |
|---|---|
| `plan-exit-code` | `0`=no changes, `1`=error, `2`=changes present |

### Secrets

| Secret | Required when | Description |
|---|---|---|
| `AZURE_CLIENT_ID` | `cloud-provider=azure` | OIDC App Registration client ID |
| `AZURE_TENANT_ID` | `cloud-provider=azure` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | `cloud-provider=azure` | Azure subscription ID |
| `GCP_PROJECT_NUMBER` | `cloud-provider=gcp` | GCP project number |
| `GCP_SERVICE_ACCOUNT` | `cloud-provider=gcp` | SA email for WIF |

---

## argocd-sync

**File:** `.github/workflows/argocd-sync.yml`  
**Purpose:** Trigger ArgoCD app sync via CLI after image promotion. Optionally
waits for Healthy + Synced status. Queues concurrent syncs for the same app
(does not cancel in-progress — concurrent syncs would conflict in ArgoCD).

### Inputs

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `app-name` | string | yes | — | ArgoCD application name |
| `revision` | string | no | `HEAD` | Git revision to sync to |
| `prune` | boolean | no | `false` | Remove resources absent from Git |
| `wait` | boolean | no | `true` | Wait for Healthy + Synced |
| `wait-timeout` | number | no | `300` | Seconds before timeout |
| `argocd-version` | string | no | `2.13.0` | ArgoCD CLI version |
| `insecure-skip-tls-verify` | boolean | no | `false` | Skip TLS cert verification |

### Outputs

| Name | Description |
|---|---|
| `sync-status` | Final ArgoCD sync status (`Synced`, `OutOfSync`, etc.) |

### Secrets

| Secret | Required | Description |
|---|---|---|
| `ARGOCD_SERVER` | yes | Server hostname without `https://` |
| `ARGOCD_AUTH_TOKEN` | yes | API token with sync + get on the target app |

---

## python-quality

**File:** `.github/workflows/python-quality.yml`  
**Purpose:** ruff lint → ruff format check → mypy type checking → pytest with
enforced coverage threshold. Tool versions are centrally pinned. ruff replaces
flake8 + isort + black.

### Inputs

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `python-version` | string | no | `3.12` | Python version |
| `source-path` | string | no | `.` | Directory to lint/type-check |
| `test-path` | string | no | `tests/` | Directory containing tests |
| `coverage-threshold` | number | no | `80` | Minimum coverage % |
| `ruff-version` | string | no | `0.8.6` | ruff PyPI version |
| `mypy-version` | string | no | `1.13.0` | mypy PyPI version |
| `pytest-version` | string | no | `8.3.4` | pytest PyPI version |
| `pytest-cov-version` | string | no | `6.0.0` | pytest-cov PyPI version |
| `mypy-soft-fail` | boolean | no | `false` | mypy errors as warnings |
| `install-deps` | boolean | no | `true` | Install requirements*.txt |

### Outputs

| Name | Description |
|---|---|
| `coverage-pct` | Final coverage percentage reported by pytest-cov |

### Secrets

None — runs entirely in the GitHub Actions runner.

---

## Composite actions

### setup-tools

**File:** `.github/actions/setup-tools/action.yml`  
**Purpose:** Download and install Trivy, Helm, kubeconform, tflint, and Checkov at
platform-pinned versions. All binaries are fetched directly from official release
pages — no intermediate installer actions needed. Boolean inputs allow callers
to skip tools they don't use.

| Tool | Default version | Why pinned centrally | Note |
|---|---|---|---|
| Trivy | 0.58.2 | Version affects CVE database format + SARIF schema | Verify: [aquasecurity/trivy/releases](https://github.com/aquasecurity/trivy/releases) |
| Helm | 3.17.0 | Minor versions change template output and default values | — |
| kubeconform | 0.6.7 | Schema set tied to k8s release; old version = false negatives | — |
| tflint | 0.54.0 | Rule changes between versions can flip pass/fail | — |
| Checkov | 3.2.350 | Replaces archived tfsec — [see archival notice](https://github.com/aquasecurity/tfsec) | pip install |

### Outputs

| Name | Description |
|---|---|
| `trivy-version` | Installed Trivy version |
| `helm-version` | Installed Helm version |
| `kubeconform-version` | Installed kubeconform version |
