/**
 * On-demand worktree enumeration.
 *
 * git is the database. Every answer here comes from `git worktree list
 * --porcelain` over the bare repositories under the scan roots, fanned out in
 * parallel and thrown away when the command exits.
 *
 * This replaces the ~/.config/i3/repos.json inventory, which keyed a directory
 * by `account/repo:branch` — a mutable property of that directory. The key went
 * wrong on every `git checkout` and the file went stale on every `git worktree
 * add` that did not go through the daemon, which is now all of them. Nothing
 * here is cached and nothing is written.
 */

import * as path from "@std/path";

export const DEFAULT_CONCURRENCY = 16;
export const DEFAULT_GIT_TIMEOUT_MS = 30_000;

/** A worktree is reported stale once its tip commit is this old. */
export const DEFAULT_STALE_DAYS = 30;

/** How much of a commit subject a report row carries. */
const COMMIT_MESSAGE_LIMIT = 80;

const SECONDS_PER_DAY = 86_400;

/** A `<root>/<account>/<repo>/` directory holding a `.bare` git directory. */
export interface BareRepositoryRef {
  account: string;
  repo: string;
  repo_path: string;
  bare_path: string;
}

/** One checkout git knows about, with everything git can say about it. */
export interface WorktreeReport {
  account: string;
  repo: string;
  repo_path: string;
  path: string;
  commit: string;
  /** null for a detached HEAD, which has no branch to be addressed by. */
  branch: string | null;
  detached: boolean;
  is_trunk: boolean;
  /** git holds a registration but the checkout directory is gone. */
  missing: boolean;
  /** git refuses to prune this one until it is unlocked. */
  locked: boolean;
  /** The checkout exists but its status or log could not be read. */
  unreadable: boolean;
  is_clean: boolean;
  ahead: number;
  behind: number;
  staged_count: number;
  modified_count: number;
  untracked_count: number;
  has_conflicts: boolean;
  last_commit_timestamp: number;
  last_commit_message: string;
  age_days: number | null;
  is_stale: boolean;
  is_merged: boolean;
}

/**
 * A repository whose worktrees could not be enumerated.
 *
 * Reported rather than silently dropped: a repository that fails to list is not
 * a repository with no worktrees, and treating the two alike is how the earlier
 * implementation erased whole repositories while still reporting success.
 */
export interface RepositorySkip {
  account: string;
  repo: string;
  repo_path: string;
  reason: string;
}

export interface WorktreeScanResult {
  roots: string[];
  /** Repositories found under the roots, including any that then failed. */
  repositories: BareRepositoryRef[];
  worktrees: WorktreeReport[];
  skipped: RepositorySkip[];
  /** Non-empty when git could not be started at all, which voids the scan. */
  spawn_failure: string;
  duration_ms: number;
}

export interface ScanOptions {
  /** Directories holding `<account>/<repo>/.bare` layouts. */
  roots?: string[];
  /** Restrict the scan to one account directory name. */
  account?: string;
  concurrency?: number;
  timeoutMs?: number;
  staleDays?: number;
}

/** True when the scan could not see everything it was asked to see. */
export function isIncomplete(result: WorktreeScanResult): boolean {
  return result.spawn_failure !== "" ||
    result.skipped.length > 0 ||
    result.worktrees.some((worktree) => worktree.unreadable);
}

export function defaultScanRoots(): string[] {
  return [path.join(Deno.env.get("HOME") || "", "repos")];
}

/**
 * Find every `<root>/<account>/<repo>/.bare` under the given roots.
 *
 * Globbing the filesystem rather than reading a curated accounts list keeps a
 * newly cloned account visible without a rebuild, and leaves this command with
 * no configuration file to go stale.
 */
export async function findBareRepositories(roots: string[]): Promise<BareRepositoryRef[]> {
  const found: BareRepositoryRef[] = [];

  for (const root of roots) {
    for (const account of await listDirectory(root)) {
      const accountPath = path.join(root, account);
      for (const repo of await listDirectory(accountPath)) {
        const repoPath = path.join(accountPath, repo);
        const barePath = path.join(repoPath, ".bare");
        // "unreadable" is deliberately kept: git is asked anyway, and failing
        // there surfaces the repository as a reported skip instead of quietly
        // dropping it.
        if (await probeDirectory(barePath) === "absent") continue;
        found.push({
          account,
          repo,
          repo_path: repoPath,
          bare_path: barePath,
        });
      }
    }
  }

  found.sort((left, right) =>
    left.account.localeCompare(right.account) || left.repo.localeCompare(right.repo)
  );
  return found;
}

