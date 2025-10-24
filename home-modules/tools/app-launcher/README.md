# Application Launcher CLI

**Feature**: 034-create-a-feature
**Version**: 1.0.0

Unified application launcher system with project context integration for i3 window manager.

## Overview

This Deno/TypeScript CLI tool provides application management through the `i3pm apps` command:
- Launch applications with project context (`$PROJECT_DIR`, `$PROJECT_NAME`, etc.)
- Manage application registry declaratively
- Validate and edit application definitions
- Query application information

## Development Setup

### Prerequisites

- Deno 1.40+
- NixOS with i3 window manager
- i3pm daemon (Feature 015) running

### Quick Start

```bash
# Install dependencies (handled by Deno)
deno cache main.ts

# Run tests
deno task test

# Lint and format
deno task lint
deno task fmt

# Run CLI locally
deno run --allow-read --allow-env --allow-net=unix main.ts apps list
```

## Project Structure

```
home-modules/tools/app-launcher/
├── deno.json                # Deno configuration
├── main.ts                  # CLI entry point
├── mod.ts                   # Public API exports
├── src/
│   ├── commands/            # CLI subcommands
│   │   ├── list.ts         # i3pm apps list
│   │   ├── launch.ts       # i3pm apps launch
│   │   ├── info.ts         # i3pm apps info
│   │   ├── edit.ts         # i3pm apps edit
│   │   ├── validate.ts     # i3pm apps validate
│   │   ├── add.ts          # i3pm apps add
│   │   └── remove.ts       # i3pm apps remove
│   ├── models.ts            # TypeScript type definitions
│   ├── registry.ts          # Registry loading and validation
│   ├── variables.ts         # Variable substitution logic
│   └── daemon-client.ts     # i3pm daemon IPC client
└── tests/
    ├── unit/                # Unit tests
    │   ├── registry_test.ts
    │   ├── variables_test.ts
    │   └── daemon_client_test.ts
    └── fixtures/            # Test data
        └── sample-registry.json
```

## Architecture

### Data Flow

```
Desktop File (.desktop)
  ↓ Exec=app-launcher-wrapper.sh <app-name>
Wrapper Script (bash)
  ↓ 1. Load registry JSON
  ↓ 2. Query i3pm daemon for project
  ↓ 3. Substitute variables ($PROJECT_DIR, etc.)
  ↓ 4. Execute application
Application (VS Code, etc.)
```

### Variable Substitution

Applications can use these variables in their parameters:

- `$PROJECT_DIR` - Active project directory path
- `$PROJECT_NAME` - Active project name
- `$SESSION_NAME` - Session identifier (same as project name)
- `$WORKSPACE` - Target workspace number
- `$HOME` - User home directory

Example registry entry:
```json
{
  "name": "vscode",
  "display_name": "VS Code",
  "command": "code",
  "parameters": "$PROJECT_DIR",
  "scope": "scoped",
  "expected_class": "Code",
  "preferred_workspace": 1
}
```

When launched with "nixos" project active:
```bash
code /etc/nixos
```

## Commands

### i3pm apps list

List all registered applications:

```bash
i3pm apps list
i3pm apps list --scope=scoped
i3pm apps list --workspace=1
i3pm apps list --format=json
```

### i3pm apps launch

Launch an application with project context:

```bash
i3pm apps launch vscode
i3pm apps launch vscode --dry-run
i3pm apps launch vscode --project=nixos
```

### i3pm apps info

Show application details:

```bash
i3pm apps info vscode
i3pm apps info vscode --resolve
i3pm apps info vscode --format=json
```

### i3pm apps edit

Edit the registry:

```bash
i3pm apps edit
```

### i3pm apps validate

Validate registry:

```bash
i3pm apps validate
i3pm apps validate --check-paths --check-icons
i3pm apps validate --fix
```

### i3pm apps add

Add new application:

```bash
i3pm apps add
i3pm apps add --non-interactive --name=custom-app ...
```

### i3pm apps remove

Remove application:

```bash
i3pm apps remove vscode
i3pm apps remove vscode --force
```

## Testing

```bash
# Run all tests
deno task test

# Run tests with watch mode
deno task test:watch

# Run specific test file
deno test tests/unit/registry_test.ts --allow-read --allow-env
```

## Integration

This tool is packaged via NixOS home-manager:

```nix
# home-modules/tools/app-launcher.nix
stdenv.mkDerivation {
  name = "app-launcher";
  src = ./app-launcher;

  installPhase = ''
    mkdir -p $out/bin $out/share/app-launcher
    cp -r src $out/share/app-launcher/
    cp main.ts mod.ts deno.json $out/share/app-launcher/

    # Runtime wrapper
    cat > $out/bin/i3pm-apps <<EOF
#!/usr/bin/env bash
exec ${pkgs.deno}/bin/deno run \
  --allow-read=/run/user,/home \
  --allow-net=unix \
  --allow-env=XDG_RUNTIME_DIR,HOME,USER \
  --no-lock \
  $out/share/app-launcher/main.ts "\$@"
EOF
    chmod +x $out/bin/i3pm-apps
  '';
}
```

## Documentation

- **Specification**: `/etc/nixos/specs/034-create-a-feature/spec.md`
- **Implementation Plan**: `/etc/nixos/specs/034-create-a-feature/plan.md`
- **Data Model**: `/etc/nixos/specs/034-create-a-feature/data-model.md`
- **Quickstart Guide**: `/etc/nixos/specs/034-create-a-feature/quickstart.md`
- **CLI API Contract**: `/etc/nixos/specs/034-create-a-feature/contracts/cli-api.md`
- **Wrapper Protocol**: `/etc/nixos/specs/034-create-a-feature/contracts/launcher-protocol.md`

## License

Part of the NixOS configuration repository.
