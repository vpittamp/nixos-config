/**
 * Worktree Remove Command
 * Feature 077: Git Worktree Project Management
 *
 * Removes a git worktree and cleans up all associated resources.
 */

import { parseArgs } from "@std/cli/parse-args";
import { join } from "@std/path";
import { execGit } from "../../utils/git.ts";
import { bold, green, yellow, red, dim } from "../../ui/ansi.ts";

/**
 * Show help for worktree remove command
 */
function showHelp(): void {
  console.log(`
i3pm worktree remove - Remove a worktree project and clean up resources

USAGE:
  i3pm worktree remove <project-name> [OPTIONS]

ARGUMENTS:
  <project-name>        Name of the worktree project to remove

OPTIONS:
  --force               Force delete branch even if not merged (git branch -D)
  --delete-remote       Also delete the remote branch (git push origin --delete)
  --keep-branch         Keep the git branch (only remove worktree and project)
  --keep-project        Keep the i3pm project JSON (only remove worktree)
  -h, --help            Show this help message

CLEANUP STEPS (performed automatically):
  1. Remove git worktree (git worktree remove)
  2. Delete local branch (git branch -d, or -D with --force)
  3. Remove i3pm project JSON (~/.config/i3/projects/<name>.json)
  4. Remove from zoxide database

EXAMPLES:
  # Standard removal (soft delete - fails if branch not merged)
  i3pm worktree remove 078-feature-name

  # Force delete unmerged branch
  i3pm worktree remove 078-feature-name --force

  # Also delete remote branch
  i3pm worktree remove 078-feature-name --delete-remote

  # Keep the branch for later use
  i3pm worktree remove 078-feature-name --keep-branch

NOTES:
  - By default, branch deletion is "soft" (fails if not merged to protect work)
  - Use --force only when you're sure the branch can be discarded
  - Remote branch deletion requires push access to origin
  - Zoxide entries auto-decay if unused, but removal is immediate
`);
  Deno.exit(0);
}

/**
 * Execute worktree remove command
 */
export async function removeWorktreeCommand(args: string[]): Promise<void> {
  const parsed = parseArgs(args, {
    boolean: ["force", "delete-remote", "keep-branch", "keep-project", "help"],
    alias: {
      h: "help",
    },
  });

  if (parsed.help) {
    showHelp();
  }

  if (parsed._.length === 0) {
    console.error(red("Error: Project name is required"));
    console.error("");
    console.error("Usage: i3pm worktree remove <project-name> [OPTIONS]");
    console.error("Run 'i3pm worktree remove --help' for more information");
    Deno.exit(1);
  }

  const projectName = String(parsed._[0]);
  const forceDelete = parsed.force || false;
  const deleteRemote = parsed["delete-remote"] || false;
  const keepBranch = parsed["keep-branch"] || false;
  const keepProject = parsed["keep-project"] || false;

  const homeDir = Deno.env.get("HOME") || "/home/vpittamp";
  const projectsDir = join(homeDir, ".config", "i3", "projects");
  const projectFile = join(projectsDir, `${projectName}.json`);

  // Step 1: Load project info to get worktree path
  console.log(dim(`Loading project info for "${projectName}"...`));

  let projectData: { directory: string; worktree?: { branch: string } } | null = null;
  let worktreePath: string;
  let branchName: string;

  try {
    const content = await Deno.readTextFile(projectFile);
    projectData = JSON.parse(content);
    worktreePath = projectData.directory;
    branchName = projectData.worktree?.branch || projectName;
  } catch {
    console.error(red(`Error: Project "${projectName}" not found`));
    console.error(dim(`Expected file: ${projectFile}`));
    Deno.exit(1);
  }

  console.log(dim(`Worktree path: ${worktreePath}`));
  console.log(dim(`Branch: ${branchName}`));
  console.log("");

  // Step 2: Remove git worktree
  console.log("Removing git worktree...");
  try {
    await execGit(["worktree", "remove", worktreePath, "--force"]);
    console.log(green("✓ Git worktree removed"));
  } catch (error) {
    console.error(red(`✗ Failed to remove worktree: ${error.message}`));
    console.error(dim("You may need to manually remove the directory"));
    Deno.exit(1);
  }

  // Step 3: Delete local branch (unless --keep-branch)
  if (!keepBranch) {
    console.log(
      forceDelete
        ? `Deleting branch "${branchName}" (force)...`
        : `Deleting branch "${branchName}" (soft - fails if not merged)...`
    );

    try {
      const deleteFlag = forceDelete ? "-D" : "-d";
      await execGit(["branch", deleteFlag, branchName]);
      console.log(green(`✓ Branch "${branchName}" deleted`));
    } catch (error) {
      if (!forceDelete && error.message.includes("not fully merged")) {
        console.error(yellow(`⚠ Branch "${branchName}" is not fully merged`));
        console.error(dim("Use --force to delete anyway, or --keep-branch to preserve it"));
        // Continue with other cleanup steps
      } else {
        console.error(yellow(`⚠ Could not delete branch: ${error.message}`));
      }
    }
  } else {
    console.log(dim(`Keeping branch "${branchName}" as requested`));
  }

  // Step 4: Delete remote branch (if requested)
  if (deleteRemote && !keepBranch) {
    console.log(`Deleting remote branch "origin/${branchName}"...`);
    try {
      await execGit(["push", "origin", "--delete", branchName]);
      console.log(green(`✓ Remote branch deleted`));
    } catch (error) {
      console.error(yellow(`⚠ Could not delete remote branch: ${error.message}`));
      console.error(dim("Branch may not exist on remote, or you lack push access"));
    }
  }

  // Step 5: Remove i3pm project JSON (unless --keep-project)
  if (!keepProject) {
    console.log("Removing i3pm project...");
    try {
      await Deno.remove(projectFile);
      console.log(green("✓ i3pm project removed"));
    } catch {
      console.error(yellow(`⚠ Could not remove project file: ${projectFile}`));
    }
  } else {
    console.log(dim("Keeping i3pm project JSON as requested"));
  }

  // Step 6: Remove from zoxide
  console.log("Removing from zoxide...");
  try {
    const zoxideCmd = new Deno.Command("zoxide", {
      args: ["remove", worktreePath],
      stdout: "null",
      stderr: "null",
    });
    await zoxideCmd.output();
    console.log(green("✓ Removed from zoxide"));
  } catch {
    console.log(dim("zoxide not available or entry not found"));
  }

  console.log("");
  console.log(bold("Worktree project removed successfully:"));
  console.log(`  Project: ${projectName}`);
  console.log(`  Path: ${worktreePath}`);
  if (!keepBranch) {
    console.log(`  Branch: ${branchName} (deleted)`);
  } else {
    console.log(`  Branch: ${branchName} (preserved)`);
  }

  if (!keepBranch && !forceDelete) {
    console.log("");
    console.log(dim("Tip: If the branch wasn't merged, your work is still in git reflog"));
    console.log(dim("Recover with: git checkout -b <branch> <commit-hash>"));
  }
}
