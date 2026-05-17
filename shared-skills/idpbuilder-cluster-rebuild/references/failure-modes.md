# Ryzen Rebuild Failure Modes

## Podman Socket Or Rootless Mode

Symptoms:
- `idpbuilder stacks create --container-engine podman` fails before Talos creates nodes.
- `talosctl cluster create docker` cannot connect to the engine.
- Cleanup tries to use Docker despite the intended Dockerless path.
- Podman reports rootless mode.

Fix:

```bash
export DOCKER_HOST=unix:///run/podman/podman.sock
command -v podman
podman info --format '{{.Host.Security.Rootless}}'
idpbuilder stacks create --help | rg -- '--container-engine|--seed-image-push-engine'
```

Expected rootless value: `false`.

If the current shell is not in the `podman` group after a NixOS rebuild, start a fresh login/session before relying on direct access to `/run/podman/podman.sock`. Do not fall back to Docker silently. For Talos Docker parity, use rootful Podman; rootless work belongs on the kind provider or a future Talos QEMU path.

## Stale Tailscale Names

Symptoms:
- Ingress hostname becomes `gitea-ryzen-2`, `workflow-builder-ryzen-2`, or similar.
- ProxyGroup reports invalid ownership or cannot claim its API service.
- `ryzen-k8s-api.tail286401.ts.net` times out or shows certificate provisioning failures after repeated rebuilds.
- Device-backed app Ingresses are online but the canonical HTTPS endpoint fails certificate provisioning after repeated destructive rebuilds.

Fix:

```bash
CLUSTER_NAME=ryzen deployment/scripts/tailscale/cleanup-old-devices.sh --cluster ryzen --wait
kubectl get proxygroups.tailscale.com k8s-api-cluster -o yaml
```

The cleanup must include both device-backed hostnames and stale API service-hosts such as `svc:ryzen-api`, `svc:ryzen-k8s-api`, and `svc:k8s-api-ryzen`.

If the old stable name hit the Let's Encrypt exact-name rate limit, use the declared alternate API hostname instead of waiting on the old certificate:

```bash
kubectl get proxygroup k8s-api-cluster
deployment/scripts/tailscale/refresh-ryzen-kubeconfig.sh --cluster ryzen --strict-remote-verify
kubectl --context ryzen-cluster get nodes
```

Expected current URL: `https://ryzen-api.tail286401.ts.net`.

For disposable ryzen app Ingresses, a production Let's Encrypt exact-hostname rate limit can block browser-trusted certificate issuance even when Tailscale routing is otherwise healthy. If the Tailscale Ingress status and device are correct, use the ryzen `development` ProxyClass until the rate-limit window clears, then verify with a staging-cert-tolerant smoke test:

```bash
curl -k -sS -L --max-time 30 https://workflow-builder-ryzen.tail286401.ts.net/
```

## Empty Gitea Registry

Symptoms:
- Fresh cluster reaches Argo sync but workload pods fail with `ImagePullBackOff`.
- Gitea registry has no tags for active-development apps.

Fix:

```bash
deployment/scripts/bootstrap/seed-ryzen-images.sh --mode critical
deployment/scripts/bootstrap/seed-ryzen-images.sh --verify-only --mode critical
```

Use GHCR release pins as the bootstrap source. Do not wait for local Gitea or spoke-local Tekton builds to create the first usable images.
The seed path also creates `:latest` compatibility aliases for critical images
that are still referenced by runtime configuration values.

Keep `openshell-sandbox` and `openshell-sandbox-xlsx` if they are referenced by workflow-builder/OpenShell sandbox template env vars. They are large, but the default sandbox templates still use them.

If port-forwarded registry copies are unstable for large images, mirror through the Tailscale Gitea endpoint instead:

```bash
skopeo copy --dest-tls-verify=false docker://ghcr.io/pittampalliorg/<image>:<tag> docker://gitea-ryzen.tail286401.ts.net/giteaadmin/<image>:<tag>
```

## Wrong Active-Development Registry

Symptoms:
- Active-development manifests reference `gitea.cnoe.localtest.me:8443/giteaadmin`.
- Host-side `skopeo inspect` or Gitea tag checks pass, but fresh workload pods still fail with `ImagePullBackOff` or kubelet reports the image is `not found`.
- Loading images directly into node containerd does not clear the pull failure.

Fix:

