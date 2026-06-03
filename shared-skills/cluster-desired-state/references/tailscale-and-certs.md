# Tailscale Connectivity & Certificate-Issue Avoidance

This is the **single canonical home** for how the fleet does Tailscale connectivity and
how we avoid the Let's Encrypt / certificate churn we hit in the past. Other skills and
references should POINT here, not re-document this in depth.

Fleet topology recap: one **hub** (Talos/Hetzner) runs the argocd-agent **principal**
(single pane). Each **spoke** (ryzen, dev) runs a LOCAL ArgoCD + an agent dialing the
principal OUTBOUND over tailnet mTLS (8443). Tailnet domain: `tail286401.ts.net`.

---

## Why this exists — the cert pain we escaped

Three concrete incidents drove the current design. All shared the same root cause:
**Let's Encrypt certs tied to ephemeral, per-hostname, recreate-churning Tailscale
resources.**

| # | Incident | Mechanism | Symptom |
|---|---|---|---|
| a | **Ingress LE-per-hostname 429** | Tailscale **Ingress** (`ingressClassName: tailscale`, ProxyClass `development-prod-cert`) mints ONE Let's Encrypt cert PER hostname. Recreate-heavy spokes blew past LE's **5-duplicate-certs / 168h** limit. | LE `429` rate-limit; services unreachable; public DNS **NXDOMAIN**. |
| b | **operator apiserver-proxy SNI strict-validation** | After a Tailscale **operator upgrade** the apiserver-proxy STRICTLY validates wire SNI == `<spoke>-operator.tail286401.ts.net`. ArgoCD sends the server-URL host as SNI (not `serverName`), so on a spoke recreate the hub ArgoCD egress mismatched. | **`tls internal error`**; all spoke apps OutOfSync / unsyncable. |
| c | **hub->spoke kube-API via operator LE cert** | hub->spoke kube-API rode the operator apiserver-proxy's per-hostname LE cert — same 5-dup-certs/week limit as (a). Recreate churn exhausted quota (2026-05-29: ryzen fleet 0-healthy). | LE quota exhausted; hub can't reach spoke apiserver; whole spoke 0-healthy. |

The fixes (PRs #2305/#2307 host passthrough, #2314 LoadBalancer, #2319 in-cluster TLS)
collapse all three into: **at most ONE stable LE hostname on the whole fleet** (the hub
ESO ingress), and everything else is LE-free.

---

## The current design, per connection type

| Connection | Mechanism | LE cert? | Trust / auth |
|---|---|---|---|
| **hub -> ryzen kube-API** (Headlamp / direct kubectl — NOT ArgoCD; ArgoCD uses the agent gRPC) | ryzen HOST runs `tailscale serve --bg --tcp=6443` raw TCP passthrough to the Talos apiserver (`ryzen.tail286401.ts.net:6443`, `100.96.102.1`) | **No** | End-to-end TLS, no termination: full verify (`insecure:false`) of the **Talos CA**; apiserver cert carries `certSANs:[ryzen.tail286401.ts.net,100.96.102.1]`. Auth = read-only SA bearer token, now delivered via the dedicated `headlamp-cluster-ryzen` Secret (the legacy `ExternalSecret-cluster-ryzen` is vestigial). |
| **hub -> dev (ArgoCD)** | NONE — managed agent, gRPC **outbound only** (dev agent dials principal :8443) | **No** | No kube-API reach needed; the principal pushes Application objects, dev's local controller reconciles. |
| **hub -> dev (Headlamp)** | dev's **DIRECT PUBLIC IP** `https://<ip>:6443` | **No** | Read-only SA token + CA (dedicated `headlamp.dev/cluster=true` Secret). |
| **spoke web / Service exposure** | tailnet **LoadBalancer** Service (`spec.loadBalancerClass: tailscale` + `tailscale.com/hostname` annotation), http-over-WireGuard. NO Ingress. | **No** | HTTPS (where needed) served by an in-cluster nginx `tls-terminator` sidecar using the persistent **self-signed `*.tail286401.ts.net` wildcard** from the Tailnet Dev CA. e.g. `workflow-builder-dev.tail286401.ts.net`. |
| **spoke -> hub ESO transport** | spoke `ClusterSecretStore hub-secrets-store` -> `https://k8s-api-hub-ingress.tail286401.ts.net` via spoke egress Service -> hub Ingress `k8s-api-hub-ingress` | **YES — the ONE remaining** | Single STABLE hostname (no per-spoke churn → never hits the limit). `caBundle` hard-set to **ISRG Root X1** (REQUIRED on ESO v2.4.1). Auth = `spoke-secrets-reader` token; `remoteNamespace: spoke-secrets`. Spoke CoreDNS rewrite maps the FQDN -> egress Service. |
| **operator device hostname** | per-cluster (`dev-operator` / `ryzen-operator`) | n/a | Avoids tailnet name collisions / stale `-N` devices (see hygiene section). |
| **Headlamp cluster Secrets** | dedicated `headlamp.dev/cluster=true` Secrets (real endpoint + read-only SA token + CA) | n/a | Separate from the argocd-agent cluster-mapping Secrets, which carry NO bearerToken post-cutover. |

### Notes per type

**(1) hub -> ryzen kube-API.** The ryzen HOST (not the cluster) runs the serve. nixos-config
`services.tailscaleK8sApiserver` defines a `tailscale-serve-k8s-apiserver` oneshot unit that
auto-discovers the Talos-in-Docker apiserver host port; the stacks bootstrap restarts it after
each recreate (Docker re-maps the port). Raw TCP passthrough does NOT terminate TLS, so the
Talos apiserver's own serving cert reaches the hub end-to-end → no `serverName`/SNI hack.
This replaced the operator apiserver-proxy LE path (incident **c**), PRs #2305/#2307.

**(2) hub -> dev.** Under argocd-agent, dev is a **managed agent**: the hub authors Application
objects in ns `dev` (== agent name), the principal pushes them out, dev's local controller
reconciles. The hub never opens a kube-API connection to dev for ArgoCD. Sync OPERATIONS run on
dev's local controller, so the hub pane shows sync+health but `Unknown operation status` —
architectural and benign. Headlamp is the only hub->dev kube reach, and it uses the direct
public IP, not the agent mapping.

**(3) spoke web exposure.** `type: LoadBalancer`, `loadBalancerClass: tailscale`, the
`tailscale.com/hostname` annotation, 443->https-tls. workflow-builder migrated off the
LE-churning Tailscale Ingress (incident **a**) in PR #2314 (LoadBalancer) / #2319 (in-cluster
TLS). The dev/staging overlays `$patch:delete` the old workflow-builder/mcp-gateway Tailscale
Ingresses. HTTPS is the in-cluster sidecar + self-signed wildcard — never Let's Encrypt.

