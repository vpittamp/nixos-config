// Feature 087: Remote Project Environment Support
// create-remote command: Create a new remote project with SSH configuration
// Created: 2025-11-22

/**
 * Create a new remote project with SSH configuration.
 *
 * Usage: i3pm project create-remote <name> --local-dir <path> --remote-host <host>
 *        --remote-user <user> --remote-dir <path> [--port <number>]
 */

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { exists } from "https://deno.land/std@0.208.0/fs/exists.ts";
import { ProjectSchema, type Project } from "../../models/project.ts";
import { RemoteConfigSchema } from "../../models/remote-config.ts";

interface CreateRemoteOptions {
  name: string;
  localDir: string;
  remoteHost: string;
  remoteUser: string;
  remoteDir: string;
  port?: number;
  displayName?: string;
  icon?: string;
}

export async function createRemote(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    string: [
      "local-dir",
      "remote-host",
      "remote-user",
      "remote-dir",
      "display-name",
      "icon",
    ],
    number: ["port"],
    default: {
      port: 22,
      icon: "🌐",
    },
  });

  // Extract positional argument (project name)
  const name = parsed._[0] as string | undefined;

  if (!name) {
    console.error("Error: Project name is required");
    console.error(
      "Usage: i3pm project create-remote <name> --local-dir <path> --remote-host <host> --remote-user <user> --remote-dir <path> [--port <number>]",
    );
    return 1;
  }

  // Validate required flags
  const requiredFlags = [
    "local-dir",
    "remote-host",
    "remote-user",
    "remote-dir",
  ] as const;
  const missing = requiredFlags.filter((flag) => !parsed[flag]);

  if (missing.length > 0) {
    console.error(`Error: Missing required flags: ${missing.join(", ")}`);
    console.error(
      "Usage: i3pm project create-remote <name> --local-dir <path> --remote-host <host> --remote-user <user> --remote-dir <path> [--port <number>]",
    );
    return 1;
  }

  const options: CreateRemoteOptions = {
    name,
    localDir: parsed["local-dir"],
    remoteHost: parsed["remote-host"],
    remoteUser: parsed["remote-user"],
    remoteDir: parsed["remote-dir"],
    port: parsed.port,
    displayName: parsed["display-name"] || name,
    icon: parsed.icon,
  };

  try {
    // Validate remote configuration
    const remoteConfig = RemoteConfigSchema.parse({
      enabled: true,
      host: options.remoteHost,
      user: options.remoteUser,
      working_dir: options.remoteDir,
      port: options.port,
    });

    // Check if local directory exists
    const localDirExists = await exists(options.localDir);
    if (!localDirExists) {
      console.error(`Error: Local directory does not exist: ${options.localDir}`);
      return 1;
    }

    // Create project object
    const now = new Date().toISOString();
    const project: Project = {
      name: options.name,
      directory: options.localDir,
      display_name: options.displayName!,
      icon: options.icon!,
      created_at: now,
      updated_at: now,
      scoped_classes: [],
      remote: remoteConfig,
    };

    // Validate project
    ProjectSchema.parse(project);

    // Save to JSON file
    const configDir = Deno.env.get("HOME") + "/.config/i3";
    const projectsDir = `${configDir}/projects`;

    // Create projects directory if it doesn't exist
    await Deno.mkdir(projectsDir, { recursive: true });

    const projectFile = `${projectsDir}/${options.name}.json`;

    // Check if project already exists
    if (await exists(projectFile)) {
      console.error(`Error: Project '${options.name}' already exists`);
      return 1;
    }

    // Write project JSON
    await Deno.writeTextFile(
      projectFile,
      JSON.stringify(project, null, 2) + "\n",
    );

    console.log(`✓ Created remote project '${options.name}'`);
    console.log(`  Local directory: ${options.localDir}`);
    console.log(
      `  Remote: ${remoteConfig.user}@${remoteConfig.host}:${remoteConfig.working_dir}`,
    );
    console.log(`  Configuration saved to: ${projectFile}`);

    return 0;
  } catch (error) {
    if (error.name === "ZodError") {
      console.error("Error: Invalid configuration:");
      for (const issue of error.errors) {
        console.error(`  - ${issue.path.join(".")}: ${issue.message}`);
      }
      return 1;
    }

    console.error(`Error: ${error.message}`);
    return 1;
  }
}
