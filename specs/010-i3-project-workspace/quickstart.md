# Quickstart Guide: i3 Project Workspace Management

**Date**: 2025-10-17
**Branch**: `010-i3-project-workspace`

## 5-Minute Quick Start

Get started with i3 project workspaces in 5 minutes.

---

## Prerequisites

- NixOS with i3wm installed and configured
- Home-manager setup
- Basic familiarity with i3 window manager

---

## Step 1: Enable the Feature

Add to your `home.nix` or home-manager configuration:

```nix
# home.nix or equivalent
{
  programs.i3Projects.enable = true;
}
```

Rebuild your system:

```bash
sudo nixos-rebuild switch --flake .#hetzner
```

---

## Step 2: Define Your First Project

Add a simple project definition:

```nix
programs.i3Projects = {
  enable = true;

  projects = {
    # Simple development project
    dev-simple = {
      displayName = "Simple Development";
      primaryWorkspace = "1";

      workspaces = [
        {
          number = "1";
          applications = [
            {
              package = "alacritty";
              command = "alacritty";
              wmClass = "Alacritty";
              launchDelay = 0.3;
            }
            {
              package = "firefox";
              command = "firefox";
              wmClass = "firefox";
              args = ["--new-window"];
              launchDelay = 2.0;
            }
          ];
        }
      ];
    };
  };
};
```

Rebuild again:

```bash
sudo nixos-rebuild switch --flake .#hetzner
```

---

## Step 3: Activate Your Project

```bash
i3-project activate dev-simple
```

You should see:
- Workspace 1 opens
- Alacritty terminal launches
- Firefox browser launches
- Both applications appear on workspace 1

---

## Step 4: List Projects

```bash
i3-project list
```

Output:
```
Available Projects:
  ● dev-simple          Simple Development (active)
    └─ 1 workspace, 2 applications

Legend: ● = active, ○ = inactive
```

---

## Step 5: Close Project

```bash
i3-project close dev-simple
```

All applications from the project will be terminated gracefully.

---

## Common Workflows

### Workflow 1: Capture Current Layout

If you've arranged windows manually and want to save the layout:

```bash
# Arrange your windows how you like them
# Then capture:
i3-project-capture my-new-project

# Review generated config
cat ~/.config/i3-projects/captured/my-new-project.nix

# Integrate into your home-manager config
# (copy content into programs.i3Projects.projects.my-new-project)
```

### Workflow 2: Multi-Workspace Project

Define a project spanning multiple workspaces:

```nix
programs.i3Projects.projects.full-stack = {
  displayName = "Full Stack Development";
  primaryWorkspace = "1";
  workingDirectory = /home/user/projects/my-app;

  workspaces = [
    # Workspace 1: Editor + Terminal
    {
      number = "1";
      applications = [
        {
          package = "vscode";
          command = "code";
          wmClass = "Code";
          args = ["/home/user/projects/my-app"];
          launchDelay = 2.0;
        }
        {
          package = "alacritty";
          command = "alacritty";
          wmClass = "Alacritty";
          workingDirectory = /home/user/projects/my-app;
          launchDelay = 0.3;
        }
      ];
    }

    # Workspace 2: Browser for testing
    {
      number = "2";
      applications = [
        {
          package = "firefox";
          command = "firefox";
          wmClass = "firefox";
          args = ["--new-window" "http://localhost:3000"];
          launchDelay = 2.0;
        }
      ];
    }

    # Workspace 3: Database terminal
    {
      number = "3";
      applications = [
        {
          package = "alacritty";
          command = "alacritty";
          wmClass = "Alacritty";
          args = ["-e" "psql" "my_app_development"];
          workingDirectory = /home/user/projects/my-app;
          launchDelay = 0.5;
        }
      ];
    }
  ];
};
```

Activate:

```bash
i3-project activate full-stack
```

### Workflow 3: Quick Switch Between Projects

```bash
# Activate first project
i3-project activate api-backend

# Do some work...

# Switch to another project (both stay running)
i3-project activate docs-site

# Switch back
i3-project switch api-backend  # Faster than activate
```

### Workflow 4: Check Project Status

