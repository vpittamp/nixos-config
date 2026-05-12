# Runbook: Grant `stacks` repo access to GHCR packages for release-pin validation

## Symptoms / when to use

GitHub Action **Validate Workflow Builder Release Pins** (`.github/workflows/validate-workflow-builder-release-pins.yml`) fails on `main` and on PRs with errors like:

```
time="…" level=fatal msg="Error parsing image name \"docker://ghcr.io/pittampalliorg/<image>:<tag>\":
  reading manifest <tag> in ghcr.io/pittampalliorg/<image>: denied"
ERROR: failed to inspect ghcr.io/pittampalliorg/<image>:<tag>
```

The job fails for **every** (or many) images at once, not a single tag. Symptom is consistent across pushes and re-runs.

`denied` here is **authz**, not "tag missing". The tag almost certainly exists on GHCR — confirm via the package's versions page if in doubt. The workflow auth path is broken instead.

## Root cause

The PittampalliOrg GHCR container packages built by other repos (workflow-builder, opencode-durable-agent, browserstation, etc.) are **private**. A workflow's standard `GITHUB_TOKEN` can only read another repo's private GHCR package if that package is **linked to the workflow's repo** under **Manage Actions access**.

The validate workflow runs in `PittampalliOrg/stacks` with `permissions: packages: read`, but images are built in `PittampalliOrg/workflow-builder` (etc.). Without the per-package access grant to `stacks`, `skopeo inspect --creds $GITHUB_ACTOR:$GITHUB_TOKEN ...` returns `denied` for each image.

## Diagnostic

1. Pull the failed run's log and confirm every error is `denied` on a `ghcr.io/pittampalliorg/<image>:<tag>` manifest:

```bash
gh run list --workflow="Validate Workflow Builder Release Pins" --limit 1 \
  --json databaseId --jq '.[0].databaseId' \
  | xargs -I{} gh run view {} --log-failed | grep -E "denied|ERROR:" | head -40
```

2. Confirm the package is private (anonymous probe returns 401, not 404):

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  "https://ghcr.io/v2/pittampalliorg/workflow-orchestrator/manifests/git-<sha>"
# HTTP 401  → private, needs auth (this case)
# HTTP 404  → tag actually missing (different problem; see promote-image-to-spokes.md)
# HTTP 200  → public, denied means something else
```

3. Confirm the workflow's permissions block grants `packages: read`. Look at the head of `.github/workflows/validate-workflow-builder-release-pins.yml`:

```yaml
permissions:
  contents: read
  packages: read
```

If missing, that's a separate bug — add it.

4. Spot-check one package's Manage Actions access in the GitHub UI:

```
https://github.com/orgs/PittampalliOrg/packages/container/<package>/settings
```

Scroll to **Manage Actions access**. If `PittampalliOrg/stacks` is not listed (or listed without Read), that package is the cause.

## Fix steps

The fix is **per-package** and must be performed via the GitHub UI by an org admin — this modifies package access controls and is not safe to automate from an agent.

For each image listed under `images:` in `packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml`:

1. Open `https://github.com/orgs/PittampalliOrg/packages/container/<package>/settings`.
2. Scroll to **Manage Actions access** → click **Add Repository**.
3. Search `stacks`, select `PittampalliOrg/stacks`, set **Role: Read**.
4. Save.

Generate the URL list from the release-pins file directly:

```bash
yq '.images | keys | .[]' \
  packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml \
  | sed 's|.*|https://github.com/orgs/PittampalliOrg/packages/container/&/settings|'
```

Note one rename: `workspace-runtime` in release-pins resolves to the `opencode-durable-agent` package (see `scripts/gitops/validate-workflow-builder-release-pins.sh` `repository_for()`). Link `opencode-durable-agent`, not `workspace-runtime`.

## Verify

Trigger a fresh run and watch it to completion:

```bash
gh workflow run validate-workflow-builder-release-pins.yml --ref main
sleep 5
gh run list --workflow="Validate Workflow Builder Release Pins" --limit 1 \
  --json databaseId --jq '.[0].databaseId' \
  | xargs -I{} gh run watch {} --exit-status
```

Expected: `Validate release pins ✓` step exits 0 and the run conclusion is `success`. If some packages still error with `denied`, those specific ones missed the link — go back to step 1 for each.

## Maintenance

- **Adding a new image to release-pins?** Link its GHCR package to `stacks` **before** committing the release-pins entry, or the next CI run goes red.
- **Renaming/replacing a GHCR package?** The new package needs its own link; the old package's link does not carry over.
- A useful audit query (requires a PAT with `read:packages`):

```bash
for pkg in $(yq '.images | keys | .[]' packages/components/hub-spoke-appsets/release-pins/workflow-builder-images.yaml); do
  pkg=${pkg//workspace-runtime/opencode-durable-agent}
  curl -s -H "Authorization: Bearer $GHCR_PAT" \
    "https://api.github.com/orgs/PittampalliOrg/packages/container/${pkg}/actions-permissions/repositories" \
    | jq -r --arg p "$pkg" '.repositories[]?.full_name | select(. == "PittampalliOrg/stacks") | "\($p) OK"'
done
```

Packages that print nothing are missing the `stacks` link.

## Related

- `runbooks/promote-image-to-spokes.md` — distinguishes auth failure from missing-tag failure.
- `reference/access-paths.md` — GHCR creds matrix.
- Validate script: `scripts/gitops/validate-workflow-builder-release-pins.sh` (function `inspect()` is the auth boundary).
