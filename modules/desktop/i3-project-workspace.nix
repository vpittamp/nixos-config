# i3 Project Workspace Management System - System Module
# Provides CLI tools and system-level configuration for i3 project workspaces
#
# This module provides:
# - i3-project: Main CLI for project management (activate, list, close, status, switch)
# - i3-project-capture: Layout capture tool
# - Shared library functions for i3 IPC and workspace management
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.i3ProjectWorkspace;

  # Shared library functions for i3 IPC and workspace management
  # Used by all i3-project commands
  i3ProjectLib = pkgs.writeShellScript "i3-project-lib.sh" ''
    # i3 Project Workspace Management - Shared Library Functions
    # Version: 1.0

    # Ensure PATH includes required tools
    export PATH="${pkgs.i3}/bin:${pkgs.jq}/bin:${pkgs.xdotool}/bin:${pkgs.xprop}/bin:${pkgs.wmctrl}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:$PATH"

    # Check if i3 is running
    i3_is_running() {
      ${pkgs.i3}/bin/i3-msg -t get_version &>/dev/null
      return $?
    }

    # Switch to a workspace
    i3_workspace_switch() {
      local workspace="$1"
      ${pkgs.i3}/bin/i3-msg "workspace number $workspace" &>/dev/null
    }

    # Get list of workspaces (JSON)
    i3_get_workspaces() {
      ${pkgs.i3}/bin/i3-msg -t get_workspaces
    }

    # Get list of outputs/monitors (JSON)
    i3_get_outputs() {
      ${pkgs.i3}/bin/i3-msg -t get_outputs
    }

    # Check if a package/command is available
    check_package_installed() {
      local cmd="$1"
      command -v "$cmd" &>/dev/null
      return $?
    }

    # Get active monitor names using xrandr
    get_active_monitors() {
      ${pkgs.xorg.xrandr}/bin/xrandr --listmonitors 2>/dev/null | \
        ${pkgs.gnugrep}/bin/grep -oP '(?<= )[A-Z0-9-]+$' || echo ""
    }

    # Wait for window to appear (using wmctrl)
    wait_for_window() {
      local class="$1"
      local timeout="''${2:-10}"
      local elapsed=0

      while [ $elapsed -lt $timeout ]; do
        if ${pkgs.wmctrl}/bin/wmctrl -lx 2>/dev/null | ${pkgs.gnugrep}/bin/grep -i "$class" > /dev/null; then
          return 0
        fi
        sleep 0.2
        ((elapsed++))
      done
      return 1
    }
  '';

in
{
  options.services.i3ProjectWorkspace = {
    enable = mkEnableOption "i3 project workspace management system";

    package = mkOption {
      type = types.package;
      default = pkgs.i3;
      description = "i3 package to use";
    };
  };

  config = mkIf cfg.enable {
    # Install required packages
    environment.systemPackages = with pkgs; [
      cfg.package
      jq
      xdotool
      xprop
      wmctrl
      xorg.xrandr

      # Main i3-project CLI tool (will be expanded in Phase 3)
      (pkgs.writeShellScriptBin "i3-project" ''
        #!/usr/bin/env bash
        # i3-project - i3 Project Workspace Management
        # Version: 1.0

        # Source shared library
        source ${i3ProjectLib}

        # Placeholder for Phase 3 implementation
        # This will contain: activate, list, close, status, switch commands

        show_help() {
          cat <<EOF
i3-project - i3 Project Workspace Management

Usage: i3-project <command> [options]

Commands:
  activate, a <name>   Activate a project (Phase 3)
  list, ls             List all projects (Phase 3)
  close, c <name>      Close a project (Phase 3)
  status, st [name]    Show project status (Phase 3)
  switch, sw <name>    Switch to a project (Phase 3)
  reload               Reload configurations (Phase 4)
  help [command]       Show help

Options:
  --help, -h           Show this help message
  --version, -v        Show version information

Note: Core functionality will be implemented in Phase 3 (User Story 1)

For more information: man i3-project (Phase 9)
EOF
        }

        # Parse command
        COMMAND="''${1:-help}"
        shift || true

        case "$COMMAND" in
          help|--help|-h)
            show_help
            ;;
          --version|-v)
            echo "i3-project version 1.0 (Phase 1 - Module Structure)"
            ;;
          *)
            echo "Error: Command '$COMMAND' not yet implemented"
            echo "Current phase: Phase 1 (Module Structure)"
            echo "Run 'i3-project help' for more information"
            exit 1
            ;;
        esac
      '')

      # i3-project-capture CLI tool (will be expanded in Phase 6)
      (pkgs.writeShellScriptBin "i3-project-capture" ''
        #!/usr/bin/env bash
        # i3-project-capture - Capture workspace layouts and generate project configs
        # Version: 1.0

        # Source shared library
        source ${i3ProjectLib}

        # Placeholder for Phase 6 implementation

        show_help() {
          cat <<EOF
i3-project-capture - Capture workspace layouts and generate project configs

Usage: i3-project-capture <project-name> [OPTIONS]

Arguments:
  <project-name>       Name for the captured project

Options:
  --workspace, -w <N>  Capture only specific workspace (default: all non-empty)
  --output-dir, -o <path>  Output directory (default: ~/.config/i3-projects/captured)
  --format, -f <format>    Output format: nix, json, or both (default: both)
  --include-empty      Include empty workspaces in capture
  --no-layouts         Skip layout file generation
  --verbose, -v        Show detailed capture process
  --help, -h           Show this help message

Note: Layout capture will be implemented in Phase 6 (User Story 4)

For more information: man i3-project-capture (Phase 9)
EOF
        }

        # Parse command
        case "''${1:-}" in
          --help|-h|help)
            show_help
            ;;
          *)
            echo "Error: i3-project-capture not yet implemented"
            echo "Current phase: Phase 1 (Module Structure)"
            echo "Run 'i3-project-capture --help' for more information"
            exit 1
            ;;
        esac
      '')
    ];

    # Conditional activation based on i3wm presence (T011)
    assertions = [
      {
        assertion = config.services.i3wm.enable or false;
        message = "i3 Project Workspace requires i3wm to be enabled (services.i3wm.enable = true)";
      }
    ];
  };
}