/** Enumerate every worktree of every bare repository under the roots. */
export async function scanWorktrees(options: ScanOptions = {}): Promise<WorktreeScanResult> {
  const startedAt = performance.now();
  const staleDays = options.staleDays ?? DEFAULT_STALE_DAYS;
  const git = createGitRunner(
    Math.max(1, options.concurrency ?? DEFAULT_CONCURRENCY),
    options.timeoutMs ?? DEFAULT_GIT_TIMEOUT_MS,
  );

  const roots = options.roots?.length ? options.roots : defaultScanRoots();
  let repositories = await findBareRepositories(roots);
  if (options.account) {
    repositories = repositories.filter((repository) => repository.account === options.account);
  }

  const scans = await Promise.all(
    repositories.map((repository) => scanRepository(repository, git, staleDays)),
  );

  const worktrees = scans.flatMap((scan) => scan.worktrees);
  const skipped = scans.flatMap((scan) => scan.skip ? [scan.skip] : []);
  worktrees.sort((left, right) =>
    left.account.localeCompare(right.account) ||
    left.repo.localeCompare(right.repo) ||
    (left.branch ?? "").localeCompare(right.branch ?? "") ||
    left.path.localeCompare(right.path)
  );

  return {
    roots,
    repositories,
    worktrees,
    skipped,
    spawn_failure: git.spawnFailure(),
    duration_ms: Math.round(performance.now() - startedAt),
  };
}

export interface PruneOptions {
  dryRun?: boolean;
  concurrency?: number;
  timeoutMs?: number;
}

export interface PruneOutcome {
  account: string;
  repo: string;
  repo_path: string;
  ok: boolean;
  dry_run: boolean;
  /** One line per registration git dropped (or would drop). */
  removed: string[];
  error: string;
}

/**
 * Drop the dead registrations of the given repositories.
 *
 * `git worktree prune` only removes bookkeeping for checkouts whose directory
 * is already gone; it never deletes a checkout. Locked worktrees are left alone
 * by git itself.
 */
export async function pruneRepositories(
  repositories: BareRepositoryRef[],
  options: PruneOptions = {},
): Promise<PruneOutcome[]> {
  const git = createGitRunner(
    Math.max(1, options.concurrency ?? DEFAULT_CONCURRENCY),
    options.timeoutMs ?? DEFAULT_GIT_TIMEOUT_MS,
  );
  const dryRun = options.dryRun === true;

  return await Promise.all(repositories.map(async (repository): Promise<PruneOutcome> => {
    // `--expire=now` overrides gc.worktreePruneExpire (three months by
    // default). Without it a repository reported as having dead registrations
    // is pruned to no effect, because git is still holding them in the grace
    // period — the command would promise a cleanup and quietly not do it.
    const args = ["-C", repository.bare_path, "worktree", "prune", "--verbose", "--expire=now"];
    if (dryRun) args.push("--dry-run");
    const result = await git.run(args);

    // `git worktree prune --verbose` reports on stderr, so a successful prune
    // has a non-empty stderr and that is not an error.
    const lines = result.stderr.split("\n").map((line) => line.trim()).filter(Boolean);
    return {
      account: repository.account,
      repo: repository.repo,
      repo_path: repository.repo_path,
      ok: result.ok,
      dry_run: dryRun,
      removed: result.ok ? lines : [],
      error: result.ok
        ? ""
        : (lines.join("; ") || git.spawnFailure() || "git worktree prune failed"),
    };
  }));
}

interface RepositoryScan {
  worktrees: WorktreeReport[];
  skip?: RepositorySkip;
}

