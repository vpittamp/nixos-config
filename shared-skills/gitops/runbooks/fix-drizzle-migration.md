# Runbook: Migration shipped but columns missing on dev/staging

## Symptoms / when to use

You added a new SQL migration to `drizzle/`, image was built and rolled out to dev, the `db-migrate` Sync hook reports `phase=Succeeded`, but the new column(s) aren't on dev's postgres. Concrete signs:

- `kubectl --kubeconfig ~/.kube/hub-config get app dev-workflow-builder -o json | jq '.status.operationState.syncResult.resources[] | select(.name=="db-migrate")'` → `hookPhase: Succeeded`, `message: "Reached expected number of succeeded pods"`.
- BFF returns `500` on any endpoint that selects the new column, with body like `{"message":"Failed query: select … \"role\", \"composition_graph\" … from \"code_functions\" …"}`.
- `\d <table>` on dev's postgres (via `kubectl exec sts/postgresql -- psql -U postgres -d workflow_builder`) doesn't show the new columns.

The trap: `npx drizzle-kit migrate` (what `db-migrate` runs) silently skips SQL files that don't have a corresponding entry in `drizzle/meta/_journal.json`. The Job exits 0 either way.

## Diagnostic — confirm the journal gap

From the workflow-builder repo:

```bash
node -e '
const fs = require("node:fs");
const path = require("node:path");
const dir = "drizzle";
const journal = JSON.parse(fs.readFileSync(path.join(dir, "meta/_journal.json"), "utf8"));
const tagsInJournal = new Set(journal.entries.map(e => e.tag));
const sqlFiles = fs.readdirSync(dir).filter(f => f.endsWith(".sql")).map(f => f.replace(".sql", ""));
console.log("SQL files in dir:", sqlFiles.length);
console.log("Tags in journal:", tagsInJournal.size);
console.log("Files NOT in journal:", sqlFiles.filter(f => !tagsInJournal.has(f)));
'
```

Your new file in the "NOT in journal" list = silent skip confirmed. (Note: many older files are also missing from the journal; their columns are present on dev only because they were applied via some out-of-band path — manual psql, prior atlas runs, etc. Don't try to "fix" those en masse: re-running them might fail on `ADD COLUMN` without `IF NOT EXISTS`. Just add YOUR new file's entry.)

## Background — why two directories

This repo has TWO migration runners that read from different directories:

| Runner | Reads from | Tracking table | Active where |
|---|---|---|---|
| `src/lib/server/startup.ts` (BFF process) | `atlas/migrations/` (timestamp-prefixed) | `_app_migrations` | Ryzen devspace pod ONLY (file-syncs source) — production image excludes `atlas/` via `.dockerignore` |
| `npx drizzle-kit migrate` (`db-migrate` Sync hook) | `drizzle/` (incremental-prefixed, gated by `_journal.json`) | `__drizzle_migrations` | Dev + staging (every sync) |

So a new migration must usually live in BOTH dirs:
- `drizzle/<NNNN>_<name>.sql` + matching `_journal.json` entry → covers dev/staging.
- `atlas/migrations/<YYYYMMDDhhmmss>_<name>.sql` → covers ryzen devspace.

Both copies should be **idempotent** (`ADD COLUMN IF NOT EXISTS`, named CHECK constraint guards) so running on a DB that already has them is a no-op.

## Fix steps

1. **Add the journal entry** for the drizzle file:

```bash
node -e '
const fs = require("node:fs");
const path = "drizzle/meta/_journal.json";
const j = JSON.parse(fs.readFileSync(path, "utf8"));
const next = Math.max(...j.entries.map(e => e.idx)) + 1;
j.entries.push({
  idx: next,
  version: "7",
  when: Date.now(),
  tag: "<NNNN>_<name>",   // basename WITHOUT .sql, e.g. "0044_code_functions_role"
  breakpoints: true,
});
fs.writeFileSync(path, JSON.stringify(j, null, "\t") + "\n");
console.log("added entry idx=" + next);
'
```

2. **Also drop a copy into `atlas/migrations/`** if you want the ryzen devspace pod to apply it on its next restart:

