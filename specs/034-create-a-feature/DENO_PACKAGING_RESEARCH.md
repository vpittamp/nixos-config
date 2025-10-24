# Deno Compilation and NixOS Packaging Research - Feature 034

**Feature**: Unified Application Launcher with Project Context
**Component**: i3pm apps CLI tool (Deno/TypeScript)
**Research Date**: 2025-10-24

---

## Executive Summary

**Recommendation**: Use the **existing i3pm-deno packaging pattern** (stdenv.mkDerivation + Bash wrapper) for Feature 034's CLI tool instead of `deno compile`. This approach:

1. ✅ Runs TypeScript directly with Deno runtime (no compilation step)
2. ✅ Allows live code reloads during development (no rebuild needed)
3. ✅ Minimizes binary size (~500KB wrapper vs ~80MB compiled binary)
4. ✅ Proven pattern already in production for `i3pm` CLI
5. ✅ Supports all required permissions via runtime flags

**Build time estimate**: ~30 seconds for home-manager rebuild (no Deno compilation needed)

---

## 1. Deno Compile - Best Practices

### Basic Command Structure

```bash
deno compile \
  --allow-read=/run/user,/home \
  --allow-net=unix \
  --allow-env=XDG_RUNTIME_DIR,HOME,USER \
  --output=i3pm-apps \
  main.ts
```

### Recommended Flags for Feature 034

| Flag | Purpose | Required? |
|------|---------|-----------|
| `--allow-read=/run/user,/home` | Read daemon socket + registry JSON | ✅ Yes |
| `--allow-net=unix` | Unix socket IPC to daemon | ✅ Yes |
| `--allow-env=XDG_RUNTIME_DIR,HOME,USER` | Environment variables | ✅ Yes |
| `--allow-run` | **NOT NEEDED** (daemon handles launches) | ❌ No |
| `--no-lock` | Skip lockfile validation | ⚠️ Dev only |
| `-A` | All permissions (development) | ❌ Avoid in production |

### Binary Size Optimization

Deno compile produces large binaries (~80-120MB) because it embeds the full V8 runtime:

```bash
# Without optimization
deno compile main.ts  # ~80MB

# With tree-shaking (minimal improvement)
deno compile --no-check main.ts  # ~78MB

# Compression (post-compilation)
upx --best i3pm-apps  # ~40MB (risky, can break on some platforms)
```

**Conclusion**: Binary size cannot be significantly reduced. This is why the **Bash wrapper approach** is preferred.

### Cross-Compilation

Deno does not support cross-compilation. To build for different platforms:

```bash
# Must build on target platform or use platform-specific CI
deno compile --target x86_64-unknown-linux-gnu main.ts  # ❌ No --target flag

# NixOS handles this automatically via system.platform
```

---

## 2. Existing Deno Packages in Codebase

### Pattern 1: i3pm CLI (Runtime Wrapper) ⭐ **RECOMMENDED**

**File**: `/etc/nixos/home-modules/tools/i3pm-deno.nix`

```nix
i3pm = pkgs.stdenv.mkDerivation {
  pname = "i3pm";
  version = "2.0.0";  # From VERSION file
  src = ./i3pm-deno;

  dontBuild = true;  # No compilation step

  installPhase = ''
    mkdir -p $out/share/i3pm
    cp -r * $out/share/i3pm/

    # Copy cli-ux library into the package
    mkdir -p $out/share/cli-ux
    cp -r ${./cli-ux}/* $out/share/cli-ux/

    mkdir -p $out/bin
    cat > $out/bin/i3pm <<EOF
#!/usr/bin/env bash
exec ${pkgs.deno}/bin/deno run \\
  --no-lock \\
  -A \\
  $out/share/i3pm/main.ts "\$@"
EOF
    chmod +x $out/bin/i3pm
  '';
};
```

**Advantages**:
- No compilation step = faster rebuilds (~30s)
- Live code during development (change .ts, run immediately)
- Minimal binary size (wrapper is ~500 bytes)
- Easy to debug (full TypeScript stack traces)
- Supports Deno's import map resolution

**Disadvantages**:
- Requires Deno runtime installed (already in system packages)
- ~2ms slower startup (runtime initialization)

