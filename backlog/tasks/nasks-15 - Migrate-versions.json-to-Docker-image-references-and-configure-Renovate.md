---
id: nasks-15
title: Migrate versions.json to Docker image references and configure Renovate
status: In Progress
assignee: []
created_date: '2026-03-09 17:22'
updated_date: '2026-03-09 18:05'
labels:
  - devops
  - automation
dependencies: []
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Unify `tanka/environments/versions.json` so that every entry uses a full Docker image reference instead of a mix of GitHub repos and Docker registry paths. Then configure Renovate to automatically create PRs when new image tags are available.

**Current state:** `versions.json` mixes GitHub org/repo format (`immich-app/immich`) with Docker registry paths (`ghcr.io/hotio/sonarr`). The actual Docker image names are hardcoded as defaults in each libsonnet file (e.g., `image='docker.io/jellyfin/jellyfin'`).

**Target state:**
1. Rename `repo` → `image` in `versions.json`, using full Docker image references (e.g., `ghcr.io/immich-app/immich-server`, `docker.io/grafana/grafana`)
2. Update all libsonnet files to read the image name from the versions config instead of hardcoding it
3. Update `utils.image()` if needed
4. Add `renovate.json` with a `docker` datasource custom manager that parses `versions.json`
5. Install Renovate GitHub App on the repo

**Version format notes:**
- Most use semver with optional `v` prefix
- Some use custom formats: `release-4.0.16.2944` (hotio), `2.6.1-ls311` (linuxserver), `latest` (invidious)
- Renovate's docker datasource handles these natively by querying registry tags
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All entries in versions.json use full Docker image references
- [ ] #2 All libsonnet files read image from versions config
- [ ] #3 renovate.json configured with docker datasource custom manager
- [ ] #4 Renovate creates PRs automatically for new image tags
- [ ] #5 Existing deployments continue working after migration
- [ ] #6 tk diff shows no changes before starting the migration
- [ ] #7 tk diff shows no changes after migrating versions.json and updating libsonnet files (zero-diff migration)
- [ ] #8 Delete check-versions.ts script (replaced by Renovate)
<!-- AC:END -->
