import { parseArgs } from "@std/cli/parse-args";
import { branchNameExists, generateFeatureBranchName } from "../../utils/branch-naming.ts";
import { detectRepoPath, repoQualifiedFromPath } from "./helpers.ts";

type SuggestNameResult = {
  repo: string;
  branch: string;
  qualified_name: string;
  number: number;
  suffix: string;
};

function showHelp(): void {
  console.log(`
i3pm worktree suggest-name - Suggest a meaningful branch name for a new worktree

USAGE:
  i3pm worktree suggest-name <task-summary> [--repo <account/repo>] [--json]

ARGUMENTS:
  task-summary      Short description of the work to be done

OPTIONS:
  -h, --help        Show this help message
  --repo            Explicit repository qualified name (account/repo)
  --json            Output the suggestion as JSON
`);
}

function formatResult(result: SuggestNameResult): void {
  console.log(`Suggested branch: ${result.branch}`);
  console.log(`  Repo: ${result.repo}`);
  console.log(`  Qualified: ${result.qualified_name}`);
  console.log(`  Number: ${String(result.number).padStart(3, "0")}`);
}

export async function worktreeSuggestName(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    string: ["repo"],
    alias: { h: "help" },
    stopEarly: false,
  });

  if (parsed.help) {
    showHelp();
    return 0;
  }

  const summary = (parsed._ as string[]).join(" ").trim();
  if (!summary) {
    console.error("Error: task summary is required");
    console.error(
      "Usage: i3pm worktree suggest-name <task-summary> [--repo <account/repo>] [--json]",
    );
    return 1;
  }

  const repoPath = await detectRepoPath(parsed.repo?.toString());
  if (!repoPath) {
    console.error("Error: Not in a managed bare repository structure");
    console.error("Please run from within a repository worktree or specify --repo");
    return 1;
  }

  const repo = parsed.repo?.toString() || repoQualifiedFromPath(repoPath);
  const generated = await generateFeatureBranchName(summary, repoPath);
  let branch = generated.branchName;
  let number = generated.number;

  for (let attempt = 0; attempt < 500; attempt += 1) {
    if (!(await branchNameExists(repoPath, branch))) {
      const result: SuggestNameResult = {
        repo,
        branch,
        qualified_name: `${repo}:${branch}`,
        number,
        suffix: generated.suffix,
      };

      if (parsed.json) {
        console.log(JSON.stringify(result, null, 2));
      } else {
        formatResult(result);
      }
      return 0;
    }
    number += 1;
    branch = `${String(number).padStart(3, "0")}-${generated.suffix}`;
  }

  console.error(`Error: Could not find an available branch name for '${summary}'`);
  return 1;
}
