// Feature 100: Repo List Command
// T032: Create `i3pm repo list` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { RepositoriesStorageSchema, type RepositoriesStorage } from "../../../models/repository.ts";

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
 * List all discovered repositories.
 */
export async function repoList(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["json"],
    string: ["account"],
    default: {
      json: false,
    },
  });

  const storage = await loadRepos();

  if (storage.repositories.length === 0) {
    console.error("No repositories discovered.");
    console.error("");
    console.error("Run discovery first:");
    console.error("  i3pm discover");
    return 0;
  }

  // Filter by account if specified
  let repos = storage.repositories;
  if (parsed.account) {
    repos = repos.filter(r => r.account === parsed.account);
    if (repos.length === 0) {
      console.error(`No repositories found for account: ${parsed.account}`);
      return 0;
    }
  }

  if (parsed.json) {
    console.log(JSON.stringify({
      repositories: repos,
      total: repos.length,
    }, null, 2));
    return 0;
  }

  console.log(`Repositories (${repos.length}):`);
  console.log("");

  // Group by account
  const byAccount = new Map<string, typeof repos>();
  for (const repo of repos) {
    const list = byAccount.get(repo.account) || [];
    list.push(repo);
    byAccount.set(repo.account, list);
  }

  for (const [account, accountRepos] of byAccount) {
    console.log(`${account}/`);
    for (const repo of accountRepos) {
      const wtCount = repo.worktrees?.length || 0;
      const wtInfo = wtCount > 0 ? ` (${wtCount} worktrees)` : "";
      console.log(`  ${repo.name}${wtInfo}`);
      console.log(`    Path: ${repo.path}`);
    }
    console.log("");
  }

  if (storage.last_discovery) {
    const lastDiscovery = new Date(storage.last_discovery);
    console.log(`Last discovery: ${lastDiscovery.toLocaleString()}`);
  }

  return 0;
}
