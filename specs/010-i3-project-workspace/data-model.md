# Data Model: i3 Project Workspace Management System

**Date**: 2025-10-17
**Branch**: `010-i3-project-workspace`

## Overview

This document defines the data structures used in the i3 project workspace management system. All entities are represented as Nix attribute sets in the NixOS/home-manager configuration.

---

## Core Entities

### 1. Project

A named collection of workspace configurations representing a cohesive development environment.

**Nix Type Definition**:
```nix
types.attrsOf (types.submodule {
  options = {
    displayName = mkOption {
      type = types.str;
      description = "Human-readable project name for display in UI";
      example = "API Backend Development";
    };

    description = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional project description";
    };

    workspaces = mkOption {
      type = types.listOf types.submodule { ... };  # See WorkspaceConfig
      description = "List of workspace configurations for this project";
    };

    workingDirectory = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Default working directory for applications";
      example = "/home/user/projects/api-backend";
    };

    primaryWorkspace = mkOption {
      type = types.str;
      description = "Workspace number/name to focus when activating project";
      example = "1";
    };

    enabled = mkOption {
      type = types.bool;
      default = true;
      description = "Whether this project is active";
    };

    autostart = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically activate this project on i3 startup";
    };
  };
})
```

**Example**:
```nix
programs.i3Projects.projects = {
  api-backend = {
    displayName = "API Backend Development";
    description = "Node.js API with PostgreSQL database";
    primaryWorkspace = "1";
    workingDirectory = /home/user/projects/api-backend;
    workspaces = [ ... ];
    enabled = true;
    autostart = false;
  };
};
```

**Relationships**:
- Contains: One or more `WorkspaceConfig` entities
- References: Optional working directory (filesystem path)

**Validation Rules**:
- Project name (attr key) must be unique
- Project name should be filesystem-safe (no spaces, special chars)
- `primaryWorkspace` must match one of the workspace numbers in `workspaces` list
- If `workingDirectory` is specified, it must exist or be creatable
- At least one workspace must be defined

---

### 2. WorkspaceConfig

Defines the applications and layout for a single i3 workspace.

**Nix Type Definition**:
```nix
types.submodule {
  options = {
    number = mkOption {
      type = types.str;
      description = "i3 workspace number or name";
      example = "1";
    };

    output = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Monitor output name (e.g., DP-1, HDMI-1)";
      example = "DP-1";
    };

    outputs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of monitor outputs with fallback (i3 4.16+)";
      example = ["DP-1" "HDMI-1" "eDP-1"];
    };

    applications = mkOption {
      type = types.listOf types.submodule { ... };  # See ApplicationConfig
      description = "Applications to launch in this workspace";
    };

    layout = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to i3 layout JSON file";
      example = /home/user/.config/i3/layouts/workspace-1.json;
    };

    layoutMode = mkOption {
      type = types.enum [ "default" "tabbed" "stacking" "splitv" "splith" ];
      default = "default";
      description = "Initial layout mode for workspace";
    };
  };
}
```

**Example**:
```nix
{
  number = "1";
  output = "DP-1";
  outputs = ["DP-1" "HDMI-1" "eDP-1"];  # Fallback chain
  layoutMode = "splith";
  applications = [
    { package = "firefox"; command = "firefox"; wmClass = "firefox"; }
    { package = "alacritty"; command = "alacritty"; wmClass = "Alacritty"; }
  ];
  layout = /home/user/.config/i3/layouts/dev-workspace.json;
}
```

**Relationships**:
- Belongs to: One `Project`
- Contains: One or more `ApplicationConfig` entities
- References: Optional layout file (filesystem path)
- References: Optional monitor output(s)

**Validation Rules**:
- `number` must be unique within a project
- If `outputs` is specified, `output` is ignored
- If `layout` is specified, file must exist and be valid JSON
- Layout file must be in i3-save-tree format
- At least one application must be defined OR layout must be specified

---

### 3. ApplicationConfig

Specifies an application to launch with its positioning and context.

**Nix Type Definition**:
```nix
types.submodule {
  options = {
    package = mkOption {
      type = types.str;
      description = "Nixpkgs package name";
      example = "firefox";
    };

    command = mkOption {
      type = types.str;
      description = "Command to execute";
      example = "firefox --new-window";
    };

    wmClass = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Expected WM_CLASS for window matching";
      example = "firefox";
    };

    wmInstance = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Expected WM_CLASS instance";
      example = "Navigator";
    };

    windowRole = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Expected window role";
    };

    workingDirectory = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Working directory override for this application";
    };

    args = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional command-line arguments";
    };

    instanceBehavior = mkOption {
      type = types.enum [ "multi" "single" "shared" "auto" ];
      default = "auto";
      description = ''
        Instance handling:
        - multi: Always launch new instance
        - single: Focus existing or launch new
        - shared: Move existing to this workspace
        - auto: Detect based on application
      '';
    };

    launchDelay = mkOption {
      type = types.float;
      default = 0.5;
      description = "Seconds to wait after launching before continuing";
    };

    floating = mkOption {
      type = types.bool;
      default = false;
      description = "Whether window should float";
    };

    position = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          x = mkOption { type = types.int; };
          y = mkOption { type = types.int; };
        };
      });
      default = null;
      description = "Absolute position for floating windows";
    };

    size = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          width = mkOption { type = types.int; };
          height = mkOption { type = types.int; };
        };
      });
      default = null;
      description = "Size for floating windows or tiled resize";
    };
  };
}
```

