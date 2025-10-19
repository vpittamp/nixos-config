# i3 Project Manager - Dynamic Runtime Project Management
# Home Manager Module for i3-native project workspace management
#
# This module provides dynamic project management using i3's native features:
# - Runtime JSON configuration files (no rebuild required)
# - i3 marks for window-project association
# - i3 scratchpad for window visibility management
# - i3 tick events for real-time synchronization
# - i3 append_layout for workspace restoration
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.i3ProjectManager;

  # T005: Common functions library (declaratively generated)
  # Replaces source-based common.sh with inline Nix string
  commonFunctions = ''
    # Configuration constants
    PROJECT_DIR="$HOME/.config/i3/projects"
    ACTIVE_PROJECT_FILE="$HOME/.config/i3/active-project"
    APP_CLASSES_FILE="$HOME/.config/i3/app-classes.json"
    LOG_FILE="$HOME/.config/i3/project-manager.log"
    MAX_LOG_SIZE=1048576  # 1MB

    # Enable debug mode if environment variable is set
    DEBUG="''${I3_PROJECT_DEBUG:-0}"

    # Color codes for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color

    #######################################
    # Initialization
    #######################################

    # Ensure active-project file exists and is writable
    if [ -L "$ACTIVE_PROJECT_FILE" ]; then
        ${pkgs.coreutils}/bin/rm -f "$ACTIVE_PROJECT_FILE"
        ${pkgs.coreutils}/bin/touch "$ACTIVE_PROJECT_FILE"
    elif [ ! -f "$ACTIVE_PROJECT_FILE" ]; then
        ${pkgs.coreutils}/bin/touch "$ACTIVE_PROJECT_FILE" 2>/dev/null || true
    fi

    #######################################
    # Logging Functions
    #######################################

    log() {
        local level="$1"
        shift
        local message="$*"
        local timestamp
        timestamp=$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')

        # Rotate log if too large
        if [ -f "$LOG_FILE" ] && [ $(${pkgs.coreutils}/bin/stat -c%s "$LOG_FILE") -gt "$MAX_LOG_SIZE" ]; then
            ${pkgs.coreutils}/bin/mv "$LOG_FILE" "''${LOG_FILE}.old"
        fi

        ${pkgs.coreutils}/bin/echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

        # Print to stderr if debug mode or error
        if [ "$DEBUG" = "1" ] || [ "$level" = "ERROR" ]; then
            ${pkgs.coreutils}/bin/echo "[$level] $message" >&2
        fi
    }

    log_info() {
        log "INFO" "$@"
    }

    log_warn() {
        log "WARN" "$@"
    }

    log_error() {
        log "ERROR" "$@"
    }

    log_debug() {
        if [ "$DEBUG" = "1" ]; then
            log "DEBUG" "$@"
        fi
    }

    #######################################
    # Error Handling Functions
    #######################################

    die() {
        local message="$1"
        local code="''${2:-1}"
        log_error "$message"
        ${pkgs.coreutils}/bin/echo -e "''${RED}Error: $message''${NC}" >&2
        exit "$code"
    }

    require_command() {
        local cmd="$1"
        if ! command -v "$cmd" &> /dev/null; then
            die "Required command '$cmd' not found. Please install it."
        fi
    }

    check_i3_running() {
        if ! ${pkgs.i3}/bin/i3-msg -t get_version &> /dev/null; then
            die "i3 window manager is not running or IPC socket is not accessible"
        fi
    }

    #######################################
    # i3 IPC Helper Functions
    #######################################

    i3_cmd() {
        local cmd="$*"
        log_debug "Executing i3 command: $cmd"

        local output
        if ! output=$(${pkgs.i3}/bin/i3-msg "$cmd" 2>&1); then
            log_error "i3 command failed: $cmd"
            log_error "Output: $output"
            return 1
        fi

        # Check if command reported success
        if ${pkgs.coreutils}/bin/echo "$output" | ${pkgs.jq}/bin/jq -e '.[] | select(.success == false)' &> /dev/null; then
            log_error "i3 command reported failure: $cmd"
            log_error "Output: $output"
            return 1
        fi

        ${pkgs.coreutils}/bin/echo "$output"
        return 0
    }

    i3_send_tick() {
        local payload="$1"
        log_debug "Sending tick event: $payload"
        ${pkgs.i3}/bin/i3-msg -t send_tick "$payload" &> /dev/null || log_warn "Failed to send tick event"
    }

    i3_get_windows_by_mark() {
        local mark="$1"
        ${pkgs.i3}/bin/i3-msg -t get_tree | ${pkgs.jq}/bin/jq -r ".. | select(.marks? | contains([\"$mark\"])) | .window" 2>/dev/null || true
    }

    i3_hide_windows_by_mark() {
        local mark="$1"
        log_debug "Hiding windows with mark: $mark"
        i3_cmd "[con_mark=\"$mark\"] move scratchpad" > /dev/null
    }

    i3_show_windows_by_mark() {
        local mark="$1"
        log_debug "Showing windows with mark: $mark"

        local windows
        windows=$(i3_get_windows_by_mark "$mark")

        if [ -z "$windows" ]; then
            log_debug "No windows found with mark: $mark"
            return 0
        fi

        while IFS= read -r window_id; do
            [ -z "$window_id" ] && continue
            i3_cmd "[id=$window_id] scratchpad show" > /dev/null
        done <<< "$windows"
    }

    #######################################
    # JSON Helper Functions
    #######################################

    validate_json() {
        local file="$1"

        if [ ! -f "$file" ]; then
            log_error "JSON file not found: $file"
            return 1
        fi

        if ! ${pkgs.jq}/bin/jq empty "$file" 2>/dev/null; then
            log_error "Invalid JSON in file: $file"
            return 1
        fi

        return 0
    }

    get_project_json() {
        local project_name="$1"
        local project_file="''${PROJECT_DIR}/''${project_name}.json"

        if ! validate_json "$project_file"; then
            return 1
        fi

        ${pkgs.coreutils}/bin/cat "$project_file"
    }

    get_active_project() {
        if [ ! -f "$ACTIVE_PROJECT_FILE" ]; then
            return 1
        fi

        local content
        content=$(${pkgs.coreutils}/bin/cat "$ACTIVE_PROJECT_FILE")

        if [ -z "$content" ]; then
            return 1
        fi

        # Try to parse as JSON (Feature 013: new format)
        if command -v ${pkgs.jq}/bin/jq >/dev/null 2>&1; then
            local project_name
            project_name=$(${pkgs.coreutils}/bin/echo "$content" | ${pkgs.jq}/bin/jq -r '.name // empty' 2>/dev/null)

            if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
                ${pkgs.coreutils}/bin/echo "$project_name"
                return 0
            fi
        fi

        # Fallback: treat as plain text (old format for backward compatibility)
        local project_name
        project_name=$(${pkgs.coreutils}/bin/echo "$content" | ${pkgs.coreutils}/bin/tr -d '[:space:]')

        if [ -z "$project_name" ]; then
            return 1
        fi

        ${pkgs.coreutils}/bin/echo "$project_name"
    }

    #######################################
    # Application Classification Functions
    #######################################

    is_app_scoped() {
        local wm_class="$1"

        if [ -f "$APP_CLASSES_FILE" ]; then
            local scoped
            scoped=$(${pkgs.jq}/bin/jq -r --arg class "$wm_class" \
                '.classes[] | select(.class == $class) | .scoped' \
                "$APP_CLASSES_FILE" 2>/dev/null)

            if [ -n "$scoped" ] && [ "$scoped" != "null" ]; then
                [ "$scoped" = "true" ] && return 0 || return 1
            fi
        fi

        # Default heuristics if not in config
        case "$wm_class" in
            *[Tt]erm*|*[Kk]onsole*|[Gg]hostty|[Aa]lacritty)
                return 0  # Terminals are scoped
                ;;
            [Cc]ode|*vim*|*emacs*|*[Ii]dea*)
                return 0  # Editors are scoped
                ;;
            *git*|lazygit|gitg)
                return 0  # Git tools are scoped
                ;;
            yazi|ranger|nnn)
                return 0  # File managers are scoped
                ;;
            *)
                return 1  # Default to global
                ;;
        esac
    }

    get_app_workspace() {
        local wm_class="$1"

        if [ -f "$APP_CLASSES_FILE" ]; then
            local workspace
            workspace=$(${pkgs.jq}/bin/jq -r --arg class "$wm_class" \
                '.classes[] | select(.class == $class) | .workspace // empty' \
                "$APP_CLASSES_FILE" 2>/dev/null)

            if [ -n "$workspace" ] && [ "$workspace" != "null" ]; then
                ${pkgs.coreutils}/bin/echo "$workspace"
                return 0
            fi
        fi

        return 1
    }

    #######################################
    # Window ID Retrieval Functions
    #######################################

    get_window_id_by_pid() {
        local pid="$1"
        local timeout="''${2:-2}"
        local start_time
        start_time=$(${pkgs.coreutils}/bin/date +%s)

        log_debug "Waiting for window from PID $pid (timeout: ''${timeout}s)"

        while true; do
            local window_id
            window_id=$(${pkgs.xdotool}/bin/xdotool search --pid "$pid" 2>/dev/null | ${pkgs.coreutils}/bin/head -1)

            if [ -n "$window_id" ]; then
                log_debug "Found window ID: $window_id"
                ${pkgs.coreutils}/bin/echo "$window_id"
                return 0
            fi

            local current_time
            current_time=$(${pkgs.coreutils}/bin/date +%s)
            if [ $((current_time - start_time)) -ge "$timeout" ]; then
                log_warn "Timeout waiting for window from PID $pid"
                return 1
            fi

            ${pkgs.coreutils}/bin/sleep 0.1
        done
    }

    mark_window_with_project() {
        local window_id="$1"
        local project_name="$2"
        local mark="project:''${project_name}"

        log_debug "Marking window $window_id with $mark"
        i3_cmd "[id=$window_id] mark --add \"$mark\"" > /dev/null
    }

    #######################################
    # Initialization
    #######################################

    ${pkgs.coreutils}/bin/mkdir -p "$PROJECT_DIR"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$LOG_FILE")"
    ${pkgs.coreutils}/bin/touch "$ACTIVE_PROJECT_FILE"

    require_command "${pkgs.jq}/bin/jq"
    require_command "${pkgs.i3}/bin/i3-msg"

    log_debug "Common library loaded successfully"
  '';

