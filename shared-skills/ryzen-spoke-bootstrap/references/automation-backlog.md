# Ryzen Recreate — Friction Log + Automation Backlog (2026-05-28)

Observed during today's destroy + recreate of the ryzen Talos Docker cluster (commits `e11e8ba06` and after). Cluster came up healthy, but the path was bumpier than the documented runbook. This log times each manual step and proposes concrete script-level fixes.

## Critical bugs found in `bootstrap-spoke-cluster.sh` (script was broken)

These were silent failures that destroyed the cluster but failed to recreate it. **All committed as fixes today**.

| Bug | Symptom | Fix | Commit |
|---|---|---|---|
| `--cidr` flag | `talosctl cluster create docker: unknown flag: --cidr` (talosctl v1.13 renamed to `--subnet`) | rename `--cidr` → `--subnet` | `fdc45ff85` |
| `--memory` / `--cpus` for CP | same: renamed to `--memory-controlplanes` / `--cpus-controlplanes` | rename both | `fdc45ff85` |
| OIDC issuer YAML key | `error parsing config patch: unknown keys found during decoding` — `cluster.serviceAccount.issuerURL` is not valid v1alpha1 | move to `cluster.apiServer.extraArgs.service-account-issuer` | `1ce550054` |
| Tailscale operator chart `mode=auth` | operator CrashLoopBackOff: `panic: unknown APISERVER_PROXY value "auth"` (chart v1.98.x renamed) | use `mode=true` + new `allowImpersonation=true` | `f3c345e1e` |

## Manual steps + observed durations

