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
import { generateFeatureBranchName } from "../../utils/branch-naming.ts";
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
  i3pm worktree create --from-description "feature description" [OPTIONS]

ARGUMENTS:
  <branch-name>         Branch name to checkout or create

OPTIONS:
  --from-description <desc>  Generate branch name from feature description (speckit naming)
  --source <branch>     Source branch to create from (default: main)
  --from-current        Create from current branch instead of main
  --name <name>         Custom worktree directory name (default: branch-name)
  --base-path <path>    Base directory for worktrees (default: $HOME)
  --checkout            Checkout existing branch instead of creating new
  --display-name <name> Custom display name for project
  --icon <emoji>        Icon for project (default: 🌿)
  -h, --help            Show this help message

EXAMPLES:
  # Create new branch from main (default)
  i3pm worktree create --from-description "Add user authentication"
  # Creates: 078-user-authentication branched from main

  # Create branch from current branch (dependent feature)
  i3pm worktree create --from-description "Fix auth bug" --from-current
  # Creates: 079-fix-auth-bug branched from current HEAD

  # Create branch from specific branch
  i3pm worktree create --from-description "Hotfix" --source release-v1.0

  # Checkout existing remote branch
  i3pm worktree create hotfix-payment --checkout

  # Custom worktree directory and display name
  i3pm worktree create feature-ui --name ui-work --display-name "UI Redesign" --icon 🎨

NOTES:
  - NEW branches default to branching from 'main' (independent features)
  - Use --from-current for dependent features that build on current work
  - Worktrees are created in $HOME by default (e.g., ~/nixos-078-feature-name)
  - Project is automatically registered with i3pm and can be switched to immediately
  - Scoped apps (terminal, editor, file manager) will open in the worktree directory
  - Specs directory is pre-created for parallel Claude Code sessions
`);
  Deno.exit(0);
}

/**
 * Truncate display name to a reasonable length for UI display
 * Limits to 60 characters to prevent overflow in top bar
 */
function truncateDisplayName(displayName: string, maxLength = 60): string {
  if (displayName.length <= maxLength) {
    return displayName;
  }
  return displayName.substring(0, maxLength - 3) + "...";
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
    string: ["name", "base-path", "display-name", "icon", "from-description", "source"],
    boolean: ["checkout", "help", "from-current"],
    alias: {
      h: "help",
    },
  });

  if (parsed.help) {
    showHelp();
  }

  const fromDescription = parsed["from-description"];
  const fromCurrent = parsed["from-current"] || false;
  const explicitSource = parsed.source;

  // Validate arguments
  if (!fromDescription && parsed._.length === 0) {
    console.error(red("Error: Branch name or --from-description is required"));
    console.error("");
    console.error("Usage: i3pm worktree create <branch-name> [OPTIONS]");
    console.error("       i3pm worktree create --from-description \"feature description\" [OPTIONS]");
    console.error("Run 'i3pm worktree create --help' for more information");
    Deno.exit(1);
  }

  // Initialize services early for branch name generation
  const gitWorktreeService = new GitWorktreeService();
  const metadataService = new WorktreeMetadataService();
  const projectManager = new ProjectManagerService();

  // Get repository root early (needed for branch name generation)
  const cwd = Deno.cwd();
  let repoRoot: string;
  try {
    console.log(dim("Validating git repository..."));
    await gitWorktreeService.validateRepository(cwd);
    repoRoot = await getRepositoryRoot(cwd);
  } catch (error) {
    console.error(red("Error: Not in a git repository"));
    console.error(red(error.message));
    Deno.exit(1);
  }

  // Determine branch name (either from argument or generated from description)
  let branchName: string;
  let featureDescription: string | undefined;

  if (fromDescription) {
    console.log(dim(`Generating branch name from: "${fromDescription}"`));
    const generated = await generateFeatureBranchName(fromDescription, repoRoot);
    branchName = generated.branchName;
    featureDescription = fromDescription;
    console.log(green(`✓ Generated branch name: ${branchName}`));
  } else {
    branchName = String(parsed._[0]);
  }

  const worktreeName = parsed.name || branchName;
  // Truncate display name to 60 characters to prevent UI overflow
  const rawDisplayName = parsed["display-name"] || featureDescription || branchName;
  const displayName = truncateDisplayName(rawDisplayName);
  const icon = parsed.icon || "🌿";
  const shouldCheckout = parsed.checkout || false;
  const customBasePath = parsed["base-path"];

  // Determine source branch for new branches
  // Priority: --source > --from-current > default (main)
  let sourceBranch: string | undefined;
  if (!shouldCheckout) {
    if (explicitSource) {
      sourceBranch = explicitSource;
    } else if (fromCurrent) {
      // Use current HEAD (don't specify source = git uses HEAD)
      sourceBranch = undefined;
    } else {
      // Default: branch from main
      sourceBranch = "main";
    }
  }

  try {
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
    if (createNewBranch) {
      const sourceInfo = sourceBranch ? ` from ${sourceBranch}` : " from current HEAD";
      console.log(`Creating worktree with new branch "${branchName}"${sourceInfo}...`);
    } else {
      console.log(`Creating worktree from existing branch "${branchName}"...`);
    }

    await gitWorktreeService.createWorktree(
      branchName,
      worktreePath,
      repoRoot,
      createNewBranch,
      sourceBranch,
    );

    console.log(green("✓ Git worktree created successfully"));

    // Step 4b: Create specs directory for speckit compatibility
    const specsDir = join(worktreePath, "specs", branchName);
    console.log(dim(`Creating specs directory: ${specsDir}`));
    await Deno.mkdir(specsDir, { recursive: true });
    console.log(green("✓ Specs directory created for parallel Claude Code sessions"));

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

    // Step 8: Add project directory to zoxide for sesh integration
    console.log(dim("Adding to zoxide for sesh integration..."));
    try {
      const zoxideCmd = new Deno.Command("zoxide", {
        args: ["add", worktreePath],
        stdout: "null",
        stderr: "null",
      });
      await zoxideCmd.output();
      console.log(green("✓ Directory added to zoxide"));
    } catch {
      // zoxide not available, skip silently
      console.log(yellow("⚠ zoxide not available, skipping sesh integration"));
    }

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
