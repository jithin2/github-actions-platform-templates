# Changelog

All notable changes to platform workflow versions are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions follow [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- Initial release of all five reusable workflows
- `container-build-scan-push` — Docker build, Trivy scan, SBOM, push to ACR/GAR
- `helm-lint-template` — helm lint + template + kubeconform validation
- `terraform-plan-apply` — fmt, validate, tflint, Checkov, plan-as-PR-comment, apply
- `argocd-sync` — ArgoCD app sync trigger
- `python-quality` — ruff, mypy, pytest with coverage threshold
- `setup-tools` composite action for pinned tool installation
- Consumer examples: app-with-helm, terraform-infra, ml-model-service
- OIDC setup documentation for Azure and GCP
- Adoption guide for teams migrating from bespoke pipelines

---

## Migration notes

### v1 → v2 (not yet released)

No breaking changes planned at this time.

---

## Deprecation schedule

| Version | Status | Deprecation date |
|---|---|---|
| v1.x | Active | — |
