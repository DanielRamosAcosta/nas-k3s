# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

K3s homelab infrastructure-as-code using **Jsonnet + Tanka** for declarative Kubernetes deployments on a personal NAS. Manages a self-hosted stack: media apps, databases, monitoring, authentication, and system services.

## Available Tools

- **jq** — Available for inspecting/transforming JSON (e.g. `tk eval ... | jq '.field'`)

## Security

**NEVER pass secrets through Claude's context. NEVER.** This includes private keys, passwords, API keys, tokens, OIDC client secrets, or any other sensitive value — do not print them, echo them, paste them into a prompt, or include them in tool arguments where they'd be captured in the conversation.

When you need to generate keys/secrets:

1. **Always redirect the output to a file** instead of printing it to stdout (where it would land in the context).
   ```bash
   # WRONG — secret ends up in Claude's context:
   openssl rand -base64 32

   # CORRECT — secret goes to a file, never shown:
   openssl rand -base64 32 > /tmp/secret.txt
   ```
2. **Pipe the file into the consuming command** (e.g. the encryption script) without ever reading its contents:
   ```bash
   cat /tmp/secret.txt | ./scripts/encrypt-secret.sh <namespace> <sealed-secret-name>
   ```
3. **Delete the file immediately after use — this is critical.**
   ```bash
   rm -f /tmp/secret.txt
   ```

Only the encrypted (SealedSecret) output is safe to commit and to display. The plaintext secret must never be read with the Read tool, printed, or otherwise surfaced into the conversation.

## Adding a new service: minimize config

**Always check the defaults before writing config.** The tendency is to copy a full generated config and include everything — this creates noise and makes real non-default values harder to spot.

Before writing `homeserver.yaml`, `config.yaml`, or any service config file:

1. Read the official docs or the default config the image generates (`--generate-config`, `-e`, dry-run, etc.) to know what the defaults actually are.
2. Only include values that differ from the default, are required to be set explicitly (e.g. `report_stats` in Synapse), or have a specific reason to be spelled out.
3. For paths (data dir, signing key, media store, etc.) — check if mounting at the default path is feasible before adding a config override.
4. For listener/network config — check which fields have sane defaults (`tls: false`, `type: http`) versus which actually need to be set (`bind_addresses`, `x_forwarded`).

A config file with 10 lines where every line matters is better than 40 lines where 30 are defaults.

## Observability: logs

**Always query logs via Loki through the `grafanaSelfHosted` MCP server. Do NOT use `kubectl logs` for log inspection.**

Loki aggregates logs from every pod in the cluster and lets you filter by time range, level, and pattern without needing the pod to still exist. `kubectl logs` only sees the current container instance and loses history on restarts.

Typical flow:
1. `mcp__grafanaSelfHosted__list_datasources` with `type: loki` → get the datasource `uid` (currently `P8E80F9AEF21F6940`).
2. `mcp__grafanaSelfHosted__query_loki_logs` with a LogQL selector. Useful labels: `namespace`, `pod`, `container`, `service_name`, `level`.
   - Example: `{namespace="media", pod=~"immich.*"} |~ "(?i)error|warn|fail"`
3. If unsure about labels, use `list_loki_label_values` (e.g. `labelName: namespace`) before querying.
4. For noisy streams, prefer `query_loki_patterns` or `find_error_pattern_logs` to cluster errors.

Namespace cheatsheet: `argocd`, `arr`, `business`, `communications`, `databases`, `kube-system`, `media`, `monitoring`, `system`. (Apps are grouped by category, not per-app namespace — e.g. immich lives in `media`, not `immich`.)

`kubectl logs` is only acceptable as a last resort when Loki/Promtail is itself broken.

## Key Commands

```bash
# Sealed Secrets
echo -n 'value' | ./scripts/encrypt-secret.sh <namespace> <sealed-secret-name>  # Strict scope
echo -n 'value' | ./scripts/encrypt-secret.sh --cluster-wide                     # Cluster-wide scope

# Jsonnet dependencies
jb install              # Install jsonnet-bundler dependencies into vendor/

# Tanka workflow
tk eval environments/<category>                        # Compile Jsonnet to JSON
tk export dist/ environments/ --recursive --format '{{index .metadata.labels "app"}}/{{.kind}}-{{.metadata.name}}'  # Export all manifests

# Deployment (GitOps via ArgoCD — NEVER use tk apply directly)
# 1. Commit + push to main
# 2. CI exports manifests to 'manifests' branch
# 3. ArgoCD detects changes → sync manually from UI or CLI
argocd app sync <app-name> --grpc-web                  # Sync a single app
```

## Architecture

### Toolchain
- **Tanka (tk)** - Kubernetes deployment tool built on Jsonnet
- **Jsonnet** - Data templating language (all K8s manifests are generated from .libsonnet files)
- **jsonnet-bundler (jb)** - Dependency manager for Jsonnet libraries
- **k8s-libsonnet 1.29** - Typed Kubernetes API bindings via `lib/k.libsonnet`