**Example**:
```nix
{
  package = "firefox";
  command = "firefox";
  wmClass = "firefox";
  wmInstance = null;
  windowRole = null;
  workingDirectory = null;
  args = ["--new-window"];
  instanceBehavior = "shared";  # Firefox is typically single-instance
  launchDelay = 2.0;  # Firefox takes ~2s to start
  floating = false;
  position = null;
  size = null;
}

# Terminal with working directory
{
  package = "alacritty";
  command = "alacritty";
  wmClass = "Alacritty";
  workingDirectory = /home/user/projects/api-backend;
  args = [];
  instanceBehavior = "multi";  # Terminals support multiple instances
  launchDelay = 0.3;
  floating = false;
}

# Floating window with position
{
  package = "pavucontrol";
  command = "pavucontrol";
  wmClass = "Pavucontrol";
  instanceBehavior = "single";
  launchDelay = 1.0;
  floating = true;
  position = { x = 1600; y = 50; };
  size = { width = 800; height = 600; };
}
```

**Relationships**:
- Belongs to: One `WorkspaceConfig`
- References: Nixpkgs package
- References: Optional working directory

**Validation Rules**:
- `package` must exist in nixpkgs
- `command` must be executable
- If `wmClass` is null, window matching may be unreliable
- `position` and `size` only apply to floating windows
- `launchDelay` must be >= 0.0
- If `workingDirectory` is specified, it must exist or be creatable

---

### 4. ApplicationAlias

A short name that maps to a full application definition for shorthand syntax.

**Nix Type Definition**:
```nix
types.attrsOf (types.submodule {
  options = {
    package = mkOption { type = types.str; };
    command = mkOption { type = types.str; };
    wmClass = mkOption { type = types.nullOr types.str; default = null; };
    defaultArgs = mkOption { type = types.listOf types.str; default = []; };
    instanceBehavior = mkOption { type = types.enum [ "multi" "single" "shared" "auto" ]; default = "auto"; };
  };
})
```

**Example**:
```nix
programs.i3Projects.aliases = {
  ff = {
    package = "firefox";
    command = "firefox";
    wmClass = "firefox";
    instanceBehavior = "shared";
  };

  term = {
    package = "alacritty";
    command = "alacritty";
    wmClass = "Alacritty";
    instanceBehavior = "multi";
  };

  vsc = {
    package = "vscode";
    command = "code";
    wmClass = "Code";
    instanceBehavior = "single";
  };
};
```

**Relationships**:
- Referenced by: Shorthand command syntax
- Maps to: `ApplicationConfig` structure

**Validation Rules**:
- Alias name must be unique
- Alias name should be short (2-5 chars recommended)
- Must contain valid `ApplicationConfig` fields

---

### 5. LayoutSnapshot

A captured state of current workspace arrangement (output of capture command).

**JSON Structure** (stored on filesystem):
```json
{
  "version": "1.0",
  "captured": "2025-10-17T14:30:00Z",
  "capturedBy": "i3-project-capture",
  "workspaces": [
    {
      "number": "1",
      "output": "DP-1",
      "focused": true,
      "applications": [
        {
          "wmClass": "firefox",
          "wmInstance": "Navigator",
          "title": "Mozilla Firefox",
          "geometry": {
            "x": 0,
            "y": 0,
            "width": 1920,
            "height": 1080
          },
          "floating": false,
          "command": "firefox"
        }
      ],
      "layoutFile": "/home/user/.config/i3/layouts/workspace-1.json"
    }
  ]
}
```

**Relationships**:
- Can be converted to: `Project` configuration
- Generated from: Current i3 workspace state
- References: i3 layout JSON files

**State Transitions**:
1. **Capture**: User executes `i3-project capture <name>`
2. **Store**: System generates JSON snapshot
3. **Review**: User examines captured state
4. **Convert**: System generates Nix configuration from snapshot
5. **Activate**: User can activate captured project

---

## Derived Data Structures

### 6. ProjectState (Runtime)

Runtime state maintained during project activation (not stored in config).

**Internal Representation**:
```bash
# Stored in /tmp/i3-projects/<project-name>.state
{
  "project": "api-backend",
  "activated": "2025-10-17T14:30:00Z",
  "primaryWorkspace": "1",
  "workspaces": ["1", "2", "3"],
  "pids": [
    { "workspace": "1", "command": "firefox", "pid": 12345, "wmClass": "firefox" },
    { "workspace": "2", "command": "alacritty", "pid": 12346, "wmClass": "Alacritty" }
  ],
  "status": "active"
}
```

**Usage**:
- Track launched applications for project close command
- Detect if project is currently active
- Monitor application lifecycle

---

## Configuration Schema

### Complete Project Definition Example

