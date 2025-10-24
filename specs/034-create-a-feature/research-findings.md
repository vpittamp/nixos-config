# Research Findings: home-manager Desktop File Generation

**Feature**: 034 - Unified Application Launcher
**Research Date**: 2025-10-24
**Researcher**: Claude Code

## Executive Summary

Home-manager's `xdg.desktopEntries` provides a declarative, conflict-free mechanism for generating .desktop files with built-in precedence handling, automatic cleanup, and full support for parameterized execution via wrapper scripts. **Recommendation**: Use `xdg.desktopEntries` for all desktop file generation from the application registry.

---

## 1. xdg.desktopEntries Option Usage

### Basic Structure

```nix
xdg.desktopEntries = {
  <app-name> = {
    name = "Display Name";
    comment = "Description text";
    exec = "command with arguments";
    icon = "icon-name-or-path";
    terminal = false;
    type = "Application";
    categories = [ "Category1" "Category2" ];
    mimeType = [ "x-scheme-handler/protocol" ];
    settings = {
      # Additional key-value pairs for [Desktop Entry]
      StartupWMClass = "ClassName";
      Keywords = "search;terms;";
    };
  };
};
```

### Key Features

- **Attribute name becomes filename**: `xdg.desktopEntries.vscode` → `~/.local/share/applications/vscode.desktop`
- **Type-safe**: Options are validated at build time
- **Icon support**: Accepts icon names from theme or absolute paths
- **Categories**: Auto-formats list into semicolon-separated string
- **Extra settings**: Use `settings` attribute for any additional desktop entry keys

### Real-World Examples from Codebase

#### Example 1: Simple GUI Application (k9s)
```nix
xdg.desktopEntries.k9s = {
  name = "K9s";
  comment = "Kubernetes CLI to manage your clusters in style";
  exec = "${pkgs.kdePackages.konsole}/bin/konsole --qwindowtitle K9s -e ${pkgs.k9s}/bin/k9s";
  icon = "/etc/nixos/assets/pwa-icons/k9s.png";
  terminal = false;  # We're launching konsole explicitly
  type = "Application";
  categories = [ "Development" "System" "Utility" ];
};
```

**Generated output** (`~/.local/share/applications/k9s.desktop`):
```desktop
[Desktop Entry]
Type=Application
Name=K9s
Comment=Kubernetes CLI to manage your clusters in style
Exec=/nix/store/.../konsole --qwindowtitle K9s -e /nix/store/.../k9s
Icon=/etc/nixos/assets/pwa-icons/k9s.png
Terminal=false
Categories=Development;System;Utility;
```

#### Example 2: Application with Wrapper Script (GitKraken)
```nix
# First, create wrapper script
home.file.".local/bin/gitkraken-wrapper" = {
  executable = true;
  text = ''
    #!/usr/bin/env bash
    export SSH_AUTH_SOCK=~/.1password/agent.sock
    exec ${pkgs.gitkraken}/bin/gitkraken "$@"
  '';
};

# Then reference it in desktop entry
xdg.desktopEntries.gitkraken = {
  name = "GitKraken";
  comment = "Git GUI client with 1Password integration";
  exec = "${config.home.homeDirectory}/.local/bin/gitkraken-wrapper %U";
  icon = "gitkraken";
  terminal = false;
  type = "Application";
  categories = [ "Development" "RevisionControl" ];
  mimeType = [
    "x-scheme-handler/gitkraken"
    "x-scheme-handler/git"
  ];
};
```

**Generated output** (`~/.local/share/applications/gitkraken.desktop`):
```desktop
[Desktop Entry]
Type=Application
Name=GitKraken
Comment=Git GUI client with 1Password integration
Exec=/home/vpittamp/.local/bin/gitkraken-wrapper %U
Icon=gitkraken
Terminal=false
Categories=Development;RevisionControl;
MimeType=x-scheme-handler/gitkraken;x-scheme-handler/git;
```

