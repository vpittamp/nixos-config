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

    # Auto-detect and set I3SOCK if not already set
    # Finds the most recently modified i3 IPC socket for the current user
    if [[ -z "$I3SOCK" ]]; then
      # Look for i3 sockets in user runtime directory
      if [[ -d "/run/user/$UID/i3" ]]; then
        # Find the most recently modified socket
        I3SOCK=$(ls -t /run/user/$UID/i3/ipc-socket.* 2>/dev/null | head -1)
        if [[ -n "$I3SOCK" ]]; then
          export I3SOCK
        fi
      fi
    fi

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
      bc  # For delay calculations in i3-project

      # Main i3-project CLI tool (will be expanded in Phase 3)
      (pkgs.writeShellScriptBin "i3-project" ''
        #!/usr/bin/env bash
        # i3-project - i3 Project Workspace Management
        # Version: 1.0 - Phase 3 Implementation

        source ${i3ProjectLib}

        CONFIG_FILE="$HOME/.config/i3-projects/projects.json"
        STATE_DIR="/tmp/i3-projects"
        DRY_RUN=false
        VERBOSE=false

        mkdir -p "$STATE_DIR"

        log() { [[ "$VERBOSE" == "true" ]] && echo "[i3-project] $*" >&2; }
        error() { echo "Error: $*" >&2; exit 1; }

        # T012: Load and validate project configuration
        load_project() {
          local name="$1"
          [[ -f "$CONFIG_FILE" ]] || error "Config file not found: $CONFIG_FILE"

          local project=$(${pkgs.jq}/bin/jq -r ".projects[\"$name\"] // empty" "$CONFIG_FILE")
          [[ -n "$project" ]] || error "Project '$name' not found"
          [[ "$(echo "$project" | ${pkgs.jq}/bin/jq -r '.enabled // true')" == "true" ]] || error "Project '$name' is disabled"

          echo "$project"
        }

        # T013-T014, T026-T028: Activate project (switch workspaces, launch apps)
        cmd_activate() {
          local name="$1"
          local override_dir=""

          # T026: Parse --dir flag
          shift
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --dir) override_dir="$2"; shift 2 ;;
              *) error "Unknown option: $1" ;;
            esac
          done

          [[ -n "$name" ]] || error "Usage: i3-project activate <name> [--dir <directory>]"

          i3_is_running || error "i3 is not running"

          local project=$(load_project "$name")
          local display_name=$(echo "$project" | ${pkgs.jq}/bin/jq -r '.displayName')
          local project_wd=$(echo "$project" | ${pkgs.jq}/bin/jq -r '.workingDirectory // empty')

          # T026: Use override if provided, otherwise use project default
          local working_dir="''${override_dir:-$project_wd}"

          # T030: Validate working directory exists
          if [[ -n "$working_dir" ]]; then
            # Expand ~ to home directory
            working_dir="''${working_dir/#\~/$HOME}"
            if [[ ! -d "$working_dir" ]]; then
              error "Working directory does not exist: $working_dir"
            fi
          fi

          echo "Activating project: $display_name"
          [[ -n "$working_dir" ]] && log "Working directory: $working_dir"

          local state_file="$STATE_DIR/$name.state"
          local workspaces=$(echo "$project" | ${pkgs.jq}/bin/jq -c '.workspaces[]')

          [[ "$DRY_RUN" == "true" ]] && { echo "[DRY-RUN] Would activate project $name in $working_dir"; return 0; }

          # T031: Initialize state with config file timestamp for change detection
          local config_mtime=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo 0)
          echo "{\"name\":\"$name\",\"startTime\":$(date +%s),\"configMtime\":$config_mtime,\"pids\":[],\"workspaces\":[]}" > "$state_file"

          # T013: Process each workspace
          while IFS= read -r ws; do
            local ws_num=$(echo "$ws" | ${pkgs.jq}/bin/jq -r '.number')
            local ws_output=$(echo "$ws" | ${pkgs.jq}/bin/jq -r '.output // empty')

            log "Processing workspace $ws_num"
            i3_workspace_switch "$ws_num"

            # T014, T027-T028: Launch applications
            local apps=$(echo "$ws" | ${pkgs.jq}/bin/jq -c '.applications[]')
            while IFS= read -r app; do
              local cmd=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.command')
              local args=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.args[]? // empty' | tr '\n' ' ')
              local app_wd=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.workingDirectory // empty')
              local delay=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.launchDelay // 0')
              local use_sesh=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.useSesh // false')
              local sesh_session=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.seshSession // empty')

              # Expand tildes in arguments
              # Convert "~/stacks" to "/home/user/stacks"
              if [[ -n "$args" ]]; then
                local expanded_args=""
                for arg in $args; do
                  arg="''${arg/#\~/$HOME}"
                  expanded_args="$expanded_args $arg"
                done
                args="''${expanded_args# }"  # Trim leading space
              fi

              # T027: Determine working directory (app-specific > override > project default)
              local final_wd="''${app_wd:-$working_dir}"

              # T030: Validate app-specific working directory
              if [[ -n "$final_wd" ]]; then
                final_wd="''${final_wd/#\~/$HOME}"
                if [[ ! -d "$final_wd" ]]; then
                  echo "Warning: Working directory does not exist for $cmd: $final_wd" >&2
                  echo "Continuing without working directory..." >&2
                  final_wd=""
                fi
              fi

              # Handle sesh integration for terminal applications
              if [[ "$use_sesh" == "true" ]]; then
                # Determine session name (explicit > project name)
                local session="''${sesh_session:-$name}"

                # Transform command to use sesh
                # e.g., "alacritty" becomes "alacritty -e sesh connect nixos"
                args="-e sesh connect $session $args"

                log "Launching: $cmd with sesh session '$session'"
              else
                log "Launching: $cmd $args"
              fi

              [[ -n "$final_wd" ]] && log "  in directory: $final_wd"

              (
                [[ -n "$final_wd" ]] && cd "$final_wd"
                $cmd $args &
                echo $! >> "$state_file.pids"
              ) &

              [[ "$delay" -gt 0 ]] && sleep $(echo "scale=3; $delay/1000" | ${pkgs.bc}/bin/bc)
            done < <(echo "$apps")

            ${pkgs.jq}/bin/jq ".workspaces += [$ws_num]" "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
          done < <(echo "$workspaces")

          # T015: Focus primary workspace
          local primary=$(echo "$project" | ${pkgs.jq}/bin/jq -r '.primaryWorkspace')
          log "Focusing primary workspace: $primary"
          i3_workspace_switch "$primary"

          # T016: Save PIDs to state
          [[ -f "$state_file.pids" ]] && ${pkgs.jq}/bin/jq ".pids = [$(cat "$state_file.pids" | tr '\n' ',' | sed 's/,$//')] " "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
          rm -f "$state_file.pids"

          echo "Project '$display_name' activated successfully"
        }

        # T017: List projects
        cmd_list() {
          [[ -f "$CONFIG_FILE" ]] || error "Config file not found"

          echo "Available projects:"
          ${pkgs.jq}/bin/jq -r '.projects | to_entries[] | "\(.key)\t\(.value.displayName)\t\(.value.enabled // true)"' "$CONFIG_FILE" | \
          while IFS=$'\t' read -r name display enabled; do
            local status="inactive"
            [[ -f "$STATE_DIR/$name.state" ]] && status="active"
            [[ "$enabled" == "false" ]] && status="disabled"

            printf "%-20s %-30s [%s]\n" "$name" "$display" "$status"
          done
        }

        # T018: Show project status
        cmd_status() {
          local name="$1"

          if [[ -z "$name" ]]; then
            # Show all active projects
            for state in "$STATE_DIR"/*.state; do
              [[ -f "$state" ]] || continue
              local pname=$(basename "$state" .state)
              cmd_status "$pname"
            done
            return 0
          fi

          local state_file="$STATE_DIR/$name.state"
          [[ -f "$state_file" ]] || { echo "Project '$name' is not active"; return 1; }

          local state=$(cat "$state_file")
          local display=$(${pkgs.jq}/bin/jq -r '.name' <<<"$state")
          local start=$(${pkgs.jq}/bin/jq -r '.startTime' <<<"$state")
          local pids=$(${pkgs.jq}/bin/jq -r '.pids[]?' <<<"$state")
          local workspaces=$(${pkgs.jq}/bin/jq -r '.workspaces[]?' <<<"$state")

          # T031: Check if configuration has changed since activation
          local state_mtime=$(${pkgs.jq}/bin/jq -r '.configMtime // 0' <<<"$state")
          local current_mtime=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo 0)

          echo "Project: $display"
          echo "Started: $(date -d @$start)"
          echo "Workspaces: $workspaces"
          echo "Running processes: $(echo "$pids" | wc -w)"

          if [[ "$current_mtime" -gt "$state_mtime" ]]; then
            echo ""
            echo "⚠ Configuration has changed since activation"
            echo "  Consider running: i3-project close $name && i3-project activate $name"
          fi
        }

        # T019: Switch to project
        cmd_switch() {
          local name="$1"
          [[ -n "$name" ]] || error "Usage: i3-project switch <name>"

          local state_file="$STATE_DIR/$name.state"
          [[ -f "$state_file" ]] || error "Project '$name' is not active. Use 'activate' first."

          local project=$(load_project "$name")
          local primary=$(echo "$project" | ${pkgs.jq}/bin/jq -r '.primaryWorkspace')

          i3_workspace_switch "$primary"
          echo "Switched to project: $name (workspace $primary)"
        }

        # T020: Close project
        cmd_close() {
          local name="$1"
          local force=false
          [[ "$2" == "--force" ]] && force=true

          [[ -n "$name" ]] || error "Usage: i3-project close <name> [--force]"

          local state_file="$STATE_DIR/$name.state"
          [[ -f "$state_file" ]] || error "Project '$name' is not active"

          local pids=$(${pkgs.jq}/bin/jq -r '.pids[]?' "$state_file")

          echo "Closing project: $name"

          for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
              log "Terminating PID $pid"
              kill "$pid" 2>/dev/null || true
            fi
          done

          if [[ "$force" == "true" ]]; then
            sleep 1
            for pid in $pids; do
              kill -9 "$pid" 2>/dev/null || true
            done
          fi

          rm -f "$state_file"
          echo "Project '$name' closed"
        }

        # T025: Reload configuration
        cmd_reload() {
          echo "Reloading project configuration..."
          [[ -f "$CONFIG_FILE" ]] || error "Config file not found: $CONFIG_FILE"

          # Verify JSON is valid
          ${pkgs.jq}/bin/jq empty "$CONFIG_FILE" 2>/dev/null || error "Invalid JSON in config file"

          echo "Configuration loaded from: $CONFIG_FILE"
          echo ""
          cmd_list
        }

        show_help() {
          cat <<EOF
i3-project - i3 Project Workspace Management

Usage: i3-project <command> [options]

Commands:
  activate, a <name>    Activate a project
  list, ls              List all projects
  close, c <name>       Close a project
  status, st [name]     Show project status
  switch, sw <name>     Switch to active project
  reload, r             Reload configuration
  help                  Show this help

Options:
  --dry-run            Show what would be done
  --verbose, -v        Verbose output
  --help, -h           Show help

Examples:
  i3-project activate backend-dev
  i3-project activate backend-dev --dir ~/my-fork
  i3-project list
  i3-project status
  i3-project close backend-dev --force
  i3-project reload
EOF
        }

        # Parse global options
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            --verbose|-v) VERBOSE=true; shift ;;
            --help|-h) show_help; exit 0 ;;
            --version) echo "i3-project 1.0"; exit 0 ;;
            *) break ;;
          esac
        done

        COMMAND="''${1:-help}"
        shift || true

        case "$COMMAND" in
          activate|a) cmd_activate "$@" ;;
          list|ls) cmd_list "$@" ;;
          status|st) cmd_status "$@" ;;
          switch|sw) cmd_switch "$@" ;;
          close|c) cmd_close "$@" ;;
          reload|r) cmd_reload "$@" ;;
          help) show_help ;;
          *) error "Unknown command: $COMMAND. Run 'i3-project help' for usage." ;;
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