### Directory Layout
- **`lib/`** - Jsonnet libraries defining each application. Each app is a `.libsonnet` module with a `new(version)` factory that returns all its K8s resources (StatefulSet/Deployment, Service, ConfigMap, Secret, IngressRoute).
  - `utils.libsonnet` - Shared helpers for hostPath volumes, secrets, config maps, ingress routes, RBAC, volume mounts, and Traefik middleware
  - `<appname>.secrets.json` - Kubeseal-encrypted secret values (gitignored), one per app alongside its `.libsonnet`
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
    ingress_route: u.ingressRoute.from(this.service, 'app.domain.com'),
    // volumes are hostPath, defined inline in the statefulset/deployment spec:
    // volume.fromHostPath('data', '/data/appname'),
  }
}
```

Environments compose these modules in `main.jsonnet`, passing versions from `versions.json`.

### Networking & Auth
- **Traefik** ingress controller with IngressRoute CRDs and Let's Encrypt TLS
- **Authelia** provides OIDC/forward-auth; middleware is applied via `utils.traefik.middleware`
- Services communicate internally via Kubernetes DNS (`svc.cluster.local`)

### Storage
- All volumes use **hostPath** directly (no PV/PVC) — simpler for a single-node NAS homelab
- Data paths: `/data/*` (SSD, app state) and `/cold-data/*` (HDD, media/backups)
- Helper: `u.volume.fromHostPath(name, path)` or `volume.fromHostPath(name, path)` from k8s-libsonnet

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

### ArgoCD

ArgoCD manages all deployments via GitOps. It lives in `environments/argocd/` with namespace `argocd`.

#### Architecture
- **CI** exports manifests to `manifests` branch on push to main
- **ArgoCD** reads YAMLs from `manifests` branch (no plugins/sidecars)
- **Webhook** notifies ArgoCD on push for instant detection (no polling)
- **Manual sync** — ArgoCD detects drift but does NOT auto-apply

#### Config changes auto-restart pods (Reloader) — do NOT `kubectl rollout restart` manually

**Stakater Reloader is installed cluster-wide and handles this for you. Never manually restart a pod just to pick up a ConfigMap/Secret change.**

`u.labelApp()` (via `u.Environment`, in `lib/utils/core.libsonnet`) automatically stamps every Deployment/StatefulSet/DaemonSet with the annotation `reloader.stakater.com/auto: "true"`. Reloader watches the ConfigMaps/Secrets each workload references and **rolls the pod automatically (within a few seconds) whenever their content changes** — including envsubst-rendered config templates like `synapse-homeserver-tpl`.

Consequence for the deploy flow: a ConfigMap/Secret-only change (no Deployment spec change) still rolls the pod on its own. After `/deploy`, just wait for ArgoCD to sync the new ConfigMap; Reloader restarts the workload. Confirm via Reloader's logs (`{namespace="kube-system", pod=~"reloader.*"}` in Loki — look for "Changes detected in '<configmap>' ... updated '<workload>'") instead of restarting by hand.

#### Applications
One Application per service (not per namespace). Generated dynamically in `argocd/main.jsonnet` by importing all other environments and extracting `app` labels from resources. When adding a new service, just add it to the environment's `main.jsonnet` with `u.labelApp()` and ArgoCD picks it up automatically.

#### OIDC
ArgoCD uses Authelia for SSO. Client IDs and secret are stored in SealedSecret `argocd-oidc-secret` and referenced from `argocd-cm` via `$argocd-oidc-secret:key-name` syntax. The `argocd-secret` (with `server.secretkey` and `webhook.github.secret`) is also a SealedSecret — the Helm chart's `createSecret` is disabled.

#### CRITICAL: Deleting ArgoCD Applications

**NEVER use `argocd app delete <name>` without `--cascade=false`**. By default, deleting an Application also deletes ALL cluster resources it manages (prune). This will take down services.

```bash
# WRONG — deletes all resources managed by the app from the cluster:
argocd app delete myapp -y

# CORRECT — only removes the Application resource, keeps cluster resources:
argocd app delete myapp --cascade=false
```

#### Server-Side Apply
The `argocd` Application uses `syncOptions: [ServerSideApply=true]` because the `applicationsets` CRD exceeds the 262KB annotation limit for client-side apply.

## Project Management

All work is tracked in **Backlog.md** via the backlog MCP server. Use the backlog MCP tools to read, create, edit, and complete tasks.

### Rules

1. **No work without a ticket.** Always have one or more tasks in `in_progress` that represent the current work. If none exist, find or create the appropriate task before starting.
2. **Refinement flow.** When asked to refine a task: read it, ask questions to reduce uncertainty, and iterate until the user says OK. Only then add the `refined` tag. Do NOT start implementation during refinement.
3. **Completion flow.** When a task is done, confirm with the user. Only after explicit approval: mark as `done` and commit.
4. **Never self-approve.** Do not move tasks to `done` or commit without the user's explicit OK.

### Backlog MCP: completing tasks

When finishing a task, only use `task_edit` with `status: "Done"`. Do NOT call `task_complete` — tasks should not be archived.
