#!/usr/bin/env deno run --allow-run --allow-read

/**
 * Minimal Deno CLI Example
 * 
 * This demonstrates:
 * 1. Basic CLI structure
 * 2. Command-line argument parsing
 * 3. Invoking system commands
 * 4. Simple output
 * 
 * Run with: deno run --allow-run hello-cli.ts
 * Or make executable: chmod +x hello-cli.ts && ./hello-cli.ts
 */

import { parse } from "https://deno.land/std@0.224.0/flags/mod.ts";

// Parse command-line arguments
const flags = parse(Deno.args, {
  boolean: ["help", "version", "command"],
  string: ["name"],
  alias: { h: "help", v: "version", c: "command" },
  default: { name: "World" },
});

// Simple command execution wrapper
async function runCommand(cmd: string, args: string[] = []): Promise<string> {
  const command = new Deno.Command(cmd, {
    args,
    stdout: "piped",
    stderr: "piped",
  });
  
  const { code, stdout, stderr } = await command.output();
  
  if (code !== 0) {
    const errorText = new TextDecoder().decode(stderr);
    throw new Error(`Command failed: ${errorText}`);
  }
  
  return new TextDecoder().decode(stdout);
}

// Main CLI function
async function main() {
  // Handle help flag
  if (flags.help) {
    console.log(`
Hello CLI - A minimal Deno TypeScript CLI example

Usage: deno run --allow-run hello-cli.ts [OPTIONS]

Options:
  -h, --help      Show this help message
  -v, --version   Show version
  -c, --command   Run a system command example
  --name <name>   Specify a name for greeting (default: World)

Examples:
  deno run --allow-run hello-cli.ts
  deno run --allow-run hello-cli.ts --name Alice
  deno run --allow-run hello-cli.ts --command
`);
    Deno.exit(0);
  }

  // Handle version flag
  if (flags.version) {
    console.log("Hello CLI v1.0.0");
    Deno.exit(0);
  }

  // Handle command execution example
  if (flags.command) {
    console.log("📊 Running system command example...\n");
    
    try {
      // Example: Get current directory
      const pwdOutput = await runCommand("pwd");
      console.log("Current directory:", pwdOutput.trim());
      
      // Example: List files (limited output)
      const lsOutput = await runCommand("ls", ["-la"]);
      const files = lsOutput.split("\n").slice(0, 5);
      console.log("\nFirst 5 items in directory:");
      files.forEach(file => console.log("  ", file));
      
      // Example: Get date
      const dateOutput = await runCommand("date");
      console.log("\nCurrent date:", dateOutput.trim());
      
    } catch (error) {
      console.error("Error running command:", error.message);
      Deno.exit(1);
    }
    
    console.log("\n✅ Command execution complete!");
  } else {
    // Default: Simple greeting
    console.log(`Hello, ${flags.name}!`);
  }
}

// Run the CLI
if (import.meta.main) {
  await main();
}

// Export for testing
export { main, runCommand };