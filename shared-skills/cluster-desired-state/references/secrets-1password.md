# Hub secret root: 1Password (replaces Azure Workload Identity)

Canonical home for **how the hub authenticates to its secret backend** and how a
recreate re-establishes it. Migrated Azure Workload Identity -> 1Password in 2026-06.
This is a HUB-only change; **spokes are unaffected** (they read hub-mirrored k8s
Secrets over Tailscale regardless of how the hub populates them — see
`architecture.md` Contract 2).

## The shape

- The **21 hub `ExternalSecret`s** resolve from the **`onepassword-store`**
  `ClusterSecretStore` (ESO **`onepasswordSDK`** provider) against the dedicated
  **`hub-eso`** 1Password vault.
- Auth is a single **scoped read-only 1Password Service Account** (`hub-eso-reader`,
  read-only on the `hub-eso` vault ONLY) whose `ops_…` token lives in the
  **`onepassword-sa-token`** Secret (ns `external-secrets`, key `token`). That Secret is
  the hub's single **bootstrap root-of-trust** — the analogue of dev's scoped read-only
  `spoke-secrets-reader` bearer token. NOT a security regression vs the fleet norm (dev
  already stores one scoped read-only token); the only model with zero stored credential
  was Azure WI itself, the tradeoff accepted to drop Azure.
- Resolution model (ESO v2.4.1 `onepasswordSDK`): **`remoteRef.key = "<item>/<field>"`**
  (the path after `op://<vault>/`; the store supplies the vault). `property` is IGNORED;
  the field is MANDATORY. Each hub secret is one item in `hub-eso`, value in the
  `password` field -> ES keys are `"<SECRET-NAME>/password"`.
- Manifests: `packages/components/hub-onepassword/ClusterSecretStore-onepassword-store.yaml`
  (the CSS, wired into `overlays/hub` via the `hub-onepassword` component); the 21 ES were
  repointed in their own (hub-only) source manifests.

## Durability + recreate

- The **`hub-eso` vault persists in 1Password** (cloud, independent of the cluster), so a
  hub recreate does NOT lose the secrets. The `hub-eso-reader` SA also persists.
- The token VALUE is shown only once at SA creation; it is persisted at
  **`op://CLI/<id>/credential`** (item "Service Account Auth Token: hub-eso-reader" in the
  `CLI` vault — use the item-ID form; the title has spaces). The operator's `developer`
  SA token can read `CLI`, so `recreate-hub.sh --seed-secret` does
  `op read op://CLI/<id>/credential` -> creates `onepassword-sa-token` on the fresh hub.
  **This replaces the old Azure JWKS-upload bootstrap step entirely** (`sync-jwks-to-azure.sh`
  is no longer in the hub path; it is a spoke-only tool now). If the token is ever lost,
  rotate the SA in the 1Password console (new token, same SA) and re-seed.
- **Ordering on a recreate:** create `onepassword-sa-token` BEFORE the `onepassword-store`
  CSS syncs (else ESO retains the existing target Secrets but cannot refresh them). On the
  manual `env/hub` promotion lane this is naturally gated.

## Minting the scoped SA (the one manual step)

A 1Password Service Account cannot mint another SA, and the CLI/desktop session is not
authorized to (403) — it needs an account **Owner** via the **web console**
(*Developer -> Service Accounts -> Create*), granting **Read-only on `hub-eso` only**.
(`recreate-hub.sh` consumes the resulting token; it does not create the SA.)

## Dormant Azure (NOT deleted)

`azure-keyvault-store` CSS, Azure Key Vault `keyvault-thcmfmoo5oeow`, the AD App, and the
Azure OIDC issuer (`oidcissuer04a3332f`) are left **dormant** — not deleted. Do NOT
re-introduce Azure WI as the hub root, and do NOT re-add `azure-keyvault-store` on a spoke.

## Gotchas (learned during the live cutover)

- **`decodingStrategy: Base64`** — `tailnet-ca` is the one ES with it. Its `hub-eso` items
  (`TAILNET-DEV-CA-CRT/KEY`) must store the **base64-encoded** value (the k8s `.data` form
  AS-IS), NOT the raw PEM, or ESO's base64-decode fails ("illegal base64 data"). All other
  hub secrets are raw (`decodingStrategy: None`).
- **Stale `before-first-apply` field manager** — on some ES (seen on the 2 mlflow ES) a
  legacy SSA field manager co-owns `spec.data` and blocks ArgoCD from writing the new
  `/password` keys. Heal with `kubectl apply --server-side --force-conflicts` of the
  origin/main manifest.
- **Child apps track `main` directly** — the 17 child-app ES flip on a merge to `main`
  (ahead of the `env/hub`-gated CSS). Until the CSS + token exist, ESO retains the target
  Secrets (no wipe). Create the token + CSS first, or promote `env/hub` together.

See also: `runbooks/build-hub.md` (bootstrap order), `references/hub.md` (hub desired state),
and the stacks-repo `packages/components/hub-onepassword/README.md` (the canonical living source).
