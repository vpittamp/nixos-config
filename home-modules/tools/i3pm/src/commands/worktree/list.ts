/**
 * Worktree List Subcommand
 * Feature 079: Preview Pane User Experience - US6
 *
 * Lists all worktree projects with their metadata including branch,
 * path, parent_repo, and git_status.
 */

import { parseArgs } from "@std/cli/parse-args";
import { z } from "zod";

// Schema for worktree list item output (Feature 079: T045)
export const WorktreeListItemSchema = z.object({
  name: z.string().min(1),
  display_name: z.string().min(1),
  branch: z.string().min(1),
  path: z.string().min(1),
  parent_repo: z.string().min(1),
  git_status: z.object({
    is_clean: z.boolean(),
    ahead_count: z.number().int().nonnegative(),
    behind_count: z.number().int().nonnegative(),
    has_untracked: z.boolean(),
  }),
  created_at: z.string(),
  updated_at: z.string(),
  icon: z.string(),
});

export type WorktreeListItem = z.infer<typeof WorktreeListItemSchema>;

/**
 * Show list command help
 */
function showHelp(): void {
  console.log(`
i3pm worktree list - List all worktree projects

USAGE:
  i3pm worktree list [OPTIONS]

OPTIONS:
  --json                Output as JSON array (default)
  --table               Output as formatted table
  --filter-dirty        Show only worktrees with uncommitted changes
  --filter-ahead        Show only worktrees with unpushed commits
  -h, --help            Show this help message

EXAMPLES:
  # List all worktrees as JSON
  i3pm worktree list

  # List as table
  i3pm worktree list --table

  # List only dirty worktrees
  i3pm worktree list --filter-dirty

OUTPUT FIELDS (JSON):
  - name: Project identifier
  - display_name: Human-readable name
  - branch: Git branch name
  - path: Worktree directory path
  - parent_repo: Parent repository path
  - git_status: { is_clean, ahead_count, behind_count, has_untracked }
  - created_at: ISO 8601 timestamp
  - updated_at: ISO 8601 timestamp
  - icon: Emoji icon
`);
  Deno.exit(0);
}

/**
 * Load all project JSON files from project directory
 */
async function loadAllProjects(): Promise<unknown[]> {
  const projectDir = Deno.env.get("HOME") + "/.config/i3/projects";
  const projects: unknown[] = [];

  try {
    for await (const entry of Deno.readDir(projectDir)) {
      if (entry.isFile && entry.name.endsWith(".json")) {
        try {
          const filePath = `${projectDir}/${entry.name}`;
          const content = await Deno.readTextFile(filePath);
          const project = JSON.parse(content);
          projects.push(project);
        } catch {
          // Skip invalid JSON files
        }
      }
    }
  } catch {
    // Project directory doesn't exist
  }

  return projects;
}

/**
 * Filter projects to only worktrees
 */
function filterWorktrees(projects: unknown[]): WorktreeListItem[] {
  const worktrees: WorktreeListItem[] = [];

  for (const project of projects) {
    // Check if project has worktree field (T047)
    if (
      typeof project === "object" &&
      project !== null &&
      "worktree" in project &&
      typeof (project as Record<string, unknown>).worktree === "object"
    ) {
      const p = project as Record<string, unknown>;
      const wt = p.worktree as Record<string, unknown>;

      // Build worktree list item (T048, T049)
      const item: WorktreeListItem = {
        name: String(p.name || ""),
        display_name: String(p.display_name || ""),
        branch: String(wt.branch || ""),
        path: String(wt.worktree_path || ""),
        parent_repo: String(wt.repository_path || ""),
        git_status: {
          is_clean: Boolean(wt.is_clean),
          ahead_count: Number(wt.ahead_count || 0),
          behind_count: Number(wt.behind_count || 0),
          has_untracked: Boolean(wt.has_untracked),
        },
        created_at: String(p.created_at || new Date().toISOString()),
        updated_at: String(p.updated_at || new Date().toISOString()),
        icon: String(p.icon || "🌿"),
      };

      // Validate with Zod schema (T045)
      try {
        WorktreeListItemSchema.parse(item);
        worktrees.push(item);
      } catch {
        // Skip invalid worktrees
      }
    }
  }

  return worktrees;
}

/**
 * Format worktree list as table
 */
function formatTable(worktrees: WorktreeListItem[]): string {
  if (worktrees.length === 0) {
    return "No worktree projects found.";
  }

  const header =
    "NAME                              | BRANCH                            | STATUS       | AHEAD | BEHIND";
  const separator =
    "----------------------------------|-----------------------------------|--------------|-------|-------";

  const rows = worktrees.map((wt) => {
    const name = wt.name.substring(0, 32).padEnd(32);
    const branch = wt.branch.substring(0, 33).padEnd(33);
    const status = wt.git_status.is_clean
      ? (wt.git_status.has_untracked ? "untracked" : "clean").padEnd(12)
      : "dirty".padEnd(12);
    const ahead = String(wt.git_status.ahead_count).padStart(5);
    const behind = String(wt.git_status.behind_count).padStart(6);
    return `${name} | ${branch} | ${status} | ${ahead} | ${behind}`;
  });

  return [header, separator, ...rows].join("\n");
}

/**
 * Main list command handler (T046)
 */
export async function listWorktreesCommand(args: string[]): Promise<void> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json", "table", "filter-dirty", "filter-ahead"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    showHelp();
  }

  // Load and filter worktrees
  const allProjects = await loadAllProjects();
  let worktrees = filterWorktrees(allProjects);

  // Apply filters
  if (parsed["filter-dirty"]) {
    worktrees = worktrees.filter(
      (wt) => !wt.git_status.is_clean || wt.git_status.has_untracked
    );
  }

  if (parsed["filter-ahead"]) {
    worktrees = worktrees.filter((wt) => wt.git_status.ahead_count > 0);
  }

  // Output format (T049)
  if (parsed.table) {
    console.log(formatTable(worktrees));
  } else {
    // Default: JSON output
    console.log(JSON.stringify(worktrees, null, 2));
  }
}
