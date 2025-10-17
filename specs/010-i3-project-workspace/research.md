# Research: i3 Project Workspace Management System

**Date**: 2025-10-17
**Branch**: `010-i3-project-workspace`

## Overview

This document consolidates research findings from three key areas:
1. i3 IPC and layout mechanisms
2. NixOS module patterns for i3 integration
3. Application launch and window positioning techniques

## 1. i3 IPC and Layout Mechanisms

### 1.1 i3 IPC Protocol

**Decision**: Use `i3-msg` with JSON output piped to `jq` for bash scripts

**Rationale**:
- Simple CLI invocation for one-off tasks
- JSON output is structured and parseable
- No additional library dependencies needed for bash scripts
- Native i3 tool, always available when i3 is installed

**Key Commands**:
```bash
# Get workspace information
i3-msg -t get_workspaces | jq '.[] | select(.focused==true) | .name'

# Get window tree
i3-msg -t get_tree | jq '.nodes[].nodes[] | .name'

# Get outputs (monitors)
i3-msg -t get_outputs | jq '.[] | select(.active==true) | .name'
```

**Implementation Notes**:
- Use `jq` for all JSON parsing; never use shell text processing
- Large JSON output from `get_tree` can be 100KB+; filter early
- IPC response time: 1-5ms per command

**Pitfalls**:
- Don't parse i3-msg output with grep/awk; always use jq
- Window tree structure is deeply nested; understand container hierarchy
- Focused window may change during script execution (mouse movement)

---

### 1.2 i3-msg vs i3ipc Libraries

**Decision**: Use `i3-msg` for bash scripts; consider Python i3ipc for event-driven features

**Comparison**:
- **i3-msg**: Command-line tool, synchronous, perfect for scripts
- **i3ipc-python**: Asynchronous event monitoring, better for daemons
- **i3ipc-rs** (Rust): High performance, compile-time safety

**Recommended Hybrid Approach**:
- Use bash + i3-msg for project activation scripts
- Consider Python daemon with i3ipc for advanced features (automatic workspace naming, event hooks)
- Keep core functionality in bash for NixOS integration simplicity

---

### 1.3 Layout Saving and Restoration

**Decision**: Use `i3-save-tree` for capture, manually edit swallows criteria, `append_layout` for restoration

**Workflow**:
```bash
# 1. Create desired layout manually in i3

# 2. Save layout to JSON
i3-save-tree --workspace 1 > ~/.config/i3/layouts/workspace-1.json

# 3. Edit JSON - uncomment swallows criteria
sed -i 's|^\(\s*\)// "|\1"|g; /^\s*\/\//d' ~/.config/i3/layouts/workspace-1.json

# 4. Load layout (in i3 config or script)
i3-msg 'workspace 1; append_layout ~/.config/i3/layouts/workspace-1.json'

# 5. Launch applications (they fill placeholders)
firefox &
kitty &
code &
```

**Critical Timing**:
- Applications MUST launch AFTER `append_layout` creates placeholders
- Windows "swallow" placeholders based on matching criteria
- Unmatched placeholders remain as empty containers (manual cleanup needed)

**Matching Criteria Priority**:
1. `class` + `instance` (most reliable)
2. `class` + `window_role`
3. `class` only
4. `title` (avoid - changes frequently)

**Pitfalls**:
- i3-save-tree output is commented by default; MUST uncomment before use
- Title matching is unreliable (Firefox title changes during page load)
- Spotify lacks proper WM_CLASS hints initially
- Stale placeholders accumulate if apps don't launch

---

### 1.4 Window Matching Reliability

**Decision**: Prefer `class` + `instance` matching; avoid `title` when possible

**WM_CLASS Structure**:
- Each X11 window has two-part WM_CLASS: `instance` and `class`
- Query with: `xprop WM_CLASS` (click window)
- Example: Firefox returns `WM_CLASS(STRING) = "Navigator", "firefox"`
  - Instance: "Navigator"
  - Class: "firefox"

**Matching Reliability Ranking**:
1. **class + instance** (best): `[class="firefox" instance="Navigator"]`
2. **class + window_role**: `[class="firefox" window_role="browser"]`
3. **class only**: `[class="firefox"]`
4. **title** (worst): `[title="Firefox"]` - changes frequently

