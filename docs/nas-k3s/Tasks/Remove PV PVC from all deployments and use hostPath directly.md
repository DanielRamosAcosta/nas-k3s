---
title: Remove PV/PVC from all deployments and use hostPath directly
status: Done
created_date: '2026-03-09 17:08'
labels:
  - tanka
  - kubernetes
  - simplification
dependencies: []
priority: 2
ordinal: 42000
---

## Description

The current Kubernetes deployments use PersistentVolumes and PersistentVolumeClaims for storage, which is overkill for a single-node K3s cluster. Replace all PV/PVC definitions with direct hostPath volume mounts in the pod specs. This simplifies the storage configuration and removes unnecessary abstraction.
