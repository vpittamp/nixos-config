# Runbook: Manage GitOps Promoter and the ArgoCD UI extension

## When to use

Use this when you need to:
- Upgrade the GitOps Promoter controller.
- Install or repair the GitOps Promoter ArgoCD UI extension.
- Recover a hub self-management rollout that is stuck between `origin/main`, `env/hub-next`, and `env/hub`.

## Current deployment shape

GitOps Promoter is hub-managed by ArgoCD:

| Component | Path | Notes |
|---|---|---|
| Promoter Helm app | `packages/components/hub-management/apps/gitops-promoter.yaml` | Chart install plus `manager.image.tag` override when chart appVersion lags the latest app release |
| Promoter config app | `packages/components/hub-management/apps/gitops-promoter-config.yaml` | Promotion strategies, commit statuses, GitRepository, and inventory resources |
| ArgoCD UI extension app | `packages/components/hub-management/apps/argocd-gitops-promoter-ui.yaml` | Applies the UI extension patch resources into `argocd` |
| UI extension manifests | `packages/components/hub-management/manifests/argocd-gitops-promoter-ui/` | RBAC, `argocd-cm` resource links, and a Sync hook Job that patches `argocd-server` |
| Bootstrap ArgoCD values | `deployment/config/argocd-values.yaml` | Fresh installs should get the same UI extension config without relying only on the patch Job |

As of 2026-04-24:
- Latest GitOps Promoter app release used here: `v0.27.1`.
- Latest Helm chart at upgrade time: `0.6.0`.
- Chart `appVersion` at upgrade time: `0.26.2`.
- Live controller image should be `quay.io/argoprojlabs/gitops-promoter:v0.27.1`.

## Upgrade procedure

1. Check the latest upstream release and latest Helm chart:

```bash
gh release view --repo argoproj-labs/gitops-promoter --json tagName,publishedAt,url,name
helm show chart gitops-promoter --repo https://argoproj-labs.github.io/gitops-promoter-helm | \
  grep -E '^(name|version|appVersion):'
```

2. If the Helm chart has a newer chart version, update `targetRevision` in `packages/components/hub-management/apps/gitops-promoter.yaml` after checking chart values compatibility.

3. If the app release is newer than the chart `appVersion`, keep the chart version and override the controller image tag:

```yaml
manager:
  image:
    tag: vX.Y.Z
```

4. Update the UI extension URLs to the same app release in both places:

```text
packages/components/hub-management/manifests/argocd-gitops-promoter-ui/Job-argocd-gitops-promoter-ui-patch.yaml
deployment/config/argocd-values.yaml
```

Use:

```text
https://github.com/argoproj-labs/gitops-promoter/releases/download/vX.Y.Z/gitops-promoter-argocd-extension.tar.gz
https://github.com/argoproj-labs/gitops-promoter/releases/download/vX.Y.Z/gitops-promoter_X.Y.Z_checksums.txt
```

5. Validate before pushing:

```bash
kubectl --context hub apply --server-side --dry-run=server \
  -k packages/components/hub-management/manifests/argocd-gitops-promoter-ui
kubectl kustomize packages/overlays/hub >/tmp/hub-render.yaml
kubectl kustomize packages/overlays/dev >/tmp/dev-render.yaml
kubectl kustomize packages/overlays/staging >/tmp/staging-render.yaml
git diff --check
```

6. Push to both remotes:

```bash
git push origin HEAD:main
git push gitea-ryzen HEAD:main
```

7. Let source-hydrator and Promoter move `origin/main` through `env/hub-next` to `env/hub`. If hub promotion does not create/merge the PR, inspect `stacks-environments` and open/merge the `env/hub-next` → `env/hub` PR only if the diff is expected.

If `env/hub-next` has advanced but `ChangeTransferPolicy/stacks-environments-env-hub-*` still proposes a prior dry SHA or prior PR, force a promoter refresh before bypassing the normal flow:

```bash
TS=$(date +%s)
kubectl --kubeconfig ~/.kube/hub-config annotate promotionstrategy stacks-environments -n argocd \
  promoter.argoproj.io/refresh-ts="$TS" --overwrite
kubectl --kubeconfig ~/.kube/hub-config annotate changetransferpolicy stacks-environments-env-hub-8c9641d5 -n argocd \
  promoter.argoproj.io/refresh-ts="$TS" --overwrite
```

## UI extension details

The UI extension follows the upstream ArgoCD integration pattern: an `extension-gitops-promoter` initContainer downloads the release tarball, verifies the checksum, and writes extension files to an `extensions` emptyDir mounted at `/tmp/extensions/`.

Important implementation details:
- Use `quay.io/argoprojlabs/argocd-extension-installer:v0.0.9@sha256:d2b43c18ac1401f579f6d27878f45e253d1e3f30287471ae74e6a4315ceb0611` for the extension installer unless upstream changes the recommendation.
- The patch Job runs shell logic, so its kubectl image must contain `/bin/sh`. `registry.k8s.io/kubectl` is distroless and fails with `exec: "/bin/sh": stat /bin/sh: no such file or directory`. Use `alpine/k8s:<kubernetes-version>`.
- The ArgoCD Helm chart names the container `server`, not `argocd-server`. JSONPath checks must look for `.spec.template.spec.containers[?(@.name=="server")]`.
- The `argocd-cm` settings add `promoter.argoproj.io/commit-status` to `resource.customLabels` and Pull Request links for `PullRequest` and `ChangeTransferPolicy`.

