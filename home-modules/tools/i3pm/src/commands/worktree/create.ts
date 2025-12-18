// Feature 100: Worktree Create Command
// T023: Create `i3pm worktree create <branch>` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { WorktreeCreateRequestSchema, type WorktreeCreateRequest } from "../../../models/repository.ts";

/**
 * Create a new worktree as sibling to main.
 *
 * Must be run from within a bare repository structure.
 * Creates worktree at: ~/repos/<account>/<repo>/<branch>/
 */
export async function worktreeCreate(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    string: ["from", "repo", "agent"],
    boolean: ["speckit"],  // Feature 112: Speckit scaffolding flag
    default: {
      from: "main",
      speckit: false,  // CLI default is opt-in (false)
      agent: "claude",
    },
  });

  const positionalArgs = parsed._ as string[];

  if (positionalArgs.length < 1) {
    console.error("Usage: i3pm worktree create <branch> [--from <base>] [--repo <account/repo>] [--speckit] [--agent claude|gemini]");
    console.error("");
    console.error("Examples:");
    console.error("  i3pm worktree create 100-feature");
    console.error("  i3pm worktree create 100-feature --speckit   # Create with speckit scaffolding");
    console.error("  i3pm worktree create 100-feature --speckit --agent gemini");
    console.error("  i3pm worktree create 101-bugfix --from develop");
    console.error("  i3pm worktree create review --repo vpittamp/nixos");
    return 1;
  }

  const branch = positionalArgs[0];

  // Validate request
  let request: WorktreeCreateRequest;
  try {
    request = WorktreeCreateRequestSchema.parse({
      branch,
      from: parsed.from,
      repo: parsed.repo,
      agent: parsed.agent,
    });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      const zodError = error as unknown as { errors: Array<{ path: string[]; message: string }> };
      console.error("Error: Invalid worktree create request:");
      for (const issue of zodError.errors) {
        console.error(`  - ${issue.path.join(".")}: ${issue.message}`);
      }
      return 1;
    }
    throw error;
  }

  // Detect repository context
  const repoPath = await detectRepoPath(request.repo);
  if (!repoPath) {
    console.error("Error: Not in a bare repository structure");
    console.error("Please run from within a repository worktree or specify --repo");
    return 1;
  }

  const barePath = `${repoPath}/.bare`;
  const worktreePath = `${repoPath}/${branch}`;

  // Check if worktree already exists
  try {
    await Deno.stat(worktreePath);
    console.error(`Error: Worktree directory already exists: ${worktreePath}`);
    return 1;
  } catch {
    // Directory doesn't exist, good
  }

  console.log(`Creating worktree '${branch}' from '${request.from}'...`);

  // Create the worktree
  const cmd = new Deno.Command("git", {
    args: [
      "-C", barePath,
      "worktree", "add",
      worktreePath,
      "-b", branch,
      request.from,
    ],
    stdout: "piped",
    stderr: "piped",
  });

  const output = await cmd.output();

  if (!output.success) {
    const stderr = new TextDecoder().decode(output.stderr);
    console.error(`Error: git worktree add failed`);
    console.error(stderr);
    return 1;
  }

  console.log(`Created worktree at: ${worktreePath}`);

  // Feature 102: Auto-discover after worktree creation to update repos.json
  // This ensures the monitoring panel and other tools see the new worktree immediately
  const discoverCmd = new Deno.Command("i3pm", {
    args: ["discover"],
    stdout: "piped",
    stderr: "piped",
  });

  const discoverOutput = await discoverCmd.output();
  if (!discoverOutput.success) {
    const stderr = new TextDecoder().decode(discoverOutput.stderr);
    console.error("");
    console.error("Warning: Failed to update repos.json (worktree still created)");
    console.error(stderr);
  }

  // Feature 112: Create speckit directory structure if --speckit flag provided
  if (parsed.speckit) {
    const specsDir = `${worktreePath}/specs/${branch}`;
    const checklistsDir = `${specsDir}/checklists`;

    try {
      await Deno.mkdir(checklistsDir, { recursive: true });
      console.log(`Created speckit directory: ${specsDir}`);

      // Feature 126: Initialize agent context file (CLAUDE.md or GEMINI.md)
      const agentFile = request.agent === "gemini" ? "GEMINI.md" : "CLAUDE.md";
      const agentPath = `${worktreePath}/${agentFile}`;
      const templatePath = `${repoPath}/.specify/templates/agent-file-template.md`;

      try {
        // Only create if it doesn't exist
        await Deno.stat(agentPath);
      } catch {
        // Doesn't exist, copy from template if available
        try {
          const templateContent = await Deno.readTextFile(templatePath);
          const projectName = repoPath.split("/").pop() || "Project";
          const date = new Date().toISOString().split("T")[0];
          
          let content = templateContent
            .replace("[PROJECT NAME]", projectName)
            .replace("[DATE]", date)
            .replace("[EXTRACTED FROM ALL PLAN.MD FILES]", "- (Initial worktree setup)")
            .replace("[ACTUAL STRUCTURE FROM PLANS]", "src/\ntests/")
            .replace("[ONLY COMMANDS FOR ACTIVE TECHNOLOGIES]", "# Add commands here")
            .replace("[LANGUAGE-SPECIFIC, ONLY FOR LANGUAGES IN USE]", "Follow project conventions")
            .replace("[LAST 3 FEATURES AND WHAT THEY ADDED]", `- ${branch}: Initial worktree setup`);
            
          await Deno.writeTextFile(agentPath, content);
          console.log(`Initialized agent context: ${agentFile}`);
        } catch (err) {
          console.error(`Warning: Failed to initialize ${agentFile}: ${err.message}`);
        }
      }
    } catch (error) {
      // Non-fatal warning - worktree was created successfully
      const message = error instanceof Error ? error.message : String(error);
      console.error(`Warning: Failed to create speckit directory: ${message}`);
    }
  }

  console.log("");
  console.log(`To switch to this worktree:`);
  console.log(`  cd ${worktreePath}`);

  return 0;
}

/**
 * Detect repository path from current directory or --repo flag.
 */
async function detectRepoPath(repo?: string): Promise<string | null> {
  if (repo) {
    // Parse account/repo format
    const parts = repo.split("/");
    if (parts.length !== 2) {
      return null;
    }
    const [account, repoName] = parts;
    const home = Deno.env.get("HOME") || "";
    return `${home}/repos/${account}/${repoName}`;
  }

  // Detect from current directory
  const cwd = Deno.cwd();

  // Walk up the directory tree looking for .bare/
  let dir = cwd;
  while (dir !== "/") {
    try {
      const bareStat = await Deno.stat(`${dir}/.bare`);
      if (bareStat.isDirectory) {
        return dir;
      }
    } catch {
      // Not found, continue up
    }

    // Go up one level
    const parent = dir.substring(0, dir.lastIndexOf("/"));
    if (parent === dir || parent === "") {
      break;
    }
    dir = parent;
  }

  return null;
}
