# Quick Answers - Feature 034 Deno CLI Tool

**Date**: 2025-10-24
**Context**: Building `i3pm apps` subcommand for Feature 034

---

## TL;DR - What You Need to Know

**DON'T use `deno compile`** - Use the runtime wrapper pattern instead.

**Recommended approach**:
1. Extend existing `i3pm` CLI (add `apps` subcommand)
2. Use runtime wrapper (already in place)
3. Build time: ~30 seconds (vs 2-3 minutes with compilation)
4. Binary size: ~500 bytes wrapper (vs ~80MB compiled)

---

## 1. deno compile Command with Recommended Flags

### Basic Command

```bash
deno compile \
  --allow-read=/run/user,/home \
  --allow-net=unix \
  --allow-env=XDG_RUNTIME_DIR,HOME,USER \
  --output=i3pm-apps \
  main.ts
```

### Flag Breakdown

| Flag | Why? | Required? |
|------|------|-----------|
| `--allow-read=/run/user` | Read daemon socket | ✅ Yes |
| `--allow-read=/home` | Read `~/.config/i3/application-registry.json` | ✅ Yes |
| `--allow-net=unix` | Unix socket IPC to daemon | ✅ Yes |
| `--allow-env=XDG_RUNTIME_DIR` | Find socket path | ✅ Yes |
| `--allow-env=HOME` | Resolve `~/.config/i3/` | ✅ Yes |
| `--allow-env=USER` | Logging/validation | ✅ Yes |
| `--allow-run` | Launch applications | ❌ No (daemon does this) |

### Binary Size Reality Check

```bash
deno compile main.ts
# Result: ~80-120MB (embeds full V8 runtime)

# Optimization attempts:
deno compile --no-check main.ts  # ~78MB (minimal difference)
upx --best i3pm-apps             # ~40MB (risky, can break)
```

**Conclusion**: Cannot meaningfully reduce binary size. This is why **runtime wrapper is better**.

---

## 2. Existing Deno Packages in Codebase

### Found: i3pm CLI (Production, 2.0.0)

**File**: `/etc/nixos/home-modules/tools/i3pm-deno.nix`

**Pattern**: Runtime wrapper (NOT compiled)

```nix
i3pm = pkgs.stdenv.mkDerivation {
  pname = "i3pm";
  version = "2.0.0";
  src = ./i3pm-deno;

  dontBuild = true;  # ← No compilation

  installPhase = ''
    mkdir -p $out/share/i3pm
    cp -r * $out/share/i3pm/

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

**Why this pattern?**
- ✅ Fast rebuilds (~30s vs 2-3 min)
- ✅ Live code editing (no rebuild needed)
- ✅ Minimal wrapper size (~500 bytes)
- ✅ Full TypeScript stack traces
- ✅ Supports Deno import maps

**Current commands**:
```bash
i3pm project list
i3pm windows --live
i3pm daemon status
i3pm layout save
i3pm rules list
i3pm monitors config show
```

**You will extend this** by adding `i3pm apps` subcommand.

### Found: cli-ux Library (Shared Dependency)

**File**: `/etc/nixos/home-modules/tools/cli-ux/default.nix`

```nix
pkgs.stdenv.mkDerivation {
  pname = "cli-ux";
  version = "1.0.0";
  src = ./.;

  buildInputs = [ pkgs.deno ];

  buildPhase = ''
    deno check mod.ts  # Type check
    deno task test     # Run tests
  '';

  installPhase = ''
    mkdir -p $out/lib/cli-ux
    cp -r * $out/lib/cli-ux/
  '';
}
```

**Use case**: Shared TypeScript library (not a CLI tool)

---

## 3. NixOS Derivation Patterns

### Pattern A: Runtime Wrapper ⭐ **USE THIS**

```nix
{ config, lib, pkgs, ... }:

let
  version = lib.strings.fileContents ./i3pm-deno/VERSION;

  i3pm = pkgs.stdenv.mkDerivation {
    pname = "i3pm";
    inherit version;
    src = ./i3pm-deno;

    dontBuild = true;

    installPhase = ''
      mkdir -p $out/share/i3pm
      cp -r * $out/share/i3pm/

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
  };
