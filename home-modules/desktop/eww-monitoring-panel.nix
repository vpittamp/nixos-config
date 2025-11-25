{ config, lib, pkgs, osConfig ? null, monitorConfig ? {}, ... }:

with lib;

let
  cfg = config.programs.eww-monitoring-panel;

  # Get hostname for monitor config lookup
  hostname = osConfig.networking.hostName or "nixos-hetzner-sway";

  # Get monitor configuration for this host (with fallback)
  hostMonitors = monitorConfig.${hostname} or {
    primary = "HEADLESS-1";
    secondary = "HEADLESS-2";
    tertiary = "HEADLESS-3";
    outputs = [ "HEADLESS-1" "HEADLESS-2" "HEADLESS-3" ];
  };

  # Export role-based outputs for use in widget config
  primaryOutput = hostMonitors.primary;
  secondaryOutput = hostMonitors.secondary;
  tertiaryOutput = hostMonitors.tertiary;

  # Feature 057: Catppuccin Mocha theme colors (consistent with unified bar system)
  mocha = {
    base = "#1e1e2e";      # Background base
    mantle = "#181825";    # Darker background
    surface0 = "#313244";  # Surface layer 1
    surface1 = "#45475a";  # Surface layer 2
    overlay0 = "#6c7086";  # Overlay/border
    text = "#cdd6f4";      # Primary text
    subtext0 = "#a6adc8";  # Dimmed text
    blue = "#89b4fa";      # Focused workspace
    sapphire = "#74c7ec";  # Secondary accent
    sky = "#89dceb";       # Tertiary accent
    teal = "#94e2d5";      # Active monitor indicator
    green = "#a6e3a1";     # Success/healthy
    yellow = "#f9e2af";    # Floating window indicator
    peach = "#fab387";     # Warning
    red = "#f38ba8";       # Urgent/critical
    mauve = "#cba6f7";     # Border accent
  };

  # Clipboard sync script - fully parameterized with nix store paths
  clipboardSyncScript = pkgs.writeShellScript "clipboard-sync" ''
    #!/usr/bin/env bash
    set -euo pipefail

    tmp=$(${pkgs.coreutils}/bin/mktemp -t clipboard-sync-XXXXXX)
    cleanup() {
      ${pkgs.coreutils}/bin/rm -f "$tmp"
    }
    trap cleanup EXIT

    ${pkgs.coreutils}/bin/cat >"$tmp"

    # Exit cleanly on empty input
    if [[ ! -s "$tmp" ]]; then
      exit 0
    fi

    # Copy to Wayland clipboard
    if [[ -n "''${WAYLAND_DISPLAY:-}" ]]; then
      ${pkgs.wl-clipboard}/bin/wl-copy <"$tmp"
      ${pkgs.wl-clipboard}/bin/wl-copy --primary <"$tmp"
    fi

    # Copy to X11 clipboard
    if command -v ${pkgs.xclip}/bin/xclip >/dev/null 2>&1; then
      ${pkgs.xclip}/bin/xclip -selection clipboard <"$tmp"
      ${pkgs.xclip}/bin/xclip -selection primary <"$tmp"
    fi
  '';

  # Python with required packages for both modes (one-shot and streaming)
  # pyxdg required for XDG icon theme lookup (resolves icon names like "firefox" to paths)
  pythonForBackend = pkgs.python3.withPackages (ps: [ ps.i3ipc ps.pyxdg ps.pydantic ]);

  # Python backend script for monitoring data
  # Supports both one-shot mode (no args) and stream mode (--listen)
  # Version: 2025-11-22-v10 (Feature 088: Added Health tab icon)
  monitoringDataScript = pkgs.writeShellScriptBin "monitoring-data-backend" ''
    #!${pkgs.bash}/bin/bash
    # Version: 2025-11-22-v10 (Feature 088: Added Health tab icon)

    # Set PYTHONPATH to tools directory for i3_project_manager imports
    export PYTHONPATH="${../tools}"

    # Set daemon socket path (system service location, not user service)
    export I3PM_DAEMON_SOCKET="/run/i3-project-daemon/ipc.sock"

    # Use Python with i3ipc package included
    # Pass through all arguments (e.g., --listen flag)
    exec ${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} "$@"
  '';

  # Toggle script for panel visibility
  # Use eww active-windows to check if panel is actually open (not just defined)
  toggleScript = pkgs.writeShellScriptBin "toggle-monitoring-panel" ''
    #!${pkgs.bash}/bin/bash
    # Check if panel is in active windows (actually open, not just defined)
    if ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel active-windows | ${pkgs.gnugrep}/bin/grep -q "monitoring-panel"; then
      # Panel is open - close it
      ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel close monitoring-panel
    else
      # Panel is closed - open it
      ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel open monitoring-panel
    fi
  '';

  # Feature 086: Toggle script for explicit panel focus (US2)
  # Allows user to lock/unlock keyboard focus to panel with Mod+Shift+M
  # Now uses Sway mode for comprehensive keyboard capture
  # Note: Eww windows are layer-shell surfaces and can't be focused via swaymsg
  toggleFocusScript = pkgs.writeShellScriptBin "toggle-panel-focus" ''
    #!${pkgs.bash}/bin/bash
    # Feature 086: Enter monitoring focus mode
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Check if panel is visible first
    if ! $EWW_CMD active-windows | ${pkgs.gnugrep}/bin/grep -q "monitoring-panel"; then
      echo "Panel not visible - use Mod+M to show it first"
      exit 0
    fi

    # Update eww variable to show focus indicator
    $EWW_CMD update panel_focused=true

    # Reset selection index
    $EWW_CMD update selected_index=0

    # Enter Sway monitoring mode (captures all keys)
    # This provides keyboard capture - eww layer-shell handles the rest
    ${pkgs.sway}/bin/swaymsg 'mode "📊 Panel"'
  '';

  # Feature 086: Exit monitoring mode script
  exitMonitorModeScript = pkgs.writeShellScriptBin "exit-monitor-mode" ''
    #!${pkgs.bash}/bin/bash
    # Feature 086: Exit monitoring focus mode
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Update eww variable to hide focus indicator
    $EWW_CMD update panel_focused=false

    # Clear selection
    $EWW_CMD update selected_index=-1

    # Exit Sway mode (return to default)
    ${pkgs.sway}/bin/swaymsg 'mode "default"'

    # Return focus to previous window
    ${pkgs.sway}/bin/swaymsg 'focus prev'
  '';

  # Feature 094: Project CRUD handler wrapper (T037)
  projectCrudScript = pkgs.writeShellScriptBin "project-crud-handler" ''
    #!${pkgs.bash}/bin/bash
    # Set PYTHONPATH to tools directory for i3_project_manager imports
    export PYTHONPATH="${../tools}"

    # Use Python with Pydantic and other dependencies
    exec ${pythonForBackend}/bin/python3 -m i3_project_manager.cli.project_crud_handler "$@"
  '';

  # Feature 094: Project edit form opener (T038)
  projectEditOpenScript = pkgs.writeShellScriptBin "project-edit-open" ''
    #!${pkgs.bash}/bin/bash
    # Open edit form by loading project data into eww variables
    # Usage: project-edit-open <name> <display_name> <icon> <directory> <scope> <remote_enabled> <remote_host> <remote_user> <remote_dir> <remote_port>

    NAME="$1"
    DISPLAY_NAME="$2"
    ICON="$3"
    DIRECTORY="$4"
    SCOPE="$5"
    REMOTE_ENABLED="$6"
    REMOTE_HOST="$7"
    REMOTE_USER="$8"
    REMOTE_DIR="$9"
    REMOTE_PORT="''${10}"

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Update all eww variables
    $EWW_CMD update editing_project_name="$NAME"
    $EWW_CMD update edit_form_display_name="$DISPLAY_NAME"
    $EWW_CMD update edit_form_icon="$ICON"
    $EWW_CMD update edit_form_directory="$DIRECTORY"
    $EWW_CMD update edit_form_scope="$SCOPE"
    $EWW_CMD update edit_form_remote_enabled="$REMOTE_ENABLED"
    $EWW_CMD update edit_form_remote_host="$REMOTE_HOST"
    $EWW_CMD update edit_form_remote_user="$REMOTE_USER"
    $EWW_CMD update edit_form_remote_dir="$REMOTE_DIR"
    $EWW_CMD update edit_form_remote_port="$REMOTE_PORT"
    $EWW_CMD update edit_form_error=""
  '';

  # Feature 094: Project edit form save handler (T038)
  projectEditSaveScript = pkgs.writeShellScriptBin "project-edit-save" ''
    #!${pkgs.bash}/bin/bash
    # Save project edit form by reading Eww variables and calling CRUD handler
    # Usage: project-edit-save <project-name>

    PROJECT_NAME="$1"
    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Read form values from Eww variables
    DISPLAY_NAME=$($EWW get edit_form_display_name)
    ICON=$($EWW get edit_form_icon)
    SCOPE=$($EWW get edit_form_scope)
    REMOTE_ENABLED=$($EWW get edit_form_remote_enabled)
    REMOTE_HOST=$($EWW get edit_form_remote_host)
    REMOTE_USER=$($EWW get edit_form_remote_user)
    REMOTE_DIR=$($EWW get edit_form_remote_dir)
    REMOTE_PORT=$($EWW get edit_form_remote_port)

    # Build JSON update object (using printf to avoid quote issues)
    UPDATES=$(printf '%s\n' "{" \
      "  \"display_name\": \"$DISPLAY_NAME\"," \
      "  \"icon\": \"$ICON\"," \
      "  \"scope\": \"$SCOPE\"," \
      "  \"remote\": {" \
      "    \"enabled\": $REMOTE_ENABLED," \
      "    \"host\": \"$REMOTE_HOST\"," \
      "    \"user\": \"$REMOTE_USER\"," \
      "    \"remote_dir\": \"$REMOTE_DIR\"," \
      "    \"port\": $REMOTE_PORT" \
      "  }" \
      "}")

    # Call CRUD handler
    export PYTHONPATH="${../tools}"
    RESULT=$(${pythonForBackend}/bin/python3 -m i3_project_manager.cli.project_crud_handler edit "$PROJECT_NAME" --updates "$UPDATES")

    # Feature 094 T041: Check for save success and conflicts
    STATUS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.status')
    CONFLICT=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.conflict // false')

    if [ "$STATUS" = "success" ]; then
      # Check for conflicts (T041)
      if [ "$CONFLICT" = "true" ]; then
        # TODO T040: Show conflict resolution dialog
        # For now, display error and keep form open
        ERROR_MSG="Conflict: File was modified externally. Please reload and try again."
        $EWW update edit_form_error="$ERROR_MSG"
        echo "Conflict detected: $ERROR_MSG" >&2
        exit 1
      fi

      # Success: Clear editing state and refresh
      $EWW update editing_project_name='''
      $EWW update edit_form_error='''

      # Refresh projects data to show updated values
      PROJECTS_DATA=$(${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} --mode projects)
      $EWW update projects_data="$PROJECTS_DATA"

      echo "Project saved successfully"
    else
      # Show validation or other errors
      ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error')
      VALIDATION_ERRORS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors // [] | length')

      if [ "$VALIDATION_ERRORS" -gt 0 ]; then
        # Extract first validation error for display
        FIRST_ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors[0].message')
        ERROR_MSG="Validation error: $FIRST_ERROR"
      else
        ERROR_MSG="$ERROR"
      fi

      $EWW update edit_form_error="$ERROR_MSG"
      echo "Error: $ERROR_MSG" >&2
      exit 1
    fi
  '';

  # Feature 094 T040: Conflict resolution handler script
  # Handles user choice when file conflicts are detected
  projectConflictResolveScript = pkgs.writeShellScriptBin "project-conflict-resolve" ''
    #!${pkgs.bash}/bin/bash
    # Feature 094 T040: Resolve file conflicts during save
    # Usage: project-conflict-resolve <action> <project-name>
    #   action: keep-file | keep-ui | merge-manual

    ACTION="$1"
    PROJECT_NAME="$2"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    case "$ACTION" in
      keep-file)
        # Discard UI changes, reload from file
        # Close edit form and conflict dialog
        $EWW_CMD update conflict_dialog_visible=false
        $EWW_CMD update editing_project_name=''''
        $EWW_CMD update edit_form_error=''''
        # Refresh project list to show file content
        PROJECTS_DATA=$(${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} --mode projects)
        $EWW_CMD update projects_data="$PROJECTS_DATA"
        echo "Kept file changes for project: $PROJECT_NAME" >&2
        ;;

      keep-ui)
        # Force overwrite file with UI changes (ignoring mtime conflict)
        # Re-run save with force flag
        # For now, just retry the save (which will fail again if conflict persists)
        # TODO: Implement force-save in project_crud_handler
        $EWW_CMD update conflict_dialog_visible=false
        echo "Force-saving UI changes for project: $PROJECT_NAME" >&2
        project-edit-save "$PROJECT_NAME"
        ;;

      merge-manual)
        # Open file in editor for manual merge
        PROJECT_FILE="$HOME/.config/i3/projects/$PROJECT_NAME.json"
        if [ -f "$PROJECT_FILE" ]; then
          # Use default editor or fallback to nano
          ''${EDITOR:-nano} "$PROJECT_FILE"
          # Close dialog and refresh
          $EWW_CMD update conflict_dialog_visible=false
          $EWW_CMD update editing_project_name=''''
          # Refresh project list
          PROJECTS_DATA=$(${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} --mode projects)
          $EWW_CMD update projects_data="$PROJECTS_DATA"
          echo "Opened $PROJECT_FILE for manual merge" >&2
        else
          echo "Error: Project file not found: $PROJECT_FILE" >&2
          exit 1
        fi
        ;;

      *)
        echo "Error: Invalid action: $ACTION" >&2
        echo "Usage: project-conflict-resolve <keep-file|keep-ui|merge-manual> <project-name>" >&2
        exit 1
        ;;
    esac
  '';

  # Feature 094 T039: Form validation stream script (300ms debouncing)
  # Monitors Eww form variables and streams validation results via deflisten
  formValidationStreamScript = pkgs.writeShellScriptBin "form-validation-stream" ''
    #!${pkgs.bash}/bin/bash
    # Feature 094 T039: Real-time form validation with 300ms debouncing

    # Set PYTHONPATH to tools directory for i3_project_manager imports
    export PYTHONPATH="${../tools}"

    # Run validation stream (reads Eww variables, outputs JSON to stdout)
    exec ${pythonForBackend}/bin/python3 ${../tools/monitoring-panel/project_form_validator_stream.py} "$HOME/.config/eww-monitoring-panel"
  '';

  # Feature 094 US5: Worktree edit form opener (T059)
  worktreeEditOpenScript = pkgs.writeShellScriptBin "worktree-edit-open" ''
    #!${pkgs.bash}/bin/bash
    # Open worktree edit form by loading worktree data into eww variables
    # Usage: worktree-edit-open <name> <display_name> <icon> <branch_name> <worktree_path> <parent_project>

    NAME="$1"
    DISPLAY_NAME="$2"
    ICON="$3"
    BRANCH_NAME="$4"
    WORKTREE_PATH="$5"
    PARENT_PROJECT="$6"

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Update all eww variables for worktree edit
    $EWW_CMD update editing_project_name="$NAME"
    $EWW_CMD update edit_form_display_name="$DISPLAY_NAME"
    $EWW_CMD update edit_form_icon="$ICON"
    # Branch name and worktree path are read-only in edit mode (per spec.md US5 scenario 6)
    $EWW_CMD update worktree_form_branch_name="$BRANCH_NAME"
    $EWW_CMD update worktree_form_path="$WORKTREE_PATH"
    $EWW_CMD update worktree_form_parent_project="$PARENT_PROJECT"
    $EWW_CMD update edit_form_error=""
  '';

  # Feature 094 US5: Worktree create script (T057-T058)
  worktreeCreateScript = pkgs.writeShellScriptBin "worktree-create" ''
    #!${pkgs.bash}/bin/bash
    # Create a new Git worktree and project config
    # Usage: worktree-create

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Read form values from Eww variables
    BRANCH_NAME=$($EWW get worktree_form_branch_name)
    WORKTREE_PATH=$($EWW get worktree_form_path)
    PARENT_PROJECT=$($EWW get worktree_form_parent_project)
    DISPLAY_NAME=$($EWW get edit_form_display_name)
    ICON=$($EWW get edit_form_icon)

    # Validate required fields
    if [[ -z "$BRANCH_NAME" ]]; then
      $EWW update edit_form_error="Branch name is required"
      exit 1
    fi
    if [[ -z "$WORKTREE_PATH" ]]; then
      $EWW update edit_form_error="Worktree path is required"
      exit 1
    fi
    if [[ -z "$PARENT_PROJECT" ]]; then
      $EWW update edit_form_error="Parent project is required"
      exit 1
    fi

    # Get parent project directory
    PARENT_FILE="$HOME/.config/i3/projects/$PARENT_PROJECT.json"
    if [[ ! -f "$PARENT_FILE" ]]; then
      $EWW update edit_form_error="Parent project not found: $PARENT_PROJECT"
      exit 1
    fi

    PARENT_DIR=$(${pkgs.jq}/bin/jq -r '.directory // .working_dir // empty' "$PARENT_FILE")
    if [[ -z "$PARENT_DIR" ]]; then
      $EWW update edit_form_error="Parent project has no directory"
      exit 1
    fi

    # Check if worktree path already exists
    if [[ -e "$WORKTREE_PATH" ]]; then
      $EWW update edit_form_error="Path already exists: $WORKTREE_PATH"
      exit 1
    fi

    # Create Git worktree
    cd "$PARENT_DIR" || {
      $EWW update edit_form_error="Cannot change to parent directory: $PARENT_DIR"
      exit 1
    }

    # Try to create worktree (branch must exist or use -b to create)
    if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
      # Branch exists
      if ! git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1; then
        $EWW update edit_form_error="Git worktree add failed"
        exit 1
      fi
    else
      # Branch doesn't exist - create it
      if ! git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" 2>&1; then
        $EWW update edit_form_error="Git worktree add failed (new branch)"
        exit 1
      fi
    fi

    # Generate worktree project name (parent-branch convention)
    WORKTREE_NAME="''${PARENT_PROJECT}-''${BRANCH_NAME//\//-}"
    if [[ -z "$DISPLAY_NAME" ]]; then
      DISPLAY_NAME="$BRANCH_NAME"
    fi
    if [[ -z "$ICON" ]]; then
      ICON="🌿"
    fi

    # Create worktree project config using CRUD handler
    export PYTHONPATH="${../tools}"
    RESULT=$(${pythonForBackend}/bin/python3 -m i3_project_manager.cli.project_crud_handler create \
      --name "$WORKTREE_NAME" \
      --display-name "$DISPLAY_NAME" \
      --icon "$ICON" \
      --directory "$WORKTREE_PATH" \
      --scope scoped \
      --worktree \
      --branch-name "$BRANCH_NAME" \
      --worktree-path "$WORKTREE_PATH" \
      --parent-project "$PARENT_PROJECT")

    STATUS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.status')
    if [[ "$STATUS" != "success" ]]; then
      ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error // "Unknown error"')
      $EWW update edit_form_error="Failed to create worktree config: $ERROR"
      # Cleanup: remove the git worktree we just created
      git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || true
      exit 1
    fi

    # Success: clear form state and refresh
    $EWW update worktree_creating=false
    $EWW update worktree_form_branch_name=""
    $EWW update worktree_form_path=""
    $EWW update worktree_form_parent_project=""
    $EWW update edit_form_display_name=""
    $EWW update edit_form_icon=""
    $EWW update edit_form_error=""

    # Refresh projects data
    PROJECTS_DATA=$(${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} --mode projects)
    $EWW update projects_data="$PROJECTS_DATA"

    echo "Worktree created successfully: $WORKTREE_NAME"
  '';

  # Feature 094 US5: Worktree delete script (T060)
  worktreeDeleteScript = pkgs.writeShellScriptBin "worktree-delete" ''
    #!${pkgs.bash}/bin/bash
    # Delete a Git worktree and its project config
    # Usage: worktree-delete <project-name>

    PROJECT_NAME="$1"
    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "Usage: worktree-delete <project-name>" >&2
      exit 1
    fi

    # Check if user confirmed deletion
    CONFIRM=$($EWW get worktree_delete_confirm)
    if [[ "$CONFIRM" != "$PROJECT_NAME" ]]; then
      # First click - set confirmation state
      $EWW update worktree_delete_confirm="$PROJECT_NAME"
      echo "Click again to confirm deletion of: $PROJECT_NAME"
      exit 0
    fi

    # User confirmed - proceed with deletion
    PROJECT_FILE="$HOME/.config/i3/projects/$PROJECT_NAME.json"
    if [[ ! -f "$PROJECT_FILE" ]]; then
      $EWW update edit_form_error="Project not found: $PROJECT_NAME"
      $EWW update worktree_delete_confirm=""
      exit 1
    fi

    # Read worktree info
    WORKTREE_PATH=$(${pkgs.jq}/bin/jq -r '.worktree_path // empty' "$PROJECT_FILE")
    PARENT_PROJECT=$(${pkgs.jq}/bin/jq -r '.parent_project // empty' "$PROJECT_FILE")

    if [[ -z "$WORKTREE_PATH" ]] || [[ -z "$PARENT_PROJECT" ]]; then
      $EWW update edit_form_error="Not a worktree project"
      $EWW update worktree_delete_confirm=""
      exit 1
    fi

    # Get parent directory for git worktree removal
    PARENT_FILE="$HOME/.config/i3/projects/$PARENT_PROJECT.json"
    if [[ -f "$PARENT_FILE" ]]; then
      PARENT_DIR=$(${pkgs.jq}/bin/jq -r '.directory // .working_dir // empty' "$PARENT_FILE")
      if [[ -n "$PARENT_DIR" ]] && [[ -d "$PARENT_DIR" ]]; then
        cd "$PARENT_DIR"
        # Remove git worktree (use --force if dirty)
        git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || true
      fi
    fi

    # Delete project config using CRUD handler
    export PYTHONPATH="${../tools}"
    RESULT=$(${pythonForBackend}/bin/python3 -m i3_project_manager.cli.project_crud_handler delete "$PROJECT_NAME")

    STATUS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.status')
    if [[ "$STATUS" != "success" ]]; then
      ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error // "Unknown error"')
      $EWW update edit_form_error="Failed to delete: $ERROR"
      $EWW update worktree_delete_confirm=""
      exit 1
    fi

    # Success: clear state and refresh
    $EWW update worktree_delete_confirm=""
    $EWW update edit_form_error=""

    # Refresh projects data
    PROJECTS_DATA=$(${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} --mode projects)
    $EWW update projects_data="$PROJECTS_DATA"

    echo "Worktree deleted successfully: $PROJECT_NAME"
  '';

  # Feature 094 US5: Worktree edit save script (T059)
  worktreeEditSaveScript = pkgs.writeShellScriptBin "worktree-edit-save" ''
    #!${pkgs.bash}/bin/bash
    # Save worktree edit form (only editable fields: display_name, icon)
    # Usage: worktree-edit-save <project-name>

    PROJECT_NAME="$1"
    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "Usage: worktree-edit-save <project-name>" >&2
      exit 1
    fi

    # Read form values (only editable fields for worktrees)
    DISPLAY_NAME=$($EWW get edit_form_display_name)
    ICON=$($EWW get edit_form_icon)

    # Build JSON update object (worktrees only allow display_name and icon changes)
    UPDATES=$(${pkgs.jq}/bin/jq -n \
      --arg display_name "$DISPLAY_NAME" \
      --arg icon "$ICON" \
      '{display_name: $display_name, icon: $icon}')

    # Call CRUD handler
    export PYTHONPATH="${../tools}"
    RESULT=$(${pythonForBackend}/bin/python3 -m i3_project_manager.cli.project_crud_handler edit "$PROJECT_NAME" --updates "$UPDATES")

    STATUS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.status')
    if [[ "$STATUS" == "success" ]]; then
      # Success: clear editing state and refresh
      $EWW update editing_project_name=""
      $EWW update edit_form_error=""

      # Refresh projects data
      PROJECTS_DATA=$(${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} --mode projects)
      $EWW update projects_data="$PROJECTS_DATA"

      echo "Worktree saved successfully"
    else
      ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error // "Unknown error"')
      $EWW update edit_form_error="$ERROR"
      echo "Error: $ERROR" >&2
      exit 1
    fi
  '';

  # Feature 094 US3: Project create form opener (T066)
  projectCreateOpenScript = pkgs.writeShellScriptBin "project-create-open" ''
    #!${pkgs.bash}/bin/bash
    # Open project create form by setting state and clearing form fields
    # Usage: project-create-open

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Clear all form fields for new project
    $EWW_CMD update create_form_name=""
    $EWW_CMD update create_form_display_name=""
    $EWW_CMD update create_form_icon="📦"
    $EWW_CMD update create_form_working_dir=""
    $EWW_CMD update create_form_scope="scoped"
    $EWW_CMD update create_form_remote_enabled=false
    $EWW_CMD update create_form_remote_host=""
    $EWW_CMD update create_form_remote_user=""
    $EWW_CMD update create_form_remote_dir=""
    $EWW_CMD update create_form_remote_port="22"
    $EWW_CMD update create_form_error=""

    # Show the create form
    $EWW_CMD update project_creating=true
  '';

  # Feature 094 US3: Project create form save handler (T069)
  projectCreateSaveScript = pkgs.writeShellScriptBin "project-create-save" ''
    #!${pkgs.bash}/bin/bash
    # Save project create form by reading Eww variables and calling CRUD handler
    # Usage: project-create-save

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Read form values from Eww variables
    NAME=$($EWW get create_form_name)
    DISPLAY_NAME=$($EWW get create_form_display_name)
    ICON=$($EWW get create_form_icon)
    WORKING_DIR=$($EWW get create_form_working_dir)
    SCOPE=$($EWW get create_form_scope)
    REMOTE_ENABLED=$($EWW get create_form_remote_enabled)
    REMOTE_HOST=$($EWW get create_form_remote_host)
    REMOTE_USER=$($EWW get create_form_remote_user)
    REMOTE_DIR=$($EWW get create_form_remote_dir)
    REMOTE_PORT=$($EWW get create_form_remote_port)

    # Client-side validation
    if [[ -z "$NAME" ]]; then
      $EWW update create_form_error="Project name is required"
      exit 1
    fi

    if [[ -z "$WORKING_DIR" ]]; then
      $EWW update create_form_error="Working directory is required"
      exit 1
    fi

    # If display name is empty, use name
    if [[ -z "$DISPLAY_NAME" ]]; then
      DISPLAY_NAME="$NAME"
    fi

    # If icon is empty, use default
    if [[ -z "$ICON" ]]; then
      ICON="📦"
    fi

    # Build JSON config object
    if [[ "$REMOTE_ENABLED" == "true" ]]; then
      CONFIG=$(${pkgs.jq}/bin/jq -n \
        --arg name "$NAME" \
        --arg display_name "$DISPLAY_NAME" \
        --arg icon "$ICON" \
        --arg working_dir "$WORKING_DIR" \
        --arg scope "$SCOPE" \
        --argjson remote_enabled true \
        --arg remote_host "$REMOTE_HOST" \
        --arg remote_user "$REMOTE_USER" \
        --arg remote_dir "$REMOTE_DIR" \
        --argjson remote_port "$REMOTE_PORT" \
        '{
          name: $name,
          display_name: $display_name,
          icon: $icon,
          working_dir: $working_dir,
          scope: $scope,
          remote: {
            enabled: $remote_enabled,
            host: $remote_host,
            user: $remote_user,
            remote_dir: $remote_dir,
            port: $remote_port
          }
        }')
    else
      CONFIG=$(${pkgs.jq}/bin/jq -n \
        --arg name "$NAME" \
        --arg display_name "$DISPLAY_NAME" \
        --arg icon "$ICON" \
        --arg working_dir "$WORKING_DIR" \
        --arg scope "$SCOPE" \
        '{
          name: $name,
          display_name: $display_name,
          icon: $icon,
          working_dir: $working_dir,
          scope: $scope
        }')
    fi

    # Call Python CRUD handler
    export PYTHONPATH="${../tools}"
    RESULT=$(${pythonForBackend}/bin/python3 ${../tools/monitoring-panel/project_crud_handler.py} <<EOF
import asyncio
import json
import sys
sys.path.insert(0, "${../tools}")
from project_crud_handler import ProjectCRUDHandler

handler = ProjectCRUDHandler()
request = {"action": "create_project", "config": $CONFIG}
result = asyncio.run(handler.handle_request(request))
print(json.dumps(result))
EOF
)

    # Check result
    SUCCESS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.success')
    if [[ "$SUCCESS" == "true" ]]; then
      # Success: clear form state and refresh
      $EWW update project_creating=false
      $EWW update create_form_name=""
      $EWW update create_form_display_name=""
      $EWW update create_form_icon="📦"
      $EWW update create_form_working_dir=""
      $EWW update create_form_scope="scoped"
      $EWW update create_form_remote_enabled=false
      $EWW update create_form_remote_host=""
      $EWW update create_form_remote_user=""
      $EWW update create_form_remote_dir=""
      $EWW update create_form_remote_port="22"
      $EWW update create_form_error=""

      # Refresh projects data
      PROJECTS_DATA=$(${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} --mode projects)
      $EWW update projects_data="$PROJECTS_DATA"

      echo "Project created successfully: $NAME"
    else
      # Show error message
      ERROR_MSG=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error_message')
      VALIDATION_ERRORS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors | length')

      if [[ "$VALIDATION_ERRORS" -gt 0 ]]; then
        FIRST_ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors[0]')
        $EWW update create_form_error="$FIRST_ERROR"
      elif [[ -n "$ERROR_MSG" ]] && [[ "$ERROR_MSG" != "null" ]]; then
        $EWW update create_form_error="$ERROR_MSG"
      else
        $EWW update create_form_error="Failed to create project"
      fi
      exit 1
    fi
  '';

  # Feature 094 US3: Project create form cancel handler (T066)
  projectCreateCancelScript = pkgs.writeShellScriptBin "project-create-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel project create form
    # Usage: project-create-cancel

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Hide form and clear all fields
    $EWW update project_creating=false
    $EWW update create_form_name=""
    $EWW update create_form_display_name=""
    $EWW update create_form_icon="📦"
    $EWW update create_form_working_dir=""
    $EWW update create_form_scope="scoped"
    $EWW update create_form_remote_enabled=false
    $EWW update create_form_remote_host=""
    $EWW update create_form_remote_user=""
    $EWW update create_form_remote_dir=""
    $EWW update create_form_remote_port="22"
    $EWW update create_form_error=""
  '';

  # Feature 094 US8: Application create form open handler (T076)
  appCreateOpenScript = pkgs.writeShellScriptBin "app-create-open" ''
    #!${pkgs.bash}/bin/bash
    # Open application create form
    # Usage: app-create-open

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Clear any previous form state
    $EWW_CMD update create_app_type="regular"
    $EWW_CMD update create_app_name=""
    $EWW_CMD update create_app_display_name=""
    $EWW_CMD update create_app_command=""
    $EWW_CMD update create_app_parameters=""
    $EWW_CMD update create_app_expected_class=""
    $EWW_CMD update create_app_scope="scoped"
    $EWW_CMD update create_app_workspace="1"
    $EWW_CMD update create_app_monitor_role=""
    $EWW_CMD update create_app_icon=""
    $EWW_CMD update create_app_floating=false
    $EWW_CMD update create_app_floating_size=""
    $EWW_CMD update create_app_start_url=""
    $EWW_CMD update create_app_scope_url=""
    $EWW_CMD update create_app_error=""
    $EWW_CMD update create_app_ulid_result=""

    # Show the create form
    $EWW_CMD update app_creating=true
  '';

  # Feature 094 US8: Application create form save handler (T082)
  appCreateSaveScript = pkgs.writeShellScriptBin "app-create-save" ''
    #!${pkgs.bash}/bin/bash
    # Save application create form by reading Eww variables and calling CRUD handler
    # Usage: app-create-save

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Read form values from Eww variables
    APP_TYPE=$($EWW get create_app_type)
    NAME=$($EWW get create_app_name)
    DISPLAY_NAME=$($EWW get create_app_display_name)
    COMMAND=$($EWW get create_app_command)
    PARAMETERS=$($EWW get create_app_parameters)
    EXPECTED_CLASS=$($EWW get create_app_expected_class)
    SCOPE=$($EWW get create_app_scope)
    WORKSPACE=$($EWW get create_app_workspace)
    MONITOR_ROLE=$($EWW get create_app_monitor_role)
    ICON=$($EWW get create_app_icon)
    FLOATING=$($EWW get create_app_floating)
    FLOATING_SIZE=$($EWW get create_app_floating_size)
    START_URL=$($EWW get create_app_start_url)
    SCOPE_URL=$($EWW get create_app_scope_url)

    # Build JSON based on app type
    if [[ "$APP_TYPE" == "pwa" ]]; then
      # PWA: auto-add -pwa suffix if missing
      if [[ "$NAME" != *-pwa ]]; then
        NAME="''${NAME}-pwa"
      fi
      # Generate ULID for PWA
      ULID=$(${pkgs.bash}/bin/bash /etc/nixos/scripts/generate-ulid.sh)
      EXPECTED_CLASS="FFPWA-$ULID"

      CONFIG_JSON=$(${pkgs.jq}/bin/jq -n \
        --arg name "$NAME" \
        --arg display_name "$DISPLAY_NAME" \
        --arg command "firefoxpwa" \
        --argjson parameters '["site", "launch", "'"$ULID"'"]' \
        --arg expected_class "$EXPECTED_CLASS" \
        --arg scope "global" \
        --argjson preferred_workspace "$WORKSPACE" \
        --arg icon "$ICON" \
        --arg ulid "$ULID" \
        --arg start_url "$START_URL" \
        --arg scope_url "$SCOPE_URL" \
        '{
          name: $name,
          display_name: $display_name,
          command: $command,
          parameters: $parameters,
          expected_class: $expected_class,
          scope: $scope,
          preferred_workspace: $preferred_workspace,
          icon: $icon,
          ulid: $ulid,
          start_url: $start_url,
          scope_url: $scope_url
        }')
    elif [[ "$APP_TYPE" == "terminal" ]]; then
      # Terminal app
      # Parse parameters string to array
      PARAMS_ARRAY=$(echo "$PARAMETERS" | ${pkgs.jq}/bin/jq -R 'split(" ") | map(select(. != ""))')

      CONFIG_JSON=$(${pkgs.jq}/bin/jq -n \
        --arg name "$NAME" \
        --arg display_name "$DISPLAY_NAME" \
        --arg command "$COMMAND" \
        --argjson parameters "$PARAMS_ARRAY" \
        --arg expected_class "$EXPECTED_CLASS" \
        --arg scope "$SCOPE" \
        --argjson preferred_workspace "$WORKSPACE" \
        --arg monitor_role "$MONITOR_ROLE" \
        --arg icon "$ICON" \
        --argjson floating "$FLOATING" \
        --arg floating_size "$FLOATING_SIZE" \
        --argjson terminal true \
        '{
          name: $name,
          display_name: $display_name,
          command: $command,
          parameters: $parameters,
          expected_class: $expected_class,
          scope: $scope,
          preferred_workspace: $preferred_workspace,
          icon: $icon,
          floating: $floating,
          terminal: $terminal
        } | if $monitor_role != "" then . + {preferred_monitor_role: $monitor_role} else . end
          | if $floating and $floating_size != "" then . + {floating_size: $floating_size} else . end')
    else
      # Regular app
      PARAMS_ARRAY=$(echo "$PARAMETERS" | ${pkgs.jq}/bin/jq -R 'split(" ") | map(select(. != ""))')

      CONFIG_JSON=$(${pkgs.jq}/bin/jq -n \
        --arg name "$NAME" \
        --arg display_name "$DISPLAY_NAME" \
        --arg command "$COMMAND" \
        --argjson parameters "$PARAMS_ARRAY" \
        --arg expected_class "$EXPECTED_CLASS" \
        --arg scope "$SCOPE" \
        --argjson preferred_workspace "$WORKSPACE" \
        --arg monitor_role "$MONITOR_ROLE" \
        --arg icon "$ICON" \
        --argjson floating "$FLOATING" \
        --arg floating_size "$FLOATING_SIZE" \
        '{
          name: $name,
          display_name: $display_name,
          command: $command,
          parameters: $parameters,
          expected_class: $expected_class,
          scope: $scope,
          preferred_workspace: $preferred_workspace,
          icon: $icon,
          floating: $floating
        } | if $monitor_role != "" then . + {preferred_monitor_role: $monitor_role} else . end
          | if $floating and $floating_size != "" then . + {floating_size: $floating_size} else . end')
    fi

    # Call the CRUD handler
    export PYTHONPATH="${../tools}"
    REQUEST_JSON=$(${pkgs.jq}/bin/jq -n \
      --arg action "create_app" \
      --argjson config "$CONFIG_JSON" \
      '{action: $action, config: $config}')

    RESULT=$(echo "$REQUEST_JSON" | ${pythonForBackend}/bin/python3 -c "
import sys
import json
import asyncio
sys.path.insert(0, '${../tools}')
sys.path.insert(0, '${../tools/monitoring-panel}')
from app_crud_handler import AppCRUDHandler

handler = AppCRUDHandler()
request = json.loads(sys.stdin.read())
result = asyncio.run(handler.handle_request(request))
print(json.dumps(result))
")

    # Check result
    SUCCESS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.success')
    if [[ "$SUCCESS" == "true" ]]; then
      # Success: clear form state and refresh
      $EWW update app_creating=false
      $EWW update create_app_type="regular"
      $EWW update create_app_name=""
      $EWW update create_app_display_name=""
      $EWW update create_app_command=""
      $EWW update create_app_parameters=""
      $EWW update create_app_expected_class=""
      $EWW update create_app_scope="scoped"
      $EWW update create_app_workspace="1"
      $EWW update create_app_monitor_role=""
      $EWW update create_app_icon=""
      $EWW update create_app_floating=false
      $EWW update create_app_floating_size=""
      $EWW update create_app_start_url=""
      $EWW update create_app_scope_url=""
      $EWW update create_app_error=""

      # If PWA, show generated ULID
      if [[ "$APP_TYPE" == "pwa" ]]; then
        ULID=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.ulid // empty')
        if [[ -n "$ULID" ]]; then
          $EWW update create_app_ulid_result="$ULID"
        fi
      fi

      # Refresh apps data
      APPS_DATA=$(${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} --mode apps)
      $EWW update apps_data="$APPS_DATA"

      echo "Application created successfully: $NAME"
    else
      # Show error message
      ERROR_MSG=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error_message')
      VALIDATION_ERRORS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors | join(", ")')
      if [[ -n "$VALIDATION_ERRORS" && "$VALIDATION_ERRORS" != "null" ]]; then
        $EWW update create_app_error="$VALIDATION_ERRORS"
      else
        $EWW update create_app_error="$ERROR_MSG"
      fi
      echo "Error creating application: $ERROR_MSG" >&2
      exit 1
    fi
  '';

  # Feature 094 US8: Application create form cancel handler (T076)
  appCreateCancelScript = pkgs.writeShellScriptBin "app-create-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel application create form
    # Usage: app-create-cancel

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Hide form and clear all fields
    $EWW update app_creating=false
    $EWW update create_app_type="regular"
    $EWW update create_app_name=""
    $EWW update create_app_display_name=""
    $EWW update create_app_command=""
    $EWW update create_app_parameters=""
    $EWW update create_app_expected_class=""
    $EWW update create_app_scope="scoped"
    $EWW update create_app_workspace="1"
    $EWW update create_app_monitor_role=""
    $EWW update create_app_icon=""
    $EWW update create_app_floating=false
    $EWW update create_app_floating_size=""
    $EWW update create_app_start_url=""
    $EWW update create_app_scope_url=""
    $EWW update create_app_error=""
    $EWW update create_app_ulid_result=""
  '';

  # Feature 094 US4: Project delete confirmation open handler (T087)
  projectDeleteOpenScript = pkgs.writeShellScriptBin "project-delete-open" ''
    #!${pkgs.bash}/bin/bash
    # Open project delete confirmation dialog
    # Usage: project-delete-open <project_name> <display_name>

    set -euo pipefail

    PROJECT_NAME="''${1:-}"
    DISPLAY_NAME="''${2:-}"

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "Error: Project name required" >&2
      exit 1
    fi

    # Check if project has worktrees by looking for worktrees with this parent
    PROJECTS_DIR="$HOME/.config/i3/projects"
    HAS_WORKTREES="false"
    for f in "$PROJECTS_DIR"/*.json; do
      if [[ -f "$f" ]]; then
        PARENT=$(${pkgs.jq}/bin/jq -r '.parent_project // empty' "$f" 2>/dev/null || echo "")
        if [[ "$PARENT" == "$PROJECT_NAME" ]]; then
          HAS_WORKTREES="true"
          break
        fi
      fi
    done

    # Clear previous state
    $EWW update delete_error=""
    $EWW update delete_success_message=""
    $EWW update delete_force=false

    # Set dialog state
    $EWW update delete_project_name="$PROJECT_NAME"
    $EWW update delete_project_display_name="''${DISPLAY_NAME:-$PROJECT_NAME}"
    $EWW update delete_project_has_worktrees="$HAS_WORKTREES"
    $EWW update project_deleting=true
  '';

  # Feature 094 US4: Project delete confirm handler (T088)
  projectDeleteConfirmScript = pkgs.writeShellScriptBin "project-delete-confirm" ''
    #!${pkgs.bash}/bin/bash
    # Execute project deletion via CRUD handler
    # Usage: project-delete-confirm

    set -euo pipefail

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Read deletion parameters
    PROJECT_NAME=$($EWW get delete_project_name)
    FORCE=$($EWW get delete_force)

    if [[ -z "$PROJECT_NAME" ]]; then
      $EWW update delete_error="No project selected for deletion"
      exit 1
    fi

    # Build request JSON
    if [[ "$FORCE" == "true" ]]; then
      REQUEST=$(${pkgs.jq}/bin/jq -n \
        --arg name "$PROJECT_NAME" \
        '{"action": "delete_project", "project_name": $name, "force": true}')
    else
      REQUEST=$(${pkgs.jq}/bin/jq -n \
        --arg name "$PROJECT_NAME" \
        '{"action": "delete_project", "project_name": $name}')
    fi

    echo "Deleting project: $PROJECT_NAME (force=$FORCE)" >&2

    # Call the CRUD handler
    RESULT=$(echo "$REQUEST" | ${pythonForBackend}/bin/python3 ${../tools/monitoring-panel/project_crud_handler.py})

    # Check result
    SUCCESS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.success')

    if [[ "$SUCCESS" == "true" ]]; then
      # Success - close dialog
      $EWW update project_deleting=false
      $EWW update delete_project_name=""
      $EWW update delete_project_display_name=""
      $EWW update delete_project_has_worktrees=false
      $EWW update delete_force=false
      $EWW update delete_error=""

      # Refresh projects data
      PROJECTS_DATA=$(${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} --mode projects)
      $EWW update projects_data="$PROJECTS_DATA"

      # Brief success notification
      ${pkgs.libnotify}/bin/notify-send -t 3000 "Project Deleted" "''${PROJECT_NAME} has been deleted"

      echo "Project deleted successfully: $PROJECT_NAME"
    else
      # Show error in dialog
      ERROR_MSG=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error_message')
      $EWW update delete_error="$ERROR_MSG"
      echo "Error deleting project: $ERROR_MSG" >&2
      exit 1
    fi
  '';

  # Feature 094 US4: Project delete cancel handler (T089)
  projectDeleteCancelScript = pkgs.writeShellScriptBin "project-delete-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel project delete confirmation dialog
    # Usage: project-delete-cancel

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Hide dialog and clear state
    $EWW update project_deleting=false
    $EWW update delete_project_name=""
    $EWW update delete_project_display_name=""
    $EWW update delete_project_has_worktrees=false
    $EWW update delete_force=false
    $EWW update delete_error=""
  '';

  # Feature 094 US9: Application delete confirmation open handler (T093)
  appDeleteOpenScript = pkgs.writeShellScriptBin "app-delete-open" ''
    #!${pkgs.bash}/bin/bash
    # Open application delete confirmation dialog
    # Usage: app-delete-open <app_name> <display_name> [is_pwa] [ulid]

    set -euo pipefail

    APP_NAME="''${1:-}"
    DISPLAY_NAME="''${2:-}"
    IS_PWA="''${3:-false}"
    ULID="''${4:-}"

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$APP_NAME" ]]; then
      echo "Error: App name required" >&2
      exit 1
    fi

    # Clear previous state
    $EWW update delete_app_error=""

    # Set dialog state
    $EWW update delete_app_name="$APP_NAME"
    $EWW update delete_app_display_name="''${DISPLAY_NAME:-$APP_NAME}"
    $EWW update delete_app_is_pwa="$IS_PWA"
    $EWW update delete_app_ulid="$ULID"
    $EWW update app_deleting=true
  '';

  # Feature 094 US9: Application delete confirm handler (T094)
  appDeleteConfirmScript = pkgs.writeShellScriptBin "app-delete-confirm" ''
    #!${pkgs.bash}/bin/bash
    # Execute application deletion via CRUD handler
    # Usage: app-delete-confirm

    set -euo pipefail

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Read deletion parameters
    APP_NAME=$($EWW get delete_app_name)

    if [[ -z "$APP_NAME" ]]; then
      $EWW update delete_app_error="No application selected for deletion"
      exit 1
    fi

    # Build request JSON
    REQUEST=$(${pkgs.jq}/bin/jq -n \
      --arg name "$APP_NAME" \
      '{"action": "delete_app", "app_name": $name}')

    echo "Deleting application: $APP_NAME" >&2

    # Call the CRUD handler
    RESULT=$(echo "$REQUEST" | ${pythonForBackend}/bin/python3 ${../tools/monitoring-panel/app_crud_handler.py})

    # Check result
    SUCCESS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.success')

    if [[ "$SUCCESS" == "true" ]]; then
      # Check for PWA warning
      PWA_WARNING=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.pwa_warning // empty')

      # Success - close dialog
      $EWW update app_deleting=false
      $EWW update delete_app_name=""
      $EWW update delete_app_display_name=""
      $EWW update delete_app_is_pwa=false
      $EWW update delete_app_ulid=""
      $EWW update delete_app_error=""

      # Refresh apps data
      APPS_DATA=$(${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} --mode apps)
      $EWW update apps_data="$APPS_DATA"

      # Show notification with PWA warning if applicable
      if [[ -n "$PWA_WARNING" ]]; then
        ${pkgs.libnotify}/bin/notify-send -t 8000 "Application Deleted" "$APP_NAME deleted. Note: $PWA_WARNING"
      else
        ${pkgs.libnotify}/bin/notify-send -t 3000 "Application Deleted" "$APP_NAME has been deleted. Rebuild required."
      fi

      echo "Application deleted successfully: $APP_NAME"
    else
      # Show error in dialog
      ERROR_MSG=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error_message')
      $EWW update delete_app_error="$ERROR_MSG"
      echo "Error deleting application: $ERROR_MSG" >&2
      exit 1
    fi
  '';

  # Feature 094 Phase 12 T099: Success notification helper with auto-dismiss
  showSuccessNotificationScript = pkgs.writeShellScriptBin "monitoring-panel-notify" ''
    #!${pkgs.bash}/bin/bash
    # Show success notification toast with auto-dismiss
    # Usage: monitoring-panel-notify "Message text" [timeout_seconds]

    MESSAGE="''${1:-Operation completed}"
    TIMEOUT="''${2:-3}"

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Show notification
    $EWW update success_notification="$MESSAGE"
    $EWW update success_notification_visible=true

    # Auto-dismiss after timeout
    (sleep "$TIMEOUT" && $EWW update success_notification_visible=false success_notification="") &
  '';

  # Feature 094 US9: Application delete cancel handler (T095)
  appDeleteCancelScript = pkgs.writeShellScriptBin "app-delete-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel application delete confirmation dialog
    # Usage: app-delete-cancel

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Hide dialog and clear state
    $EWW update app_deleting=false
    $EWW update delete_app_name=""
    $EWW update delete_app_display_name=""
    $EWW update delete_app_is_pwa=false
    $EWW update delete_app_ulid=""
    $EWW update delete_app_error=""
  '';

  # Feature 093: Focus window action script (T009-T015)
  # Focuses a window with automatic project switching if needed
  focusWindowScript = pkgs.writeShellScriptBin "focus-window-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 093: Focus window with automatic project switching
    set -euo pipefail

    PROJECT_NAME="''${1:-}"
    WINDOW_ID="''${2:-}"

    # Validate inputs (T010)
    if [[ -z "$PROJECT_NAME" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Focus Action Failed" "No project name provided"
        exit 1
    fi

    if [[ -z "$WINDOW_ID" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Focus Action Failed" "No window ID provided"
        exit 1
    fi

    # Lock file mechanism for debouncing (T011)
    LOCK_FILE="/tmp/eww-monitoring-focus-''${WINDOW_ID}.lock"

    if [[ -f "$LOCK_FILE" ]]; then
        # Silently ignore if previous action still in progress
        exit 1
    fi

    touch "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT

    # Get current project (T012)
    CURRENT_PROJECT=$(i3pm project current --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.project_name // "global"' || echo "global")

    # Conditional project switch (T013)
    if [[ "$PROJECT_NAME" != "$CURRENT_PROJECT" ]]; then
        if ! i3pm project switch "$PROJECT_NAME"; then
            EXIT_CODE=$?
            ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Failed" \
                "Failed to switch to project $PROJECT_NAME (exit code: $EXIT_CODE)"
            exit 1
        fi
    fi

    # Focus window (T014)
    if ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] focus"; then
        # Success path (T015) - Visual feedback only, no notification
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_window_id=$WINDOW_ID
        (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_window_id=0) &
        exit 0
    else
        # Failure path - Keep critical notification for actual errors
        ${pkgs.libnotify}/bin/notify-send -u critical "Focus Failed" "Window no longer available"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_window_id=0
        exit 1
    fi
  '';

  # Feature 093: Switch project action script (T016-T020)
  # Switches to a different project context by name
  switchProjectScript = pkgs.writeShellScriptBin "switch-project-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 093: Switch to a different project context
    set -euo pipefail

    PROJECT_NAME="''${1:-}"

    # Validate input (T017)
    if [[ -z "$PROJECT_NAME" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Failed" "No project name provided"
        exit 1
    fi

    # Lock file mechanism for debouncing (T018)
    LOCK_FILE="/tmp/eww-monitoring-project-''${PROJECT_NAME}.lock"

    if [[ -f "$LOCK_FILE" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Project Switch" "Previous action still in progress"
        exit 1
    fi

    touch "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT

    # Get current project (T019)
    CURRENT_PROJECT=$(i3pm project current --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.project_name // "global"' || echo "global")

    # Check if already in target project
    if [[ "$PROJECT_NAME" == "$CURRENT_PROJECT" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Already in project $PROJECT_NAME"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="$PROJECT_NAME"
        (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="") &
        exit 0
    fi

    # Execute project switch (T020)
    if i3pm project switch "$PROJECT_NAME"; then
        ${pkgs.libnotify}/bin/notify-send -u normal "Switched to project $PROJECT_NAME"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="$PROJECT_NAME"
        (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="") &
        exit 0
    else
        EXIT_CODE=$?
        ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Failed" \
            "Failed to switch to $PROJECT_NAME (exit code: $EXIT_CODE)"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project=""
        exit 1
    fi
  '';

  # SwayNC toggle wrapper
  swayNCToggleScript = pkgs.writeShellScriptBin "toggle-swaync" ''
    #!${pkgs.bash}/bin/bash
    # Toggle SwayNC notification center
    ${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw
  '';

  # Feature 088 US3: Service restart script with sudo handling (T025)
  # Usage: restart-service <service_name> <is_user_service>
  # Example: restart-service eww-top-bar true
  # Example: restart-service tailscaled.service false
  restartServiceScript = pkgs.writeShellScriptBin "restart-service" ''
    #!${pkgs.bash}/bin/bash
    # Feature 088 US3: Service restart script with sudo handling and notifications
    set -euo pipefail

    SERVICE_NAME="''${1:-}"
    IS_USER_SERVICE="''${2:-false}"

    # Validate arguments
    if [[ -z "$SERVICE_NAME" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Service Restart Failed" "No service name provided"
        echo "Error: Service name required" >&2
        echo "Usage: restart-service <service_name> <is_user_service>" >&2
        exit 1
    fi

    # Build systemctl command
    SYSTEMCTL_CMD=("${pkgs.systemd}/bin/systemctl")

    if [[ "$IS_USER_SERVICE" == "true" ]]; then
        SYSTEMCTL_CMD+=("--user")
    else
        # System service - use sudo
        SYSTEMCTL_CMD=(${pkgs.sudo}/bin/sudo ${pkgs.systemd}/bin/systemctl)
    fi

    SYSTEMCTL_CMD+=("restart" "$SERVICE_NAME")

    # Execute restart
    echo "Restarting service: $SERVICE_NAME (user service: $IS_USER_SERVICE)"
    if "''${SYSTEMCTL_CMD[@]}"; then
        ${pkgs.libnotify}/bin/notify-send -u normal "Service Restarted" "Successfully restarted $SERVICE_NAME"
        echo "Success: $SERVICE_NAME restarted" >&2
        exit 0
    else
        EXIT_CODE=$?
        ${pkgs.libnotify}/bin/notify-send -u critical "Service Restart Failed" "Failed to restart $SERVICE_NAME (exit code: $EXIT_CODE)"
        echo "Error: Failed to restart $SERVICE_NAME (exit code: $EXIT_CODE)" >&2
        exit $EXIT_CODE
    fi
  '';

  # Feature 086: Navigation script for monitoring panel
  monitorPanelNavScript = pkgs.writeShellScriptBin "monitor-panel-nav" ''
    #!${pkgs.bash}/bin/bash
    # Feature 086: Handle navigation within monitoring panel
    ACTION="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get current state
    current_index=$($EWW_CMD get selected_index 2>/dev/null || echo "0")
    current_view=$($EWW_CMD get current_view 2>/dev/null || echo "windows")
    selected_window=$($EWW_CMD get selected_window_id 2>/dev/null || echo "0")

    # Get window count from monitoring data
    window_count=$($EWW_CMD get monitoring_data 2>/dev/null | ${pkgs.jq}/bin/jq -r '.window_count // 10')
    max_items=$((window_count > 0 ? window_count : 10))

    case "$ACTION" in
      down)
        new_index=$((current_index + 1))
        if [ "$new_index" -ge "$max_items" ]; then
          new_index=$((max_items - 1))
        fi
        $EWW_CMD update selected_index=$new_index
        ;;
      up)
        new_index=$((current_index - 1))
        if [ "$new_index" -lt 0 ]; then
          new_index=0
        fi
        $EWW_CMD update selected_index=$new_index
        ;;
      first)
        $EWW_CMD update selected_index=0
        ;;
      last)
        $EWW_CMD update selected_index=$((max_items - 1))
        ;;
      select)
        # Get window ID at current index and show detail view
        window_id=$($EWW_CMD get monitoring_data 2>/dev/null | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '
          [.projects[].workspaces[].windows[]] | .[$idx].id // 0
        ')
        if [ "$window_id" != "0" ] && [ "$window_id" != "null" ] && [ -n "$window_id" ]; then
          $EWW_CMD update selected_window_id=$window_id
        fi
        ;;
      back)
        # Clear selection - go back to list view
        $EWW_CMD update selected_window_id=0
        ;;
      focus)
        # Focus the selected window in Sway
        if [ "$selected_window" != "0" ] && [ "$selected_window" != "null" ]; then
          ${pkgs.sway}/bin/swaymsg "[con_id=$selected_window] focus"
          # Exit panel mode after focusing
          exit-monitor-mode
        fi
        ;;
    esac
  '';

  # Feature 094: Copy window JSON helper script (used by Windows tab)
  copyWindowJsonScript = pkgs.writeShellScript "copy-window-json" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    JSON_BASE64="''${1:-}"
    WINDOW_ID="''${2:-0}"

    if [[ -z "$JSON_BASE64" ]]; then
      echo "Usage: copy-window-json <window-json-b64> <window-id>" >&2
      exit 1
    fi

    # Decode payload and copy to clipboard
    ${pkgs.coreutils}/bin/printf %s "$JSON_BASE64" \
      | ${pkgs.coreutils}/bin/base64 -d \
      | ${pkgs.wl-clipboard}/bin/wl-copy

    # Toggle copied state for visual feedback
    $EWW_CMD update copied_window_id="$WINDOW_ID"
    (${pkgs.coreutils}/bin/sleep 2 && $EWW_CMD update copied_window_id=0) &
  '';

  # Keyboard handler script for view switching (Alt+1-4 or just 1-4)
  handleKeyScript = pkgs.writeShellScript "monitoring-panel-keyhandler" ''
    KEY="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    # Debug: log the key to journal
    echo "Monitoring panel key pressed: '$KEY'" | ${pkgs.systemd}/bin/systemd-cat -t eww-keyhandler
    case "$KEY" in
      1|Alt+1) $EWW_CMD update current_view=windows ;;
      2|Alt+2) $EWW_CMD update current_view=projects ;;
      3|Alt+3) $EWW_CMD update current_view=apps ;;
      4|Alt+4) $EWW_CMD update current_view=health ;;
      5|Alt+5) $EWW_CMD update current_view=events ;;
      Escape|q) $EWW_CMD close monitoring-panel ;;
    esac
  '';

in
{
  options.programs.eww-monitoring-panel = {
    enable = mkEnableOption "Eww monitoring panel for window/project state visualization";

    toggleKey = mkOption {
      type = types.str;
      default = "$mod+m";
      description = ''
        Keybinding to toggle monitoring panel visibility.
        Uses Sway mod variable (typically Super/Win key).
      '';
    };

    updateInterval = mkOption {
      type = types.int;
      default = 10;
      description = ''
        DEPRECATED: This option is no longer used since migrating to deflisten.
        Kept for backward compatibility but has no effect.
        Updates are now real-time via event stream (<100ms latency).
      '';
    };
  };

  config = mkIf cfg.enable {
    # Add required packages
    home.packages = [
      pkgs.eww              # Widget framework
      monitoringDataScript  # Python backend script wrapper
      toggleScript          # Toggle visibility script
      toggleFocusScript     # Feature 086: Toggle focus script
      exitMonitorModeScript # Feature 086: Exit monitoring mode
      monitorPanelNavScript # Feature 086: Navigation within panel
      swayNCToggleScript    # SwayNC toggle with mutual exclusivity
      restartServiceScript  # Feature 088 US3: Service restart script
      focusWindowScript     # Feature 093: Focus window action
      switchProjectScript   # Feature 093: Switch project action
      projectCrudScript     # Feature 094: Project CRUD handler (T037)
      projectEditOpenScript # Feature 094: Project edit form opener (T038)
      projectEditSaveScript # Feature 094: Project edit save handler (T038)
      worktreeEditOpenScript  # Feature 094 US5: Worktree edit form opener (T059)
      worktreeCreateScript    # Feature 094 US5: Worktree create handler (T057-T058)
      worktreeDeleteScript    # Feature 094 US5: Worktree delete handler (T060)
      worktreeEditSaveScript  # Feature 094 US5: Worktree edit save handler (T059)
      projectCreateOpenScript   # Feature 094 US3: Project create form opener (T066)
      projectCreateSaveScript   # Feature 094 US3: Project create save handler (T069)
      projectCreateCancelScript # Feature 094 US3: Project create cancel handler (T066)
      appCreateOpenScript       # Feature 094 US8: App create form opener (T076)
      appCreateSaveScript       # Feature 094 US8: App create save handler (T082)
      appCreateCancelScript     # Feature 094 US8: App create cancel handler (T076)
      projectDeleteOpenScript   # Feature 094 US4: Project delete dialog opener (T087)
      projectDeleteConfirmScript # Feature 094 US4: Project delete confirm handler (T088)
      projectDeleteCancelScript # Feature 094 US4: Project delete cancel handler (T089)
      appDeleteOpenScript       # Feature 094 US9: App delete dialog opener (T093)
      appDeleteConfirmScript    # Feature 094 US9: App delete confirm handler (T094)
      appDeleteCancelScript     # Feature 094 US9: App delete cancel handler (T095)
      showSuccessNotificationScript # Feature 094 Phase 12 T099: Success notification helper
    ];

    # Eww Yuck widget configuration (T009-T014)
    # Version: v9-dynamic-sizing (Build: 2025-11-21-18:15)
    xdg.configFile."eww-monitoring-panel/eww.yuck".text = ''
      ;; Live Window/Project Monitoring Panel - Multi-View Edition
      ;; Feature 085: Sway Monitoring Widget
      ;; Build: 2025-11-20 15:55 UTC

      ;; Deflisten: Real-time event stream for Windows view (<100ms latency)
      ;; Backend subscribes to Sway window/workspace/output events
      ;; Automatic reconnection with exponential backoff
      ;; Heartbeat every 5s to detect stale connections
      (deflisten monitoring_data
        :initial "{\"status\":\"connecting\",\"projects\":[],\"project_count\":0,\"monitor_count\":0,\"workspace_count\":0,\"window_count\":0,\"timestamp\":0,\"timestamp_friendly\":\"Initializing...\",\"error\":null}"
        `${monitoringDataScript}/bin/monitoring-data-backend --listen`)

      ;; Defpoll: Projects view data (5s refresh)
      (defpoll projects_data
        :interval "5s"
        :initial "{\"status\":\"loading\",\"projects\":[],\"project_count\":0,\"active_project\":null}"
        `${monitoringDataScript}/bin/monitoring-data-backend --mode projects`)

      ;; Defpoll: Apps view data (5s refresh)
      (defpoll apps_data
        :interval "5s"
        :initial "{\"status\":\"loading\",\"apps\":[],\"app_count\":0}"
        `${monitoringDataScript}/bin/monitoring-data-backend --mode apps`)

      ;; Defpoll: Health view data (5s refresh)
      (defpoll health_data
        :interval "5s"
        :initial "{\"status\":\"loading\",\"health\":{}}"
        `${monitoringDataScript}/bin/monitoring-data-backend --mode health`)

      ;; Feature 092: Deflisten: Real-time Sway event log stream
      ;; Subscribes to window/workspace/output IPC events with <100ms latency
      ;; Maintains circular buffer of 500 most recent events (FIFO eviction)
      (deflisten events_data
        :initial "{\"status\":\"connecting\",\"events\":[],\"event_count\":0,\"daemon_available\":true,\"ipc_connected\":false,\"timestamp\":0,\"timestamp_friendly\":\"Initializing...\"}"
        `${monitoringDataScript}/bin/monitoring-data-backend --mode events --listen`)

      ;; Feature 094 T039: Deflisten: Real-time form validation stream
      ;; Monitors form variable changes and streams validation results with 300ms debouncing
      ;; Provides live validation feedback for project edit forms
      (deflisten validation_state
        :initial "{\"valid\":true,\"editing\":false,\"errors\":{},\"warnings\":{},\"timestamp\":\"\"}"
        `${formValidationStreamScript}/bin/form-validation-stream`)

      ;; Current view state (windows, projects, apps, health, events)
      (defvar current_view "windows")

      ;; Selected window ID for detail view (0 = none selected)
      (defvar selected_window_id 0)

      ;; Feature 086: Panel focus state (updated by toggle-panel-focus script)
      ;; When true, panel has keyboard focus and shows visual indicator
      (defvar panel_focused false)

      ;; Feature 086: Selected index for keyboard navigation (-1 = none)
      ;; Updated by j/k or up/down in monitoring mode
      (defvar selected_index -1)

      ;; Hover tooltip state - Window ID being hovered (0 = none)
      ;; Updated by onhover/onhoverlost events on window items
      (defvar hover_window_id 0)

      ;; Copy state - Window ID that was just copied (0 = none)
      ;; Set when copy button clicked, auto-resets after 2 seconds
      (defvar copied_window_id 0)

      ;; Event-driven state variable (updated by daemon publisher)
      (defvar panel_state "{}")

      ;; Feature 093: Click interaction state variables (T021-T023)
      ;; Window ID of last clicked window (0 = no window clicked or auto-reset after 2s)
      (defvar clicked_window_id 0)

      ;; Project name of last clicked project header ("" = no project clicked or auto-reset after 2s)
      (defvar clicked_project "")

      ;; True if a click action is currently executing (lock file exists)
      (defvar click_in_progress false)

      ;; Feature 094: Project hover and copy state
      (defvar hover_project_name "")

      ;; Feature 094: Hover state for Applications tab detail tooltips
      (defvar hover_app_name "")
      (defvar copied_project_name "")

      ;; Feature 094: Edit mode state for Projects tab (T038)
      (defvar editing_project_name "")
      (defvar edit_form_display_name "")
      (defvar edit_form_icon "")
      (defvar edit_form_directory "")
      (defvar edit_form_scope "scoped")
      (defvar edit_form_remote_enabled false)
      (defvar edit_form_remote_host "")
      (defvar edit_form_remote_user "")
      (defvar edit_form_remote_dir "")
      (defvar edit_form_remote_port "22")
      (defvar edit_form_error "")  ;; T041: Error message for save failures

      ;; Feature 094 US3: Project create form state (T066-T069)
      (defvar project_creating false)               ;; True when create project form is visible
      (defvar create_form_name "")                  ;; Project name (unique identifier)
      (defvar create_form_display_name "")          ;; Display name
      (defvar create_form_icon "📦")                ;; Icon emoji
      (defvar create_form_working_dir "")           ;; Working directory path
      (defvar create_form_scope "scoped")           ;; Scope: scoped or global
      (defvar create_form_remote_enabled false)     ;; Remote project toggle
      (defvar create_form_remote_host "")           ;; Remote SSH host
      (defvar create_form_remote_user "")           ;; Remote SSH user
      (defvar create_form_remote_dir "")            ;; Remote working directory
      (defvar create_form_remote_port "22")         ;; Remote SSH port
      (defvar create_form_error "")                 ;; Error message for create failures

      ;; Feature 094 US8: Application create form state (T076-T082)
      (defvar app_creating false)                    ;; True when create app form is visible
      (defvar create_app_type "regular")             ;; App type: regular, terminal, pwa
      (defvar create_app_name "")                    ;; Application name (unique identifier)
      (defvar create_app_display_name "")            ;; Display name
      (defvar create_app_command "")                 ;; Executable command
      (defvar create_app_parameters "")              ;; Command-line parameters (space-separated)
      (defvar create_app_expected_class "")          ;; Window class for matching
      (defvar create_app_scope "scoped")             ;; Scope: scoped or global
      (defvar create_app_workspace "1")              ;; Preferred workspace (1-50 for regular, 50+ for PWA)
      (defvar create_app_monitor_role "")            ;; Monitor role: primary, secondary, tertiary, or empty
      (defvar create_app_icon "")                    ;; Icon name, emoji, or file path
      (defvar create_app_floating false)             ;; Launch as floating window
      (defvar create_app_floating_size "")           ;; Floating size: scratchpad, small, medium, large
      (defvar create_app_start_url "")               ;; PWA start URL
      (defvar create_app_scope_url "")               ;; PWA scope URL
      (defvar create_app_error "")                   ;; Error message for create failures
      (defvar create_app_ulid_result "")             ;; Generated ULID after successful PWA creation

      ;; Feature 094 US5: Worktree form state (T057-T061)
      (defvar worktree_creating false)            ;; True when create worktree form is visible
      (defvar worktree_form_branch_name "")       ;; Branch name (editable in create, read-only in edit)
      (defvar worktree_form_path "")              ;; Worktree path (editable in create, read-only in edit)
      (defvar worktree_form_parent_project "")    ;; Parent project name (required for worktrees)
      (defvar worktree_delete_confirm "")         ;; Project name to confirm deletion (click-to-confirm)

      ;; Feature 094 US4: Project delete confirmation state (T086-T089)
      (defvar project_deleting false)              ;; True when delete confirmation dialog is visible
      (defvar delete_project_name "")              ;; Name of project to delete
      (defvar delete_project_display_name "")      ;; Display name for confirmation message
      (defvar delete_project_has_worktrees false)  ;; True if project has worktrees
      (defvar delete_force false)                  ;; Force delete (even with worktrees)
      (defvar delete_error "")                     ;; Error message from delete operation
      (defvar delete_success_message "")           ;; Success message after deletion

      ;; Feature 094 US9: Application delete confirmation state (T093-T096)
      (defvar app_deleting false)                   ;; True when delete confirmation dialog is visible
      (defvar delete_app_name "")                   ;; Name of app to delete
      (defvar delete_app_display_name "")           ;; Display name for confirmation message
      (defvar delete_app_is_pwa false)              ;; True if app is a PWA
      (defvar delete_app_ulid "")                   ;; ULID for PWA (for uninstall command)
      (defvar delete_app_error "")                  ;; Error message from delete operation

      ;; Feature 094 Phase 12: Loading and notification states (T098-T099)
      (defvar save_in_progress false)               ;; True during save operations (disables form inputs)
      (defvar success_notification "")              ;; Success message to display (auto-dismiss after 3s)
      (defvar success_notification_visible false)   ;; Controls success notification visibility

      ;; Feature 094 T040: Conflict resolution dialog state
      (defvar conflict_dialog_visible false)
      (defvar conflict_file_content "")  ;; JSON from disk
      (defvar conflict_ui_content "")    ;; JSON from UI form
      (defvar conflict_project_name "")

      ;; Feature 094 US7: Edit mode state for Applications tab (T048)
      (defvar editing_app_name "")
      (defvar edit_display_name "")
      (defvar edit_workspace "")
      (defvar edit_icon "")
      (defvar edit_start_url "")

      ;; Main monitoring panel window - Sidebar layout
      ;; Non-focusable overlay: stays visible but allows interaction with apps underneath
      ;; Tab switching via global Sway keybindings (Alt+1-4) since widget doesn't capture input
      ;; Use output name directly since monitor indices vary by platform
      ;; Dynamic sizing: 90% height adapts to different screen sizes (M1: 720px, Hetzner: ~972px)
      (defwindow monitoring-panel
        :monitor "${primaryOutput}"
        :geometry (geometry
          :anchor "right center"
          :x "0px"
          :y "0px"
          :width "450px"
          :height "90%")
        :namespace "eww-monitoring-panel"
        :stacking "fg"
        :focusable "ondemand"
        :exclusive false
        :windowtype "dock"
        (monitoring-panel-content))

      ;; Main panel content widget with keyboard navigation
      ;; Feature 086: Dynamic class changes when panel has focus
      (defwidget monitoring-panel-content []
        (eventbox
          :onkeypress "${handleKeyScript} {}"
          :cursor "default"
          (box
            :class {panel_focused ? "panel-container focused" : "panel-container"}
            :orientation "v"
            :space-evenly false
            (panel-header)
            (panel-body)
            (panel-footer)
            ;; Feature 094 T040: Conflict resolution dialog overlay
            (conflict-resolution-dialog)
            ;; Feature 094 Phase 12 T099: Success notification overlay (auto-dismiss)
            (success-notification-toast))))

      ;; Panel header with tab navigation
      (defwidget panel-header []
        (box
          :class "panel-header"
          :orientation "v"
          :space-evenly false
          ;; Tab navigation bar
          (box
            :class "tabs"
            :orientation "h"
            :space-evenly true
            (eventbox
              :cursor "pointer"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update current_view=windows"
              (button
                :class "tab ''${current_view == 'windows' ? 'active' : ""}"
                :tooltip "Windows (Alt+1)"
                "󰖯"))
            (eventbox
              :cursor "pointer"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update current_view=projects"
              (button
                :class "tab ''${current_view == 'projects' ? 'active' : ""}"
                :tooltip "Projects (Alt+2)"
                "󱂬"))
            (eventbox
              :cursor "pointer"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update current_view=apps"
              (button
                :class "tab ''${current_view == 'apps' ? 'active' : ""}"
                :tooltip "Apps (Alt+3)"
                "󰀻"))
            (eventbox
              :cursor "pointer"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update current_view=health"
              (button
                :class "tab ''${current_view == 'health' ? 'active' : ""}"
                :tooltip "Health (Alt+4)"
                "󰓙"))
            ;; Feature 092: Logs tab (5th tab)
            (eventbox
              :cursor "pointer"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update current_view=events"
              (button
                :class "tab ''${current_view == 'events' ? 'active' : ""}"
                :tooltip "Logs (Alt+5)"
                "󰌱"))
            ;; Feature 086: Focus mode indicator badge
            (label
              :class "focus-indicator"
              :visible {panel_focused}
              :text "⌨ FOCUS"))
          ;; Summary counts (dynamic based on view)
          (box
            :class "summary-counts"
            :orientation "h"
            :space-evenly true
            (label
              :class "count-badge"
              :text "''${current_view == 'windows' ? monitoring_data.project_count ?: 0 : current_view == 'projects' ? projects_data.project_count ?: 0 : current_view == 'apps' ? apps_data.app_count ?: 0 : 0} ''${current_view == 'windows' || current_view == 'projects' ? 'PRJ' : current_view == 'apps' ? 'APPS' : 'ITEMS'}")
            (label
              :class "count-badge"
              :text "''${current_view == 'windows' ? monitoring_data.workspace_count ?: 0 : 0} WS"
              :visible {current_view == "windows"})
            (label
              :class "count-badge"
              :text "''${current_view == 'windows' ? monitoring_data.window_count ?: 0 : 0} WIN"
              :visible {current_view == "windows"}))))

      ;; Panel body with multi-view container
      ;; Uses overlay to ensure only one view is visible at a time (no stacking)
      (defwidget panel-body []
        (box
          :class "panel-body"
          :orientation "v"
          :vexpand true
          (overlay
            :vexpand true
            ;; Only one of these will be visible at a time
            (box
              :vexpand true
              :visible {current_view == "windows"}
              (windows-view))
            (box
              :vexpand true
              :visible {current_view == "projects"}
              (projects-view))
            (box
              :vexpand true
              :visible {current_view == "apps"}
              (apps-view))
            (box
              :vexpand true
              :visible {current_view == "health"}
              (health-view))
            ;; Feature 092: Events/Logs View - Real-time Sway IPC event log
            (box
              :visible {current_view == "events"}
              (events-view)))))

      ;; Windows View - Project-based hierarchy with real-time updates
      ;; Shows detail view when a window is selected, otherwise shows list
      (defwidget windows-view []
        (scroll
          :vscroll true
          :hscroll false
          :vexpand true
          (box
            :class "content-container"
            :orientation "v"
            :space-evenly false
            :vexpand true
            ;; Show detail view when window is selected
            (box
              :visible {selected_window_id != 0}
              :vexpand true
              (window-detail-view))
            ;; Show list view when no window is selected
            (box
              :visible {selected_window_id == 0}
              :orientation "v"
              :space-evenly false
              :vexpand true
              ; Show error state when status is "error"
              (box
                :visible {monitoring_data.status == "error"}
                (error-state))
              ; Show empty state when no windows and no error
              (box
                :visible {monitoring_data.status != "error" && (monitoring_data.window_count ?: 0) == 0}
                (empty-state))
              ; Show projects when no error and has windows
              (box
                :visible {monitoring_data.status != "error" && (monitoring_data.window_count ?: 0) > 0}
                :orientation "v"
                :space-evenly false
                (for project in {monitoring_data.projects ?: []}
                  (project-widget :project project)))))))

      ;; Project display widget
      (defwidget project-widget [project]
        (box
          :class "project ''${project.scope == 'scoped' ? 'scoped-project' : 'global-project'}"
          :orientation "v"
          :space-evenly false
          ; Project header
          (box
            :class "project-header"
            :orientation "h"
            :space-evenly false
            (label
              :class "project-name"
              :text "''${project.scope == 'scoped' ? '󱂬' : '󰞇'} ''${project.name}")
            (label
              :class "window-count-badge"
              :text "''${project.window_count}"))
          ; Windows list
          (box
            :class "windows-container"
            :orientation "v"
            :space-evenly false
            (for window in {project.windows ?: []}
              (window-widget :window window)))))

      ;; Compact window widget for sidebar - Single line with badges + JSON hover tooltip
      ;; Click to show detail view (stores window ID)
      ;; Hover to show syntax-highlighted JSON with copy button
      ;; Fixed: Entire widget wrapped in eventbox so tooltip stays open when hovering over JSON
      (defwidget window-widget [window]
        (eventbox
          :onhover "eww --config $HOME/.config/eww-monitoring-panel update hover_window_id=''${window.id}"
          :onhoverlost "eww --config $HOME/.config/eww-monitoring-panel update hover_window_id=0"
          (box
            :class "window-container"
            :orientation "v"
            :space-evenly false
            ;; Main window item (clickable)
            ;; Feature 093: Added click handler for window focus with project switching
            (eventbox
              :onclick "focus-window-action ''${window.project} ''${window.id} &"
              :cursor "pointer"
              (box
                :class "window ''${window.scope == 'scoped' ? 'scoped-window' : 'global-window'} ''${window.state_classes} ''${clicked_window_id == window.id ? ' clicked' : ""} ''${strlength(window.icon_path) > 0 ? 'has-icon' : 'no-icon'}"
                :orientation "h"
                :space-evenly false
                ; App icon (image if available, fallback emoji otherwise)
                (box
                  :class "window-icon-container"
                  :valign "center"
                  (image :class "window-icon-image"
                         :path {strlength(window.icon_path) > 0 ? window.icon_path : "/etc/nixos/assets/icons/tmux-original.svg"}
                         :image-width 20
                         :image-height 20
                         :visible {strlength(window.icon_path) > 0})
                  (label
                    :class "window-icon-fallback"
                    :text "''${window.floating ? '⚓' : '󱂬'}"
                    :visible {strlength(window.icon_path) == 0}))
                ; App name and truncated title
                (box
                  :class "window-info"
                  :orientation "v"
                  :space-evenly false
                  :hexpand true
                  (label
                    :class "window-app-name"
                    :halign "start"
                    :text "''${window.display_name}"
                    :limit-width 18
                    :truncate true)
                  (label
                    :class "window-title"
                    :halign "start"
                    :text "''${window.title ?: '#' + window.id}"
                    :limit-width 25
                    :truncate true))
                ; Compact badges for states
                (box
                  :class "window-badges"
                  :orientation "h"
                  :space-evenly false
                  :hexpand true
                  :halign "end"
                  (label
                    :class "badge badge-workspace"
                    :text "WS''${window.workspace_number}")
                  (label
                    :class "badge badge-pwa"
                    :text "PWA"
                    :visible {window.is_pwa ?: false}))))
            ;; JSON hover tooltip (slides down on hover)
            (revealer
              :reveal {hover_window_id == window.id}
              :transition "slidedown"
              :duration "150ms"
              (box
                :class "window-json-tooltip"
                :orientation "v"
                :space-evenly false
                ;; Header with title and copy button
                (box
                  :class "json-tooltip-header"
                  :orientation "h"
                  :space-evenly false
                  (label
                    :class "json-tooltip-title"
                    :halign "start"
                    :hexpand true
                    :text "Window JSON (ID: ''${window.id})")
                  (eventbox
                    :cursor "pointer"
                    :onclick "${copyWindowJsonScript} ''${window.json_base64} ''${window.id} &"
                    :tooltip "Copy JSON to clipboard"
                    (label
                      :class "json-copy-btn''${copied_window_id == window.id ? ' copied' : ""}"
                      :text "''${copied_window_id == window.id ? '󰄬' : '󰆏'}")))
                ;; Scrollable JSON content with syntax highlighting
                (scroll
                  :vscroll true
                  :hscroll false
                  :vexpand false
                  :height 200
                  (label
                    :class "json-content"
                    :halign "start"
                    :markup "''${window.json_repr}"
                    :wrap false)))))))

      ;; Empty state display (T041)
      (defwidget empty-state []
        (box
          :class "empty-state"
          :orientation "v"
          :valign "center"
          :halign "center"
          :vexpand true
          (label
            :class "empty-icon"
            :text "󰝧")
          (label
            :class "empty-title"
            :text "No Windows Open")
          (label
            :class "empty-message"
            :text "Open a window to see it here")))

      ;; Feature 094 Phase 12 T102: Empty state for projects tab
      (defwidget projects-empty-state []
        (box
          :class "empty-state"
          :orientation "v"
          :valign "center"
          :halign "center"
          :vexpand true
          (label
            :class "empty-icon"
            :text "󱂬")
          (label
            :class "empty-title"
            :text "No Projects Configured")
          (label
            :class "empty-message"
            :text "Create a project to manage workspaces")
          (button
            :class "empty-action-button"
            :onclick "project-create-open"
            "+ Create Project")))

      ;; Feature 094 Phase 12 T102: Empty state for apps tab
      (defwidget apps-empty-state []
        (box
          :class "empty-state"
          :orientation "v"
          :valign "center"
          :halign "center"
          :vexpand true
          (label
            :class "empty-icon"
            :text "󰀻")
          (label
            :class "empty-title"
            :text "No Applications Registered")
          (label
            :class "empty-message"
            :text "Add applications to manage workspaces")
          (button
            :class "empty-action-button"
            :onclick "app-create-open"
            "+ Add Application")))

      ;; Error state display (T042)
      (defwidget error-state []
        (box
          :class "error-state"
          :orientation "v"
          :valign "center"
          :halign "center"
          :vexpand true
          (label
            :class "error-icon"
            :text "󰀪")
          (label
            :class "error-message"
            :text "''${monitoring_data.error ?: 'Unknown error'}")))

      ;; Window Detail View - Shows comprehensive info when window is selected
      ;; Iterates through all_windows to find the matching ID
      (defwidget window-detail-view []
        (box
          :class "detail-view"
          :orientation "v"
          :space-evenly false
          :vexpand true
          ;; Header with back button
          (box
            :class "detail-header"
            :orientation "h"
            :space-evenly false
            (button
              :class "detail-back-btn"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update selected_window_id=0"
              :tooltip "Back to window list"
              "󰁍 Back")
            (label
              :class "detail-title"
              :hexpand true
              :halign "center"
              :text "Window Details"))
          ;; Detail content - iterate through all_windows and show the matching one
          (scroll
            :vscroll true
            :hscroll false
            :vexpand true
            (box
              :class "detail-content"
              :orientation "v"
              :space-evenly false
              (for win in {monitoring_data.all_windows ?: []}
                (box
                  :visible {win.id == selected_window_id}
                  :orientation "v"
                  :space-evenly false
                  ;; Identity section
                  (box
                    :class "detail-section"
                    :orientation "v"
                    :space-evenly false
                    (label :class "detail-section-title" :halign "start" :text "Identity")
                    (detail-row :label "ID" :value "''${win.id}")
                    (detail-row :label "PID" :value "''${win.pid ?: '-'}")
                    (detail-row :label "App ID" :value "''${win.app_id ?: '-'}")
                    (detail-row :label "Class" :value "''${win.class ?: '-'}")
                    (detail-row :label "Instance" :value "''${win.instance ?: '-'}"))
                  ;; Title section
                  (box
                    :class "detail-section"
                    :orientation "v"
                    :space-evenly false
                    (label :class "detail-section-title" :halign "start" :text "Title")
                    (label
                      :class "detail-full-title"
                      :halign "start"
                      :wrap true
                      :text "''${win.full_title ?: win.title ?: '-'}"))
                  ;; Location section
                  (box
                    :class "detail-section"
                    :orientation "v"
                    :space-evenly false
                    (label :class "detail-section-title" :halign "start" :text "Location")
                    (detail-row :label "Workspace" :value "''${win.workspace ?: '-'}")
                    (detail-row :label "Output" :value "''${win.output ?: '-'}")
                    (detail-row :label "Project" :value "''${win.project ?: '-'}")
                    (detail-row :label "Scope" :value "''${win.scope ?: '-'}"))
                  ;; State section
                  (box
                    :class "detail-section"
                    :orientation "v"
                    :space-evenly false
                    (label :class "detail-section-title" :halign "start" :text "State")
                    (detail-row :label "Floating" :value "''${win.floating}")
                    (detail-row :label "Focused" :value "''${win.focused}")
                    (detail-row :label "Hidden" :value "''${win.hidden}")
                    (detail-row :label "Fullscreen" :value "''${win.fullscreen ?: false}")
                    (detail-row :label "PWA" :value "''${win.is_pwa}"))
                  ;; Geometry section
                  (box
                    :class "detail-section"
                    :orientation "v"
                    :space-evenly false
                    (label :class "detail-section-title" :halign "start" :text "Geometry")
                    (detail-row :label "Position" :value "''${win.geometry_x}, ''${win.geometry_y}")
                    (detail-row :label "Size" :value "''${win.geometry_width} × ''${win.geometry_height}"))
                  ;; Marks section
                  (box
                    :class "detail-section"
                    :orientation "v"
                    :space-evenly false
                    (label :class "detail-section-title" :halign "start" :text "Marks")
                    (label
                      :class "detail-marks"
                      :halign "start"
                      :wrap true
                      :text "''${arraylength(win.marks ?: []) > 0 ? win.marks : 'None'}"))))))))

      ;; Detail row widget - key/value pair
      (defwidget detail-row [label value]
        (box
          :class "detail-row"
          :orientation "h"
          :space-evenly false
          (label
            :class "detail-label"
            :halign "start"
            :text label)
          (label
            :class "detail-value"
            :halign "end"
            :hexpand true
            :text value)))

      ;; Projects View - Project list with metadata
      (defwidget projects-view []
        (scroll
          :vscroll true
          :hscroll false
          :vexpand true
          (box
            :class "content-container"
            :orientation "v"
            :space-evenly false
            ;; Feature 094 US3: Projects tab header with New Project button (T066)
            (box
              :class "projects-header"
              :orientation "h"
              :space-evenly false
              :visible {!project_creating}
              (label
                :class "projects-header-title"
                :halign "start"
                :hexpand true
                :text "Projects")
              (button
                :class "new-project-button"
                :onclick "project-create-open"
                :tooltip "Create a new project"
                "+ New Project"))
            ;; Feature 094 US3: Project create form (T067)
            (revealer
              :transition "slidedown"
              :reveal project_creating
              :duration "200ms"
              (project-create-form))
            ;; Feature 094 US4: Delete confirmation dialog (T088)
            (project-delete-confirmation)
            ;; Error state
            (box
              :class "error-message"
              :visible {projects_data.status == "error"}
              (label :text "Error: ''${projects_data.error ?: 'Unknown error'}"))
            ;; Main projects
            (for project in {projects_data.main_projects ?: []}
              (box
                :orientation "v"
                :space-evenly false
                ;; Main project card
                (project-card :project project)
                ;; Worktrees for this main project
                (for worktree in {projects_data.worktrees ?: []}
                  (box
                    :visible {worktree.parent_project == project.name}
                    (worktree-card :project worktree))))))))

      (defwidget project-card [project]
        (eventbox
          :onhover "eww update hover_project_name=''${project.name}"
          :onhoverlost "eww update hover_project_name='''"
          (box
            :class "project-card"
            :orientation "v"
            :space-evenly false
            (box
              :class "project-card-header"
              :orientation "h"
              :space-evenly false
              ;; Icon
              (box
                :class "project-icon-container"
                :orientation "v"
                :valign "center"
                (label
                  :class "project-icon"
                  :text "''${project.icon}"))
              ;; Project info
              (box
                :class "project-info"
                :orientation "v"
                :space-evenly false
                :hexpand false
                (box
                  :class "project-name-row"
                  :orientation "h"
                  :space-evenly false
                  (label
                    :class "project-card-name"
                    :halign "start"
                    :truncate true
                    :text "''${project.display_name ?: project.name}")
                  ;; Remote indicator
                  (label
                    :class "remote-indicator"
                    :visible {project.is_remote}
                    :text "󰒍"))
                (label
                  :class "project-card-path"
                  :halign "start"
                  :truncate true
                  :text "''${project.directory}"))
              ;; Active indicator
              (label
                :class "active-indicator"
                :visible {project.is_active}
                :text "●")
              ;; Feature 094: Edit button (T038)
              (button
                :class "edit-button"
                :visible {editing_project_name != project.name && !project_deleting}
                :onclick "project-edit-open \"''${project.name}\" \"''${project.display_name ?: project.name}\" \"''${project.icon}\" \"''${project.directory}\" \"''${project.scope ?: 'scoped'}\" \"''${project.remote.enabled}\" \"''${project.remote.host}\" \"''${project.remote.user}\" \"''${project.remote.remote_dir}\" \"''${project.remote.port}\""
                "✏")
              ;; Feature 094 US4: Delete button (T087)
              (button
                :class "delete-button"
                :visible {editing_project_name != project.name && !project_deleting}
                :onclick "project-delete-open \"''${project.name}\" \"''${project.display_name ?: project.name}\""
                :tooltip "Delete project"
                "🗑"))
            ;; Hover detail tooltip
            (revealer
              :reveal {hover_project_name == project.name && editing_project_name != project.name}
              :transition "slidedown"
              :duration "200ms"
              (box
                :class "project-detail-tooltip"
                :orientation "v"
                :space-evenly false
                (label
                  :class "json-detail"
                  :halign "start"
                  :wrap true
                  :text "''${project.directory}")))
            ;; Feature 094: Inline edit form (T038)
            (revealer
              :reveal {editing_project_name == project.name}
              :transition "slidedown"
              :duration "300ms"
              (project-edit-form :project project)))))

      (defwidget worktree-card [project]
        (eventbox
          :onhover "eww update hover_project_name=''${project.name}"
          :onhoverlost "eww update hover_project_name='''"
          (box
            :class "worktree-card"
            :orientation "v"
            :space-evenly false
            (box
              :class "project-card-header"
              :orientation "h"
              :space-evenly false
              ;; Worktree tree indicator
              (label
                :class "worktree-tree"
                :text "''${"├─"}")
              ;; Icon
              (box
                :class "project-icon-container"
                :orientation "v"
                :valign "center"
                (label
                  :class "project-icon worktree-icon"
                  :text "''${project.icon}"))
              ;; Project info
              (box
                :class "project-info"
                :orientation "v"
                :space-evenly false
                :hexpand true
                (box
                  :class "project-name-row"
                  :orientation "h"
                  :space-evenly false
                  (label
                    :class "project-card-name worktree-name"
                    :halign "start"
                    :text "''${project.display_name ?: project.name}")
                  ;; Branch indicator (US5)
                  (label
                    :class "branch-indicator"
                    :visible {project.branch_name != ""}
                    :text "''${project.branch_name}")
                  ;; Remote indicator
                  (label
                    :class "remote-indicator"
                    :visible {project.is_remote}
                    :text "󰒍"))
                (label
                  :class "project-card-path"
                  :halign "start"
                  :truncate true
                  :text "''${project.directory}"))
              ;; Action buttons (visible on hover, hide when editing)
              (revealer
                :reveal {hover_project_name == project.name && editing_project_name != project.name}
                :transition "slideleft"
                :duration "150ms"
                (box
                  :class "worktree-actions"
                  :orientation "h"
                  :space-evenly false
                  (button
                    :class "worktree-action-btn edit-btn"
                    :tooltip "Edit worktree"
                    :onclick "worktree-edit-open \"''${project.name}\" \"''${project.display_name ?: project.name}\" \"''${project.icon}\" \"''${project.branch_name}\" \"''${project.worktree_path}\" \"''${project.parent_project}\""
                    "''${"✏️"}")
                  (button
                    :class "worktree-action-btn delete-btn ''${worktree_delete_confirm == project.name ? "confirm" : ""}"
                    :tooltip "''${worktree_delete_confirm == project.name ? "Click again to confirm" : "Delete worktree"}"
                    :onclick "worktree-delete ''${project.name}"
                    "''${worktree_delete_confirm == project.name ? "❗" : "🗑️"}")))
              ;; Active indicator
              (label
                :class "active-indicator"
                :visible {project.is_active}
                :text "●"))
            ;; Hover detail tooltip (hide when editing)
            (revealer
              :reveal {hover_project_name == project.name && editing_project_name != project.name}
              :transition "slidedown"
              :duration "200ms"
              (box
                :class "project-detail-tooltip"
                :orientation "v"
                :space-evenly false
                (label
                  :class "json-detail"
                  :halign "start"
                  :wrap true
                  :text "''${project.directory}")))
            ;; Edit form (T059: Worktree edit shows read-only branch/path)
            (revealer
              :reveal {editing_project_name == project.name}
              :transition "slidedown"
              :duration "200ms"
              (worktree-edit-form :project project)))))

      ;; Feature 094: Project edit form widget (T038)
      (defwidget project-edit-form [project]
        (box
          :class "edit-form"
          :orientation "v"
          :space-evenly false
          ;; Form header
          (label
            :class "edit-form-header"
            :halign "start"
            :text "Edit Project")
          ;; Display name field
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Display Name")
            (input
              :class "field-input"
              :value edit_form_display_name
              :onchange "eww update edit_form_display_name={}")
            ;; T039: Validation error for display_name
            (revealer
              :reveal {validation_state.errors.display_name != ""}
              :transition "slidedown"
              :duration "150ms"
              (label
                :class "field-error"
                :halign "start"
                :wrap true
                :text {validation_state.errors.display_name ?: ""})))
          ;; Icon field
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Icon (emoji or path)")
            (input
              :class "field-input"
              :value edit_form_icon
              :onchange "eww update edit_form_icon={}")
            ;; T039: Validation error for icon
            (revealer
              :reveal {validation_state.errors.icon != ""}
              :transition "slidedown"
              :duration "150ms"
              (label
                :class "field-error"
                :halign "start"
                :wrap true
                :text {validation_state.errors.icon ?: ""})))
          ;; Directory field (read-only)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Directory (read-only)")
            (label
              :class "field-value-readonly"
              :halign "start"
              :wrap true
              :text edit_form_directory))
          ;; Scope field
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Scope")
            (box
              :class "radio-group"
              :orientation "h"
              :space-evenly false
              (button
                :class "''${edit_form_scope == 'scoped' ? 'radio-button selected' : 'radio-button'}"
                :onclick "eww update edit_form_scope='scoped'"
                "Scoped")
              (button
                :class "''${edit_form_scope == 'global' ? 'radio-button selected' : 'radio-button'}"
                :onclick "eww update edit_form_scope='global'"
                "Global")))
          ;; Remote SSH configuration
          (box
            :class "form-section"
            :orientation "v"
            :space-evenly false
            ;; Remote enabled checkbox
            (box
              :class "form-field"
              :orientation "h"
              :space-evenly false
              (checkbox
                :checked edit_form_remote_enabled
                :onchecked "eww update edit_form_remote_enabled=true"
                :onunchecked "eww update edit_form_remote_enabled=false")
              (label
                :class "field-label"
                :text "Enable Remote SSH"))
            ;; Remote fields (conditional)
            (revealer
              :reveal edit_form_remote_enabled
              :transition "slidedown"
              :duration "200ms"
              (box
                :class "remote-fields"
                :orientation "v"
                :space-evenly false
                ;; Host
                (box
                  :class "form-field"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "field-label"
                    :halign "start"
                    :text "SSH Host")
                  (input
                    :class "field-input"
                    :value edit_form_remote_host
                    :onchange "eww update edit_form_remote_host={}")
                  ;; T039: Validation error for remote host
                  (revealer
                    :reveal {validation_state.errors["remote.host"] != ""}
                    :transition "slidedown"
                    :duration "150ms"
                    (label
                      :class "field-error"
                      :halign "start"
                      :wrap true
                      :text {validation_state.errors["remote.host"] ?: ""})))
                ;; User
                (box
                  :class "form-field"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "field-label"
                    :halign "start"
                    :text "SSH User")
                  (input
                    :class "field-input"
                    :value edit_form_remote_user
                    :onchange "eww update edit_form_remote_user={}")
                  ;; T039: Validation error for remote user
                  (revealer
                    :reveal {validation_state.errors["remote.user"] != ""}
                    :transition "slidedown"
                    :duration "150ms"
                    (label
                      :class "field-error"
                      :halign "start"
                      :wrap true
                      :text {validation_state.errors["remote.user"] ?: ""})))
                ;; Remote directory
                (box
                  :class "form-field"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "field-label"
                    :halign "start"
                    :text "Remote Directory")
                  (input
                    :class "field-input"
                    :value edit_form_remote_dir
                    :onchange "eww update edit_form_remote_dir={}")
                  ;; T039: Validation error for remote directory
                  (revealer
                    :reveal {validation_state.errors["remote.working_dir"] != ""}
                    :transition "slidedown"
                    :duration "150ms"
                    (label
                      :class "field-error"
                      :halign "start"
                      :wrap true
                      :text {validation_state.errors["remote.working_dir"] ?: ""})))
                ;; Port
                (box
                  :class "form-field"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "field-label"
                    :halign "start"
                    :text "SSH Port")
                  (input
                    :class "field-input"
                    :value edit_form_remote_port
                    :onchange "eww update edit_form_remote_port={}")
                  ;; T039: Validation error for remote port
                  (revealer
                    :reveal {validation_state.errors["remote.port"] != ""}
                    :transition "slidedown"
                    :duration "150ms"
                    (label
                      :class "field-error"
                      :halign "start"
                      :wrap true
                      :text {validation_state.errors["remote.port"] ?: ""}))))))
          ;; Error message display (T041)
          (revealer
            :reveal {edit_form_error != ""}
            :transition "slidedown"
            :duration "200ms"
            (label
              :class "error-message"
              :halign "start"
              :wrap true
              :text edit_form_error))
          ;; Action buttons
          (box
            :class "form-actions"
            :orientation "h"
            :space-evenly false
            :halign "end"
            (button
              :class "cancel-button"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update editing_project_name='''' && eww --config $HOME/.config/eww-monitoring-panel update edit_form_error=''''"
              "Cancel")
            (button
              :class "''${validation_state.valid ? 'save-button' : 'save-button-disabled'}"
              :sensitive {validation_state.valid}
              :onclick "project-edit-save ''${project.name}"
              "Save"))))

      ;; Feature 094 US5 T059: Worktree edit form widget
      ;; Similar to project-edit-form but with read-only branch and path fields
      (defwidget worktree-edit-form [project]
        (box
          :class "edit-form worktree-edit-form"
          :orientation "v"
          :space-evenly false
          ;; Form header
          (label
            :class "edit-form-header"
            :halign "start"
            :text "Edit Worktree")
          ;; Display name field (editable)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Display Name")
            (input
              :class "field-input"
              :value edit_form_display_name
              :onchange "eww update edit_form_display_name={}"))
          ;; Icon field (editable)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Icon")
            (input
              :class "field-input"
              :value edit_form_icon
              :onchange "eww update edit_form_icon={}"))
          ;; Branch name field (read-only per spec.md US5 scenario 6)
          (box
            :class "form-field readonly-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Branch (read-only)")
            (label
              :class "field-readonly"
              :halign "start"
              :text worktree_form_branch_name))
          ;; Worktree path field (read-only per spec.md US5 scenario 6)
          (box
            :class "form-field readonly-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Path (read-only)")
            (label
              :class "field-readonly"
              :halign "start"
              :truncate true
              :text worktree_form_path))
          ;; Parent project field (read-only)
          (box
            :class "form-field readonly-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Parent Project (read-only)")
            (label
              :class "field-readonly"
              :halign "start"
              :text worktree_form_parent_project))
          ;; Error message display
          (revealer
            :reveal {edit_form_error != ""}
            :transition "slidedown"
            :duration "200ms"
            (label
              :class "error-message"
              :halign "start"
              :wrap true
              :text edit_form_error))
          ;; Action buttons
          (box
            :class "form-actions"
            :orientation "h"
            :space-evenly false
            :halign "end"
            (button
              :class "cancel-button"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update editing_project_name='''' && eww --config $HOME/.config/eww-monitoring-panel update edit_form_error=''''"
              "Cancel")
            (button
              :class "save-button"
              :onclick "worktree-edit-save ''${project.name}"
              "Save"))))

      ;; Feature 094 US5 T057-T058: Worktree create form widget
      ;; Shown when worktree_creating is true
      (defwidget worktree-create-form [parent_project]
        (box
          :class "edit-form worktree-create-form"
          :orientation "v"
          :space-evenly false
          ;; Form header
          (label
            :class "edit-form-header"
            :halign "start"
            :text "Create Worktree")
          ;; Parent project indicator
          (box
            :class "form-field readonly-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Parent Project")
            (label
              :class "field-readonly"
              :halign "start"
              :text parent_project))
          ;; Branch name field (required)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Branch Name *")
            (input
              :class "field-input"
              :value worktree_form_branch_name
              :onchange "eww update worktree_form_branch_name={}")
            (label
              :class "field-hint"
              :halign "start"
              :text "Use existing branch or create new"))
          ;; Worktree path field (required)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Worktree Path *")
            (input
              :class "field-input"
              :value worktree_form_path
              :onchange "eww update worktree_form_path={}"))
          ;; Display name field (optional)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Display Name")
            (input
              :class "field-input"
              :value edit_form_display_name
              :onchange "eww update edit_form_display_name={}"))
          ;; Icon field (optional)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Icon")
            (input
              :class "field-input"
              :value edit_form_icon
              :onchange "eww update edit_form_icon={}"))
          ;; Error message display
          (revealer
            :reveal {edit_form_error != ""}
            :transition "slidedown"
            :duration "200ms"
            (label
              :class "error-message"
              :halign "start"
              :wrap true
              :text edit_form_error))
          ;; Action buttons
          (box
            :class "form-actions"
            :orientation "h"
            :space-evenly false
            :halign "end"
            (button
              :class "cancel-button"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update worktree_creating=false && eww --config $HOME/.config/eww-monitoring-panel update worktree_form_branch_name='''' && eww --config $HOME/.config/eww-monitoring-panel update worktree_form_path='''' && eww --config $HOME/.config/eww-monitoring-panel update worktree_form_parent_project='''' && eww --config $HOME/.config/eww-monitoring-panel update edit_form_error=''''"
              "Cancel")
            (button
              :class "save-button"
              :onclick "worktree-create"
              "Create"))))

      ;; Feature 094 US3: Project create form widget (T067)
      (defwidget project-create-form []
        (box
          :class "edit-form project-create-form"
          :orientation "v"
          :space-evenly false
          ;; Form header
          (label
            :class "edit-form-header"
            :halign "start"
            :text "Create New Project")
          ;; Name field (required) - must be unique, lowercase with hyphens only
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Project Name *")
            (input
              :class "field-input"
              :value create_form_name
              :onchange "eww update create_form_name={}")
            (label
              :class "field-hint"
              :halign "start"
              :text "Lowercase, hyphens only (e.g., my-project)"))
          ;; Display name field (optional)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Display Name")
            (input
              :class "field-input"
              :value create_form_display_name
              :onchange "eww update create_form_display_name={}"))
          ;; Icon field (optional)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Icon")
            (input
              :class "field-input icon-input"
              :value create_form_icon
              :onchange "eww update create_form_icon={}"))
          ;; Working directory field (required)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Working Directory *")
            (input
              :class "field-input"
              :value create_form_working_dir
              :onchange "eww update create_form_working_dir={}")
            (label
              :class "field-hint"
              :halign "start"
              :text "Absolute path to project directory"))
          ;; Scope selector
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Scope")
            (box
              :class "scope-buttons"
              :orientation "h"
              :space-evenly false
              (button
                :class "scope-btn ''${create_form_scope == 'scoped' ? 'active' : '''}"
                :onclick "eww update create_form_scope='scoped'"
                "Scoped")
              (button
                :class "scope-btn ''${create_form_scope == 'global' ? 'active' : '''}"
                :onclick "eww update create_form_scope='global'"
                "Global")))
          ;; Remote project toggle
          (box
            :class "form-field remote-toggle"
            :orientation "h"
            :space-evenly false
            (checkbox
              :checked create_form_remote_enabled
              :onchange "eww update create_form_remote_enabled={}")
            (label
              :class "field-label"
              :halign "start"
              :text "Remote Project (SSH)"))
          ;; Remote fields (shown only when remote is enabled)
          (revealer
            :reveal create_form_remote_enabled
            :transition "slidedown"
            :duration "200ms"
            (box
              :class "remote-fields"
              :orientation "v"
              :space-evenly false
              ;; Remote host
              (box
                :class "form-field"
                :orientation "v"
                :space-evenly false
                (label
                  :class "field-label"
                  :halign "start"
                  :text "SSH Host *")
                (input
                  :class "field-input"
                  :value create_form_remote_host
                  :onchange "eww update create_form_remote_host={}")
                (label
                  :class "field-hint"
                  :halign "start"
                  :text "e.g., hetzner-sway.tailnet"))
              ;; Remote user
              (box
                :class "form-field"
                :orientation "v"
                :space-evenly false
                (label
                  :class "field-label"
                  :halign "start"
                  :text "SSH User *")
                (input
                  :class "field-input"
                  :value create_form_remote_user
                  :onchange "eww update create_form_remote_user={}"))
              ;; Remote directory
              (box
                :class "form-field"
                :orientation "v"
                :space-evenly false
                (label
                  :class "field-label"
                  :halign "start"
                  :text "Remote Directory *")
                (input
                  :class "field-input"
                  :value create_form_remote_dir
                  :onchange "eww update create_form_remote_dir={}")
                (label
                  :class "field-hint"
                  :halign "start"
                  :text "Absolute path on remote (e.g., /home/user/project)"))
              ;; Remote port
              (box
                :class "form-field"
                :orientation "v"
                :space-evenly false
                (label
                  :class "field-label"
                  :halign "start"
                  :text "SSH Port")
                (input
                  :class "field-input port-input"
                  :value create_form_remote_port
                  :onchange "eww update create_form_remote_port={}"))))
          ;; Error message display
          (revealer
            :reveal {create_form_error != ""}
            :transition "slidedown"
            :duration "200ms"
            (label
              :class "error-message"
              :halign "start"
              :wrap true
              :text create_form_error))
          ;; Action buttons
          (box
            :class "form-actions"
            :orientation "h"
            :space-evenly false
            :halign "end"
            (button
              :class "cancel-button"
              :onclick "project-create-cancel"
              "Cancel")
            (button
              :class "save-button"
              :onclick "project-create-save"
              "Create"))))

      ;; Feature 094 US4: Project delete confirmation dialog (T088-T089)
      (defwidget project-delete-confirmation []
        (revealer
          :reveal project_deleting
          :transition "slidedown"
          :duration "200ms"
          (box
            :class "delete-confirmation-dialog"
            :orientation "v"
            :space-evenly false
            ;; Dialog header
            (box
              :class "dialog-header"
              :orientation "h"
              :space-evenly false
              (label
                :class "dialog-icon warning"
                :text "⚠️")
              (label
                :class "dialog-title"
                :halign "start"
                :text "Delete Project"))
            ;; Project name display
            (label
              :class "project-name-display"
              :halign "start"
              :text "''${delete_project_display_name}")
            ;; Warning message
            (label
              :class "warning-message"
              :halign "start"
              :wrap true
              :text "This action is permanent. The project configuration file will be moved to a .deleted backup.")
            ;; Worktree warning (shown only if project has worktrees)
            (revealer
              :reveal delete_project_has_worktrees
              :transition "slidedown"
              :duration "150ms"
              (box
                :class "worktree-warning"
                :orientation "v"
                :space-evenly false
                (label
                  :class "warning-icon"
                  :halign "start"
                  :text "⚠ This project has worktrees")
                (label
                  :class "warning-detail"
                  :halign "start"
                  :wrap true
                  :text "Worktrees will become orphaned if you force delete. Consider deleting worktrees first.")
                ;; Force delete checkbox
                (box
                  :class "force-delete-option"
                  :orientation "h"
                  :space-evenly false
                  (checkbox
                    :class "force-delete-checkbox"
                    :checked delete_force
                    :onchange "eww update delete_force={}")
                  (label
                    :class "force-delete-label"
                    :halign "start"
                    :text "Force delete (orphan worktrees)"))))
            ;; Error message display
            (revealer
              :reveal {delete_error != ""}
              :transition "slidedown"
              :duration "150ms"
              (label
                :class "error-message"
                :halign "start"
                :wrap true
                :text delete_error))
            ;; Action buttons
            (box
              :class "dialog-actions"
              :orientation "h"
              :space-evenly false
              :halign "end"
              (button
                :class "cancel-delete-button"
                :onclick "project-delete-cancel"
                "Cancel")
              (button
                :class "confirm-delete-button ''${delete_project_has_worktrees && !delete_force ? 'disabled' : '''}"
                :onclick {delete_project_has_worktrees && !delete_force ? "" : "project-delete-confirm"}
                :tooltip "''${delete_project_has_worktrees && !delete_force ? 'Check force delete to proceed' : 'Permanently delete project'}"
                "🗑 Delete")))))

      ;; Feature 094 US9: Application delete confirmation dialog (T093-T096)
      (defwidget app-delete-confirmation []
        (revealer
          :reveal app_deleting
          :transition "slidedown"
          :duration "200ms"
          (box
            :class "app-delete-confirmation-dialog"
            :orientation "v"
            :space-evenly false
            ;; Dialog header
            (box
              :class "dialog-header"
              :orientation "h"
              :space-evenly false
              (label
                :class "dialog-icon warning"
                :text "⚠️")
              (label
                :class "dialog-title"
                :halign "start"
                :text "Delete Application"))
            ;; Application name display
            (label
              :class "app-name-display"
              :halign "start"
              :text "''${delete_app_display_name}")
            ;; Warning message
            (label
              :class "warning-message"
              :halign "start"
              :wrap true
              :text "This action is permanent. The application will be removed from the registry. A NixOS rebuild is required to apply changes.")
            ;; PWA warning (shown only if deleting a PWA)
            (revealer
              :reveal delete_app_is_pwa
              :transition "slidedown"
              :duration "150ms"
              (box
                :class "pwa-warning"
                :orientation "v"
                :space-evenly false
                (label
                  :class "warning-icon"
                  :halign "start"
                  :text "⚠ This is a PWA (Progressive Web App)")
                (label
                  :class "warning-detail"
                  :halign "start"
                  :wrap true
                  :text "After removing from registry, run pwa-uninstall to fully remove the PWA from Firefox.")))
            ;; Error message display
            (revealer
              :reveal {delete_app_error != ""}
              :transition "slidedown"
              :duration "150ms"
              (label
                :class "error-message"
                :halign "start"
                :wrap true
                :text delete_app_error))
            ;; Action buttons
            (box
              :class "dialog-actions"
              :orientation "h"
              :space-evenly false
              :halign "end"
              (button
                :class "cancel-delete-app-button"
                :onclick "app-delete-cancel"
                "Cancel")
              (button
                :class "confirm-delete-app-button"
                :onclick "app-delete-confirm"
                :tooltip "Permanently remove application from registry"
                "🗑 Delete")))))

      ;; Feature 094 US8: Application create form widget (T077-T080)
      (defwidget app-create-form []
        (box
          :class "edit-form app-create-form"
          :orientation "v"
          :space-evenly false
          ;; Form header
          (label
            :class "edit-form-header"
            :halign "start"
            :text "Create New Application")
          ;; App type selector (T077)
          (box
            :class "form-field app-type-selector"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Application Type *")
            (box
              :class "type-buttons"
              :orientation "h"
              :space-evenly false
              (button
                :class "type-btn type-option ''${create_app_type == 'regular' ? 'active' : '''}"
                :onclick "eww update create_app_type='regular' && eww update create_app_workspace='1'"
                "󰀻 Regular App")
              (button
                :class "type-btn type-option ''${create_app_type == 'terminal' ? 'active' : '''}"
                :onclick "eww update create_app_type='terminal' && eww update create_app_command='ghostty' && eww update create_app_expected_class='ghostty'"
                "🖥️ Terminal")
              (button
                :class "type-btn type-option ''${create_app_type == 'pwa' ? 'active' : '''}"
                :onclick "eww update create_app_type='pwa' && eww update create_app_workspace='50'"
                "🌐 PWA")))
          ;; Name field (required)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Application Name *")
            (input
              :class "field-input"
              :value create_app_name
              :onchange "eww update create_app_name={}")
            (label
              :class "field-hint"
              :halign "start"
              :text "''${create_app_type == 'pwa' ? 'Name will get -pwa suffix automatically' : 'Lowercase, hyphens only (e.g., my-app)'}"))
          ;; Display name field
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Display Name *")
            (input
              :class "field-input"
              :value create_app_display_name
              :onchange "eww update create_app_display_name={}"))
          ;; Command field (not shown for PWA - auto-set to firefoxpwa)
          (revealer
            :reveal {create_app_type != "pwa"}
            :transition "slidedown"
            :duration "150ms"
            (box
              :class "form-field"
              :orientation "v"
              :space-evenly false
              (label
                :class "field-label"
                :halign "start"
                :text "Command *")
              ;; Regular apps: free text input
              (box
                :visible {create_app_type == "regular"}
                (input
                  :class "field-input"
                  :value create_app_command
                  :onchange "eww update create_app_command={}"))
              ;; Terminal apps: dropdown of terminal emulators
              (box
                :visible {create_app_type == "terminal"}
                :class "terminal-command-select"
                :orientation "h"
                :space-evenly false
                (button
                  :class "term-btn ''${create_app_command == 'ghostty' ? 'active' : '''}"
                  :onclick "eww update create_app_command='ghostty' && eww update create_app_expected_class='ghostty'"
                  "Ghostty")
                (button
                  :class "term-btn ''${create_app_command == 'alacritty' ? 'active' : '''}"
                  :onclick "eww update create_app_command='alacritty' && eww update create_app_expected_class='Alacritty'"
                  "Alacritty")
                (button
                  :class "term-btn ''${create_app_command == 'kitty' ? 'active' : '''}"
                  :onclick "eww update create_app_command='kitty' && eww update create_app_expected_class='kitty'"
                  "Kitty")
                (button
                  :class "term-btn ''${create_app_command == 'wezterm' ? 'active' : '''}"
                  :onclick "eww update create_app_command='wezterm' && eww update create_app_expected_class='org.wezfurlong.wezterm'"
                  "WezTerm"))))
          ;; Parameters field (not shown for PWA)
          (revealer
            :reveal {create_app_type != "pwa"}
            :transition "slidedown"
            :duration "150ms"
            (box
              :class "form-field terminal-parameters"
              :orientation "v"
              :space-evenly false
              (label
                :class "field-label"
                :halign "start"
                :text "Parameters")
              (input
                :class "field-input"
                :value create_app_parameters
                :onchange "eww update create_app_parameters={}")
              (label
                :class "field-hint"
                :halign "start"
                :text "''${create_app_type == 'terminal' ? 'e.g., -e sesh connect $PROJECT_NAME' : 'Space-separated arguments'}")))
          ;; Expected class field (not shown for PWA - auto-generated with ULID)
          (revealer
            :reveal {create_app_type != "pwa"}
            :transition "slidedown"
            :duration "150ms"
            (box
              :class "form-field"
              :orientation "v"
              :space-evenly false
              (label
                :class "field-label"
                :halign "start"
                :text "Expected Window Class *")
              (input
                :class "field-input"
                :value create_app_expected_class
                :onchange "eww update create_app_expected_class={}")
              (label
                :class "field-hint"
                :halign "start"
                :text "Use 'swaymsg -t get_tree' to find window class")))
          ;; PWA-specific fields (T079)
          (revealer
            :reveal {create_app_type == "pwa"}
            :transition "slidedown"
            :duration "150ms"
            (box
              :class "pwa-fields"
              :orientation "v"
              :space-evenly false
              ;; Start URL
              (box
                :class "form-field"
                :orientation "v"
                :space-evenly false
                (label
                  :class "field-label"
                  :halign "start"
                  :text "Start URL *")
                (input
                  :class "field-input"
                  :value create_app_start_url
                  :onchange "eww update create_app_start_url={}")
                (label
                  :class "field-hint"
                  :halign "start"
                  :text "e.g., https://youtube.com"))
              ;; Scope URL
              (box
                :class "form-field"
                :orientation "v"
                :space-evenly false
                (label
                  :class "field-label"
                  :halign "start"
                  :text "Scope URL *")
                (input
                  :class "field-input"
                  :value create_app_scope_url
                  :onchange "eww update create_app_scope_url={}")
                (label
                  :class "field-hint"
                  :halign "start"
                  :text "Usually start URL with trailing slash"))
              ;; ULID note (not editable - auto-generated)
              (label
                :class "pwa-workspace-note field-hint"
                :halign "start"
                :text "⚙️ ULID will be auto-generated on save")))
          ;; Workspace field
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Preferred Workspace *")
            (input
              :class "field-input workspace-input"
              :value create_app_workspace
              :onchange "eww update create_app_workspace={}")
            (label
              :class "field-hint ''${create_app_type == 'pwa' ? 'pwa-workspace-note' : '''}"
              :halign "start"
              :text "''${create_app_type == 'pwa' ? 'PWAs must use workspace 50+' : 'Regular apps use 1-50'}"))
          ;; Scope selector
          (revealer
            :reveal {create_app_type != "pwa"}
            :transition "slidedown"
            :duration "150ms"
            (box
              :class "form-field"
              :orientation "v"
              :space-evenly false
              (label
                :class "field-label"
                :halign "start"
                :text "Scope")
              (box
                :class "scope-buttons"
                :orientation "h"
                :space-evenly false
                (button
                  :class "scope-btn ''${create_app_scope == 'scoped' ? 'active' : '''}"
                  :onclick "eww update create_app_scope='scoped'"
                  "Scoped")
                (button
                  :class "scope-btn ''${create_app_scope == 'global' ? 'active' : '''}"
                  :onclick "eww update create_app_scope='global'"
                  "Global"))))
          ;; Icon field
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Icon")
            (input
              :class "field-input icon-input"
              :value create_app_icon
              :onchange "eww update create_app_icon={}")
            (label
              :class "field-hint"
              :halign "start"
              :text "Icon name, emoji, or path to SVG"))
          ;; Error message display
          (revealer
            :reveal {create_app_error != ""}
            :transition "slidedown"
            :duration "200ms"
            (label
              :class "error-message"
              :halign "start"
              :wrap true
              :text create_app_error))
          ;; Success message with ULID (shown after PWA creation)
          (revealer
            :reveal {create_app_ulid_result != ""}
            :transition "slidedown"
            :duration "200ms"
            (box
              :class "pwa-create-success"
              :orientation "v"
              :space-evenly false
              (label
                :class "success-message"
                :halign "start"
                :text "✓ PWA created successfully!")
              (box
                :class "ulid-display"
                :orientation "h"
                :space-evenly false
                (label
                  :class "ulid-label"
                  :text "ULID: ")
                (label
                  :class "ulid-value"
                  :text create_app_ulid_result))))
          ;; Action buttons
          (box
            :class "form-actions"
            :orientation "h"
            :space-evenly false
            :halign "end"
            (button
              :class "cancel-button"
              :onclick "app-create-cancel"
              "Cancel")
            (button
              :class "save-button"
              :onclick "app-create-save"
              "Create"))))

      ;; Feature 094 T040: Conflict resolution dialog widget
      ;; Overlay dialog shown when file conflicts are detected during save
      (defwidget conflict-resolution-dialog []
        (revealer
          :reveal conflict_dialog_visible
          :transition "slidedown"
          :duration "300ms"
          (box
            :class "conflict-dialog-overlay"
            :orientation "v"
            :space-evenly false
            (box
              :class "conflict-dialog"
              :orientation "v"
              :space-evenly false
              ;; Dialog header
              (box
                :class "conflict-header"
                :orientation "h"
                :space-evenly false
                (label
                  :class "conflict-title"
                  :halign "start"
                  :hexpand true
                  :text "⚠️  Conflict Detected")
                (button
                  :class "conflict-close-button"
                  :onclick "eww update conflict_dialog_visible=false"
                  "✕"))
              ;; Conflict explanation
              (label
                :class "conflict-message"
                :halign "start"
                :wrap true
                :text "The project configuration file was modified externally while you were editing. Choose how to resolve:")
              ;; Diff display (side-by-side comparison)
              (box
                :class "conflict-diff-container"
                :orientation "h"
                :space-evenly true
                ;; File content (left side)
                (box
                  :class "conflict-diff-pane"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "conflict-pane-header"
                    :text "📄 File on Disk")
                  (scroll
                    :vscroll true
                    :hscroll false
                    :height 200
                    (label
                      :class "conflict-content"
                      :halign "start"
                      :valign "start"
                      :wrap false
                      :text conflict_file_content)))
                ;; UI content (right side)
                (box
                  :class "conflict-diff-pane"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "conflict-pane-header"
                    :text "✏️  Your Unsaved Changes")
                  (scroll
                    :vscroll true
                    :hscroll false
                    :height 200
                    (label
                      :class "conflict-content"
                      :halign "start"
                      :valign "start"
                      :wrap false
                      :text conflict_ui_content))))
              ;; Action buttons
              (box
                :class "conflict-actions"
                :orientation "h"
                :space-evenly false
                :halign "center"
                (button
                  :class "conflict-button conflict-keep-file"
                  :onclick "project-conflict-resolve keep-file ''${conflict_project_name}"
                  "Keep File Changes")
                (button
                  :class "conflict-button conflict-keep-ui"
                  :onclick "project-conflict-resolve keep-ui ''${conflict_project_name}"
                  "Keep My Changes")
                (button
                  :class "conflict-button conflict-merge"
                  :onclick "project-conflict-resolve merge-manual ''${conflict_project_name}"
                  "Merge Manually"))))))

      ;; Feature 094 Phase 12 T099: Success notification toast (auto-dismiss after 3s)
      (defwidget success-notification-toast []
        (revealer
          :reveal success_notification_visible
          :transition "slidedown"
          :duration "200ms"
          (box
            :class "success-notification-toast"
            :orientation "h"
            :space-evenly false
            :halign "center"
            (label
              :class "success-icon"
              :text "[OK]")
            (label
              :class "success-message"
              :text success_notification)
            (button
              :class "success-dismiss"
              :onclick "eww update success_notification_visible=false success_notification=\"\""
              "x"))))

      ;; Apps View - Application registry browser
      ;; Applications View - App registry with type grouping (Feature 094)
      (defwidget apps-view []
        (scroll
          :vscroll true
          :hscroll false
          :vexpand true
          (box
            :class "content-container"
            :orientation "v"
            :space-evenly false
            ;; Feature 094 US8: Apps tab header with New Application button (T076)
            (box
              :class "apps-header"
              :orientation "h"
              :space-evenly false
              :visible {!app_creating}
              (label
                :class "apps-header-title"
                :halign "start"
                :hexpand true
                :text "Applications")
              (button
                :class "new-app-button"
                :onclick "app-create-open"
                :tooltip "Create a new application"
                "+ New Application"))
            ;; Feature 094 US8: Application create form (T077-T080)
            (revealer
              :transition "slidedown"
              :reveal app_creating
              :duration "200ms"
              (app-create-form))
            ;; Feature 094 US9: Application delete confirmation dialog (T093)
            (app-delete-confirmation)
            ;; Regular Apps Section
            (box
              :class "app-section"
              :orientation "v"
              :space-evenly false
              (label
                :class "section-header"
                :halign "start"
                :text "Regular Applications")
              (for app in {apps_data.apps ?: []}
                (box
                  :visible {!app.terminal && app.preferred_workspace <= 50 && !matches(app.name, ".*-pwa$")}
                  (app-card :app app))))
            ;; Terminal Apps Section
            (box
              :class "app-section"
              :orientation "v"
              :space-evenly false
              (label
                :class "section-header"
                :halign "start"
                :text "Terminal Applications")
              (for app in {apps_data.apps ?: []}
                (box
                  :visible {app.terminal}
                  (app-card :app app))))
            ;; PWA Apps Section
            (box
              :class "app-section"
              :orientation "v"
              :space-evenly false
              (label
                :class "section-header"
                :halign "start"
                :text "Progressive Web Apps")
              (for app in {apps_data.apps ?: []}
                (box
                  :visible {app.preferred_workspace >= 50 || matches(app.name, ".*-pwa$")}
                  (app-card :app app)))))))

      (defwidget app-card [app]
        (eventbox
          :onhover "eww update hover_app_name=''${app.name}"
          :onhoverlost "eww update hover_app_name='''"
          (box
            :class "app-card"
            :orientation "v"
            :space-evenly false
            (box
              :class "app-card-header"
              :orientation "h"
              :space-evenly false
              ;; Type icon
              (box
                :class "app-icon-container"
                :orientation "v"
                :valign "center"
                (label
                  :class "app-type-icon"
                  :text "''${app.terminal ? '🖥️' : app.preferred_workspace >= 50 ? '🌐' : '󰀻'}"))
              ;; App info
              (box
                :class "app-info"
                :orientation "v"
                :space-evenly false
                :hexpand true
                (box
                  :class "app-name-row"
                  :orientation "h"
                  :space-evenly false
                  (label
                    :class "app-card-name"
                    :halign "start"
                    :text "''${app.display_name ?: app.name}")
                  ;; Terminal indicator
                  (label
                    :class "terminal-indicator"
                    :visible {app.terminal}
                    :text ""))
                (label
                  :class "app-card-command"
                  :halign "start"
                  :text "''${app.command}"))
              ;; Running indicator
              (box
                :class "app-status-container"
                :orientation "v"
                :valign "center"
                (label
                  :class "app-running-indicator"
                  :visible {(app.running_instances ?: 0) > 0}
                  :text "●")))
            ;; Details row
            (box
              :class "app-card-details-row"
              :orientation "h"
              :space-evenly false
              (label
                :class "app-card-details"
                :halign "start"
                :hexpand true
                :text "WS ''${app.preferred_workspace ?: '?'} · ''${app.scope} · ''${app.running_instances ?: 0} running")
              (button
                :class "app-edit-button"
                :onclick "eww update editing_app_name=''${app.name}"
                "")
              (button
                :class "delete-app-button"
                :visible {editing_app_name != app.name && !app_deleting}
                :onclick "app-delete-open ''${app.name} ''${app.display_name} ''${app.ulid}"
                :tooltip "Delete application"
                "🗑")))))

      ;; Health View - System diagnostics (Feature 088)
      (defwidget health-view []
        (scroll
          :vscroll true
          :hscroll false
          :vexpand true
          (box
            :class "content-container"
            :orientation "v"
            :space-evenly false
            ;; Error state
            (box
              :class "error-message"
              :visible {health_data.status == "error"}
              (label :text "⚠ ''${health_data.error ?: 'Unknown error'}"))
            ;; System health summary
            (box
              :class "health-summary"
              :orientation "v"
              :space-evenly false
              :visible {health_data.status == "ok"}
              (label
                :class "health-summary-title"
                :text "System Health: ''${health_data.health.system_health ?: 'unknown'}")
              (label
                :class "health-summary-counts"
                :text "''${health_data.health.healthy_count ?: 0}/''${health_data.health.total_services ?: 0} services healthy"))
            ;; Service categories
            (box
              :class "health-categories"
              :orientation "v"
              :space-evenly false
              :visible {health_data.status == "ok"}
              (for category in {health_data.health.categories ?: []}
                (service-category
                  :category category))))))

      ;; Service category widget (Feature 088)
      (defwidget service-category [category]
        (box
          :class "service-category"
          :orientation "v"
          :space-evenly false
          ;; Category header
          (box
            :class "category-header"
            :orientation "h"
            :space-evenly false
            (label
              :class "category-title"
              :halign "start"
              :hexpand true
              :text "''${category.display_name ?: 'Services'}")
            (label
              :class "category-counts"
              :halign "end"
              :text "''${category.healthy_count ?: 0}/''${category.total_count ?: 0}"))
          ;; Service health cards
          (box
            :class "service-list"
            :orientation "v"
            :space-evenly false
            (for service in {category.services ?: []}
              (service-health-card
                :service service)))))

      ;; Service health card widget (Feature 088 US2)
      (defwidget service-health-card [service]
        (box
          :class "service-health-card health-''${service.health_state ?: 'unknown'}"
          :orientation "h"
          :space-evenly false
          ;; Status icon
          (label
            :class "service-icon"
            :text "''${service.status_icon ?: '?'}")
          ;; Service info
          (box
            :class "service-info"
            :orientation "v"
            :hexpand true
            (label
              :class "service-name"
              :halign "start"
              :text "''${service.display_name ?: 'Unknown Service'}")
            (label
              :class "service-status"
              :halign "start"
              :text "''${service.active_state ?: 'unknown'}")
            ;; T022: Display uptime for active services
            (label
              :class "service-uptime"
              :halign "start"
              :visible {service.health_state == "healthy" || service.health_state == "degraded"}
              :text "Uptime: ''${service.uptime_friendly ?: 'N/A'}")
            ;; Display memory usage for active services
            (label
              :class "service-memory"
              :halign "start"
              :visible {service.memory_usage_mb > 0}
              :text "Memory: ''${service.memory_usage_mb} MB")
            ;; T023: Display last active time for failed/stopped services
            (label
              :class "service-last-active"
              :halign "start"
              :visible {service.health_state == "critical" || service.health_state == "disabled"}
              :text "Last active: ''${service.last_active_time ?: 'Never'}"))
          ;; Health state indicator with restart count and restart button
          (box
            :class "health-indicator-box"
            :orientation "v"
            :halign "end"
            :space-evenly false
            (label
              :class "health-indicator"
              :text "''${service.health_state ?: 'unknown'}")
            ;; T033: Show restart count if > 0 with tooltip
            (label
              :class "restart-count''${service.restart_count >= 3 ? ' restart-warning' : ' '}"
              :visible {service.restart_count > 0}
              :tooltip "Service has restarted ''${service.restart_count} time(s)"
              :text "↻ ''${service.restart_count}")
            ;; T028-T030: Restart button (only shown when service can be restarted)
            (button
              :class "restart-button"
              :visible {service.can_restart ?: false}
              :onclick "restart-service ''${service.service_name} ''${service.is_user_service ? 'true' : 'false'} &"
              :tooltip "Restart ''${service.display_name}"
              "⟳"))))

      ;; Feature 092: Events/Logs View - Real-time Sway IPC event log (T024)
      (defwidget events-view []
        (box
          :class "events-view-container"
          :orientation "v"
          :vexpand true
          ;; Error state
          (box
            :visible {events_data.status == "error"}
            :class "error-state"
            :orientation "v"
            :valign "center"
            :halign "center"
            :vexpand true
            (label
              :class "error-message"
              :text "󰀦 Error: ''${events_data.error ?: 'Unknown error'}")
            (label
              :class "error-help"
              :text "Check i3pm daemon and Sway IPC connection"))
          ;; Empty state (no events yet)
          (box
            :visible {events_data.status == "ok" && events_data.event_count == 0}
            :class "empty-state"
            :orientation "v"
            :valign "center"
            :halign "center"
            :vexpand true
            (label
              :class "empty-message"
              :text "󰌱 No events yet")
            (label
              :class "empty-help"
              :text "Waiting for Sway window/workspace events..."))
          ;; Events list (scroll container)
          (scroll
            :vscroll true
            :hscroll false
            :vexpand true
            :visible {events_data.status == "ok" && events_data.event_count > 0}
            (box
              :class "events-list"
              :orientation "v"
              :space-evenly false
              ;; Iterate through events (newest last for auto-scroll)
              (for event in {events_data.events ?: []}
                (event-card :event event))))))

      ;; Feature 092: Event card widget - Single event display (T025)
      (defwidget event-card [event]
        (box
          :class "event-card event-category-''${event.category}"
          :orientation "h"
          :space-evenly false
          ;; Event icon with category color
          (label
            :class "event-icon"
            :style "color: ''${event.color};"
            :text "''${event.icon}")
          ;; Event details
          (box
            :class "event-details"
            :orientation "v"
            :space-evenly false
            :hexpand true
            ;; Event type and timestamp
            (box
              :class "event-header"
              :orientation "h"
              :space-evenly false
              (label
                :class "event-type"
                :halign "start"
                :hexpand true
                :text "''${event.event_type}")
              (label
                :class "event-timestamp"
                :halign "end"
                :text "''${event.timestamp_friendly}"))
            ;; Event payload info (window/workspace details)
            (label
              :class "event-payload"
              :halign "start"
              :limit-width 60
              :text "''${event.searchable_text}"))))

      ;; Panel footer with friendly timestamp
      (defwidget panel-footer []
        (box
          :class "panel-footer"
          :orientation "h"
          :halign "center"
          (label
            :class "timestamp"
            :text "''${monitoring_data.timestamp_friendly ?: 'Initializing...'}")))
    '';

    # Eww SCSS styling (T015)
    xdg.configFile."eww-monitoring-panel/eww.scss".text = ''
      /* Feature 085: Sway Monitoring Widget - Catppuccin Mocha Theme */
      /* Direct color interpolation from Nix - Eww doesn't support CSS variables */

      /* Window base - must be transparent for see-through effect on Wayland */
      * {
        /* Removed 'all: unset' as it was resetting colors to black/white */
        /* Only reset margins and padding */
        margin: 0;
        padding: 0;
        /* Force Catppuccin text color on all elements */
        color: ${mocha.text};
      }

      window {
        background-color: transparent;
      }

      /* Explicit GTK widget styling to override theme */
      label, box, button {
        color: ${mocha.text};
        background-color: transparent;
      }

      /* Panel Container - Sidebar Style with rounded corners and transparency */
      .panel-container {
        background-color: ${mocha.base};
        border-radius: 12px;
        padding: 8px;
        margin: 8px;
        border: 2px solid rgba(137, 180, 250, 0.2);
        /* transition not supported in GTK CSS */
      }

      /* Feature 086: Focused state with glowing border effect */
      .panel-container.focused {
        border: 2px solid ${mocha.mauve};
        box-shadow: 0 0 20px rgba(203, 166, 247, 0.4),
                    0 0 40px rgba(203, 166, 247, 0.2),
                    inset 0 0 15px rgba(203, 166, 247, 0.05);
        background-color: rgba(30, 30, 46, 0.70);
      }

      /* Focus mode indicator badge */
      .focus-indicator {
        font-size: 10px;
        font-weight: bold;
        color: ${mocha.base};
        background-image: linear-gradient(135deg, ${mocha.mauve}, ${mocha.blue});
        padding: 2px 8px;
        border-radius: 4px;
        margin-left: 8px;
      }
      .panel-header {
        background-color: rgba(24, 24, 37, 0.4);
        border-bottom: 1px solid ${mocha.overlay0};
        border-radius: 8px;
        padding: 8px 12px;
        margin-bottom: 8px;
      }

      .panel-title {
        font-size: 14px;
        font-weight: bold;
        color: ${mocha.text};
        margin-bottom: 4px;
      }

      .summary-counts {
        font-size: 11px;
        color: ${mocha.subtext0};
      }

      .count-badge {
        font-size: 10px;
        color: ${mocha.teal};
        background-color: rgba(148, 226, 213, 0.15);
        padding: 2px 6px;
        border-radius: 3px;
      }

      /* Tab Navigation */
      .tabs {
        margin-bottom: 8px;
      }

      .tab {
        font-size: 16px;
        padding: 8px 16px;
        min-width: 60px;
        background-color: rgba(49, 50, 68, 0.4);
        color: ${mocha.subtext0};
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
        /* transition not supported in GTK CSS */
      }

      .tab label {
        color: ${mocha.subtext0};
      }

      .tab:hover {
        background-color: rgba(69, 71, 90, 0.5);
        color: ${mocha.text};
        border-color: ${mocha.overlay0};
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
      }

      .tab:hover label {
        color: ${mocha.text};
      }

      .tab.active {
        background-color: rgba(137, 180, 250, 0.6);
        color: ${mocha.base};
        border-color: ${mocha.blue};
        font-weight: bold;
        box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
      }

      .tab.active label {
        color: ${mocha.base};
      }

      .tab.active:hover {
        background-color: rgba(137, 180, 250, 0.7);
        box-shadow: 0 0 12px rgba(137, 180, 250, 0.6);
      }

      .tab.active:hover label {
        color: ${mocha.base};
      }

      /* Panel Body - Compact */
      .panel-body {
        background-color: rgba(30, 30, 46, 0.3);
        padding: 4px;
        min-height: 0;  /* Enable proper flex shrinking for scrolling */
      }

      .content-container {
        padding: 0;
      }

      /* Project Widget */
      .project {
        margin-bottom: 12px;
        padding: 8px;
        background-color: rgba(49, 50, 68, 0.4);
        border-radius: 8px;
        border: 1px solid ${mocha.overlay0};
      }

      .scoped-project {
        border-left: 3px solid ${mocha.teal};
      }

      .global-project {
        border-left: 3px solid ${mocha.mauve};
      }

      .project-header {
        padding: 6px 8px;
        border-bottom: 1px solid ${mocha.overlay0};
        margin-bottom: 6px;
      }

      .project-name {
        font-size: 13px;
        font-weight: bold;
        color: ${mocha.text};
      }

      .window-count-badge {
        font-size: 10px;
        color: ${mocha.teal};
        background-color: rgba(148, 226, 213, 0.2);
        padding: 1px 5px;
        border-radius: 3px;
        min-width: 18px;
      }

      /* Windows Container */
      .windows-container {
        margin-left: 8px;
        margin-top: 2px;
      }

      .window {
        padding: 4px 8px;
        margin-bottom: 1px;
        border-radius: 2px;
        background-color: transparent;
        border-left: 2px solid transparent;
      }

      .window-focused {
        background-color: rgba(137, 180, 250, 0.1);
        border-left-color: ${mocha.blue};
      }

      .window-floating {
        border-right: 2px solid ${mocha.yellow};
      }

      .window-hidden {
        opacity: 0.5;
        font-style: italic;
      }

      /* Project Scope - Subtle border */
      .scoped-window {
        border-left-color: ${mocha.teal};
      }

      .global-window {
        border-left-color: ${mocha.overlay0};
      }

      /* Feature 093: Hover state for clickable window rows (T029) */
      .window:hover {
        background-color: rgba(137, 180, 250, 0.15);
        border-left-width: 3px;
      }

      /* Feature 093: Clicked state (2s highlight after successful focus) (T030) */
      .window.clicked {
        background-color: rgba(137, 180, 250, 0.25);
        border-left-color: ${mocha.blue};
        border-left-width: 4px;
      }

      .window-icon-container {
        min-width: 24px;
        min-height: 24px;
        margin-right: 6px;
      }

      .window-icon-image {
        min-width: 20px;
        min-height: 20px;
      }

      .window-icon-fallback {
        font-size: 14px;
        color: ${mocha.subtext0};
        min-width: 20px;
      }

      .window-app-name {
        font-size: 11px;
        font-weight: 500;
        color: ${mocha.text};
        margin-left: 6px;
      }

      /* Compact badges for states */
      .window-badges {
        margin-left: 4px;
      }

      .badge {
        font-size: 9px;
        font-weight: 600;
        padding: 1px 4px;
        border-radius: 2px;
        margin-left: 4px;
      }

      .badge-pwa {
        color: ${mocha.mauve};
        background-color: rgba(203, 166, 247, 0.2);
      }

      .badge-project {
        color: ${mocha.teal};
        background-color: rgba(148, 226, 213, 0.15);
      }

      .badge-workspace {
        color: ${mocha.blue};
        background-color: rgba(137, 180, 250, 0.15);
      }

      /* JSON Hover Tooltip */
      .window-json-tooltip {
        background-color: rgba(24, 24, 37, 0.98);
        border: 2px solid ${mocha.blue};
        border-radius: 8px;
        padding: 0;
        margin: 4px 0 8px 0;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6),
                    0 0 0 1px rgba(137, 180, 250, 0.3);
      }

      .json-tooltip-header {
        background-color: rgba(137, 180, 250, 0.15);
        border-bottom: 1px solid ${mocha.blue};
        padding: 8px 12px;
        border-radius: 6px 6px 0 0;
      }

      .json-tooltip-title {
        font-size: 11px;
        font-weight: bold;
        color: ${mocha.blue};
      }

      .json-copy-btn {
        font-size: 14px;
        padding: 4px 8px;
        background-color: rgba(137, 180, 250, 0.2);
        color: ${mocha.blue};
        border: 1px solid ${mocha.blue};
        border-radius: 4px;
        min-width: 32px;
      }

      .json-copy-btn:hover {
        background-color: rgba(137, 180, 250, 0.3);
        box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
      }

      .json-copy-btn:active {
        background-color: rgba(137, 180, 250, 0.5);
        box-shadow: 0 0 12px rgba(137, 180, 250, 0.6);
      }

      /* Success state when JSON is copied */
      .json-copy-btn.copied {
        background-color: rgba(166, 227, 161, 0.3);  /* Green with transparency */
        color: ${mocha.green};  /* #a6e3a1 */
        border: 1px solid ${mocha.green};
        box-shadow: 0 0 12px rgba(166, 227, 161, 0.5),
                    inset 0 0 8px rgba(166, 227, 161, 0.2);
        font-weight: bold;
      }

      .json-copy-btn.copied:hover {
        background-color: rgba(166, 227, 161, 0.4);
        box-shadow: 0 0 16px rgba(166, 227, 161, 0.6);
      }

      .json-content {
        font-family: "JetBrains Mono", "Fira Code", "Source Code Pro", monospace;
        font-size: 10px;
        padding: 10px 12px;
        background-color: rgba(30, 30, 46, 0.4);
      }

      /* Error State (T042) */
      .error-state {
        padding: 32px;
      }

      .error-icon {
        font-size: 48px;
        color: ${mocha.red};
        margin-bottom: 16px;
      }

      .error-message {
        font-size: 14px;
        color: ${mocha.text};
      }

      /* Empty State (T041) */
      .empty-state {
        padding: 32px;
      }

      .empty-icon {
        font-size: 48px;
        color: ${mocha.subtext0};
        margin-bottom: 16px;
      }

      .empty-title {
        font-size: 16px;
        font-weight: bold;
        color: ${mocha.text};
        margin-bottom: 8px;
      }

      .empty-message {
        font-size: 14px;
        color: ${mocha.subtext0};
      }

      /* Feature 094 Phase 12 T102: Empty state action button */
      .empty-action-button {
        background-color: ${mocha.blue};
        color: ${mocha.mantle};
        border: none;
        border-radius: 6px;
        padding: 8px 16px;
        margin-top: 16px;
        font-size: 13px;
        font-weight: 500;
      }

      .empty-action-button:hover {
        background-color: ${mocha.sapphire};
      }

      /* Compact Panel Footer */
      .panel-footer {
        background-color: rgba(24, 24, 37, 0.4);
        border-top: 1px solid ${mocha.overlay0};
        border-radius: 8px;
        padding: 6px 8px;
        margin-top: 8px;
      }

      .timestamp {
        font-size: 10px;
        color: ${mocha.subtext0};
        font-style: italic;
      }

      /* Compact Scrollbar */
      scrollbar {
        background-color: transparent;
        border-radius: 4px;
      }

      scrollbar slider {
        background-color: ${mocha.overlay0};
        border-radius: 4px;
        min-width: 6px;
      }

      scrollbar slider:hover {
        background-color: ${mocha.surface1};
      }

      /* Project Card Styles */
      .project-card {
        background-color: rgba(49, 50, 68, 0.4);
        border: 1px solid ${mocha.overlay0};
        border-radius: 8px;
        padding: 12px;
        margin-bottom: 8px;
      }

      .project-card.active-project {
        border-color: ${mocha.teal};
        background-color: rgba(148, 226, 213, 0.1);
      }

      .project-card-header {
        margin-bottom: 4px;
      }

      .project-icon {
        font-size: 16px;
        margin-right: 8px;
      }

      .project-info {
        margin-right: 8px;
        min-width: 0;
      }

      .project-card-name {
        font-size: 12px;
        font-weight: bold;
        color: ${mocha.text};
        margin-bottom: 2px;
      }

      .project-card-path {
        font-size: 9px;
        color: ${mocha.subtext0};
      }

      .active-indicator {
        color: ${mocha.teal};
        font-size: 12px;
      }

      .remote-indicator {
        color: ${mocha.peach};
        font-size: 10px;
        margin-left: 6px;
      }

      .project-name-row {
        margin-bottom: 2px;
      }

      .project-detail-tooltip {
        background-color: rgba(24, 24, 37, 0.95);
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
        padding: 10px;
        margin-top: 8px;
      }

      .json-detail {
        font-family: "JetBrainsMono Nerd Font", monospace;
        font-size: 9px;
        color: ${mocha.text};
      }

      /* Worktree Card Styles */
      .worktree-card {
        background-color: rgba(49, 50, 68, 0.3);
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
        padding: 10px;
        margin-left: 20px;
        margin-bottom: 6px;
        margin-top: 4px;
      }

      .worktree-tree {
        color: ${mocha.overlay0};
        font-size: 12px;
        margin-right: 4px;
        font-family: monospace;
      }

      .worktree-icon {
        font-size: 16px;
      }

      .worktree-name {
        font-size: 12px;
        color: ${mocha.subtext0};
      }

      /* Feature 094 US5: Branch indicator */
      .branch-indicator {
        font-size: 10px;
        color: ${mocha.teal};
        background-color: rgba(148, 226, 213, 0.15);
        padding: 2px 6px;
        border-radius: 4px;
        margin-left: 8px;
        font-family: monospace;
      }

      /* Feature 094 US5: Worktree action buttons (T057-T061) */
      .worktree-actions {
        /* GTK CSS doesn't support margin-left: auto; use box expand in yuck instead */
      }

      .worktree-action-btn {
        background-color: transparent;
        border: none;
        padding: 4px 8px;
        border-radius: 4px;
        font-size: 12px;
        min-width: 28px;
      }

      .worktree-action-btn.edit-btn {
        color: ${mocha.blue};
      }

      .worktree-action-btn.edit-btn:hover {
        background-color: rgba(137, 180, 250, 0.2);
      }

      .worktree-action-btn.delete-btn {
        color: ${mocha.red};
      }

      .worktree-action-btn.delete-btn:hover {
        background-color: rgba(243, 139, 168, 0.2);
      }

      .worktree-action-btn.delete-btn.confirm {
        background-color: rgba(243, 139, 168, 0.4);
        border: 2px solid ${mocha.red};
        /* GTK CSS doesn't support @keyframes, use static visual distinction */
        font-weight: bold;
      }

      /* Feature 094 US5: Worktree edit form styles */
      .worktree-edit-form {
        border-color: ${mocha.teal};
      }

      .worktree-create-form {
        border-color: ${mocha.green};
      }

      /* Feature 094 US3: Project create form styles (T066-T067) */
      .projects-header {
        padding: 8px 12px;
        background-color: rgba(30, 30, 46, 0.4);
        border-bottom: 1px solid ${mocha.surface0};
        margin-bottom: 8px;
      }

      .projects-header-title {
        font-size: 14px;
        font-weight: bold;
        color: ${mocha.text};
      }

      .new-project-button {
        background-color: ${mocha.green};
        color: ${mocha.base};
        padding: 4px 12px;
        border-radius: 6px;
        font-size: 12px;
        font-weight: bold;
        border: none;
      }

      .new-project-button:hover {
        background-color: ${mocha.teal};
      }

      .project-create-form {
        border-color: ${mocha.green};
        background-color: rgba(30, 30, 46, 0.95);
        margin: 8px;
        border-radius: 8px;
      }

      .project-create-form .edit-form-header {
        color: ${mocha.green};
      }

      /* Feature 094 US8: Apps tab header and create form styles */
      .apps-header {
        padding: 8px 12px;
        background-color: rgba(30, 30, 46, 0.4);
        border-bottom: 1px solid ${mocha.surface0};
        margin-bottom: 8px;
      }

      .apps-header-title {
        font-size: 14px;
        font-weight: bold;
        color: ${mocha.text};
      }

      .new-app-button {
        background-color: ${mocha.sapphire};
        color: ${mocha.base};
        padding: 4px 12px;
        border-radius: 6px;
        font-size: 12px;
        font-weight: bold;
        border: none;
      }

      .new-app-button:hover {
        background-color: ${mocha.sky};
      }

      .app-create-form {
        border-color: ${mocha.sapphire};
        background-color: rgba(30, 30, 46, 0.95);
        margin: 8px;
        border-radius: 8px;
      }

      .app-create-form .edit-form-header {
        color: ${mocha.sapphire};
      }

      /* App type selector buttons */
      .app-type-selector {
        margin-bottom: 12px;
      }

      .type-buttons {
        padding: 4px 0;
      }

      .type-btn {
        background-color: rgba(49, 50, 68, 0.5);
        color: ${mocha.subtext0};
        padding: 8px 16px;
        border: 1px solid ${mocha.surface0};
        border-radius: 6px;
        font-size: 12px;
        margin-right: 8px;
      }

      .type-btn:hover {
        background-color: rgba(49, 50, 68, 0.8);
        color: ${mocha.text};
      }

      .type-btn.active {
        background-color: ${mocha.sapphire};
        color: ${mocha.base};
        border-color: ${mocha.sapphire};
        font-weight: bold;
      }

      /* Terminal command selector */
      .terminal-command-select {
        padding: 4px 0;
      }

      .term-btn {
        background-color: rgba(49, 50, 68, 0.5);
        color: ${mocha.subtext0};
        padding: 6px 12px;
        border: 1px solid ${mocha.surface0};
        border-radius: 4px;
        font-size: 11px;
        margin-right: 6px;
      }

      .term-btn:hover {
        background-color: rgba(49, 50, 68, 0.8);
        color: ${mocha.text};
      }

      .term-btn.active {
        background-color: ${mocha.teal};
        color: ${mocha.base};
        border-color: ${mocha.teal};
        font-weight: bold;
      }

      /* PWA-specific fields */
      .pwa-fields {
        padding: 12px;
        background-color: rgba(137, 180, 250, 0.1);
        border-radius: 6px;
        border: 1px solid ${mocha.sapphire};
        margin-top: 8px;
      }

      .pwa-workspace-note {
        color: ${mocha.peach};
        font-style: italic;
      }

      /* PWA create success message */
      .pwa-create-success {
        background-color: rgba(166, 227, 161, 0.2);
        border: 1px solid ${mocha.green};
        border-radius: 6px;
        padding: 12px;
        margin-top: 8px;
      }

      .pwa-create-success .success-message {
        color: ${mocha.green};
        font-weight: bold;
        margin-bottom: 8px;
      }

      .ulid-display {
        font-family: monospace;
      }

      .ulid-label {
        color: ${mocha.subtext0};
      }

      .ulid-value {
        color: ${mocha.sapphire};
        font-weight: bold;
      }

      /* Workspace input styling */
      .workspace-input {
        min-width: 80px;
      }

      /* Scope selector buttons */
      .scope-buttons {
        padding: 4px 0;
      }

      .scope-btn {
        background-color: rgba(49, 50, 68, 0.5);
        color: ${mocha.subtext0};
        padding: 6px 16px;
        border: 1px solid ${mocha.surface0};
        border-radius: 4px;
        font-size: 12px;
        margin-right: 8px;
      }

      .scope-btn:hover {
        background-color: rgba(49, 50, 68, 0.8);
        color: ${mocha.text};
      }

      .scope-btn.active {
        background-color: ${mocha.blue};
        color: ${mocha.base};
        border-color: ${mocha.blue};
        font-weight: bold;
      }

      /* Remote toggle styling */
      .remote-toggle {
        padding: 8px 0;
        margin-top: 8px;
      }

      .remote-toggle checkbox {
        margin-right: 8px;
      }

      .remote-fields {
        padding: 12px;
        background-color: rgba(49, 50, 68, 0.3);
        border-radius: 6px;
        border: 1px solid ${mocha.surface1};
        margin-top: 8px;
      }

      /* Smaller input fields for icon and port */
      .icon-input {
        min-width: 60px;
      }

      .port-input {
        min-width: 80px;
      }

      /* Feature 094 US5: Read-only field styling */
      .readonly-field .field-readonly {
        color: ${mocha.subtext0};
        background-color: rgba(49, 50, 68, 0.5);
        padding: 8px 12px;
        border-radius: 6px;
        border: 1px solid ${mocha.surface0};
        font-family: monospace;
        font-size: 12px;
      }

      .readonly-field .field-label {
        color: ${mocha.overlay0};
      }

      /* Feature 094 US5: Field hint text */
      .field-hint {
        font-size: 10px;
        color: ${mocha.overlay0};
        margin-top: 4px;
        font-style: italic;
      }

      /* Feature 094: Edit Form Styles (T038) */
      .edit-button {
        background-color: transparent;
        border: none;
        color: ${mocha.blue};
        padding: 3px 6px;
        border-radius: 4px;
        font-size: 11px;
        margin-left: 6px;
      }

      .edit-button label {
        color: ${mocha.blue};
      }

      .edit-button:hover {
        background-color: rgba(137, 180, 250, 0.2);
      }

      .edit-button:hover label {
        color: ${mocha.blue};
      }

      /* Feature 094 US4: Delete button styles (T087) */
      .delete-button {
        background-color: transparent;
        border: none;
        color: ${mocha.red};
        padding: 3px 6px;
        border-radius: 4px;
        font-size: 11px;
        margin-left: 4px;
      }

      .delete-button:hover {
        background-color: rgba(243, 139, 168, 0.2);
      }

      /* Feature 094 US4: Delete confirmation dialog styles (T088-T089) */
      .delete-confirmation-dialog {
        background-color: rgba(24, 24, 37, 0.98);
        border: 2px solid ${mocha.red};
        border-radius: 8px;
        padding: 16px;
        margin: 8px 0;
      }

      .delete-confirmation-dialog .dialog-header {
        margin-bottom: 12px;
      }

      .delete-confirmation-dialog .dialog-icon {
        font-size: 18px;
        margin-right: 8px;
      }

      .delete-confirmation-dialog .dialog-icon.warning {
        color: ${mocha.peach};
      }

      .delete-confirmation-dialog .dialog-title {
        font-size: 16px;
        font-weight: bold;
        color: ${mocha.red};
      }

      .delete-confirmation-dialog .project-name-display {
        font-size: 14px;
        font-weight: bold;
        color: ${mocha.text};
        margin-bottom: 12px;
        padding: 8px 12px;
        background-color: rgba(243, 139, 168, 0.1);
        border-radius: 4px;
        border-left: 3px solid ${mocha.red};
      }

      .delete-confirmation-dialog .warning-message {
        font-size: 12px;
        color: ${mocha.subtext0};
        margin-bottom: 12px;
        
      }

      .delete-confirmation-dialog .worktree-warning {
        background-color: rgba(250, 179, 135, 0.15);
        border: 1px solid ${mocha.peach};
        border-radius: 6px;
        padding: 12px;
        margin-bottom: 12px;
      }

      .delete-confirmation-dialog .warning-icon {
        font-size: 12px;
        color: ${mocha.peach};
        font-weight: bold;
        margin-bottom: 6px;
      }

      .delete-confirmation-dialog .warning-detail {
        font-size: 11px;
        color: ${mocha.subtext0};
        margin-bottom: 8px;
        
      }

      .delete-confirmation-dialog .force-delete-option {
        margin-top: 8px;
        padding: 6px 0;
      }

      .delete-confirmation-dialog .force-delete-checkbox {
        margin-right: 8px;
      }

      .delete-confirmation-dialog .force-delete-label {
        font-size: 12px;
        color: ${mocha.peach};
      }

      .delete-confirmation-dialog .error-message {
        color: ${mocha.red};
        font-size: 12px;
        padding: 8px 12px;
        background-color: rgba(243, 139, 168, 0.15);
        border-radius: 4px;
        margin-bottom: 12px;
      }

      .delete-confirmation-dialog .dialog-actions {
        margin-top: 16px;
      }

      .delete-confirmation-dialog .cancel-delete-button {
        background-color: rgba(49, 50, 68, 0.8);
        color: ${mocha.subtext0};
        padding: 8px 16px;
        border: 1px solid ${mocha.surface1};
        border-radius: 6px;
        font-size: 12px;
        margin-right: 8px;
      }

      .delete-confirmation-dialog .cancel-delete-button:hover {
        background-color: ${mocha.surface0};
        color: ${mocha.text};
      }

      .delete-confirmation-dialog .confirm-delete-button {
        background-color: ${mocha.red};
        color: ${mocha.base};
        padding: 8px 16px;
        border: none;
        border-radius: 6px;
        font-size: 12px;
        font-weight: bold;
      }

      .delete-confirmation-dialog .confirm-delete-button:hover {
        background-color: rgba(243, 139, 168, 0.85);
      }

      .delete-confirmation-dialog .confirm-delete-button.disabled {
        background-color: ${mocha.surface1};
        color: ${mocha.overlay0};
      }

      .delete-confirmation-dialog .confirm-delete-button.disabled:hover {
        background-color: ${mocha.surface1};
      }

      /* Feature 094 US9: Application Delete Confirmation Dialog (T093-T096) */
      .app-delete-confirmation-dialog {
        background-color: rgba(24, 24, 37, 0.98);
        border: 2px solid rgba(243, 139, 168, 0.7);
        border-radius: 8px;
        padding: 16px;
        margin-top: 8px;
        margin-bottom: 8px;
      }

      .app-delete-confirmation-dialog .dialog-header {
        margin-bottom: 12px;
      }

      .app-delete-confirmation-dialog .dialog-icon {
        font-size: 20px;
        margin-right: 8px;
      }

      .app-delete-confirmation-dialog .dialog-icon.warning {
        color: ${mocha.yellow};
      }

      .app-delete-confirmation-dialog .dialog-title {
        font-size: 14px;
        font-weight: bold;
        color: rgba(243, 139, 168, 0.95);
      }

      .app-delete-confirmation-dialog .app-name-display {
        font-size: 16px;
        font-weight: bold;
        color: ${mocha.text};
        padding: 8px 12px;
        background-color: ${mocha.surface0};
        border-radius: 4px;
        margin-bottom: 12px;
      }

      .app-delete-confirmation-dialog .warning-message {
        font-size: 12px;
        color: ${mocha.subtext0};
        margin-bottom: 12px;
        
      }

      .app-delete-confirmation-dialog .pwa-warning {
        background-color: rgba(249, 226, 175, 0.15);
        border: 1px solid ${mocha.yellow};
        border-radius: 6px;
        padding: 10px;
        margin-bottom: 12px;
      }

      .app-delete-confirmation-dialog .pwa-warning .warning-icon {
        font-size: 12px;
        font-weight: bold;
        color: ${mocha.yellow};
        margin-bottom: 4px;
      }

      .app-delete-confirmation-dialog .pwa-warning .warning-detail {
        font-size: 11px;
        color: ${mocha.subtext0};
        
      }

      .app-delete-confirmation-dialog .error-message {
        background-color: rgba(243, 139, 168, 0.2);
        border: 1px solid rgba(243, 139, 168, 0.5);
        border-radius: 4px;
        padding: 8px;
        margin-bottom: 12px;
        font-size: 12px;
        color: rgba(243, 139, 168, 1);
      }

      .app-delete-confirmation-dialog .dialog-actions {
        margin-top: 8px;
      }

      .app-delete-confirmation-dialog .cancel-delete-app-button {
        background-color: ${mocha.surface0};
        color: ${mocha.text};
        border: 1px solid ${mocha.overlay0};
        border-radius: 4px;
        padding: 6px 12px;
        font-size: 12px;
      }

      .app-delete-confirmation-dialog .cancel-delete-app-button:hover {
        background-color: ${mocha.surface1};
        border-color: ${mocha.overlay0};
      }

      .app-delete-confirmation-dialog .confirm-delete-app-button {
        background-color: rgba(243, 139, 168, 0.85);
        color: ${mocha.mantle};
        border: none;
        border-radius: 4px;
        padding: 6px 12px;
        font-size: 12px;
        font-weight: bold;
      }

      .app-delete-confirmation-dialog .confirm-delete-app-button:hover {
        background-color: rgba(243, 139, 168, 1);
      }

      /* Delete button styling for app cards */
      .delete-app-button {
        background-color: transparent;
        border: none;
        font-size: 12px;
        padding: 2px 6px;
        border-radius: 3px;
        opacity: 0.6;
        margin-left: 4px;
      }

      .delete-app-button:hover {
        background-color: rgba(243, 139, 168, 0.2);
        opacity: 1;
      }

      /* Rebuild required notice after successful deletion */
      .rebuild-required-notice {
        background-color: rgba(166, 227, 161, 0.15);
        border: 1px solid ${mocha.green};
        border-radius: 6px;
        padding: 12px;
        margin: 8px 0;
        font-size: 12px;
        color: ${mocha.green};
      }

      /* Feature 094 Phase 12 T099: Success notification toast */
      .success-notification-toast {
        background-color: rgba(166, 227, 161, 0.95);
        border: 1px solid ${mocha.green};
        border-radius: 8px;
        padding: 10px 16px;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
        margin-top: 10px;
      }

      .success-notification-toast .success-icon {
        font-size: 16px;
        color: ${mocha.mantle};
        font-weight: bold;
      }

      .success-notification-toast .success-message {
        font-size: 13px;
        color: ${mocha.mantle};
        font-weight: 500;
      }

      .success-notification-toast .success-dismiss {
        background-color: transparent;
        border: none;
        font-size: 12px;
        color: ${mocha.mantle};
        opacity: 0.7;
        padding: 2px 6px;
        margin-left: 8px;
      }

      .success-notification-toast .success-dismiss:hover {
        opacity: 1;
      }

      /* Feature 094 Phase 12 T098: Loading spinner styles */
      .save-in-progress {
        opacity: 0.6;
      }

      .loading-spinner {
        font-size: 14px;
      }

      .edit-form {
        background-color: rgba(24, 24, 37, 0.95);
        border: 1px solid ${mocha.blue};
        border-radius: 8px;
        padding: 16px;
        margin-top: 8px;
      }

      .edit-form-header {
        font-size: 14px;
        font-weight: bold;
        color: ${mocha.blue};
        margin-bottom: 12px;
      }

      .form-field {
        margin-bottom: 12px;
      }

      .field-label {
        font-size: 11px;
        color: ${mocha.subtext0};
        margin-bottom: 4px;
      }

      .field-input {
        background-color: ${mocha.surface0};
        border: 1px solid ${mocha.overlay0};
        border-radius: 4px;
        padding: 6px 8px;
        font-size: 12px;
        color: ${mocha.text};
      }

      .field-input:focus {
        border-color: ${mocha.blue};
        outline: none;
      }

      .field-value-readonly {
        font-size: 11px;
        color: ${mocha.subtext0};
        padding: 6px 8px;
        background-color: ${mocha.mantle};
        border-radius: 4px;
        font-family: "JetBrainsMono Nerd Font", monospace;
      }

      /* Feature 094 T040: Conflict resolution dialog styles */
      .conflict-dialog-overlay {
        background-color: rgba(0, 0, 0, 0.7);
        padding: 20px;
      }

      .conflict-dialog {
        background-color: ${mocha.base};
        border: 2px solid ${mocha.yellow};
        border-radius: 12px;
        padding: 20px;
      }

      .conflict-header {
        padding-bottom: 12px;
        border-bottom: 1px solid ${mocha.overlay0};
        margin-bottom: 16px;
      }

      .conflict-title {
        font-size: 16px;
        font-weight: bold;
        color: ${mocha.yellow};
      }

      .conflict-close-button {
        background-color: transparent;
        border: none;
        color: ${mocha.overlay0};
        font-size: 18px;
        padding: 4px 8px;
      }

      .conflict-close-button:hover {
        color: ${mocha.text};
        background-color: ${mocha.surface0};
        border-radius: 4px;
      }

      .conflict-message {
        font-size: 13px;
        color: ${mocha.text};
        margin-bottom: 16px;
      }

      .conflict-diff-container {
        margin: 16px 0;
      }

      .conflict-diff-pane {
        border: 1px solid ${mocha.overlay0};
        border-radius: 8px;
        padding: 8px;
        background-color: ${mocha.mantle};
      }

      .conflict-pane-header {
        font-size: 12px;
        font-weight: bold;
        color: ${mocha.blue};
        margin-bottom: 8px;
      }

      .conflict-content {
        font-family: "JetBrainsMono Nerd Font", monospace;
        font-size: 11px;
        color: ${mocha.text};
      }

      .conflict-actions {
        margin-top: 16px;
        padding-top: 12px;
        border-top: 1px solid ${mocha.overlay0};
      }

      .conflict-button {
        padding: 8px 16px;
        border-radius: 6px;
        font-size: 12px;
        font-weight: bold;
        margin: 0 4px;
      }

      .conflict-keep-file {
        background-color: ${mocha.surface0};
        border: 1px solid ${mocha.overlay0};
        color: ${mocha.text};
      }

      .conflict-keep-file:hover {
        background-color: ${mocha.surface1};
        border-color: ${mocha.overlay0};
      }

      .conflict-keep-ui {
        background-color: ${mocha.green};
        border: 1px solid ${mocha.green};
        color: ${mocha.base};
      }

      .conflict-keep-ui:hover {
        background-color: ${mocha.teal};
        border-color: ${mocha.teal};
      }

      .conflict-merge {
        background-color: ${mocha.yellow};
        border: 1px solid ${mocha.yellow};
        color: ${mocha.base};
      }

      .conflict-merge:hover {
        background-color: ${mocha.peach};
        border-color: ${mocha.peach};
      }

      .radio-button {
        background-color: ${mocha.surface0};
        border: 1px solid ${mocha.overlay0};
        border-radius: 4px;
        padding: 6px 12px;
        font-size: 11px;
        color: ${mocha.text};
        margin-right: 8px;
      }

      .radio-button.selected {
        background-color: ${mocha.blue};
        border-color: ${mocha.blue};
        color: ${mocha.base};
      }

      .radio-button:hover {
        border-color: ${mocha.blue};
      }

      .form-section {
        margin-top: 16px;
        padding-top: 16px;
        border-top: 1px solid ${mocha.overlay0};
      }

      .remote-fields {
        margin-left: 24px;
        margin-top: 8px;
      }

      .form-actions {
        margin-top: 16px;
      }

      .cancel-button {
        background-color: ${mocha.surface0};
        border: 1px solid ${mocha.overlay0};
        border-radius: 4px;
        padding: 8px 16px;
        margin-right: 8px;
        font-size: 12px;
        color: ${mocha.text};
      }

      .cancel-button:hover {
        background-color: ${mocha.surface1};
        border-color: ${mocha.overlay0};
      }

      .save-button {
        background-color: ${mocha.blue};
        border: 1px solid ${mocha.blue};
        border-radius: 4px;
        padding: 8px 16px;
        font-size: 12px;
        color: ${mocha.base};
        font-weight: bold;
      }

      .save-button:hover {
        background-color: ${mocha.sapphire};
        border-color: ${mocha.sapphire};
      }

      /* T039: Disabled save button (validation failed) */
      .save-button-disabled {
        background-color: ${mocha.surface0};
        border: 1px solid ${mocha.overlay0};
        border-radius: 4px;
        padding: 8px 16px;
        font-size: 12px;
        color: ${mocha.subtext0};
        font-weight: bold;
        opacity: 0.5;
      }

      /* T039: Field-level validation error messages */
      .field-error {
        font-size: 11px;
        color: ${mocha.red};
        margin-top: 4px;
        padding: 4px 0;
      }

      /* Error message styles (T041) */
      .error-message {
        background-color: rgba(243, 139, 168, 0.15);
        border-left: 3px solid ${mocha.red};
        padding: 12px;
        margin: 8px 0;
        font-size: 12px;
        color: ${mocha.red};
        border-radius: 4px;
      }

      /* App Card Styles */
      .app-card {
        background-color: rgba(49, 50, 68, 0.4);
        border: 1px solid ${mocha.overlay0};
        border-radius: 8px;
        padding: 12px;
        margin-bottom: 8px;
      }

      .app-card-header {
        margin-bottom: 4px;
      }

      .app-icon {
        font-size: 18px;
        margin-right: 8px;
      }

      .app-card-name {
        font-size: 13px;
        font-weight: bold;
        color: ${mocha.text};
        margin-bottom: 2px;
      }

      .app-card-details {
        font-size: 10px;
        color: ${mocha.subtext0};
      }

      .app-running-indicator {
        color: ${mocha.green};
        font-size: 14px;
      }

      /* Feature 094: Enhanced Applications Tab Styles */
      .app-section {
        margin-bottom: 16px;
      }

      .section-header {
        font-size: 12px;
        font-weight: bold;
        color: ${mocha.subtext0};
        letter-spacing: 0.5px;
        margin-bottom: 8px;
        margin-left: 4px;
      }

      .app-icon-container {
        margin-right: 10px;
      }

      .app-type-icon {
        font-size: 24px;
      }

      .app-name-row {
        margin-bottom: 2px;
      }

      .app-card-command {
        font-size: 9px;
        color: ${mocha.subtext0};
        font-family: "JetBrainsMono Nerd Font", monospace;
      }

      .terminal-indicator {
        color: ${mocha.mauve};
        font-size: 12px;
        margin-left: 6px;
      }

      .app-status-container {
        margin-left: 8px;
      }

      .app-card-details-row {
        margin-top: 6px;
        padding-top: 6px;
        border-top: 1px solid rgba(108, 112, 134, 0.2);
      }

      /* Feature 094 US7: Application Edit Button Style (T048) */
      .app-edit-button {
        background-color: transparent;
        color: ${mocha.blue};
        border: none;
        font-size: 14px;
        padding: 2px 6px;
        border-radius: 4px;
      }

      .app-edit-button:hover {
        background-color: rgba(137, 180, 250, 0.15);
        color: ${mocha.sapphire};
      }

      /* Health Card Styles */
      .health-cards {
        padding: 4px;
      }

      .health-card {
        background-color: rgba(49, 50, 68, 0.4);
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
        padding: 10px 12px;
        margin-bottom: 6px;
      }

      .health-card.health-ok {
        border-left: 3px solid ${mocha.green};
      }

      .health-card.health-error {
        border-left: 3px solid ${mocha.red};
      }

      .health-card-title {
        font-size: 12px;
        color: ${mocha.subtext0};
      }

      .health-card-value {
        font-size: 13px;
        font-weight: bold;
        color: ${mocha.text};
      }

      /* Feature 088: Service Health Card Styles */
      .health-summary {
        background-color: rgba(49, 50, 68, 0.3);
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
        padding: 8px 12px;
        margin-bottom: 8px;
      }

      .health-summary-title {
        font-size: 14px;
        font-weight: bold;
        color: ${mocha.text};
        margin-bottom: 4px;
      }

      .health-summary-counts {
        font-size: 11px;
        color: ${mocha.subtext0};
      }

      .health-categories {
        padding: 4px;
      }

      .service-category {
        margin-bottom: 12px;
      }

      .category-header {
        background-color: rgba(69, 71, 90, 0.5);
        border-radius: 4px;
        padding: 6px 10px;
        margin-bottom: 6px;
      }

      .category-title {
        font-size: 13px;
        font-weight: bold;
        color: ${mocha.text};
      }

      .category-counts {
        font-size: 11px;
        color: ${mocha.subtext0};
      }

      .service-list {
        padding-left: 4px;
      }

      .service-health-card {
        background-color: rgba(49, 50, 68, 0.4);
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
        padding: 8px 10px;
        margin-bottom: 4px;
        /* transition not supported in GTK CSS */
      }

      .service-health-card:hover {
        background-color: rgba(69, 71, 90, 0.6);
      }

      /* Health state colors (Feature 088) */
      .service-health-card.health-healthy {
        border-left: 3px solid ${mocha.green};  /* #a6e3a1 */
      }

      /* T034: Enhanced visual differentiation for degraded services */
      .service-health-card.health-degraded {
        border-left: 3px solid ${mocha.yellow};  /* #f9e2af */
        background-color: rgba(249, 226, 175, 0.1);  /* Subtle yellow tint */
      }

      .service-health-card.health-degraded .service-icon {
        color: ${mocha.yellow};
      }

      /* T024: Enhanced visual differentiation for critical services */
      .service-health-card.health-critical {
        border-left: 4px solid ${mocha.red};  /* #f38ba8 - thicker border */
        border: 1px solid ${mocha.red};  /* Red border all around */
        background-color: rgba(243, 139, 168, 0.15);  /* More prominent background */
        box-shadow: 0 0 8px rgba(243, 139, 168, 0.3);  /* Subtle glow effect */
      }

      .service-health-card.health-critical .service-name {
        color: ${mocha.red};  /* Red service name for critical */
        font-weight: 600;
      }

      .service-health-card.health-critical .service-icon {
        color: ${mocha.red};
      }

      .service-health-card.health-disabled {
        border-left: 3px solid ${mocha.overlay0};  /* #6c7086 */
        opacity: 0.7;
      }

      .service-health-card.health-unknown {
        border-left: 3px solid ${mocha.peach};  /* #fab387 */
      }

      .service-icon {
        font-size: 16px;
        min-width: 24px;
        margin-right: 8px;
      }

      .service-info {
        /* GTK CSS uses box model, not flexbox - widget expands automatically */
      }

      .service-name {
        font-size: 12px;
        font-weight: 500;
        color: ${mocha.text};
      }

      .service-status {
        font-size: 10px;
        color: ${mocha.subtext0};
        margin-top: 2px;
      }

      /* Feature 088 US2: Uptime and last active time (T022, T023) */
      .service-uptime {
        font-size: 9px;
        color: ${mocha.green};
        margin-top: 2px;
      }

      .service-memory {
        font-size: 9px;
        color: ${mocha.blue};
        margin-top: 2px;
      }

      .service-last-active {
        font-size: 9px;
        color: ${mocha.red};
        margin-top: 2px;
        font-style: italic;
      }

      .health-indicator-box {
        min-width: 80px;
      }

      .health-indicator {
        font-size: 10px;
        color: ${mocha.subtext0};
        /* text-transform not supported in GTK CSS */
        padding: 2px 6px;
        border-radius: 3px;
        background-color: rgba(69, 71, 90, 0.5);
      }

      /* Feature 088 US2: Restart count indicator (T022, T032, T033) */
      .restart-count {
        font-size: 9px;
        color: ${mocha.yellow};
        margin-top: 2px;
        font-weight: bold;
      }

      /* T032: High restart count warning (>= 3 restarts) */
      .restart-count.restart-warning {
        color: ${mocha.red};
        font-size: 10px;
        /* GTK CSS doesn't support @keyframes animations */
      }

      /* Feature 088 US3: Restart button (T028-T030) */
      .restart-button {
        background-color: ${mocha.blue};
        color: ${mocha.base};
        border: none;
        border-radius: 4px;
        padding: 4px 8px;
        margin-top: 4px;
        font-size: 14px;
        font-weight: bold;
        /* cursor and transition not supported in GTK CSS */
      }

      .restart-button:hover {
        background-color: ${mocha.sapphire};
        /* transform not supported in GTK CSS */
      }

      .restart-button:active {
        background-color: ${mocha.sky};
        /* transform not supported in GTK CSS */
      }

      /* Window Detail View Styles */
      .detail-view {
        background-color: transparent;
        padding: 8px;
      }

      .detail-header {
        background-color: rgba(49, 50, 68, 0.4);
        border-radius: 8px;
        padding: 8px 12px;
        margin-bottom: 8px;
      }

      .detail-back-btn {
        font-size: 12px;
        padding: 6px 12px;
        background-color: rgba(69, 71, 90, 0.5);
        color: ${mocha.text};
        border: 1px solid ${mocha.overlay0};
        border-radius: 4px;
      }

      .detail-back-btn:hover {
        background-color: rgba(137, 180, 250, 0.6);
        color: ${mocha.base};
        border-color: ${mocha.blue};
      }

      .detail-title {
        font-size: 14px;
        font-weight: bold;
        color: ${mocha.text};
      }

      .detail-content {
        padding: 4px;
      }

      .detail-section {
        background-color: rgba(49, 50, 68, 0.4);
        border: 1px solid ${mocha.overlay0};
        border-radius: 8px;
        padding: 10px 12px;
        margin-bottom: 8px;
      }

      .detail-section-title {
        font-size: 12px;
        font-weight: bold;
        color: ${mocha.teal};
        margin-bottom: 8px;
      }

      .detail-row {
        padding: 4px 0;
        border-bottom: 1px solid rgba(108, 112, 134, 0.2);
      }

      .detail-row:last-child {
        border-bottom: none;
      }

      .detail-label {
        font-size: 11px;
        color: ${mocha.subtext0};
        min-width: 80px;
      }

      .detail-value {
        font-size: 11px;
        color: ${mocha.text};
        font-family: monospace;
      }

      .detail-full-title {
        font-size: 12px;
        color: ${mocha.text};
      }

      .detail-marks {
        font-size: 10px;
        color: ${mocha.subtext0};
        font-family: monospace;
      }

      /* Window info in list view */
      .window-info {
        margin-left: 6px;
        min-width: 0;
      }

      .window-app-name {
        min-width: 0;
      }

      .window-title {
        font-size: 10px;
        color: ${mocha.subtext0};
        min-width: 0;
      }

      .window:hover {
        background-color: rgba(49, 50, 68, 0.3);
      }

      /* Feature 092: Event Logging - Logs View Styling (T027) */
      .events-view-container {
        padding: 8px;
      }

      .events-list {
        padding: 4px;
      }

      .event-card {
        background-color: ${mocha.surface0};
        border-left: 3px solid ${mocha.overlay0};
        border-radius: 4px;
        padding: 8px;
        margin-bottom: 6px;
        transition: background-color 0.2s ease;
      }

      .event-card:hover {
        background-color: ${mocha.surface1};
      }

      /* Category-specific border colors */
      .event-card.event-category-window {
        border-left-color: ${mocha.blue};
      }

      .event-card.event-category-workspace {
        border-left-color: ${mocha.teal};
      }

      .event-card.event-category-output {
        border-left-color: ${mocha.mauve};
      }

      .event-card.event-category-binding {
        border-left-color: ${mocha.yellow};
      }

      .event-card.event-category-mode {
        border-left-color: ${mocha.sky};
      }

      .event-card.event-category-system {
        border-left-color: ${mocha.red};
      }

      .event-icon {
        font-size: 20px;
        margin-right: 12px;
        min-width: 28px;
      }

      .event-details {
        /* GTK CSS doesn't support flex property - layout handled by box widget */
      }

      .event-header {
        margin-bottom: 4px;
      }

      .event-type {
        font-size: 11px;
        font-weight: 600;
        color: ${mocha.text};
        font-family: monospace;
      }

      .event-timestamp {
        font-size: 10px;
        color: ${mocha.subtext0};
        font-style: italic;
      }

      .event-payload {
        font-size: 10px;
        color: ${mocha.subtext0};
        /* GTK CSS doesn't support white-space property */
      }
    '';

    # Systemd user service for Eww monitoring panel (T018)
    systemd.user.services.eww-monitoring-panel = {
      Unit = {
        Description = "Eww Monitoring Panel for Window/Project State";
        Documentation = "file:///etc/nixos/specs/085-sway-monitoring-widget/quickstart.md";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.eww}/bin/eww --config %h/.config/eww-monitoring-panel daemon --no-daemonize";
        # Open the monitoring panel window after daemon starts
        # This is required for deflisten to start streaming window data
        ExecStartPost = "${pkgs.bash}/bin/bash -c 'sleep 1 && ${pkgs.eww}/bin/eww --config %h/.config/eww-monitoring-panel open monitoring-panel'";
        Restart = "on-failure";
        RestartSec = "3s";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
# Test comment to force rebuild
