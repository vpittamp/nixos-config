# Runbook: Review ArgoCD app health and drift

## When to use

Use this for fleet-level reviews of OutOfSync, Degraded, Progressing, or stuck ArgoCD Applications across hub-managed `hub`, `dev`, `staging`, and `ryzen`.

The goal is not just to make Argo green. First decide whether each app/resource is still part of the current platform. Remove legacy resources declaratively; fix needed resources by making desired state and live state converge.

## Inventory

Hub ArgoCD is authoritative for hub and spokes. Dev/staging may not have local `applications.argoproj.io` CRDs.

```bash
kubectl --kubeconfig ~/.kube/hub-config get applications.argoproj.io -n argocd \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,PHASE:.status.operationState.phase,DEST:.spec.destination.name,REV:.status.sync.revision --no-headers |
  awk '$2!="Synced" || $3!="Healthy" || $4=="Running" {print}' | sort

kubectl --kubeconfig ~/.kube/hub-config get app root-application spoke-dev spoke-staging -n argocd \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,PHASE:.status.operationState.phase,REV:.status.sync.revision --no-headers
```

Useful grouping:

```bash
kubectl --kubeconfig ~/.kube/hub-config get applications.argoproj.io -n argocd -o json |
  jq -r '.items | group_by(.spec.destination.name // "hub")[] | "\((.[0].spec.destination.name // "hub")): \(length) apps"' | sort
```

## Decide keep vs remove

Before fixing drift, answer these questions:

- Is the app referenced by current overlays, ApplicationSets, docs, or active runtime code?
- Is it a CRD/bootstrap app that must sync before controllers or workloads?
- Is it only legacy scaffolding from a removed product or old provider path?
- Does the backing product still exist in the current platform?

Known decisions:

- Keep `agent-sandbox-crds` and `<spoke>-agent-sandbox-crds`. OpenShell and agent-runtime controllers require `AgentRuntime`, `Sandbox`, `SandboxClaim`, `SandboxTemplate`, and `SandboxWarmPool` CRDs. CRDs are split into a separate early-wave app intentionally.
- Keep hub Tekton/Gitea build apps when workflow-builder or OpenShell images still build through them.
- Remove AutoKube resources. AutoKube is legacy in this repo; do not repair AutoKube apps, Ingresses, ACL approvals, or manifests unless the product is explicitly reintroduced.
- The old hcloud-spoke Crossplane `AzureWorkloadIdentity` claim/provider path is legacy. The current hcloud spoke lifecycle uses hcloud/talos/kubernetes/terraform providers plus existing Azure Workload Identity configuration, not generated Azure Crossplane RoleAssignments/FICs.

If removing a resource, delete it from the source kustomization/ApplicationSet/app spec, commit, push, and let Argo prune. Avoid manual deletion unless finalizers or orphaned live resources block pruning.

## Diagnose real drift

Start with Argo's comparison, not raw `kubectl diff`:

```bash
argocd app get <app> --hard-refresh --server argocd-hub.tail286401.ts.net --grpc-web --insecure
argocd app diff <app> --server argocd-hub.tail286401.ts.net --grpc-web --insecure

kubectl --kubeconfig ~/.kube/hub-config get app <app> -n argocd -o json |
  jq '.status.resources[]? | select(.status!="Synced")'
```

`kubectl diff` often reports Argo tracking annotations or controller-managed fields that Argo itself ignores. Treat `argocd app diff` as the source of truth for Argo comparison.

If `argocd app diff` is empty but the app remains OutOfSync, hard-refresh and wait a reconcile cycle. If status stays stale, inspect application-controller logs. Restarting `argocd-application-controller` is safer than status patching.

```bash
kubectl --kubeconfig ~/.kube/hub-config logs -n argocd statefulset/argocd-application-controller --since=5m |
  rg '<app>|OutOfSync|Skipping auto-sync|diff|comparison'
```

## Common drift patterns

### ExternalSecret defaults

External Secrets Operator defaults fields such as:

- `remoteRef.conversionStrategy: Default`
- `remoteRef.decodingStrategy: None`
- `remoteRef.metadataPolicy: None`
- `target.deletionPolicy: Retain`
- `target.template.engineVersion: v2`
- `target.template.mergePolicy: Replace`

Prefer declaring these defaults in Git when they cause persistent Argo drift.

### Tekton defaults

Tekton defaults or normalizes several fields:

- CRDs may show `preserveUnknownFields: false`.
- EventListeners default `spec.namespaceSelector: {}`.
- EventListener refs default `bindings[].kind: TriggerBinding` and `interceptors[].ref.kind: ClusterInterceptor`.
- EventListener pod templates may gain `metadata.creationTimestamp: null` and `spec.containers: null`.
- Embedded Pipeline `taskSpec` blocks may gain empty `metadata`, `spec: null`, or `computeResources`.

Prefer declaring exact stable defaults for high-value resources like EventListeners so real trigger/filter drift remains visible. Use narrow `ignoreDifferences` for harmless CRD defaulting or deeply embedded generated fields.

### Tailscale egress Services

Tailscale operator mutates egress Services:

- `/spec/externalName`
- `/spec/ports/0/targetPort`

Apps that own egress Services should ignore those fields. Do not "fix" the live Service back to Git state; the operator will re-mutate it.

### Pending cache PVCs

Build cache PVCs using `WaitForFirstConsumer` can remain Pending until a build runs. If they are labelled cache PVCs, customize Argo health to treat them as Healthy instead of deleting them or forcing a pod.

## Apply declarative fixes

For platform/app-spec changes:

```bash
kubectl kustomize packages/overlays/hub >/tmp/hub-render.yaml
git diff --check
git push origin HEAD:main
git push gitea-ryzen HEAD:main
```

If ryzen root/child Application specs changed, also fast-forward `gitea-ryzen/ryzen-main`.

Hub changes hydrate from `origin/main` to `env/hub-next`; `stacks-environments` has `autoMerge: false`, so merge the generated `env/hub` PR after checking it:

```bash
gh pr list --repo PittampalliOrg/stacks --state open --base env/hub --json number,title,headRefName,url
gh pr merge <number> --repo PittampalliOrg/stacks --merge
kubectl --kubeconfig ~/.kube/hub-config annotate app root-application -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

If `env/hub-next` advanced but the promoter still proposes the prior dry SHA/PR, force a promoter refresh:

```bash
TS=$(date +%s)
kubectl --kubeconfig ~/.kube/hub-config annotate promotionstrategy stacks-environments -n argocd \
  promoter.argoproj.io/refresh-ts="$TS" --overwrite
kubectl --kubeconfig ~/.kube/hub-config annotate changetransferpolicy stacks-environments-env-hub-8c9641d5 -n argocd \
  promoter.argoproj.io/refresh-ts="$TS" --overwrite
```

## Verify

```bash
kubectl --kubeconfig ~/.kube/hub-config get applications.argoproj.io -n argocd \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,PHASE:.status.operationState.phase,DEST:.spec.destination.name,REV:.status.sync.revision --no-headers |
  awk '$2!="Synced" || $3!="Healthy" || $4=="Running" {print}' | sort

kubectl --kubeconfig ~/.kube/hub-config get app root-application spoke-dev spoke-staging -n argocd \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,PHASE:.status.operationState.phase,REV:.status.sync.revision --no-headers
```

Expected final state: the first command prints no rows; root, dev, and staging aggregate apps are `Synced Healthy Succeeded`.