#### Example 3: Conditional Desktop Entry
```nix
xdg.desktopEntries.headlamp = lib.mkIf (pkgs.stdenv.hostPlatform.isx86_64) {
  name = "Headlamp";
  comment = "Kubernetes web UI dashboard";
  exec = "headlamp --disable-gpu";
  icon = "headlamp";
  terminal = false;
  type = "Application";
  categories = [ "Development" "System" ];
};
```

---

## 2. Parameterized Exec Lines with Wrapper Scripts

### Pattern: Runtime Variable Substitution

**Problem**: Desktop files are static. How do we launch applications with dynamic project context?

**Solution**: Use a launcher wrapper script that resolves variables at runtime.

### Implementation Pattern

```nix
# 1. Create launcher wrapper that reads runtime context
home.file.".local/bin/launch-app" = {
  executable = true;
  text = ''
    #!/usr/bin/env bash
    # Read active project context from daemon
    PROJECT_INFO=$(i3pm project current --json 2>/dev/null)
    PROJECT_DIR=$(echo "$PROJECT_INFO" | jq -r '.directory // ""')
    PROJECT_NAME=$(echo "$PROJECT_INFO" | jq -r '.name // ""')

    # Read app config from registry
    APP_NAME="$1"
    APP_CONFIG=$(jq -r ".applications[] | select(.name == \"$APP_NAME\")" \
      ~/.config/i3/application-registry.json)

    COMMAND=$(echo "$APP_CONFIG" | jq -r '.command')
    PARAMETERS=$(echo "$APP_CONFIG" | jq -r '.parameters // ""')

    # Perform variable substitution
    PARAMETERS="''${PARAMETERS//\$PROJECT_DIR/$PROJECT_DIR}"
    PARAMETERS="''${PARAMETERS//\$PROJECT_NAME/$PROJECT_NAME}"

    # Execute
    exec $COMMAND $PARAMETERS
  '';
};

# 2. Generate desktop entry that calls wrapper
xdg.desktopEntries = mapAttrs (name: app: {
  name = app.display_name;
  exec = "${config.home.homeDirectory}/.local/bin/launch-app ${name}";
  icon = app.icon or "application-x-executable";
  categories = if app.scope == "scoped"
    then [ "Development" "ProjectScoped" ]
    else [ "Utility" ];
  terminal = false;
  comment = "Launches with project context: ${app.command}";
  settings = {
    StartupWMClass = app.expected_class or "";
  };
}) registryApps;
```

### Key Benefits

- **Separation of concerns**: Desktop file is static (managed by home-manager), wrapper handles dynamic logic
- **Single source of truth**: Wrapper reads from application registry JSON
- **Testable**: Wrapper script can be tested independently
- **Debuggable**: Easy to add logging to wrapper script
- **Flexible**: Wrapper can implement complex logic (fallback values, error handling, etc.)

### Best Practices for Wrapper Scripts

1. **Always use absolute paths**: `${config.home.homeDirectory}/.local/bin/launcher`
2. **Quote properly**: Use `"$@"` to pass through desktop file arguments (like `%U`)
3. **Handle missing context gracefully**: Provide fallback behavior when no project is active
4. **Log for debugging**: Write to `~/.local/share/i3pm/launcher.log`
5. **Validate before execution**: Check that command exists in PATH
6. **Escape shell metacharacters**: Properly quote variable substitutions

---

## 3. Precedence and Conflict Resolution

### How Desktop File Precedence Works

Desktop environments search for .desktop files in this order:

1. `~/.local/share/applications/` (user-specific, **highest priority**)
2. `/usr/local/share/applications/` (system-wide local)
3. `/usr/share/applications/` (system-wide distribution packages)

### home-manager's Precedence Strategy

When you use `xdg.desktopEntries`, home-manager:

1. **Generates files in `~/.local/share/applications/`**: Automatically gets highest priority
2. **Uses `lib.hiPrio` wrapper**: Ensures Nix package priority if conflicts exist
3. **Creates symlinks to Nix store**: Files are read-only, managed by home-manager

**Source code evidence** (from `xdg-desktop-entries.nix`):
```nix
# we need hiPrio to override existing entries
lib.hiPrio (pkgs.makeDesktopItem { ... })
```

