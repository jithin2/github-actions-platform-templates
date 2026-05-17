# Security model

This document covers where secrets live, what permissions each workflow requests,
and the complete OIDC trust setup for Azure and GCP.

> **Status:** Outline. Full OIDC walkthrough with worked examples delivered in Step 5.

---

## Sections (to be completed in Step 5)

### 1. Secret scopes and storage

Where each category of secret belongs:

- Repository secrets vs Environment secrets — when to use each
- Why long-lived cloud credentials are prohibited in this repo
- How to rotate a compromised OIDC credential (hint: it's just a federated credential deletion)

### 2. Workflow permission model

`permissions` blocks used by each workflow and why each permission is needed:

| Workflow | `id-token` | `contents` | `pull-requests` | `packages` |
|---|---|---|---|---|
| container-build-scan-push | write (OIDC) | read | — | write (GHCR fallback) |
| helm-lint-template | — | read | — | — |
| terraform-plan-apply | write (OIDC) | read | write (PR comment) | — |
| argocd-sync | — | read | — | — |
| python-quality | — | read | — | — |

### 3. Azure OIDC — full walkthrough

- App Registration creation and why no client secret
- Federated credential subject claim options (environment vs branch vs tag vs PR)
- RBAC assignment — least-privilege role mapping per workflow
- Debugging auth failures (decoding the raw JWT)

### 4. GCP OIDC — full walkthrough

- Workload Identity Pool + Provider creation
- Attribute mapping and why `attribute-condition` is required
- Service Account binding scoped to a specific repo
- `principalSet` vs `principal` — when each is appropriate
- Debugging token exchange failures via `gcloud` logs

### 5. Fork PR restrictions

- Why `pull_request` from a fork cannot access secrets
- The `pull_request_target` risk model
- The correct split: code-only jobs on PR, authenticated jobs on push to main

### 6. Action SHA pinning

- Supply chain threat model — what SHA pinning defends against
- `tj-actions/changed-files` incident as a worked example
- Dependabot configuration for automated SHA bump PRs
- Where SHA comments in this repo come from (release tag + SHA lookup)

### 7. SARIF upload and code scanning

- How Trivy SARIF output feeds into GitHub Advanced Security code scanning
- Required permissions for `security-events: write`
- What shows up in the Security tab vs workflow logs

### 8. Secrets in composite actions

- Composite actions cannot declare `secrets:` — they receive them via inputs
- Masking: any secret passed as an input is automatically masked in logs
- Why you should never `echo` a secret even in a debug step
