# Runbook: Recreate a Crossplane Talos Spoke

Use when replacing a disposable or planned-outage spoke such as `dev` or when
moving a manual HCloud/Talos cluster under Crossplane ownership.

## Preconditions

- The user has authorized a destructive outage for the spoke.
- Required runtime data is exported or already represented by idempotent repo
  fixtures.
- The desired claim exists in Git and has been parsed/rendered locally.
- Provider quota and target HCloud server types are available. If a requested
  server type cannot be placed, pause instead of silently downgrading.

## Preflight

```bash
SPOKE=dev
HUB=~/.kube/hub-config

kubectl --kubeconfig "$HUB" -n argocd get app | rg "$SPOKE|spoke-$SPOKE|crossplane"
kubectl --kubeconfig "$HUB" -n crossplane-system get talospokeclusterclaims,talospokeclusters,job
```

If the old spoke is still reachable, verify it is idle:

```bash
kubectl --context ${SPOKE}-api-v2.tail286401.ts.net -n workflow-builder exec postgresql-0 -- \
  psql -U postgres -d workflow_builder -c "
    select status, count(*) from benchmark_runs group by status;
    select status, count(*) from benchmark_resource_leases group by status;
    select status, count(*) from workflow_executions group by status;
  "

kubectl --context ${SPOKE}-api-v2.tail286401.ts.net get pods -A | \
  rg 'swebench|openshell|agent-runtime' || true
```

Stop or cancel active benchmark runs, resource leases, Dapr workflow executions,
and OpenShell sandboxes before deleting infrastructure.

## Edit And Validate Git

1. Update the spoke claim:

   ```text
   packages/components/crossplane-hetzner-talos/manifests/crossplane-hcloud-compositions/TalosSpokeClusterClaim-<spoke>.yaml
   ```

2. If worker count, schema, or generated resources change, update:

   ```text
   CompositeResourceDefinition-talospokecluster.yaml
   Composition-talospokecluster.yaml
   ```

3. Validate before pushing:

   ```bash
   yq '.' packages/components/crossplane-hetzner-talos/manifests/crossplane-hcloud-compositions/*.yaml >/dev/null
   kubectl kustomize packages/components/crossplane-hetzner-talos >/dev/null
   kubectl kustomize packages/overlays/<spoke> >/dev/null
   ```

4. Commit and push to `origin/main`, then track hub Argo until the composition
   revision reaches the hub.

## Remove Stale Ownership

Do this only after preflight is clean and the new desired state is committed.

1. Delete old manual HCloud servers/network/firewall that are not owned by
   Crossplane.
2. Delete stale hub Argo cluster secrets for the spoke if they point at old certs
   or old API endpoints and are not owned by the current claim.
3. Clean stale Tailscale devices and service-hosts before the new cluster
   authenticates. Read `tailscale-name-recovery.md`.

## Apply Or Sync The Claim

Prefer letting hub Argo sync `crossplane-hcloud-compositions`. If applying
directly is appropriate:

```bash
kubectl --kubeconfig ~/.kube/hub-config apply -f \
  packages/components/crossplane-hetzner-talos/manifests/crossplane-hcloud-compositions/TalosSpokeClusterClaim-<spoke>.yaml
```

Watch provisioning:

```bash
kubectl --kubeconfig ~/.kube/hub-config -n crossplane-system get \
  talospokeclusterclaims,talospokeclusters,workspaces.tf.upbound.io,job -w
```

Then watch hub Argo:

```bash
kubectl --kubeconfig ~/.kube/hub-config -n argocd get app | rg '<spoke>|spoke-<spoke>'
```

## Expected Lifecycle

- HCloud network/firewall/servers are created.
- Talos installs to disk, bootstraps etcd, and detaches ISO/resets nodes.
- Crossplane writes a fresh kubeconfig secret.
- Spoke bootstrap installs namespaces, PodSecurity, webhooks, Tailscale operator,
  and the API ProxyGroup.
- Hub Argo gets a fresh cluster secret.
- Source-hydrator and Promoter create/sync `spoke-<spoke>` and workload apps.

## Recovery Notes

- If Tailscale API DNS is broken, extract the newest Crossplane kubeconfig secret
  and use `KUBECONFIG=/tmp/<spoke>-kubeconfig`.
- If source-hydrator or Promoter appears pinned to an old dry SHA, use the
  `gitops` skill's promoter/source-hydrator runbooks.
- If Argo apps are `Progressing` from missing Services, orphan PVCs, or defaulted
  fields, fix desired manifests rather than declaring the cluster bad.