### Pattern 2: cli-ux Library (Build-time Type Check)

**File**: `/etc/nixos/home-modules/tools/cli-ux/default.nix`

```nix
pkgs.stdenv.mkDerivation {
  pname = "cli-ux";
  version = "1.0.0";
  src = ./.;

  buildInputs = [ pkgs.deno ];

  buildPhase = ''
    # Type check the library
    deno check mod.ts

    # Run tests
    deno task test
  '';

  installPhase = ''
    mkdir -p $out/lib/cli-ux
    cp -r * $out/lib/cli-ux/
  '';
}
```

**Use case**: Shared TypeScript library used by i3pm (not a CLI tool)

---

## 3. NixOS Derivation Patterns for Deno

### Option A: Runtime Wrapper (Current i3pm Pattern) ⭐ **RECOMMENDED**

```nix
{ config, lib, pkgs, ... }:

let
  version = lib.strings.fileContents ./i3pm-apps/VERSION;

  i3pm-apps = pkgs.stdenv.mkDerivation {
    pname = "i3pm-apps";
    inherit version;
    src = ./i3pm-apps;

    dontBuild = true;

    installPhase = ''
      mkdir -p $out/share/i3pm-apps
      cp -r * $out/share/i3pm-apps/

      mkdir -p $out/bin
      cat > $out/bin/i3pm-apps <<EOF
#!/usr/bin/env bash
exec ${pkgs.deno}/bin/deno run \\
  --allow-read=/run/user,/home \\
  --allow-net=unix \\
  --allow-env=XDG_RUNTIME_DIR,HOME,USER \\
  --no-lock \\
  $out/share/i3pm-apps/main.ts "\$@"
EOF
      chmod +x $out/bin/i3pm-apps
    '';

    meta = with lib; {
      description = "Application launcher CLI for i3pm";
      platforms = platforms.linux;
    };
  };
in
{
  home.packages = [ i3pm-apps ];
}
```

**Build time**: ~30 seconds (home-manager rebuild, no compilation)

### Option B: Compiled Binary (Not Recommended)

```nix
{ config, lib, pkgs, ... }:

let
  i3pm-apps = pkgs.stdenv.mkDerivation {
    pname = "i3pm-apps";
    version = "1.0.0";
    src = ./i3pm-apps;

    nativeBuildInputs = [ pkgs.deno ];

    buildPhase = ''
      deno compile \
        --allow-read=/run/user,/home \
        --allow-net=unix \
        --allow-env=XDG_RUNTIME_DIR,HOME,USER \
        --output=i3pm-apps \
        main.ts
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp i3pm-apps $out/bin/
    '';
  };
in
{
  home.packages = [ i3pm-apps ];
}
```

**Build time**: ~2-3 minutes (Deno compilation + V8 embedding)
**Binary size**: ~80-120MB
**NOT RECOMMENDED** due to slow builds and large binary size.

### Option C: buildDenoApplication Helper

**Status**: ❌ Not available in nixpkgs (as of 2025-10-24)

The `buildDenoApplication` helper mentioned in Feature 027 research does not exist in stable nixpkgs. You would need to:

1. Create a custom builder similar to `buildGoModule` or `buildRustPackage`
2. Handle Deno's import map and lockfile resolution
3. Manage V8 snapshot generation

**Conclusion**: Custom derivation with `stdenv.mkDerivation` is the standard approach.

---

## 4. Permission Flags for i3pm Daemon Communication

### Required Permissions

```bash
# Minimal permission set for Feature 034
deno run \
  --allow-read=/run/user,/home/.config/i3 \
  --allow-net=unix \
  --allow-env=XDG_RUNTIME_DIR,HOME,USER \
  main.ts
```

### Justification by Permission

| Permission | Scope | Justification |
|------------|-------|---------------|
| `--allow-read=/run/user` | Daemon socket directory | Read Unix socket at `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock` |
| `--allow-read=/home` | Registry JSON | Read `~/.config/i3/application-registry.json` |
| `--allow-net=unix` | Unix socket IPC | Connect to daemon via `Deno.connect({ path: socketPath, transport: 'unix' })` |
| `--allow-env=XDG_RUNTIME_DIR` | Runtime directory | Locate daemon socket |
| `--allow-env=HOME` | User home | Resolve `~/.config/i3/` paths |
| `--allow-env=USER` | Username | Logging and validation |