**Problematic Applications**:
- **Spotify**: No WM_CLASS on initial map; use `for_window` not `assign`
- **Firefox**: Late title updates; prefer class matching
- **Terminals**: Can't match by internal content; use window_role or custom class
- **Electron apps**: Usually have good class names (e.g., "Slack", "Code")

**Edge Cases**:
- Windows without WM_CLASS exist (rare, usually splash screens)
- Multiple windows with same class need instance/role differentiation
- Dynamic titles make title-based matching unreliable

---

### 1.5 Monitor/Output Assignment

**Decision**: Use workspace output assignment + xrandr for detection; support multi-output fallback

**i3 Configuration**:
```bash
# Assign workspace to specific output (monitor)
workspace 1 output DP-1
workspace 2 output DP-2
workspace 3 output HDMI-1

# Multi-output fallback (i3 4.16+)
workspace 1 output DP-1 HDMI-1 eDP-1
```

**Output Detection**:
```bash
# List active monitors
xrandr --listmonitors

# Get output names
xrandr | grep " connected" | awk '{print $1}'

# Check if specific output is connected
xrandr | grep "DP-1 connected"
```

**Implementation Notes**:
- i3's workspace assignment is declarative; workspaces "follow" outputs
- If assigned output is disconnected, workspace falls back to primary
- Multiple output assignment provides graceful degradation (3 monitors → 1 monitor)
- Output assignment doesn't configure displays; use xrandr for physical setup

**Pitfalls**:
- Output names change between systems (DP-1 vs DisplayPort-1)
- Monitor connection/disconnection requires i3 restart or `i3-msg reload`
- Workspace can "disappear" if output is disconnected and no fallback defined

---

### 1.6 Workspace Switching

**Decision**: Use `workspace number` for numeric workspaces; chain commands for atomic operations

**Best Practices**:
```bash
# Switch to workspace (create if doesn't exist)
i3-msg "workspace 2"

# Switch to workspace by number (allows dynamic naming)
i3-msg "workspace number 2"

# Move window to workspace
i3-msg "move container to workspace 3"

# Chain commands for atomic operation
i3-msg "workspace 2; split h; exec firefox"

# Focus explicit before move (avoids race conditions)
i3-msg "[class=Firefox] focus; move container to workspace 3"
```

**Timing Issues**:
- Don't switch workspaces between app launch and window map
- Mouse can change focus between commands
- Use chained commands or explicit focus for reliability

**Pitfalls**:
- `workspace number X` vs `workspace X` behavior differs with named workspaces
- Workspace switching during app startup causes window to appear on wrong workspace
- Race condition: focus can change between commands

---

## 2. NixOS Module Patterns for i3 Integration

### 2.1 Module Structure Pattern

**Recommended Structure**:
```nix
# home-modules/desktop/i3-projects.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.i3Projects;

  # Filter enabled projects
  enabledProjects = filterAttrs (name: proj: proj.enabled or true) cfg.projects;

in {
  options.programs.i3Projects = {
    enable = mkEnableOption "i3 project workspace management";

    projects = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          displayName = mkOption { type = types.str; };
          workspace = mkOption { type = types.str; };
          applications = mkOption { type = types.listOf (types.submodule { ... }); };
          enabled = mkOption { type = types.bool; default = true; };
        };
      });
      default = {};
    };
  };

  config = mkIf cfg.enable {
    # Validation
    assertions = [{
      assertion = all (proj: proj.workspace != null) (attrValues enabledProjects);
      message = "All projects must have workspace assigned";
    }];

    # Install tools
    home.packages = mapAttrsToList makeProjectScript enabledProjects;

    # Generate config files
    home.file.".config/i3/projects.conf".text = generateConfig enabledProjects;
  };
}
```

**Key Patterns**:
- Use `types.attrsOf (types.submodule { ... })` for collections
- Filter with `filterAttrs` for enabled items
- Generate scripts with `mapAttrsToList`
- Validate with `assertions` block

---

### 2.2 Script Generation Patterns