in
{
  home.packages = [ i3pm ];
}
```

**Build time**: ~30 seconds
**Binary size**: ~500 bytes (wrapper script)

### Pattern B: Compiled Binary (DON'T USE)

```nix
{ config, lib, pkgs, ... }:

let
  i3pm = pkgs.stdenv.mkDerivation {
    pname = "i3pm";
    version = "1.0.0";
    src = ./i3pm-deno;

    nativeBuildInputs = [ pkgs.deno ];

    buildPhase = ''
      deno compile \
        --allow-read=/run/user,/home \
        --allow-net=unix \
        --allow-env=XDG_RUNTIME_DIR,HOME,USER \
        --output=i3pm \
        main.ts
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp i3pm $out/bin/
    '';
  };
in
{
  home.packages = [ i3pm ];
}
```

**Build time**: ~2-3 minutes (6-12x slower)
**Binary size**: ~80-120MB
**NOT RECOMMENDED**

### buildDenoApplication Helper

**Status**: ❌ Does not exist in nixpkgs

You would need to create a custom builder (like `buildGoModule`). Not worth the effort for this project.

---

## 4. Permission Flags Justification

### Minimal Permission Set

```bash
deno run \
  --allow-read=/run/user,/home/.config/i3 \
  --allow-net=unix \
  --allow-env=XDG_RUNTIME_DIR,HOME,USER \
  main.ts
```

### Detailed Justification

| Permission | What it allows | Why needed | Security impact |
|------------|----------------|------------|-----------------|
| `--allow-read=/run/user` | Read files in `/run/user/<uid>/` | Access daemon socket at `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock` | Low - Only runtime dir |
| `--allow-read=/home` | Read files in user home | Read `~/.config/i3/application-registry.json` | Medium - User files only |
| `--allow-net=unix` | Unix socket connections | Connect to daemon via `Deno.connect({ path: socketPath, transport: 'unix' })` | Low - Unix sockets only, no TCP |
| `--allow-env=XDG_RUNTIME_DIR` | Read this env var | Locate daemon socket path | Low - Standard XDG var |
| `--allow-env=HOME` | Read this env var | Resolve `~/.config/i3/` paths | Low - Standard env var |
| `--allow-env=USER` | Read this env var | Logging and validation | Low - Username only |

### Permissions NOT Needed

| Permission | Why NOT needed |
|------------|----------------|
| `--allow-run` | Daemon launches applications, CLI just sends RPC requests |
| `--allow-write` | CLI reads registry only. Editing uses `$EDITOR` (external process) |
| `--allow-ffi` | No foreign function interface needed |
| `--allow-hrtime` | No high-resolution timing needed |
| `-A` (all) | Overly permissive, use granular flags |

### Current i3pm Permissions (for comparison)

The existing i3pm CLI uses `-A` (all permissions):

```bash
exec ${pkgs.deno}/bin/deno run \\
  --no-lock \\
  -A \\
  $out/share/i3pm/main.ts "\$@"
```

**Why?** Convenience during rapid development. You could restrict to the minimal set above.

---

## 5. Integration with i3pm CLI Structure

### Current i3pm Architecture

```typescript
// /etc/nixos/home-modules/tools/i3pm-deno/main.ts

async function main(): Promise<void> {
  const args = parseArgs(Deno.args, {
    boolean: ["help", "version", "verbose", "debug"],
    stopEarly: true,
  });

  const command = String(args._[0]);

  // Route to command handler
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
    case "layout":
      await layoutCommand(commandArgs, options);
      break;
    case "rules":
      await rulesCommand(commandArgs, options);
      break;
    // ... more commands
  }
}
```

### How to Add `apps` Subcommand

**Step 1**: Update main.ts routing

```typescript
// /etc/nixos/home-modules/tools/i3pm-deno/main.ts

case "apps":
  {
    const { appsCommand } = await import("./src/commands/apps.ts");
    await appsCommand(commandArgs, { verbose: args.verbose, debug: args.debug });
  }
  break;
```

**Step 2**: Create apps.ts command file

```typescript
// /etc/nixos/home-modules/tools/i3pm-deno/src/commands/apps.ts

import { parseArgs } from "@std/cli/parse-args";
import { createClient } from "../client.ts";

