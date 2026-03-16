---
id: NASKS-16
title: Migrate Tanka directory to its own repository
status: Done
assignee: []
created_date: '2026-03-09 18:07'
updated_date: '2026-03-16 11:07'
labels:
  - infrastructure
  - kubernetes
  - argocd
dependencies: []
priority: medium
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extract the `tanka/` directory from this NAS configuration repository into its own standalone Git repository. This separation is needed to eventually migrate the Kubernetes deployment workflow from Tanka (jsonnet) to ArgoCD, which expects application manifests in dedicated repositories.

Scope includes:
- Create a new Git repository for the Tanka/Kubernetes configuration
- Move `tanka/` contents (environments, lib, justfile, jsonnetfile, etc.)
- Update any references in the NAS repo that point to tanka paths
- Ensure the new repo is self-contained with its own CI, secrets management, and documentation
- Preserve Git history for the tanka directory if possible
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tanka configuration lives in its own standalone Git repository
- [ ] #2 New repo builds and deploys successfully independent of the NAS repo
- [ ] #3 NAS repo no longer contains tanka/ directory
- [ ] #4 Git history for tanka files is preserved in the new repo
- [ ] #5 Documentation updated in both repos to reflect the separation
<!-- AC:END -->
