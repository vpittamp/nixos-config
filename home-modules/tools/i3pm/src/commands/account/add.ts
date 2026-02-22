// Feature 100: Account Add Command
// T010: Create `i3pm account add` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { exists } from "https://deno.land/std@0.208.0/fs/exists.ts";
import { AccountConfigSchema, AccountsStorageSchema, type AccountConfig, type AccountsStorage } from "../../../models/account.ts";

const ACCOUNTS_FILE = `${Deno.env.get("HOME")}/.config/i3/accounts.json`;

async function loadAccounts(): Promise<AccountsStorage> {
  try {
    const content = await Deno.readTextFile(ACCOUNTS_FILE);
    return AccountsStorageSchema.parse(JSON.parse(content));
  } catch {
    return { version: 1, accounts: [] };
  }
}

async function saveAccounts(storage: AccountsStorage): Promise<void> {
  const dir = ACCOUNTS_FILE.substring(0, ACCOUNTS_FILE.lastIndexOf("/"));
  await Deno.mkdir(dir, { recursive: true });
  await Deno.writeTextFile(ACCOUNTS_FILE, JSON.stringify(storage, null, 2) + "\n");
}

export async function accountAdd(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    string: ["ssh-host"],
    boolean: ["default"],
    default: {
      "ssh-host": "github.com",
      default: false,
    },
  });

  const positionalArgs = parsed._ as string[];

  if (positionalArgs.length < 2) {
    console.error("Usage: i3pm account add <name> <path> [--ssh-host <host>] [--default]");
    console.error("");
    console.error("Examples:");
    console.error("  i3pm account add vpittamp ~/repos/vpittamp");
    console.error("  i3pm account add PittampalliOrg ~/repos/PittampalliOrg --default");
    console.error("  i3pm account add work ~/repos/work --ssh-host github-work");
    return 1;
  }

  const name = positionalArgs[0];
  let path = positionalArgs[1];

  // Expand ~ to home directory
  if (path.startsWith("~/")) {
    path = `${Deno.env.get("HOME")}${path.substring(1)}`;
  }

  // Validate account config
  let account: AccountConfig;
  try {
    account = AccountConfigSchema.parse({
      name,
      path,
      is_default: parsed.default,
      ssh_host: parsed["ssh-host"],
    });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      const zodError = error as unknown as { errors: Array<{ path: string[]; message: string }> };
      console.error("Error: Invalid account configuration:");
      for (const issue of zodError.errors) {
        console.error(`  - ${issue.path.join(".")}: ${issue.message}`);
      }
      return 1;
    }
    throw error;
  }

  // Load existing accounts
  const storage = await loadAccounts();

  // Check if account already exists
  const existing = storage.accounts.find(a => a.name === name);
  if (existing) {
    console.error(`Error: Account '${name}' already exists`);
    console.error(`  Path: ${existing.path}`);
    return 1;
  }

  // If this is the new default, clear other defaults
  if (account.is_default) {
    for (const a of storage.accounts) {
      a.is_default = false;
    }
  }

  // If this is the first account, make it default
  if (storage.accounts.length === 0) {
    account.is_default = true;
  }

  // Create directory if it doesn't exist
  if (!await exists(path)) {
    await Deno.mkdir(path, { recursive: true });
    console.log(`Created directory: ${path}`);
  }

  // Add account
  storage.accounts.push(account);
  await saveAccounts(storage);

  console.log(`Added account '${name}'`);
  console.log(`  Path: ${path}`);
  console.log(`  SSH host: ${account.ssh_host}`);
  console.log(`  Default: ${account.is_default}`);

  return 0;
}