async function scanRepository(
  repository: BareRepositoryRef,
  git: GitRunner,
  staleDays: number,
): Promise<RepositoryScan> {
  const listed = await git.run(["-C", repository.bare_path, "worktree", "list", "--porcelain"]);
  if (!listed.ok) {
    return {
      worktrees: [],
      skip: {
        account: repository.account,
        repo: repository.repo,
        repo_path: repository.repo_path,
        reason: listed.stderr || git.spawnFailure() || "git worktree list failed",
      },
    };
  }

  const records = parseWorktreeList(listed.stdout).filter((record) =>
    !record.bare && record.path && !record.path.endsWith("/.bare")
  );

  const defaultBranch = await resolveDefaultBranch(repository.bare_path, git);
  const merge = await resolveMergeContext(repository.bare_path, defaultBranch, git);
  const nowSeconds = Math.floor(Date.now() / 1000);

  const worktrees = await Promise.all(
    records.map((record) =>
      buildReport({ repository, record, defaultBranch, merge, git, nowSeconds, staleDays })
    ),
  );

  return { worktrees };
}

async function buildReport(context: {
  repository: BareRepositoryRef;
  record: WorktreeRecord;
  defaultBranch: string;
  merge: MergeContext;
  git: GitRunner;
  nowSeconds: number;
  staleDays: number;
}): Promise<WorktreeReport> {
  const { repository, record, git } = context;
  const probe = await probeDirectory(record.path);
  const present = probe === "present";
  // An observation that could not be made is not evidence that a checkout is
  // gone, so an unreadable path is never called missing — it is called
  // unreadable, which makes the whole report incomplete.
  const missing = probe === "absent" || (present && record.prunable);
  const isTrunk = record.branch !== "" &&
    (record.branch === context.defaultBranch || record.branch === "main" ||
      record.branch === "master");

  const [status, commit] = await Promise.all([
    // A checkout that is gone has no working tree to ask about, but the bare
    // repository still knows when its tip commit landed.
    present ? readStatus(record.path, git) : Promise.resolve(null),
    present
      ? readLastCommit(record.path, git)
      : readLastCommit(repository.bare_path, git, record.commit),
  ]);

  const isMerged = await resolveMerged(context, isTrunk);

  const timestamp = commit?.timestamp ?? 0;
  const ageDays = timestamp > 0
    ? Math.floor((context.nowSeconds - timestamp) / SECONDS_PER_DAY)
    : null;
  const staged = status?.staged_count ?? 0;
  const modified = status?.modified_count ?? 0;
  const untracked = status?.untracked_count ?? 0;

  return {
    account: repository.account,
    repo: repository.repo,
    repo_path: repository.repo_path,
    path: record.path,
    commit: record.commit,
    branch: record.branch || null,
    detached: record.branch === "",
    is_trunk: isTrunk,
    missing,
    locked: record.locked,
    unreadable: probe === "unreadable" || (present && (status === null || commit === null)),
    is_clean: staged === 0 && modified === 0 && untracked === 0,
    ahead: status?.ahead ?? 0,
    behind: status?.behind ?? 0,
    staged_count: staged,
    modified_count: modified,
    untracked_count: untracked,
    has_conflicts: status?.has_conflicts ?? false,
    last_commit_timestamp: timestamp,
    last_commit_message: commit?.message ?? "",
    age_days: ageDays,
    is_stale: ageDays !== null && ageDays >= context.staleDays,
    is_merged: isMerged,
  };
}

async function resolveMerged(
  context: {
    repository: BareRepositoryRef;
    record: WorktreeRecord;
    merge: MergeContext;
    git: GitRunner;
  },
  isTrunk: boolean,
): Promise<boolean> {
  const { record, merge } = context;
  if (record.branch) {
    return !isTrunk && merge.branches.has(record.branch);
  }
  // A detached checkout has no branch to look up, but its commit is merged if
  // the trunk already contains it. The old inventory dropped these outright.
  if (!merge.target || !record.commit) return false;
  const ancestor = await context.git.run([
    "-C",
    context.repository.bare_path,
    "merge-base",
    "--is-ancestor",
    record.commit,
    merge.target,
  ]);
  return ancestor.ok;
}