**From firefox-pwas-declarative.nix**:
```nix
# CLI tool in PATH
home.packages = [
  (pkgs.writeShellScriptBin "pwa-list" ''
    #!/usr/bin/env bash
    echo "Configured PWAs:"
    ${lib.concatMapStrings (pwa: ''
      echo "  - ${pwa.name}: ${pwa.url}"
    '') pwas}
  '')
];

# Script for internal use
managePWAsScript = pkgs.writeShellScript "manage-pwas" ''
  export PATH="${pkgs.coreutils}/bin:${pkgs.jq}/bin:$PATH"

  # Script logic with absolute package paths
  ${pkgs.firefoxpwa}/bin/firefoxpwa site launch ${pwa.id}
'';
```

**Key Patterns**:
- `pkgs.writeShellScriptBin` for CLI tools (added to PATH)
- `pkgs.writeShellScript` for internal scripts
- Always use absolute paths: `${pkgs.tool}/bin/tool`
- Set PATH at script start for cleaner code
- Use `lib.concatMapStrings` for list iteration

---

### 2.3 Configuration File Generation

**From i3wm.nix**:
```nix
# System-level config
environment.etc."i3/config".text = ''
  # i3 configuration
  set $mod Mod4
  bindsym $mod+Return exec ${pkgs.alacritty}/bin/alacritty
  bindsym $mod+d exec ${pkgs.rofi}/bin/rofi -show drun
'';

# User-level config with proper permissions
home.file.".config/i3/projects.conf" = {
  text = generateProjectConfig cfg.projects;
  # Optional: onChange = "i3-msg reload";
};
```

**Key Patterns**:
- Use `environment.etc` for system-level configs
- Use `home.file` for user configs
- Use `xdg.configFile` for XDG-compliant configs
- Generate with Nix string interpolation
- Include generation timestamp/comment

---

### 2.4 JSON Configuration Generation

**Pattern**:
```nix
home.file.".config/i3-projects/projects.json" = {
  text = builtins.toJSON {
    projects = mapAttrs (name: proj: {
      displayName = proj.displayName;
      workspace = proj.workspace;
      applications = map (app: {
        command = app.command;
        wmClass = app.wmClass;
      }) proj.applications;
    }) enabledProjects;
    version = "1.0";
    generated = "2025-10-17";
  };
};
```

**Key Patterns**:
- Use `builtins.toJSON` for structured configs
- Transform Nix attrs to JSON-friendly structure
- Include metadata (version, generation time)

---

### 2.5 Data Processing Functions

**Essential Nix Functions**:
```nix
# Convert attrset to list
mapAttrsToList (name: value: ...) attrset

# Filter attrset
filterAttrs (name: value: condition) attrset

# Get values only
attrValues attrset

# Concatenate strings from list
concatMapStrings (item: "...") list

# String join
concatStringsSep "\n" list

# Conditional inclusion
optionals condition [ items ]
optionalString condition "text"
```

---

## 3. Application Launch and Window Positioning

### 3.1 Application Launching Best Practices

**Decision**: Use direct execution for runtime, `exec --no-startup-id` for i3 config

**Runtime Script Pattern**:
```bash
#!/bin/bash
# Switch to workspace first
i3-msg "workspace 2"

# Launch application directly (inherits workspace context)
firefox &

# Don't use i3-msg exec - unnecessary complexity
# AVOID: i3-msg "exec firefox"
```

**i3 Config Pattern**:
```bash
# Startup applications
exec --no-startup-id firefox
exec_always --no-startup-id $HOME/.config/i3/workspace-setup.sh
```

**Key Insights**:
- `i3-msg exec` offers no advantages over direct execution
- `--no-startup-id` avoids 60-second watch cursor for non-compliant apps
- Direct execution is faster and more predictable

---

### 3.2 Window Positioning Techniques

**Decision**: Use layout saving for complex arrangements; `for_window` for simple positioning

**Layout Saving (Complex Arrangements)**:
```bash
# 1. Create layout manually
# 2. Save layout
i3-save-tree --workspace 1 > ~/.config/i3/layouts/workspace-1.json

# 3. Edit JSON - uncomment swallows
sed -i 's|^\(\s*\)// "|\1"|g; /^\s*\/\//d' ~/.config/i3/layouts/workspace-1.json

# 4. Load layout
i3-msg 'workspace 1; append_layout ~/.config/i3/layouts/workspace-1.json'

# 5. Launch apps
firefox &
kitty &
```

