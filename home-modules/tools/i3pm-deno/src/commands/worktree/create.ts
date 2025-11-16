/**
 * Worktree Create Command
 * Feature 077: Git Worktree Project Management
 *
 * Creates a new git worktree and registers it as an i3pm project.
 */

import { parseArgs } from "@std/cli/parse-args";
import { join, basename } from "@std/path";
import { GitWorktreeService } from "../../services/git-worktree.ts";
import { WorktreeMetadataService } from "../../services/worktree-metadata.ts";
import { ProjectManagerService } from "../../services/project-manager.ts";
import { getRepositoryRoot } from "../../utils/git.ts";
import type { WorktreeProject } from "../../models/worktree.ts";
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
  -h, --help            Show this help message

EXAMPLES:
  # Create new branch and worktree
  i3pm worktree create feature-auth-refactor

  # Checkout existing remote branch
  i3pm worktree create hotfix-payment --checkout

  # Custom worktree directory and display name
  i3pm worktree create feature-ui --name ui-work --display-name "UI Redesign" --icon 🎨

NOTES:
  - Worktrees are created as siblings to the main repository by default
  - If main repo is at /home/user/nixos, worktree will be at /home/user/nixos-feature-auth-refactor
  - Project is automatically registered with i3pm and can be switched to immediately
  - Scoped apps (terminal, editor, file manager) will open in the worktree directory
`);
  Deno.exit(0);
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
 */
export async function createWorktreeCommand(args: string[]): Promise<void> {
  const parsed = parseArgs(args, {
    string: ["name", "base-path", "display-name", "icon"],
    boolean: ["checkout", "help"],
    alias: {
      h: "help",
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

  // Initialize services
  const gitWorktreeService = new GitWorktreeService();
  const metadataService = new WorktreeMetadataService();
  const projectManager = new ProjectManagerService();

  try {
    // Step 1: Validate we're in a git repository
    console.log(dim("Validating git repository..."));
    const cwd = Deno.cwd();
    await gitWorktreeService.validateRepository(cwd);

    // Get repository root
    const repoRoot = await getRepositoryRoot(cwd);
    console.log(dim(`Repository: ${repoRoot}`));

    // Step 2: Check if branch exists
    const branchExists = await gitWorktreeService.checkBranchExists(branchName, repoRoot);

    let createNewBranch = !shouldCheckout;
    if (shouldCheckout && !branchExists) {
      console.error(
        red(`Error: Branch "${branchName}" does not exist and --checkout flag was specified`),
      );
      console.error("");
      console.error("Options:");
      console.error("  1. Remove --checkout flag to create a new branch");
      console.error(`  2. Use an existing branch name`);
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
    const worktreePath = join(basePath, `${repoName}-${worktreeName}`);

    console.log(dim(`Worktree path: ${worktreePath}`));

    // Check if worktree path already exists
    try {
      const stat = await Deno.stat(worktreePath);
      if (stat.isDirectory) {
        console.error(red(`Error: Directory already exists: ${worktreePath}`));
        console.error("");
        console.error("Options:");
        console.error("  1. Use --name flag to specify a different worktree directory name");
        console.error("  2. Remove the existing directory");
        Deno.exit(1);
      }
    } catch (err) {
      // Path doesn't exist - this is good
      if (!(err instanceof Deno.errors.NotFound)) {
        throw err;
      }
    }

    // Step 4: Create git worktree
    console.log("");
    console.log(
      createNewBranch
        ? `Creating worktree with new branch "${branchName}"...`
        : `Creating worktree from existing branch "${branchName}"...`,
    );

    await gitWorktreeService.createWorktree(
      branchName,
      worktreePath,
      repoRoot,
      createNewBranch,
    );

    console.log(green("✓ Git worktree created successfully"));

    // Step 5: Extract worktree metadata
    console.log(dim("Extracting git metadata..."));
    const metadata = await metadataService.extractMetadata(worktreePath, repoRoot);

    // Step 6: Resolve project name (handle conflicts)
    const projectName = await resolveProjectNameConflict(worktreeName, projectManager);

    if (projectName !== worktreeName) {
      console.log(
        yellow(
          `Project name "${worktreeName}" already exists, using "${projectName}" instead`,
        ),
      );
    }

    // Step 7: Create i3pm project
    console.log(dim("Registering i3pm project..."));

    const worktreeProject: WorktreeProject = {
      name: projectName,
      display_name: displayName,
      icon,
      directory: worktreePath,
      scoped_classes: ["Ghostty", "code", "yazi", "lazygit"], // Default scoped apps
      created_at: Date.now(),
      last_used_at: Date.now(),
      worktree: metadata,
    };

    await projectManager.createWorktreeProject(worktreeProject);

    console.log(green("✓ i3pm project created successfully"));
    console.log("");
    console.log(bold("Worktree project created:"));
    console.log(`  ${icon} ${displayName} (${projectName})`);
    console.log(`  Branch: ${metadata.branch}`);
    console.log(`  Path: ${worktreePath}`);
    console.log(`  Status: ${metadata.is_clean ? "clean" : "dirty"}`);
    console.log("");
    console.log("Next steps:");
    console.log(`  ${bold("Switch to project:")} i3pm project switch ${projectName}`);
    console.log(
      `  ${bold("Launch apps:")} Apps will automatically open in ${worktreePath}`,
    );
  } catch (error) {
    console.error("");
    console.error(red("Error creating worktree:"));
    console.error(red(error.message));

    if (error.stderr) {
      console.error("");
      console.error(dim("Git error details:"));
      console.error(dim(error.stderr));
    }

    Deno.exit(1);
  }
}