```bash
cp drizzle/<NNNN>_<name>.sql atlas/migrations/$(date -u +%Y%m%d%H%M%S)_<name>.sql

# Update atlas.sum (use docker because atlas binary isn't usually in $PATH; mount via /tmp
# to avoid worktree-symlink mount issues from .bare/worktrees layouts):
cp -r atlas/migrations /tmp/atlas-mig
docker run --rm -v /tmp/atlas-mig:/migrations arigaio/atlas:latest \
  migrate hash --dir file:///migrations
cp /tmp/atlas-mig/atlas.sum atlas/migrations/atlas.sum
rm -rf /tmp/atlas-mig
```

3. **Commit + push to BOTH workflow-builder remotes** (origin = GitHub, gitea-ryzen = inner-loop trigger):

```bash
git add drizzle/meta/_journal.json drizzle/<NNNN>_<name>.sql \
        atlas/migrations/atlas.sum atlas/migrations/<timestamp>_<name>.sql
git commit -m "fix(migrations): register <NNNN>_<name> in drizzle journal"
git push origin main
git push gitea-ryzen main
```

4. **Wait for the new image to build + roll** through the normal pipeline (ryzen Tekton inner-loop builds, mirror to ghcr.io if hub Tekton outer-loop is still broken — see `mirror-image-gitea-to-ghcr.md` — then bump release-pins per `promote-image-to-spokes.md`).

5. The next dev sync will run `db-migrate` with the updated image; the `__drizzle_migrations` table will get a row, and the `ADD COLUMN` will execute.

## Verify

```bash
# 1. db-migrate Job ran with the new image
kubectl --kubeconfig ~/.kube/hub-config get app dev-workflow-builder \
  -o json | jq '.status.operationState.syncResult.resources[] | select(.name=="db-migrate") | {hookPhase,message}'
# hookPhase: "Succeeded"

# 2. Columns actually exist
KUBECONFIG=/tmp/dev-kubeconfig kubectl -n workflow-builder exec sts/postgresql \
  -- psql -U postgres -d workflow_builder -c "\d <table>" | grep -E "<col_a>|<col_b>"

# 3. BFF endpoint stops 500ing
curl -sk https://workflow-builder-dev.tail286401.ts.net/api/<endpoint-using-new-cols> \
  -o /dev/null -w "%{http_code}\n"
# Expect 200 or 401 (401 = auth required — that's fine; the SELECT didn't fail)
```

## Risks

- **The journal-skip behavior bites every new migration**, not just yours. There's currently a backlog of files in `drizzle/` (including old ones like `0006_*`, `0020_*`, `0032_*`, plus newer `0037_*`–`0043_*`) that lack journal entries. Don't add them all en masse — many will fail `ADD COLUMN` without `IF NOT EXISTS`, and their columns are already present on dev/staging from prior out-of-band application.
- **idx must be unique and incrementing.** If two PRs in flight both add idx=N+1, the second to merge will need a rebase to bump to N+2.
- **Make migrations idempotent.** Use `ADD COLUMN IF NOT EXISTS`, named CHECK constraint guards (`DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='...') THEN ALTER TABLE ... ADD CONSTRAINT ... END IF; END $$`), `CREATE INDEX IF NOT EXISTS`. Re-runs are common (every spoke + the ryzen devspace pod restart cycle) and a non-idempotent migration breaks one of those paths.

## Why it's like this

Drizzle Kit was originally designed for greenfield schemas where every migration is generated from a schema diff and the journal is auto-maintained. This repo deviated by adding hand-written SQL files for ops migrations (NOT NULL backfills, JSONB columns, indexes) without re-running `drizzle-kit generate`, so the journal stopped reflecting the directory contents. The atlas-runner in startup.ts was an experiment to get around this; it's effective only inside the ryzen devspace pod because production builds drop `atlas/`. A proper fix would be to either (a) regenerate the journal to include all current files (risky — see Risks), or (b) replace `db-migrate` with a runner that just globs the dir and tracks via a custom table. Until then, every new SQL file needs its journal entry by hand.
