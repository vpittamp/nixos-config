import { assert, assertEquals } from "jsr:@std/assert@^1.0.0";
import { branchNameExists, generateFeatureBranchName } from "./branch-naming.ts";

async function runGit(args: string[], cwd?: string): Promise<void> {
  const output = await new Deno.Command("git", {
    args,
    cwd,
    stdout: "piped",
    stderr: "piped",
  }).output();

  if (!output.success) {
    const stderr = new TextDecoder().decode(output.stderr).trim();
    throw new Error(stderr || `git ${args.join(" ")} failed`);
  }
}

async function createBareRepoFixture(): Promise<string> {
  const root = await Deno.makeTempDir({ prefix: "i3pm-branch-naming-" });
  const seed = `${root}/seed`;
  const repoRoot = `${root}/repo`;

  await Deno.mkdir(seed, { recursive: true });
  await runGit(["init", "-b", "main"], seed);
  await runGit(["config", "user.email", "codex@example.com"], seed);
  await runGit(["config", "user.name", "Codex"], seed);
  await Deno.writeTextFile(`${seed}/README.md`, "# fixture\n");
  await runGit(["add", "README.md"], seed);
  await runGit(["commit", "-m", "initial"], seed);

  await Deno.mkdir(repoRoot, { recursive: true });
  await runGit(["clone", "--bare", seed, `${repoRoot}/.bare`]);
  await runGit(["-C", `${repoRoot}/.bare`, "worktree", "add", `${repoRoot}/main`, "main"]);
  await runGit(["-C", `${repoRoot}/.bare`, "branch", "041-existing", "main"]);
  await runGit([
    "-C",
    `${repoRoot}/.bare`,
    "worktree",
    "add",
    `${repoRoot}/042-existing`,
    "-b",
    "042-existing",
    "main",
  ]);

  await Deno.mkdir(`${repoRoot}/specs/007-existing`, { recursive: true });
  return repoRoot;
}

Deno.test("generateFeatureBranchName works against bare repo roots", async () => {
  const repoRoot = await createBareRepoFixture();
  const result = await generateFeatureBranchName("Improve launcher refresh handling", repoRoot);

  assertEquals(result.suffix, "improve-launcher-refresh-handling");
  assertEquals(result.branchName, "043-improve-launcher-refresh-handling");
  assertEquals(result.number, 43);
});

Deno.test("branchNameExists checks bare repo branches and worktrees", async () => {
  const repoRoot = await createBareRepoFixture();

  assert(await branchNameExists(repoRoot, "041-existing"));
  assert(await branchNameExists(repoRoot, "042-existing"));
  assertEquals(await branchNameExists(repoRoot, "099-missing"), false);
});
