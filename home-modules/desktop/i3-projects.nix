# i3 Projects - Home Manager Module
# Declarative project workspace definitions for i3
#
# This module allows users to define project environments in their home-manager configuration
# Projects are collections of applications with specific workspace assignments and layouts
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.i3Projects;

  # Filter enabled projects
  enabledProjects = filterAttrs (name: proj: proj.enabled or true) cfg.projects;

  # Application configuration type (T006)
  applicationConfigType = types.submodule {
      options = {
        package = mkOption {
          type = types.nullOr types.package;
          default = null;
          description = "Nix package for the application";
          example = literalExpression "pkgs.firefox";
        };

        command = mkOption {
          type = types.str;
          description = "Command to execute (binary name or full path)";
          example = "firefox";
        };

        wmClass = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "X11 WM_CLASS for window matching";
          example = "Firefox";
        };

        wmInstance = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "X11 WM_INSTANCE for window matching";
        };

        workingDirectory = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Working directory for the application";
          example = "/home/user/projects/backend";
        };

        args = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Command-line arguments";
          example = ["--new-window" "https://example.com"];
        };

        instanceBehavior = mkOption {
          type = types.enum ["new" "reuse" "focus"];
          default = "new";
          description = ''
            How to handle existing instances:
            - new: Always launch new instance
            - reuse: Reuse existing instance if found
            - focus: Just focus existing instance
          '';
        };

        launchDelay = mkOption {
          type = types.ints.unsigned;
          default = 0;
          description = "Delay in milliseconds before launching";
        };

        useSesh = mkOption {
          type = types.bool;
          default = false;
          description = "Launch terminal with sesh tmux session manager";
        };

        seshSession = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Sesh session name (defaults to project name if not specified)";
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
          description = "Window position for floating windows";
        };

        size = mkOption {
          type = types.nullOr (types.submodule {
            options = {
              width = mkOption { type = types.int; };
              height = mkOption { type = types.int; };
            };
          });
          default = null;
          description = "Window size for floating windows";
        };

        # T001: Enhanced schema for project-scoped applications
        projectScoped = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether this application is project-scoped (hidden when switching projects)
            or global (always visible across all projects).

            Project-scoped: VS Code, Ghostty, lazygit, yazi
            Global: Firefox, YouTube PWA, K9s
          '';
        };

        monitorPriority = mkOption {
          type = types.ints.positive;
          default = 2;
          description = ''
            Monitor assignment priority for multi-monitor setups.
            Lower numbers = higher priority (assigned to primary monitors first).

            Priority 1: Primary monitor (critical applications like terminal, IDE)
            Priority 2: Secondary monitor (supporting tools)
            Priority 3: Tertiary monitor (background applications)
          '';
        };
      };
    };

  # Workspace configuration type (T005)
  workspaceConfigType = types.submodule {
      options = {
        number = mkOption {
          type = types.ints.positive;
          description = "Workspace number (1-10 typical)";
          example = 1;
        };

        output = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Primary output/monitor for this workspace";
          example = "DP-1";
        };

        outputs = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "List of valid outputs for this workspace";
          example = ["DP-1" "HDMI-1"];
        };

        applications = mkOption {
          type = types.listOf applicationConfigType;
          default = [];
          description = "Applications to launch in this workspace";
        };

        layout = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Path to i3 layout JSON file";
        };

        layoutMode = mkOption {
          type = types.enum ["manual" "restore" "auto"];
          default = "manual";
          description = ''
            How to handle workspace layout:
            - manual: User arranges windows manually
            - restore: Restore from saved layout file
            - auto: Auto-arrange based on application order
          '';
        };
      };
    };

