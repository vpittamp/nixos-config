/**
 * Feature 097: i3pm project discover command
 *
 * Discover and register git repositories as projects using git-centric architecture.
 * Uses bare_repo_path (GIT_COMMON_DIR) as the canonical identifier.
 *
 * User Story 1: Discover and Register Repository
 */

import { parseArgs } from "@std/cli/parse-args";
import { join, basename, resolve } from "@std/path";
import { exists } from "@std/fs/exists";
import { bold, cyan, dim, gray, green, yellow, red } from "../../ui/ansi.ts";

import {
  getBareRepositoryPath,
  determineSourceType,
  generateUniqueName,
  getCurrentBranch,
  getCurrentCommitHash,
  parseGitStatus,
  parseBranchTracking,
  execGit,
  isGitRepository,
} from "../../utils/git.ts";

import type { Project, SourceType, GitMetadata } from "../../models/discovery.ts";

// ============================================================================
// Types
// ============================================================================

interface DiscoverOptions {
  path?: string;
  name?: string;
  icon?: string;
  standalone?: boolean;
  dryRun?: boolean;
  json?: boolean;
  verbose?: boolean;
}

interface DiscoverResult {
  success: boolean;
  action: "created" | "updated" | "skipped";
  project?: Project;
  message: string;
}

// ============================================================================
// Project Storage
// ============================================================================

const PROJECTS_DIR = join(Deno.env.get("HOME") || "~", ".config/i3/projects");

async function ensureProjectsDir(): Promise<void> {
  await Deno.mkdir(PROJECTS_DIR, { recursive: true });
}

async function loadExistingProjects(): Promise<Project[]> {
  const projects: Project[] = [];

  try {
    for await (const entry of Deno.readDir(PROJECTS_DIR)) {
      if (entry.isFile && entry.name.endsWith(".json")) {
        try {
          const content = await Deno.readTextFile(join(PROJECTS_DIR, entry.name));
          const project = JSON.parse(content) as Project;
          projects.push(project);
        } catch {
          // Skip invalid JSON files
        }
      }
    }
  } catch {
    // Directory doesn't exist yet
  }

  return projects;
}

async function saveProject(project: Project): Promise<void> {
  await ensureProjectsDir();
  const filePath = join(PROJECTS_DIR, `${project.name}.json`);
  await Deno.writeTextFile(filePath, JSON.stringify(project, null, 2));
}

// ============================================================================
// Git Metadata Extraction
// ============================================================================

async function extractGitMetadata(directory: string): Promise<GitMetadata | null> {
  try {
    // Get current branch
    const currentBranch = await getCurrentBranch(directory);

    // Get commit hash (7 chars)
    const commitHash = await getCurrentCommitHash(directory, true);

    // Get status
    const statusResult = await execGit(["status", "--porcelain"], directory, false);
    const status = parseGitStatus(statusResult.stdout);

    // Get tracking info
    const trackingResult = await execGit(
      ["status", "--porcelain=v2", "--branch"],
      directory,
      false
    );
    const tracking = parseBranchTracking(trackingResult.stdout);

    // Get remote URL
    let remoteUrl: string | null = null;
    try {
      const remoteResult = await execGit(["remote", "get-url", "origin"], directory, false);
      if (remoteResult.success) {
        remoteUrl = remoteResult.stdout || null;
      }
    } catch {
      // No remote configured
    }

    return {
      current_branch: currentBranch,
      commit_hash: commitHash.slice(0, 7).padEnd(7, "0"),
      is_clean: status.isClean,
      has_untracked: status.hasUntracked,
      ahead_count: tracking.aheadCount,
      behind_count: tracking.behindCount,
      remote_url: remoteUrl,
      last_modified: null,
      last_refreshed: new Date().toISOString(),
    };
  } catch {
    return null;
  }
}

// ============================================================================
// Project Name Generation
// ============================================================================

function inferProjectName(directory: string): string {
  // Use directory basename, convert to lowercase, replace spaces with hyphens
  const base = basename(directory);
  return base.toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "");
}

function inferIcon(sourceType: SourceType): string {
  switch (sourceType) {
    case "repository":
      return "🔧";
    case "worktree":
      return "🌿";
    case "standalone":
      return "📁";
  }
}

// ============================================================================
// Main Discover Logic
// ============================================================================

