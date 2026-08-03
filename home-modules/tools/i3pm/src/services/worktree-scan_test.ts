import { assert, assertEquals } from "jsr:@std/assert";
import {
  findBareRepositories,
  isIncomplete,
  parsePorcelainStatus,
  parseWorktreeList,
  probeDirectory,
  scanWorktrees,
  type WorktreeScanResult,
} from "./worktree-scan.ts";
import { selectWorktrees, worktreeTags } from "../commands/worktrees.ts";

Deno.test("parseWorktreeList reads branch, commit and bare/prunable/locked markers", () => {
  const records = parseWorktreeList(
    [
      "worktree /home/u/repos/acct/repo/.bare",
      "bare",
      "",
      "worktree /home/u/repos/acct/repo/main",
      "HEAD 1111111111111111111111111111111111111111",
      "branch refs/heads/main",
      "",
      "worktree /tmp/scratch",
      "HEAD 2222222222222222222222222222222222222222",
      "detached",
      "",
      "worktree /home/u/repos/acct/repo/gone",
      "HEAD 3333333333333333333333333333333333333333",
      "branch refs/heads/gone",
      "prunable gitdir file points to non-existent location",
      "",
      "worktree /media/stick/pinned",
      "HEAD 4444444444444444444444444444444444444444",
      "branch refs/heads/pinned",
      "locked on removable media",
      "",
    ].join("\n"),
  );

  assertEquals(records.length, 5);
  assertEquals(records[0].bare, true);
  assertEquals(records[1].branch, "main");
  assertEquals(records[1].commit, "1111111111111111111111111111111111111111");
  assertEquals(records[2].branch, "");
  assertEquals(records[3].prunable, true);
  assertEquals(records[4].locked, true);
});

Deno.test("parsePorcelainStatus classifies staged, modified and untracked entries", () => {
  const status = parsePorcelainStatus(
    [
      "## feature...origin/feature [ahead 3, behind 2]",
      "M  staged.ts",
      " M modified.ts",
      "MM staged-and-modified.ts",
      "?? untracked.ts",
    ].join("\n"),
  );

  assertEquals(status.ahead, 3);
  assertEquals(status.behind, 2);
  assertEquals(status.staged_count, 2);
  assertEquals(status.modified_count, 2);
  assertEquals(status.untracked_count, 1);
  assertEquals(status.has_conflicts, false);
});

Deno.test("parsePorcelainStatus never counts the branch header as a change", () => {
  assertEquals(parsePorcelainStatus("## main...origin/main\n"), {
    ahead: 0,
    behind: 0,
    staged_count: 0,
    modified_count: 0,
    untracked_count: 0,
    has_conflicts: false,
  });
});

Deno.test("parsePorcelainStatus reads a one-sided tracking summary", () => {
  assertEquals(parsePorcelainStatus("## main...origin/main [behind 5]").behind, 5);
  assertEquals(parsePorcelainStatus("## main...origin/main [ahead 5]").ahead, 5);
  assertEquals(parsePorcelainStatus("## HEAD (no branch)").ahead, 0);
});

Deno.test("parsePorcelainStatus flags unmerged entries as conflicts", () => {
  assertEquals(
    parsePorcelainStatus("## main\nUU both.ts\nAA added.ts\nDD deleted.ts").has_conflicts,
    true,
  );
});

Deno.test("selectWorktrees unions the filters and passes everything through with none", () => {
  const worktrees = [
    row({ path: "/a", is_merged: true }),
    row({ path: "/b", is_stale: true }),
    row({ path: "/c", missing: true }),
    row({ path: "/d" }),
  ];

  assertEquals(
    selectWorktrees(worktrees, { merged: false, stale: false, missing: false }).length,
    4,
  );
  assertEquals(
    selectWorktrees(worktrees, { merged: true, stale: true, missing: false }).map((w) => w.path),
    ["/a", "/b"],
  );
  assertEquals(
    selectWorktrees(worktrees, { merged: false, stale: false, missing: true }).map((w) => w.path),
    ["/c"],
  );
});

Deno.test("worktreeTags names every property worth acting on", () => {
  assertEquals(worktreeTags(row({ missing: true, locked: true })), ["missing", "locked"]);
  assertEquals(
    worktreeTags(row({ detached: true, is_merged: true, is_clean: false })),
    ["detached", "merged", "dirty"],
  );
  // A missing checkout has no working tree, so it is never reported dirty.
  assertEquals(worktreeTags(row({ missing: true, is_clean: false })), ["missing"]);
});

