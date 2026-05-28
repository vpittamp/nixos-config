# Ryzen Recreate — Friction Log + Automation Backlog

**Status**:
- **P0 items**: ✅ implemented in stacks `32ecea8a7` (2026-05-28). Validated end-to-end in 48m 16s wall-clock.
- **P1.A / P1.B / P1.C**: ✅ implemented + validated in stacks `e619d0ddd`, `d98d6d7a7`, `0d2f5a9bf`, `f74becf81`, `78a4c6979` (2026-05-28).
- **P1.2** (Tailscale device rename): demoted to P2 — `cleanup-tailnet-devices.sh` pre-destroy step prevents collision in practice.
- **P2 Tailscale ACL spoke registration**: ✅ implemented + validated in stacks `83ce11f0f`, `42ddb16cd`, `a9da1d030`, `85ed6fbca` (2026-05-28). `bash bootstrap-spoke-cluster.sh --recreate --ts-acl-mode` completes bootstrap + register in **8m30s** (vs 31m for the bearer-token path on the prior validation). Convergence to ~50/67 SH happens within an additional ~5-10 min.

**Measured wall-clock (2026-05-28 attempt 3, --ts-acl-mode)**:
| Phase | Time |
|---|---|
| Pre-destroy cleanup (Tailscale devices, kubeconfig) | ~10s |
| talosctl cluster destroy + create | ~1m40s |
| Helms (cert-manager, ESO, AWI, Tailscale operator) | ~3m |
| Kueue pre-install + label patch + rollout-status wait | ~1m20s |
| Spoke-registration manifests | ~5s |
| Tailscale ProxyGroup advertise wait | ~2m |
| register-spoke-with-hub.sh (steps 1, 5.5, 7, 8, 8.5 only) | ~30s |
| **Total bootstrap + register** | **8m30s** |
| Convergence to 50/67 SH (background) | +5-10 min |

**~85% reduction** vs 2026-05-28 P1 baseline of 48m. Steps 2-6 of register-spoke-with-hub.sh (token extract, KV push, ESO annotate, JWKS sync, CSS Ready poll) are entirely skipped under `--ts-acl-mode` because hub→spoke auth is via Tailscale ACL impersonation, not a per-spoke bearer token. JWKS sync still runs (in background) for spoke-side ESO's other KV secrets.

**Validation outcome of the prior 2026-05-28 attempt 2 (bearer-token path, retained for comparison)**: Wall-clock 46m to plateau (45 SH + 2 SP + 5 OOS/H = 52 effectively operational of 67). Missed the ≤32 min target because validation surfaced four new bugs:
1. `STACKS_DIR` cwd-sensitivity (stacks `d98d6d7a7`)
2. Polluted shell env from legacy `kind.env` (stacks `0d2f5a9bf`)
3. Egress-restart step ordering vs CSS poll (stacks `f74becf81`)
4. Pod-only delete leaves stale Tailscale state Secret (stacks `78a4c6979`)

---


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

### P0 — must-have for next clean recreate (ALL IMPLEMENTED in stacks 32ecea8a7)

**P0.1 — ✅ DONE: `register-spoke-with-hub.sh`** (new script in `deployment/scripts/`):

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

**P0.2 — ✅ DONE: Move `sync-jwks-to-azure.sh` into main**: currently lives only on `122-crawl4ai` (and other feature) branches. The script is identical across them — copy to `deployment/scripts/` so it's branch-independent. The skill's hard-coded path is fragile.

**P0.3 — ✅ DONE: Auto-load Tailscale OAuth from KV in bootstrap**: if `TS_OAUTH_CLIENT_ID` / `_SECRET` env vars unset AND `az` is logged in, source from `TAILSCALE-OAUTH-CLIENT-ID` / `-SECRET` automatically. Same for `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` (use defaults from cluster history). Eliminates the manual env-var dance.

**P0.4 — ✅ DONE: `--recreate` flag cleans kubeconfig**: bootstrap-spoke-cluster.sh now runs:
```bash
if $RECREATE; then
  talosctl cluster destroy --name "$CLUSTER_NAME" || true
  kubectl config delete-context "admin@$CLUSTER_NAME" 2>/dev/null || true
  kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
  kubectl config delete-user "admin@$CLUSTER_NAME" 2>/dev/null || true
fi
```

**P0.5 — ✅ DONE: `cleanup-tailnet-devices.sh`** (new script at `deployment/scripts/`). Calls Tailscale API to delete devices matching `^${CLUSTER_NAME}-`, `-${CLUSTER_NAME}($|-)`, `^k8s-api-cluster-`, plus offline `*-${CLUSTER_NAME}*` devices. Invoked automatically by `--recreate` BEFORE `talosctl cluster destroy` (so the OAuth Secret is still in cluster) OR uses `TS_OAUTH_*` from env/KV.

**P0.6 — ✅ DONE: Bootstrap labels `tailscale` + `local-path-storage` namespaces privileged**: now in bootstrap-spoke-cluster.sh after the Tailscale operator helm install:
```bash
kubectl label namespace tailscale pod-security.kubernetes.io/enforce=privileged --overwrite
```

### P1 — quality of life

**P1.A — ✅ DONE: Pre-install Kueue in bootstrap-spoke-cluster.sh**: bootstrap step 6c now applies the upstream Kueue release manifest server-side and waits for kueue-controller-manager Available before any ArgoCD sync. Eliminates the CRD partial-apply race + controller crashloop that wedged ~14 ryzen-* Apps for ~10 min during the 48m validation. `KUEUE_VERSION` env var (default `v0.17.3`) must match `packages/components/workloads/kueue/Application-kueue.yaml` targetRevision.