| # | Step | Time | Currently | Automation rec |
|---|------|------|-----------|----------------|
| A | Pre-flight tools + env vars + az login | 2 min | manual `export` of TS/Azure vars from KV | **P0**: bootstrap script auto-loads from `az keyvault secret show` when env vars are unset |
| B | postgres dump from ryzen | 1 min | manual `kubectl exec + pg_dump` | **P2**: bootstrap `--with-data-backup` flag |
| C1 | Run bootstrap (helm + overlay) | 8-10 min | scripted ✓ | (script bugs above) |
| C2 | kubeconfig context cleanup (talosctl appends `-1` if old context exists) | 2 min | not in script | **P0**: `--recreate` flag should `kubectl config delete-{cluster,context,user}` first |
| D1 | Tailscale stale device cleanup | 5 min | runbook-only python snippet; not run before bootstrap | **P0**: bootstrap should call `cleanup-tailnet-devices.sh` (new) before recreate |
| D2 | Hub `ryzen-api-egress` Service annotation reset + pod delete | 2 min | manual | **P1**: registration script handles this (it knew the new device name via the API rename above) |
| D2b | **NEW friction**: Tailscale device name collision (`ryzen-api-v3-1` because old `ryzen-api-v3` device still claimed the name 53 min after cluster destroy) | 5 min | undocumented; required Tailscale API device rename | **P0**: D1's cleanup must delete the old device BEFORE bootstrap to avoid the `-1` suffix |
| D3 | Extract bearer token + CA + push to KV | <1 min | manual | **P0**: registration script does this idempotently |
| D4 | Refresh hub ESO `argocd-cluster-ryzen` | <1 min | manual `kubectl annotate force-sync` | **P0**: registration script does this |
| D5 | JWKS sync to Azure storage | ~10 sec script + **29 min Azure AD federated cache wait** | runs the script from `122-crawl4ai/ref-implementation/` (a feature branch!) | **P0**: move script to `deployment/scripts/sync-jwks-to-azure.sh` in main; registration script invokes it |
| D6 | Poll `ClusterSecretStore` Ready | 29 min (mostly waiting on Azure AD) | manual `kubectl get` loop | **P1**: registration script polls automatically; same long wait, but unattended |
| D7 | Restart Headlamp Deployments | <1 min | manual `rollout restart` of `hub-headlamp` + `hub-headlamp-embedded` | **P1**: registration script does this last |
| D8 | **NEW friction**: `tailscale` namespace needs `pod-security.kubernetes.io/enforce=privileged` label (operator's proxy pods need privileged for sysctl + tailscale containers) | 1 min | not in bootstrap; failure-modes.md notes it | **P0**: bootstrap should `kubectl label namespace tailscale pod-security.kubernetes.io/enforce=privileged --overwrite` after creating it |
| D9 | **NEW friction**: hub `ryzen-api-egress` operator only reads `tailnet-fqdn` annotation at pod create; annotation changes do NOT trigger reconnect | 3 min | force pod delete | **P1**: registration script auto-rotates the pod after annotation change |
| E | Hub reconcile (50/67 in ~10 min, full convergence in ~15-20) | 15 min | automatic | nothing to fix |
| F | Validation checks | 2 min | runbook checklist | **P3**: extend existing `deployment/scripts/cluster-readiness.sh` |
| G | Restore postgres data + smoke test | 5 min | manual | **P2**: combine with B (backup/restore as a pair) |

**Total observed wall-clock: ~80 min** (vs. estimated 40-60 min in plan — overrun caused by the 4 broken-script bugs above, each requiring debug + commit cycle).

## Prioritized automation backlog

### P0 — must-have for next clean recreate

**P0.1 — `register-spoke-with-hub.sh`** (new script in `deployment/scripts/`):

```
Inputs:
  CLUSTER_NAME=ryzen (positional, default)
  AZURE_KEY_VAULT (default keyvault-thcmfmoo5oeow)
  HUB_KUBECONFIG (default ~/.kube/hub-config)
  AZURE_WORKLOAD_IDENTITY_CLIENT_ID (default 137fbb08-...)
  AZURE_WORKLOAD_IDENTITY_TENANT_ID (default 0c4da9c5-...)

Steps:
  1. Verify kube-api reachable on $CLUSTER_NAME context
  2. kubectl create token argocd-hub-spoke-sa -n kube-system --duration=8760h
  3. kubectl get configmap kube-root-ca.crt ... | base64 -w 0
  4. az keyvault secret set --name ARGOCD-CLUSTER-{NAME-UPPER}-TOKEN/-CA
  5. kubectl --kubeconfig $HUB_KUBECONFIG annotate externalsecret argocd-cluster-${NAME} force-sync=$(date +%s)
  6. bash deployment/scripts/sync-jwks-to-azure.sh
  7. until cluster-secret-store-ready (poll); do sleep 30
  8. kubectl --kubeconfig $HUB_KUBECONFIG rollout restart deploy -n headlamp hub-headlamp hub-headlamp-embedded
  9. Print summary

Exit codes:
  0 = success
  1 = kube-api unreachable
  2 = KV push failed
  3 = JWKS sync failed
  4 = ClusterSecretStore polling timed out (>30 min)
```

**P0.2 — Move `sync-jwks-to-azure.sh` into main**: currently lives only on `122-crawl4ai` (and other feature) branches. The script is identical across them — copy to `deployment/scripts/` so it's branch-independent. The skill's hard-coded path is fragile.

**P0.3 — Auto-load Tailscale OAuth from KV in bootstrap**: if `TS_OAUTH_CLIENT_ID` / `_SECRET` env vars unset AND `az` is logged in, source from `TAILSCALE-OAUTH-CLIENT-ID` / `-SECRET` automatically. Same for `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` (use defaults from cluster history). Eliminates the manual env-var dance.

**P0.4 — `--recreate` flag should clean kubeconfig**: add to bootstrap-spoke-cluster.sh:
```bash
if $RECREATE; then
  talosctl cluster destroy --name "$CLUSTER_NAME" || true
  kubectl config delete-context "admin@$CLUSTER_NAME" 2>/dev/null || true
  kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
  kubectl config delete-user "admin@$CLUSTER_NAME" 2>/dev/null || true
fi
```

**P0.5 — `cleanup-tailnet-devices.sh`** (new script). Calls Tailscale API to delete devices matching `^${CLUSTER_NAME}-`, `-${CLUSTER_NAME}($|-)`, `^k8s-api-cluster-`, plus offline `*-${CLUSTER_NAME}*` devices. Invoked automatically by `--recreate` BEFORE `talosctl cluster destroy` (so the OAuth Secret is still in cluster) OR uses `TS_OAUTH_*` from env/KV.

**P0.6 — Bootstrap should label `tailscale` namespace privileged**: add after the Tailscale operator helm install:
```bash
kubectl label namespace tailscale pod-security.kubernetes.io/enforce=privileged --overwrite
```

### P1 — quality of life

**P1.1 — Annotation-change auto-rotates egress pods**: the Tailscale operator's `ryzen-api-egress` egress pod doesn't pick up `tailscale.com/tailnet-fqdn` changes without pod delete. The registration script should detect annotation changes and force pod delete.

**P1.2 — Auto-rename new Tailscale device to canonical name**: if `cleanup-tailnet-devices.sh` ran successfully, the new device should get the canonical name on first registration. Belt-and-suspenders: if `${CLUSTER_NAME}-api-v3-N` is registered (suffix N>0), invoke the Tailscale API to rename it to `${CLUSTER_NAME}-api-v3`.

### P2 — eventual

**P2.1 — Optional `--with-data` flag** for backup/restore of `environment_image_builds` and any other tables.

**P2.2 — Reorganize all deployment scripts under `deployment/scripts/spoke/`** namespace so the spoke-bootstrap, registration, cleanup, jwks-sync, and readiness scripts live together.

### P3 — nice-to-have

**P3.1 — Extend `cluster-readiness.sh`** with the Phase F checks from the plan: cluster Secret server URL, ClusterSecretStore Ready, worker labels present, Talos worker Docker mem limit ≥ 13 GiB, `benchmark-fast` quota = 9 Gi, `ollama-host-egress` Service ABSENT.

**P3.2 — Document the Tailscale operator chart upgrade path** in failure-modes.md: chart v1.98.x renamed `apiServerProxyConfig.mode` values. Add a known-good chart version pin to the bootstrap script.

## Updates needed in the `ryzen-spoke-bootstrap` skill docs

1. **SKILL.md**: reference `register-spoke-with-hub.sh` once it exists (replaces steps 3-7's manual block).
2. **recreate-runbook.md**: note that `--recreate` now handles kubeconfig cleanup + tailnet device cleanup automatically.
3. **failure-modes.md**: add 5 new modes encountered today (talosctl flag drift, Tailscale operator chart drift, Tailscale name collision after recreate, tailscale ns privileged label, hub egress not picking up annotation change). All 4 broken-script bugs are documented in commit messages but should be in failure-modes too for searchability.

## Verification checklist completed during this session

- ✓ Talos workers came up at 12.7 GiB (Docker reports 13 GiB → 12.7 GiB after overhead)
- ✓ Worker node labels applied (`stacks.io/swebench-pool=dev-benchmark` + `node-role.kubernetes.io/worker=`)
- ✓ Tailscale operator running (after chart-value fix)
- ✓ ryzen-api-v3 tailnet device registered (after name-collision fix)
- ✓ Hub argocd-application-controller connects to ryzen ("Successful" in `argocd cluster list`)
- ✓ ClusterSecretStore Ready (after 29-min Azure AD wait)
- ✓ Headlamp Deployments restarted
- → Hub reconcile in progress (50/67 Healthy at 10 min, watching for full convergence)
