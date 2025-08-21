#!/usr/bin/env deno run --allow-run --allow-read --allow-write --allow-env --allow-net

/**
 * Claude Session Manager - Deno TypeScript Implementation
 * 
 * A modern CLI for managing Claude Code sessions using:
 * - Claude Code SDK types for type safety
 * - CLI execution (not direct API) for compatibility
 * - Integration with tmux, sesh, fzf, gum, and zoxide
 */

import { parse } from "https://deno.land/std@0.224.0/flags/mod.ts";
import { ClaudeCliWrapper } from "./claude-cli-wrapper.ts";
import type { 
  ClaudeSession, 
  SessionSelection,
  ExportFormat,
} from "./claude-types.ts";

// Initialize CLI wrapper
const claude = new ClaudeCliWrapper();

/**
 * Execute shell command helper
 */
async function exec(cmd: string, args: string[] = []): Promise<string> {
  const command = new Deno.Command(cmd, {
    args,
    stdout: "piped",
    stderr: "piped",
  });
  
  const { stdout } = await command.output();
  return new TextDecoder().decode(stdout).trim();
}

/**
 * Check if a command exists
 */
async function commandExists(cmd: string): Promise<boolean> {
  try {
    await exec("which", [cmd]);
    return true;
  } catch {
    return false;
  }
}

/**
 * Get sesh session name for a directory
 */
function getSeshName(dir: string): string {
  const parts = dir.split("/");
  const name = parts[parts.length - 1] || "home";
  return name.replace(/[.:]/g, "_");
}

/**
 * Format session for display
 */
function formatSession(session: ClaudeSession): string {
  const date = new Date(session.timestamp).toLocaleString();
  const icon = session.gitBranch ? "🔸" : "📁";
  const status = session.status === "active" ? "🟢" : "";
  const message = session.summary || session.lastMessage || "No messages";
  
  return `${icon} ${status} [${date}] ${getSeshName(session.cwd)} - ${message.slice(0, 50)}... | ${session.id} | ${session.cwd}`;
}

/**
 * Select session using fzf
 */
async function selectWithFzf(sessions: ClaudeSession[]): Promise<SessionSelection | null> {
  if (sessions.length === 0) {
    console.log("No sessions found");
    return null;
  }
  
  // Format sessions for display
  const displayLines = sessions.map(formatSession).join("\n");
  
  // Create temp file for fzf input
  const tempFile = await Deno.makeTempFile();
  await Deno.writeTextFile(tempFile, displayLines);
  
  try {
    // Run fzf with options
    const fzfCmd = new Deno.Command("fzf", {
      args: [
        "--ansi",
        "--no-sort",
        "--layout=reverse",
        "--info=inline",
        "--prompt=Select session: ",
        "--header=Enter: Resume | F2: View | F3: Export | ESC: Cancel",
        "--expect=f2,f3",
      ],
      stdin: "piped",
      stdout: "piped",
    });
    
    const process = fzfCmd.spawn();
    const writer = process.stdin.getWriter();
    await writer.write(new TextEncoder().encode(displayLines));
    await writer.close();
    
    const { stdout } = await process.output();
    const output = new TextDecoder().decode(stdout).trim().split("\n");
    
    if (output.length < 2) return null;
    
    const key = output[0];
    const selected = output[1];
    
    if (!selected) return null;
    
    // Parse selection to get session ID
    const parts = selected.split("|");
    const sessionId = parts[1]?.trim();
    
    if (!sessionId) return null;
    
    // Find the session
    const session = sessions.find(s => s.id === sessionId);
    if (!session) return null;
    
    // Determine action based on key
    let action: SessionSelection["action"] = "resume";
    if (key === "f2") action = "view";
    else if (key === "f3") action = "export";
    
    return { session, action };
  } finally {
    await Deno.remove(tempFile);
  }
}

/**
 * Select session using gum
 */