```nix
programs.i3Projects = {
  enable = true;

  # Application aliases for shorthand syntax
  aliases = {
    ff = { package = "firefox"; command = "firefox"; wmClass = "firefox"; };
    term = { package = "alacritty"; command = "alacritty"; wmClass = "Alacritty"; };
    vsc = { package = "vscode"; command = "code"; wmClass = "Code"; };
  };

  # Project definitions
  projects = {
    api-backend = {
      displayName = "API Backend Development";
      description = "Node.js API with PostgreSQL";
      primaryWorkspace = "1";
      workingDirectory = /home/user/projects/api-backend;
      enabled = true;
      autostart = false;

      workspaces = [
        # Workspace 1: Main development (DP-1 monitor)
        {
          number = "1";
          outputs = ["DP-1" "HDMI-1" "eDP-1"];
          layoutMode = "splith";
          applications = [
            {
              package = "alacritty";
              command = "alacritty";
              wmClass = "Alacritty";
              workingDirectory = /home/user/projects/api-backend;
              instanceBehavior = "multi";
              launchDelay = 0.3;
            }
            {
              package = "vscode";
              command = "code";
              wmClass = "Code";
              args = ["/home/user/projects/api-backend"];
              instanceBehavior = "single";
              launchDelay = 2.0;
            }
          ];
        }

        # Workspace 2: Browser testing (DP-2 monitor)
        {
          number = "2";
          outputs = ["DP-2" "DP-1"];
          applications = [
            {
              package = "firefox";
              command = "firefox";
              wmClass = "firefox";
              args = ["--new-window" "http://localhost:3000"];
              instanceBehavior = "shared";
              launchDelay = 2.0;
            }
          ];
        }

        # Workspace 3: Database tools (DP-1 monitor)
        {
          number = "3";
          outputs = ["DP-1"];
          layout = /home/user/.config/i3/layouts/db-tools.json;
          applications = [
            {
              package = "alacritty";
              command = "alacritty";
              wmClass = "Alacritty";
              args = ["-e" "psql" "api_development"];
              workingDirectory = /home/user/projects/api-backend;
              instanceBehavior = "multi";
              launchDelay = 0.5;
            }
          ];
        }
      ];
    };

    docs-site = {
      displayName = "Documentation Site";
      primaryWorkspace = "4";
      enabled = true;

      workspaces = [
        {
          number = "4";
          applications = [
            {
              package = "vscode";
              command = "code";
              wmClass = "Code";
              args = ["/home/user/projects/docs"];
              instanceBehavior = "single";
              launchDelay = 2.0;
            }
            {
              package = "firefox";
              command = "firefox";
              wmClass = "firefox";
              args = ["--new-window" "http://localhost:8000"];
              instanceBehavior = "shared";
              launchDelay = 2.0;
            }
          ];
        }
      ];
    };
  };
};
```

---

## Data Flow

### Project Activation Flow

```
1. User Input: i3-project activate api-backend
   ↓
2. Load Config: Read projects.api-backend from Nix-generated JSON
   ↓
3. Validate: Check workspaces, applications exist
   ↓
4. For Each Workspace:
   ↓
   4a. Switch to workspace (i3-msg "workspace N")
   ↓
   4b. Load layout if specified (i3-msg "append_layout ...")
   ↓
   4c. For Each Application:
       ↓
       Launch with args (command &)
       ↓
       Wait launchDelay seconds
       ↓
       Track PID for project state
   ↓
5. Focus primary workspace
   ↓
6. Write ProjectState to /tmp/i3-projects/<name>.state
   ↓
7. Output: "Project 'api-backend' activated"
```

### Layout Capture Flow

```
1. User Input: i3-project capture my-project
   ↓
2. Query i3: Get active workspaces (i3-msg -t get_workspaces)
   ↓
3. For Each Non-Empty Workspace:
   ↓
   3a. Save layout (i3-save-tree --workspace N)
   ↓
   3b. Post-process JSON (uncomment swallows)
   ↓
   3c. Query windows (i3-msg -t get_tree | jq ...)
   ↓
   3d. Build ApplicationConfig for each window
   ↓
4. Generate LayoutSnapshot JSON
   ↓
5. Generate Nix configuration template
   ↓
6. Output: "Captured to ~/.config/i3-projects/captured/my-project.nix"
```

---

## Validation Rules Summary

### Project Level
- Unique project names
- Filesystem-safe names (no spaces)
- At least one workspace
- `primaryWorkspace` must exist in workspace list

### Workspace Level
- Unique workspace numbers within project
- Valid monitor output names
- At least one application OR layout file
- Layout file must exist and be valid JSON

### Application Level
- Package must exist in nixpkgs
- Command must be executable
- Non-negative launch delay
- Floating-only attributes (position/size) require floating = true
- Working directory must exist or be creatable

---

## References

- NixOS Module System: https://nixos.org/manual/nixos/stable/#sec-writing-modules
- i3 IPC Types: https://i3wm.org/docs/ipc.html#_tree_reply
- i3 Layout Format: https://i3wm.org/docs/layout-saving.html

---

**Data Model Version**: 1.0
**Last Updated**: 2025-10-17
