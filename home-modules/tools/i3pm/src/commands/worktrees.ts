/**
 * `i3pm worktrees` — the cross-repository cleanup view.
 *
 * This is the one capability the repos.json inventory provided that nothing
 * else replaces: which checkouts are merged, stale, or registered but gone.
 * The daemon no longer keeps a list; the command asks git directly, in
 * parallel, every time it runs.
 */

import { parseArgs } from "@std/cli/parse-args";
import { bold, cyan, dim, green, red, yellow } from "jsr:@std/fmt/colors";
import {
  type BareRepositoryRef,
  DEFAULT_CONCURRENCY,
  DEFAULT_STALE_DAYS,
  isIncomplete,
  pruneRepositories,
  scanWorktrees,
  type WorktreeReport,
  type WorktreeScanResult,
} from "../services/worktree-scan.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

function showHelp(): void {
  console.log(`i3pm worktrees [filters] [options]

List every git worktree of every bare repository under the scan roots
(default ~/repos/<account>/<repo>/.bare), enumerated on demand. Nothing is
cached and nothing is written — git is the inventory.

FILTERS (combine as a union; with none, everything is listed):
  --merged            Branch already merged into the trunk, or a detached
                      checkout whose commit the trunk already contains
  --stale             Tip commit older than --stale-days
  --missing           git holds a registration but the checkout is gone

ACTIONS:
  --prune             Drop the dead registrations of repositories that have
                      missing worktrees (git worktree prune). Never deletes a
                      checkout that still exists.
  --dry-run           With --prune, report what would be dropped

OPTIONS:
  --root <path>       Scan root, repeatable (default ~/repos)
  --account <name>    Only scan one account directory
  --stale-days <n>    Age threshold for --stale (default ${DEFAULT_STALE_DAYS})
  --concurrency <n>   Git processes in flight (default ${DEFAULT_CONCURRENCY})
  --paths             Print bare paths only, one per line
  --json              Emit the full report as JSON
  -h, --help          Show this help

EXIT CODES:
  0  the report is complete
  1  the report is incomplete (a repository could not be listed, a checkout
     could not be read, or git could not be started), or a prune failed

EXAMPLES:
  i3pm worktrees                          Everything git knows about
  i3pm worktrees --merged --stale         Cleanup candidates
  i3pm worktrees --missing --json         Dead registrations, machine readable
  i3pm worktrees --prune --dry-run        What a prune would drop
  i3pm worktrees --merged --paths | xargs -n1 git worktree remove`);
}

export async function worktreesCommand(
  args: string[],
  _options: CommandOptions = {},
): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json", "merged", "stale", "missing", "prune", "dry-run", "paths"],
    string: ["root", "account", "stale-days", "concurrency"],
    collect: ["root"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    showHelp();
    return 0;
  }

  const staleDays = parsePositiveInt(parsed["stale-days"], DEFAULT_STALE_DAYS);
  const concurrency = parsePositiveInt(parsed.concurrency, DEFAULT_CONCURRENCY);
  if (staleDays === null || concurrency === null) {
    console.error("Error: --stale-days and --concurrency take a positive integer");
    return 1;
  }

  const roots = (parsed.root as string[]).map(String).filter(Boolean);
  const result = await scanWorktrees({
    roots,
    account: parsed.account ? String(parsed.account) : undefined,
    staleDays,
    concurrency,
  });

  // A scan that could not start git saw nothing, so every "0 found" below would
  // be a lie. Say so before printing a report shaped like a successful one.
  if (result.spawn_failure) {
    console.error(`Error: git could not be started: ${result.spawn_failure}`);
    console.error("Nothing was scanned.");
    return 1;
  }

  const selected = selectWorktrees(result.worktrees, {
    merged: parsed.merged,
    stale: parsed.stale,
    missing: parsed.missing || parsed.prune,
  });

  const prunes = parsed.prune
    ? await pruneRepositories(repositoriesWithMissing(result), {
      dryRun: parsed["dry-run"],
      concurrency,
    })
    : [];
  const pruneFailed = prunes.some((outcome) => !outcome.ok);

  if (parsed.json) {
    console.log(JSON.stringify(
      {
        roots: result.roots,
        repositories: result.repositories.length,
        scanned: result.repositories.length - result.skipped.length,
        total: result.worktrees.length,
        matched: selected.length,
        filters: {
          merged: parsed.merged,
          stale: parsed.stale,
          missing: parsed.missing || parsed.prune,
          stale_days: staleDays,
        },
        worktrees: selected,
        skipped: result.skipped,
        pruned: prunes,
        incomplete: isIncomplete(result),
        duration_ms: result.duration_ms,
      },
      null,
      2,
    ));
  } else {
    if (parsed.paths) {
      for (const worktree of selected) {
        console.log(worktree.path);
      }
    } else {
      renderReport(result, selected, prunes, staleDays);
    }
    renderDiagnostics(result, prunes);
  }

  return isIncomplete(result) || pruneFailed ? 1 : 0;
}

