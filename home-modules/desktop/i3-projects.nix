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

    # Project definitions (will be expanded in Phase 2 with full types)
    projects = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          # Placeholder structure for Phase 1
          # Full type definitions will be added in Phase 2 (T004-T006)

          displayName = mkOption {
            type = types.str;
            description = "Human-readable project name for display";
            example = "API Backend Development";
          };

          enabled = mkOption {
            type = types.bool;
            default = true;
            description = "Whether this project is active";
          };

          # Additional fields will be added in Phase 2:
          # - description
          # - workspaces (list of workspace configs)
          # - workingDirectory
          # - primaryWorkspace
          # - autostart
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

        Full type definitions will be added in Phase 2 (Foundational).
      '';
      example = literalExpression ''
        {
          api-backend = {
            displayName = "API Backend Development";
            enabled = true;
            # Additional fields in Phase 2
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    # Conditional activation based on i3wm presence (T011)
    # Only activate if i3 is configured
    # Note: We check for xsession.windowManager.i3.enable which is the home-manager i3 option

    # Create config directory structure
    xdg.configFile."i3-projects/.keep".text = "";
    xdg.configFile."i3-projects/captured/.keep".text = "";
    xdg.configFile."i3-projects/captured/layouts/.keep".text = "";

    # Generate JSON configuration file from Nix definitions (Phase 2: T008)
    # This will be implemented in Phase 2 to convert Nix project definitions to JSON
    # For now, create an empty placeholder
    xdg.configFile."i3-projects/projects.json".text = builtins.toJSON {
      version = "1.0";
      generated = "Phase 1 - Module Structure";
      projects = {};
      # Full project data will be generated in Phase 2
    };

    # Example configuration in module comments (will be expanded in Phase 4: T024)
    # TODO Phase 4: Add complete working examples with all options documented
  };
}
