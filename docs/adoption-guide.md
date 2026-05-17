# Adoption guide

How to migrate from a bespoke pipeline to this platform's reusable workflows.
Expect the migration to take half a day for a straightforward containerised app,
and a full day if your existing pipeline has accumulated significant custom logic.

---

## Before you start

Work through this checklist before touching any YAML:

- [ ] Confirm your repo is in the same GitHub org as this template repo
- [ ] Identify which workflows you need (container build? helm? terraform? all?)
- [ ] Request OIDC credentials from the platform team (or set up your own using [security-model.md](security-model.md))
- [ ] Register required secrets in your repo Settings → Secrets and variables → Actions
- [ ] Read the "what it does" section for each workflow you plan to call — understand every input before you wire it

---

## Migration path

### Step 1: Audit your existing pipeline

Map each job in your current workflow to a platform workflow:

| Your existing job | Platform workflow to call |
|---|---|
| Docker build + push | `container-build-scan-push` |
| helm lint / template render | `helm-lint-template` |
| terraform plan/apply | `terraform-plan-apply` |
| Deploy / sync ArgoCD | `argocd-sync` |
| Python lint / test | `python-quality` |

Note any custom steps that have no platform equivalent — you will need to keep those in your own workflow calling the platform workflow as a job.

### Step 2: Create a parallel workflow file

Do not delete your existing workflow yet. Create a new file, e.g. `.github/workflows/ci-platform.yml`,
and wire it up alongside the existing one. This lets you compare outputs before committing to the migration.

### Step 3: Register secrets

See [docs/README.md](README.md) for the required secrets list per workflow.
Register them in your repo under Settings → Secrets and variables → Actions → Repository secrets,
or in a GitHub Environment if you're using environment-scoped trust (recommended for production).

### Step 4: Run in parallel and compare

Trigger both workflows on a branch and compare results. Pay attention to:
- Image tag format (the platform workflow uses `<registry>/<name>:<sha>` by default)
- Scan thresholds (Trivy CRITICAL is a hard fail by default)
- Coverage threshold (pytest defaults to 80% — adjust via input if needed)

### Step 5: Cut over and remove the old workflow

Once you're satisfied the platform workflow covers your requirements, delete the old file
and open a PR. Tag the platform team for awareness.

---

## Common sticking points

**"My Dockerfile is in a subdirectory"**  
Pass `context` and `dockerfile` inputs to `container-build-scan-push`. The workflow accepts
both as optional inputs.

**"We need a custom Trivy severity threshold"**  
Use the `trivy-severity` input (default: `CRITICAL,HIGH`). Set to `CRITICAL` only if you
have a backlog of HIGH findings you're working down.

**"Our terraform state is in a different backend config per environment"**  
Pass `backend-config` as an input. The workflow runs `terraform init -backend-config=...`
before plan/apply.

**"We use a private Helm chart repo"**  
The `setup-tools` composite action installs Helm. You'll need to add a `helm repo add`
step in your calling workflow before invoking `helm-lint-template`.

**"We have a monorepo and only want CI to run on changed paths"**  
Use `paths` filters in your trigger in the calling workflow. The platform workflows do not
impose trigger conditions — that is the product team's responsibility.

---

## Getting help

- Open an issue in this repository with the `adoption` label
- Ping the platform team in `#platform-eng` (Slack)
- See [security-model.md](security-model.md) for OIDC setup help
