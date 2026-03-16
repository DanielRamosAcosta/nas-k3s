---
id: NASKS-13
title: Remove PV/PVC from all deployments and use hostPath directly
status: To Do
assignee: []
created_date: '2026-03-09 17:08'
updated_date: '2026-03-16 11:05'
labels:
  - tanka
  - kubernetes
  - simplification
dependencies: []
priority: medium
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The current Kubernetes deployments use PersistentVolumes and PersistentVolumeClaims for storage, which is overkill for a single-node K3s cluster. Replace all PV/PVC definitions with direct hostPath volume mounts in the pod specs. This simplifies the storage configuration and removes unnecessary abstraction.
<!-- SECTION:DESCRIPTION:END -->
