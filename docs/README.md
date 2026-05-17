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
**Purpose:** Run `terraform fmt`, `validate`, `tflint`, Checkov security scan,
post the plan as a PR comment, and apply on merge to the default branch.

> Full input/output table added in Step 3.

### Required secrets

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | OIDC — if targeting Azure |
| `AZURE_TENANT_ID` | OIDC — if targeting Azure |
| `AZURE_SUBSCRIPTION_ID` | OIDC — if targeting Azure |
| `GCP_PROJECT_NUMBER` | OIDC — if targeting GCP |
| `GCP_SERVICE_ACCOUNT` | OIDC — if targeting GCP |
| `TF_BACKEND_CONFIG` | Optional backend config override |

---

## argocd-sync

**File:** `.github/workflows/argocd-sync.yml`  
**Purpose:** Trigger an ArgoCD application sync via the ArgoCD API after an image
has been promoted to the target registry.

> Full input/output table added in Step 3.

### Required secrets

| Secret | Description |
|---|---|
| `ARGOCD_SERVER` | ArgoCD server hostname (no `https://` prefix) |
| `ARGOCD_AUTH_TOKEN` | ArgoCD API token with sync permission on the target app |

---

## python-quality

**File:** `.github/workflows/python-quality.yml`  
**Purpose:** Run ruff lint + format check, mypy static type checking, and pytest
with an enforced minimum coverage threshold.

> Full input/output table added in Step 3.

### Required secrets

None — this workflow runs entirely in the GitHub Actions runner.

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