interface Filters {
  merged: boolean;
  stale: boolean;
  missing: boolean;
}

/**
 * Apply the filters as a union.
 *
 * `--merged --stale` asks for everything worth looking at, not for the
 * intersection of two rare properties.
 */
export function selectWorktrees(
  worktrees: WorktreeReport[],
  filters: Filters,
): WorktreeReport[] {
  if (!filters.merged && !filters.stale && !filters.missing) return worktrees;
  return worktrees.filter((worktree) =>
    (filters.merged && worktree.is_merged) ||
    (filters.stale && worktree.is_stale) ||
    (filters.missing && worktree.missing)
  );
}

/** The repositories holding at least one registration whose checkout is gone. */
function repositoriesWithMissing(result: WorktreeScanResult): BareRepositoryRef[] {
  const dead = new Set(
    result.worktrees.filter((worktree) => worktree.missing).map((worktree) => worktree.repo_path),
  );
  return result.repositories.filter((repository) => dead.has(repository.repo_path));
}

/** The properties worth naming on a report row, in priority order. */
export function worktreeTags(worktree: WorktreeReport): string[] {
  const tags: string[] = [];
  if (worktree.missing) tags.push("missing");
  if (worktree.locked) tags.push("locked");
  if (worktree.unreadable) tags.push("unreadable");
  if (worktree.detached) tags.push("detached");
  if (worktree.is_merged) tags.push("merged");
  if (worktree.is_stale) tags.push("stale");
  if (!worktree.missing && !worktree.is_clean) tags.push("dirty");
  return tags;
}

function renderReport(
  result: WorktreeScanResult,
  selected: WorktreeReport[],
  prunes: Awaited<ReturnType<typeof pruneRepositories>>,
  staleDays: number,
): void {
  const home = Deno.env.get("HOME") || "";
  const branchWidth = Math.min(
    44,
    Math.max(12, ...selected.map((worktree) => branchLabel(worktree).length)),
  );
  const tagWidth = Math.min(
    32,
    Math.max(8, ...selected.map((worktree) => worktreeTags(worktree).join(",").length)),
  );

  let currentRepo = "";
  for (const worktree of selected) {
    const repoKey = `${worktree.account}/${worktree.repo}`;
    if (repoKey !== currentRepo) {
      currentRepo = repoKey;
      console.log("");
      console.log(bold(repoKey));
    }
    const tags = worktreeTags(worktree);
    console.log(
      `  ${colorTags(tags).padEnd(tagWidth + colorPadding(tags))}  ` +
        `${branchLabel(worktree).padEnd(branchWidth)}  ` +
        `${formatAge(worktree.age_days).padStart(5)}  ` +
        dim(shorten(worktree.path, home)),
    );
  }

  const scanned = result.repositories.length - result.skipped.length;
  console.log("");
  console.log(
    `${bold("Repositories")} ${cyan(String(scanned))}/${result.repositories.length}   ` +
      `${bold("Worktrees")} ${cyan(String(selected.length))}/${result.worktrees.length}   ` +
      `${bold("Stale after")} ${staleDays}d   ` +
      dim(`${result.duration_ms}ms`),
  );

  const counts = countBy(result.worktrees);
  console.log(
    `  ${counts.merged} merged, ${counts.stale} stale, ${counts.missing} missing, ` +
      `${counts.detached} detached, ${counts.dirty} dirty`,
  );

  for (const outcome of prunes.filter((candidate) => candidate.ok)) {
    const verb = outcome.dry_run ? "would drop" : "dropped";
    console.log(
      `  ${green(verb)} ${outcome.removed.length} in ${outcome.account}/${outcome.repo}`,
    );
    for (const line of outcome.removed) {
      console.log(`    ${dim(line)}`);
    }
  }
}

