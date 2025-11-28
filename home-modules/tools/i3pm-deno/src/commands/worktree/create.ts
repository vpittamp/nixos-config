/**
 * Worktree Create Command
 * Feature 077: Git Worktree Project Management
 * Feature 097: Git-Centric Project and Worktree Management
 *
 * Creates a new git worktree and registers it as an i3pm project.
 * Updated for Feature 097 to use bare_repo_path and parent_project.
 */

import { parseArgs } from "@std/cli/parse-args";
import { join, basename } from "@std/path";
import { exists } from "@std/fs/exists";
import { GitWorktreeService } from "../../services/git-worktree.ts";
import { WorktreeMetadataService } from "../../services/worktree-metadata.ts";
import { ProjectManagerService } from "../../services/project-manager.ts";
import {
  getRepositoryRoot,
  getBareRepositoryPath,
  getCurrentBranch,
  getCurrentCommitHash,
  parseGitStatus,
  parseBranchTracking,
  execGit,
} from "../../utils/git.ts";
import type { Project, SourceType, GitMetadata } from "../../models/discovery.ts";
import { bold, green, yellow, red, dim } from "../../ui/ansi.ts";

/**
 * Show help for worktree create command
 */
function showHelp(): void {
  console.log(`
i3pm worktree create - Create a new worktree project

USAGE:
  i3pm worktree create <branch-name> [OPTIONS]

ARGUMENTS:
  <branch-name>         Branch name to checkout or create

OPTIONS:
  --name <name>         Custom worktree directory name (default: branch-name)
  --base-path <path>    Base directory for worktrees (default: sibling to main repo)
  --checkout            Checkout existing branch instead of creating new
  --display-name <name> Custom display name for project
  --icon <emoji>        Icon for project (default: 🌿)
  -p, --parent <name>   Parent Repository Project name (auto-detected from bare_repo_path)
  -h, --help            Show this help message

EXAMPLES:
  # Create new branch and worktree (auto-detects parent from current repo)
  i3pm worktree create feature-auth-refactor

  # Checkout existing remote branch
  i3pm worktree create hotfix-payment --checkout

  # Custom worktree directory and display name
  i3pm worktree create feature-ui --name ui-work --display-name "UI Redesign" --icon 🎨

  # Specify parent project explicitly
  i3pm worktree create my-feature --parent nixos-main

NOTES:
  - Worktrees are created as siblings to the main repository by default
  - If main repo is at /home/user/nixos, worktree will be at /home/user/nixos-feature-auth-refactor
  - Project is automatically registered with i3pm and can be switched to immediately
  - Scoped apps (terminal, editor, file manager) will open in the worktree directory

FEATURE 097 (Git-Centric Architecture):
  - Worktree projects are linked to their parent Repository Project via parent_project field
  - All worktrees of the same repo share the same bare_repo_path (GIT_COMMON_DIR)
  - A Repository Project must exist before creating worktrees (use: i3pm project discover)
`);
  Deno.exit(0);
}

// ============================================================================
// Project Storage (Feature 097)
// ============================================================================

const PROJECTS_DIR = join(Deno.env.get("HOME") || "~", ".config/i3/projects");

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
  await Deno.mkdir(PROJECTS_DIR, { recursive: true });
  const filePath = join(PROJECTS_DIR, `${project.name}.json`);
  await Deno.writeTextFile(filePath, JSON.stringify(project, null, 2));
}

/**
 * Feature 097 T026/T027: Find the parent Repository Project for a bare_repo_path
 */
async function findParentProject(
  bareRepoPath: string,
  projects: Project[]
): Promise<Project | null> {
  return projects.find(
    (p) => p.source_type === "repository" && p.bare_repo_path === bareRepoPath
  ) || null;
}

/**
 * Extract git metadata for the new worktree (Feature 097)
 */