Deno.test("findBareRepositories globs <root>/<account>/<repo>/.bare", async () => {
  const root = await Deno.makeTempDir();
  try {
    await Deno.mkdir(`${root}/acct/repo/.bare`, { recursive: true });
    await Deno.mkdir(`${root}/acct/plain-checkout/.git`, { recursive: true });
    await Deno.writeTextFile(`${root}/loose-file`, "");

    const found = await findBareRepositories([root]);
    assertEquals(found.length, 1);
    assertEquals(found[0].account, "acct");
    assertEquals(found[0].repo, "repo");
    assertEquals(found[0].bare_path, `${root}/acct/repo/.bare`);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("scanWorktrees reports detached checkouts instead of dropping them", async () => {
  const root = await Deno.makeTempDir();
  try {
    const bare = await makeRepository(root, "acct", "repo");
    await git(bare, ["worktree", "add", "--detach", `${root}/acct/repo/loose`, "HEAD"]);

    const result = await scanWorktrees({ roots: [root] });
    assertEquals(result.skipped, []);
    assertEquals(isIncomplete(result), false);

    const detached = result.worktrees.filter((worktree) => worktree.detached);
    assertEquals(detached.length, 1);
    assertEquals(detached[0].branch, null);
    assertEquals(detached[0].path, `${root}/acct/repo/loose`);
    // Its commit is the trunk tip, so the trunk already contains it.
    assertEquals(detached[0].is_merged, true);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("scanWorktrees flags a registration whose checkout is gone", async () => {
  const root = await Deno.makeTempDir();
  try {
    const bare = await makeRepository(root, "acct", "repo");
    await git(bare, ["worktree", "add", "-b", "topic", `${root}/acct/repo/topic`]);
    await Deno.remove(`${root}/acct/repo/topic`, { recursive: true });

    const result = await scanWorktrees({ roots: [root] });
    const topic = find(result, "topic");
    assertEquals(topic.missing, true);
    assertEquals(topic.unreadable, false);
    // The checkout is gone but the bare repository still dates its tip commit.
    assert(topic.last_commit_timestamp > 0);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("probeDirectory keeps 'it is gone' and 'I could not look' apart", async () => {
  const root = await Deno.makeTempDir();
  try {
    assertEquals(await probeDirectory(root), "present");
    assertEquals(await probeDirectory(`${root}/nope`), "absent");

    await Deno.mkdir(`${root}/blocked/inner`, { recursive: true });
    await Deno.chmod(`${root}/blocked`, 0o000);
    try {
      // A path an ancestor hides is not a path that is gone. Conflating the
      // two is what put 62 live /tmp worktrees on the missing list, because
      // the CLI's read scope did not cover /tmp.
      const probe = await probeDirectory(`${root}/blocked/inner`);
      assertEquals(probe === "absent", false);
    } finally {
      await Deno.chmod(`${root}/blocked`, 0o755);
    }
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("scanWorktrees reports an unobservable checkout as unreadable, never as missing", async () => {
  const root = await Deno.makeTempDir();
  try {
    const bare = await makeRepository(root, "acct", "repo");
    await Deno.mkdir(`${root}/outside`, { recursive: true });
    await git(bare, ["worktree", "add", "-b", "hidden", `${root}/outside/hidden`]);
    await Deno.chmod(`${root}/outside`, 0o000);

    let result: WorktreeScanResult;
    try {
      result = await scanWorktrees({ roots: [root] });
    } finally {
      await Deno.chmod(`${root}/outside`, 0o755);
    }

    const hidden = find(result, "hidden");
    if (hidden.missing === false && hidden.unreadable === false) {
      // A process that can read through mode 000 (root) sees a healthy
      // checkout, which is a correct answer to a setup that did not hide it.
      return;
    }
    assertEquals(hidden.missing, false, "an unreadable checkout must not be called missing");
    assertEquals(hidden.unreadable, true);
    assertEquals(isIncomplete(result), true);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("scanWorktrees surfaces an unlistable repository as a skip, not as zero worktrees", async () => {
  const root = await Deno.makeTempDir();
  try {
    await makeRepository(root, "acct", "good");
    // A .bare directory that is not a git directory: `git worktree list` fails,
    // which must not read as "this repository has no worktrees".
    await Deno.mkdir(`${root}/acct/broken/.bare`, { recursive: true });

    const result = await scanWorktrees({ roots: [root] });
    assertEquals(result.repositories.map((repository) => repository.repo), ["broken", "good"]);
    assertEquals(result.skipped.length, 1);
    assertEquals(result.skipped[0].repo, "broken");
    assert(result.skipped[0].reason.length > 0, "a skip must carry git's reason");
    assertEquals(isIncomplete(result), true);
    // The healthy repository is still fully reported.
    assert(result.worktrees.every((worktree) => worktree.repo === "good"));
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("scanWorktrees separates merged branches from the trunk and from unmerged work", async () => {
  const root = await Deno.makeTempDir();
  try {
    const bare = await makeRepository(root, "acct", "repo");
    await git(bare, ["worktree", "add", "-b", "merged-topic", `${root}/acct/repo/merged-topic`]);
    await git(bare, ["worktree", "add", "-b", "open-topic", `${root}/acct/repo/open-topic`]);
    await Deno.writeTextFile(`${root}/acct/repo/open-topic/new.txt`, "work\n");
    await git(`${root}/acct/repo/open-topic`, ["add", "new.txt"]);
    await git(`${root}/acct/repo/open-topic`, ["commit", "-m", "work"]);

    const result = await scanWorktrees({ roots: [root] });
    assertEquals(find(result, "main").is_trunk, true);
    assertEquals(find(result, "main").is_merged, false);
    assertEquals(find(result, "merged-topic").is_merged, true);
    assertEquals(find(result, "open-topic").is_merged, false);
    assertEquals(find(result, "open-topic").is_clean, true);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("scanWorktrees counts untracked files as dirty", async () => {
  const root = await Deno.makeTempDir();
  try {
    await makeRepository(root, "acct", "repo");
    await Deno.writeTextFile(`${root}/acct/repo/main/scratch.txt`, "unsaved\n");

    const main = find(await scanWorktrees({ roots: [root] }), "main");
    assertEquals(main.untracked_count, 1);
    assertEquals(main.is_clean, false);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

function find(result: WorktreeScanResult, branch: string) {
  const worktree = result.worktrees.find((candidate) => candidate.branch === branch);
  assert(worktree, `expected a worktree on branch ${branch}`);
  return worktree;
}

/** Build a `<root>/<account>/<repo>/.bare` layout with one `main` worktree. */
async function makeRepository(root: string, account: string, repo: string): Promise<string> {
  const bare = `${root}/${account}/${repo}/.bare`;
  await Deno.mkdir(bare, { recursive: true });
  await git(root, ["init", "--bare", "--initial-branch=main", bare]);

  const main = `${root}/${account}/${repo}/main`;
  await git(bare, ["worktree", "add", "-b", "main", main]);
  await Deno.writeTextFile(`${main}/README.md`, "seed\n");
  await git(main, ["add", "README.md"]);
  await git(main, ["commit", "-m", "seed"]);
  return bare;
}

async function git(cwd: string, args: string[]): Promise<void> {
  const output = await new Deno.Command("git", {
    args: ["-C", cwd, ...args],
    stdin: "null",
    stdout: "null",
    stderr: "piped",
    env: {
      // Same NixOS constraint as the scanner, plus a fixed identity so the
      // test does not depend on the developer's git config.
      LD_LIBRARY_PATH: "",
      GIT_AUTHOR_NAME: "i3pm test",
      GIT_AUTHOR_EMAIL: "test@example.invalid",
      GIT_COMMITTER_NAME: "i3pm test",
      GIT_COMMITTER_EMAIL: "test@example.invalid",
      GIT_CONFIG_GLOBAL: "/dev/null",
      GIT_CONFIG_SYSTEM: "/dev/null",
    },
  }).output();
  if (!output.success) {
    throw new Error(`git ${args.join(" ")} failed: ${new TextDecoder().decode(output.stderr)}`);
  }
}

type Row = Parameters<typeof worktreeTags>[0];

function row(overrides: Partial<Row>): Row {
  return {
    account: "acct",
    repo: "repo",
    repo_path: "/repos/acct/repo",
    path: "/repos/acct/repo/main",
    commit: "1111111111111111111111111111111111111111",
    branch: "main",
    detached: false,
    is_trunk: false,
    missing: false,
    locked: false,
    unreadable: false,
    is_clean: true,
    ahead: 0,
    behind: 0,
    staged_count: 0,
    modified_count: 0,
    untracked_count: 0,
    has_conflicts: false,
    last_commit_timestamp: 0,
    last_commit_message: "",
    age_days: null,
    is_stale: false,
    is_merged: false,
    ...overrides,
  };
}