async function selectWithGum(sessions: ClaudeSession[]): Promise<SessionSelection | null> {
  if (sessions.length === 0) {
    console.log("No sessions found");
    return null;
  }
  
  // Use gum filter for selection
  const displayLines = sessions.map(formatSession);
  const selected = await exec("gum", [
    "filter",
    "--placeholder", "Search for a Claude session...",
    "--indicator", "▶",
    "--header", "Select Claude session:",
    ...displayLines,
  ]);
  
  if (!selected) return null;
  
  // Parse selection
  const parts = selected.split("|");
  const sessionId = parts[1]?.trim();
  
  if (!sessionId) return null;
  
  const session = sessions.find(s => s.id === sessionId);
  if (!session) return null;
  
  // Show action menu
  const action = await exec("gum", [
    "choose",
    "Resume Session",
    "View Conversation",
    "Export to Markdown",
    "Delete Session",
    "Cancel",
  ]);
  
  switch (action) {
    case "Resume Session": return { session, action: "resume" };
    case "View Conversation": return { session, action: "view" };
    case "Export to Markdown": return { session, action: "export" };
    case "Delete Session": return { session, action: "delete" };
    default: return { session, action: "cancel" };
  }
}

/**
 * Connect to tmux/sesh session and resume Claude
 */
async function connectAndResume(session: ClaudeSession): Promise<void> {
  const seshName = getSeshName(session.cwd);
  const windowName = `claude-${session.id.slice(0, 8)}`;
  
  console.log(`📍 Resuming session in ${session.cwd}`);
  console.log(`🏷️ Sesh name: ${seshName}`);
  console.log(`🆔 Session ID: ${session.id.slice(0, 8)}...`);
  
  // Check if we're in tmux
  const inTmux = Deno.env.get("TMUX") !== undefined;
  
  // Check if tmux session exists
  let sessionExists = false;
  try {
    await exec("tmux", ["has-session", "-t", seshName]);
    sessionExists = true;
  } catch {
    sessionExists = false;
  }
  
  if (sessionExists) {
    if (inTmux) {
      // Switch to session and create new window
      await exec("tmux", ["switch-client", "-t", seshName]);
      await exec("tmux", ["new-window", "-a", "-t", seshName, "-c", session.cwd, "-n", windowName]);
      await exec("tmux", ["send-keys", "-t", `${seshName}:${windowName}`, `claude --resume ${session.id}`, "C-m"]);
    } else {
      // Create window and attach
      await exec("tmux", ["new-window", "-a", "-t", seshName, "-c", session.cwd, "-n", windowName]);
      await exec("tmux", ["send-keys", "-t", `${seshName}:${windowName}`, `claude --resume ${session.id}`, "C-m"]);
      await exec("tmux", ["attach-session", "-t", seshName]);
    }
  } else {
    // Create new session
    await exec("tmux", ["new-session", "-d", "-s", seshName, "-c", session.cwd, "-n", windowName]);
    await exec("tmux", ["send-keys", "-t", `${seshName}:${windowName}`, `claude --resume ${session.id}`, "C-m"]);
    
    if (inTmux) {
      await exec("tmux", ["switch-client", "-t", seshName]);
    } else {
      await exec("tmux", ["attach-session", "-t", seshName]);
    }
  }
}

/**
 * View session conversation
 */
async function viewSession(session: ClaudeSession): Promise<void> {
  const content = await claude.exportSession(session.id, "markdown");
  
  // Use gum pager to display
  const pager = new Deno.Command("gum", {
    args: ["pager"],
    stdin: "piped",
  });
  
  const process = pager.spawn();
  const writer = process.stdin.getWriter();
  await writer.write(new TextEncoder().encode(content));
  await writer.close();
  await process.status;
}

/**
 * Export session
 */
async function exportSession(session: ClaudeSession, format: ExportFormat = "markdown"): Promise<void> {
  const content = await claude.exportSession(session.id, format as any);
  const filename = `claude-session-${session.id.slice(0, 8)}-${Date.now()}.${format === "markdown" ? "md" : format}`;
  
  await Deno.writeTextFile(filename, content);
  console.log(`✅ Exported to ${filename}`);
}

/**
 * Main CLI
 */