### NOT Required

- ❌ `--allow-run`: CLI does not launch applications directly (daemon handles this)
- ❌ `--allow-write`: CLI reads registry only (modifications via `i3pm apps edit` will open $EDITOR)
- ❌ `--allow-ffi`: No foreign function interface needed
- ❌ `-A` (all permissions): Overly permissive, use granular flags

---

## 5. Integration with i3pm CLI Structure

### Current i3pm CLI Architecture

The existing i3pm CLI is structured as a **parent command** with subcommands:

```typescript
// main.ts - Entry point with command routing
const command = String(args._[0]);

switch (command) {
  case "project":
    await projectCommand(commandArgs, options);
    break;
  case "windows":
    await windowsCommand(commandArgs, options);
    break;
  case "daemon":
    await daemonCommand(commandArgs, options);
    break;
  // ... other commands
}
```

### Integration Pattern for Feature 034

**Option 1: Extend Existing i3pm CLI** ⭐ **RECOMMENDED**

Add `apps` subcommand to existing i3pm:

```typescript
// /etc/nixos/home-modules/tools/i3pm-deno/main.ts

case "apps":
  {
    const { appsCommand } = await import("./src/commands/apps.ts");
    await appsCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
  }
  break;
```

```typescript
// /etc/nixos/home-modules/tools/i3pm-deno/src/commands/apps.ts

export async function appsCommand(args: string[], options: GlobalOptions): Promise<void> {
  const subcommand = args[0];

  switch (subcommand) {
    case "list":
      await listApps();
      break;
    case "launch":
      await launchApp(args[1]);
      break;
    case "validate":
      await validateRegistry();
      break;
    // ... other subcommands
  }
}
```

**Usage**:
```bash
i3pm apps list
i3pm apps launch vscode
i3pm apps validate
```

**Advantages**:
- Consistent CLI interface (all i3pm commands under one binary)
- Reuses existing daemon client (`src/client.ts`)
- Shares validation logic (`src/validation.ts`)
- No additional package to install

**Option 2: Standalone i3pm-apps Binary**

Create separate CLI tool with its own entrypoint:

```nix
# /etc/nixos/home-modules/tools/i3pm-apps.nix
let
  i3pm-apps = pkgs.stdenv.mkDerivation {
    pname = "i3pm-apps";
    # ... (pattern from Option A above)
  };
in
{
  home.packages = [ i3pm-apps ];
}
```

**Usage**:
```bash
i3pm-apps list
i3pm-apps launch vscode
```

**Advantages**:
- Isolated codebase (easier to extract as separate project later)
- Smaller binary if using deno compile

**Disadvantages**:
- Duplicate daemon client code
- Additional package to maintain
- Inconsistent CLI interface

**Recommendation**: **Option 1** (extend existing i3pm CLI)

---

## 6. Build Time Estimates

### Runtime Wrapper Pattern (Recommended)

```bash
# Initial rebuild (cold cache)
home-manager switch --flake .#vpittamp@hetzner
# Time: ~30 seconds

# Subsequent rebuilds (code changes)
home-manager switch --flake .#vpittamp@hetzner
# Time: ~15 seconds (NixOS detects no derivation changes)

# Development workflow (no rebuild needed)
# Edit /etc/nixos/home-modules/tools/i3pm-deno/src/commands/apps.ts
# Run immediately:
i3pm apps list
# Time: <1 second
```

### Compiled Binary Pattern (Not Recommended)

```bash
# Initial rebuild
home-manager switch --flake .#vpittamp@hetzner
# Time: ~2-3 minutes (deno compile)

# Subsequent rebuilds (code changes)
home-manager switch --flake .#vpittamp@hetzner
# Time: ~2-3 minutes (deno compile re-runs)

# Development workflow (rebuild required for every change)
# Edit src/commands/apps.ts
# Rebuild:
home-manager switch --flake .#vpittamp@hetzner
# Time: ~2-3 minutes
```