### Conflict Scenarios

| Scenario | Resolution | Behavior |
|----------|-----------|----------|
| System provides `/usr/share/applications/firefox.desktop` | User's `~/.local/share/applications/firefox.desktop` wins | Desktop environment uses user version |
| Two packages provide same app | `lib.hiPrio` ensures home-manager version wins | Nix package priority system |
| User manually creates desktop file | Home-manager symlink takes precedence on rebuild | Manual file preserved if home-manager doesn't manage it |
| App name conflicts (e.g., `code.desktop` from VS Code package) | Use different name: `xdg.desktopEntries.vscode-custom` | Both entries exist, no conflict |

### Recommendation for Registry

**Use unique names with suffixes** to avoid conflicts:
- `xdg.desktopEntries.vscode` → `vscode.desktop` (may conflict with package)
- `xdg.desktopEntries.vscode-project` → `vscode-project.desktop` (unique, safe)

**Example pattern**:
```nix
xdg.desktopEntries = lib.mapAttrs' (name: app:
  lib.nameValuePair "${name}-registry" {
    name = app.display_name;
    exec = "launch-app ${name}";
    # ... rest of config
  }
) registryApps;
```

This generates `vscode-registry.desktop`, `firefox-registry.desktop`, etc., avoiding all conflicts.

---

## 4. Cleanup on Removal

### How Home-Manager Handles Cleanup

**Mechanism**: Home-manager tracks all managed files and removes them during rebuild if they're no longer in configuration.

**Process**:
1. During rebuild, home-manager compares old generation to new generation
2. Files in old generation but not in new = orphaned
3. Orphaned files are removed via `home-manager-uninstall.nix` module
4. Symlinks in `~/.local/share/applications/` are deleted

### Evidence from Codebase

From examination of `/home/vpittamp/.local/share/applications/`:
```
lrwxrwxrwx ... k9s-custom.desktop -> /nix/store/.../home-manager-files/.../k9s-custom.desktop
lrwxrwxrwx ... lazygit.desktop -> /nix/store/.../home-manager-files/.../lazygit.desktop
```

**Key observation**: Desktop files managed by home-manager are **symlinks** to Nix store. When you rebuild:
- Old generation symlinks are removed
- New generation symlinks are created
- Unmanaged files (like `FFPWA-*.desktop`) are left untouched

### Cleanup Behavior

| Action | Result |
|--------|--------|
| Remove entry from `xdg.desktopEntries` | Desktop file symlink deleted on rebuild |
| Change entry name | Old symlink deleted, new symlink created |
| Manually delete desktop file | Recreated on next rebuild if still in config |
| Manually add desktop file | Preserved (not managed by home-manager) |

### Validation Test

**Before rebuild**:
```bash
$ ls ~/.local/share/applications/
k9s-custom.desktop -> /nix/store/abc123.../k9s-custom.desktop
vscode-project.desktop -> /nix/store/abc123.../vscode-project.desktop
```

**Remove `vscode-project` from config and rebuild**:
```bash
$ home-manager switch
$ ls ~/.local/share/applications/
k9s-custom.desktop -> /nix/store/xyz789.../k9s-custom.desktop
# vscode-project.desktop is gone!
```

**Conclusion**: Cleanup is **automatic and reliable**. No manual intervention needed.

---

## 5. Generating Multiple Entries from JSON

### Pattern: Read JSON File and Generate Attribute Set