in
{
  options.programs.i3ProjectManager = {
    enable = mkEnableOption "i3 dynamic project workspace management";

    package = mkOption {
      type = types.package;
      default = pkgs.i3;
      description = "i3 package to use";
    };

    enableShellcheck = mkOption {
      type = types.bool;
      default = true;
      description = "Enable shellcheck validation for deployed scripts";
    };

    defaultAppClasses = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          scoped = mkOption {
            type = types.bool;
            description = "Whether this application is project-scoped";
          };
          workspace = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "Default workspace assignment";
          };
          description = mkOption {
            type = types.str;
            default = "";
            description = "Human-readable description";
          };
        };
      });
      default = {
        Code = {
          scoped = true;
          workspace = 2;
          description = "VS Code editor";
        };
        Ghostty = {
          scoped = true;
          workspace = 1;
          description = "Ghostty terminal";
        };
        lazygit = {
          scoped = true;
          workspace = 7;
          description = "Lazygit git UI";
        };
        yazi = {
          scoped = true;
          workspace = 5;
          description = "Yazi file manager";
        };
        Firefox = {
          scoped = false;
          description = "Firefox browser (global)";
        };
        "^FFPWA-.*" = {
          scoped = false;
          description = "Firefox PWAs (global)";
        };
      };
      description = ''
        Default application class classifications.
        User can override by editing ~/.config/i3/app-classes.json
      '';
    };
  };

  config = mkIf cfg.enable {
    # T004: Shellcheck validation assertion
    assertions = [
      {
        assertion = cfg.enableShellcheck -> (pkgs.shellcheck != null);
        message = "Shellcheck validation enabled but shellcheck package not available";
      }
    ];

    # Ensure required packages are available
    home.packages = with pkgs; [
      jq          # JSON parsing
      xdotool     # Window ID retrieval
      rofi        # Project switcher UI
    ] ++ (if cfg.enableShellcheck then [ shellcheck ] else []);

    # Create directory structure
    home.file.".config/i3/projects/.keep".text = "# Project JSON files directory";
    home.file.".config/i3/launchers/.keep".text = "# Application launcher scripts";
    home.file.".config/i3/scripts/.keep".text = "# Project management scripts";

    # NOTE: active-project file is NOT managed by home-manager because it needs to be writable
    # It will be created on first use by the project management scripts

    # Generate default app-classes.json
    home.file.".config/i3/app-classes.json".text = builtins.toJSON {
      version = "1.0";
      classes = mapAttrsToList (class: config: {
        inherit class;
        scoped = config.scoped;
        workspace = config.workspace;
        description = config.description;
      }) cfg.defaultAppClasses;
    };

    # T004 (continuation): Removed common.sh deployment - now inlined via commonFunctions let binding

    # T009: project-list.sh - List all available projects
    home.file.".config/i3/scripts/project-list.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # i3-project-list - List all available projects
        # Declaratively generated by home-manager

        set -euo pipefail

        ${commonFunctions}

        usage() {
            ${pkgs.coreutils}/bin/cat <<EOF
        Usage: i3-project-list [--format FORMAT]

        List all available i3 projects.

        Arguments:
            --format FORMAT    Output format: text (default) or json

        Examples:
            i3-project-list
            i3-project-list --format json
        EOF
        }

        main() {
            local format="text"

            if [ "$1" = "--format" ]; then
                format="$2"
            elif [ "$1" = "--help" ]; then
                usage
                exit 0
            fi

            local active_project
            active_project=$(get_active_project 2>/dev/null) || active_project=""

            local project_files=()
            local file
            while IFS= read -r -d '' file; do
                project_files=("''${project_files[@]}" "$file")
            done < <(${pkgs.findutils}/bin/find "$PROJECT_DIR" -maxdepth 1 -name "*.json" -print0 2>/dev/null | ${pkgs.coreutils}/bin/sort -z)

            if [ ''${#project_files[@]} -eq 0 ]; then
                if [ "$format" = "json" ]; then
                    ${pkgs.coreutils}/bin/echo '{"projects": []}'
                else
                    ${pkgs.coreutils}/bin/echo "No projects found in $PROJECT_DIR"
                fi
                exit 0
            fi

            if [ "$format" = "json" ]; then
                ${pkgs.coreutils}/bin/echo "{"
                ${pkgs.coreutils}/bin/echo '  "active": "'$active_project'",'
                ${pkgs.coreutils}/bin/echo '  "projects": ['

                local first=true
                for file in "''${project_files[@]}"; do
                    if [ "$first" = true ]; then
                        first=false
                    else
                        ${pkgs.coreutils}/bin/echo ","
                    fi

                    local proj_json
                    proj_json=$(${pkgs.coreutils}/bin/cat "$file")
                    local name
                    name=$(${pkgs.coreutils}/bin/echo "$proj_json" | ${pkgs.jq}/bin/jq -r '.project.name')

                    ${pkgs.coreutils}/bin/echo -n "    {"
                    ${pkgs.coreutils}/bin/echo -n '"name": "'$name'", '
                    ${pkgs.coreutils}/bin/echo -n '"active": '$([ "$name" = "$active_project" ] && ${pkgs.coreutils}/bin/echo "true" || ${pkgs.coreutils}/bin/echo "false")', '
                    ${pkgs.coreutils}/bin/echo -n '"file": "'$file'", '
                    ${pkgs.coreutils}/bin/echo -n '"data": '$proj_json
                    ${pkgs.coreutils}/bin/echo -n "    }"
                done

                ${pkgs.coreutils}/bin/echo ""
                ${pkgs.coreutils}/bin/echo "  ]"
                ${pkgs.coreutils}/bin/echo "}"
            else
                ${pkgs.coreutils}/bin/echo "Available projects:"
                ${pkgs.coreutils}/bin/echo ""

                for file in "''${project_files[@]}"; do
                    local name display_name icon dir
                    name=$(${pkgs.jq}/bin/jq -r '.project.name' "$file")
                    display_name=$(${pkgs.jq}/bin/jq -r '.project.displayName // .project.name' "$file")
                    icon=$(${pkgs.jq}/bin/jq -r '.project.icon // ""' "$file")
                    dir=$(${pkgs.jq}/bin/jq -r '.project.directory' "$file")

                    local active_marker=" "
                    if [ "$name" = "$active_project" ]; then
                        active_marker="*"
                    fi

                    ${pkgs.coreutils}/bin/printf " %s %s %s\n" "$active_marker" "$icon" "$display_name"
                    ${pkgs.coreutils}/bin/printf "    Name: %s\n" "$name"
                    ${pkgs.coreutils}/bin/printf "    Directory: %s\n" "$dir"
                    ${pkgs.coreutils}/bin/echo ""
                done

                if [ -n "$active_project" ]; then
                    ${pkgs.coreutils}/bin/echo "* = currently active project"
                fi
            fi
        }

        main "$@"
      '';
    };

    # T008: project-clear.sh - Clear active project
    home.file.".config/i3/scripts/project-clear.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # i3-project-clear - Clear active project (return to global mode)
        # Declaratively generated by home-manager

        set -euo pipefail

        ${commonFunctions}

        usage() {
            ${pkgs.coreutils}/bin/cat <<EOF
        Usage: i3-project-clear

        Clear the active project and return to global mode.

        In global mode:
          - All applications are visible
          - No project context is applied
          - Launching apps creates global (non-project-scoped) windows

        Examples:
            i3-project-clear
        EOF
        }

        main() {
            if [ "$1" = "--help" ]; then
                usage
                exit 0
            fi

            local old_project
            old_project=$(get_active_project 2>/dev/null) || old_project=""

            if [ -z "$old_project" ]; then
                ${pkgs.coreutils}/bin/echo "No active project to clear"
                exit 0
            fi

            log_info "Clearing active project: $old_project"

            ${pkgs.coreutils}/bin/echo "{}" > "$ACTIVE_PROJECT_FILE"

            ${pkgs.coreutils}/bin/echo -e "''${GREEN}✓''${NC} Cleared active project (was: $old_project)"
            ${pkgs.coreutils}/bin/echo "  Returned to global mode"

            log_info "Showing all project windows from scratchpad"

            # Get all project marks from i3 tree (Bug fix: removed quotes from -t get_tree)
            local all_marks
            all_marks=$(i3_cmd -t get_tree | ${pkgs.jq}/bin/jq -r '.. | select(.marks?) | .marks[] | select(startswith("project:"))' | ${pkgs.coreutils}/bin/sort -u)

            if [ -n "$all_marks" ]; then
                while IFS= read -r mark; do
                    if [ -n "$mark" ]; then
                        log_debug "Showing windows with mark: $mark"
                        i3_show_windows_by_mark "$mark" || log_debug "No windows to show for mark $mark"
                    fi
                done <<< "$all_marks"
            fi

            log_debug "Sending tick event: project:none"
            i3_send_tick "project:none"

            log_debug "Signaling i3blocks to update project indicator"
            ${pkgs.coreutils}/bin/sleep 0.1
            ${pkgs.procps}/bin/pkill -RTMIN+10 i3blocks 2>/dev/null || true
        }

        main "$@"
      '';
    };

    # T006: project-create.sh - Create new project configuration
    home.file.".config/i3/scripts/project-create.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # i3-project-create - Create new project configuration
        # Declaratively generated by home-manager

        set -euo pipefail

        ${commonFunctions}

        usage() {
            ${pkgs.coreutils}/bin/cat <<EOF
        Usage: i3-project-create --name NAME --dir DIRECTORY [OPTIONS]

        Create a new i3 project configuration.

        Required Arguments:
            --name NAME            Project identifier (alphanumeric, dash, underscore)
            --dir DIRECTORY        Project working directory (absolute path)

        Optional Arguments:
            --icon ICON            Icon for project display (emoji or nerd font)
            --display-name NAME    Human-readable project name (defaults to name)
            --help                 Show this help message

        Examples:
            i3-project-create --name nixos --dir /etc/nixos
            i3-project-create --name stacks --dir ~/code/stacks --icon "" --display-name "Stacks Project"

        Project files are created in: ~/.config/i3/projects/
        EOF
        }

        validate_project_name() {
            local name="$1"
            if [ -z "$name" ]; then
                die "Project name cannot be empty"
            fi
            if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                die "Project name must contain only alphanumeric characters, dash, or underscore: $name"
            fi
            return 0
        }

        validate_directory() {
            local dir="$1"
            if [ -z "$dir" ]; then
                die "Project directory cannot be empty"
            fi
            if [[ "$dir" != /* ]]; then
                die "Project directory must be an absolute path: $dir"
            fi
            if [ ! -d "$dir" ]; then
                log_warn "Directory does not exist: $dir"
                ${pkgs.coreutils}/bin/echo "Warning: Directory '$dir' does not exist" >&2
                ${pkgs.coreutils}/bin/echo "Project will be created anyway. Directory can be created later." >&2
            fi
            return 0
        }

        main() {
            local project_name=""
            local project_dir=""
            local project_icon=""
            local display_name=""

            while [[ $# -gt 0 ]]; do
                case $1 in
                    --name)
                        project_name="$2"
                        shift 2
                        ;;
                    --dir)
                        project_dir="$2"
                        shift 2
                        ;;
                    --icon)
                        project_icon="$2"
                        shift 2
                        ;;
                    --display-name)
                        display_name="$2"
                        shift 2
                        ;;
                    --help)
                        usage
                        exit 0
                        ;;
                    *)
                        ${pkgs.coreutils}/bin/echo "Error: Unknown option: $1" >&2
                        ${pkgs.coreutils}/bin/echo "Try 'i3-project-create --help' for more information." >&2
                        exit 1
                        ;;
                esac
            done

            if [ -z "$project_name" ]; then
                ${pkgs.coreutils}/bin/echo "Error: Missing required argument: --name" >&2
                usage
                exit 1
            fi

            if [ -z "$project_dir" ]; then
                ${pkgs.coreutils}/bin/echo "Error: Missing required argument: --dir" >&2
                usage
                exit 1
            fi

            validate_project_name "$project_name"
            validate_directory "$project_dir"

            if [ -z "$display_name" ]; then
                display_name="$project_name"
            fi

            local project_file="''${PROJECT_DIR}/''${project_name}.json"
            if [ -f "$project_file" ]; then
                die "Project '$project_name' already exists at: $project_file"
            fi

            log_info "Creating project: $project_name"

            local temp_file="''${project_file}.tmp"
            ${pkgs.coreutils}/bin/cat > "$temp_file" <<EOF
        {
          "version": "1.0",
          "project": {
            "name": "$project_name",
            "displayName": "$display_name",
            "icon": "$project_icon",
            "directory": "$project_dir"
          },
          "workspaces": {},
          "workspaceOutputs": {},
          "appClasses": []
        }
        EOF

            if ! validate_json "$temp_file"; then
                ${pkgs.coreutils}/bin/rm -f "$temp_file"
                die "Failed to generate valid JSON for project"
            fi

            ${pkgs.coreutils}/bin/mv "$temp_file" "$project_file"

            log_info "Project created successfully: $project_file"
            ${pkgs.coreutils}/bin/echo -e "''${GREEN}✓''${NC} Created project '$project_name' at ''${BLUE}$project_file''${NC}"

            ${pkgs.coreutils}/bin/cat <<EOF

        Next steps:
          1. Switch to project:     i3-project-switch $project_name
          2. Edit configuration:    i3-project-edit $project_name
          3. Validate configuration: i3-project-validate $project_name

        To add workspace layouts and launch commands, edit the JSON file.
        See ~/.config/i3/projects/README.md for examples.
        EOF
        }

        main "$@"
      '';
    };

    # T011: project-delete.sh - Delete project configuration
    home.file.".config/i3/scripts/project-delete.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # i3-project-delete - Delete project configuration
        # Declaratively generated by home-manager

        set -euo pipefail

        ${commonFunctions}

        usage() {
            ${pkgs.coreutils}/bin/cat <<EOF
        Usage: i3-project-delete PROJECT_NAME [--force]

        Delete an i3 project configuration file.

        Arguments:
            PROJECT_NAME    Name of the project to delete
            --force         Skip confirmation prompt

        Examples:
            i3-project-delete test-project
            i3-project-delete old-project --force
        EOF
        }

        main() {
            local project_name="$1"
            local force=false

            if [ "$2" = "--force" ]; then
                force=true
            fi

            if [ -z "$project_name" ] || [ "$project_name" = "--help" ]; then
                usage
                exit $([ "$project_name" = "--help" ] && ${pkgs.coreutils}/bin/echo 0 || ${pkgs.coreutils}/bin/echo 1)
            fi

            local project_file="''${PROJECT_DIR}/''${project_name}.json"

            if [ ! -f "$project_file" ]; then
                die "Project '$project_name' does not exist"
            fi

            local active_project
            if active_project=$(get_active_project 2>/dev/null); then
                if [ "$active_project" = "$project_name" ]; then
                    log_warn "Clearing active project before deletion"
                    ${pkgs.coreutils}/bin/echo "Project '$project_name' is currently active. Clearing..." >&2
                    ${pkgs.coreutils}/bin/echo "" > "$ACTIVE_PROJECT_FILE"
                fi
            fi

            if [ "$force" != true ]; then
                ${pkgs.coreutils}/bin/echo "Are you sure you want to delete project '$project_name'? (y/N) " >&2
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    ${pkgs.coreutils}/bin/echo "Deletion cancelled." >&2
                    exit 0
                fi
            fi

            ${pkgs.coreutils}/bin/rm "$project_file"
            log_info "Deleted project: $project_name"
            ${pkgs.coreutils}/bin/echo -e "''${GREEN}✓''${NC} Deleted project '$project_name'"
        }

        main "$@"
      '';
    };

    # T010: project-current.sh - Display currently active project
    home.file.".config/i3/scripts/project-current.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # i3-project-current - Display currently active project
        # Declaratively generated by home-manager

        set -euo pipefail

        # Source common functions
        ${commonFunctions}

        usage() {
            ${pkgs.coreutils}/bin/cat <<EOF
        Usage: i3-project-current [--format FORMAT]

        Display the currently active project.

        Arguments:
            --format FORMAT    Output format: text (default) or json

        Examples:
            i3-project-current
            i3-project-current --format json
        EOF
        }

        main() {
            local format="text"

            if [ "$1" = "--format" ]; then
                format="$2"
            elif [ "$1" = "--help" ]; then
                usage
                exit 0
            fi

            # Get active project
            local project_name
            project_name=$(get_active_project 2>/dev/null) || project_name=""

            if [ -z "$project_name" ]; then
                if [ "$format" = "json" ]; then
                    ${pkgs.coreutils}/bin/echo '{"active": false, "name": null}'
                else
                    ${pkgs.coreutils}/bin/echo "No active project (global mode)"
                fi
                exit 0
            fi

            # Get project details
            local project_file="''${PROJECT_DIR}/''${project_name}.json"
            if [ ! -f "$project_file" ]; then
                log_error "Active project file not found: $project_name"
                if [ "$format" = "json" ]; then
                    ${pkgs.coreutils}/bin/echo '{"active": false, "name": null, "error": "project file not found"}'
                else
                    ${pkgs.coreutils}/bin/echo "Error: Active project '$project_name' configuration not found"
                fi
                exit 1
            fi

            local project_json
            project_json=$(${pkgs.coreutils}/bin/cat "$project_file")

            if [ "$format" = "json" ]; then
                # JSON output
                ${pkgs.coreutils}/bin/echo "$project_json" | ${pkgs.jq}/bin/jq -c '{
                    active: true,
                    name: .project.name,
                    displayName: .project.displayName,
                    icon: .project.icon,
                    directory: .project.directory
                }'
            else
                # Text output
                local display_name icon dir
                display_name=$(${pkgs.coreutils}/bin/echo "$project_json" | ${pkgs.jq}/bin/jq -r '.project.displayName // .project.name')
                icon=$(${pkgs.coreutils}/bin/echo "$project_json" | ${pkgs.jq}/bin/jq -r '.project.icon // ""')
                dir=$(${pkgs.coreutils}/bin/echo "$project_json" | ${pkgs.jq}/bin/jq -r '.project.directory')

                ${pkgs.coreutils}/bin/echo "Active project: $icon $display_name"
                ${pkgs.coreutils}/bin/echo "  Name: $project_name"
                ${pkgs.coreutils}/bin/echo "  Directory: $dir"
            fi
        }

        main "$@"
      '';
    };

    # T017-T018: Deploy Phase 4 (US4) project management scripts
    home.file.".config/i3/scripts/project-validate.sh" = {
      executable = true;
      source = ./scripts/project-validate.sh;
    };

    home.file.".config/i3/scripts/project-edit.sh" = {
      executable = true;
      source = ./scripts/project-edit.sh;
    };

    # T007: project-switch.sh - Switch to a different project (COMPLEX)
    home.file.".config/i3/scripts/project-switch.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # i3-project-switch - Switch to a different project
        # Declaratively generated by home-manager

        set -euo pipefail

        ${commonFunctions}

        usage() {
            ${pkgs.coreutils}/bin/cat <<EOF
        Usage: i3-project-switch PROJECT_NAME

        Switch to an i3 project context.

        Arguments:
            PROJECT_NAME    Name of the project to activate

        Examples:
            i3-project-switch nixos
            i3-project-switch stacks

        This will:
          1. Load project configuration
          2. Apply workspace layouts (i3 append_layout)
          3. Execute launch commands
          4. Apply workspace output assignments (multi-monitor)
          5. Update active project state
          6. Hide old project windows / show new project windows
          7. Send i3 tick event for UI updates

        To see available projects: i3-project-list
        EOF
        }

        main() {
            local project_name="$1"

            if [ -z "$project_name" ] || [ "$project_name" = "--help" ]; then
                usage
                exit $([ "$project_name" = "--help" ] && ${pkgs.coreutils}/bin/echo 0 || ${pkgs.coreutils}/bin/echo 1)
            fi

            check_i3_running

            local project_file="''${PROJECT_DIR}/''${project_name}.json"
            if [ ! -f "$project_file" ]; then
                die "Project '$project_name' does not exist"
            fi

            if ! validate_json "$project_file"; then
                die "Project configuration is invalid JSON"
            fi

            local project_json
            project_json=$(${pkgs.coreutils}/bin/cat "$project_file")

            local display_name dir icon
            display_name=$(${pkgs.coreutils}/bin/echo "$project_json" | ${pkgs.jq}/bin/jq -r '.project.displayName // .project.name')
            dir=$(${pkgs.coreutils}/bin/echo "$project_json" | ${pkgs.jq}/bin/jq -r '.project.directory')
            icon=$(${pkgs.coreutils}/bin/echo "$project_json" | ${pkgs.jq}/bin/jq -r '.project.icon // ""')

            log_info "Switching to project: $project_name"

            local old_project
            old_project=$(get_active_project 2>/dev/null) || old_project=""

            # T036: Atomic write using temp file + rename pattern
            local temp_file
            temp_file=$(${pkgs.coreutils}/bin/mktemp "''${ACTIVE_PROJECT_FILE}.XXXXXX")
            ${pkgs.coreutils}/bin/cat > "$temp_file" <<EOF
        {
          "name": "$project_name",
          "display_name": "$display_name",
          "icon": "$icon"
        }
        EOF
            ${pkgs.coreutils}/bin/mv "$temp_file" "$ACTIVE_PROJECT_FILE"

            log_info "Active project set to: $project_name"
            ${pkgs.coreutils}/bin/echo -e "''${GREEN}✓''${NC} Switched to project: $icon $display_name"

            if [ -d "$dir" ]; then
                ${pkgs.coreutils}/bin/echo "  Project directory: $dir"
            else
                ${pkgs.coreutils}/bin/echo -e "''${YELLOW}⚠''${NC}  Warning: Project directory does not exist: $dir"
            fi

            local workspace_outputs
            workspace_outputs=$(${pkgs.coreutils}/bin/echo "$project_json" | ${pkgs.jq}/bin/jq -r '.workspaceOutputs // empty')

            if [ -n "$workspace_outputs" ]; then
                log_info "Applying workspace output assignments..."
                local ws_nums
                ws_nums=$(${pkgs.coreutils}/bin/echo "$workspace_outputs" | ${pkgs.jq}/bin/jq -r 'keys[]' 2>/dev/null)

                while IFS= read -r ws_num; do
                    if [ -n "$ws_num" ]; then
                        local output
                        output=$(${pkgs.coreutils}/bin/echo "$workspace_outputs" | ${pkgs.jq}/bin/jq -r ".[\"$ws_num\"]")

                        if [ -n "$output" ] && [ "$output" != "null" ]; then
                            log_debug "Assigning workspace $ws_num to output $output"
                            i3_cmd "workspace $ws_num output $output" || log_warn "Failed to assign workspace $ws_num to output $output"
                        fi
                    fi
                done <<< "$ws_nums"
            fi

            local workspaces
            workspaces=$(${pkgs.coreutils}/bin/echo "$project_json" | ${pkgs.jq}/bin/jq -r '.workspaces // empty')

            if [ -n "$workspaces" ]; then
                log_info "Applying workspace layouts..."
                local ws_nums
                ws_nums=$(${pkgs.coreutils}/bin/echo "$workspaces" | ${pkgs.jq}/bin/jq -r 'keys[]' 2>/dev/null)

                while IFS= read -r ws_num; do
                    if [ -n "$ws_num" ]; then
                        local ws_data
                        ws_data=$(${pkgs.coreutils}/bin/echo "$workspaces" | ${pkgs.jq}/bin/jq -r ".[\"$ws_num\"]")

                        local layout
                        layout=$(${pkgs.coreutils}/bin/echo "$ws_data" | ${pkgs.jq}/bin/jq -r '.layout // empty')

                        if [ -n "$layout" ]; then
                            log_debug "Applying layout to workspace $ws_num"

                            local layout_file
                            layout_file=$(${pkgs.coreutils}/bin/mktemp)
                            ${pkgs.coreutils}/bin/echo "$layout" > "$layout_file"

                            i3_cmd "workspace $ws_num" || log_warn "Failed to switch to workspace $ws_num"
                            i3_cmd "append_layout $layout_file" || log_warn "Failed to apply layout to workspace $ws_num"

                            ${pkgs.coreutils}/bin/rm -f "$layout_file"
                        fi
                    fi
                done <<< "$ws_nums"
            fi

            if [ -n "$workspaces" ]; then
                log_info "Executing launch commands..."
                local ws_nums
                ws_nums=$(${pkgs.coreutils}/bin/echo "$workspaces" | ${pkgs.jq}/bin/jq -r 'keys[]' 2>/dev/null)

                while IFS= read -r ws_num; do
                    if [ -n "$ws_num" ]; then
                        local ws_data
                        ws_data=$(${pkgs.coreutils}/bin/echo "$workspaces" | ${pkgs.jq}/bin/jq -r ".[\"$ws_num\"]")

                        local launch_cmds
                        launch_cmds=$(${pkgs.coreutils}/bin/echo "$ws_data" | ${pkgs.jq}/bin/jq -r '.launchCommands // empty')

                        if [ -n "$launch_cmds" ]; then
                            local cmd_count
                            cmd_count=$(${pkgs.coreutils}/bin/echo "$launch_cmds" | ${pkgs.jq}/bin/jq 'length')

                            log_debug "Executing $cmd_count launch command(s) for workspace $ws_num"

                            local idx=0
                            while [ $idx -lt "$cmd_count" ]; do
                                local cmd
                                cmd=$(${pkgs.coreutils}/bin/echo "$launch_cmds" | ${pkgs.jq}/bin/jq -r ".[$idx]")

                                if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
                                    log_debug "Launching: $cmd"
                                    (cd "$dir" && eval "$cmd" &) || log_warn "Failed to execute: $cmd"
                                    ${pkgs.coreutils}/bin/sleep 0.5
                                fi

                                ((idx++))
                            done
                        fi
                    fi
                done <<< "$ws_nums"
            fi

            if [ -n "$old_project" ] && [ "$old_project" != "$project_name" ]; then
                log_info "Switching from project: $old_project → $project_name"

                local old_mark="project:''${old_project}"
                log_debug "Moving windows with mark '$old_mark' to scratchpad"
                i3_hide_windows_by_mark "$old_mark" || log_warn "Failed to hide windows for old project"
            fi

            local new_mark="project:''${project_name}"
            log_debug "Showing windows with mark '$new_mark' from scratchpad"
            i3_show_windows_by_mark "$new_mark" || log_debug "No windows to show for project (or failed to show)"

            log_debug "Sending tick event: project:$project_name"
            i3_send_tick "project:$project_name"

            log_debug "Signaling i3blocks to update project indicator"
            ${pkgs.coreutils}/bin/sleep 0.1
            ${pkgs.procps}/bin/pkill -RTMIN+10 i3blocks 2>/dev/null || true
        }

        main "$@"
      '';
    };

    # T024-T028: Deploy Phase 5 (US2) window management and launcher scripts
    home.file.".config/i3/scripts/project-mark-window.sh" = {
      executable = true;
      source = ./scripts/project-mark-window.sh;
    };

    # T012: launch-code.sh - Launch VS Code in project context
    home.file.".config/i3/scripts/launch-code.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # launch-code - Launch VS Code in project context with automatic marking
        # Declaratively generated by home-manager

        set -euo pipefail

        ${commonFunctions}

        main() {
            local project_name
            project_name=$(get_active_project 2>/dev/null) || project_name=""

            local target_dir="$1"

            if [ -n "$project_name" ]; then
                if [ -z "$target_dir" ]; then
                    local project_file="''${PROJECT_DIR}/''${project_name}.json"
                    if [ -f "$project_file" ]; then
                        target_dir=$(${pkgs.jq}/bin/jq -r '.project.directory' "$project_file")
                        log_info "Launching Code in project directory: $target_dir"
                    fi
                fi
            fi

            if [ -n "$target_dir" ]; then
                log_debug "Executing: code \"$target_dir\""
                ${pkgs.vscode}/bin/code "$target_dir" &
                local code_pid=$!
            else
                log_debug "Executing: code"
                ${pkgs.vscode}/bin/code &
                local code_pid=$!
            fi

            if [ -n "$project_name" ]; then
                if is_app_scoped "Code"; then
                    log_info "Code is project-scoped, will mark window with project:$project_name"

                    local window_id
                    window_id=$(get_window_id_by_pid "$code_pid" 10)

                    if [ -n "$window_id" ]; then
                        mark_window_with_project "$window_id" "$project_name"
                        ${pkgs.coreutils}/bin/echo -e "''${GREEN}✓''${NC} Launched Code for project: $project_name (window $window_id)"
                    else
                        log_warn "Could not find window for Code process $code_pid"
                        ${pkgs.coreutils}/bin/echo -e "''${YELLOW}⚠''${NC} Launched Code but could not mark window"
                    fi
                else
                    log_debug "Code is global - not marking window"
                fi
            fi
        }

        main "$@"
      '';
    };

    # T013: launch-ghostty.sh - Launch Ghostty terminal in project context
    home.file.".config/i3/scripts/launch-ghostty.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # launch-ghostty - Launch Ghostty terminal in project context with automatic marking
        # Declaratively generated by home-manager

        set -euo pipefail

        ${commonFunctions}

        main() {
            local project_name
            project_name=$(get_active_project 2>/dev/null) || project_name=""

            local target_dir=""
            local session_name=""

            if [ -n "$project_name" ]; then
                local project_file="''${PROJECT_DIR}/''${project_name}.json"
                if [ -f "$project_file" ]; then
                    target_dir=$(${pkgs.jq}/bin/jq -r '.project.directory' "$project_file")
                    session_name="$project_name"
                    log_info "Launching Ghostty in project directory: $target_dir (session: $session_name)"
                fi
            fi

            local ghostty_pid

            if [ -n "$session_name" ] && command -v sesh >/dev/null 2>&1; then
                log_debug "Executing: ghostty -e sesh connect \"$session_name\""
                ghostty -e sesh connect "$session_name" &
                ghostty_pid=$!
            elif [ -n "$target_dir" ]; then
                log_debug "Executing: ghostty --working-directory=\"$target_dir\""
                ghostty --working-directory="$target_dir" &
                ghostty_pid=$!
            else
                log_debug "Executing: ghostty"
                ghostty &
                ghostty_pid=$!
            fi

            if [ -n "$project_name" ]; then
                if is_app_scoped "Ghostty" || is_app_scoped "com.mitchellh.ghostty"; then
                    log_info "Ghostty is project-scoped, will mark window with project:$project_name"

                    local window_id
                    window_id=$(get_window_id_by_pid "$ghostty_pid" 10)

                    if [ -n "$window_id" ]; then
                        mark_window_with_project "$window_id" "$project_name"
                        ${pkgs.coreutils}/bin/echo -e "''${GREEN}✓''${NC} Launched Ghostty for project: $project_name (window $window_id)"
                    else
                        log_warn "Could not find window for Ghostty process $ghostty_pid"
                        ${pkgs.coreutils}/bin/echo -e "''${YELLOW}⚠''${NC} Launched Ghostty but could not mark window"
                    fi
                else
                    log_debug "Ghostty is global - not marking window"
                fi
            fi
        }

        main "$@"
      '';
    };

    # T014: launch-lazygit.sh - Launch lazygit in project context
    home.file.".config/i3/scripts/launch-lazygit.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # launch-lazygit - Launch lazygit in project context with automatic marking
        # Declaratively generated by home-manager

        set -euo pipefail

        ${commonFunctions}

        main() {
            local project_name
            project_name=$(get_active_project 2>/dev/null) || project_name=""

            local target_dir="$1"

            if [ -n "$project_name" ]; then
                if [ -z "$target_dir" ]; then
                    local project_file="''${PROJECT_DIR}/''${project_name}.json"
                    if [ -f "$project_file" ]; then
                        target_dir=$(${pkgs.jq}/bin/jq -r '.project.directory' "$project_file")
                        log_info "Launching lazygit in project directory: $target_dir"
                    fi
                fi
            fi

            local ghostty_pid

            if [ -n "$target_dir" ]; then
                log_debug "Executing: ghostty -e lazygit --work-tree=\"$target_dir\" --git-dir=\"$target_dir/.git\""
                (cd "$target_dir" && ghostty -e lazygit) &
                ghostty_pid=$!
            else
                log_debug "Executing: ghostty -e lazygit"
                ghostty -e lazygit &
                ghostty_pid=$!
            fi

            if [ -n "$project_name" ]; then
                if is_app_scoped "lazygit"; then
                    log_info "lazygit is project-scoped, will mark window with project:$project_name"

                    local window_id
                    window_id=$(get_window_id_by_pid "$ghostty_pid" 10)

                    if [ -n "$window_id" ]; then
                        mark_window_with_project "$window_id" "$project_name"
                        ${pkgs.coreutils}/bin/echo -e "''${GREEN}✓''${NC} Launched lazygit for project: $project_name (window $window_id)"
                    else
                        log_warn "Could not find window for lazygit process $ghostty_pid"
                        ${pkgs.coreutils}/bin/echo -e "''${YELLOW}⚠''${NC} Launched lazygit but could not mark window"
                    fi
                else
                    log_debug "lazygit is global - not marking window"
                fi
            fi
        }

        main "$@"
      '';
    };

    # T015: launch-yazi.sh - Launch yazi file manager in project context
    home.file.".config/i3/scripts/launch-yazi.sh" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        # launch-yazi - Launch yazi file manager in project context with automatic marking
        # Declaratively generated by home-manager

        set -euo pipefail

        ${commonFunctions}

        main() {
            local project_name
            project_name=$(get_active_project 2>/dev/null) || project_name=""

            local target_dir="$1"

            if [ -n "$project_name" ]; then
                if [ -z "$target_dir" ]; then
                    local project_file="''${PROJECT_DIR}/''${project_name}.json"
                    if [ -f "$project_file" ]; then
                        target_dir=$(${pkgs.jq}/bin/jq -r '.project.directory' "$project_file")
                        log_info "Launching yazi in project directory: $target_dir"
                    fi
                fi
            fi

            local ghostty_pid

            if [ -n "$target_dir" ]; then
                log_debug "Executing: ghostty -e yazi \"$target_dir\""
                ghostty -e yazi "$target_dir" &
                ghostty_pid=$!
            else
                log_debug "Executing: ghostty -e yazi"
                ghostty -e yazi &
                ghostty_pid=$!
            fi

            if [ -n "$project_name" ]; then
                if is_app_scoped "yazi"; then
                    log_info "yazi is project-scoped, will mark window with project:$project_name"

                    local window_id
                    window_id=$(get_window_id_by_pid "$ghostty_pid" 10)

                    if [ -n "$window_id" ]; then
                        mark_window_with_project "$window_id" "$project_name"
                        ${pkgs.coreutils}/bin/echo -e "''${GREEN}✓''${NC} Launched yazi for project: $project_name (window $window_id)"
                    else
                        log_warn "Could not find window for yazi process $ghostty_pid"
                        ${pkgs.coreutils}/bin/echo -e "''${YELLOW}⚠''${NC} Launched yazi but could not mark window"
                    fi
                else
                    log_debug "yazi is global - not marking window"
                fi
            fi
        }

        main "$@"
      '';
    };

    # T022: Removed polybar integration script deployment (migrated to i3blocks)

    # T041: Deploy Phase 7 (US5) workspace output reassignment script
    home.file.".config/i3/scripts/reassign-workspaces.sh" = {
      executable = true;
      source = ./scripts/reassign-workspaces.sh;
    };

    # T048: Deploy Phase 9 rofi project switcher
    home.file.".config/i3/scripts/rofi-project-switcher.sh" = {
      executable = true;
      source = ./scripts/rofi-project-switcher.sh;
    };

    # T015: Create command-line symlinks in ~/.local/bin/
    home.file.".local/bin/i3-project-create".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-create.sh";
    home.file.".local/bin/i3-project-delete".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-delete.sh";
    home.file.".local/bin/i3-project-list".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-list.sh";
    home.file.".local/bin/i3-project-switch".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-switch.sh";
    home.file.".local/bin/i3-project-clear".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-clear.sh";
    home.file.".local/bin/i3-project-current".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-current.sh";

    # T022: Create symlinks for Phase 4 commands
    home.file.".local/bin/i3-project-validate".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-validate.sh";
    home.file.".local/bin/i3-project-edit".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-edit.sh";

    # T033: Create symlink for Phase 5 window marking
    home.file.".local/bin/i3-project-mark-window".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/i3/scripts/project-mark-window.sh";
  };
}