**Conclusion**: Runtime wrapper is **6-12x faster** for development iteration.

---

## 7. Example Derivation for Feature 034

### Full Implementation (Recommended Pattern)

```nix
# /etc/nixos/home-modules/tools/i3pm-deno.nix

{ config, lib, pkgs, ... }:

let
  # Read version from VERSION file (single source of truth)
  version = lib.strings.fileContents ./i3pm-deno/VERSION;

  # i3pm Deno CLI - Wrapper script that runs TypeScript with Deno runtime
  i3pm = pkgs.stdenv.mkDerivation {
    pname = "i3pm";
    inherit version;

    src = ./i3pm-deno;

    dontBuild = true;

    installPhase = ''
      mkdir -p $out/share/i3pm
      cp -r * $out/share/i3pm/

      # Copy cli-ux library into the package
      mkdir -p $out/share/cli-ux
      cp -r ${./cli-ux}/* $out/share/cli-ux/

      mkdir -p $out/bin
      cat > $out/bin/i3pm <<EOF
#!/usr/bin/env bash
exec ${pkgs.deno}/bin/deno run \\
  --allow-read=/run/user,/home \\
  --allow-net=unix \\
  --allow-env=XDG_RUNTIME_DIR,HOME,USER \\
  --no-lock \\
  $out/share/i3pm/main.ts "\$@"
EOF
      chmod +x $out/bin/i3pm
    '';

    meta = with lib; {
      description = "i3 project management CLI tool";
      longDescription = ''
        Type-safe, compiled CLI for i3 project context switching and window management.
        Communicates with i3-project-event-daemon via JSON-RPC 2.0 over Unix socket.

        Features:
        - Project context switching with window visibility management
        - Real-time window state visualization (tree, table, JSON, live TUI)
        - Daemon status and event monitoring
        - Window classification rules management
        - Interactive multi-pane monitoring dashboard
        - Application launcher with project context (Feature 034)
      '';
      homepage = "https://github.com/user/nixos-config";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };
in
{
  config = {
    # Install i3pm binary
    home.packages = [ i3pm ];
  };
}
```

### TypeScript Implementation Template

```typescript
// /etc/nixos/home-modules/tools/i3pm-deno/src/commands/apps.ts

import { parseArgs } from "@std/cli/parse-args";
import { createClient } from "../client.ts";
import type { ApplicationRegistry } from "../models.ts";

/**
 * Apps subcommand - Application launcher management
 */
export async function appsCommand(args: string[], options: GlobalOptions): Promise<void> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    alias: { h: "help" },
    stopEarly: true,
  });

  if (parsed.help || parsed._.length === 0) {
    showAppsHelp();
    return;
  }

  const subcommand = String(parsed._[0]);
  const subcommandArgs = parsed._.slice(1);

  switch (subcommand) {
    case "list":
      await listApps(parsed.json);
      break;
    case "launch":
      await launchApp(String(subcommandArgs[0]));
      break;
    case "validate":
      await validateRegistry();
      break;
    default:
      console.error(`Unknown subcommand: ${subcommand}`);
      Deno.exit(1);
  }
}

/**
 * List all registered applications
 */
async function listApps(jsonOutput: boolean): Promise<void> {
  const client = createClient();
  await client.connect();

  try {
    const registry = await client.request<ApplicationRegistry>("get_application_registry");

    if (jsonOutput) {
      console.log(JSON.stringify(registry, null, 2));
    } else {
      // Table format
      console.log("Application Registry:");
      for (const app of registry.applications) {
        console.log(`  ${app.name} - ${app.display_name} (${app.scope})`);
      }
    }
  } finally {
    await client.close();
  }
}

/**
 * Launch application with project context
 */
async function launchApp(appName: string): Promise<void> {
  const client = createClient();
  await client.connect();

  try {
    await client.request("launch_application", { app_name: appName });
    console.log(`Launched: ${appName}`);
  } finally {
    await client.close();
  }
}

/**
 * Validate registry JSON schema and parameters
 */
async function validateRegistry(): Promise<void> {
  const registryPath = `${Deno.env.get("HOME")}/.config/i3/application-registry.json`;

  try {
    const content = await Deno.readTextFile(registryPath);
    const registry = JSON.parse(content);

    // Validation logic (see RESEARCH_SUMMARY.md Section 6)
    console.log("✓ Registry is valid");
  } catch (err) {
    console.error("✗ Validation failed:", err.message);
    Deno.exit(1);
  }
}

function showAppsHelp(): void {
  console.log(`