async function main() {
  // Parse arguments
  const flags = parse(Deno.args, {
    boolean: ["help", "gum", "fzf", "list", "zoxide"],
    string: ["resume", "view", "export", "delete", "search"],
    alias: { h: "help", l: "list", r: "resume", v: "view", e: "export", d: "delete", s: "search" },
  });
  
  // Show help
  if (flags.help) {
    console.log(`
Claude Session Manager - Deno TypeScript Implementation

Usage: deno run --allow-all claude-session-manager.ts [OPTIONS]

Options:
  -h, --help          Show this help message
  -l, --list          List all sessions
  -r, --resume ID     Resume specific session
  -v, --view ID       View session conversation
  -e, --export ID     Export session to markdown
  -d, --delete ID     Delete session
  -s, --search TERM   Search sessions
  --gum               Use gum for selection (default)
  --fzf               Use fzf for selection
  --zoxide            Sort by zoxide frecency

Examples:
  # Interactive selection with gum
  deno run --allow-all claude-session-manager.ts
  
  # Use fzf for selection
  deno run --allow-all claude-session-manager.ts --fzf
  
  # Resume specific session
  deno run --allow-all claude-session-manager.ts --resume abc123
  
  # Search sessions
  deno run --allow-all claude-session-manager.ts --search "typescript"
`);
    Deno.exit(0);
  }
  
  // Get all sessions
  let sessions = await claude.listSessions();
  
  // Apply search filter if provided
  if (flags.search) {
    const searchTerm = flags.search.toLowerCase();
    sessions = sessions.filter(s => 
      s.lastMessage?.toLowerCase().includes(searchTerm) ||
      s.summary?.toLowerCase().includes(searchTerm) ||
      s.cwd.toLowerCase().includes(searchTerm)
    );
  }
  
  // Sort by zoxide if requested
  if (flags.zoxide && await commandExists("zoxide")) {
    // Get zoxide rankings
    const zoxideOutput = await exec("zoxide", ["query", "-l"]);
    const rankings = zoxideOutput.split("\n");
    
    sessions.sort((a, b) => {
      const aRank = rankings.indexOf(a.cwd);
      const bRank = rankings.indexOf(b.cwd);
      if (aRank === -1 && bRank === -1) return 0;
      if (aRank === -1) return 1;
      if (bRank === -1) return -1;
      return aRank - bRank;
    });
  }
  
  // Handle specific actions
  if (flags.resume) {
    const session = sessions.find(s => s.id.includes(flags.resume as string));
    if (session) {
      await connectAndResume(session);
    } else {
      console.error(`Session ${flags.resume} not found`);
      Deno.exit(1);
    }
  } else if (flags.view) {
    const session = sessions.find(s => s.id.includes(flags.view as string));
    if (session) {
      await viewSession(session);
    } else {
      console.error(`Session ${flags.view} not found`);
      Deno.exit(1);
    }
  } else if (flags.export) {
    const session = sessions.find(s => s.id.includes(flags.export as string));
    if (session) {
      await exportSession(session);
    } else {
      console.error(`Session ${flags.export} not found`);
      Deno.exit(1);
    }
  } else if (flags.delete) {
    const success = await claude.deleteSession(flags.delete);
    if (success) {
      console.log(`✅ Session ${flags.delete} deleted`);
    } else {
      console.error(`Failed to delete session ${flags.delete}`);
      Deno.exit(1);
    }
  } else if (flags.list) {
    // List all sessions
    for (const session of sessions) {
      console.log(formatSession(session));
    }
  } else {
    // Interactive selection
    const useFzf = flags.fzf || !(await commandExists("gum"));
    const selection = useFzf 
      ? await selectWithFzf(sessions)
      : await selectWithGum(sessions);
    
    if (selection) {
      switch (selection.action) {
        case "resume":
          await connectAndResume(selection.session);
          break;
        case "view":
          await viewSession(selection.session);
          break;
        case "export":
          await exportSession(selection.session);
          break;
        case "delete":
          await claude.deleteSession(selection.session.id);
          console.log("✅ Session deleted");
          break;
      }
    }
  }
}

// Run main
if (import.meta.main) {
  main().catch(console.error);
}