#!/usr/bin/env deno run --allow-all

/**
 * Test Setup for Claude Session Manager
 * 
 * Creates a test tmux environment with mock Claude sessions
 * for testing the Deno TypeScript implementation.
 */

import { ensureDir } from "@std/fs";
import { join } from "@std/path";

const HOME = Deno.env.get("HOME") || "";
const CLAUDE_DIR = join(HOME, ".claude");
const PROJECTS_DIR = join(CLAUDE_DIR, "projects");
const TEST_SESSION = "cli-1-2";

/**
 * Execute shell command
 */
async function exec(cmd: string, args: string[] = []): Promise<{ success: boolean; output: string }> {
  try {
    const command = new Deno.Command(cmd, {
      args,
      stdout: "piped",
      stderr: "piped",
    });
    
    const { code, stdout, stderr } = await command.output();
    const output = new TextDecoder().decode(stdout);
    
    if (code !== 0) {
      const error = new TextDecoder().decode(stderr);
      console.error(`Command failed: ${cmd} ${args.join(" ")}`);
      console.error(error);
    }
    
    return { success: code === 0, output: output.trim() };
  } catch (error) {
    console.error(`Failed to execute: ${cmd}`, error);
    return { success: false, output: "" };
  }
}

/**
 * Create mock session file
 */
async function createMockSession(
  projectName: string,
  sessionId: string,
  options: {
    cwd: string;
    gitBranch?: string;
    messageCount?: number;
    summary?: string;
  }
): Promise<void> {
  const projectDir = join(PROJECTS_DIR, projectName);
  await ensureDir(projectDir);
  
  const sessionFile = join(projectDir, `${sessionId}.jsonl`);
  const lines: string[] = [];
  
  // Add initial metadata
  lines.push(JSON.stringify({
    type: "metadata",
    timestamp: new Date().toISOString(),
    cwd: options.cwd,
    gitBranch: options.gitBranch || "main",
    sessionId: sessionId,
  }));
  
  // Add mock messages
  const messageCount = options.messageCount || 3;
  for (let i = 0; i < messageCount; i++) {
    // User message
    lines.push(JSON.stringify({
      type: "message",
      timestamp: new Date(Date.now() - (messageCount - i) * 60000).toISOString(),
      message: {
        role: "user",
        content: `Test user message ${i + 1} for ${projectName}`,
      },
    }));
    
    // Assistant message
    lines.push(JSON.stringify({
      type: "message",
      timestamp: new Date(Date.now() - (messageCount - i) * 59000).toISOString(),
      message: {
        role: "assistant",
        content: [{
          text: `Test assistant response ${i + 1}. Working on ${projectName} in ${options.cwd}`,
          type: "text",
        }],
      },
    }));
  }
  
  // Add summary if provided
  if (options.summary) {
    lines.push(JSON.stringify({
      type: "summary",
      timestamp: new Date().toISOString(),
      summary: options.summary,
    }));
  }
  
  await Deno.writeTextFile(sessionFile, lines.join("\n") + "\n");
  console.log(`✅ Created mock session: ${sessionId} in ${projectName}`);
}

/**
 * Setup tmux test environment
 */
async function setupTmux(): Promise<void> {
  console.log("🔧 Setting up tmux test environment...\n");
  
  // Kill existing test session if it exists
  await exec("tmux", ["kill-session", "-t", TEST_SESSION]);
  
  // Create new test session
  const { success } = await exec("tmux", [
    "new-session",
    "-d",
    "-s", TEST_SESSION,
    "-n", "main",
    "-c", HOME,
  ]);
  
  if (!success) {
    console.error("❌ Failed to create tmux session");
    return;
  }
  
  console.log(`✅ Created tmux session: ${TEST_SESSION}`);
  
  // Create additional windows for testing
  const windows = [
    { name: "deno-cli", cwd: "/home/vpittamp/cli" },
    { name: "test-project", cwd: "/tmp" },
    { name: "home", cwd: HOME },
  ];
  
  for (const window of windows) {
    await exec("tmux", [
      "new-window",
      "-t", TEST_SESSION,
      "-n", window.name,
      "-c", window.cwd,
    ]);
    console.log(`✅ Created window: ${window.name}`);
  }
  
  // Switch back to main window
  await exec("tmux", ["select-window", "-t", `${TEST_SESSION}:main`]);
}