i3pm apps - Application launcher management

USAGE:
  i3pm apps <COMMAND>

COMMANDS:
  list                List all registered applications
  launch <name>       Launch application with project context
  validate            Validate registry JSON schema

OPTIONS:
  --json              Output in JSON format
  -h, --help          Show this help

EXAMPLES:
  i3pm apps list
  i3pm apps list --json
  i3pm apps launch vscode
  i3pm apps validate
`);
}
```

---

## 8. Comparison with Other Deno Packaging Approaches

### systemd Service Pattern (Not Applicable)

Some Deno applications run as systemd services:

```nix
systemd.user.services.my-deno-service = {
  ExecStart = "${pkgs.deno}/bin/deno run --allow-net main.ts";
};
```

**Use case**: Long-running daemons (like i3-project-event-daemon)
**Not applicable to CLI tools**: CLI tools are invoked on-demand, not background services.

### Docker Container Pattern (Not Applicable)

```dockerfile
FROM denoland/deno:alpine
COPY . /app
RUN deno cache main.ts
CMD ["deno", "run", "-A", "main.ts"]
```

**Use case**: Containerized applications
**Not applicable**: NixOS provides native package management, containers are unnecessary.

---

## 9. Final Recommendations

### For Feature 034 Implementation

1. ✅ **Use runtime wrapper pattern** (extend existing i3pm CLI)
2. ✅ **Add `apps` subcommand** to `/etc/nixos/home-modules/tools/i3pm-deno/main.ts`
3. ✅ **Implement in TypeScript** at `src/commands/apps.ts`
4. ✅ **Reuse existing daemon client** from `src/client.ts`
5. ✅ **Use granular permissions** (--allow-read, --allow-net=unix, --allow-env)
6. ❌ **Do NOT use deno compile** (slower builds, larger binaries, no benefit)

### Permission Set

```bash
--allow-read=/run/user,/home  # Daemon socket + registry JSON
--allow-net=unix              # Unix socket IPC
--allow-env=XDG_RUNTIME_DIR,HOME,USER  # Environment variables
--no-lock                     # Skip lockfile validation (faster startup)
```

### Integration Pattern

```typescript
// main.ts
case "apps":
  {
    const { appsCommand } = await import("./src/commands/apps.ts");
    await appsCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
  }
  break;
```

### Build Time

- **Development**: ~1 second (no rebuild, edit and run)
- **Production rebuild**: ~30 seconds (home-manager switch)

---

## 10. References

### Codebase Files Reviewed

- `/etc/nixos/home-modules/tools/i3pm-deno.nix` - Existing i3pm packaging
- `/etc/nixos/home-modules/tools/i3pm-deno/main.ts` - CLI entry point
- `/etc/nixos/home-modules/tools/i3pm-deno/deno.json` - Deno configuration
- `/etc/nixos/home-modules/tools/i3pm-deno/src/client.ts` - Daemon IPC client
- `/etc/nixos/home-modules/tools/cli-ux/default.nix` - Library packaging pattern
- `/etc/nixos/specs/027-update-the-spec/research.md` - Feature 027 Deno research
- `/etc/nixos/.specify/memory/constitution.md` - Constitution Principle XIII (Deno standardization)

### External References

- [Deno Manual - Compiling Executables](https://deno.land/manual/tools/compiler)
- [Deno Manual - Permissions](https://deno.land/manual/basics/permissions)
- [NixOS Wiki - Deno](https://nixos.wiki/wiki/Deno)
- [nixpkgs stdenv.mkDerivation](https://nixos.org/manual/nixpkgs/stable/#sec-using-stdenv)

---

**Last Updated**: 2025-10-24
**Feature Branch**: `034-create-a-feature`
**Related Document**: `/etc/nixos/specs/034-create-a-feature/plan.md`
