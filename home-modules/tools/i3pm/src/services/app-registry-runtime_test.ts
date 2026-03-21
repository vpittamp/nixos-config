import { assertEquals, assertRejects } from "jsr:@std/assert";
import {
  applyWorkingCopy,
  diffWorkingCopy,
  mergeRegistry,
  renderEffectiveRegistry,
  type RegistryOverridesFile,
  sanitizeOverride,
} from "./app-registry-runtime.ts";
import type { ApplicationRegistry } from "../models/registry.ts";

function sampleBaseRegistry(): ApplicationRegistry {
  return {
    version: "1.0.0",
    applications: [
      {
        name: "terminal",
        display_name: "Terminal",
        command: "ghostty",
        parameters: [],
        terminal: true,
        expected_class: "com.mitchellh.ghostty",
        preferred_workspace: 1,
        scope: "scoped",
        fallback_behavior: "use_home",
        multi_instance: true,
        icon: "ghostty",
      },
      {
        name: "code",
        display_name: "VS Code",
        command: "code",
        parameters: [],
        terminal: false,
        expected_class: "Code",
        preferred_workspace: 2,
        scope: "scoped",
        fallback_behavior: "skip",
        multi_instance: true,
        icon: "vscode",
      },
    ],
  };
}

async function writeJson(path: string, value: unknown): Promise<void> {
  await Deno.writeTextFile(path, `${JSON.stringify(value, null, 2)}\n`);
}

Deno.test("mergeRegistry applies repo and working-copy overrides with working-copy precedence", () => {
  const base = sampleBaseRegistry();
  const repo: RegistryOverridesFile = {
    version: "1.0.0",
    applications: {
      terminal: {
        preferred_workspace: 3,
        description: "Repo description",
      },
    },
  };
  const working: RegistryOverridesFile = {
    version: "1.0.0",
    applications: {
      terminal: {
        preferred_workspace: 4,
      },
    },
  };

  const merged = mergeRegistry(base, repo, working);
  assertEquals(merged.applications[0].preferred_workspace, 4);
  assertEquals(merged.applications[0].description, "Repo description");
});

Deno.test("sanitizeOverride drops empty strings and empty arrays", () => {
  assertEquals(
    sanitizeOverride({
      display_name: "  Terminal  ",
      description: "   ",
      aliases: ["term", " ", "shell"],
    }),
    {
      display_name: "Terminal",
      aliases: ["term", "shell"],
    },
  );
});

Deno.test("renderEffectiveRegistry writes merged effective registry", async () => {
  const dir = await Deno.makeTempDir();
  const basePath = `${dir}/base.json`;
  const declarativePath = `${dir}/declarative.json`;
  const workingCopyPath = `${dir}/working.json`;
  const effectivePath = `${dir}/effective.json`;

  await writeJson(basePath, sampleBaseRegistry());
  await writeJson(declarativePath, { version: "1.0.0", applications: { terminal: { description: "Repo" } } });
  await writeJson(workingCopyPath, { version: "1.0.0", applications: { terminal: { preferred_workspace: 5 } } });

  const merged = await renderEffectiveRegistry({
    basePath,
    declarativePath,
    workingCopyPath,
    effectivePath,
  });

  const onDisk = JSON.parse(await Deno.readTextFile(effectivePath));
  assertEquals(merged, onDisk);
  assertEquals(merged.applications[0].description, "Repo");
  assertEquals(merged.applications[0].preferred_workspace, 5);
});

Deno.test("diffWorkingCopy reports changed apps only", async () => {
  const dir = await Deno.makeTempDir();
  await writeJson(`${dir}/repo.json`, { version: "1.0.0", applications: { terminal: { preferred_workspace: 1 } } });
  await writeJson(`${dir}/working.json`, { version: "1.0.0", applications: { terminal: { preferred_workspace: 2 } } });

  const diff = await diffWorkingCopy({
    repoOverridePath: `${dir}/repo.json`,
    workingCopyPath: `${dir}/working.json`,
  });

  assertEquals(diff.length, 1);
  assertEquals(diff[0].name, "terminal");
  assertEquals(diff[0].before.preferred_workspace, 1);
  assertEquals(diff[0].after.preferred_workspace, 2);
});

Deno.test("applyWorkingCopy rejects unknown apps", async () => {
  const dir = await Deno.makeTempDir();
  await writeJson(`${dir}/base.json`, sampleBaseRegistry());
  await writeJson(`${dir}/repo.json`, { version: "1.0.0", applications: {} });
  await writeJson(`${dir}/working.json`, { version: "1.0.0", applications: { unknown: { preferred_workspace: 9 } } });

  await assertRejects(
    () =>
      applyWorkingCopy({
        basePath: `${dir}/base.json`,
        repoOverridePath: `${dir}/repo.json`,
        workingCopyPath: `${dir}/working.json`,
        effectivePath: `${dir}/effective.json`,
      }),
    Error,
    "unknown application",
  );
});
