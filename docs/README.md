# Workflow catalogue

Complete input/output/secrets reference for every reusable workflow in this repository.

---

## container-build-scan-push

**File:** `.github/workflows/container-build-scan-push.yml`  
**Purpose:** Build a Docker image, run a Trivy vulnerability scan, generate an SBOM
with Syft, and push to Azure Container Registry or Google Artifact Registry.

> Full input/output table added in Step 2.

### Required secrets

| Secret | Where to register | Description |
|---|---|---|
| `AZURE_CLIENT_ID` | Repo or Environment | App Registration client ID for OIDC auth to ACR |
| `AZURE_TENANT_ID` | Repo or Environment | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Repo or Environment | Subscription containing the ACR |
| `GCP_PROJECT_NUMBER` | Repo or Environment | GCP project number (not ID) for WIF provider path |
| `GCP_SERVICE_ACCOUNT` | Repo or Environment | SA email with Artifact Registry Writer role |

Register only the secrets relevant to the cloud target you're pushing to.

---

## helm-lint-template

**File:** `.github/workflows/helm-lint-template.yml`  
**Purpose:** Run `helm lint`, render templates with `helm template`, and validate
rendered manifests against the target Kubernetes JSON schema via kubeconform.

> Full input/output table added in Step 2.

### Required secrets

None — this workflow does not authenticate to any cloud provider.

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
**Purpose:** Install and cache all shared tooling at pinned versions.
Called at the start of any workflow that needs tflint, Checkov, Trivy,
kubeconform, or Helm.

> Full output table added in Step 2.

| Tool | Why pinned here | Note |
|---|---|---|
| Trivy | Security scanner — version affects CVE database and output format | Verify latest at [aquasecurity/trivy](https://github.com/aquasecurity/trivy/releases) |
| Helm | Chart tooling — minor versions change template output | — |
| kubeconform | Schema validator — must match target k8s version | — |
| tflint | Terraform linter | — |
| Checkov | IaC security scanner — replaces archived tfsec | tfsec is archived; Checkov (Bridgecrew/Prisma) is the maintained successor |