async function resolveDefaultBranch(barePath: string, git: GitRunner): Promise<string> {
  const symbolic = await git.run(["-C", barePath, "symbolic-ref", "refs/remotes/origin/HEAD"]);
  if (symbolic.ok) {
    const match = symbolic.stdout.match(/refs\/remotes\/origin\/(.+)/);
    if (match) return match[1];
  }

  for (const branch of ["main", "master"]) {
    const exists = await git.run(["-C", barePath, "rev-parse", "--verify", `refs/heads/${branch}`]);
    if (exists.ok) return branch;
  }

  return "main";
}

interface MergeContext {
  /** The ref merges were tested against, or "" when none resolved. */
  target: string;
  branches: Set<string>;
}

/**
 * Local branches already merged into the trunk.
 *
 * `--format` is what keeps this honest: plain `git branch --merged` prefixes
 * branches checked out elsewhere with `+ `, which silently defeats name
 * matching when every branch lives in its own worktree.
 */
async function resolveMergeContext(
  barePath: string,
  defaultBranch: string,
  git: GitRunner,
): Promise<MergeContext> {
  for (const candidate of [defaultBranch, "main", "master"]) {
    const merged = await git.run(
      ["-C", barePath, "branch", "--merged", candidate, "--format=%(refname:short)"],
    );
    if (merged.ok) {
      return {
        target: candidate,
        branches: new Set(
          merged.stdout.split("\n").map((line) => line.trim()).filter((line) => line.length > 0),
        ),
      };
    }
  }
  return { target: "", branches: new Set() };
}

/** One `git worktree list --porcelain` record, before enrichment. */
export interface WorktreeRecord {
  path: string;
  commit: string;
  branch: string;
  bare: boolean;
  prunable: boolean;
  locked: boolean;
}

export function parseWorktreeList(stdout: string): WorktreeRecord[] {
  const records: WorktreeRecord[] = [];
  for (const entry of stdout.split("\n\n")) {
    if (!entry.trim()) continue;
    const record: WorktreeRecord = {
      path: "",
      commit: "",
      branch: "",
      bare: false,
      prunable: false,
      locked: false,
    };
    for (const line of entry.split("\n")) {
      if (line.startsWith("worktree ")) {
        record.path = line.substring("worktree ".length);
      } else if (line.startsWith("HEAD ")) {
        record.commit = line.substring("HEAD ".length);
      } else if (line.startsWith("branch refs/heads/")) {
        record.branch = line.substring("branch refs/heads/".length);
      } else if (line === "bare") {
        record.bare = true;
      } else if (line === "prunable" || line.startsWith("prunable ")) {
        record.prunable = true;
      } else if (line === "locked" || line.startsWith("locked ")) {
        record.locked = true;
      }
    }
    records.push(record);
  }
  return records;
}

export interface WorktreeStatus {
  ahead: number;
  behind: number;
  staged_count: number;
  modified_count: number;
  untracked_count: number;
  has_conflicts: boolean;
}

/**
 * Parse `git status --porcelain=v1 --branch`.
 *
 * The XY classification: `x` counts as staged unless it is untracked, only
 * `y === "M"` counts as modified.
 */
export function parsePorcelainStatus(stdout: string): WorktreeStatus {
  const status: WorktreeStatus = {
    ahead: 0,
    behind: 0,
    staged_count: 0,
    modified_count: 0,
    untracked_count: 0,
    has_conflicts: false,
  };

  for (const line of stdout.split("\n")) {
    if (line.startsWith("## ")) {
      const tracking = line.match(/\[([^\]]+)\]\s*$/);
      if (tracking) {
        status.ahead = Number(tracking[1].match(/ahead (\d+)/)?.[1] ?? 0);
        status.behind = Number(tracking[1].match(/behind (\d+)/)?.[1] ?? 0);
      }
      continue;
    }
    if (line.length < 2) continue;

    const x = line[0];
    const y = line[1];
    if (x === "U" || y === "U" || (x === "A" && y === "A") || (x === "D" && y === "D")) {
      status.has_conflicts = true;
    }
    if (x !== " " && x !== "?") {
      status.staged_count += 1;
    }
    if (y === "M") {
      status.modified_count += 1;
    }
    if (x === "?" && y === "?") {
      status.untracked_count += 1;
    }
  }

  return status;
}