in
{
  options.programs.i3Projects = {
    enable = mkEnableOption "i3 project workspace management";

    # Project definitions (T004)
    projects = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          displayName = mkOption {
            type = types.str;
            description = "Human-readable project name for display";
            example = "API Backend Development";
          };

          icon = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Icon to display for the project (emoji or nerd font icon)";
            example = "";
          };

          description = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional project description";
          };

          enabled = mkOption {
            type = types.bool;
            default = true;
            description = "Whether this project is active";
          };

          workspaces = mkOption {
            type = types.listOf workspaceConfigType;
            default = [];
            description = "Workspace configurations for this project";
          };

          primaryWorkspace = mkOption {
            type = types.ints.positive;
            default = 1;
            description = "Primary workspace to focus after activation";
          };

          workingDirectory = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default working directory for the project";
          };

          autostart = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to auto-start project on i3 startup";
          };
        };
      });
      default = {};
      description = ''
        Project definitions for i3 workspace management.

        Each project represents a complete development environment with:
        - Multiple workspaces across monitors
        - Application assignments with launch parameters
        - Layout configurations
        - Working directory context
      '';
      example = literalExpression ''
        # T024: Complete working example with all options documented
        {
          # Simple single-workspace project
          quick-notes = {
            displayName = "Quick Notes";
            description = "Simple note-taking environment";
            primaryWorkspace = 9;
            workingDirectory = "$HOME/Documents/notes";
            workspaces = [
              {
                number = 9;
                applications = [
                  {
                    command = "alacritty";
                    wmClass = "Alacritty";
                  }
                  {
                    package = pkgs.obsidian;
                    command = "obsidian";
                    wmClass = "obsidian";
                  }
                ];
              }
            ];
          };

          # Complex multi-workspace project
          backend-dev = {
            displayName = "Backend API Development";
            description = "Full-stack development with IDE, terminals, and database tools";
            primaryWorkspace = 1;
            workingDirectory = "/home/user/projects/backend";
            autostart = false;  # Don't auto-start on i3 launch

            workspaces = [
              # Workspace 1: Code editor and terminal
              {
                number = 1;
                output = "DP-1";  # Primary monitor
                layoutMode = "manual";
                applications = [
                  {
                    package = pkgs.vscode;
                    command = "code";
                    args = ["."];  # Open current directory
                    wmClass = "Code";
                    instanceBehavior = "new";
                  }
                  {
                    command = "alacritty";
                    wmClass = "Alacritty";
                    workingDirectory = "/home/user/projects/backend";
                  }
                ];
              }

              # Workspace 2: Browser and API testing
              {
                number = 2;
                output = "DP-1";
                applications = [
                  {
                    package = pkgs.firefox;
                    command = "firefox";
                    args = ["--new-window" "http://localhost:8080"];
                    wmClass = "Firefox";
                    instanceBehavior = "new";
                    launchDelay = 1000;  # Wait 1s before launching
                  }
                  {
                    package = pkgs.postman;
                    command = "postman";
                    wmClass = "Postman";
                    launchDelay = 2000;
                  }
                ];
              }

              # Workspace 3: Database tools
              {
                number = 3;
                output = "HDMI-1";  # Secondary monitor
                applications = [
                  {
                    package = pkgs.dbeaver;
                    command = "dbeaver";
                    wmClass = "DBeaver";
                  }
                  {
                    command = "alacritty";
                    args = ["-e" "psql" "-U" "postgres"];
                    wmClass = "Alacritty";
                  }
                ];
              }
            ];
          };

          # T029: Template-based project examples
          # You can create helper functions for common project patterns in your configuration:

          # Example 1: Simple single-workspace template
          # let
          #   makeSimpleProject = { name, displayName, workspace ? 9, apps }:
          #     {
          #       inherit displayName;
          #       primaryWorkspace = workspace;
          #       workspaces = [{
          #         number = workspace;
          #         applications = apps;
          #       }];
          #     };
          # in {
          #   quick-notes = makeSimpleProject {
          #     name = "quick-notes";
          #     displayName = "Quick Notes";
          #     workspace = 9;
          #     apps = [
          #       { command = "alacritty"; wmClass = "Alacritty"; }
          #       { package = pkgs.obsidian; command = "obsidian"; wmClass = "obsidian"; }
          #     ];
          #   };
          # }

          # Example 2: Full-stack development template
          # let
          #   makeDevProject = { name, displayName, workingDir, editor, browser, workspace ? 1 }:
          #     {
          #       inherit displayName workingDir;
          #       primaryWorkspace = workspace;
          #       workspaces = [
          #         {
          #           number = workspace;
          #           applications = [
          #             { package = editor; command = editor.pname or editor.name; wmClass = "Code"; args = ["."]; }
          #             { command = "alacritty"; wmClass = "Alacritty"; }
          #           ];
          #         }
          #         {
          #           number = workspace + 1;
          #           applications = [
          #             { package = browser; command = browser.pname or browser.name; wmClass = "Firefox"; args = ["--new-window" "http://localhost:3000"]; launchDelay = 1000; }
          #           ];
          #         }
          #       ];
          #     };
          # in {
          #   frontend-dev = makeDevProject {
          #     name = "frontend-dev";
          #     displayName = "Frontend Development";
          #     workingDir = "/home/user/projects/frontend";
          #     editor = pkgs.vscode;
          #     browser = pkgs.firefox;
          #   };
          # }

          # Example 3: Multi-monitor project template
          # let
          #   makeMultiMonitorProject = { name, displayName, workingDir, primaryOutput, secondaryOutput }:
          #     {
          #       inherit displayName workingDir;
          #       primaryWorkspace = 1;
          #       workspaces = [
          #         {
          #           number = 1;
          #           output = primaryOutput;
          #           applications = [
          #             { package = pkgs.vscode; command = "code"; args = ["."]; wmClass = "Code"; }
          #           ];
          #         }
          #         {
          #           number = 2;
          #           output = secondaryOutput;
          #           applications = [
          #             { package = pkgs.firefox; command = "firefox"; wmClass = "Firefox"; }
          #           ];
          #         }
          #       ];
          #     };
          # in {
          #   backend-dev = makeMultiMonitorProject {
          #     name = "backend-dev";
          #     displayName = "Backend API Development";
          #     workingDir = "/home/user/projects/backend";
          #     primaryOutput = "DP-1";
          #     secondaryOutput = "HDMI-1";
          #   };
          # }
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    # T007: Configuration validation assertions
    assertions = [
      # Validate unique project names (implicit by attrsOf)

      # Validate workspace references
      {
        assertion = all (proj:
          proj.primaryWorkspace > 0 &&
          (length proj.workspaces == 0 || any (ws: ws.number == proj.primaryWorkspace) proj.workspaces)
        ) (attrValues enabledProjects);
        message = "All projects must have a valid primaryWorkspace that exists in their workspaces list";
      }

      # Validate packages exist
      {
        assertion = all (proj:
          all (ws:
            all (app:
              app.package == null || app.package ? outPath
            ) ws.applications
          ) proj.workspaces
        ) (attrValues enabledProjects);
        message = "All application packages must be valid Nix packages";
      }

      # Validate workspace numbers are unique per project
      {
        assertion = all (proj:
          let
            wsNumbers = map (ws: ws.number) proj.workspaces;
            uniqueNumbers = unique wsNumbers;
          in
          length wsNumbers == length uniqueNumbers
        ) (attrValues enabledProjects);
        message = "Workspace numbers must be unique within each project";
      }
    ];

    # Create config directory structure
    xdg.configFile."i3-projects/.keep".text = "";
    xdg.configFile."i3-projects/captured/.keep".text = "";
    xdg.configFile."i3-projects/captured/layouts/.keep".text = "";

    # T008: Generate JSON configuration file from Nix definitions
    xdg.configFile."i3-projects/projects.json".text = builtins.toJSON {
      version = "1.0";
      generated = "NixOS home-manager (i3-projects.nix)";
      generatedAt = "build-time";

      projects = mapAttrs (name: proj: {
        displayName = proj.displayName;
        icon = proj.icon;
        description = proj.description;
        enabled = proj.enabled;
        primaryWorkspace = proj.primaryWorkspace;
        workingDirectory = proj.workingDirectory;
        autostart = proj.autostart;

        workspaces = map (ws: {
          number = ws.number;
          output = ws.output;
          outputs = ws.outputs;
          layoutMode = ws.layoutMode;
          layout = ws.layout;

          applications = map (app: {
            command = app.command;
            wmClass = app.wmClass;
            wmInstance = app.wmInstance;
            workingDirectory = app.workingDirectory;
            args = app.args;
            instanceBehavior = app.instanceBehavior;
            launchDelay = app.launchDelay;
            useSesh = app.useSesh;
            seshSession = app.seshSession;
            floating = app.floating;
            position = app.position;
            size = app.size;
            # T001: Include new project-scoped fields
            projectScoped = app.projectScoped;
            monitorPriority = app.monitorPriority;
            # Note: package is resolved at build time, only command is in JSON
          }) ws.applications;
        }) proj.workspaces;
      }) enabledProjects;
    };

    # Project management scripts with proper Nix paths
    home.file.".config/i3/scripts/project-current.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # Get current active project
        # Returns JSON or empty if no project active

        STATE_FILE=~/.config/i3/current-project

        if [ ! -f "$STATE_FILE" ]; then
          echo "{}"
          exit 0
        fi

        # Check if state is stale (> 24 hours old)
        if [ -f "$STATE_FILE" ]; then
          ACTIVATED=$(${pkgs.jq}/bin/jq -r '.activated_at // empty' "$STATE_FILE")
          if [ -n "$ACTIVATED" ]; then
            ACTIVATED_EPOCH=$(${pkgs.coreutils}/bin/date -d "$ACTIVATED" +%s 2>/dev/null || echo 0)
            NOW_EPOCH=$(${pkgs.coreutils}/bin/date +%s)
            AGE=$((NOW_EPOCH - ACTIVATED_EPOCH))

            # If > 24 hours, consider stale and fall back to auto-detect
            if [ $AGE -gt 86400 ]; then
              echo "{}" >&2
              exit 0
            fi
          fi
        fi

        ${pkgs.coreutils}/bin/cat "$STATE_FILE"
      '';
    };

    home.file.".config/i3/scripts/project-set.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # Set active project

        PROJECT_ID="$1"
        PROJECTS_FILE=~/.config/i3-projects/projects.json
        STATE_FILE=~/.config/i3/current-project

        if [ -z "$PROJECT_ID" ]; then
          echo "Usage: $0 <project_id>" >&2
          echo "Available projects:" >&2
          ${pkgs.jq}/bin/jq -r '.projects | keys[]' "$PROJECTS_FILE" >&2
          exit 1
        fi

        # Get project info
        PROJECT_INFO=$(${pkgs.jq}/bin/jq -r --arg id "$PROJECT_ID" '.projects[$id]' "$PROJECTS_FILE")

        if [ "$PROJECT_INFO" = "null" ] || [ -z "$PROJECT_INFO" ]; then
          echo "Error: Project '$PROJECT_ID' not found" >&2
          exit 1
        fi

        # T009: Read current project BEFORE updating state
        OLD_PROJECT=""
        if [ -f "$STATE_FILE" ]; then
          OLD_PROJECT=$(${pkgs.jq}/bin/jq -r '.project_id // empty' "$STATE_FILE" 2>/dev/null || echo "")
        fi

        # Create state with metadata
        ${pkgs.jq}/bin/jq -n \
          --arg id "$PROJECT_ID" \
          --argjson info "$PROJECT_INFO" \
          --arg timestamp "$(${pkgs.coreutils}/bin/date -Iseconds)" \
          '{
            mode: "manual",
            override: true,
            project_id: $id,
            name: $info.displayName,
            directory: $info.workingDirectory,
            icon: ($info.icon // ""),
            activated_at: $timestamp
          }' > "$STATE_FILE"

        echo "✓ Active project set to: $(${pkgs.jq}/bin/jq -r '.name' "$STATE_FILE")"

        # T009: Detect monitors and assign workspaces
        if command -v ~/.config/i3/scripts/detect-monitors.sh > /dev/null 2>&1; then
          ~/.config/i3/scripts/assign-workspace-monitor.sh 2>/dev/null || true
        fi

        # T009: Call project-switch-hook to show/hide windows
        # Pass both old and new project to the hook
        if [ "$OLD_PROJECT" != "$PROJECT_ID" ] && command -v ~/.config/i3/scripts/project-switch-hook.sh > /dev/null 2>&1; then
          ~/.config/i3/scripts/project-switch-hook.sh "$OLD_PROJECT" "$PROJECT_ID"
        fi

        # Optional: Switch to first workspace of project
        if [ "$2" = "--switch" ]; then
          FIRST_WS=$(${pkgs.jq}/bin/jq -r '.primaryWorkspace' <<< "$PROJECT_INFO")
          i3-msg "workspace number $FIRST_WS" > /dev/null 2>&1 || true
          echo "  Switched to workspace $FIRST_WS"
        fi
      '';
    };

    home.file.".config/i3/scripts/project-clear.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # T046: Clear active project (return to global mode)

        STATE_FILE=~/.config/i3/current-project

        # T046: Read old project before clearing
        OLD_PROJECT=""
        if [ -f "$STATE_FILE" ]; then
          OLD_PROJECT=$(${pkgs.jq}/bin/jq -r '.project_id // empty' "$STATE_FILE" 2>/dev/null || echo "")
          PREV_PROJECT_NAME=$(${pkgs.jq}/bin/jq -r '.name // "None"' "$STATE_FILE")
          ${pkgs.coreutils}/bin/rm "$STATE_FILE"
          echo "✓ Cleared active project (was: $PREV_PROJECT_NAME)"
        else
          echo "No active project to clear"
          exit 0
        fi

        # T046: Call project-switch-hook with empty new project to show all windows
        if [ -n "$OLD_PROJECT" ] && command -v ~/.config/i3/scripts/project-switch-hook.sh > /dev/null 2>&1; then
          ~/.config/i3/scripts/project-switch-hook.sh "$OLD_PROJECT" ""
        fi
      '';
    };

    home.file.".config/i3/scripts/project-switcher.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # Interactive project switcher using rofi

        PROJECTS_FILE=~/.config/i3-projects/projects.json
        CURRENT=$(~/.config/i3/scripts/project-current.sh | ${pkgs.jq}/bin/jq -r '.project_id // empty')

        # Build rofi list with current project highlighted
        PROJECT_LIST=$(${pkgs.jq}/bin/jq -r '.projects | to_entries[] | "\(.value.icon // "") \(.value.displayName)\t\(.key)"' "$PROJECTS_FILE")

        # Add "Clear Project" option
        PROJECT_LIST="󰅖 Clear Project (Global Mode)	__clear__
        $PROJECT_LIST"

        # Show rofi menu
        SELECTED=$(${pkgs.coreutils}/bin/echo "$PROJECT_LIST" | ${pkgs.rofi}/bin/rofi -dmenu -i -p "Project" -format 's' -selected-row 0)

        if [ -z "$SELECTED" ]; then
          exit 0
        fi

        PROJECT_ID=$(${pkgs.coreutils}/bin/echo "$SELECTED" | ${pkgs.gawk}/bin/awk '{print $NF}')

        if [ "$PROJECT_ID" = "__clear__" ]; then
          ~/.config/i3/scripts/project-clear.sh
        else
          ~/.config/i3/scripts/project-set.sh "$PROJECT_ID" --switch
        fi
      '';
    };

    # T002: Deploy project-switch-hook.sh
    home.file.".config/i3/scripts/project-switch-hook.sh" = {
      executable = true;
      text = builtins.readFile ../../scripts/project-switch-hook.sh;
    };

    # T003/T007: Deploy monitor detection scripts
    home.file.".config/i3/scripts/detect-monitors.sh" = {
      executable = true;
      text = builtins.readFile ../../scripts/detect-monitors.sh;
    };

    # T008: Deploy workspace-monitor assignment script
    home.file.".config/i3/scripts/assign-workspace-monitor.sh" = {
      executable = true;
      text = builtins.readFile ../../scripts/assign-workspace-monitor.sh;
    };

    # T018-T021: Deploy project-aware launcher scripts
    home.file.".config/i3/scripts/launch-code.sh" = {
      executable = true;
      text = builtins.readFile ../../scripts/launch-code.sh;
    };

    home.file.".config/i3/scripts/launch-ghostty.sh" = {
      executable = true;
      text = builtins.readFile ../../scripts/launch-ghostty.sh;
    };

    home.file.".config/i3/scripts/launch-lazygit.sh" = {
      executable = true;
      text = builtins.readFile ../../scripts/launch-lazygit.sh;
    };

    home.file.".config/i3/scripts/launch-yazi.sh" = {
      executable = true;
      text = builtins.readFile ../../scripts/launch-yazi.sh;
    };

    # T027: Override desktop entries to use launcher scripts
    # This ensures rofi/application menus launch project-aware versions
    xdg.dataFile."applications/code.desktop" = {
      text = ''
        [Desktop Entry]
        Actions=new-empty-window
        Categories=Utility;TextEditor;Development;IDE
        Comment=Code Editing. Redefined.
        Exec=${config.home.homeDirectory}/.config/i3/scripts/launch-code.sh %F
        GenericName=Text Editor
        Icon=vscode
        Keywords=vscode
        Name=Visual Studio Code
        StartupNotify=true
        StartupWMClass=Code
        Type=Application
        Version=1.5

        [Desktop Action new-empty-window]
        Exec=${config.home.homeDirectory}/.config/i3/scripts/launch-code.sh --new-window %F
        Icon=vscode
        Name=New Empty Window
      '';
    };
  };
}