```bash
deployment/scripts/bootstrap/seed-ryzen-images.sh --rewrite-kustomizations . --skip-copy --quiet
```

Then rebuild/apply manifests and sync the affected ArgoCD apps. The expected rewrite registry is `gitea-ryzen.tail286401.ts.net/giteaadmin` for active-development manifests.

For bootstrap images copied to `gitea.cnoe.localtest.me:8443/giteaadmin`, inspect the node registry/auth path when pulls fail despite Gitea tags existing:

```bash
kubectl --context admin@ryzen get pods -A | rg 'ImagePull|ErrImage|BackOff'
```

Do not replace the hostname registry contract with a raw pod IP endpoint.

## Gitea Repository Create Race

Symptoms:
- `idpbuilder stacks sync` or create logs show Gitea repo create returning HTTP 500.
- The repository exists afterward and a retry works.

Fix:

Use an idpbuilder fork revision that tolerates this partial-create race by checking whether the repo exists after the failed create call. Do not add sleep-only retries in stacks scripts unless the forked command is unavailable.

## Non-Fast-Forward Local Gitea History

Symptoms:
- `idpbuilder stacks sync` prints `Refusing non-fast-forward push; run with --reset-local-history to replace local Gitea history`.
- The local Gitea `stacks` branch is unrelated to the cache clone or was manually rewritten.

Fix:

Prefer preserving local Gitea history. First confirm the installed fork supports cache-backed sync:

```bash
idpbuilder stacks sync --help | rg -- '--watch|--debounce|--cache-dir|--reset-local-history'
```

If the branch is intentionally disposable or corrupted, run the explicit recovery path once:

```bash
idpbuilder stacks sync --reset-local-history --container-engine podman --seed-image-push-engine skopeo
```

Do not add `--force` to normal sync wrappers. The default `cluster-update` path should push descendant commits, skip no-op pushes, and leave unrelated-history replacement as a deliberate operator action.

## Watch Path Falls Back To Repeated Syncs

Symptoms:
- `dev-watch-only` or `deployment/scripts/devenv-up.sh --watch` repeatedly invokes one-shot syncs through `watchexec`.
- Rapid file edits produce multiple Gitea commits instead of one debounced commit.

Fix:

Install a fork revision whose sync command exposes watch flags, then rebuild the host:

```bash
cd /home/vpittamp/repos/vpittamp/nixos-config/main
nix flake lock --update-input idpbuilder-src
sudo nixos-rebuild switch --flake .#ryzen
idpbuilder stacks sync --help | rg -- '--watch|--debounce'
```

After rebuild, this should start the direct watcher:

```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/main
timeout 6 deployment/scripts/devenv-up.sh --watch
```

The timeout interruption is expected for a smoke test; the important signal is that it starts `idpbuilder stacks sync --watch --debounce 2s`.

## Argo Hooks Or Old Images

Symptoms:
- `workflow-builder` sync waits on `db-migrate` or `db-seed`.
- Hook image references an older tag that lacks current scripts or migrations.

Fix the image provenance first: ensure the Gitea tag matches `release-pins/workflow-builder-images.yaml`, then hard refresh or resync the app. Avoid deleting hook jobs unless the desired image is already corrected.

## Azure Workload Identity And External Secrets

Symptoms:
- ExternalSecrets remain not Ready.
- Apps depending on Azure Key Vault fail after the root app sync.

Check:

```bash
kubectl get clustersecretstore
kubectl get externalsecrets -A
deployment/scripts/cluster-readiness.sh wait --cohort gitops-core
```

JWKS sync must happen before workloads that require External Secrets are considered ready.

## Kubeconfig Transfer

Symptoms:
- Local `admin@ryzen` works but `ryzen-cluster` does not.
- ThinkPad still points at an old API endpoint.
- `tailscale file cp` fails with peer ownership errors.
- `ryzen-cluster` resolves to an old `100.x` address after the ProxyGroup recreated.

Use the refresh script and prefer SSH/SCP:

```bash
deployment/scripts/tailscale/refresh-ryzen-kubeconfig.sh --cluster ryzen --strict-remote-verify
deployment/scripts/tailscale/refresh-ryzen-kubeconfig.sh --cluster ryzen --push-host thinkpad
```

Verify with:

```bash
kubectl --context admin@ryzen get nodes
kubectl --context ryzen-cluster get nodes
ssh thinkpad 'kubectl --context ryzen-cluster get nodes'
```
