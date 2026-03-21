import { ensureDir } from "@std/fs";
import * as path from "@std/path";
import {
  type ApplicationRegistry,
  type RegistryApplication,
  isApplicationRegistry,
} from "../models/registry.ts";

const VERSION = "1.0.0";

export const EDITABLE_REGISTRY_FIELDS = [
  "aliases",
  "description",
  "display_name",
  "fallback_behavior",
  "floating",
  "floating_size",
  "icon",
  "multi_instance",
  "preferred_monitor_role",
  "preferred_workspace",
] as const;

type EditableRegistryField = (typeof EDITABLE_REGISTRY_FIELDS)[number];

export interface EditableRegistryOverride {
  aliases?: string[];
  description?: string;
  display_name?: string;
  fallback_behavior?: RegistryApplication["fallback_behavior"] | null;
  floating?: boolean | null;
  floating_size?: RegistryApplication["floating_size"] | null;
  icon?: string;
  multi_instance?: boolean | null;
  preferred_monitor_role?: RegistryApplication["preferred_monitor_role"] | null;
  preferred_workspace?: number | null;
}

export interface RegistryOverridesFile {
  version: string;
  applications: Record<string, EditableRegistryOverride>;
}

export interface RegistryRuntimePaths {
  basePath: string;
  declarativePath: string;
  effectivePath: string;
  repoOverridePath: string;
  workingCopyPath: string;
}

export interface RegistryDiffEntry {
  name: string;
  before: EditableRegistryOverride;
  after: EditableRegistryOverride;
}

export interface ApplyWorkingCopyResult {
  changedApplications: string[];
  effectivePath: string;
  repoOverridePath: string;
  workingCopyPath: string;
}

function defaultHome(): string {
  return Deno.env.get("HOME") || "/home/user";
}

function normalizeConfigRoot(root: string): string {
  const trimmed = String(root || "").trim();
  if (!trimmed) {
    return "/etc/nixos";
  }

  if (path.basename(trimmed) === "flake.nix") {
    return path.dirname(trimmed);
  }

  return trimmed;
}

function resolveConfigRoot(): string {
  const candidates = [
    Deno.env.get("I3PM_CONFIG_ROOT"),
    Deno.env.get("FLAKE_ROOT"),
    Deno.env.get("NH_FLAKE"),
    Deno.env.get("NH_OS_FLAKE"),
    "/etc/nixos",
  ];

  for (const candidate of candidates) {
    const normalized = normalizeConfigRoot(candidate || "");
    if (normalized && existsSync(normalized)) {
      return normalized;
    }
  }

  return "/etc/nixos";
}

function existsSync(candidate: string): boolean {
  try {
    Deno.statSync(candidate);
    return true;
  } catch {
    return false;
  }
}