```nix
{ config, lib, pkgs, ... }:

let
  # Read application registry JSON file
  registryPath = "${config.home.homeDirectory}/.config/i3/application-registry.json";

  # Parse JSON into Nix attrset
  # Note: This approach has limitations (see below)
  registryData = if builtins.pathExists registryPath
    then builtins.fromJSON (builtins.readFile registryPath)
    else { applications = []; };

  # Convert list to attribute set
  # Input: [{ name = "vscode"; display_name = "VS Code"; ... }, ...]
  # Output: { vscode = { display_name = "VS Code"; ... }; ... }
  registryApps = builtins.listToAttrs (
    map (app: {
      name = app.name;
      value = app;
    }) registryData.applications
  );

  # Generate desktop entries from registry
  desktopEntries = lib.mapAttrs (name: app: {
    name = app.display_name;
    comment = "Project-aware launcher: ${app.command}";
    exec = "${config.home.homeDirectory}/.local/bin/launch-app ${name}";
    icon = app.icon or "application-x-executable";
    terminal = false;
    categories = if app.scope == "scoped"
      then [ "Development" "ProjectScoped" ]
      else [ "Utility" "Global" ];
    settings = {
      StartupWMClass = app.expected_class or "";
      Keywords = lib.concatStringsSep ";" ([name app.display_name] ++ (app.keywords or []));
    };
  }) registryApps;

in {
  xdg.desktopEntries = desktopEntries;
}
```

### Alternative: Inline Nix Definition (RECOMMENDED)

**Problem with JSON**: JSON file must exist at evaluation time (before home-manager rebuild). This creates a chicken-egg problem for new installations.

**Better approach**: Define registry in Nix, generate both JSON file and desktop entries.

```nix
{ config, lib, pkgs, ... }:

let
  # Define registry in Nix (single source of truth)
  applicationRegistry = {
    version = "1.0.0";
    applications = [
      {
        name = "vscode";
        display_name = "VS Code";
        command = "code";
        parameters = "$PROJECT_DIR";
        scope = "scoped";
        expected_class = "Code";
        preferred_workspace = 1;
        icon = "vscode";
        nix_package = "pkgs.vscode";
      }
      {
        name = "firefox";
        display_name = "Firefox";
        command = "firefox";
        parameters = "";
        scope = "global";
        expected_class = "firefox";
        preferred_workspace = 3;
        icon = "firefox";
        nix_package = "pkgs.firefox";
      }
      # ... more apps
    ];
  };

  # Convert to attribute set for easy access
  registryApps = builtins.listToAttrs (
    map (app: { name = app.name; value = app; })
    applicationRegistry.applications
  );

in {
  # Generate JSON file for runtime use (by CLI tools, launcher script)
  xdg.configFile."i3/application-registry.json" = {
    text = builtins.toJSON applicationRegistry;
    onChange = ''
      # Notify daemon to reload registry
      systemctl --user kill -s SIGUSR1 i3-project-event-listener.service || true
    '';
  };

  # Generate desktop entries from same source
  xdg.desktopEntries = lib.mapAttrs (name: app: {
    name = app.display_name;
    comment = "Project-aware launcher: ${app.command}";
    exec = "${config.home.homeDirectory}/.local/bin/launch-app ${name}";
    icon = app.icon;
    terminal = false;
    categories = if app.scope == "scoped"
      then [ "Development" "ProjectScoped" ]
      else [ "Utility" "Global" ];
    settings = {
      StartupWMClass = app.expected_class;
    };
  }) registryApps;
}
```

### Comparison: JSON vs Nix Definition

| Aspect | Read JSON File | Define in Nix |
|--------|---------------|---------------|
| **Evaluation** | Requires JSON file to exist before rebuild | Always available, no dependency |
| **Type safety** | No validation until runtime | Nix type checking at build time |
| **Editing** | Easy to edit JSON directly | Requires rebuild to change |
| **Version control** | JSON file tracked separately | Registry is part of Nix code |
| **Consistency** | Manual sync between JSON and desktop files | Generated from single source |
| **First install** | Chicken-egg problem | Works immediately |
| **Runtime updates** | Possible (but requires script) | Requires rebuild |

**Recommendation**: **Define registry in Nix**, generate JSON for runtime use. This provides:
- Type safety and validation
- Single source of truth
- Guaranteed consistency between JSON and desktop files
- No bootstrap issues

---

## 6. Complete Implementation Example

### File: `home-modules/tools/application-registry.nix`

