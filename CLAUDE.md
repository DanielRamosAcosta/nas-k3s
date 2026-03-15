# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

K3s homelab infrastructure-as-code using **Jsonnet + Tanka** for declarative Kubernetes deployments on a personal NAS. Manages a self-hosted stack: media apps, databases, monitoring, authentication, and system services.

## Key Commands

```bash
# Sealed Secrets
echo -n 'value' | ./scripts/encrypt-secret.sh <namespace> <sealed-secret-name>  # Strict scope
echo -n 'value' | ./scripts/encrypt-secret.sh --cluster-wide                     # Cluster-wide scope

# Jsonnet dependencies
jb install              # Install jsonnet-bundler dependencies into vendor/

# Tanka workflow
tk eval environments/<category>                        # Compile Jsonnet to JSON
tk apply environments/<category> --auto-approve=always # Deploy to cluster
tk export dist/ environments/ --recursive --format '{{env.spec.namespace}}/{{.kind}}-{{.metadata.name}}'  # Export all manifests
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
local secrets = import 'category/appname.secrets.json';
{
  new():: {
    local this = self,
    statefulset: /* or deployment */,
    service: /* ClusterIP service */,
    config_map: /* app config via importstr */,
    sealed_secret: u.sealedSecret.forEnv(self.statefulset, secrets.appname),
    pv: u.pv.localPathFor(this.statefulset, '10Gi', '/data/appname'),
    pvc: u.pvc.from(self.pv),
    ingress_route: u.ingressRoute.from(this.service, 'app.domain.com'),
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

### Secrets (Sealed Secrets)

All services use **Bitnami Sealed Secrets**. The controller runs in `kube-system` and decrypts `SealedSecret` resources into regular `Secret` resources in the cluster.

#### Encryption scopes

| Scope | When to use | Encrypt command |
|-------|-------------|-----------------|
| **strict** | Service-specific secrets (API keys, OIDC client secrets) | `echo -n 'value' \| ./scripts/encrypt-secret.sh <namespace> <sealed-secret-name>` |
| **cluster-wide** | Shared secrets (DB passwords, SMTP) reused across namespaces | `echo -n 'value' \| ./scripts/encrypt-secret.sh --cluster-wide` |

**Important**: You cannot mix strict and cluster-wide encrypted values in the same SealedSecret resource. Use separate resources (e.g. `sealed_secret` + `sealed_secret_shared`).

#### Secret file structure

Encrypted data lives in `<appname>.secrets.json` files alongside each `.libsonnet`:
```json
{
  "serviceName": {
    "SECRET_KEY": "kubeseal-encrypted-value"
  },
  "shared": {
    "DB_PASSWORD": "kubeseal-encrypted-value-cluster-wide"
  }
}
```

#### Utils API

**Strict scope** (service-specific):
- `u.sealedSecret.forEnv(component, encryptedData)` — SealedSecret with name derived from component
- `u.sealedSecret.forEnvNamed(name, encryptedData)` — SealedSecret with explicit name
- `u.sealedSecret.forFile(fileName, encryptedValue)` — SealedSecret for file mount

**Cluster-wide scope** (shared across namespaces):
- `u.sealedSecret.wide.forEnv(component, encryptedData)`
- `u.sealedSecret.wide.forEnvNamed(name, encryptedData)`
- `u.sealedSecret.wide.forFile(fileName, encryptedValue)`

**Referencing secrets**:
- `u.envVars.fromSealedSecret(sealedSecret)` — generates env var references
- `u.volumeMount.fromSealedSecretFile(sealedSecret, path)` — mount a file from SealedSecret
- `u.volume.fromSealedSecret(sealedSecret)` — volume referencing the decrypted Secret

#### Pattern: Config with embedded secrets (jq merge)

For apps that need a config file mixing public config + secrets (e.g. invidious, immich):

1. **ConfigMap** with public config (visible in git)
2. **SealedSecret** with only the secret fields as a JSON file
3. **Init container** with `jq` that deep-merges both: `jq -s '.[0] * .[1]' public.json secret.json > merged.json`
4. **Main container** reads the merged result

```jsonnet
invidiousConfigPublic: u.configMap.forFile('invidious-config.json', std.manifestJsonEx(config, '  ')),
invidiousConfigSecret: u.sealedSecret.wide.forFile('invidious-config-secret.json', secrets.configSecretFile),
// init container merges both, main container reads via env var or file mount
```

#### Legacy (age-encrypted secrets.json) — DEPRECATED

`lib/secrets.json` still exists (gitignored) but is no longer used by any service. All services have been migrated to Sealed Secrets. The file will be removed once ArgoCD prune cleans up the legacy Secret resources in the cluster.