**(4) spoke -> hub ESO transport.** This is the ONE LE cert left and the one you must KEEP. It
delivers the agent mTLS cert + repo cred + shared secrets onto the spoke. Because the hostname
`k8s-api-hub-ingress.tail286401.ts.net` is **single and stable** (it is a standalone Tailscale
Ingress device on the hub, not per-spoke), it never churns and never trips the rate limit. The
`caBundle` MUST be ISRG Root X1 on ESO v2.4.1 (the hub Ingress serving cert chains to it). The
spoke CoreDNS rewrite (re-applied every recreate — Talos resets the Corefile) maps the FQDN to
the egress Service.

**(5) operator device hostname.** The shared `tailscale-operator` manifest hardcodes
`OPERATOR_HOSTNAME=ryzen-operator`; every NON-ryzen cluster MUST override it (dev did via a
dev-overlay `source.kustomize` patch, PR #2364) or its operator collides on the tailnet and
suffixes to `ryzen-operator-1`/`-2`.

**(6) Headlamp cluster Secrets.** Headlamp reads dedicated `headlamp.dev/cluster=true` Secrets
(per-spoke real endpoint + read-only SA token + CA), NOT the argocd-agent cluster-mapping
Secrets. The agent mapping Secrets carry NO bearerToken post-cutover, so if Headlamp keyed off
them a restart would drop all spokes. PRs #2366/#2368. The spoke read SA is GitOps
(`base/manifests/headlamp-reader`, reaches dev via overlays/dev->talos->base); the enroll
script stages the hub `headlamp-cluster-<spoke>` Secret; both Headlamp generators (headlamp +
headlamp-embedded) select the label. **Post-recreate freshness (Fix 3, PR #2395):** Headlamp
builds its kubeconfig only in its `generate-kubeconfig` init-container (at pod start), so a pod
predating a spoke recreate keeps serving the OLD endpoint/CA/token. Both `enroll-{dev,ryzen}-agent.sh`
(step 5b) `kubectl -n headlamp rollout restart deploy/hub-headlamp deploy/hub-headlamp-embedded`
on the hub after staging the Secret (guarded on deploy existence, non-fatal).

**Token-race hardening (2026-06, `reference_headlamp_recreate_token_race`).** Staging used to
race the spoke token controller: step 5b waited only **60s** for the spoke `headlamp-reader-token`
(a `kubernetes.io/service-account-token` Secret the kube-controller-manager populates). On the
slower Talos/Hetzner **dev** cluster that elapsed before the token was ready, so 5b warn-skipped and
left the PREVIOUS cluster's token+CA in `headlamp-cluster-dev` -> hub Headlamp proxy got
**`x509: certificate signed by unknown authority`** (stale CA) + **`HTTP 401`** (stale token);
reachability was fine (it reached `dev-cp-1.tail286401.ts.net:6443`, got a 401 not a timeout).
ryzen's fast local Docker cluster won the race, masking the bug. Fix (3 parts):
- step 5b extracted to a reusable `stage_headlamp()` fn in both enroll scripts;
- a **`HEADLAMP_ONLY=true`** mode runs ONLY the staging (skip the agent enroll) — used by the
  orchestrators AND as the live recovery: `HEADLAMP_ONLY=true SPOKE_KUBECONFIG=/tmp/talos-spoke-dev/kubeconfig HUB_CONTEXT=hub-cluster bash deployment/scripts/argocd-agent/enroll-dev-agent.sh dev`;
- the wait is now **180s** and requires BOTH `token` AND `ca.crt`; AND the orchestrators **re-stage
  AFTER convergence** (`recreate-dev.sh` **step 8b**, `bootstrap-spoke-cluster.sh` **step 10b**),
  when the token is guaranteed ready — the durable guarantee.

Verify a connection: from a `hub-headlamp` pod, `wget -H "Authorization: Bearer <staged token>"
https://<spoke-fqdn>:6443/version` returns 200; `kubectl -n headlamp logs deploy/hub-headlamp` shows
no `x509`/`401`. See `cluster-desired-state/runbooks/recovery-and-gotchas.md`.

---

## Rules of thumb (how we KEEP avoiding cert issues)

- **Prefer LoadBalancer Services over Ingress** for spoke web exposure — Ingress = one LE cert
  per hostname; LoadBalancer = http-over-WireGuard, zero LE.
- **Prefer host-passthrough or agent-gRPC over operator-LE for kube-API** — raw TCP passthrough
  (ryzen) or outbound agent gRPC (dev) both drop the operator apiserver-proxy LE cert.
- **At most ONE stable LE hostname on the fleet** — the hub `k8s-api-hub-ingress`. Anything that
  would mint a per-hostname or per-recreate LE cert is the wrong design.
- **Per-cluster operator hostnames** — never let two clusters request the same operator device
  name.
- **Gated stale-device cleanup** — ephemeral keys + poll-until-offline before reusing a
  canonical hostname.
- **For HTTPS where it's truly needed, terminate in-cluster** with the self-signed
  `*.tail286401.ts.net` wildcard, not LE.

---

## Stale tailnet device hygiene

**Root cause of `-1`/`-2` collisions.** A recreate leaves a stale duplicate `<spoke>-operator`
(or other) tailnet device that still RESERVES the canonical hostname. The new operator can't
claim it and registers a suffixed `<spoke>-operator-1`/`-2`. Hub egress Services may also stay
pinned to the OLD device.

**Cleanup recipe (TS API).**
1. Mint a Tailscale API token from the **operator-oauth** Secret / OAuth client
   (`client_credentials`).
2. List devices; delete the **OFFLINE** orphans only (gated — `lastSeen > ~30m`).
3. Re-poll until the canonical hostname is gone, THEN let the operator re-claim it.
4. Patch/restart the hub egress Service or the operator StatefulSet pod so it re-resolves.

**API gotcha.** The Tailscale device `hostname` field DROPS the `-N` suffix — a live device and
its dead `-N` twin share one `hostname`. **Match on the MagicDNS `name`, not `hostname`.** The
operator profile's `Hostname` setting is the REQUESTED name, NOT necessarily the assigned `-N`
device name. **Verify by pod age + re-poll-after-delete** (don't trust the hostname field
alone). `lastSeen` IS a reliable liveness signal (control-plane keepalives keep it fresh for
connected devices).

**Backstop.** Hub `tailnet-device-sweeper` CronJob (ns `tailscale`, every 15m, PRs #2322/#2325)
deletes OFFLINE stale devices best-effort. It is hygiene, NOT the guarantee — the hard
on-recreate guarantee is the gated pre-recreate `cleanup-tailnet-devices.sh`. (ryzen's hub->spoke
no longer uses an operator device per the host passthrough; this still matters for the ESO
transport device and any operator-proxy spokes.)

**Destroy speed (Fix 4, PR #2395).** `provision-spoke.sh --destroy` now deletes the N Hetzner
servers concurrently (no inter-server ordering) instead of sequentially (~18s each), mirroring
the parallel create — ~156s down to ~20s for a 9-node dev. See
`cluster-desired-state/runbooks/recovery-and-gotchas.md`.

---

## The persistent self-signed Tailnet Dev CA

A **10-year, offline-generated, cluster-NEUTRAL** CA ("PittampalliOrg Tailnet Dev CA") lives in
Azure Key Vault as `TAILNET-DEV-CA-CRT` / `TAILNET-DEV-CA-KEY`.

- **What it's for.** Signs the `*.tail286401.ts.net` wildcard Certificate that the in-cluster
  `tls-terminator` nginx sidecar serves — so spoke web exposure gets HTTPS with **no Let's
  Encrypt**.
- **Why cluster-neutral + long-lived.** The SAME CA is mirrored onto every cluster (hub
  `ExternalSecret-tailnet-ca` -> ns `spoke-secrets` Secret `tailnet-ca`, read namespace-wide by
  `spoke-secrets-reader`; spoke restores it into `cert-manager/tailnet-dev-ca` and a CA
  `ClusterIssuer` signs the wildcard). Clients trust it ONCE and the trust **survives cluster
  recreation**. 10-year validity means no renewal
  churn.
- **Workstation trust** (nixos-config): `modules/services/cluster-certs.nix` for system/curl/git
  + `home-modules/tools/chromium.nix` certutil seed of `~/.pki/nssdb` (REQUIRED — `security.pki`
  does not cover Chrome's NSS db on NixOS).