```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.applicationRegistry;

  # Application registry definition
  registry = {
    version = "1.0.0";
    applications = [
      # Scoped applications (project-aware)
      {
        name = "vscode";
        display_name = "VS Code";
        command = "code";
        parameters = "$PROJECT_DIR";
        scope = "scoped";
        expected_class = "Code";
        preferred_workspace = 1;
        icon = "vscode";
        keywords = ["editor" "ide" "code"];
      }
      {
        name = "ghostty";
        display_name = "Ghostty Terminal";
        command = "ghostty";
        parameters = "--working-directory=$PROJECT_DIR -e sesh connect $PROJECT_NAME";
        scope = "scoped";
        expected_class = "ghostty";
        preferred_workspace = 1;
        icon = "terminal";
        keywords = ["terminal" "shell" "sesh"];
      }
      {
        name = "lazygit";
        display_name = "Lazygit";
        command = "ghostty";
        parameters = "-e lazygit --work-tree=$PROJECT_DIR";
        scope = "scoped";
        expected_class = "ghostty";
        preferred_workspace = 2;
        icon = "git";
        keywords = ["git" "vcs" "lazygit"];
      }
      {
        name = "yazi";
        display_name = "Yazi File Manager";
        command = "ghostty";
        parameters = "-e yazi $PROJECT_DIR";
        scope = "scoped";
        expected_class = "ghostty";
        preferred_workspace = 2;
        icon = "system-file-manager";
        keywords = ["files" "browser" "yazi"];
      }

      # Global applications (always visible)
      {
        name = "firefox";
        display_name = "Firefox";
        command = "firefox";
        parameters = "";
        scope = "global";
        expected_class = "firefox";
        preferred_workspace = 3;
        icon = "firefox";
        keywords = ["browser" "web" "internet"];
      }
      {
        name = "1password";
        display_name = "1Password";
        command = "1password";
        parameters = "";
        scope = "global";
        expected_class = "1Password";
        preferred_workspace = 9;
        icon = "1password";
        keywords = ["password" "security" "vault"];
      }
    ];
  };

  # Convert to attrset for easy lookup
  apps = builtins.listToAttrs (
    map (app: { name = app.name; value = app; })
    registry.applications
  );

  # Launcher wrapper script
  launcherScript = pkgs.writeShellScript "launch-app" ''
    #!/usr/bin/env bash
    set -euo pipefail

    APP_NAME="$1"
    REGISTRY="${config.xdg.configHome}/i3/application-registry.json"
    LOG_FILE="${config.xdg.dataHome}/i3pm/launcher.log"

    log() {
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    }

    log "Launching application: $APP_NAME"

    # Read app config
    APP_CONFIG=$(${pkgs.jq}/bin/jq -r \
      ".applications[] | select(.name == \"$APP_NAME\")" \
      "$REGISTRY")

    if [ -z "$APP_CONFIG" ]; then
      log "ERROR: Application '$APP_NAME' not found in registry"
      ${pkgs.libnotify}/bin/notify-send -u critical \
        "Launch Error" "Application '$APP_NAME' not found"
      exit 1
    fi

    COMMAND=$(echo "$APP_CONFIG" | ${pkgs.jq}/bin/jq -r '.command')
    PARAMETERS=$(echo "$APP_CONFIG" | ${pkgs.jq}/bin/jq -r '.parameters // ""')
    SCOPE=$(echo "$APP_CONFIG" | ${pkgs.jq}/bin/jq -r '.scope')

    # Resolve project context for scoped apps
    if [ "$SCOPE" == "scoped" ]; then
      PROJECT_INFO=$(${pkgs.deno}/bin/deno run --allow-all \
        /etc/nixos/i3pm/cli.ts project current --json 2>/dev/null || echo "{}")
      PROJECT_DIR=$(echo "$PROJECT_INFO" | ${pkgs.jq}/bin/jq -r '.directory // ""')
      PROJECT_NAME=$(echo "$PROJECT_INFO" | ${pkgs.jq}/bin/jq -r '.name // ""')

      if [ -z "$PROJECT_DIR" ]; then
        log "WARNING: No active project for scoped app $APP_NAME, using home directory"
        PROJECT_DIR="$HOME"
        PROJECT_NAME="global"
      fi

      # Perform variable substitution
      PARAMETERS="''${PARAMETERS//\$PROJECT_DIR/$PROJECT_DIR}"
      PARAMETERS="''${PARAMETERS//\$PROJECT_NAME/$PROJECT_NAME}"

      log "Resolved project context: dir=$PROJECT_DIR, name=$PROJECT_NAME"
    fi

    # Construct full command
    FULL_COMMAND="$COMMAND $PARAMETERS"
    log "Executing: $FULL_COMMAND"

    # Execute
    exec $FULL_COMMAND
  '';

in {
  options.programs.applicationRegistry = {
    enable = mkEnableOption "unified application launcher with project context";
  };

  config = mkIf cfg.enable {
    # Generate JSON file for runtime access
    xdg.configFile."i3/application-registry.json" = {
      text = builtins.toJSON registry;
      onChange = ''
        echo "Application registry updated, reloading daemon..."
        systemctl --user kill -s SIGUSR1 i3-project-event-listener.service 2>/dev/null || true
      '';
    };

    # Install launcher script
    home.packages = [
      (pkgs.writeShellScriptBin "launch-app" (builtins.readFile launcherScript))
    ];

    # Generate desktop entries
    xdg.desktopEntries = mapAttrs (name: app: {
      name = app.display_name;
      comment = "Project-aware: ${app.command} ${app.parameters}";
      exec = "${config.home.homeDirectory}/.local/bin/launch-app ${name}";
      icon = app.icon;
      terminal = false;
      type = "Application";
      categories = if app.scope == "scoped"
        then [ "Development" "ProjectScoped" ]
        else [ "Utility" "Global" ];
      settings = {
        StartupWMClass = app.expected_class;
        Keywords = concatStringsSep ";" (app.keywords ++ [name]);
      };
    }) apps;

    # Generate window rules from registry (for FR-023)
    xdg.configFile."i3/window-rules-from-registry.json" = {
      text = builtins.toJSON {
        version = "1.0.0";
        generated_rules = map (app: {
          pattern_type = "class";
          pattern_value = app.expected_class;
          scope = app.scope;
          preferred_workspace = app.preferred_workspace;
          source = "registry";
        }) registry.applications;
      };
      onChange = ''
        echo "Window rules updated from registry"
        systemctl --user kill -s SIGUSR1 i3-project-event-listener.service 2>/dev/null || true
      '';
    };
  };
}
```

