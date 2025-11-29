// Feature 100: Repo Get Command
// T033: Create `i3pm repo get <account>/<repo>` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { RepositoriesStorageSchema, type RepositoriesStorage, type BareRepository } from "../../../models/repository.ts";

const REPOS_FILE = `${Deno.env.get("HOME")}/.config/i3/repos.json`;

async function loadRepos(): Promise<RepositoriesStorage> {
  try {
    const content = await Deno.readTextFile(REPOS_FILE);
    return RepositoriesStorageSchema.parse(JSON.parse(content));
  } catch {
    return { version: 1, repositories: [] };
  }
}

/**
 * Get details for a specific repository.
 */
export async function repoGet(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["json"],
    default: {
      json: false,
    },
  });

  const positionalArgs = parsed._ as string[];

  if (positionalArgs.length < 1) {
    console.error("Usage: i3pm repo get <account/repo> [--json]");
    console.error("");
    console.error("Examples:");
    console.error("  i3pm repo get vpittamp/nixos");
    console.error("  i3pm repo get PittampalliOrg/api --json");
    return 1;
  }

  const qualifiedName = positionalArgs[0];
  const parts = qualifiedName.split("/");

  if (parts.length !== 2) {
    console.error("Error: Repository name must be in format: account/repo");
    console.error("Example: vpittamp/nixos");
    return 1;
  }

  const [account, repoName] = parts;

  const storage = await loadRepos();
  const repo = storage.repositories.find(
    r => r.account === account && r.name === repoName
  );

  if (!repo) {
    console.error(`Error: Repository not found: ${qualifiedName}`);
    console.error("");
    console.error("Run discovery to update repository list:");
    console.error("  i3pm discover");
    return 1;
  }

  if (parsed.json) {
    console.log(JSON.stringify(repo, null, 2));
    return 0;
  }

  console.log(`Repository: ${account}/${repoName}`);
  console.log("");
  console.log(`  Path: ${repo.path}`);
  console.log(`  Remote: ${repo.remote_url}`);
  console.log(`  Default branch: ${repo.default_branch}`);

  if (repo.worktrees && repo.worktrees.length > 0) {
    console.log("");
    console.log(`  Worktrees (${repo.worktrees.length}):`);
    for (const wt of repo.worktrees) {
      const mainMarker = wt.is_main ? " (main)" : "";
      const commitInfo = wt.commit ? ` @ ${wt.commit.substring(0, 7)}` : "";
      console.log(`    ${wt.branch}${mainMarker}${commitInfo}`);
      console.log(`      Path: ${wt.path}`);
    }
  }

  if (repo.discovered_at) {
    console.log("");
    console.log(`  Discovered: ${new Date(repo.discovered_at).toLocaleString()}`);
  }

  return 0;
}