**for_window Rules (Simple Positioning)**:
```bash
# In i3 config
for_window [class="Pavucontrol"] floating enable, move absolute position 1600 50
for_window [class="Spotify"] move to workspace 5, resize set 1920 1080
for_window [class="Terminal" title="bottom"] move down, resize set height 300px
```

**Manual Split Control**:
```bash
i3-msg "workspace 2"
i3-msg "split h"  # Next window splits horizontal
kitty &
sleep 0.5

i3-msg "split v"  # Next window splits vertical
firefox &
```

**Key Insights**:
- Layout files create placeholders that swallow matching windows
- `for_window` executes on every window state change
- Tiled windows: use `resize set width/height`
- Floating windows: use `move absolute position X Y`
- Split commands affect where next window appears

---

### 3.3 Asynchronous Handling Strategies

**Decision**: Multi-layered approach based on reliability needs

**Level 1: Sleep-Based (Simplest)**:
```bash
firefox &
sleep 2  # Wait for Firefox

spotify &
sleep 3  # Spotify is slow
```

**Timing Guidelines**:
- Terminals: 0.2-0.5s
- Light apps: 1-2s
- Browsers: 2-3s
- Heavy apps: 3-5s

**Level 2: PID-Based Waiting (More Reliable)**:
```bash
wait_for_window() {
    local class="$1"
    local timeout="${2:-10}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if wmctrl -lx | grep -i "$class" > /dev/null; then
            return 0
        fi
        sleep 0.2
        ((elapsed++))
    done
    return 1
}

firefox &
wait_for_window "Firefox" 5
```

**Level 3: xdotool Synchronous Launch**:
```bash
firefox &
pid=$!
xdotool search --sync --onlyvisible --pid $pid --name "Firefox"
```

**Key Insights**:
- Sleep-based works for 80% of use cases
- Applications have variable startup times (0.2s - 5s)
- Window appearance ≠ window ready
- Race conditions occur when switching workspaces too early

---

### 3.4 xdotool vs i3-msg Tool Selection

**Decision**: Use i3-msg for layout, xdotool for window detection

| Operation | i3-msg | xdotool | Winner |
|-----------|--------|---------|---------|
| Workspace switching | ✓ Fast | ✗ Not supported | i3-msg |
| Wait for window | ✗ Not supported | ✓ Reliable | xdotool |
| Tiled window resize | ✓ Works | ✗ Doesn't work | i3-msg |
| Window detection | Limited | ✓ Excellent | xdotool |
| Focus management | ✓ Container-aware | Basic | i3-msg |

**Usage Pattern**:
```bash
# Use i3-msg for workspace and layout operations
i3-msg "workspace 2"
i3-msg "split h"
i3-msg "[class=Firefox] focus"

# Use xdotool for window detection and waiting
xdotool search --sync --onlyvisible --class "Firefox"
```

---

### 3.5 Working Directory Context

**Decision**: Use terminal-specific flags + helper scripts

**Direct Specification**:
```bash
# Most terminals support --working-directory
kitty --directory=/path/to/project &
alacritty --working-directory /path/to/project &
gnome-terminal --working-directory=/path/to/project &
```

**Project Launch Script Pattern**:
```bash
#!/bin/bash
PROJECT_DIR="$HOME/projects/$1"

i3-msg "workspace $1"
kitty --directory="$PROJECT_DIR" &
sleep 0.5

i3-msg "split v"
code "$PROJECT_DIR" &
```

**Key Insights**:
- i3's exec does NOT preserve working directory (always launches from $HOME)
- Most modern terminals support `--directory` flag
- GUI applications don't have meaningful CWD
- Project-specific launch scripts are most maintainable

---

### 3.6 Multi-Instance Detection

**Decision**: Use window criteria + launch-time differentiation

**Detection Pattern**:
```bash
is_running() {
    local class="$1"
    wmctrl -lx | grep -i "$class" > /dev/null
    return $?
}

launch_or_focus() {
    local class="$1"
    local command="$2"

    if is_running "$class"; then
        i3-msg "[class=\"$class\"] focus"
    else
        $command &
    fi
}
```