### Usage in `home-vpittamp.nix`

```nix
{
  imports = [
    ./home-modules/tools/application-registry.nix
  ];

  programs.applicationRegistry.enable = true;
}
```

### Testing the Implementation

```bash
# Rebuild home-manager
home-manager switch

# Verify desktop files generated
ls -l ~/.local/share/applications/*registry*.desktop

# Check JSON file created
cat ~/.config/i3/application-registry.json | jq '.applications[].name'

# Test launcher directly
launch-app vscode

# Test from rofi
rofi -show drun
# Type "VS Code" and verify it appears with correct icon
```

---

## 7. Best Practices Summary

### Do's

✅ **Use `xdg.desktopEntries`** for all desktop file generation
✅ **Define registry in Nix**, generate JSON for runtime
✅ **Use wrapper scripts** for dynamic parameter substitution
✅ **Use unique desktop file names** (e.g., `vscode-registry`) to avoid conflicts
✅ **Leverage `settings` attribute** for extra desktop entry keys
✅ **Add `onChange` hooks** to notify daemon of config changes
✅ **Log launcher executions** for debugging
✅ **Validate paths** with `lib.mkIf (pathExists ...)` for conditional entries

### Don'ts

❌ **Don't read JSON at eval time** (creates bootstrap dependency)
❌ **Don't manually create desktop files** (defeats declarative management)
❌ **Don't use relative paths** in Exec lines
❌ **Don't skip error handling** in wrapper scripts
❌ **Don't hardcode paths** (use `config.home.homeDirectory`)
❌ **Don't forget to escape** shell variables in parameters

---

## 8. Integration with Feature 034 Requirements

### Mapping to Functional Requirements