export async function appsCommand(args: string[], options: GlobalOptions): Promise<void> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    stopEarly: true,
  });

  const subcommand = String(parsed._[0]);

  switch (subcommand) {
    case "list":
      await listApps(parsed.json);
      break;
    case "launch":
      await launchApp(String(parsed._[1]));
      break;
    case "validate":
      await validateRegistry();
      break;
  }
}

async function listApps(jsonOutput: boolean): Promise<void> {
  const client = createClient();
  await client.connect();

  try {
    const registry = await client.request("get_application_registry");
    // Display applications...
  } finally {
    await client.close();
  }
}
```

**Step 3**: Use immediately (no rebuild needed)

```bash
# Edit the .ts file
nvim /etc/nixos/home-modules/tools/i3pm-deno/src/commands/apps.ts

# Run immediately (wrapper executes TypeScript directly)
i3pm apps list
```

**Step 4**: Rebuild for production

```bash
sudo nixos-rebuild switch --flake .#hetzner
# Time: ~30 seconds
```

### Usage Examples

```bash
# List all registered applications
i3pm apps list

# List with JSON output
i3pm apps list --json

# Launch application with project context
i3pm apps launch vscode

# Validate registry schema
i3pm apps validate

# Show help
i3pm apps --help
```

---

## 6. Build Time Estimate

### Development Workflow (Runtime Wrapper)

```bash
# 1. Edit TypeScript code
nvim /etc/nixos/home-modules/tools/i3pm-deno/src/commands/apps.ts

# 2. Run immediately (NO REBUILD NEEDED)
i3pm apps list
# Time: <1 second

# 3. Edit again, run again
nvim src/commands/apps.ts
i3pm apps list
# Time: <1 second
```

**Total time**: Instant feedback loop

### Production Rebuild (Runtime Wrapper)

```bash
# After code is stable, rebuild for NixOS generation
sudo nixos-rebuild switch --flake .#hetzner

# Time breakdown:
# - NixOS evaluation: ~5 seconds
# - Derivation build: ~5 seconds (copy files, generate wrapper)
# - Activation: ~20 seconds
# Total: ~30 seconds
```

### Comparison: Compiled Binary (NOT RECOMMENDED)

```bash
# Every code change requires full rebuild
nvim src/commands/apps.ts
sudo nixos-rebuild switch --flake .#hetzner

# Time breakdown:
# - NixOS evaluation: ~5 seconds
# - Deno compilation: ~120 seconds (V8 embedding)
# - Activation: ~20 seconds
# Total: ~145 seconds (2.4 minutes)
```

**Development time multiplier**: 145x slower (145 seconds vs 1 second)

---

## Summary Table

| Aspect | Runtime Wrapper | Compiled Binary |
|--------|----------------|-----------------|
| **Build time (initial)** | ~30 seconds | ~2-3 minutes |
| **Build time (rebuild)** | ~15 seconds | ~2-3 minutes |
| **Dev feedback loop** | <1 second | ~2-3 minutes |
| **Binary size** | ~500 bytes | ~80-120MB |
| **Requires Deno** | Yes (in system packages) | No |
| **Startup time** | +2ms (runtime init) | Instant |
| **Debugging** | Full TypeScript traces | Compiled traces |
| **Recommended?** | ✅ Yes | ❌ No |

---

## Recommended Actions

1. ✅ **Extend existing i3pm CLI** (add `apps` subcommand)
2. ✅ **Use runtime wrapper pattern** (already in place)
3. ✅ **Reuse daemon client** from `src/client.ts`
4. ✅ **Use minimal permissions** (--allow-read, --allow-net=unix, --allow-env)
5. ❌ **Do NOT use deno compile** (slower, larger, no benefit)

---

## Next Steps

1. Read `/etc/nixos/specs/034-create-a-feature/DENO_PACKAGING_RESEARCH.md` (full details)
2. Create `/etc/nixos/home-modules/tools/i3pm-deno/src/commands/apps.ts`
3. Update `/etc/nixos/home-modules/tools/i3pm-deno/main.ts` (add case "apps")
4. Test: `i3pm apps list` (no rebuild needed)
5. Rebuild: `sudo nixos-rebuild switch --flake .#hetzner` (~30s)

---

**Last Updated**: 2025-10-24
**See Also**: `DENO_PACKAGING_RESEARCH.md` (comprehensive details)