**Known Single-Instance Apps**:
- Firefox (main window)
- Spotify
- Slack, Discord
- Most Electron apps

**Known Multi-Instance Apps**:
- Terminals (kitty, alacritty, urxvt)
- Text editors (nvim, vim)
- File managers

**Creating Multiple Instances**:
```bash
# Firefox with profiles
firefox -P "work" --class "Firefox-Work" &
firefox -P "personal" --class "Firefox-Personal" &

# Then assign differently
assign [class="Firefox-Work"] workspace 1
assign [class="Firefox-Personal"] workspace 2
```

**Key Insights**:
- Use `for_window` instead of `assign` for Spotify
- Firefox profiles + `--class` flag enables multi-instance
- Window roles enable differentiation
- Custom classes via command-line flags

---

## Key Decisions Summary

### Technology Choices

**1. Scripting Language**: Bash 5.x
- **Rationale**: Native to NixOS, no additional dependencies, good i3-msg integration
- **Alternative Considered**: Python + i3ipc (rejected for initial version; too complex for basic needs)

**2. IPC Communication**: i3-msg + jq
- **Rationale**: Simple, declarative, already available in NixOS
- **Alternative Considered**: i3ipc library (considered for future event-driven features)

**3. Layout Storage**: i3-save-tree JSON format
- **Rationale**: Native i3 format, well-documented, machine and human readable
- **Alternative Considered**: Custom format (rejected; reinventing the wheel)

**4. Configuration Format**: Nix attribute sets
- **Rationale**: Natural NixOS integration, type checking, validation
- **Alternative Considered**: YAML/JSON files (rejected; less integrated with NixOS)

**5. Project Definitions**: Home-manager module options
- **Rationale**: Declarative, version controlled, integrated with system configuration
- **Alternative Considered**: Standalone config files (rejected; doesn't leverage NixOS strengths)

---

### Architecture Decisions

**1. Module Split**: System module + Home-manager module
- **System module** (`modules/desktop/i3-project-workspace.nix`): CLI tools, core functionality
- **Home-manager module** (`home-modules/desktop/i3-projects.nix`): User project definitions

**2. Script Generation**: Embedded in Nix modules
- Generate all scripts from Nix expressions
- Use `pkgs.writeShellScriptBin` for CLI tools
- Use absolute package paths for reproducibility

**3. Layout Management**: Capture-Edit-Load workflow
- Capture: `i3-save-tree` generates JSON
- Edit: Script post-processes to uncomment swallows
- Load: `append_layout` + app launch

**4. Timing Strategy**: Sleep-based with configurable delays
- Simple, predictable, works for 80% of cases
- Document timing recommendations per app type
- Future enhancement: xdotool-based waiting

**5. Multi-Monitor Support**: Workspace output assignment with fallback
- Declarative output assignment in config
- Graceful degradation to single monitor
- xrandr for monitor detection

---

## Implementation Recommendations

### Phase 1: Core Functionality
1. NixOS module with basic options
2. Project activation script (sleep-based timing)
3. Simple project definitions in home-manager
4. i3 config generation (assign rules)

### Phase 2: Layout Management
1. Layout capture command
2. JSON post-processing script
3. Layout restoration in project activation
4. Layout file management

### Phase 3: Advanced Features
1. Project close command
2. rofi integration for project selection
3. i3wsr integration for workspace naming
4. xdotool-based window waiting

### Phase 4: Enhancements
1. Multi-monitor adaptation
2. Application aliases
3. Ad-hoc project composition
4. Python daemon for events (optional)

---

## References

- i3 User Guide: https://i3wm.org/docs/userguide.html
- i3 IPC Documentation: https://i3wm.org/docs/ipc.html
- i3 Layout Saving: https://i3wm.org/docs/layout-saving.html
- NixOS Module System: https://nixos.org/manual/nixos/stable/#sec-writing-modules
- Home-Manager Manual: https://nix-community.github.io/home-manager/

---

**Research Completed**: 2025-10-17
**Next Phase**: Data model and contracts generation