**P1.B — ✅ DONE: Hub egress pod auto-rotate**: `register-spoke-with-hub.sh` step 6.5 now force-deletes hub-side `ts-${CLUSTER_NAME}-api-egress-*` pods after CSS Ready and waits for the operator to spin a fresh one. Eliminates the 51-min stale-Tailscale-auth wait observed during the 48m validation.

**P1.C — ✅ DONE: Force-sync OOS ryzen-* apps**: `register-spoke-with-hub.sh` step 8.5 now lists ryzen-* Apps via the argocd CLI and force-syncs any in OutOfSync/Degraded state asynchronously, after hub→spoke is verified Successful. Eliminates the ~5 min manual `argocd app sync ryzen-<name>` toil.

**P1.2 — Auto-rename new Tailscale device to canonical name** (demoted to P2): if `cleanup-tailnet-devices.sh` ran successfully, the new device should get the canonical name on first registration. The pre-destroy cleanup makes this collision unlikely in practice — kept as a belt-and-suspenders item.

### P2 — architectural evaluation: Tailscale ACL impersonation in place of Azure WI for spoke registration  ✅ DONE

**Outcome** (2026-05-28): Validated end-to-end on ryzen. Measured wall-clock improvement: bootstrap + register-spoke went from ~31 min (bearer-token path) to **8m30s** (Tailscale ACL path). Steps 2-6 of register-spoke-with-hub.sh entirely eliminated. Pattern works exactly as documented in the Tailscale ArgoCD multi-cluster guide, with three architectural requirements that we had to surface during validation (now codified — see failure-modes.md):

1. **APISERVER_PROXY=true** on the spoke operator Deployment so it actually listens on port 443 of its tailnet device (commit `83ce11f0f`).
2. **policy.hujson grant** `tag:k8s → tag:k8s-operator` with `system:masters` impersonation (the hub egress carries tag:k8s, the operator carries tag:k8s-operator; existing grants don't cover this path) (commit `83ce11f0f`).
3. **tlsClientConfig.serverName** in the cluster Secret pointing at the operator's tailnet hostname so ArgoCD's TLS SNI matches what the proxy accepts (commit `42ddb16cd`).

Plus two side-discoveries unrelated to the ACL pattern but required for the path to work end-to-end:

4. **Kueue label patch** — upstream Kueue release manifest's Deployment is missing the `app.kubernetes.io/instance=kueue` label that helm's webhook-service selector requires; without it, every admission webhook call timeouts (commit `a9da1d030`).
5. **Kueue rollout-status wait** — `kubectl wait Available` returns on the still-terminating OLD pod after the label patch triggers a rollout; needed explicit `kubectl rollout status` + endpoint-population poll (commit `85ed6fbca`).

**Premise** (researched 2026-05-28 from `tailscale.com/blog/workload-identity-ga`, `…/docs/solutions/sync-kubernetes-secrets-across-clusters-external-secrets`, and `…/docs/solutions/manage-multi-cluster-kubernetes-deployments-argocd`): the Tailscale ArgoCD multi-cluster pattern uses a hub cluster Secret whose `server` field is `https://<spoke-tailnet-fqdn>` (or the in-cluster ExternalName that bridges to it) and whose bearer token field is `"unused"`. The actual auth is via a Tailscale ACL grant of `impersonate.groups: ['system:masters']` for the hub's operator identity → spoke kube-api proxy. No per-spoke bearer token; no JWKS sync for the registration path; no AAD federated-credential cache wait.

**What we'd eliminate from `register-spoke-with-hub.sh`**:
- Step 2 (kubectl create token + extract CA)
- Step 3 (push to Azure KV as ARGOCD-CLUSTER-RYZEN-{TOKEN,CA})
- Step 4 (annotate hub ExternalSecret for ESO refresh)
- Step 5 (sync-jwks-to-azure.sh — eliminates the script and the failure modes above)
- Step 6 (ClusterSecretStore Ready poll — eliminates the ~10 min AAD cache wait, the largest remaining bottleneck)

What stays: step 5.5 (egress pod rotation — Tailscale device identity still rotates), step 7 (Headlamp restart), step 8 (verify), step 8.5 (force-sync OOS).

**Expected savings**: ~10–15 min off the recreate wall-clock. Combined with the P1 fixes, a clean recreate could land near **~15–20 min** instead of 25–30.

**Tradeoffs / costs**:
- Tailscale ACL `impersonate.groups: ['system:masters']` is broader than per-cluster bearer-token RBAC. Need careful tag scoping (e.g., `tag:argocd-operator → ryzen-cluster: system:masters`, not `* → *`).
- The hub still needs Azure Workload Identity for **other** KV secrets (GHCR PATs, OAuth credentials, Tailscale OAuth client, AAD app credentials). This refactor doesn't eliminate AWI; it only removes the spoke-registration-specific KV roundtrip.
- Conflicts with `[[feedback_workload_identity_use_app_registration]]` user memory only for the spoke-registration-Secret subcase; the broader AAD App Registration pattern remains the default for everything else.
- Requires Tailscale `apiServerProxyConfig.allowImpersonation=true` on the spoke (already set) plus an ACL grant on the hub side.

**Recommended approach**: prototype on a `talos-test` spoke first (separate from ryzen), validate end-to-end including a destructive recreate, then promote to ryzen if the savings hold. Document any new failure modes in `failure-modes.md`.

**Complementary, smaller bite**: also evaluate Tailscale Workload Identity (GA, blog 2026-05) — lets the in-cluster Tailscale operator authenticate to Tailscale's control plane via the cluster's native OIDC tokens, removing the `TS_OAUTH_CLIENT_ID/SECRET` env var dance from `bootstrap-spoke-cluster.sh` step 1. Smaller-blast-radius change than the ACL impersonation pivot.

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