async function readStatus(worktreePath: string, git: GitRunner): Promise<WorktreeStatus | null> {
  const result = await git.run(["-C", worktreePath, "status", "--porcelain=v1", "--branch"]);
  if (!result.ok) return null;
  return parsePorcelainStatus(result.stdout);
}

interface CommitInfo {
  timestamp: number;
  message: string;
}

async function readLastCommit(
  cwd: string,
  git: GitRunner,
  rev?: string,
): Promise<CommitInfo | null> {
  const args = ["-C", cwd, "log", "-1", "--format=%ct|%s"];
  if (rev) args.push(rev);
  const result = await git.run(args);
  if (!result.ok || !result.stdout) return null;

  const parts = result.stdout.split("|");
  return {
    timestamp: Number.parseInt(parts[0], 10) || 0,
    message: parts.slice(1).join("|").substring(0, COMMIT_MESSAGE_LIMIT),
  };
}

interface GitResult {
  ok: boolean;
  stdout: string;
  stderr: string;
}

interface GitRunner {
  run(args: string[]): Promise<GitResult>;
  /** Non-empty once git could not be *started* at all. */
  spawnFailure(): string;
}

async function listDirectory(directory: string): Promise<string[]> {
  const names: string[] = [];
  try {
    for await (const entry of Deno.readDir(directory)) {
      names.push(entry.name);
    }
  } catch {
    return [];
  }
  return names;
}

type PathProbe = "present" | "absent" | "unreadable";

/**
 * Ask whether a directory is there, keeping "gone" and "could not look" apart.
 *
 * Only NotFound means a checkout is gone. Anything else — a Deno permission
 * scope that does not cover the path, an I/O error, a dead mount — is a failure
 * to observe, and calling that "missing" would put a live checkout on the prune
 * list. Worktrees under /tmp made this concrete: they are outside the CLI's
 * read scope by default, and 62 of them read as deleted until this told the
 * two cases apart.
 */
export async function probeDirectory(target: string): Promise<PathProbe> {
  try {
    return (await Deno.stat(target)).isDirectory ? "present" : "absent";
  } catch (error) {
    return error instanceof Deno.errors.NotFound ? "absent" : "unreadable";
  }
}

/**
 * Build a git runner that never has more than `limit` processes in flight.
 *
 * The budget is shared by every caller, so nesting worktree probes inside the
 * repository scan cannot multiply into limit-squared subprocesses.
 */
function createGitRunner(limit: number, timeoutMs: number): GitRunner {
  let available = limit;
  const waiting: Array<() => void> = [];
  let spawnFailure = "";

  return {
    spawnFailure: () => spawnFailure,

    async run(args: string[]): Promise<GitResult> {
      if (available > 0) {
        available -= 1;
      } else {
        await new Promise<void>((resolve) => waiting.push(resolve));
      }

      try {
        const command = new Deno.Command("git", {
          args,
          stdin: "null",
          stdout: "piped",
          stderr: "piped",
          signal: AbortSignal.timeout(timeoutMs),
          // Deno refuses to spawn under a scoped `--allow-run=git` while
          // LD_LIBRARY_PATH is set, because that variable can hijack the
          // binary. NixOS sets it, so without this every git call throws
          // NotCapable and the scan reports zero repositories on a machine
          // with forty. Blanking the one variable satisfies the check; git
          // still inherits HOME, PATH and GIT_*.
          env: { LD_LIBRARY_PATH: "" },
        });
        const output = await command.output();
        return {
          ok: output.success,
          stdout: new TextDecoder().decode(output.stdout).trim(),
          stderr: new TextDecoder().decode(output.stderr).trim(),
        };
      } catch (error) {
        // A non-zero git exit is ordinary (no origin, no such branch). Failing
        // to START git is not, and reporting that as "nothing found" is how
        // this code shipped broken once already — record it so the caller can
        // say so and exit non-zero.
        const reason = String(error).split("\n")[0];
        if (!spawnFailure) spawnFailure = reason;
        return { ok: false, stdout: "", stderr: reason };
      } finally {
        // Hand the slot straight to the next waiter; releasing it back into
        // `available` first would let a newly arriving caller jump the queue
        // and push the in-flight count over the limit.
        const next = waiting.shift();
        if (next) {
          next();
        } else {
          available += 1;
        }
      }
    },
  };
}