async function extractGitMetadata(directory: string): Promise<GitMetadata | null> {
  try {
    const currentBranch = await getCurrentBranch(directory);
    const commitHash = await getCurrentCommitHash(directory, true);

    const statusResult = await execGit(["status", "--porcelain"], directory, false);
    const status = parseGitStatus(statusResult.stdout);

    const trackingResult = await execGit(
      ["status", "--porcelain=v2", "--branch"],
      directory,
      false
    );
    const tracking = parseBranchTracking(trackingResult.stdout);

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

/**
 * Generate a unique project name if there's a conflict
 */
async function resolveProjectNameConflict(
  baseName: string,
  projectManager: ProjectManagerService,
): Promise<string> {
  let candidateName = baseName;
  let counter = 1;

  while (true) {
    const existing = await projectManager.getProject(candidateName);
    if (!existing) {
      return candidateName;
    }

    // Name conflict - try appending counter
    counter++;
    candidateName = `${baseName}-${counter}`;

    if (counter > 100) {
      throw new Error(
        `Unable to resolve project name conflict for "${baseName}" after 100 attempts`,
      );
    }
  }
}

/**
 * Execute worktree create command
 *
 * Feature 097: Updated to use git-centric project model with:
 * - bare_repo_path as canonical identifier
 * - parent_project linking to Repository Project
 * - source_type = "worktree"
 */
export async function createWorktreeCommand(args: string[]): Promise<void> {
  const parsed = parseArgs(args, {
    string: ["name", "base-path", "display-name", "icon", "parent"],
    boolean: ["checkout", "help"],
    alias: {
      h: "help",
      p: "parent",
    },
  });

  if (parsed.help) {
    showHelp();
  }

  // Validate branch name argument
  if (parsed._.length === 0) {
    console.error(red("Error: Branch name is required"));
    console.error("");
    console.error("Usage: i3pm worktree create <branch-name> [OPTIONS]");
    console.error("Run 'i3pm worktree create --help' for more information");
    Deno.exit(1);
  }

  const branchName = String(parsed._[0]);
  const worktreeName = parsed.name || branchName;
  const displayName = parsed["display-name"] || branchName;
  const icon = parsed.icon || "🌿";
  const shouldCheckout = parsed.checkout || false;
  const customBasePath = parsed["base-path"];
  const parentProjectName = parsed.parent as string | undefined;

  // Initialize services
  const gitWorktreeService = new GitWorktreeService();
  const projectManager = new ProjectManagerService();

  // Track worktree path for cleanup on error
  let worktreePath: string | null = null;
  let worktreeCreated = false;

  try {
    // Step 1: Validate we're in a git repository
    console.log(dim("Validating git repository..."));
    const cwd = Deno.cwd();
    await gitWorktreeService.validateRepository(cwd);

    // Get repository root
    const repoRoot = await getRepositoryRoot(cwd);
    console.log(dim(`Repository: ${repoRoot}`));

    // Feature 097 T027: Get bare_repo_path for this repository
    const bareRepoPath = await getBareRepositoryPath(repoRoot);
    console.log(dim(`Bare repo path: ${bareRepoPath}`));

    // Feature 097 T026: Find parent Repository Project
    const existingProjects = await loadExistingProjects();
    let parentProject: Project | null = null;

    if (parentProjectName) {
      // User specified parent project explicitly
      parentProject = existingProjects.find((p) => p.name === parentProjectName) || null;
      if (!parentProject) {
        console.error(red(`Error: Parent project "${parentProjectName}" not found`));
        console.error("");
        console.error("Create the parent Repository Project first with:");
        console.error(`  i3pm project discover --path ${repoRoot}`);
        Deno.exit(1);
      }
      if (parentProject.source_type !== "repository") {
        console.error(red(`Error: Parent project "${parentProjectName}" is not a Repository Project`));
        console.error("");
        console.error(`It is a ${parentProject.source_type} project. Worktrees can only be created from repository projects.`);
        Deno.exit(1);
      }
    } else {
      // Auto-detect parent from bare_repo_path
      parentProject = await findParentProject(bareRepoPath, existingProjects);
      if (!parentProject) {
        console.error(red("Error: No Repository Project found for this repository"));
        console.error("");
        console.error("Create a Repository Project first with:");
        console.error(`  i3pm project discover --path ${repoRoot}`);
        console.error("");
        console.error("Or specify a parent project with --parent <name>");
        Deno.exit(1);
      }
    }

    console.log(dim(`Parent project: ${parentProject.name}`));

    // Step 2: Check if branch exists (Feature 097 T028)
    const branchExists = await gitWorktreeService.checkBranchExists(branchName, repoRoot);

    let createNewBranch = !shouldCheckout;
    if (shouldCheckout && !branchExists) {
      console.error(
        red(`Error: Branch "${branchName}" does not exist and --checkout flag was specified`),
      );
      console.error("");
      console.error("Options:");
      console.error("  1. Remove --checkout flag to create a new branch");
      console.error("  2. Use an existing branch name");
      console.error("");
      console.error("Available branches:");
      // List available branches
      try {
        const branchResult = await execGit(["branch", "-a", "--format=%(refname:short)"], repoRoot, false);
        if (branchResult.success && branchResult.stdout) {
          const branches = branchResult.stdout.split("\n").filter(Boolean).slice(0, 10);
          branches.forEach((b) => console.error(`    ${b}`));
          if (branches.length === 10) {
            console.error("    ... (more branches available)");
          }
        }
      } catch {
        // Ignore branch listing errors
      }
      Deno.exit(1);
    }

    if (!shouldCheckout && branchExists) {
      // Branch exists but user didn't specify --checkout
      // Auto-detect: checkout existing branch
      console.log(yellow(`Branch "${branchName}" already exists, checking out existing branch`));
      createNewBranch = false;
    }

    // Step 3: Resolve worktree path
    const basePath = customBasePath ||
      await gitWorktreeService.resolveWorktreeBasePath(repoRoot);
    const repoName = basename(repoRoot);
    worktreePath = join(basePath, `${repoName}-${worktreeName}`);

    console.log(dim(`Worktree path: ${worktreePath}`));

    // Check if worktree path already exists
    if (await exists(worktreePath)) {
      console.error(red(`Error: Directory already exists: ${worktreePath}`));
      console.error("");
      console.error("Options:");
      console.error("  1. Use --name flag to specify a different worktree directory name");
      console.error("  2. Remove the existing directory");
      Deno.exit(1);
    }

    // Step 4: Create git worktree (Feature 097 T029: with error handling)
    console.log("");
    console.log(
      createNewBranch
        ? `Creating worktree with new branch "${branchName}"...`
        : `Creating worktree from existing branch "${branchName}"...`,
    );

    try {
      await gitWorktreeService.createWorktree(
        branchName,
        worktreePath,
        repoRoot,
        createNewBranch,
      );
      worktreeCreated = true;
    } catch (gitError) {
      // Feature 097 T029: Clean error message for git worktree failures
      console.error(red("✗ Failed to create git worktree"));
      if (gitError instanceof Error) {
        console.error(red(`  ${gitError.message}`));
      }
      Deno.exit(1);
    }

    console.log(green("✓ Git worktree created successfully"));

    // Step 5: Extract git metadata for the new worktree
    console.log(dim("Extracting git metadata..."));
    const gitMetadata = await extractGitMetadata(worktreePath);

    // Step 6: Resolve project name (handle conflicts)
    const existingNames = new Set(existingProjects.map((p) => p.name));
    let projectName = worktreeName.toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "");

    // Ensure uniqueness
    let counter = 1;
    let baseName = projectName;
    while (existingNames.has(projectName)) {
      counter++;
      projectName = `${baseName}-${counter}`;
    }

    if (projectName !== worktreeName.toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "")) {
      console.log(yellow(`Project name conflict resolved: using "${projectName}"`));
    }

    // Step 7: Create Feature 097 Worktree Project
    console.log(dim("Registering i3pm project..."));

    const now = new Date().toISOString();
    const worktreeProject: Project = {
      name: projectName,
      display_name: displayName,
      icon,
      directory: worktreePath,
      scope: "scoped",
      remote: null,

      // Feature 097: Git-centric fields
      source_type: "worktree" as SourceType,
      status: "active",
      bare_repo_path: bareRepoPath,           // T027: Copy from parent
      parent_project: parentProject.name,      // T026: Set parent reference
      git_metadata: gitMetadata,
      scoped_classes: ["Ghostty", "code", "yazi", "lazygit"],
      created_at: now,
      updated_at: now,
    };

    // Save project directly to filesystem (bypass daemon for Feature 097)
    await saveProject(worktreeProject);

    console.log(green("✓ i3pm project created successfully"));
    console.log("");
    console.log(bold("Worktree project created:"));
    console.log(`  ${icon} ${displayName} (${projectName})`);
    console.log(`  ${dim("Branch:")} ${gitMetadata?.current_branch || branchName}`);
    console.log(`  ${dim("Path:")} ${worktreePath}`);
    console.log(`  ${dim("Parent:")} ${parentProject.name}`);
    console.log(`  ${dim("Status:")} ${gitMetadata?.is_clean ? "clean" : "dirty"}`);
    console.log("");
    console.log("Next steps:");
    console.log(`  ${bold("Switch to project:")} i3pm project switch ${projectName}`);
    console.log(
      `  ${bold("Launch apps:")} Apps will automatically open in ${worktreePath}`,
    );
  } catch (error) {
    // Feature 097 T029: Clean up partial state on error
    if (worktreeCreated && worktreePath) {
      console.log(dim("Cleaning up partial worktree..."));
      try {
        await execGit(["worktree", "remove", "--force", worktreePath], Deno.cwd(), false);
      } catch {
        console.log(yellow(`Warning: Could not clean up worktree at ${worktreePath}`));
        console.log(yellow("You may need to manually run: git worktree remove --force " + worktreePath));
      }
    }

    console.error("");
    console.error(red("Error creating worktree:"));
    console.error(red(error instanceof Error ? error.message : String(error)));

    const anyError = error as { stderr?: string };
    if (anyError.stderr) {
      console.error("");
      console.error(dim("Git error details:"));
      console.error(dim(anyError.stderr));
    }

    Deno.exit(1);
  }
}
