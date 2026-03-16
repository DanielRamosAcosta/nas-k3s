---
name: deploy
description: Create PR, wait for CI, squash merge, watch ArgoCD rollout, and verify pods/logs
disable-model-invocation: true
---

# /deploy

Deploy the current changes through the full GitOps pipeline. Follow every step in order — do NOT skip verification.

## Pre-flight

Before starting, determine which services are affected by the current changes:
1. Run `git diff --name-only` to see changed files
2. Map changed `lib/<category>/<app>` paths to their Kubernetes namespace (from `environments/<category>/spec.json`) and app/pod names
3. Keep this list — you'll need it for verification later

## Step 1 — Create PR

- Create a new branch from the current state (use a descriptive name based on the changes)
- Push the branch and create a PR with `gh pr create`
- Use a clear title and summary describing what changed

## Step 2 — Watch CI

- Get the PR number and watch the CI workflow: `gh pr checks <number> --watch`
- If CI fails, investigate the failure, fix it, push again, and re-watch
- Do NOT proceed until all checks pass

## Step 3 — Squash merge

- Once CI is green, squash merge: `gh pr merge <number> --squash --delete-branch`
- Confirm the merge succeeded

## Step 4 — Watch ArgoCD detect the change

Do NOT use `sleep`. Instead, actively poll for the rollout:

1. First, wait for the `manifests` branch to update (CI exports manifests on push to main):
   ```
   gh run list --branch main --limit 1 --json status,conclusion
   ```
   Poll this with `gh run watch` until the post-merge CI run completes.

2. Then watch the affected pods for restart/rollout using kubectl:
   ```
   kubectl get pods -n <namespace> -l app=<app-name> -w
   ```
   Use a short timeout (90s). Look for new pod creation or container restart.
   If the pod doesn't restart, check if ArgoCD has synced:
   ```
   argocd app get <app-name> --grpc-web -o json | jq '{syncStatus: .status.sync.status, healthStatus: .status.health.status}'
   ```

## Step 5 — Verify health

For each affected service:

1. **Pod status**: Confirm the pod is Running and containers are Ready:
   ```
   kubectl get pods -n <namespace> -l app=<app-name>
   ```

2. **Logs**: Check recent logs for errors (last 2 minutes since rollout):
   ```
   kubectl logs -n <namespace> -l app=<app-name> --tail=50 --since=2m
   ```

3. **Probes** (if the change added/modified probes): Confirm no restart loops by checking `RESTARTS` column and describe the pod to verify probe config:
   ```
   kubectl describe pod -n <namespace> -l app=<app-name> | grep -A5 'Liveness\|Readiness\|Startup'
   ```

4. **Related services**: If the change could affect dependent services (e.g. a DB change might affect apps using it), check those pods too.

Report a clear summary: which pods rolled, current status, and any warnings from logs.
