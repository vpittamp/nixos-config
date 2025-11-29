// Feature 100: Account List Command
// T011: Create `i3pm account list` CLI command

import { parseArgs } from "https://deno.land/std@0.208.0/cli/parse_args.ts";
import { AccountsStorageSchema, type AccountsStorage } from "../../../models/account.ts";

const ACCOUNTS_FILE = `${Deno.env.get("HOME")}/.config/i3/accounts.json`;

async function loadAccounts(): Promise<AccountsStorage> {
  try {
    const content = await Deno.readTextFile(ACCOUNTS_FILE);
    return AccountsStorageSchema.parse(JSON.parse(content));
  } catch {
    return { version: 1, accounts: [] };
  }
}

export async function accountList(args: string[]): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["json"],
    default: {
      json: false,
    },
  });

  const storage = await loadAccounts();

  if (parsed.json) {
    console.log(JSON.stringify(storage.accounts, null, 2));
    return 0;
  }

  if (storage.accounts.length === 0) {
    console.log("No accounts configured.");
    console.log("");
    console.log("Add an account with:");
    console.log("  i3pm account add <name> <path>");
    return 0;
  }

  console.log("Configured accounts:");
  console.log("");

  for (const account of storage.accounts) {
    const defaultMarker = account.is_default ? " (default)" : "";
    const sshHost = account.ssh_host !== "github.com" ? ` [ssh: ${account.ssh_host}]` : "";
    console.log(`  ${account.name}${defaultMarker}${sshHost}`);
    console.log(`    Path: ${account.path}`);
  }

  return 0;
}
