{ config, pkgs, lib, ... }:

let
  # Helper script to query window PIDs and environment variables
  windowEnv = pkgs.writeShellScriptBin "window-env" ''
    #!/usr/bin/env bash
    # window-env: Query window PIDs and environment variables
    #
    # Usage:
    #   window-env [OPTIONS] <pattern-or-pid>
    #
    # Options:
    #   --pid              Show only PID(s)
    #   --filter PATTERN   Filter environment variables by pattern (e.g., I3PM_)
    #   --json             Output raw JSON data
    #   --all              Show all matching windows (default: first match)
    #   --help             Show this help message

    set -euo pipefail

    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    DIM='\033[2m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color

    # Default options
    SHOW_PID_ONLY=false
    ENV_FILTER=""
    OUTPUT_JSON=false
    SHOW_ALL=false
    WINDOW_PATTERN=""
    SEARCH_BY_PID=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --pid)
                SHOW_PID_ONLY=true
                shift
                ;;
            --filter)
                ENV_FILTER="$2"
                shift 2
                ;;
            --json)
                OUTPUT_JSON=true
                shift
                ;;
            --all)
                SHOW_ALL=true
                shift
                ;;
            --help|-h)
                cat << EOF
    window-env: Query window PIDs and environment variables

    Usage:
      window-env [OPTIONS] <pattern-or-pid>

    Options:
      --pid              Show only PID(s)
      --filter PATTERN   Filter environment variables by pattern (e.g., I3PM_)
      --json             Output raw JSON data
      --all              Show all matching windows (default: first match)
      --help             Show this help message

    Search Modes:
      - By PID:    Provide numeric PID (e.g., 4099278)
      - By Class:  Provide window class pattern (e.g., Code, FFPWA)
      - By Title:  Provide window title pattern (e.g., YouTube, Claude)

    Examples:
      window-env 4099278                    # Query by PID
      window-env YouTube                    # Query by title (fuzzy match)
      window-env --pid YouTube              # Show just the PID for YouTube
      window-env --filter I3PM_ Claude      # Show only I3PM_* variables for Claude
      window-env --all Code                 # Show env vars for all VS Code windows
      window-env FFPWA-01K666               # Query by class (partial ULID)

    Notes:
      - Pattern matching is case-insensitive and fuzzy (matches class or title)
      - If numeric pattern provided, searches by PID first
      - If multiple windows match, only the first is shown unless --all is used
      - PID must be valid (process still running) to read environment variables
    EOF
                exit 0
                ;;
            -*)
                echo -e "''${RED}Error: Unknown option: $1''${NC}" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
            *)
                WINDOW_PATTERN="$1"
                shift
                ;;
        esac
    done

    # Validate arguments
    if [[ -z "$WINDOW_PATTERN" ]]; then
        echo -e "''${RED}Error: Pattern or PID required''${NC}" >&2
        echo "Usage: window-env [OPTIONS] <pattern-or-pid>" >&2
        echo "Use --help for more information" >&2
        exit 1
    fi

    # Detect if pattern is a numeric PID
    if [[ "$WINDOW_PATTERN" =~ ^[0-9]+$ ]]; then
        SEARCH_BY_PID=true
    fi

    # Check if jq is available
    if ! command -v ${pkgs.jq}/bin/jq &> /dev/null; then
        echo -e "''${RED}Error: jq command not found''${NC}" >&2
        echo "jq is required for parsing window data" >&2
        exit 1
    fi

    # Query windows from i3pm
    WINDOWS_JSON=$(i3pm windows --json 2>/dev/null) || {
        echo -e "''${RED}Error: Failed to query window state from i3pm''${NC}" >&2
        echo "Is the i3pm daemon running? Check with: systemctl --user status i3-project-event-listener" >&2
        exit 1
    }

    # Find matching windows (case-insensitive, by PID or class/title)
    if [[ "$SEARCH_BY_PID" == "true" ]]; then
        # Search by numeric PID
        MATCHING_WINDOWS=$(echo "$WINDOWS_JSON" | ${pkgs.jq}/bin/jq -r --argjson pid "$WINDOW_PATTERN" '
            [
                .[].workspaces[].windows[] |
                select(.pid == $pid)
            ]
        ')
    else
        # Search by class or title (fuzzy, case-insensitive)
        MATCHING_WINDOWS=$(echo "$WINDOWS_JSON" | ${pkgs.jq}/bin/jq -r --arg pattern "$WINDOW_PATTERN" '
            [
                .[].workspaces[].windows[] |
                select(
                    (.class | ascii_downcase | contains($pattern | ascii_downcase)) or
                    (.title | ascii_downcase | contains($pattern | ascii_downcase))
                )
            ]
        ')
    fi

    # Check if any windows matched
    WINDOW_COUNT=$(echo "$MATCHING_WINDOWS" | ${pkgs.jq}/bin/jq 'length')

    if [[ "$WINDOW_COUNT" -eq 0 ]]; then
        if [[ "$SEARCH_BY_PID" == "true" ]]; then
            echo -e "''${YELLOW}No window found with PID: ''${BOLD}$WINDOW_PATTERN''${NC}" >&2
        else
            echo -e "''${YELLOW}No windows found matching pattern: ''${BOLD}$WINDOW_PATTERN''${NC}" >&2
        fi
        echo "" >&2
        echo -e "''${DIM}Available windows:''${NC}" >&2
        echo "$WINDOWS_JSON" | ${pkgs.jq}/bin/jq -r '.[].workspaces[].windows[] | "  PID: \(.pid | tostring | if length < 7 then . + (" " * (7 - length)) else . end)  Class: \(.class)  Title: \(.title)"' | head -10 >&2
        exit 1
    fi

    # Handle JSON output
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "$MATCHING_WINDOWS"
        exit 0
    fi

    # Handle PID-only output
    if [[ "$SHOW_PID_ONLY" == "true" ]]; then
        if [[ "$SHOW_ALL" == "true" ]]; then
            echo "$MATCHING_WINDOWS" | ${pkgs.jq}/bin/jq -r '.[].pid // "N/A"'
        else
            echo "$MATCHING_WINDOWS" | ${pkgs.jq}/bin/jq -r '.[0].pid // "N/A"'
        fi
        exit 0
    fi

    # Show environment variables for matching windows
    show_window_env() {
        local window_json="$1"
        local window_id=$(echo "$window_json" | ${pkgs.jq}/bin/jq -r '.id')
        local window_class=$(echo "$window_json" | ${pkgs.jq}/bin/jq -r '.class')
        local window_title=$(echo "$window_json" | ${pkgs.jq}/bin/jq -r '.title')
        local window_pid=$(echo "$window_json" | ${pkgs.jq}/bin/jq -r '.pid // "N/A"')
        local workspace=$(echo "$window_json" | ${pkgs.jq}/bin/jq -r '.workspace')
        local project=$(echo "$window_json" | ${pkgs.jq}/bin/jq -r '.project // "N/A"')

        # Truncate long titles
        if [[ ''${#window_title} -gt 60 ]]; then
            window_title="''${window_title:0:57}..."
        fi

        # Print window header
        echo -e "''${BOLD}''${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"
        echo -e "''${BOLD}''${GREEN}Window:''${NC} $window_class''${DIM} - $window_title''${NC}"
        echo -e "''${BOLD}''${BLUE}ID:''${NC} $window_id  ''${BOLD}''${BLUE}PID:''${NC} $window_pid  ''${BOLD}''${BLUE}Workspace:''${NC} $workspace  ''${BOLD}''${BLUE}Project:''${NC} $project"
        echo -e "''${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"
        echo ""

        # Check if PID is valid
        if [[ "$window_pid" == "N/A" ]] || [[ ! "$window_pid" =~ ^[0-9]+$ ]]; then
            echo -e "''${YELLOW}⚠ PID not available for this window''${NC}"
            return
        fi

        # Check if process exists
        if [[ ! -d "/proc/$window_pid" ]]; then
            echo -e "''${YELLOW}⚠ Process $window_pid no longer exists''${NC}"
            return
        fi

        # Read environment variables
        if [[ ! -r "/proc/$window_pid/environ" ]]; then
            echo -e "''${RED}✗ Cannot read environment variables (permission denied)''${NC}"
            echo -e "''${DIM}Try running with sudo if you need to inspect other users' processes''${NC}"
            return
        fi

        # Get environment variables
        local env_vars
        if [[ -n "$ENV_FILTER" ]]; then
            env_vars=$(cat "/proc/$window_pid/environ" 2>/dev/null | tr '\0' '\n' | ${pkgs.gnugrep}/bin/grep "$ENV_FILTER" || true)
            if [[ -z "$env_vars" ]]; then
                echo -e "''${YELLOW}No environment variables matching '$ENV_FILTER' found''${NC}"
                return
            fi
            echo -e "''${BOLD}Environment variables (filtered by '$ENV_FILTER'):''${NC}"
        else
            env_vars=$(cat "/proc/$window_pid/environ" 2>/dev/null | tr '\0' '\n')
            local env_count=$(echo "$env_vars" | wc -l)
            echo -e "''${BOLD}Environment variables (''${env_count} total):''${NC}"
        fi

        echo ""

        # Format and colorize output
        echo "$env_vars" | while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                continue
            fi

            # Split on first = sign
            local var_name="''${line%%=*}"
            local var_value="''${line#*=}"

            # Color I3PM_ variables specially
            if [[ "$var_name" == I3PM_* ]]; then
                echo -e "  ''${BOLD}''${GREEN}''${var_name}''${NC}=''${CYAN}''${var_value}''${NC}"
            else
                echo -e "  ''${DIM}''${var_name}''${NC}=''${var_value}"
            fi
        done

        echo ""
    }

    # Show environment for matching windows
    if [[ "$SHOW_ALL" == "true" ]]; then
        # Show all matching windows
        for i in $(seq 0 $((WINDOW_COUNT - 1))); do
            window_json=$(echo "$MATCHING_WINDOWS" | ${pkgs.jq}/bin/jq ".[$i]")
            show_window_env "$window_json"

            # Add separator between windows (except for last one)
            if [[ $i -lt $((WINDOW_COUNT - 1)) ]]; then
                echo ""
            fi
        done
    else
        # Show only first match
        window_json=$(echo "$MATCHING_WINDOWS" | ${pkgs.jq}/bin/jq '.[0]')

        # Warn if multiple windows matched
        if [[ "$WINDOW_COUNT" -gt 1 ]]; then
            echo -e "''${YELLOW}⚠ Found $WINDOW_COUNT matching windows, showing first match''${NC}" >&2
            echo -e "''${DIM}Use --all to see all matching windows''${NC}" >&2
            echo "" >&2
        fi

        show_window_env "$window_json"
    fi
  '';

in
{
  home.packages = [ windowEnv ];
}