/**
 * Report what the scan could not see, on stderr.
 *
 * stderr rather than stdout so that a repository which failed to list is still
 * visible when the caller is piping `--paths` into `xargs`. A repository that
 * could not be listed contributes zero rows to every count, which is otherwise
 * indistinguishable from a repository with nothing to report.
 */
function renderDiagnostics(
  result: WorktreeScanResult,
  prunes: Awaited<ReturnType<typeof pruneRepositories>>,
): void {
  const home = Deno.env.get("HOME") || "";

  for (const outcome of prunes.filter((candidate) => !candidate.ok)) {
    console.error(`${red("prune failed")} ${outcome.account}/${outcome.repo}: ${outcome.error}`);
  }
  for (const skip of result.skipped) {
    console.error(`${red("skipped")} ${skip.account}/${skip.repo}: ${skip.reason}`);
  }
  for (const worktree of result.worktrees.filter((candidate) => candidate.unreadable)) {
    console.error(`${yellow("unreadable")} ${shorten(worktree.path, home)}`);
  }
  if (isIncomplete(result)) {
    console.error(yellow("This report is incomplete."));
  }
}

function countBy(worktrees: WorktreeReport[]) {
  return {
    merged: worktrees.filter((worktree) => worktree.is_merged).length,
    stale: worktrees.filter((worktree) => worktree.is_stale).length,
    missing: worktrees.filter((worktree) => worktree.missing).length,
    detached: worktrees.filter((worktree) => worktree.detached).length,
    dirty: worktrees.filter((worktree) => !worktree.missing && !worktree.is_clean).length,
  };
}

function branchLabel(worktree: WorktreeReport): string {
  if (worktree.branch) return worktree.branch;
  return worktree.commit ? `(${worktree.commit.substring(0, 8)})` : "(detached)";
}

function colorTags(tags: string[]): string {
  return tags.map((tag) => {
    if (tag === "missing" || tag === "unreadable") return red(tag);
    if (tag === "merged") return green(tag);
    if (tag === "stale" || tag === "locked") return yellow(tag);
    return dim(tag);
  }).join(dim(","));
}

/** Extra width the ANSI escapes add, so padEnd still lines the columns up. */
function colorPadding(tags: string[]): number {
  const plain = tags.join(",").length;
  const colored = colorTags(tags).length;
  return colored - plain;
}

function formatAge(days: number | null): string {
  if (days === null) return "-";
  if (days < 999) return `${days}d`;
  return "999d+";
}

function shorten(target: string, home: string): string {
  return home && target.startsWith(`${home}/`) ? `~${target.substring(home.length)}` : target;
}

function parsePositiveInt(raw: unknown, fallback: number): number | null {
  const text = String(raw ?? "").trim();
  if (!text) return fallback;
  const value = Number.parseInt(text, 10);
  return Number.isFinite(value) && value > 0 ? value : null;
}
