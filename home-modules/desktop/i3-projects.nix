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

in
{
  options.programs.i3Projects = {
    enable = mkEnableOption "i3 project workspace management";

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

    # Project definitions (T004)
    projects = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          displayName = mkOption {
            type = types.str;
            description = "Human-readable project name for display";
            example = "API Backend Development";
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
        {
          backend-dev = {
            displayName = "Backend API Development";
            description = "Spring Boot API with database tools";
            primaryWorkspace = 1;
            workingDirectory = "/home/user/projects/backend";
            workspaces = [
              {
                number = 1;
                output = "DP-1";
                applications = [
                  {
                    package = pkgs.vscode;
                    command = "code";
                    args = ["."];
                    wmClass = "Code";
                  }
                  {
                    command = "alacritty";
                    wmClass = "Alacritty";
                  }
                ];
              }
            ];
          };
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
            floating = app.floating;
            position = app.position;
            size = app.size;
            # Note: package is resolved at build time, only command is in JSON
          }) ws.applications;
        }) proj.workspaces;
      }) enabledProjects;
    };
  };
}
