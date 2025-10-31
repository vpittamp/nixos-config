# Workspace window management utilities
# Provides commands for killing windows by workspace
{ pkgs, ... }:

{
  home.packages = [
    (pkgs.writeShellScriptBin "i3pm-workspace-kill" ''
      # Kill all windows in a workspace
      set -euo pipefail

      usage() {
        cat <<EOF
Usage: i3pm-workspace-kill <workspace_id>

Kill all windows in the specified workspace.

ARGUMENTS:
    <workspace_id>    Workspace number (1-70)

OPTIONS:
    -h, --help       Show this help message
    -f, --force      Force kill (SIGKILL) instead of graceful close

EXAMPLES:
    # Kill all windows in workspace 5
    i3pm-workspace-kill 5

    # Force kill all windows in workspace 10
    i3pm-workspace-kill --force 10

    # Get current workspace and kill all its windows
    i3pm-workspace-kill \$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused) | .num')
EOF
      }

      FORCE=0

      # Parse arguments
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h|--help)
            usage
            exit 0
            ;;
          -f|--force)
            FORCE=1
            shift
            ;;
          -*)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
          *)
            WORKSPACE_ID="$1"
            shift
            ;;
        esac
      done

      # Validate workspace ID
      if [ -z "''${WORKSPACE_ID:-}" ]; then
        echo "Error: Workspace ID is required" >&2
        usage >&2
        exit 1
      fi

      if ! [[ "$WORKSPACE_ID" =~ ^[0-9]+$ ]]; then
        echo "Error: Workspace ID must be a number" >&2
        exit 1
      fi

      if [ "$WORKSPACE_ID" -lt 1 ] || [ "$WORKSPACE_ID" -gt 70 ]; then
        echo "Error: Workspace ID must be between 1 and 70" >&2
        exit 1
      fi

      # Get all window IDs in the workspace
      window_ids=$(${pkgs.sway}/bin/swaymsg -t get_tree | \
        ${pkgs.jq}/bin/jq -r "
          .. |
          select(.type? == \"workspace\" and .num? == $WORKSPACE_ID) |
          .. |
          select(.pid? and .id?) |
          .id
        " | sort -u)

      if [ -z "$window_ids" ]; then
        echo "No windows found in workspace $WORKSPACE_ID"
        exit 0
      fi

      # Count windows
      window_count=$(echo "$window_ids" | wc -l)
      echo "Found $window_count window(s) in workspace $WORKSPACE_ID"

      # Kill windows
      if [ "$FORCE" -eq 1 ]; then
        echo "Force killing windows..."
        for window_id in $window_ids; do
          # Get PID and force kill
          pid=$(${pkgs.sway}/bin/swaymsg -t get_tree | \
            ${pkgs.jq}/bin/jq -r ".. | select(.id? == $window_id) | .pid")
          if [ -n "$pid" ]; then
            echo "  Killing PID $pid (window ID: $window_id)"
            kill -9 "$pid" 2>/dev/null || true
          fi
        done
      else
        echo "Gracefully closing windows..."
        for window_id in $window_ids; do
          echo "  Closing window ID: $window_id"
          ${pkgs.sway}/bin/swaymsg "[con_id=$window_id] kill" >/dev/null 2>&1 || true
        done
      fi

      echo "Done. Killed $window_count window(s) in workspace $WORKSPACE_ID"
    '')

    (pkgs.writeShellScriptBin "i3pm-workspace-close" ''
      # Alias for i3pm-workspace-kill (more intuitive name for graceful close)
      exec i3pm-workspace-kill "$@"
    '')
  ];
}