```bash
# See all active projects
i3-project status

# See specific project details
i3-project status api-backend
```

Output:
```
Project: api-backend
Status: Active
Activated: 2025-10-17 14:30:00 (15 minutes ago)
Primary Workspace: 1

Workspaces:
  1: 2 applications
  2: 1 application

Total: 3 applications
```

---

## Configuration Examples

### Example 1: Minimal Terminal + Browser

```nix
programs.i3Projects.projects.web-dev = {
  displayName = "Web Development";
  primaryWorkspace = "1";

  workspaces = [{
    number = "1";
    applications = [
      {
        package = "alacritty";
        command = "alacritty";
        wmClass = "Alacritty";
        launchDelay = 0.3;
      }
      {
        package = "firefox";
        command = "firefox";
        wmClass = "firefox";
        launchDelay = 2.0;
      }
    ];
  }];
};
```

### Example 2: With Working Directory

```nix
programs.i3Projects.projects.api-work = {
  displayName = "API Development";
  primaryWorkspace = "1";
  workingDirectory = /home/user/projects/api;

  workspaces = [{
    number = "1";
    applications = [
      {
        package = "alacritty";
        command = "alacritty";
        wmClass = "Alacritty";
        workingDirectory = /home/user/projects/api;  # Overrides project default
        launchDelay = 0.3;
      }
      {
        package = "vscode";
        command = "code";
        wmClass = "Code";
        args = ["/home/user/projects/api"];
        launchDelay = 2.0;
      }
    ];
  }];
};
```

### Example 3: Multi-Monitor Setup

```nix
programs.i3Projects.projects.multi-monitor = {
  displayName = "Multi-Monitor Development";
  primaryWorkspace = "1";

  workspaces = [
    # Left monitor (DP-1): Editor
    {
      number = "1";
      outputs = ["DP-1" "eDP-1"];  # Fallback to laptop screen
      applications = [
        {
          package = "vscode";
          command = "code";
          wmClass = "Code";
          launchDelay = 2.0;
        }
      ];
    }

    # Right monitor (DP-2): Browser
    {
      number = "2";
      outputs = ["DP-2" "DP-1"];  # Fallback to DP-1
      applications = [
        {
          package = "firefox";
          command = "firefox";
          wmClass = "firefox";
          launchDelay = 2.0;
        }
      ];
    }
  ];
};
```

---

## Keybinding Integration

Add to your i3 config for quick access:

```nix
# In modules/desktop/i3wm.nix or similar
services.xserver.windowManager.i3.config = ''
  # Project activation menu (requires rofi)
  bindsym $mod+p exec --no-startup-id i3-project-menu

  # Quick project shortcuts
  bindsym $mod+Shift+1 exec --no-startup-id i3-project activate dev-simple
  bindsym $mod+Shift+2 exec --no-startup-id i3-project activate full-stack
  bindsym $mod+Shift+3 exec --no-startup-id i3-project activate api-work

  # List active projects
  bindsym $mod+Shift+p exec --no-startup-id i3-project status | rofi -dmenu
'';
```

Where `i3-project-menu` is a simple rofi script:

```bash
#!/usr/bin/env bash
# i3-project-menu
project=$(i3-project list --json | jq -r '.projects[].name' | rofi -dmenu -p "Activate Project")
[ -n "$project" ] && i3-project activate "$project"
```

---

## Troubleshooting

### Applications Don't Launch

**Problem**: `i3-project activate` succeeds but no windows appear

**Solutions**:
1. Check application is installed:
   ```bash
   which firefox
   which alacritty
   ```

2. Increase `launchDelay`:
   ```nix
   launchDelay = 3.0;  # Try higher value
   ```

3. Check logs:
   ```bash
   journalctl --user -u i3 -f
   ```

### Wrong Workspace Assignment

**Problem**: Applications appear on wrong workspaces

**Solutions**:
1. Use `for_window` rules instead of `assign` for Spotify and similar apps

2. Check WM_CLASS values:
   ```bash
   xprop WM_CLASS  # Then click the window
   ```

3. Ensure `wmClass` in config matches actual window class

### Layout Doesn't Restore

**Problem**: Layout file doesn't work correctly

