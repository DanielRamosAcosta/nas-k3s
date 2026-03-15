# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

K3s homelab infrastructure-as-code using **Jsonnet + Tanka** for declarative Kubernetes deployments on a personal NAS. Manages a self-hosted stack: media apps, databases, monitoring, authentication, and system services.

## Key Commands

```bash
# Secret management
just encrypt-secrets    # Encrypt lib/secrets.json → lib/secrets.json.age (age + Ed25519)
just decrypt-secrets    # Decrypt lib/secrets.json.age → lib/secrets.json

# Jsonnet dependencies
jb install              # Install jsonnet-bundler dependencies into vendor/

# Tanka workflow
tk eval environments/<category>                        # Compile Jsonnet to JSON
tk apply environments/<category> --auto-approve=always # Deploy to cluster
tk export dist/ environments/<category>                # Export manifests to dist/
```

## Architecture

### Toolchain
- **Tanka (tk)** - Kubernetes deployment tool built on Jsonnet
- **Jsonnet** - Data templating language (all K8s manifests are generated from .libsonnet files)
- **jsonnet-bundler (jb)** - Dependency manager for Jsonnet libraries
- **k8s-libsonnet 1.29** - Typed Kubernetes API bindings via `lib/k.libsonnet`

### Directory Layout
- **`lib/`** - Jsonnet libraries defining each application. Each app is a `.libsonnet` module with a `new(version)` factory that returns all its K8s resources (StatefulSet/Deployment, Service, ConfigMap, Secret, PV/PVC, IngressRoute).
  - `utils.libsonnet` - Shared helpers for PV/PVC creation, secrets, config maps, ingress routes, RBAC, volume mounts, and Traefik middleware
  - `secrets.json` - Plaintext secrets (gitignored, encrypted at rest via age)
  - Subdirectories: `arr/`, `auth/`, `databases/`, `media/`, `monitoring/`, `system/`
- **`environments/`** - Tanka environment definitions. Each has `main.jsonnet` (imports libs, wires versions) + `spec.json` (namespace, API server).
  - `versions.json` - Centralized container image versions for all apps
- **`dist/`** - Generated YAML manifests (gitignored, output of `tk export`)
- **`charts/`** - Vendored Helm charts (Traefik, K8s Dashboard) managed via `chartfile.yaml`
- **`vendor/`** - Jsonnet dependencies (gitignored, installed via `jb install`)

### App Module Pattern

Every app in `lib/` follows this pattern:

```jsonnet
{
  new(version):: {
    local this = self,
    statefulset: /* or deployment */,
    service: /* ClusterIP service */,
    config_map: /* app config via importstr */,
    secret: /* from lib/secrets.json */,
    pv: utils.pv.localPathFor(this.statefulset, '10Gi', '/data/appname'),
    pvc: utils.pvc.from(self.pv),
    ingress_route: utils.ingressRoute.from(this.service, 'app.domain.com'),
  }
}
```

Environments compose these modules in `main.jsonnet`, passing versions from `versions.json`.

### Networking & Auth
- **Traefik** ingress controller with IngressRoute CRDs and Let's Encrypt TLS
- **Authelia** provides OIDC/forward-auth; middleware is applied via `utils.traefik.middleware`
- Services communicate internally via Kubernetes DNS (`svc.cluster.local`)

### Storage
- All PVs use `local-path` storage class with `hostPath` mounts from NAS paths (`/data/*`, `/cold-data/*`)
- `Retain` reclaim policy on all persistent volumes

### Secrets
- `lib/secrets.json` holds all secrets in plain JSON (gitignored)
- Encrypted with age to `lib/secrets.json.age` (committed)
- Public key: `id_dani.pub`, decryption key: `~/.ssh/id_ed25519`
- Secrets are injected into K8s Secret resources and referenced via env vars or volume mounts