async function discoverProject(options: DiscoverOptions): Promise<DiscoverResult> {
  // T016: Default to current directory
  const directory = resolve(options.path || Deno.cwd());

  // Verify directory exists
  if (!(await exists(directory))) {
    return {
      success: false,
      action: "skipped",
      message: `Directory does not exist: ${directory}`,
    };
  }

  // Load existing projects
  const existingProjects = await loadExistingProjects();
  const existingNames = new Set(existingProjects.map((p) => p.name));

  // T018: Get bare_repo_path and handle non-git directories
  let bareRepoPath: string | null = null;
  let sourceType: SourceType = "standalone";

  if (await isGitRepository(directory)) {
    try {
      bareRepoPath = await getBareRepositoryPath(directory);
      // T019: Determine source type based on existing projects
      sourceType = await determineSourceType(directory, existingProjects);
    } catch {
      // Failed to get git info, treat as standalone
      bareRepoPath = null;
      sourceType = "standalone";
    }
  } else if (!options.standalone) {
    // T022: Non-git directories require --standalone flag
    return {
      success: false,
      action: "skipped",
      message: `Not a git repository: ${directory}. Use --standalone flag to create a standalone project.`,
    };
  }

  // Check if we already have a project at this directory
  const existingAtPath = existingProjects.find((p) => p.directory === directory);
  if (existingAtPath) {
    return {
      success: false,
      action: "skipped",
      project: existingAtPath,
      message: `Project already exists for this directory: ${existingAtPath.name}`,
    };
  }

  // T23: Generate unique name
  const baseName = options.name || inferProjectName(directory);
  const uniqueName = generateUniqueName(baseName, existingNames);

  // Get display name
  const displayName = options.name
    ? options.name.charAt(0).toUpperCase() + options.name.slice(1).replace(/-/g, " ")
    : basename(directory);

  // Get icon
  const icon = options.icon || inferIcon(sourceType);

  // Extract git metadata
  const gitMetadata = sourceType !== "standalone"
    ? await extractGitMetadata(directory)
    : null;

  // Find parent project for worktrees
  let parentProject: string | null = null;
  if (sourceType === "worktree" && bareRepoPath) {
    const parent = existingProjects.find(
      (p) => p.source_type === "repository" && p.bare_repo_path === bareRepoPath
    );
    if (parent) {
      parentProject = parent.name;
    }
  }

  // T020/T021/T022: Create project based on type
  const now = new Date().toISOString();
  const project: Project = {
    name: uniqueName,
    display_name: displayName,
    directory,
    icon,
    scope: "scoped",
    remote: null,
    source_type: sourceType,
    status: "active",
    bare_repo_path: bareRepoPath,
    parent_project: parentProject,
    git_metadata: gitMetadata,
    scoped_classes: ["Ghostty", "code", "yazi", "lazygit"],
    created_at: now,
    updated_at: now,
  };

  // Dry run - don't save
  if (options.dryRun) {
    return {
      success: true,
      action: "skipped",
      project,
      message: `Would create ${sourceType} project: ${uniqueName}`,
    };
  }

  // Save project
  await saveProject(project);

  return {
    success: true,
    action: "created",
    project,
    message: `Created ${sourceType} project: ${uniqueName}`,
  };
}

// ============================================================================
// Command Handler
// ============================================================================

export async function discoverCommand(args: string[]): Promise<void> {
  const parsed = parseArgs(args, {
    string: ["path", "name", "icon"],
    boolean: ["standalone", "dry-run", "json", "verbose", "help"],
    alias: {
      p: "path",
      n: "name",
      i: "icon",
      s: "standalone",
      h: "help",
    },
  });

  if (parsed.help) {
    showHelp();
    return;
  }

  const options: DiscoverOptions = {
    path: parsed.path,
    name: parsed.name,
    icon: parsed.icon,
    standalone: parsed.standalone,
    dryRun: parsed["dry-run"],
    json: parsed.json,
    verbose: parsed.verbose,
  };

  try {
    const result = await discoverProject(options);

    if (parsed.json) {
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    // T024: Output discovery result
    if (result.success) {
      if (result.action === "created") {
        console.log(green("✓") + ` ${result.message}`);
      } else {
        console.log(yellow("⚠") + ` ${result.message}`);
      }

      if (result.project && parsed.verbose) {
        console.log("");
        console.log(`  ${gray("Directory:")} ${result.project.directory}`);
        console.log(`  ${gray("Source Type:")} ${result.project.source_type}`);
        if (result.project.bare_repo_path) {
          console.log(`  ${gray("Bare Repo:")} ${result.project.bare_repo_path}`);
        }
        if (result.project.parent_project) {
          console.log(`  ${gray("Parent:")} ${result.project.parent_project}`);
        }
        if (result.project.git_metadata) {
          const meta = result.project.git_metadata;
          console.log(`  ${gray("Branch:")} ${meta.current_branch}`);
          console.log(`  ${gray("Commit:")} ${meta.commit_hash}`);
          console.log(`  ${gray("Status:")} ${meta.is_clean ? "clean" : "dirty"}`);
        }
      }
    } else {
      console.error(red("✗") + ` ${result.message}`);
      Deno.exit(1);
    }
  } catch (err) {
    if (parsed.json) {
      console.log(JSON.stringify({ success: false, error: String(err) }, null, 2));
    } else {
      console.error(red("✗") + ` Error: ${err instanceof Error ? err.message : String(err)}`);
    }
    Deno.exit(1);
  }
}

function showHelp(): void {
  console.log(`
${bold("i3pm project discover")} - Discover and register git repositories

${bold("USAGE:")}
  i3pm project discover [OPTIONS]

${bold("DESCRIPTION:")}
  Discovers the git repository at the specified path (or current directory)
  and registers it as an i3pm project with the correct source_type:

  • ${cyan("repository")}: Primary entry for a bare repo (ONE per repo)
  • ${cyan("worktree")}: Linked to an existing Repository Project
  • ${cyan("standalone")}: Non-git directory (requires --standalone)

${bold("OPTIONS:")}
  -p, --path <path>       Path to discover (default: current directory)
  -n, --name <name>       Custom project name (default: directory basename)
  -i, --icon <emoji>      Custom icon (default: based on type)
  -s, --standalone        Create standalone project for non-git directory
      --dry-run           Preview without creating project
      --json              Output result as JSON
      --verbose           Show detailed information
  -h, --help              Show this help message

${bold("EXAMPLES:")}
  ${dim("# Discover current directory")}
  i3pm project discover

  ${dim("# Discover specific path")}
  i3pm project discover --path /etc/nixos

  ${dim("# With custom name and icon")}
  i3pm project discover --path ~/my-app --name "My App" --icon "🚀"

  ${dim("# Preview without creating")}
  i3pm project discover --path ~/projects/foo --dry-run

${bold("BEHAVIOR:")}
  • If bare_repo_path already has a Repository Project → creates Worktree
  • If no Repository Project exists → creates Repository
  • Non-git directories require --standalone flag
  • Existing projects at same directory are skipped
`);
}