**Solutions**:
1. Verify layout file was post-processed:
   ```bash
   grep -v "//" ~/.config/i3/layouts/my-layout.json
   ```

2. Ensure swallows criteria uncommented

3. Try regenerating layout:
   ```bash
   i3-save-tree --workspace 1 > layout.json
   sed -i 's|^\(\s*\)// "|\1"|g; /^\s*\/\//d' layout.json
   ```

### Project Won't Close

**Problem**: `i3-project close` doesn't terminate all applications

**Solutions**:
1. Use `--force` flag:
   ```bash
   i3-project close my-project --force
   ```

2. Check for orphaned processes:
   ```bash
   ps aux | grep firefox
   ```

3. Manually kill if needed:
   ```bash
   killall firefox
   ```

---

## Next Steps

### Beginner

1. ✓ Define 1-2 simple projects
2. ✓ Practice activate/close workflow
3. Try capturing an existing layout
4. Add keybindings for favorite projects

### Intermediate

1. Create multi-workspace projects
2. Use working directory configurations
3. Experiment with layout files
4. Configure application aliases
5. Set up rofi integration

### Advanced

1. Multi-monitor project configurations
2. Conditional application launching
3. Project templates with parameterized directories
4. Custom launch scripts
5. Integration with tmux sessions

---

## Common Patterns

### Pattern: Project Template

Create reusable patterns for similar projects:

```nix
let
  makeApiProject = name: dir: {
    displayName = "${name} API Development";
    primaryWorkspace = "1";
    workingDirectory = dir;
    workspaces = [{
      number = "1";
      applications = [
        {
          package = "alacritty";
          command = "alacritty";
          wmClass = "Alacritty";
          workingDirectory = dir;
          launchDelay = 0.3;
        }
        {
          package = "vscode";
          command = "code";
          wmClass = "Code";
          args = ["${dir}"];
          launchDelay = 2.0;
        }
      ];
    }];
  };
in {
  programs.i3Projects.projects = {
    users-api = makeApiProject "Users" /home/user/projects/users-api;
    orders-api = makeApiProject "Orders" /home/user/projects/orders-api;
    products-api = makeApiProject "Products" /home/user/projects/products-api;
  };
}
```

### Pattern: Conditional Applications

```nix
let
  baseApps = [
    { package = "alacritty"; command = "alacritty"; wmClass = "Alacritty"; launchDelay = 0.3; }
    { package = "firefox"; command = "firefox"; wmClass = "firefox"; launchDelay = 2.0; }
  ];

  # Add vscode only if available
  allApps = baseApps ++ lib.optionals (pkgs ? vscode) [
    { package = "vscode"; command = "code"; wmClass = "Code"; launchDelay = 2.0; }
  ];
in {
  programs.i3Projects.projects.my-project = {
    workspaces = [{ number = "1"; applications = allApps; }];
  };
}
```

---

## Useful Commands Reference

```bash
# Activation
i3-project activate <name>       # Activate project
i3-project a <name>               # Short form
i3-project activate <name> --dry-run  # Preview without executing

# Information
i3-project list                   # List all projects
i3-project list --active          # Show only active
i3-project status                 # Show all active projects
i3-project status <name>          # Show specific project

# Management
i3-project close <name>           # Close project gracefully
i3-project close <name> --force   # Force close
i3-project switch <name>          # Quick switch
i3-project reload                 # Reload config

# Capture
i3-project-capture <name>         # Capture all workspaces
i3-project-capture <name> -w 1    # Capture workspace 1 only
i3-project-capture <name> --no-layouts  # Skip layout files

# Help
i3-project help                   # General help
i3-project help activate          # Command-specific help
```

---

## Related Documentation

- **Full Documentation**: `/etc/nixos/docs/I3_PROJECT_WORKSPACE.md` (to be created)
- **Data Model**: `./data-model.md`
- **CLI Contract**: `./contracts/i3-project-cli.md`
- **Research**: `./research.md`
- **Implementation Plan**: `./plan.md`

---

**Quickstart Version**: 1.0
**Last Updated**: 2025-10-17

**Next**: Run `sudo nixos-rebuild switch --flake .#hetzner` after adding your first project definition!