## Recover stale hub hydration

Symptom: `origin/main` has the new commit, but `root-application.status.sourceHydrator.currentOperation.drySHA` remains at an older SHA and `env/hub-next` is not advancing.

Fix:

```bash
kubectl --context hub -n argocd patch applications.argoproj.io/root-application --type=json -p='[
  {"op":"remove","path":"/status/sourceHydrator/currentOperation"},
  {"op":"remove","path":"/status/sourceHydrator/lastSuccessfulOperation"}
]'
kubectl --context hub -n argocd annotate applications.argoproj.io/root-application \
  argocd.argoproj.io/hard-refresh="$(date +%s)" --overwrite
```

Then poll:

```bash
kubectl --context hub -n argocd get applications.argoproj.io root-application -o json | \
  jq '.status.sourceHydrator'
git ls-remote origin refs/heads/env/hub-next refs/heads/env/hub
```

## Recover stale hub promotion proposal

Symptom: `root-application.status.sourceHydrator.currentOperation.drySHA` matches the latest `origin/main`, and `env/hub-next` has the latest hydrated commit, but `ChangeTransferPolicy/stacks-environments-env-hub-*` still shows the previously merged dry SHA/PR.

Fix:

```bash
TS=$(date +%s)
kubectl --kubeconfig ~/.kube/hub-config annotate promotionstrategy stacks-environments -n argocd \
  promoter.argoproj.io/refresh-ts="$TS" --overwrite
kubectl --kubeconfig ~/.kube/hub-config annotate changetransferpolicy stacks-environments-env-hub-8c9641d5 -n argocd \
  promoter.argoproj.io/refresh-ts="$TS" --overwrite

kubectl --kubeconfig ~/.kube/hub-config get changetransferpolicy stacks-environments-env-hub-8c9641d5 -n argocd -o json |
  jq '{activeDry:.status.active.dry.sha, proposedDry:.status.proposed.dry.sha, proposedHydrated:.status.proposed.hydrated.sha, pr:.status.pullRequest}'
gh pr list --repo PittampalliOrg/stacks --state open --base env/hub --json number,title,headRefName,url
```

Expected: the proposed dry SHA advances to the latest main commit and a new `env/hub` PR appears. Merge it after checking the diff is expected.

## Recover a failed UI patch hook

Symptoms:
- `argocd-gitops-promoter-ui` operation is stuck waiting for `batch/Job/argocd-gitops-promoter-ui-patch`.
- Hook pod shows `RunContainerError`, `ImagePullBackOff`, or a shell startup error.
- ArgoCD app operation is still tied to an older revision even after a fixed commit lands.

Fix:

```bash
kubectl --context hub -n argocd logs job/argocd-gitops-promoter-ui-patch --all-containers=true --tail=200
kubectl --context hub -n argocd describe pod -l job-name=argocd-gitops-promoter-ui-patch

argocd app terminate-op argocd-gitops-promoter-ui --grpc-web || true
kubectl --context hub -n argocd delete job argocd-gitops-promoter-ui-patch --ignore-not-found=true
kubectl --context hub -n argocd annotate applications.argoproj.io/argocd-gitops-promoter-ui \
  argocd.argoproj.io/refresh=hard --overwrite
argocd app sync argocd-gitops-promoter-ui --grpc-web --prune
```

Do not pass `--force` when the app uses `ServerSideApply=true`; ArgoCD rejects `--force` with server-side apply.

## Verify

```bash
# Promoter controller is upgraded and healthy
kubectl --context hub -n gitops-promoter-system rollout status \
  deploy/gitops-promoter-controller-manager --timeout=300s
kubectl --context hub -n gitops-promoter-system get deploy gitops-promoter-controller-manager \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="manager")].image}{"\n"}'
kubectl --context hub -n gitops-promoter-system get pods -o wide

# UI app is synced and healthy
kubectl --context hub -n argocd get applications.argoproj.io \
  argocd-gitops-promoter-ui gitops-promoter gitops-promoter-config -o wide

# ArgoCD server has the extension initContainer and mount
kubectl --context hub -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl --context hub -n argocd get deploy argocd-server \
  -o jsonpath='{.spec.template.spec.initContainers[?(@.name=="extension-gitops-promoter")].env[?(@.name=="EXTENSION_URL")].value}{"\n"}'
kubectl --context hub -n argocd get deploy argocd-server \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="server")].volumeMounts[?(@.name=="extensions")].mountPath}{"\n"}'

# Extension installer actually downloaded and installed the UI bundle
kubectl --context hub -n argocd logs deploy/argocd-server \
  -c extension-gitops-promoter --tail=100

# ArgoCD resource metadata is configured for Promoter CRDs
kubectl --context hub -n argocd get cm argocd-cm \
  -o jsonpath='{.data.resource\.customLabels}{"\n"}{.data.resource\.links}{"\n"}'
```

Expected:
- Controller image matches the intended app release.
- `argocd-gitops-promoter-ui`, `gitops-promoter`, and `gitops-promoter-config` are Synced/Healthy.
- `argocd-server` logs show `UI extension downloaded successfully` and `UI extension installed successfully`.
- The ArgoCD web UI has a GitOps Promoter section.