export function resolveRegistryRuntimePaths(): RegistryRuntimePaths {
  const home = defaultHome();
  const configRoot = resolveConfigRoot();

  return {
    basePath: path.join(home, ".local/share/i3pm/registry/base.json"),
    declarativePath: path.join(home, ".local/share/i3pm/registry/declarative-overrides.json"),
    effectivePath: path.join(home, ".config/i3/application-registry.json"),
    repoOverridePath: path.join(configRoot, "shared/app-registry-overrides.json"),
    workingCopyPath: path.join(home, ".config/i3/app-registry-working-copy.json"),
  };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

function isNullableInteger(value: unknown): value is number | null {
  return value === null || (Number.isInteger(value) && typeof value === "number");
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isNullableBoolean(value: unknown): value is boolean | null {
  return value === null || typeof value === "boolean";
}

function validateOverrideShape(name: string, value: unknown): EditableRegistryOverride {
  if (!isPlainObject(value)) {
    throw new Error(`Override for '${name}' must be an object`);
  }

  const result: EditableRegistryOverride = {};

  for (const [key, rawValue] of Object.entries(value)) {
    if (!EDITABLE_REGISTRY_FIELDS.includes(key as EditableRegistryField)) {
      throw new Error(`Override for '${name}' contains unsupported field '${key}'`);
    }

    switch (key) {
      case "aliases":
        if (!isStringArray(rawValue)) {
          throw new Error(`Override field '${name}.aliases' must be an array of strings`);
        }
        result.aliases = rawValue;
        break;
      case "description":
      case "display_name":
      case "icon":
        if (typeof rawValue !== "string") {
          throw new Error(`Override field '${name}.${key}' must be a string`);
        }
        result[key] = rawValue;
        break;
      case "preferred_workspace":
        if (!isNullableInteger(rawValue)) {
          throw new Error(`Override field '${name}.preferred_workspace' must be an integer or null`);
        }
        result.preferred_workspace = rawValue;
        break;
      case "preferred_monitor_role":
        if (!isNullableString(rawValue)) {
          throw new Error(`Override field '${name}.preferred_monitor_role' must be a string or null`);
        }
        if (typeof rawValue === "string" && !["primary", "secondary", "tertiary"].includes(rawValue)) {
          throw new Error(`Override field '${name}.preferred_monitor_role' must be primary, secondary, tertiary, or null`);
        }
        result.preferred_monitor_role = rawValue as EditableRegistryOverride["preferred_monitor_role"];
        break;
      case "floating":
      case "multi_instance":
        if (!isNullableBoolean(rawValue)) {
          throw new Error(`Override field '${name}.${key}' must be a boolean or null`);
        }
        result[key] = rawValue;
        break;
      case "floating_size":
        if (!isNullableString(rawValue)) {
          throw new Error(`Override field '${name}.floating_size' must be a string or null`);
        }
        if (typeof rawValue === "string" && !["scratchpad", "small", "medium", "large"].includes(rawValue)) {
          throw new Error(`Override field '${name}.floating_size' must be scratchpad, small, medium, large, or null`);
        }
        result.floating_size = rawValue as EditableRegistryOverride["floating_size"];
        break;
      case "fallback_behavior":
        if (!isNullableString(rawValue)) {
          throw new Error(`Override field '${name}.fallback_behavior' must be a string or null`);
        }
        if (typeof rawValue === "string" && !["skip", "use_home", "error"].includes(rawValue)) {
          throw new Error(`Override field '${name}.fallback_behavior' must be skip, use_home, error, or null`);
        }
        result.fallback_behavior = rawValue as EditableRegistryOverride["fallback_behavior"];
        break;
      default:
        break;
    }
  }

  return result;
}

export function sanitizeOverride(value: EditableRegistryOverride): EditableRegistryOverride {
  const sanitized: EditableRegistryOverride = {};

  for (const field of EDITABLE_REGISTRY_FIELDS) {
    if (!(field in value)) {
      continue;
    }

    const fieldValue = value[field];
    if (fieldValue === undefined) {
      continue;
    }

    if (typeof fieldValue === "string") {
      const trimmed = fieldValue.trim();
      if (!trimmed.length) {
        if (["preferred_monitor_role", "floating_size", "fallback_behavior"].includes(field)) {
          sanitized[field] = null as never;
        }
        continue;
      }
      sanitized[field] = trimmed as never;
      continue;
    }

    if (Array.isArray(fieldValue)) {
      const cleaned = fieldValue.map((item) => String(item).trim()).filter((item) => item.length > 0);
      if (cleaned.length > 0) {
        sanitized[field] = cleaned as never;
      }
      continue;
    }

    sanitized[field] = fieldValue as never;
  }

  return validateOverrideShape("<inline>", sanitized);
}

function emptyOverrides(): RegistryOverridesFile {
  return {
    version: VERSION,
    applications: {},
  };
}

async function readJsonFile<T>(filePath: string): Promise<T | null> {
  try {
    const content = await Deno.readTextFile(filePath);
    return JSON.parse(content) as T;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      return null;
    }
    throw error;
  }
}

async function writeJsonFile(filePath: string, value: unknown): Promise<void> {
  await ensureDir(path.dirname(filePath));
  const tempPath = `${filePath}.tmp-${crypto.randomUUID()}`;
  await Deno.writeTextFile(tempPath, `${JSON.stringify(value, null, 2)}\n`);
  await Deno.rename(tempPath, filePath);
}

export async function loadOverridesFile(filePath: string): Promise<RegistryOverridesFile> {
  const raw = await readJsonFile<unknown>(filePath);
  if (raw === null) {
    return emptyOverrides();
  }

  if (!isPlainObject(raw)) {
    throw new Error(`Overrides file at ${filePath} must be a JSON object`);
  }

  const version = typeof raw.version === "string" ? raw.version : VERSION;
  const applicationsRaw = raw.applications;
  if (!isPlainObject(applicationsRaw)) {
    throw new Error(`Overrides file at ${filePath} must contain an 'applications' object`);
  }

  const applications: Record<string, EditableRegistryOverride> = {};
  for (const [name, value] of Object.entries(applicationsRaw)) {
    applications[name] = validateOverrideShape(name, value);
  }

  return { version, applications };
}

export async function loadBaseRegistry(filePath: string): Promise<ApplicationRegistry> {
  const raw = await readJsonFile<unknown>(filePath);
  if (raw === null) {
    throw new Error(`Base registry not found at ${filePath}`);
  }

  if (!isApplicationRegistry(raw)) {
    throw new Error(`Base registry at ${filePath} has an invalid schema`);
  }

  return raw;
}

function pickEditableOverrideFromApp(app: RegistryApplication): EditableRegistryOverride {
  const picked: EditableRegistryOverride = {};
  for (const field of EDITABLE_REGISTRY_FIELDS) {
    const value = app[field];
    if (value !== undefined) {
      picked[field] = value as never;
    }
  }
  return sanitizeOverride(picked);
}

function overridesEqual(left: EditableRegistryOverride, right: EditableRegistryOverride): boolean {
  return JSON.stringify(sanitizeOverride(left)) === JSON.stringify(sanitizeOverride(right));
}

function applyOverride(
  app: RegistryApplication,
  override: EditableRegistryOverride | undefined,
): RegistryApplication {
  if (!override) {
    return app;
  }

  const next = { ...app };
  for (const field of EDITABLE_REGISTRY_FIELDS) {
    if (!(field in override)) {
      continue;
    }

    const value = override[field];
    if (value === undefined || value === null) {
      delete (next as Record<string, unknown>)[field];
      continue;
    }
    (next as Record<string, unknown>)[field] = value;
  }

  return next;
}

export function mergeRegistry(
  baseRegistry: ApplicationRegistry,
  repoOverrides: RegistryOverridesFile,
  workingCopyOverrides: RegistryOverridesFile,
): ApplicationRegistry {
  return {
    version: baseRegistry.version || VERSION,
    applications: baseRegistry.applications.map((app) =>
      applyOverride(
        applyOverride(app, repoOverrides.applications[app.name]),
        workingCopyOverrides.applications[app.name],
      )
    ),
  };
}

export async function renderEffectiveRegistry(
  explicitPaths?: Partial<RegistryRuntimePaths>,
): Promise<ApplicationRegistry> {
  const paths = { ...resolveRegistryRuntimePaths(), ...explicitPaths };
  const [baseRegistry, declarativeOverrides, workingCopyOverrides] = await Promise.all([
    loadBaseRegistry(paths.basePath),
    loadOverridesFile(paths.declarativePath),
    loadOverridesFile(paths.workingCopyPath),
  ]);

  const merged = mergeRegistry(baseRegistry, declarativeOverrides, workingCopyOverrides);
  await writeJsonFile(paths.effectivePath, merged);
  return merged;
}

export async function resetWorkingCopy(
  explicitPaths?: Partial<RegistryRuntimePaths>,
): Promise<RegistryOverridesFile> {
  const paths = { ...resolveRegistryRuntimePaths(), ...explicitPaths };
  const declarativeOverrides = await loadOverridesFile(paths.declarativePath);
  await writeJsonFile(paths.workingCopyPath, declarativeOverrides);
  await renderEffectiveRegistry(paths);
  return declarativeOverrides;
}

export async function validateRegistryRuntime(
  explicitPaths?: Partial<RegistryRuntimePaths>,
): Promise<RegistryRuntimePaths> {
  const paths = { ...resolveRegistryRuntimePaths(), ...explicitPaths };
  await loadBaseRegistry(paths.basePath);
  await loadOverridesFile(paths.declarativePath);
  await loadOverridesFile(paths.workingCopyPath);
  return paths;
}

export async function diffWorkingCopy(
  explicitPaths?: Partial<RegistryRuntimePaths>,
): Promise<RegistryDiffEntry[]> {
  const paths = { ...resolveRegistryRuntimePaths(), ...explicitPaths };
  const [repoOverrides, workingCopyOverrides] = await Promise.all([
    loadOverridesFile(paths.repoOverridePath),
    loadOverridesFile(paths.workingCopyPath),
  ]);

  const names = Array.from(new Set([
    ...Object.keys(repoOverrides.applications),
    ...Object.keys(workingCopyOverrides.applications),
  ])).sort();

  return names.reduce<RegistryDiffEntry[]>((entries, name) => {
    const before = sanitizeOverride(repoOverrides.applications[name] || {});
    const after = sanitizeOverride(workingCopyOverrides.applications[name] || {});
    if (!overridesEqual(before, after)) {
      entries.push({ name, before, after });
    }
    return entries;
  }, []);
}

export async function applyWorkingCopy(
  explicitPaths?: Partial<RegistryRuntimePaths>,
): Promise<ApplyWorkingCopyResult> {
  const paths = { ...resolveRegistryRuntimePaths(), ...explicitPaths };
  const [baseRegistry, workingCopyOverrides] = await Promise.all([
    loadBaseRegistry(paths.basePath),
    loadOverridesFile(paths.workingCopyPath),
  ]);

  const knownNames = new Set(baseRegistry.applications.map((app) => app.name));
  for (const name of Object.keys(workingCopyOverrides.applications)) {
    if (!knownNames.has(name)) {
      throw new Error(`Working copy contains unknown application '${name}'`);
    }
  }

  const cleaned: RegistryOverridesFile = {
    version: workingCopyOverrides.version || VERSION,
    applications: {},
  };

  for (const [name, override] of Object.entries(workingCopyOverrides.applications)) {
    const sanitized = sanitizeOverride(override);
    if (Object.keys(sanitized).length > 0) {
      cleaned.applications[name] = sanitized;
    }
  }

  await writeJsonFile(paths.repoOverridePath, cleaned);
  await renderEffectiveRegistry(paths);

  return {
    changedApplications: Object.keys(cleaned.applications).sort(),
    effectivePath: paths.effectivePath,
    repoOverridePath: paths.repoOverridePath,
    workingCopyPath: paths.workingCopyPath,
  };
}

export async function upsertWorkingCopyOverride(
  appName: string,
  override: EditableRegistryOverride,
  explicitPaths?: Partial<RegistryRuntimePaths>,
): Promise<RegistryOverridesFile> {
  const paths = { ...resolveRegistryRuntimePaths(), ...explicitPaths };
  const workingCopy = await loadOverridesFile(paths.workingCopyPath);
  const sanitized = sanitizeOverride(override);

  if (Object.keys(sanitized).length === 0) {
    delete workingCopy.applications[appName];
  } else {
    workingCopy.applications[appName] = sanitized;
  }

  await writeJsonFile(paths.workingCopyPath, workingCopy);
  await renderEffectiveRegistry(paths);
  return workingCopy;
}

export async function removeWorkingCopyOverride(
  appName: string,
  explicitPaths?: Partial<RegistryRuntimePaths>,
): Promise<RegistryOverridesFile> {
  const paths = { ...resolveRegistryRuntimePaths(), ...explicitPaths };
  const workingCopy = await loadOverridesFile(paths.workingCopyPath);
  delete workingCopy.applications[appName];
  await writeJsonFile(paths.workingCopyPath, workingCopy);
  await renderEffectiveRegistry(paths);
  return workingCopy;
}

export async function buildWorkingCopyFromEffectiveRegistry(
  explicitPaths?: Partial<RegistryRuntimePaths>,
): Promise<RegistryOverridesFile> {
  const paths = { ...resolveRegistryRuntimePaths(), ...explicitPaths };
  const effective = await readJsonFile<unknown>(paths.effectivePath);
  if (!effective || !isApplicationRegistry(effective)) {
    return emptyOverrides();
  }

  const result: RegistryOverridesFile = emptyOverrides();
  for (const app of effective.applications) {
    const override = pickEditableOverrideFromApp(app);
    if (Object.keys(override).length > 0) {
      result.applications[app.name] = override;
    }
  }

  return result;
}