/**
 * Create mock Claude sessions
 */
async function createMockSessions(): Promise<void> {
  console.log("\n📝 Creating mock Claude sessions...\n");
  
  // Ensure directories exist
  await ensureDir(PROJECTS_DIR);
  
  // Create various test sessions
  const sessions = [
    {
      project: "deno-typescript",
      id: "test-session-001",
      cwd: "/home/vpittamp/cli",
      gitBranch: "main",
      messageCount: 5,
      summary: "Converting bash scripts to Deno TypeScript",
    },
    {
      project: "web-development",
      id: "test-session-002",
      cwd: "/home/vpittamp/projects/webapp",
      gitBranch: "feature/auth",
      messageCount: 3,
      summary: "Implementing authentication system",
    },
    {
      project: "data-analysis",
      id: "test-session-003",
      cwd: "/home/vpittamp/data",
      messageCount: 8,
      summary: "Analyzing sales data with Python",
    },
    {
      project: "nixos-config",
      id: "test-session-004",
      cwd: "/home/vpittamp/.config/nixos",
      gitBranch: "main",
      messageCount: 2,
      summary: "Configuring NixOS system",
    },
    {
      project: "cli-tools",
      id: "test-session-005",
      cwd: "/home/vpittamp/cli",
      gitBranch: "main",
      messageCount: 10,
      summary: "Building CLI tools with Claude Code SDK",
    },
  ];
  
  for (const session of sessions) {
    await createMockSession(session.project, session.id, {
      cwd: session.cwd,
      gitBranch: session.gitBranch,
      messageCount: session.messageCount,
      summary: session.summary,
    });
  }
}

/**
 * Display test information
 */
async function displayTestInfo(): Promise<void> {
  console.log("\n" + "=".repeat(60));
  console.log("📋 TEST ENVIRONMENT READY");
  console.log("=".repeat(60));
  console.log("\nTmux Session: " + TEST_SESSION);
  console.log("\nAvailable Commands:");
  console.log("  • Attach to test session:");
  console.log(`    tmux attach -t ${TEST_SESSION}`);
  console.log("\n  • List tmux windows:");
  console.log(`    tmux list-windows -t ${TEST_SESSION}`);
  console.log("\n  • Test the CLI:");
  console.log("    deno task cli");
  console.log("    deno task cli --list");
  console.log("    deno task cli --view test-session-001");
  console.log("\n  • Run with fzf:");
  console.log("    deno task cli --fzf");
  console.log("\n  • Run with gum:");
  console.log("    deno task cli --gum");
  console.log("\n  • Clean up test session:");
  console.log(`    tmux kill-session -t ${TEST_SESSION}`);
  console.log("\n" + "=".repeat(60));
  
  // Show created sessions
  console.log("\n📂 Mock Sessions Created:");
  const sessions = [
    "test-session-001 (deno-typescript)",
    "test-session-002 (web-development)",
    "test-session-003 (data-analysis)",
    "test-session-004 (nixos-config)",
    "test-session-005 (cli-tools)",
  ];
  
  for (const session of sessions) {
    console.log(`  • ${session}`);
  }
  
  console.log("\n" + "=".repeat(60));
}

/**
 * Main test setup
 */
async function main() {
  console.log("🚀 Claude Session Manager Test Setup\n");
  
  // Check for required tools
  const requiredTools = ["tmux", "fzf", "gum"];
  const missingTools: string[] = [];
  
  for (const tool of requiredTools) {
    const { success } = await exec("which", [tool]);
    if (!success) {
      missingTools.push(tool);
    }
  }
  
  if (missingTools.length > 0) {
    console.warn("⚠️  Missing tools:", missingTools.join(", "));
    console.warn("Some features may not work properly.\n");
  }
  
  // Setup test environment
  await setupTmux();
  await createMockSessions();
  await displayTestInfo();
  
  // Optionally run a test command
  const args = Deno.args;
  if (args.includes("--run-test")) {
    console.log("\n🧪 Running test command...\n");
    const { output } = await exec("deno", ["task", "cli", "--list"]);
    console.log(output);
  }
}

// Run setup
if (import.meta.main) {
  main().catch(console.error);
}