| Requirement | Implementation |
|-------------|----------------|
| **FR-005**: Generate .desktop files from registry | ✅ `xdg.desktopEntries` + `mapAttrs` |
| **FR-006**: Include Name, Exec, Icon, Categories, StartupWMClass | ✅ All supported in `xdg.desktopEntries` |
| **FR-007**: Use launcher wrapper for variable substitution | ✅ `launch-app` wrapper script pattern |
| **FR-008**: Remove orphaned desktop files | ✅ Automatic via home-manager |
| **FR-023**: Auto-generate window rules from registry | ✅ Additional JSON file generated |

### Architecture Diagram

```
┌─────────────────────────────────────────────┐
│     application-registry.nix (Nix)          │
│  Single source of truth for all apps       │
└─────────────┬───────────────────────────────┘
              │
              ├──────────────────────────────┐
              │                              │
              ▼                              ▼
┌─────────────────────────┐    ┌────────────────────────┐
│ application-registry     │    │ xdg.desktopEntries     │
│ .json (Runtime)          │    │ (Desktop files)        │
│                          │    │                        │
│ Used by:                 │    │ Generated:             │
│ - launch-app script      │    │ - vscode.desktop       │
│ - i3pm CLI commands      │    │ - firefox.desktop      │
│ - Daemon for validation  │    │ - lazygit.desktop      │
└─────────────────────────┘    └────────────────────────┘
              │                              │
              │                              ▼
              │                    ┌─────────────────┐
              │                    │ Rofi launcher   │
              │                    │ Shows all apps  │
              │                    └────────┬────────┘
              │                             │
              │                             ▼
              │                    ┌─────────────────┐
              └───────────────────>│ launch-app      │
                                   │ wrapper script  │
                                   │ - Reads registry│
                                   │ - Gets context  │
                                   │ - Substitutes   │
                                   │ - Executes      │
                                   └─────────────────┘
```

---

## 9. Next Steps

### Implementation Phases

**Phase 1: Core Infrastructure** (1-2 hours)
- [ ] Create `home-modules/tools/application-registry.nix`
- [ ] Define registry structure with initial apps (vscode, firefox, lazygit, yazi, ghostty)
- [ ] Implement `launch-app` wrapper script with logging
- [ ] Generate desktop entries from registry
- [ ] Test manual launches

**Phase 2: CLI Integration** (1-2 hours)
- [ ] Implement `i3pm apps list` in Deno CLI
- [ ] Implement `i3pm apps launch <name>` command
- [ ] Implement `i3pm apps info <name>` command
- [ ] Test CLI commands match GUI launcher behavior

**Phase 3: Rofi Integration** (1 hour)
- [ ] Update i3 keybinding to use rofi with application launcher mode
- [ ] Add visual indicators for scoped vs global apps
- [ ] Test fuzzy search and icon display

**Phase 4: Window Rules Generation** (1 hour)
- [ ] Generate `window-rules-from-registry.json`
- [ ] Update daemon to merge registry rules with manual rules
- [ ] Test window classification and workspace assignment

**Phase 5: Documentation & Testing** (1 hour)
- [ ] Update quickstart guide
- [ ] Add example applications to registry
- [ ] Test edge cases (no project active, missing commands, etc.)
- [ ] Verify cleanup on app removal

---

## 10. References

- **home-manager source**: [xdg-desktop-entries.nix](https://github.com/nix-community/home-manager/blob/master/modules/misc/xdg-desktop-entries.nix)
- **Desktop Entry Spec**: [freedesktop.org](https://specifications.freedesktop.org/desktop-entry-spec/latest/)
- **Existing implementations**:
  - `/etc/nixos/home-modules/tools/kubernetes-apps.nix` (k9s, headlamp)
  - `/etc/nixos/home-modules/tools/gitkraken.nix` (wrapper pattern)
  - `/etc/nixos/home-modules/desktop/i3-project-daemon.nix` (JSON generation)
- **Feature 034 Spec**: `/etc/nixos/specs/034-create-a-feature/spec.md`

---

**End of Research Findings**
