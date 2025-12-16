{ config, lib, pkgs, osConfig ? null, monitorConfig ? {}, ... }:

with lib;

let
  cfg = config.programs.eww-monitoring-panel;

  # Get hostname for monitor config lookup
  hostname = osConfig.networking.hostName or "hetzner";

  # Get monitor configuration for this host (with fallback)
  hostMonitors = monitorConfig.${hostname} or {
    primary = "HEADLESS-1";
    secondary = "HEADLESS-2";
    tertiary = "HEADLESS-3";
    quaternary = "HEADLESS-3";  # Fallback to tertiary
    outputs = [ "HEADLESS-1" "HEADLESS-2" "HEADLESS-3" ];
  };

  # Export role-based outputs for use in widget config (4-tier system)
  primaryOutput = hostMonitors.primary;
  secondaryOutput = hostMonitors.secondary;
  tertiaryOutput = hostMonitors.tertiary;
  quaternaryOutput = hostMonitors.quaternary or hostMonitors.tertiary;

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
    lavender = "#b4befe";  # Lavender accent (input focus)
    pink = "#f5c2e7";      # Pink accent (scratchpad events)
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
  # Version: 2025-11-26-v12 (Feature 097: Optional chaining for remote fields)
  monitoringDataScript = pkgs.writeShellScriptBin "monitoring-data-backend" ''
    #!${pkgs.bash}/bin/bash
    # Version: 2025-12-15-v15 (Feature 117: AI Sessions bar with 3 states - working/attention/idle)

    # Add user profile bin to PATH so i3pm can be found by subprocess calls
    export PATH="${config.home.profileDirectory}/bin:$PATH"

    # Set PYTHONPATH to tools directory for i3_project_manager imports
    export PYTHONPATH="${../tools}"

    # Feature 117: Set daemon socket path (user service at XDG_RUNTIME_DIR)
    export I3PM_DAEMON_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

    # Use Python with i3ipc package included
    # Pass through all arguments (e.g., --listen flag)
    exec ${pythonForBackend}/bin/python3 ${../tools/i3_project_manager/cli/monitoring_data.py} "$@"
  '';

  # Feature 110: Spinner animation script for pulsating circle
  # Outputs both the circle character and opacity value (space-separated)
  # Larger base circle with opacity fade effect
  spinnerScript = pkgs.writeShellScriptBin "eww-spinner-frame" ''
    #!/usr/bin/env bash
    IDX_FILE="/tmp/eww-spinner-idx"
    IDX=$(cat "$IDX_FILE" 2>/dev/null || echo 0)
    # 8-frame animation: large circle with opacity pulse
    # All frames use the same large circle, opacity creates the pulse
    case $IDX in
      0)  echo "⬤" ;;  # opacity: 0.4
      1)  echo "⬤" ;;  # opacity: 0.6
      2)  echo "⬤" ;;  # opacity: 0.8
      3)  echo "⬤" ;;  # opacity: 1.0 (peak)
      4)  echo "⬤" ;;  # opacity: 1.0 (peak)
      5)  echo "⬤" ;;  # opacity: 0.8
      6)  echo "⬤" ;;  # opacity: 0.6
      7)  echo "⬤" ;;  # opacity: 0.4
      *)  echo "⬤" ;;
    esac
    NEXT=$(( (IDX + 1) % 8 ))
    echo "$NEXT" > "$IDX_FILE"
  '';

  # Feature 110: Opacity script for fade effect
  spinnerOpacityScript = pkgs.writeShellScriptBin "eww-spinner-opacity" ''
    #!/usr/bin/env bash
    IDX=$(cat /tmp/eww-spinner-idx 2>/dev/null || echo 0)
    # Opacity values matching frame index
    case $IDX in
      0)  echo "0.4" ;;
      1)  echo "0.6" ;;
      2)  echo "0.8" ;;
      3)  echo "1.0" ;;
      4)  echo "1.0" ;;
      5)  echo "0.8" ;;
      6)  echo "0.6" ;;
      7)  echo "0.4" ;;
      *)  echo "1.0" ;;
    esac
  '';

  # Service wrapper script - manages daemon and handles toggle signals
  # This keeps all eww processes (daemon + GTK renderers) in the service cgroup
  # preventing orphaned processes when toggle is invoked from keybindings
  wrapperScript = pkgs.writeShellScriptBin "eww-monitoring-panel-wrapper" ''
    #!${pkgs.bash}/bin/bash

    EWW="${pkgs.eww}/bin/eww"
    CONFIG="$HOME/.config/eww-monitoring-panel"
    TIMEOUT="${pkgs.coreutils}/bin/timeout"
    PID_FILE="/tmp/eww-monitoring-panel-wrapper.pid"

    # Write wrapper PID for toggle script to send signals directly to this process only
    echo $$ > "$PID_FILE"

    # Cleanup on exit
    cleanup() {
      rm -f "$PID_FILE"
      # Kill orphaned 'eww open' processes (they escape to systemd due to double-fork)
      ${pkgs.procps}/bin/pkill -f 'eww.*eww-monitoring-panel.*open' 2>/dev/null || true
      kill $DAEMON_PID 2>/dev/null
    }
    trap cleanup EXIT

    # Start daemon in background, capture PID
    $EWW --config "$CONFIG" daemon --no-daemonize &
    DAEMON_PID=$!

    # Wait for daemon ready (max 6 seconds)
    for i in $(seq 1 30); do
      $TIMEOUT 1s $EWW --config "$CONFIG" ping 2>/dev/null && break
      ${pkgs.coreutils}/bin/sleep 0.2
    done

    # Kill any orphaned 'eww open' processes before opening
    # eww 0.6.0 double-forks so 'eww open' escapes to systemd - must clean up
    ${pkgs.procps}/bin/pkill -f 'eww.*eww-monitoring-panel.*open' 2>/dev/null || true

    # Open panel initially (--no-daemonize prevents orphan process spawning)
    $EWW --config "$CONFIG" --no-daemonize open monitoring-panel || true

    # Re-sync stack index (workaround for eww #1192: index resets on reopen)
    ${pkgs.coreutils}/bin/sleep 0.2
    IDX=$($EWW --config "$CONFIG" get current_view_index 2>/dev/null || echo 0)
    $EWW --config "$CONFIG" update current_view_index=$IDX 2>/dev/null || true

    # Toggle handler - called when SIGUSR1 received
    # Best practices from eww documentation:
    # - Verify daemon is ready before sending commands
    # - Use --no-daemonize to prevent eww from spawning new daemons
    # Note: Orphan cleanup only happens at service start/stop, not during toggle
    #       to avoid killing the window renderer mid-operation
    toggle_panel() {
      # Verify daemon is ready (prevents eww from starting new daemon)
      if ! $TIMEOUT 2s $EWW --config "$CONFIG" ping 2>/dev/null; then
        return 1
      fi

      # Atomic toggle with --no-daemonize to prevent orphan spawning
      $EWW --config "$CONFIG" --no-daemonize open --toggle monitoring-panel 2>/dev/null || true

      # Brief pause for state to settle
      ${pkgs.coreutils}/bin/sleep 0.2

      # Update state variables based on window visibility
      if $TIMEOUT 2s $EWW --config "$CONFIG" active-windows 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "monitoring-panel"; then
        $EWW --config "$CONFIG" update panel_visible=true panel_focus_mode=false 2>/dev/null || true
      else
        $EWW --config "$CONFIG" update panel_visible=false panel_focus_mode=false 2>/dev/null || true
      fi
    }

    trap toggle_panel SIGUSR1

    # Wait for daemon (re-wait after signal interrupts)
    while kill -0 $DAEMON_PID 2>/dev/null; do
      wait $DAEMON_PID || true
    done
  '';

  # Toggle script for panel visibility - sends signal directly to wrapper process
  # Uses PID file to avoid sending signal to all processes in service cgroup
  toggleScript = pkgs.writeShellScriptBin "toggle-monitoring-panel" ''
    #!${pkgs.bash}/bin/bash

    LOCK_FILE="/tmp/eww-monitoring-panel-toggle.lock"
    PID_FILE="/tmp/eww-monitoring-panel-wrapper.pid"

    # Debounce: prevent rapid toggling (crashes eww daemon)
    if [[ -f "$LOCK_FILE" ]]; then
      LOCK_AGE=$(($(${pkgs.coreutils}/bin/date +%s) - $(${pkgs.coreutils}/bin/stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
      if [[ $LOCK_AGE -lt 1 ]]; then
        exit 0
      fi
    fi
    ${pkgs.coreutils}/bin/touch "$LOCK_FILE"

    # Ensure service is running
    if ! ${pkgs.systemd}/bin/systemctl --user is-active eww-monitoring-panel.service >/dev/null 2>&1; then
      ${pkgs.systemd}/bin/systemctl --user start eww-monitoring-panel.service
      ${pkgs.coreutils}/bin/sleep 1  # Wait for service to start and PID file to be created
    fi

    # Send toggle signal directly to wrapper process (not entire cgroup)
    if [[ -f "$PID_FILE" ]]; then
      WRAPPER_PID=$(${pkgs.coreutils}/bin/cat "$PID_FILE")
      if kill -0 "$WRAPPER_PID" 2>/dev/null; then
        kill -SIGUSR1 "$WRAPPER_PID"
      fi
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
    TIMEOUT="${pkgs.coreutils}/bin/timeout"

    # Only proceed if daemon is running (avoid spawning duplicate daemon)
    if ! $TIMEOUT 2s $EWW_CMD ping >/dev/null 2>&1; then
      echo "Monitoring panel daemon not running"
      exit 0
    fi

    # Check if panel is visible first
    if ! $TIMEOUT 2s $EWW_CMD active-windows | ${pkgs.gnugrep}/bin/grep -q "monitoring-panel"; then
      echo "Panel not visible - use Mod+M to show it first"
      exit 0
    fi

    # Update eww variables sequentially with --kill-after to prevent orphans
    # Don't background these - orphaned processes cause duplicate tabs
    $TIMEOUT --kill-after=1s 2s $EWW_CMD update panel_focused=true || true
    $TIMEOUT --kill-after=1s 2s $EWW_CMD update panel_focus_mode=true || true
    $TIMEOUT --kill-after=1s 2s $EWW_CMD update selected_index=0 || true

    # Enter Sway monitoring mode (captures all keys)
    # This provides keyboard capture - eww layer-shell handles the rest
    ${pkgs.sway}/bin/swaymsg 'mode "📊 Panel"'
  '';

  # Feature 086: Exit monitoring mode script
  exitMonitorModeScript = pkgs.writeShellScriptBin "exit-monitor-mode" ''
    #!${pkgs.bash}/bin/bash
    # Feature 086: Exit monitoring focus mode
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    TIMEOUT="${pkgs.coreutils}/bin/timeout"

    # Only update eww if daemon is running (avoid spawning duplicate daemon)
    if $TIMEOUT 2s $EWW_CMD ping >/dev/null 2>&1; then
      # Update eww variables sequentially with --kill-after to prevent orphans
      # Don't background these - orphaned processes cause duplicate tabs
      $TIMEOUT --kill-after=1s 2s $EWW_CMD update panel_focused=false || true
      $TIMEOUT --kill-after=1s 2s $EWW_CMD update panel_focus_mode=false || true
      $TIMEOUT --kill-after=1s 2s $EWW_CMD update selected_index=-1 || true
    fi

    # Exit Sway mode (return to default) - always do this
    ${pkgs.sway}/bin/swaymsg 'mode "default"'

    # Return focus to previous window
    ${pkgs.sway}/bin/swaymsg 'focus prev'
  '';

  # Wrapper script: Switch monitoring panel tab by index
  # Usage: monitor-panel-tab <index>
  # Index mapping: 0=windows, 1=projects, 2=apps, 3=health, 4=events, 5=traces
  # This centralizes the variable name so Sway keybindings don't need to know it
  monitorPanelTabScript = pkgs.writeShellScriptBin "monitor-panel-tab" ''
    #!${pkgs.bash}/bin/bash
    # Switch monitoring panel to specified tab index
    # Usage: monitor-panel-tab <index>
    # Index: 0=windows, 1=projects, 2=apps, 3=health, 4=events, 5=traces

    EWW="${pkgs.eww}/bin/eww"
    CONFIG="$HOME/.config/eww-monitoring-panel"
    TIMEOUT="${pkgs.coreutils}/bin/timeout"
    INDEX="''${1:-0}"

    # Validate index is 0-6
    if [[ ! "$INDEX" =~ ^[0-6]$ ]]; then
      echo "Error: Invalid tab index '$INDEX'. Must be 0-6." >&2
      exit 1
    fi

    # Only proceed if daemon is running (avoid spawning duplicate daemon)
    if ! $TIMEOUT 2s $EWW --config "$CONFIG" ping >/dev/null 2>&1; then
      exit 0
    fi

    # Run sequentially with --kill-after to prevent orphans from rapid tab switching
    $TIMEOUT --kill-after=1s 2s $EWW --config "$CONFIG" update current_view_index="$INDEX" || true
  '';

  # Wrapper script: Get current monitoring panel view index
  # Usage: monitor-panel-get-view
  # Returns: 0-5 (or empty if panel not running)
  # Used by Sway keybindings for conditional routing (e.g., projects tab-specific actions)
  monitorPanelGetViewScript = pkgs.writeShellScriptBin "monitor-panel-get-view" ''
    #!${pkgs.bash}/bin/bash
    # Get current monitoring panel view index
    # Returns: 0=windows, 1=projects, 2=apps, 3=health, 4=events, 5=traces

    ${pkgs.eww}/bin/eww --config "$HOME/.config/eww-monitoring-panel" get current_view_index 2>/dev/null || echo "-1"
  '';

  # Wrapper script: Check if current view is projects tab
  # Usage: monitor-panel-is-projects && do_something
  # Exit code: 0 if on projects tab, 1 otherwise
  # Simplifies Sway keybinding conditionals
  monitorPanelIsProjectsScript = pkgs.writeShellScriptBin "monitor-panel-is-projects" ''
    #!${pkgs.bash}/bin/bash
    # Check if monitoring panel is on projects tab (index 1)
    # Exit code: 0 = on projects tab, 1 = not on projects tab

    VIEW=$(${pkgs.eww}/bin/eww --config "$HOME/.config/eww-monitoring-panel" get current_view_index 2>/dev/null)
    [ "$VIEW" = "1" ]
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

    # Feature 114: Enable focus mode so form inputs are clickable
    $EWW_CMD update panel_focus_mode=true

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
    # Usage: project-edit-save [project-name]
    # If no project-name is provided, reads from editing_project_name eww variable

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get project name from argument or from eww variable
    if [ -n "$1" ]; then
      PROJECT_NAME="$1"
    else
      PROJECT_NAME=$($EWW get editing_project_name)
    fi

    # Validate project name
    if [ -z "$PROJECT_NAME" ]; then
      echo "Error: No project name provided" >&2
      $EWW update edit_form_error="No project selected"
      exit 1
    fi

    # Feature 096 T022: Set loading state to prevent double-submit
    $EWW update save_in_progress=true

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
      # Feature 096 T010: Handle conflicts as warnings, not errors
      # The save DID succeed (last write wins), so continue with success handling
      # but show a warning notification to inform the user about the conflict
      if [ "$CONFLICT" = "true" ]; then
        # Feature 096 T023: Show warning notification for conflicts (but save succeeded)
        $EWW update warning_notification="File was modified externally - your changes were saved (last write wins)"
        $EWW update warning_notification_visible=true
        # Auto-dismiss warning after 5 seconds
        (sleep 5 && $EWW update warning_notification_visible=false warning_notification="") &
        echo "Warning: File was modified externally but your changes were saved (last write wins)" >&2
      fi

      # Success: Clear editing state and refresh
      # Feature 114: Disable focus mode to return to click-through
      $EWW update panel_focus_mode=false
      $EWW update editing_project_name='''
      $EWW update edit_form_error='''

      # Note: Project list will be refreshed by the deflisten stream automatically

      # Feature 096 T023: Show success notification
      $EWW update success_notification="Project saved successfully"
      $EWW update success_notification_visible=true
      # Auto-dismiss after 3 seconds (T020)
      (sleep 3 && $EWW update success_notification_visible=false success_notification="") &

      # Feature 096 T022: Clear loading state
      $EWW update save_in_progress=false

      echo "Project saved successfully"
    else
      # Feature 096 T024: Show error notification with specific message
      ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error')
      VALIDATION_ERRORS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors // [] | length')

      if [ "$VALIDATION_ERRORS" -gt 0 ]; then
        # Extract first validation error for display
        FIRST_ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors[0].message')
        ERROR_MSG="Validation error: $FIRST_ERROR"
      else
        ERROR_MSG="$ERROR"
      fi

      # Show error in form AND as notification toast
      $EWW update edit_form_error="$ERROR_MSG"
      $EWW update error_notification="$ERROR_MSG"
      $EWW update error_notification_visible=true
      # Error notifications persist until dismissed (no auto-dismiss)

      # Feature 096 T022: Clear loading state
      $EWW update save_in_progress=false

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
        # Feature 114: Disable focus mode to return to click-through
        $EWW_CMD update panel_focus_mode=false
        $EWW_CMD update conflict_dialog_visible=false
        $EWW_CMD update editing_project_name='''
        $EWW_CMD update edit_form_error='''
        # Note: Project list will be refreshed by the deflisten stream automatically
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
        # Feature 101: Open repos.json for manual editing
        # Individual project files no longer exist - all data is in repos.json
        REPOS_FILE="$HOME/.config/i3/repos.json"
        if [ -f "$REPOS_FILE" ]; then
          # Use default editor or fallback to nano
          ''${EDITOR:-nano} "$REPOS_FILE"
          # Close dialog - project list will be refreshed by the deflisten stream automatically
          # Feature 114: Disable focus mode to return to click-through
          $EWW_CMD update panel_focus_mode=false
          $EWW_CMD update conflict_dialog_visible=false
          $EWW_CMD update editing_project_name='''
          # Trigger rediscovery to ensure state is consistent
          i3pm discover >/dev/null 2>&1 || true
          echo "Opened $REPOS_FILE for manual editing (project: $PROJECT_NAME)" >&2
        else
          echo "Error: repos.json not found" >&2
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
    export PYTHONPATH="${../tools}:${../tools/monitoring-panel}"

    # Run validation stream (reads Eww variables, outputs JSON to stdout)
    exec ${pythonForBackend}/bin/python3 -c "
import sys
sys.path.insert(0, '${../tools}')
sys.path.insert(0, '${../tools/monitoring-panel}')
from project_form_validator_stream import FormValidationStream
import asyncio
stream = FormValidationStream('$HOME/.config/eww-monitoring-panel')
asyncio.run(stream.run())
"
  '';

  # Feature 099 T021: Worktree create form opener
  worktreeCreateOpenScript = pkgs.writeShellScriptBin "worktree-create-open" ''
    #!${pkgs.bash}/bin/bash
    # Open worktree create form for a given parent project
    # Usage: worktree-create-open <parent_project_name>
    # Feature 102: Auto-populate fields and suggest next branch number

    PARENT_PROJECT="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$PARENT_PROJECT" ]]; then
      echo "Usage: worktree-create-open <parent_project_name>" >&2
      exit 1
    fi

    # Feature 102: Get repo path from repos.json
    REPOS_FILE="$HOME/.config/i3/repos.json"
    REPO_PATH=""

    if [[ -f "$REPOS_FILE" ]]; then
      # Parse qualified name: account/repo
      REPO_ACCOUNT=$(echo "$PARENT_PROJECT" | cut -d'/' -f1)
      REPO_NAME=$(echo "$PARENT_PROJECT" | cut -d'/' -f2)

      # Get repo path for auto-populating worktree path
      REPO_PATH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" \
        '.repositories[] | select(.account == $acc and .name == $name) | .path // empty' "$REPOS_FILE")
    fi

    # Clear form fields and set parent project
    # Feature 114: Enable focus mode so form inputs are clickable
    $EWW_CMD update panel_focus_mode=true
    $EWW_CMD update worktree_creating=true
    $EWW_CMD update worktree_form_parent_project="$PARENT_PROJECT"
    $EWW_CMD update edit_form_icon="🌿"
    $EWW_CMD update edit_form_error=""

    # Feature 102: Store repo path for path auto-generation and description-to-branch conversion
    $EWW_CMD update worktree_form_repo_path="$REPO_PATH"

    # Clear fields - user enters description, branch name auto-generated
    $EWW_CMD update worktree_form_branch_name=""
    $EWW_CMD update worktree_form_description=""
    $EWW_CMD update worktree_form_path=""
    $EWW_CMD update edit_form_display_name=""

    # Also expand the parent project to show the form in context
    CURRENT=$($EWW_CMD get expanded_projects)
    if ! echo "$CURRENT" | ${pkgs.jq}/bin/jq -e "index(\"$PARENT_PROJECT\")" > /dev/null 2>&1; then
      NEW=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c ". + [\"$PARENT_PROJECT\"]")
      $EWW_CMD update "expanded_projects=$NEW"
    fi
  '';

  # Feature 102: Auto-populate worktree form fields based on description
  # Uses the same branch naming logic as .specify/scripts/bash/create-new-feature.sh
  worktreeAutoPopulateScript = pkgs.writeShellScriptBin "worktree-auto-populate" ''
    #!${pkgs.bash}/bin/bash
    # Auto-populate worktree form fields when description changes
    # Usage: worktree-auto-populate <description>

    DESCRIPTION="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$DESCRIPTION" ]]; then
      exit 0
    fi

    # Get stored repo path and parent project
    REPO_PATH=$($EWW_CMD get worktree_form_repo_path 2>/dev/null || echo "")
    PARENT_PROJECT=$($EWW_CMD get worktree_form_parent_project 2>/dev/null || echo "")

    # Function to generate branch suffix from description (same logic as create-new-feature.sh)
    generate_branch_suffix() {
      local description="$1"

      # Common stop words to filter out
      local stop_words="^(i|a|an|the|to|for|of|in|on|at|by|with|from|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|can|may|might|must|shall|this|that|these|those|my|your|our|their|want|need|add|get|set)$"

      # Convert to lowercase and split into words
      local clean_name=$(echo "$description" | tr '[:upper:]' '[:lower:]' | ${pkgs.gnused}/bin/sed 's/[^a-z0-9]/ /g')

      # Filter words: remove stop words and words shorter than 3 chars
      local meaningful_words=()
      for word in $clean_name; do
        [ -z "$word" ] && continue
        if ! echo "$word" | ${pkgs.gnugrep}/bin/grep -qiE "$stop_words"; then
          if [ ''${#word} -ge 3 ]; then
            meaningful_words+=("$word")
          fi
        fi
      done

      # Use first 3-4 meaningful words
      if [ ''${#meaningful_words[@]} -gt 0 ]; then
        local max_words=3
        if [ ''${#meaningful_words[@]} -eq 4 ]; then max_words=4; fi

        local result=""
        local count=0
        for word in "''${meaningful_words[@]}"; do
          if [ $count -ge $max_words ]; then break; fi
          if [ -n "$result" ]; then result="$result-"; fi
          result="$result$word"
          count=$((count + 1))
        done
        echo "$result"
      else
        # Fallback
        echo "$description" | tr '[:upper:]' '[:lower:]' | ${pkgs.gnused}/bin/sed 's/[^a-z0-9]/-/g' | ${pkgs.gnused}/bin/sed 's/-\+/-/g' | ${pkgs.gnused}/bin/sed 's/^-//' | ${pkgs.gnused}/bin/sed 's/-$//' | tr '-' '\n' | ${pkgs.gnugrep}/bin/grep -v '^$' | head -3 | tr '\n' '-' | ${pkgs.gnused}/bin/sed 's/-$//'
      fi
    }

    # Get next branch number from repos.json
    get_next_branch_number() {
      local repo_path="$1"
      local parent_project="$2"
      local repos_file="$HOME/.config/i3/repos.json"

      if [[ ! -f "$repos_file" ]]; then
        echo "100"
        return
      fi

      local repo_account=$(echo "$parent_project" | cut -d'/' -f1)
      local repo_name=$(echo "$parent_project" | cut -d'/' -f2)

      # Get max branch number from existing worktrees
      local max_number=$(${pkgs.jq}/bin/jq -r --arg acc "$repo_account" --arg name "$repo_name" \
        '.repositories[] | select(.account == $acc and .name == $name) | .worktrees[]?.branch // empty' "$repos_file" \
        | ${pkgs.gnugrep}/bin/grep -oE '^[0-9]+' | sort -n | tail -1)

      # Also check local branches in the repo
      if [[ -n "$repo_path" && -d "$repo_path" ]]; then
        local local_max=$(cd "$repo_path" && git branch 2>/dev/null | ${pkgs.gnugrep}/bin/grep -oE '^[* ]*[0-9]+' | ${pkgs.gnused}/bin/sed 's/[* ]*//' | sort -n | tail -1)
        if [[ -n "$local_max" && "$local_max" -gt "''${max_number:-0}" ]]; then
          max_number="$local_max"
        fi
      fi

      if [[ -n "$max_number" ]]; then
        echo $((max_number + 1))
      else
        echo "100"
      fi
    }

    # Generate branch suffix from description
    BRANCH_SUFFIX=$(generate_branch_suffix "$DESCRIPTION")

    # Get next available branch number
    NEXT_NUMBER=$(get_next_branch_number "$REPO_PATH" "$PARENT_PROJECT")
    FEATURE_NUM=$(printf "%03d" "$NEXT_NUMBER")

    # Construct full branch name
    BRANCH_NAME="''${FEATURE_NUM}-''${BRANCH_SUFFIX}"

    # Update branch name field
    $EWW_CMD update "worktree_form_branch_name=$BRANCH_NAME"

    # Auto-generate worktree path: <repo_path>/<branch_name>
    if [[ -n "$REPO_PATH" && -n "$BRANCH_NAME" ]]; then
      WORKTREE_PATH="''${REPO_PATH}/''${BRANCH_NAME}"
      $EWW_CMD update "worktree_form_path=$WORKTREE_PATH"
    fi

    # Auto-generate display name: NNN - Description (Title Case of original)
    TITLE_CASE=$(echo "$DESCRIPTION" | ${pkgs.gnused}/bin/sed 's/\b\(.\)/\u\1/g')
    DISPLAY_NAME="$FEATURE_NUM - $TITLE_CASE"
    $EWW_CMD update "edit_form_display_name=$DISPLAY_NAME"
  '';

  # Feature 102: Open worktree delete confirmation dialog
  worktreeDeleteOpenScript = pkgs.writeShellScriptBin "worktree-delete-open" ''
    #!${pkgs.bash}/bin/bash
    # Open worktree delete confirmation dialog
    # Usage: worktree-delete-open <qualified_name> <branch_name> <is_dirty>

    QUALIFIED_NAME="$1"
    BRANCH_NAME="$2"
    IS_DIRTY="$3"

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$QUALIFIED_NAME" ]]; then
      echo "Usage: worktree-delete-open <qualified_name> <branch_name> <is_dirty>" >&2
      exit 1
    fi

    # Set dialog state
    $EWW_CMD update worktree_delete_name="$QUALIFIED_NAME"
    $EWW_CMD update worktree_delete_branch="$BRANCH_NAME"
    $EWW_CMD update worktree_delete_is_dirty="$IS_DIRTY"
    $EWW_CMD update worktree_delete_dialog_visible=true
  '';

  # Feature 102: Confirm and execute worktree deletion
  worktreeDeleteConfirmScript = pkgs.writeShellScriptBin "worktree-delete-confirm" ''
    #!${pkgs.bash}/bin/bash
    # Execute worktree deletion after confirmation
    # Usage: worktree-delete-confirm

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get worktree to delete from dialog state
    QUALIFIED_NAME=$($EWW_CMD get worktree_delete_name)

    if [[ -z "$QUALIFIED_NAME" ]]; then
      echo "No worktree selected for deletion" >&2
      exit 1
    fi

    # Parse qualified name: account/repo:branch
    # e.g., vpittamp/nixos-config:101-worktree-click-switch
    REPO_QUALIFIED=$(echo "$QUALIFIED_NAME" | cut -d':' -f1)
    BRANCH_NAME=$(echo "$QUALIFIED_NAME" | cut -d':' -f2)
    REPO_ACCOUNT=$(echo "$REPO_QUALIFIED" | cut -d'/' -f1)
    REPO_NAME=$(echo "$REPO_QUALIFIED" | cut -d'/' -f2)

    # Get repo path from repos.json
    REPOS_FILE="$HOME/.config/i3/repos.json"
    if [[ ! -f "$REPOS_FILE" ]]; then
      $EWW_CMD update error_notification="repos.json not found"
      $EWW_CMD update error_notification_visible=true
      $EWW_CMD update worktree_delete_dialog_visible=false
      exit 1
    fi

    REPO_PATH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .path // empty' "$REPOS_FILE")

    if [[ -z "$REPO_PATH" ]]; then
      $EWW_CMD update error_notification="Repository not found: $REPO_QUALIFIED"
      $EWW_CMD update error_notification_visible=true
      $EWW_CMD update worktree_delete_dialog_visible=false
      exit 1
    fi

    # Get worktree path
    WORKTREE_PATH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" --arg branch "$BRANCH_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .worktrees[]? | select(.branch == $branch) | .path // empty' "$REPOS_FILE")

    if [[ -z "$WORKTREE_PATH" ]]; then
      $EWW_CMD update error_notification="Worktree not found: $BRANCH_NAME"
      $EWW_CMD update error_notification_visible=true
      $EWW_CMD update worktree_delete_dialog_visible=false
      exit 1
    fi

    # Execute git worktree remove
    cd "$REPO_PATH" || {
      $EWW_CMD update error_notification="Cannot access repo: $REPO_PATH"
      $EWW_CMD update error_notification_visible=true
      $EWW_CMD update worktree_delete_dialog_visible=false
      exit 1
    }

    # Force remove the worktree (--force handles dirty worktrees after user confirmation)
    if ! git worktree remove --force "$WORKTREE_PATH" 2>&1; then
      $EWW_CMD update error_notification="Failed to remove worktree: $BRANCH_NAME"
      $EWW_CMD update error_notification_visible=true
      $EWW_CMD update worktree_delete_dialog_visible=false
      exit 1
    fi

    # Trigger rediscovery to update repos.json
    i3pm discover >/dev/null 2>&1 || true

    # Close dialog and show success
    $EWW_CMD update worktree_delete_dialog_visible=false
    $EWW_CMD update worktree_delete_name=""
    $EWW_CMD update worktree_delete_branch=""
    $EWW_CMD update worktree_delete_is_dirty=false
    $EWW_CMD update success_notification="Worktree '$BRANCH_NAME' deleted successfully"
    $EWW_CMD update success_notification_visible=true
    (sleep 3 && $EWW_CMD update success_notification_visible=false success_notification="") &

    echo "Worktree deleted: $QUALIFIED_NAME"
  '';

  # Feature 102: Cancel worktree deletion
  worktreeDeleteCancelScript = pkgs.writeShellScriptBin "worktree-delete-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel worktree delete dialog
    # Usage: worktree-delete-cancel

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    $EWW_CMD update worktree_delete_dialog_visible=false
    $EWW_CMD update worktree_delete_name=""
    $EWW_CMD update worktree_delete_branch=""
    $EWW_CMD update worktree_delete_is_dirty=false
  '';

  # Feature 102: Validate branch name and check for duplicates
  worktreeValidateBranchScript = pkgs.writeShellScriptBin "worktree-validate-branch" ''
    #!${pkgs.bash}/bin/bash
    # Validate branch name for worktree creation
    # Usage: worktree-validate-branch <branch_name> <parent_project>
    # Returns: JSON with validation result

    BRANCH_NAME="$1"
    PARENT_PROJECT="$2"
    REPOS_FILE="$HOME/.config/i3/repos.json"

    # Validate branch name pattern (should be NNN-description)
    if [[ ! "$BRANCH_NAME" =~ ^[0-9]+-[a-z0-9-]+$ ]]; then
      echo '{"valid": false, "error": "Branch name must match pattern: NNN-description (e.g., 103-new-feature)"}'
      exit 0
    fi

    # Check for existing branch with same name
    if [[ -f "$REPOS_FILE" ]]; then
      REPO_ACCOUNT=$(echo "$PARENT_PROJECT" | cut -d'/' -f1)
      REPO_NAME=$(echo "$PARENT_PROJECT" | cut -d'/' -f2)

      EXISTING=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" --arg branch "$BRANCH_NAME" \
        '.repositories[] | select(.account == $acc and .name == $name) | .worktrees[]? | select(.branch == $branch) | .branch' "$REPOS_FILE")

      if [[ -n "$EXISTING" ]]; then
        echo "{\"valid\": false, \"error\": \"Branch '$BRANCH_NAME' already exists as a worktree\"}"
        exit 0
      fi
    fi

    echo '{"valid": true, "error": ""}'
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

    # Feature 114: Enable focus mode so form inputs are clickable
    $EWW_CMD update panel_focus_mode=true

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

    # Feature 096 T022: Set loading state to prevent double-submit
    $EWW update save_in_progress=true

    # Read form values from Eww variables
    BRANCH_NAME=$($EWW get worktree_form_branch_name)
    WORKTREE_PATH=$($EWW get worktree_form_path)
    PARENT_PROJECT=$($EWW get worktree_form_parent_project)
    DISPLAY_NAME=$($EWW get edit_form_display_name)
    ICON=$($EWW get edit_form_icon)
    SETUP_SPECKIT=$($EWW get worktree_form_speckit)  # Feature 112: Speckit scaffolding

    # Validate required fields
    if [[ -z "$BRANCH_NAME" ]]; then
      $EWW update edit_form_error="Branch name is required"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Branch name is required"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi
    if [[ -z "$WORKTREE_PATH" ]]; then
      $EWW update edit_form_error="Worktree path is required"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Worktree path is required"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi
    if [[ -z "$PARENT_PROJECT" ]]; then
      $EWW update edit_form_error="Parent project is required"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Parent project is required"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # Feature 102: Validate branch name format (NNN-description pattern)
    if [[ ! "$BRANCH_NAME" =~ ^[0-9]+-[a-z0-9-]+$ ]]; then
      $EWW update edit_form_error="Branch name must match pattern: NNN-description (e.g., 103-new-feature)"
      $EWW update error_notification="Invalid branch name format"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # Feature 101: Get parent project directory from repos.json
    # PARENT_PROJECT is now a qualified name: account/repo (e.g., vpittamp/nixos-config)
    REPOS_FILE="$HOME/.config/i3/repos.json"
    if [[ ! -f "$REPOS_FILE" ]]; then
      $EWW update edit_form_error="repos.json not found. Run 'i3pm discover' first."
      $EWW update error_notification="repos.json not found. Run 'i3pm discover' first."
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # Parse qualified name: account/repo
    REPO_ACCOUNT=$(echo "$PARENT_PROJECT" | cut -d'/' -f1)
    REPO_NAME=$(echo "$PARENT_PROJECT" | cut -d'/' -f2)

    # Find repo in repos.json
    PARENT_DIR=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .path // empty' "$REPOS_FILE")
    if [[ -z "$PARENT_DIR" ]]; then
      $EWW update edit_form_error="Repository not found: $PARENT_PROJECT"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Repository not found: $PARENT_PROJECT"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # Feature 102: Check for duplicate branch name (worktree already exists)
    EXISTING_BRANCH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" --arg branch "$BRANCH_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .worktrees[]? | select(.branch == $branch) | .branch // empty' "$REPOS_FILE")
    if [[ -n "$EXISTING_BRANCH" ]]; then
      $EWW update edit_form_error="Branch '$BRANCH_NAME' already exists as a worktree"
      $EWW update error_notification="Worktree already exists: $BRANCH_NAME"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # Check if worktree path already exists
    if [[ -e "$WORKTREE_PATH" ]]; then
      $EWW update edit_form_error="Path already exists: $WORKTREE_PATH"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Path already exists: $WORKTREE_PATH"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # Create Git worktree
    cd "$PARENT_DIR" || {
      $EWW update edit_form_error="Cannot change to parent directory: $PARENT_DIR"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Cannot change to parent directory: $PARENT_DIR"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    }

    # Try to create worktree (branch must exist or use -b to create)
    if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
      # Branch exists
      if ! git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1; then
        $EWW update edit_form_error="Git worktree add failed"
        # Feature 096 T024: Show error notification
        $EWW update error_notification="Git worktree add failed for branch: $BRANCH_NAME"
        $EWW update error_notification_visible=true
        $EWW update save_in_progress=false
        exit 1
      fi
    else
      # Branch doesn't exist - create it
      if ! git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" 2>&1; then
        $EWW update edit_form_error="Git worktree add failed (new branch)"
        # Feature 096 T024: Show error notification
        $EWW update error_notification="Failed to create new branch: $BRANCH_NAME"
        $EWW update error_notification_visible=true
        $EWW update save_in_progress=false
        exit 1
      fi
    fi

    # Feature 101: Generate qualified worktree name
    # Format: account/repo:branch (e.g., vpittamp/nixos-config:101-worktree-click-switch)
    WORKTREE_NAME="''${PARENT_PROJECT}:''${BRANCH_NAME}"
    if [[ -z "$DISPLAY_NAME" ]]; then
      DISPLAY_NAME="$BRANCH_NAME"
    fi

    # Feature 101: Trigger rediscovery to pick up the new worktree
    # The git worktree add above created the worktree, now repos.json needs to be updated
    if ! i3pm discover >/dev/null 2>&1; then
      $EWW update edit_form_error="Failed to update repos.json"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Worktree created but repos.json refresh failed"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      # Note: Don't remove the git worktree - it was successfully created
      exit 1
    fi

    # Feature 112: Create speckit directory structure if enabled
    if [[ "$SETUP_SPECKIT" == "true" ]]; then
      SPECS_DIR="$WORKTREE_PATH/specs/$BRANCH_NAME"
      if mkdir -p "$SPECS_DIR/checklists" 2>/dev/null; then
        echo "Created speckit directory: $SPECS_DIR"
      else
        # Non-fatal warning - worktree was successfully created
        echo "Warning: Failed to create speckit directory: $SPECS_DIR"
      fi
    fi

    # Success: clear form state and refresh
    # Feature 114: Disable focus mode to return to click-through
    $EWW update panel_focus_mode=false
    $EWW update worktree_creating=false
    $EWW update worktree_form_description=""
    $EWW update worktree_form_branch_name=""
    $EWW update worktree_form_path=""
    $EWW update worktree_form_parent_project=""
    $EWW update worktree_form_repo_path=""
    $EWW update worktree_form_speckit=true  # Feature 112: Reset to default (checked)
    $EWW update edit_form_display_name=""
    $EWW update edit_form_icon=""
    $EWW update edit_form_error=""

    # Note: Project list will be refreshed by the deflisten stream automatically

    # Feature 096 T023: Show success notification
    $EWW update success_notification="Worktree '$WORKTREE_NAME' created successfully"
    $EWW update success_notification_visible=true
    # Auto-dismiss after 3 seconds (T020)
    (sleep 3 && $EWW update success_notification_visible=false success_notification="") &

    # Feature 096 T022: Clear loading state
    $EWW update save_in_progress=false

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

    # Feature 096 T022: Set loading state
    $EWW update save_in_progress=true

    # Feature 101: User confirmed - proceed with deletion using repos.json
    # PROJECT_NAME is now a qualified name: account/repo:branch
    REPOS_FILE="$HOME/.config/i3/repos.json"
    if [[ ! -f "$REPOS_FILE" ]]; then
      $EWW update edit_form_error="repos.json not found"
      $EWW update error_notification="repos.json not found. Run 'i3pm discover' first."
      $EWW update error_notification_visible=true
      $EWW update worktree_delete_confirm=""
      $EWW update save_in_progress=false
      exit 1
    fi

    # Parse qualified name: account/repo:branch
    REPO_PART=$(echo "$PROJECT_NAME" | cut -d':' -f1)
    BRANCH_NAME=$(echo "$PROJECT_NAME" | cut -d':' -f2)
    REPO_ACCOUNT=$(echo "$REPO_PART" | cut -d'/' -f1)
    REPO_NAME=$(echo "$REPO_PART" | cut -d'/' -f2)

    # Find worktree in repos.json
    WORKTREE_PATH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" --arg branch "$BRANCH_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .worktrees[] | select(.branch == $branch) | .path // empty' "$REPOS_FILE")
    PARENT_DIR=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .path // empty' "$REPOS_FILE")

    if [[ -z "$WORKTREE_PATH" ]]; then
      $EWW update edit_form_error="Worktree not found: $PROJECT_NAME"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Worktree not found: $PROJECT_NAME"
      $EWW update error_notification_visible=true
      $EWW update worktree_delete_confirm=""
      $EWW update save_in_progress=false
      exit 1
    fi

    # Get parent directory for git worktree removal
    GIT_CLEANUP_WARNING=""
    if [[ -n "$PARENT_DIR" ]] && [[ -d "$PARENT_DIR" ]]; then
      cd "$PARENT_DIR"
      # Remove git worktree (use --force if dirty)
      if ! git worktree remove "$WORKTREE_PATH" --force 2>/dev/null; then
        GIT_CLEANUP_WARNING=" (Git cleanup may have failed)"
      fi
    fi

    # Feature 101: Trigger rediscovery to update repos.json
    # The git worktree remove above already deleted the worktree
    # Now we just need to refresh repos.json via discovery
    if ! i3pm discover >/dev/null 2>&1; then
      # Non-fatal warning - worktree was still deleted
      GIT_CLEANUP_WARNING="$GIT_CLEANUP_WARNING (repos.json refresh may have failed)"
    fi

    # Success: clear state and refresh
    $EWW update worktree_delete_confirm=""
    $EWW update edit_form_error=""

    # Note: Project list will be refreshed by the deflisten stream automatically

    # Feature 096 T023: Show success notification (with optional warning)
    if [[ -n "$GIT_CLEANUP_WARNING" ]]; then
      $EWW update warning_notification="Worktree '$PROJECT_NAME' deleted$GIT_CLEANUP_WARNING"
      $EWW update warning_notification_visible=true
      (sleep 5 && $EWW update warning_notification_visible=false warning_notification="") &
    else
      $EWW update success_notification="Worktree '$PROJECT_NAME' deleted successfully"
      $EWW update success_notification_visible=true
      (sleep 3 && $EWW update success_notification_visible=false success_notification="") &
    fi

    # Feature 096 T022: Clear loading state
    $EWW update save_in_progress=false

    echo "Worktree deleted successfully: $PROJECT_NAME"
  '';

  # Feature 099 T015: Toggle project expand/collapse script
  toggleProjectExpandedScript = pkgs.writeShellScriptBin "toggle-project-expanded" ''
    #!${pkgs.bash}/bin/bash
    # Toggle expand/collapse state for a repository project
    # Usage: toggle-project-expanded <project-name>

    PROJECT_NAME="$1"
    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "Usage: toggle-project-expanded <project-name>" >&2
      exit 1
    fi

    # Get current expanded projects state
    CURRENT=$($EWW get expanded_projects)

    # Handle "all" case - when all expanded, clicking collapses just this one
    if [[ "$CURRENT" == "all" ]]; then
      # Get all project names and remove the clicked one
      ALL_NAMES=$($EWW get projects_data | ${pkgs.jq}/bin/jq -r '[.repositories[]?.qualified_name // empty, .projects[]?.name // empty] | unique')
      NEW=$(echo "$ALL_NAMES" | ${pkgs.jq}/bin/jq -c "del(.[] | select(. == \"$PROJECT_NAME\"))")
      $EWW update "expanded_projects=$NEW" "projects_all_expanded=false"
    elif echo "$CURRENT" | ${pkgs.jq}/bin/jq -e "index(\"$PROJECT_NAME\")" > /dev/null 2>&1; then
      # Remove from array (collapse)
      NEW=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c "del(.[] | select(. == \"$PROJECT_NAME\"))")
      $EWW update "expanded_projects=$NEW"
    else
      # Add to array (expand)
      NEW=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c ". + [\"$PROJECT_NAME\"]")
      $EWW update "expanded_projects=$NEW"
    fi
  '';

  # Feature 099 UX3: Expand/collapse all repositories script
  toggleExpandAllScript = pkgs.writeShellScriptBin "toggle-expand-all-projects" ''
    #!${pkgs.bash}/bin/bash
    # Toggle expand/collapse all repositories
    # Usage: toggle-expand-all-projects

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get current all_expanded state
    CURRENT_STATE=$($EWW get projects_all_expanded)

    if [[ "$CURRENT_STATE" == "true" ]]; then
      # Currently expanded, collapse all
      $EWW update projects_all_expanded=false
      $EWW update 'expanded_projects=[]'
    else
      # Currently collapsed, expand all - use "all" marker
      $EWW update projects_all_expanded=true
      $EWW update 'expanded_projects=all'
    fi
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

    # Feature 096 T022: Set loading state to prevent double-submit
    $EWW update save_in_progress=true

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
    CONFLICT=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.conflict // false')

    if [[ "$STATUS" == "success" ]]; then
      # Feature 096 T010: Handle conflicts as warnings, not errors
      if [[ "$CONFLICT" == "true" ]]; then
        $EWW update warning_notification="File was modified externally - your changes were saved (last write wins)"
        $EWW update warning_notification_visible=true
        (sleep 5 && $EWW update warning_notification_visible=false warning_notification="") &
      fi

      # Success: clear editing state and refresh
      # Feature 114: Disable focus mode to return to click-through
      $EWW update panel_focus_mode=false
      $EWW update editing_project_name=""
      $EWW update edit_form_error=""

      # Note: Project list will be refreshed by the deflisten stream automatically

      # Feature 096 T023: Show success notification
      $EWW update success_notification="Worktree saved successfully"
      $EWW update success_notification_visible=true
      (sleep 3 && $EWW update success_notification_visible=false success_notification="") &

      # Feature 096 T022: Clear loading state
      $EWW update save_in_progress=false

      echo "Worktree saved successfully"
    else
      ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error // "Unknown error"')
      $EWW update edit_form_error="$ERROR"

      # Feature 096 T024: Show error notification
      $EWW update error_notification="Failed to save worktree: $ERROR"
      $EWW update error_notification_visible=true

      # Feature 096 T022: Clear loading state
      $EWW update save_in_progress=false

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

    # Feature 114: Enable focus mode so form inputs are clickable
    $EWW_CMD update panel_focus_mode=true

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

    # Feature 096 T022: Set loading state to prevent double-submit
    $EWW update save_in_progress=true

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
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Project name is required"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    if [[ -z "$WORKING_DIR" ]]; then
      $EWW update create_form_error="Working directory is required"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Working directory is required"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
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
    export PYTHONPATH="${../tools}:${../tools/monitoring-panel}"
    RESULT=$(${pythonForBackend}/bin/python3 <<EOF
import asyncio
import json
import sys
sys.path.insert(0, "${../tools}")
sys.path.insert(0, "${../tools/monitoring-panel}")
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
      # Feature 114: Disable focus mode to return to click-through
      $EWW update panel_focus_mode=false
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

      # Note: Project list will be refreshed by the deflisten stream automatically
      # Skipping manual refresh to avoid issues with large JSON payloads in eww update

      # Feature 096 T023: Show success notification
      $EWW update success_notification="Project '$NAME' created successfully"
      $EWW update success_notification_visible=true
      # Auto-dismiss after 3 seconds (T020)
      (sleep 3 && $EWW update success_notification_visible=false success_notification="") &

      # Feature 096 T022: Clear loading state
      $EWW update save_in_progress=false

      echo "Project created successfully: $NAME"
    else
      # Show error message
      ERROR_MSG=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error_message')
      VALIDATION_ERRORS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors | length')

      if [[ "$VALIDATION_ERRORS" -gt 0 ]]; then
        FIRST_ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors[0]')
        $EWW update create_form_error="$FIRST_ERROR"
        # Feature 096 T024: Show error notification
        $EWW update error_notification="Validation error: $FIRST_ERROR"
        $EWW update error_notification_visible=true
      elif [[ -n "$ERROR_MSG" ]] && [[ "$ERROR_MSG" != "null" ]]; then
        $EWW update create_form_error="$ERROR_MSG"
        # Feature 096 T024: Show error notification
        $EWW update error_notification="$ERROR_MSG"
        $EWW update error_notification_visible=true
      else
        $EWW update create_form_error="Failed to create project"
        # Feature 096 T024: Show error notification
        $EWW update error_notification="Failed to create project"
        $EWW update error_notification_visible=true
      fi

      # Feature 096 T022: Clear loading state on error
      $EWW update save_in_progress=false

      exit 1
    fi
  '';

  # Feature 094 US3: Project create form cancel handler (T066)
  projectCreateCancelScript = pkgs.writeShellScriptBin "project-create-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel project create form
    # Usage: project-create-cancel

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Feature 114: Disable focus mode to return to click-through
    $EWW update panel_focus_mode=false

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

    # Feature 114: Enable focus mode so form inputs are clickable
    $EWW_CMD update panel_focus_mode=true

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
      # Feature 114: Disable focus mode to return to click-through
      $EWW update panel_focus_mode=false
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

    # Feature 114: Disable focus mode to return to click-through
    $EWW update panel_focus_mode=false

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
    export PYTHONPATH="${../tools}:${../tools/monitoring-panel}"
    RESULT=$(echo "$REQUEST" | ${pythonForBackend}/bin/python3 -c "
import sys
sys.path.insert(0, '${../tools}')
sys.path.insert(0, '${../tools/monitoring-panel}')
from project_crud_handler import ProjectCRUDHandler
import asyncio
import json

handler = ProjectCRUDHandler()
request = json.loads(sys.stdin.read())
result = asyncio.run(handler.handle_request(request))
print(json.dumps(result))
")

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

      # Note: Project list will be refreshed by the deflisten stream automatically

      # Feature 096 T023: Show success notification via eww (consistent with create/edit)
      $EWW update success_notification="Project '$PROJECT_NAME' deleted successfully"
      $EWW update success_notification_visible=true
      # Auto-dismiss after 3 seconds (T020)
      (sleep 3 && $EWW update success_notification_visible=false success_notification="") &

      echo "Project deleted successfully: $PROJECT_NAME"
    else
      # Show error in dialog
      ERROR_MSG=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error_message')
      $EWW update delete_error="$ERROR_MSG"

      # Feature 096 T024: Show error notification via eww
      $EWW update error_notification="Delete failed: $ERROR_MSG"
      $EWW update error_notification_visible=true

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
    export PYTHONPATH="${../tools}:${../tools/monitoring-panel}"
    RESULT=$(echo "$REQUEST" | ${pythonForBackend}/bin/python3 -c "
import sys
sys.path.insert(0, '${../tools}')
sys.path.insert(0, '${../tools/monitoring-panel}')
from app_crud_handler import AppCRUDHandler
import asyncio
import json

handler = AppCRUDHandler()
request = json.loads(sys.stdin.read())
result = asyncio.run(handler.handle_request(request))
print(json.dumps(result))
")

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

    # Get current project (T012) - Read from active-worktree.json (Feature 101 single source of truth)
    CURRENT_PROJECT=$(${pkgs.jq}/bin/jq -r '.qualified_name // "global"' "$HOME/.config/i3/active-worktree.json" 2>/dev/null || echo "global")

    # Conditional project switch (T013)
    if [[ "$PROJECT_NAME" != "$CURRENT_PROJECT" ]]; then
        if ! i3pm worktree switch "$PROJECT_NAME"; then
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

    # Get current project (T019) - Read from active-worktree.json (Feature 101 single source of truth)
    CURRENT_PROJECT=$(${pkgs.jq}/bin/jq -r '.qualified_name // "global"' "$HOME/.config/i3/active-worktree.json" 2>/dev/null || echo "global")

    # Check if already in target project
    if [[ "$PROJECT_NAME" == "$CURRENT_PROJECT" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Already in project $PROJECT_NAME"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="$PROJECT_NAME"
        (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="") &
        exit 0
    fi

    # Execute project switch (T020)
    if i3pm worktree switch "$PROJECT_NAME"; then
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

  # Close worktree action script - closes all windows for a specific project/worktree
  # Feature 119: Improved close worktree script with rate limiting and error handling
  closeWorktreeScript = pkgs.writeShellScriptBin "close-worktree-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 119: Close all windows belonging to a specific worktree/project
    # Improved with rate limiting, error handling, and state validation
    set -euo pipefail

    PROJECT_NAME="''${1:-}"

    # Validate input
    if [[ -z "$PROJECT_NAME" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Close Worktree Failed" "No project name provided"
        exit 1
    fi

    # Feature 119: Rate limiting instead of lock file (1 second debounce for batch operations)
    LOCK_FILE="/tmp/eww-close-worktree-''${PROJECT_NAME//\//_}.lock"
    CURRENT_TIME=$(date +%s%N)

    if [[ -f "$LOCK_FILE" ]]; then
        LAST_TIME=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        TIME_DIFF=$(( (CURRENT_TIME - LAST_TIME) / 1000000000 ))  # Convert to seconds
        if [[ $TIME_DIFF -lt 1 ]]; then
            # Within rate limit window, silently ignore
            exit 0
        fi
    fi

    # Update lock file with current timestamp
    echo "$CURRENT_TIME" > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT

    # Get all window IDs with marks matching this project
    # Feature 119: Marks are in format: scoped:<app_name>:<project_name>:<window_id>
    # The regex must skip the app name component between scoped: and project name
    WINDOW_IDS=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r --arg proj "$PROJECT_NAME" '
      .. | objects | select(.marks? != null) |
      select(.marks | map(test("^scoped:[^:]+:" + $proj + ":")) | any) |
      .id
    ' 2>/dev/null || echo "")

    if [[ -z "$WINDOW_IDS" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Close Worktree" "No windows found for $PROJECT_NAME"
        exit 0
    fi

    # Count windows to close
    WINDOW_COUNT=$(echo "$WINDOW_IDS" | wc -l)

    # Feature 119: Close each window with explicit error handling
    CLOSED=0
    FAILED=0
    for WID in $WINDOW_IDS; do
        if ${pkgs.sway}/bin/swaymsg "[con_id=$WID] kill" 2>/dev/null; then
            ((CLOSED++)) || true
        else
            ((FAILED++)) || true
            # Log failure but continue
            echo "Failed to close window $WID" >&2
        fi
    done

    # Feature 119: Re-query sway tree to confirm close
    sleep 0.2  # Brief wait for window close to propagate
    REMAINING=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r --arg proj "$PROJECT_NAME" '
      .. | objects | select(.marks? != null) |
      select(.marks | map(test("^scoped:" + $proj + ":")) | any) |
      .id
    ' 2>/dev/null | wc -l || echo "0")

    # Feature 119: Send notification with actual close count
    if [[ "$REMAINING" -gt 0 ]]; then
        ${pkgs.libnotify}/bin/notify-send -u normal "Worktree Closed" \
            "Closed $CLOSED/$WINDOW_COUNT windows for $PROJECT_NAME\n$REMAINING windows still open"
    else
        ${pkgs.libnotify}/bin/notify-send -u normal "Worktree Closed" \
            "Closed all $CLOSED windows for $PROJECT_NAME"
    fi
  '';

  # Feature 119: Improved close all windows script with rate limiting and error handling
  closeAllWindowsScript = pkgs.writeShellScriptBin "close-all-windows-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 119: Close all windows tracked by the monitoring panel
    # Improved with rate limiting, error handling, and state validation
    set -euo pipefail

    # Feature 119: Rate limiting instead of lock file (1 second debounce)
    LOCK_FILE="/tmp/eww-close-all-windows.lock"
    CURRENT_TIME=$(date +%s%N)

    if [[ -f "$LOCK_FILE" ]]; then
        LAST_TIME=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        TIME_DIFF=$(( (CURRENT_TIME - LAST_TIME) / 1000000000 ))  # Convert to seconds
        if [[ $TIME_DIFF -lt 1 ]]; then
            # Within rate limit window, silently ignore
            exit 0
        fi
    fi

    # Update lock file with current timestamp
    echo "$CURRENT_TIME" > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT

    # Get all window IDs with i3pm marks (scoped windows)
    WINDOW_IDS=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '
      .. | objects | select(.marks? != null) |
      select(.marks | map(startswith("scoped:")) | any) |
      .id
    ' 2>/dev/null || echo "")

    if [[ -z "$WINDOW_IDS" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Close All" "No scoped windows to close"
        exit 0
    fi

    # Count windows to close
    WINDOW_COUNT=$(echo "$WINDOW_IDS" | wc -l)

    # Feature 119: Close each window with explicit error handling
    CLOSED=0
    FAILED=0
    for WID in $WINDOW_IDS; do
        if ${pkgs.sway}/bin/swaymsg "[con_id=$WID] kill" 2>/dev/null; then
            ((CLOSED++)) || true
        else
            ((FAILED++)) || true
            echo "Failed to close window $WID" >&2
        fi
    done

    # Feature 119: Re-query sway tree to confirm close
    sleep 0.2  # Brief wait for window close to propagate
    REMAINING=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '
      .. | objects | select(.marks? != null) |
      select(.marks | map(startswith("scoped:")) | any) |
      .id
    ' 2>/dev/null | wc -l || echo "0")

    # Feature 119: Send notification with actual close count
    if [[ "$REMAINING" -gt 0 ]]; then
        ${pkgs.libnotify}/bin/notify-send -u normal "All Windows Closed" \
            "Closed $CLOSED/$WINDOW_COUNT scoped windows\n$REMAINING windows still open"
    else
        ${pkgs.libnotify}/bin/notify-send -u normal "All Windows Closed" \
            "Closed all $CLOSED scoped windows"
    fi
  '';

  # Feature 119: Close individual window script with rate limiting
  # Prevents double-click race conditions and handles missing windows gracefully
  closeWindowScript = pkgs.writeShellScriptBin "close-window-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 119: Close individual window with rate limiting and error handling
    set -euo pipefail

    WINDOW_ID="''${1:-}"

    # Validate input
    if [[ -z "$WINDOW_ID" ]] || [[ "$WINDOW_ID" == "0" ]]; then
        exit 1
    fi

    # Rate limiting: Use lock file with timestamp check (200ms debounce)
    LOCK_FILE="/tmp/eww-close-window-''${WINDOW_ID}.lock"
    CURRENT_TIME=$(date +%s%N)

    if [[ -f "$LOCK_FILE" ]]; then
        LAST_TIME=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        TIME_DIFF=$(( (CURRENT_TIME - LAST_TIME) / 1000000 ))  # Convert to ms
        if [[ $TIME_DIFF -lt 200 ]]; then
            # Within rate limit window, silently ignore
            exit 0
        fi
    fi

    # Update lock file with current timestamp
    echo "$CURRENT_TIME" > "$LOCK_FILE"

    # Clear context menu state first (optimistic update)
    ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=0 &

    # Check if window still exists before trying to close
    WINDOW_EXISTS=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r --arg id "$WINDOW_ID" '
        .. | objects | select(.type=="con") | select(.id == ($id | tonumber)) | .id
    ' 2>/dev/null | head -1 || echo "")

    if [[ -z "$WINDOW_EXISTS" ]]; then
        # Window already gone, just clean up state
        rm -f "$LOCK_FILE"
        exit 0
    fi

    # Close the window
    if ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] kill" 2>/dev/null; then
        # Success - clean up lock file after brief delay
        (sleep 0.5 && rm -f "$LOCK_FILE") &
        exit 0
    else
        # Failed to close - clean up lock file
        rm -f "$LOCK_FILE"
        exit 1
    fi
  '';

  # Toggle context menu for project in Windows view
  toggleProjectContextScript = pkgs.writeShellScriptBin "toggle-project-context" ''
    #!${pkgs.bash}/bin/bash
    # Toggle the project context menu in monitoring panel
    PROJECT_NAME="''${1:-}"
    if [[ -z "$PROJECT_NAME" ]]; then
        exit 1
    fi

    # Get current value
    CURRENT=$(${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel get context_menu_project 2>/dev/null || echo "")

    if [[ "$CURRENT" == "$PROJECT_NAME" ]]; then
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update context_menu_project='''
    else
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update "context_menu_project=$PROJECT_NAME"
    fi
  '';

  # Toggle individual project expand/collapse in Windows view
  # Handles: "all" mode (switch to array), array mode (add/remove project)
  toggleWindowsProjectExpandScript = pkgs.writeShellScriptBin "toggle-windows-project-expand" ''
    #!${pkgs.bash}/bin/bash
    # Toggle individual project expand/collapse state
    PROJECT_NAME="''${1:-}"
    if [[ -z "$PROJECT_NAME" ]]; then
        exit 1
    fi

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get current state
    CURRENT=$($EWW get windows_expanded_projects 2>/dev/null || echo "all")

    if [[ "$CURRENT" == "all" ]]; then
        # Currently all expanded - clicking collapses this one only
        # Get all project names and remove the clicked one
        ALL_PROJECTS=$($EWW get monitoring_data 2>/dev/null | ${pkgs.jq}/bin/jq -r '[.projects[].name]')
        NEW_LIST=$(echo "$ALL_PROJECTS" | ${pkgs.jq}/bin/jq -c --arg name "$PROJECT_NAME" '[.[] | select(. != $name)]')
        $EWW update "windows_expanded_projects=$NEW_LIST" "windows_all_expanded=false"
    else
        # Array mode - toggle this project in/out
        IS_EXPANDED=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -e --arg name "$PROJECT_NAME" '. | index($name) != null' 2>/dev/null || echo "false")

        if [[ "$IS_EXPANDED" == "true" ]]; then
            # Remove from array
            NEW_LIST=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c --arg name "$PROJECT_NAME" '[.[] | select(. != $name)]')
        else
            # Add to array
            NEW_LIST=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c --arg name "$PROJECT_NAME" '. + [$name]')
        fi

        # Check if all projects are now expanded
        PROJECT_COUNT=$($EWW get monitoring_data 2>/dev/null | ${pkgs.jq}/bin/jq '.projects | length')
        EXPANDED_COUNT=$(echo "$NEW_LIST" | ${pkgs.jq}/bin/jq 'length')

        if [[ "$EXPANDED_COUNT" -ge "$PROJECT_COUNT" ]]; then
            # All expanded - switch to "all" mode
            $EWW update "windows_expanded_projects=all" "windows_all_expanded=true"
        else
            $EWW update "windows_expanded_projects=$NEW_LIST" "windows_all_expanded=false"
        fi
    fi
  '';

  # SwayNC toggle wrapper - DISABLED pending removal
  # Notification center is being removed, so this is now a no-op
  swayNCToggleScript = pkgs.writeShellScriptBin "toggle-swaync" ''
    #!${pkgs.bash}/bin/bash
    # DISABLED: Notification center is being removed
    # This is now a no-op to prevent any interaction
    exit 0
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
    current_view_index=$($EWW_CMD get current_view_index 2>/dev/null || echo "0")
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

  # Feature 099 UX2: Projects tab keyboard navigation script
  projectsNavScript = pkgs.writeShellScriptBin "projects-nav" ''
    #!${pkgs.bash}/bin/bash
    # Feature 099 UX2: Handle keyboard navigation within Projects tab
    # Usage: projects-nav <action>
    # Actions: down, up, select, expand, edit, delete, copy, new

    ACTION="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get current state
    current_index=$($EWW_CMD get project_selected_index 2>/dev/null || echo "-1")
    filter_text=$($EWW_CMD get project_filter 2>/dev/null || echo "")

    # Get filtered project list
    projects_data=$($EWW_CMD get projects_data 2>/dev/null)

    # Build combined list: main projects + worktrees (matching filter)
    # Each entry: { name, type: "project"|"worktree", parent?, index }
    all_items=$(echo "$projects_data" | ${pkgs.jq}/bin/jq -c --arg filter "$filter_text" '
      def matches_filter:
        if $filter == "" then true
        else
          (.name | ascii_downcase | contains($filter | ascii_downcase)) or
          ((.display_name // "") | ascii_downcase | contains($filter | ascii_downcase)) or
          ((.branch_name // "") | ascii_downcase | contains($filter | ascii_downcase))
        end;

      [
        (.main_projects // [])[] |
        select(matches_filter) |
        {name, type: "project", display_name, directory}
      ] +
      [
        (.worktrees // [])[] |
        select(matches_filter) |
        {name, type: "worktree", parent: .parent_project, display_name, directory}
      ]
    ')

    max_items=$(echo "$all_items" | ${pkgs.jq}/bin/jq 'length')

    # If no items, skip navigation
    if [ "$max_items" -eq 0 ]; then
      exit 0
    fi

    # Helper function to update selection by index
    update_selection() {
      local idx=$1
      local name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson i "$idx" '.[$i].name // ""')
      $EWW_CMD update project_selected_index=$idx
      $EWW_CMD update "project_selected_name=$name"
    }

    case "$ACTION" in
      down|j)
        new_index=$((current_index + 1))
        if [ "$new_index" -ge "$max_items" ]; then
          new_index=$((max_items - 1))
        fi
        update_selection $new_index
        ;;
      up|k)
        new_index=$((current_index - 1))
        if [ "$new_index" -lt 0 ]; then
          new_index=0
        fi
        update_selection $new_index
        ;;
      first|g)
        update_selection 0
        ;;
      last|G)
        update_selection $((max_items - 1))
        ;;
      select|enter)
        # Switch to selected project
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            i3pm worktree switch "$project_name"
            # Exit panel mode after switching
            exit-monitor-mode
          fi
        fi
        ;;
      expand|space)
        # Toggle expand/collapse for selected project (if it's a main project)
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          item_type=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].type')
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          if [ "$item_type" = "project" ] && [ -n "$project_name" ]; then
            toggle-project-expanded "$project_name"
          fi
        fi
        ;;
      edit|e)
        # Open edit form for selected project
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          item_type=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].type')
          if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            if [ "$item_type" = "worktree" ]; then
              # Get worktree data for edit form
              worktree_data=$(echo "$projects_data" | ${pkgs.jq}/bin/jq -r --arg name "$project_name" '
                .worktrees[] | select(.name == $name) |
                "\(.display_name // .name)\t\(.icon)\t\(.branch_name // "")\t\(.worktree_path // "")\t\(.parent_project // "")"
              ')
              IFS=$'\t' read -r display_name icon branch_name worktree_path parent_project <<< "$worktree_data"
              worktree-edit-open "$project_name" "$display_name" "$icon" "$branch_name" "$worktree_path" "$parent_project"
            else
              # Get project data for edit form
              project_data=$(echo "$projects_data" | ${pkgs.jq}/bin/jq -r --arg name "$project_name" '
                .main_projects[] | select(.name == $name) |
                "\(.display_name // .name)\t\(.icon)\t\(.directory)\t\(.scope // "scoped")\t\(.remote.enabled // false)\t\(.remote.host // "")\t\(.remote.user // "")\t\(.remote.remote_dir // "")\t\(.remote.port // 22)"
              ')
              IFS=$'\t' read -r display_name icon directory scope remote_enabled remote_host remote_user remote_dir remote_port <<< "$project_data"
              project-edit-open "$project_name" "$display_name" "$icon" "$directory" "$scope" "$remote_enabled" "$remote_host" "$remote_user" "$remote_dir" "$remote_port"
            fi
          fi
        fi
        ;;
      delete|d)
        # Open delete confirmation for selected project
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          display_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].display_name // .[$idx].name')
          item_type=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].type')
          if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            if [ "$item_type" = "worktree" ]; then
              worktree-delete "$project_name"
            else
              project-delete-open "$project_name" "$display_name"
            fi
          fi
        fi
        ;;
      copy|y)
        # Copy directory path of selected project
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          directory=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].directory')
          if [ -n "$directory" ] && [ "$directory" != "null" ]; then
            echo -n "$directory" | ${pkgs.wl-clipboard}/bin/wl-copy
            $EWW_CMD update success_notification="Copied: $directory" success_notification_visible=true
            (sleep 2 && $EWW_CMD update success_notification_visible=false) &
          fi
        fi
        ;;
      new|n)
        # Open new project form
        project-create-open
        ;;
      git|Shift+l)
        # Feature 109 T028: Launch lazygit for selected worktree with context-aware view
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          directory=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].directory')
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          if [ -n "$directory" ] && [ "$directory" != "null" ] && [ -d "$directory" ]; then
            # Get git status for context-aware view selection
            git_dirty=$(cd "$directory" && ${pkgs.git}/bin/git status --porcelain 2>/dev/null | head -1)
            git_behind=$(cd "$directory" && ${pkgs.git}/bin/git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")

            # Select view: dirty -> status, behind -> branch, else status
            if [ -n "$git_dirty" ]; then
              view="status"
            elif [ "$git_behind" -gt 0 ]; then
              view="branch"
            else
              view="status"
            fi

            # Launch lazygit using the worktree-lazygit script
            worktree-lazygit "$directory" "$view" &

            # Exit panel mode after launching
            exit-monitor-mode
          fi
        fi
        ;;
      filter|/)
        # Focus filter input (handled by Sway keybinding - this is a placeholder)
        # The actual focus requires direct eww interaction
        ;;
      clear-filter|escape)
        # Clear filter and reset selection
        $EWW_CMD update "project_filter="
        $EWW_CMD update project_selected_index=-1
        $EWW_CMD update "project_selected_name="
        ;;
      create-worktree|c)
        # Feature 109 T035: Open worktree create form for selected project
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          item_type=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].type')
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')

          # If selected item is a worktree, use its parent project; otherwise use the project itself
          if [ "$item_type" = "worktree" ]; then
            parent_project=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].parent // ""')
            if [ -n "$parent_project" ] && [ "$parent_project" != "null" ]; then
              worktree-create-open "$parent_project"
            fi
          elif [ "$item_type" = "project" ]; then
            worktree-create-open "$project_name"
          fi
        fi
        ;;
      terminal|t)
        # Feature 109 T060: Open scratchpad terminal in selected worktree
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            i3pm scratchpad toggle "$project_name" &
            exit-monitor-mode
          fi
        fi
        ;;
      editor|Shift+e)
        # Feature 109 T061: Open VS Code in selected worktree
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          directory=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].directory')
          if [ -n "$directory" ] && [ "$directory" != "null" ] && [ -d "$directory" ]; then
            code --folder-uri "file://$directory" &
            exit-monitor-mode
          fi
        fi
        ;;
      files|Shift+f)
        # Feature 109 T055: Open file manager (yazi) in selected worktree
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          directory=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].directory')
          if [ -n "$directory" ] && [ "$directory" != "null" ] && [ -d "$directory" ]; then
            ${pkgs.ghostty}/bin/ghostty -e ${pkgs.yazi}/bin/yazi "$directory" &
            exit-monitor-mode
          fi
        fi
        ;;
      refresh|r)
        # Feature 109 T059: Refresh project list
        i3pm discover --quiet &
        $EWW_CMD update success_notification="Refreshing projects..." success_notification_visible=true
        (sleep 2 && $EWW_CMD update success_notification_visible=false) &
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

  # Feature 096: Copy project JSON to clipboard (similar to window JSON)
  # Feature 101: Updated to extract worktree data from repos.json
  copyProjectJsonScript = pkgs.writeShellScript "copy-project-json" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    PROJECT_NAME="''${1:-}"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "Usage: copy-project-json <qualified-name>" >&2
      echo "  qualified-name: account/repo:branch (e.g., vpittamp/nixos-config:main)" >&2
      exit 1
    fi

    # Feature 101: Extract worktree data from repos.json
    REPOS_FILE="$HOME/.config/i3/repos.json"
    if [[ ! -f "$REPOS_FILE" ]]; then
      echo "repos.json not found" >&2
      exit 1
    fi

    # Parse qualified name: account/repo:branch
    REPO_PART=$(echo "$PROJECT_NAME" | cut -d':' -f1)
    BRANCH_NAME=$(echo "$PROJECT_NAME" | cut -d':' -f2)
    REPO_ACCOUNT=$(echo "$REPO_PART" | cut -d'/' -f1)
    REPO_NAME=$(echo "$REPO_PART" | cut -d'/' -f2)

    # Extract worktree data and copy to clipboard
    ${pkgs.jq}/bin/jq --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" --arg branch "$BRANCH_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | {
        repository: {account: .account, name: .name, path: .path, default_branch: .default_branch},
        worktree: (.worktrees[] | select(.branch == $branch))
      }' "$REPOS_FILE" | ${pkgs.wl-clipboard}/bin/wl-copy

    # Toggle copied state for visual feedback
    $EWW_CMD update copied_project_name="$PROJECT_NAME"
    (${pkgs.coreutils}/bin/sleep 2 && $EWW_CMD update copied_project_name="") &
  '';

  # Feature 101: Copy trace data to clipboard for LLM analysis
  # Formats trace with timeline, timing analysis, and context for easy analysis
  copyTraceDataScript = pkgs.writeShellScript "copy-trace-data" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    TRACE_ID="''${1:-}"

    if [[ -z "$TRACE_ID" ]]; then
      echo "Usage: copy-trace-data <trace-id>" >&2
      exit 1
    fi

    # Query daemon for full trace data in timeline format
    # Feature 117: User socket only (daemon runs as user service)
    SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
    if [[ ! -S "$SOCKET" ]]; then
      echo "Daemon not running" >&2
      exit 1
    fi

    # Request trace with timeline format for LLM-friendly output
    RESPONSE=$(${pkgs.coreutils}/bin/printf '{"jsonrpc":"2.0","method":"trace.get","params":{"trace_id":"%s","format":"timeline"},"id":1}\n' "$TRACE_ID" \
      | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null || echo '{"error":"Connection failed"}')

    # Extract timeline text and copy to clipboard
    TIMELINE=$(${pkgs.jq}/bin/jq -r '.result.timeline // "Error: Could not fetch trace"' <<< "$RESPONSE")
    ${pkgs.coreutils}/bin/printf '%s' "$TIMELINE" | ${pkgs.wl-clipboard}/bin/wl-copy

    # Toggle copied state for visual feedback
    $EWW_CMD update copied_trace_id="$TRACE_ID"
    (${pkgs.coreutils}/bin/sleep 2 && $EWW_CMD update copied_trace_id="") &
  '';

  # Feature 099: Fetch window environment variables via IPC
  # This script queries the daemon for environment variables and updates Eww state
  fetchWindowEnvScript = pkgs.writeShellScript "fetch-window-env" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    WINDOW_PID="''${1:-}"
    WINDOW_ID="''${2:-0}"

    if [[ -z "$WINDOW_PID" ]] || [[ "$WINDOW_PID" == "0" ]] || [[ "$WINDOW_PID" == "null" ]]; then
      # No PID available - update state to show error
      $EWW_CMD update env_window_id="$WINDOW_ID"
      $EWW_CMD update env_loading=false
      $EWW_CMD update env_error="No process ID available for this window"
      $EWW_CMD update env_i3pm_vars="[]"
      $EWW_CMD update env_other_vars="[]"
      exit 0
    fi

    # Set loading state
    $EWW_CMD update env_window_id="$WINDOW_ID"
    $EWW_CMD update env_loading=true
    $EWW_CMD update env_error=""

    # Query daemon for environment variables
    # Feature 117: User socket only (daemon runs as user service)
    SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
    if [[ ! -S "$SOCKET" ]]; then
      $EWW_CMD update env_loading=false
      $EWW_CMD update env_error="Daemon not running"
      $EWW_CMD update env_i3pm_vars="[]"
      $EWW_CMD update env_other_vars="[]"
      exit 0
    fi

    # Send JSON-RPC request and parse response
    RESPONSE=$(${pkgs.coreutils}/bin/printf '{"jsonrpc":"2.0","method":"window.get_env","params":{"pid":%s},"id":1}\n' "$WINDOW_PID" \
      | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null || echo '{"error":"Connection failed"}')

    # Extract result using jq
    ERROR=$(${pkgs.jq}/bin/jq -r '.result.error // .error.message // ""' <<< "$RESPONSE")
    I3PM_VARS=$(${pkgs.jq}/bin/jq -c '.result.i3pm_vars // []' <<< "$RESPONSE")
    OTHER_VARS=$(${pkgs.jq}/bin/jq -c '.result.other_vars // []' <<< "$RESPONSE")

    # Update Eww state
    $EWW_CMD update env_loading=false
    $EWW_CMD update env_error="$ERROR"
    $EWW_CMD update env_i3pm_vars="$I3PM_VARS"
    $EWW_CMD update env_other_vars="$OTHER_VARS"
  '';

  # Feature 101: Start tracing a window by ID
  # Uses the window's Sway container ID as the deterministic identifier
  startWindowTraceScript = pkgs.writeShellScript "start-window-trace" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    WINDOW_ID="''${1:-}"
    WINDOW_TITLE="''${2:-Window}"

    if [[ -z "$WINDOW_ID" ]] || [[ "$WINDOW_ID" == "0" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Failed" "No window ID provided"
      exit 1
    fi

    # Close the context menu
    $EWW_CMD update context_menu_window_id=0

    # Start trace using window ID (most deterministic identifier)
    RESULT=$(i3pm trace start --id "$WINDOW_ID" 2>&1) || {
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Failed" "$RESULT"
      exit 1
    }

    # Extract trace ID from result
    TRACE_ID=$(echo "$RESULT" | ${pkgs.gnugrep}/bin/grep -oP 'trace-\d+-\d+' | head -1)

    # Show success notification
    ${pkgs.libnotify}/bin/notify-send -t 3000 "Trace Started" "Tracing window: $WINDOW_TITLE\nTrace ID: $TRACE_ID"

    # Switch to Traces tab to show the new trace (index 5)
    $EWW_CMD update current_view_index=5
  '';

  # Feature 101: Fetch trace events for expanded trace card
  # Toggles expansion and fetches events via IPC
  fetchTraceEventsScript = pkgs.writeShellScript "fetch-trace-events" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    TRACE_ID="''${1:-}"

    if [[ -z "$TRACE_ID" ]]; then
      exit 1
    fi

    # Check if already expanded - if so, collapse
    CURRENT_EXPANDED=$($EWW_CMD get expanded_trace_id 2>/dev/null || echo "")
    if [[ "$CURRENT_EXPANDED" == "$TRACE_ID" ]]; then
      # Collapse: clear expanded state
      $EWW_CMD update expanded_trace_id=""
      $EWW_CMD update trace_events="[]"
      exit 0
    fi

    # Expand: set loading state and fetch events
    $EWW_CMD update expanded_trace_id="$TRACE_ID"
    $EWW_CMD update trace_events_loading=true
    $EWW_CMD update trace_events="[]"

    # Query daemon for trace events
    # Feature 117: User socket only (daemon runs as user service)
    SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
    if [[ ! -S "$SOCKET" ]]; then
      $EWW_CMD update trace_events_loading=false
      $EWW_CMD update trace_events='[{"time_display":"Error","event_type":"error","description":"Daemon not running"}]'
      exit 0
    fi

    # Send JSON-RPC request
    RESPONSE=$(${pkgs.coreutils}/bin/printf '{"jsonrpc":"2.0","method":"trace.get","params":{"trace_id":"%s"},"id":1}\n' "$TRACE_ID" \
      | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null || echo '{"error":"Connection failed"}')

    # Extract and format events using jq
    EVENTS=$(${pkgs.jq}/bin/jq -c '[.result.trace.events[] | {
      time_display: (.time_iso | split("T")[1] | split(".")[0]),
      event_type: .event_type,
      description: .description,
      changes: (
        if .state_before and .state_after then
          (
            (if .state_before.floating != .state_after.floating then ["floating: \(.state_before.floating) → \(.state_after.floating)"] else [] end) +
            (if .state_before.focused != .state_after.focused then ["focused: \(.state_before.focused) → \(.state_after.focused)"] else [] end) +
            (if .state_before.hidden != .state_after.hidden then ["hidden: \(.state_before.hidden) → \(.state_after.hidden)"] else [] end) +
            (if .state_before.workspace_num != .state_after.workspace_num then ["workspace: \(.state_before.workspace_num) → \(.state_after.workspace_num)"] else [] end) +
            (if .state_before.output != .state_after.output then ["output: \(.state_before.output) → \(.state_after.output)"] else [] end)
          ) | join(", ")
        else
          ""
        end
      )
    }]' <<< "$RESPONSE" 2>/dev/null || echo '[]')

    # Handle empty/error response
    if [[ "$EVENTS" == "[]" ]] || [[ "$EVENTS" == "null" ]]; then
      EVENTS='[{"time_display":"--:--:--","event_type":"info","description":"No events recorded","changes":""}]'
    fi

    # Update Eww state
    $EWW_CMD update trace_events_loading=false
    $EWW_CMD update trace_events="$EVENTS"
  '';

  # Feature 102 (T029-T031): Navigate between Log and Traces tabs with highlight
  # Used for click-to-navigate from trace indicator to Traces tab, and vice versa
  navigateToTraceScript = pkgs.writeShellScript "navigate-to-trace" ''
    #!/usr/bin/env bash
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    TRACE_ID="''${1:-}"

    if [[ -z "$TRACE_ID" ]]; then
      exit 0
    fi

    # Set highlight state and switch to traces tab (index 5)
    $EWW_CMD update highlight_trace_id="$TRACE_ID"
    $EWW_CMD update current_view_index=5

    # Clear highlight after 2 seconds
    (${pkgs.coreutils}/bin/sleep 2 && $EWW_CMD update highlight_trace_id="") &
  '';

  # Feature 102 (T029-T031): Navigate from Traces tab to Log tab and highlight event
  navigateToEventScript = pkgs.writeShellScript "navigate-to-event" ''
    #!/usr/bin/env bash
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    EVENT_ID="''${1:-}"

    if [[ -z "$EVENT_ID" ]]; then
      exit 0
    fi

    # Set highlight state and switch to events tab (index 4)
    $EWW_CMD update highlight_event_id="$EVENT_ID"
    $EWW_CMD update current_view_index=4

    # Clear highlight after 2 seconds
    (${pkgs.coreutils}/bin/sleep 2 && $EWW_CMD update highlight_event_id="") &
  '';

  # Feature 102 T059: Start trace from template
  startTraceFromTemplateScript = pkgs.writeShellScript "start-trace-from-template" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    TEMPLATE_ID="''${1:-}"

    if [[ -z "$TEMPLATE_ID" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Error" "No template ID provided"
      exit 1
    fi

    # Close the dropdown
    $EWW_CMD update template_dropdown_open=false

    # Query daemon to start trace from template
    # Feature 117: User socket only (daemon runs as user service)
    SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
    if [[ ! -S "$SOCKET" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Error" "i3pm daemon not running"
      exit 1
    fi

    # Send JSON-RPC request
    RESPONSE=$(${pkgs.coreutils}/bin/printf '{"jsonrpc":"2.0","method":"traces.start_from_template","params":{"template_id":"%s"},"id":1}\n' "$TEMPLATE_ID" \
      | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null || echo '{"error":"Connection failed"}')

    # Check for error
    ERROR=$(${pkgs.jq}/bin/jq -r '.error.message // .result.error // empty' <<< "$RESPONSE" 2>/dev/null)
    if [[ -n "$ERROR" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Error" "$ERROR"
      exit 1
    fi

    # Extract trace ID
    TRACE_ID=$(${pkgs.jq}/bin/jq -r '.result.trace_id // empty' <<< "$RESPONSE" 2>/dev/null)
    if [[ -z "$TRACE_ID" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Error" "Failed to start trace"
      exit 1
    fi

    # Show success notification
    TEMPLATE_NAME=$(${pkgs.jq}/bin/jq -r '.result.template_name // "Template"' <<< "$RESPONSE" 2>/dev/null)
    ${pkgs.libnotify}/bin/notify-send -t 3000 "Trace Started" "Template: $TEMPLATE_NAME\nTrace ID: $TRACE_ID"
  '';

  # Keyboard handler script for view switching (Alt+1-7 or just 1-7)
  # Index mapping: 0=windows, 1=projects, 2=apps, 3=health, 4=events, 5=traces, 6=devices
  handleKeyScript = pkgs.writeShellScript "monitoring-panel-keyhandler" ''
    KEY="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    # Debug: log the key to journal
    echo "Monitoring panel key pressed: '$KEY'" | ${pkgs.systemd}/bin/systemd-cat -t eww-keyhandler
    case "$KEY" in
      1|Alt+1) $EWW_CMD update current_view_index=0 ;;
      2|Alt+2) $EWW_CMD update current_view_index=1 ;;
      3|Alt+3) $EWW_CMD update current_view_index=2 ;;
      4|Alt+4) $EWW_CMD update current_view_index=3 ;;
      5|Alt+5) $EWW_CMD update current_view_index=4 ;;
      6|Alt+6) $EWW_CMD update current_view_index=5 ;;
      7|Alt+7) $EWW_CMD update current_view_index=6 ;;
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

    panelWidth = mkOption {
      type = types.int;
      # Feature 119: Reduced default width by ~33%
      default = if hostname == "thinkpad" then 213 else 307;
      description = ''
        Width of the monitoring panel in pixels.
        Default is 213px for ThinkPad (1.25 scale) and 307px for other hosts.
        Feature 119: Reduced by ~33% from previous defaults (320/460).
        Adjust based on display scaling to prevent panel from being too wide.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Add required packages
    home.packages = [
      pkgs.eww              # Widget framework
      pkgs.inotify-tools    # Feature 107: inotifywait for badge file watching
      monitoringDataScript  # Python backend script wrapper
      toggleScript          # Toggle visibility script
      toggleFocusScript     # Feature 086: Toggle focus script
      exitMonitorModeScript # Feature 086: Exit monitoring mode
      monitorPanelTabScript       # Tab switching wrapper (centralizes variable name)
      monitorPanelGetViewScript   # Get current view index
      monitorPanelIsProjectsScript # Check if on projects tab (for conditional routing)
      monitorPanelNavScript # Feature 086: Navigation within panel
      swayNCToggleScript    # SwayNC toggle with mutual exclusivity
      restartServiceScript  # Feature 088 US3: Service restart script
      focusWindowScript     # Feature 093: Focus window action
      switchProjectScript   # Feature 093: Switch project action
      closeWorktreeScript     # Close all windows for a worktree
      closeAllWindowsScript   # Close all scoped windows
      closeWindowScript       # Feature 119: Close individual window with rate limiting
      toggleProjectContextScript # Toggle project context menu in Windows view
      toggleWindowsProjectExpandScript # Toggle individual project expand in Windows view
      projectCrudScript     # Feature 094: Project CRUD handler (T037)
      projectEditOpenScript # Feature 094: Project edit form opener (T038)
      projectEditSaveScript # Feature 094: Project edit save handler (T038)
      worktreeEditOpenScript  # Feature 094 US5: Worktree edit form opener (T059)
      worktreeCreateScript    # Feature 094 US5: Worktree create handler (T057-T058)
      worktreeDeleteScript    # Feature 094 US5: Worktree delete handler (T060)
      worktreeEditSaveScript  # Feature 094 US5: Worktree edit save handler (T059)
      toggleProjectExpandedScript # Feature 099 T015: Toggle project expand/collapse
      toggleExpandAllScript       # Feature 099 UX3: Expand/collapse all projects
      projectsNavScript           # Feature 099 UX2: Projects tab keyboard navigation
      worktreeCreateOpenScript    # Feature 099 T021: Worktree create form opener
      worktreeAutoPopulateScript  # Feature 102: Auto-populate form fields from branch name
      worktreeValidateBranchScript # Feature 102: Validate branch name and check duplicates
      worktreeDeleteOpenScript    # Feature 102: Open worktree delete confirmation dialog
      worktreeDeleteConfirmScript # Feature 102: Confirm and execute worktree deletion
      worktreeDeleteCancelScript  # Feature 102: Cancel worktree deletion
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
      ;; Build: 2025-12-15 - Fix run-while variable ordering

      ;; CRITICAL: Define current_view_index BEFORE defpolls that use :run-while
      ;; Otherwise :run-while conditions don't work and all polls run continuously
      (defvar current_view_index 0)

      ;; Defpoll: Windows view data (3s refresh)
      ;; Changed from deflisten to defpoll to prevent process spawning issues
      ;; Only runs when Windows tab is active (index 0)
      ;; Note: 3s interval reduces "channel closed" errors while still providing reasonable updates
      (defpoll monitoring_data
        :interval "3s"
        :run-while {current_view_index == 0}
        :initial "{\"status\":\"connecting\",\"projects\":[],\"project_count\":0,\"monitor_count\":0,\"workspace_count\":0,\"window_count\":0,\"timestamp\":0,\"timestamp_friendly\":\"Initializing...\",\"error\":null}"
        `${monitoringDataScript}/bin/monitoring-data-backend`)

      ;; Defpoll: Projects view data (5s refresh)
      ;; Only runs when Projects tab is active (index 1) to reduce CPU/process overhead
      (defpoll projects_data
        :interval "5s"
        :run-while {current_view_index == 1}
        :initial "{\"status\":\"loading\",\"projects\":[],\"project_count\":0,\"active_project\":null}"
        `${monitoringDataScript}/bin/monitoring-data-backend --mode projects`)

      ;; Defpoll: Apps view data (5s refresh)
      ;; Only runs when Apps tab is active (index 2)
      (defpoll apps_data
        :interval "5s"
        :run-while {current_view_index == 2}
        :initial "{\"status\":\"loading\",\"apps\":[],\"app_count\":0}"
        `${monitoringDataScript}/bin/monitoring-data-backend --mode apps`)

      ;; Defpoll: Health view data (30s refresh)
      ;; Only runs when Health tab is active (index 3) - queries systemctl which can be slow
      (defpoll health_data
        :interval "30s"
        :run-while {current_view_index == 3}
        :initial "{\"status\":\"loading\",\"health\":{}}"
        `${monitoringDataScript}/bin/monitoring-data-backend --mode health`)

      ;; Feature 101: Defpoll: Window traces view data (2s refresh)
      ;; Only runs when Traces tab is active (index 5)
      ;; Lists active and stopped traces from daemon's WindowTracer
      (defpoll traces_data
        :interval "2s"
        :run-while {current_view_index == 5}
        :initial "{\"status\":\"loading\",\"traces\":[],\"trace_count\":0,\"active_count\":0,\"stopped_count\":0}"
        `${monitoringDataScript}/bin/monitoring-data-backend --mode traces`)

      ;; Feature 110: Pulsating red circle animation with opacity fade
      ;; Large circle with opacity pulse for smooth "breathing" effect
      ;; 120ms interval with 8 frames = ~1s full cycle
      (defpoll spinner_frame
        :interval "120ms"
        :run-while {monitoring_data.has_working_badge ?: false}
        :initial "⬤"
        `${spinnerScript}/bin/eww-spinner-frame`)

      ;; Feature 110: Opacity value for fade effect (synced with spinner_frame)
      (defpoll spinner_opacity
        :interval "120ms"
        :run-while {monitoring_data.has_working_badge ?: false}
        :initial "1.0"
        `${spinnerOpacityScript}/bin/eww-spinner-opacity`)

      ;; Feature 092: Defpoll: Sway event log (2s refresh)
      ;; Changed from deflisten to defpoll to prevent process spawning issues
      ;; Only runs when Events tab is active (index 4)
      (defpoll events_data
        :interval "2s"
        :run-while {current_view_index == 4}
        :initial "{\"status\":\"connecting\",\"events\":[],\"event_count\":0,\"daemon_available\":true,\"ipc_connected\":false,\"timestamp\":0,\"timestamp_friendly\":\"Initializing...\"}"
        `${monitoringDataScript}/bin/monitoring-data-backend --mode events`)

      ;; Feature 094 T039: Form validation state
      ;; Changed from deflisten to defvar - validation is rarely used and causes process issues
      ;; Validation handled via explicit update commands when forms are opened
      (defvar validation_state "{\"valid\":true,\"editing\":false,\"errors\":{},\"warnings\":{},\"timestamp\":\"\"}")

      ;; Feature 116: Defpoll: Device state (2s refresh - reduced from 500ms)
      ;; Only runs when Devices tab is active (index 6)
      ;; Uses device-backend.py from eww-device-controls module
      ;; Note: 500ms was too aggressive and caused daemon overload
      (defpoll devices_state
        :interval "2s"
        :run-while {current_view_index == 6}
        :initial "{\"volume\":{\"volume\":50,\"muted\":false,\"icon\":\"󰕾\",\"current_device\":\"Unknown\"},\"bluetooth\":{\"enabled\":false,\"scanning\":false,\"devices\":[]},\"brightness\":{\"display\":50,\"keyboard\":0},\"battery\":{\"percentage\":100,\"state\":\"full\",\"icon\":\"󰁹\",\"level\":\"normal\",\"time_remaining\":\"\"},\"thermal\":{\"cpu_temp\":0,\"level\":\"normal\",\"icon\":\"󰔏\"},\"network\":{\"tailscale_connected\":false,\"wifi_connected\":false},\"hardware\":{\"has_battery\":false,\"has_brightness\":false,\"has_keyboard_backlight\":false,\"has_bluetooth\":true,\"has_power_profiles\":false,\"has_thermal_sensors\":true},\"power_profile\":{\"current\":\"balanced\",\"available\":[],\"icon\":\"󰾅\"}}"
        `$HOME/.config/eww/eww-device-controls/scripts/device-backend.py 2>/dev/null || echo '{}'`)

      ;; NOTE: current_view_index is defined at the TOP of this file (before defpolls)
      ;; This is required for :run-while conditions to work correctly

      ;; Selected window ID for detail view (0 = none selected)
      (defvar selected_window_id 0)

      ;; Panel visibility state (toggled by Mod+M)
      ;; Uses CSS-based hiding instead of open/close which crashes eww daemon
      (defvar panel_visible true)

      ;; Feature 086: Panel focus state (updated by toggle-panel-focus script)
      ;; When true, panel has keyboard focus and shows visual indicator
      (defvar panel_focused false)

      ;; Feature 114: Panel focus mode for click-through behavior
      ;; When false (default), clicks pass through to windows beneath
      ;; When true, panel receives clicks (interactive mode via Mod+M)
      (defvar panel_focus_mode false)

      ;; Feature 086: Selected index for keyboard navigation (-1 = none)
      ;; Updated by j/k or up/down in monitoring mode
      (defvar selected_index -1)

      ;; Feature 119: Debug mode toggle - Controls visibility of JSON and env var features
      ;; When false (default), JSON inspect and env var features are hidden
      ;; When true, debug features are visible
      (defvar debug_mode false)

      ;; Hover tooltip state - Window ID being hovered (0 = none)
      ;; Updated by onhover/onhoverlost events on window items
      (defvar hover_window_id 0)

      ;; UX Enhancement: Inline action bar state - tracks which window has action bar visible
      (defvar context_menu_window_id 0)

      ;; Project context menu state - Project name for action bar ("" = none)
      (defvar context_menu_project "")

      ;; Windows view expand state - Multiple projects can be expanded simultaneously
      ;; JSON array of expanded project names, or "all" to expand all
      ;; Default "all" means all projects expanded by default
      (defvar windows_expanded_projects "all")
      ;; Track if all are expanded (for toggle button state)
      (defvar windows_all_expanded true)

      ;; Copy state - Window ID that was just copied (0 = none)
      ;; Set when copy button clicked, auto-resets after 2 seconds
      (defvar copied_window_id 0)

      ;; Feature 099: Environment variables view state
      ;; Window ID whose env vars are being displayed (0 = none)
      (defvar env_window_id 0)
      ;; True while fetching env vars from daemon
      (defvar env_loading false)
      ;; Error message from env fetch (empty = no error)
      (defvar env_error "")
      ;; Array of I3PM_* variables: [{key, value}, ...]
      (defvar env_i3pm_vars "[]")
      ;; Array of other notable variables: [{key, value}, ...]
      (defvar env_other_vars "[]")
      ;; Filter text for env vars (case-insensitive contains match on key or value)
      (defvar env_filter "")

      ;; Event-driven state variable (updated by daemon publisher)
      (defvar panel_state "{}")

      ;; Feature 093: Click interaction state variables (T021-T023)
      ;; Window ID of last clicked window (0 = no window clicked or auto-reset after 2s)
      (defvar clicked_window_id 0)

      ;; Project name of last clicked project header ("" = no project clicked or auto-reset after 2s)
      (defvar clicked_project "")

      ;; True if a click action is currently executing (lock file exists)
      (defvar click_in_progress false)

      ;; Panel transparency control (0-100, default 35%)
      ;; Adjustable via slider in header - persists across tabs
      (defvar panel_opacity 35)

      ;; Feature 092: Event filter state (all enabled by default)
      ;; Individual event type filters (true = show, false = hide)
      (defvar filter_window_new true)
      (defvar filter_window_close true)
      (defvar filter_window_focus true)
      (defvar filter_window_move true)
      (defvar filter_window_floating true)
      (defvar filter_window_fullscreen_mode true)
      (defvar filter_window_title true)
      (defvar filter_window_mark true)
      (defvar filter_window_urgent true)
      ;; Feature 102 T049: Window blur filter
      (defvar filter_window_blur true)
      (defvar filter_workspace_focus true)
      (defvar filter_workspace_init true)
      (defvar filter_workspace_empty true)
      (defvar filter_workspace_move true)
      (defvar filter_workspace_rename true)
      (defvar filter_workspace_urgent true)
      (defvar filter_workspace_reload true)
      ;; Feature 102 T047: Output event type filters
      (defvar filter_output_connected true)
      (defvar filter_output_disconnected true)
      (defvar filter_output_profile_changed true)
      (defvar filter_output_unspecified true)
      (defvar filter_binding_run true)
      (defvar filter_mode_change true)
      (defvar filter_shutdown_exit true)
      (defvar filter_tick_manual true)

      ;; Feature 102: i3pm internal event filters (T014)
      ;; Project events
      (defvar filter_i3pm_project_switch true)
      (defvar filter_i3pm_project_clear true)
      ;; Visibility events
      (defvar filter_i3pm_visibility_hidden true)
      (defvar filter_i3pm_visibility_shown true)
      ;; Scratchpad events
      (defvar filter_i3pm_scratchpad_move true)
      (defvar filter_i3pm_scratchpad_show true)
      ;; Launch events
      (defvar filter_i3pm_launch_intent true)
      (defvar filter_i3pm_launch_queued true)
      (defvar filter_i3pm_launch_complete true)
      (defvar filter_i3pm_launch_failed true)
      ;; State events
      (defvar filter_i3pm_state_cached true)
      (defvar filter_i3pm_state_restored true)
      ;; Command events (placeholder for US2)
      (defvar filter_i3pm_command_queued true)
      (defvar filter_i3pm_command_executed true)
      (defvar filter_i3pm_command_result true)
      (defvar filter_i3pm_command_batch true)
      ;; Trace events
      (defvar filter_i3pm_trace_started true)
      (defvar filter_i3pm_trace_stopped true)
      (defvar filter_i3pm_trace_event true)

      ;; Filter panel visibility (false = collapsed, true = expanded)
      (defvar filter_panel_expanded false)

      ;; Feature 102 T053: Sort mode for events log (time = chronological, duration = slowest first)
      (defvar events_sort_mode "time")

      ;; Feature 094: Project hover and copy state
      (defvar hover_project_name "")

      ;; Feature 094: Hover state for Applications tab detail tooltips
      (defvar hover_app_name "")
      (defvar copied_project_name "")
      ;; Feature 096: JSON hover state for Projects tab (separate from general hover)
      (defvar json_hover_project "")

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
      (defvar worktree_form_description "")       ;; Feature 102: Primary input - feature description
      (defvar worktree_form_branch_name "")       ;; Branch name (auto-generated from description, editable)
      (defvar worktree_form_path "")              ;; Worktree path (auto-generated, editable)
      (defvar worktree_form_parent_project "")    ;; Parent project name (required for worktrees)
      (defvar worktree_form_repo_path "")         ;; Feature 102: Repo path for auto-populating worktree path
      (defvar worktree_form_speckit true)         ;; Feature 112: Speckit scaffolding checkbox (default: checked)
      (defvar worktree_delete_confirm "")         ;; Project name to confirm deletion (click-to-confirm)
      ;; Feature 102: Worktree hover state (using Eww events instead of CSS :hover for nested for loop compatibility)
      (defvar hover_worktree_name "")           ;; Qualified name of currently hovered worktree
      ;; Feature 102: Worktree delete dialog state
      (defvar worktree_delete_dialog_visible false)
      (defvar worktree_delete_name "")            ;; Worktree qualified name to delete
      (defvar worktree_delete_branch "")          ;; Branch name for display
      (defvar worktree_delete_is_dirty false)     ;; Whether worktree has uncommitted changes

      ;; Feature 099 T008: Expanded projects state (list of expanded project names as JSON array)
      (defvar expanded_projects "all")            ;; "all" = all expanded, or JSON array of expanded names

      ;; Feature 099 UX Enhancements
      (defvar project_filter "")                  ;; UX1: Filter text for projects search
      (defvar project_selected_index -1)          ;; UX2: Currently selected project index for keyboard nav
      (defvar project_selected_name "")           ;; UX2: Name of currently selected project (for highlighting)
      (defvar projects_all_expanded true)         ;; UX3: Toggle state for expand/collapse all (default: expanded)

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
      ;; Feature 096 T017-T018: Enhanced notification state for all CRUD operations
      (defvar save_in_progress false)               ;; True during save operations (disables form inputs)
      (defvar success_notification "")              ;; Success message to display (auto-dismiss after 3s)
      (defvar success_notification_visible false)   ;; Controls success notification visibility
      (defvar error_notification "")                ;; Error message to display (persist until dismissed)
      (defvar error_notification_visible false)     ;; Controls error notification visibility
      (defvar warning_notification "")              ;; Warning message (e.g., conflict detected but saved)
      (defvar warning_notification_visible false)   ;; Controls warning notification visibility

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

      ;; Feature 101: Trace expansion state for inline event timeline
      (defvar expanded_trace_id "")           ;; Trace ID currently expanded (empty = none)
      (defvar trace_events "[]")              ;; JSON array of events for expanded trace
      (defvar trace_events_loading false)     ;; True while fetching events
      (defvar copied_trace_id "")             ;; Trace ID just copied (for visual feedback)

      ;; Feature 102 (T029-T031): Cross-navigation between Log and Traces tabs
      (defvar highlight_event_id "")          ;; Event ID to highlight after navigation
      (defvar highlight_trace_id "")          ;; Trace ID to highlight after navigation
      (defvar navigate_to_tab "")             ;; Tab to navigate to (triggers via revealer animation)

      ;; Feature 102 T059: Trace template selector state
      (defvar template_dropdown_open false)   ;; True when template dropdown is visible
      (defvar trace_templates "[{\"id\":\"debug-app-launch\",\"name\":\"Debug App Launch\",\"icon\":\"󰘳\",\"description\":\"Pre-launch trace for debugging app startup\"},{\"id\":\"debug-project-switch\",\"name\":\"Debug Project Switch\",\"icon\":\"󰓩\",\"description\":\"Trace all scoped windows during project switch\"},{\"id\":\"debug-focus-chain\",\"name\":\"Debug Focus Chain\",\"icon\":\"󰋴\",\"description\":\"Track focus and blur events for the currently focused window\"}]")

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
          :width "${toString cfg.panelWidth}px"
          :height "90%")
        :namespace "eww-monitoring-panel"
        :stacking "fg"
        ;; Feature 114: Use ondemand - clicks are received when user clicks on panel
        ;; The panel is now properly closed (not just hidden) so it won't intercept clicks when not visible
        :focusable "ondemand"
        :exclusive false
        :windowtype "dock"
        (monitoring-panel-content))

      ;; Main panel content widget with keyboard navigation
      ;; Feature 086: Dynamic class changes when panel has focus
      ;; Dynamic opacity controlled by panel_opacity variable (10-100%)
      ;; Note: Keyboard input is handled via Sway mode (📊 Panel), not eventbox
      ;; since eww layer-shell windows cannot capture keyboard events directly
      ;; Visibility controlled by revealer widget for proper show/hide behavior
      ;; Revealer collapses the widget completely when hidden (no mouse interception)
      (defwidget monitoring-panel-content []
        (revealer
          :transition "crossfade"
          :reveal {panel_visible}
          :duration "150ms"
          (eventbox
            :cursor "default"
            (box
              :class {panel_focused ? "panel-container focused" : "panel-container"}
              :style "background-color: rgba(30, 30, 46, ''${panel_opacity / 100});"
              :orientation "v"
              :space-evenly false
              (panel-header)
              (panel-body)
              (panel-footer)
              ;; Feature 094 T040: Conflict resolution dialog overlay
              (conflict-resolution-dialog)
              ;; Feature 094 Phase 12 T099: Success notification overlay (auto-dismiss)
              (success-notification-toast)
              ;; Feature 096 T019: Error and warning notification overlays
              (error-notification-toast)
              (warning-notification-toast)))))

      ;; Panel header with tab navigation
      ;; Index mapping: 0=windows, 1=projects, 2=apps, 3=health, 4=events, 5=traces
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
              :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update current_view_index=0"
              (button
                :class "tab ''${current_view_index == 0 ? 'active' : ""}"
                :tooltip "Windows (Alt+1)"
                "󰖯"))
            (eventbox
              :cursor "pointer"
              :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update current_view_index=1"
              (button
                :class "tab ''${current_view_index == 1 ? 'active' : ""}"
                :tooltip "Projects (Alt+2)"
                "󱂬"))
            (eventbox
              :cursor "pointer"
              :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update current_view_index=2"
              (button
                :class "tab ''${current_view_index == 2 ? 'active' : ""}"
                :tooltip "Apps (Alt+3)"
                "󰀻"))
            (eventbox
              :cursor "pointer"
              :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update current_view_index=3"
              (button
                :class "tab ''${current_view_index == 3 ? 'active' : ""}"
                :tooltip "Health (Alt+4)"
                "󰓙"))
            ;; Feature 092: Logs tab (5th tab)
            (eventbox
              :cursor "pointer"
              :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update current_view_index=4"
              (button
                :class "tab ''${current_view_index == 4 ? 'active' : ""}"
                :tooltip "Logs (Alt+5)"
                "󰌱"))
            ;; Feature 101: Traces tab (6th tab)
            (eventbox
              :cursor "pointer"
              :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update current_view_index=5"
              (button
                :class "tab ''${current_view_index == 5 ? 'active' : ""}"
                :tooltip "Traces (Alt+6)"
                "󱂛"))
            ;; Feature 116: Devices tab (7th tab)
            (eventbox
              :cursor "pointer"
              :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update current_view_index=6"
              (button
                :class "tab ''${current_view_index == 6 ? 'active' : ""}"
                :tooltip "Devices (Alt+7)"
                "󰒓"))
            ;; Feature 086: Focus mode indicator badge
            (label
              :class "focus-indicator"
              :visible {panel_focused}
              :text "⌨ FOCUS"))
          ;; Summary counts (dynamic based on view)
          (box
            :class "summary-counts"
            :orientation "h"
            :space-evenly false
            (box
              :orientation "h"
              :space-evenly true
              :hexpand true
              ;; Feature 119: Removed PRJ/WS/WIN text labels - show just counts with icons
              ;; Index mapping: 0=windows, 1=projects, 2=apps, 3=health, 4=events, 5=traces
              (label
                :class "count-badge"
                :tooltip "Projects"
                :text "󰉋 ''${current_view_index == 0 ? monitoring_data.project_count ?: 0 : current_view_index == 1 ? projects_data.project_count ?: 0 : current_view_index == 2 ? apps_data.app_count ?: 0 : 0}")
              (label
                :class "count-badge"
                :tooltip "Workspaces"
                :text "󰍹 ''${current_view_index == 0 ? monitoring_data.workspace_count ?: 0 : 0}"
                :visible {current_view_index == 0})
              (label
                :class "count-badge"
                :tooltip "Windows"
                :text "󱂬 ''${current_view_index == 0 ? monitoring_data.window_count ?: 0 : 0}"
                :visible {current_view_index == 0}))
            ;; Feature 119: Debug mode toggle button
            ;; When toggling OFF: also clear hover_window_id and env_window_id to collapse panels
            (eventbox
              :cursor "pointer"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update debug_mode=''${debug_mode ? 'false' : 'true'} hover_window_id=0 env_window_id=0"
              :tooltip {debug_mode ? "Debug mode ON - click to hide debug features" : "Debug mode OFF - click to show JSON/env features"}
              (label
                :class {"debug-toggle" + (debug_mode ? " active" : "")}
                :text {debug_mode ? "󰃤" : "󰃠"}))
            ;; Opacity slider - small unobtrusive control
            (box
              :class "opacity-control"
              :orientation "h"
              :space-evenly false
              :tooltip "Panel opacity: ''${panel_opacity}%"
              (label
                :class "opacity-icon"
                :text "󰃞")
              (scale
                :class "opacity-slider"
                :min 10
                :max 100
                :value panel_opacity
                :orientation "h"
                :round-digits 0
                :onchange "eww --config $HOME/.config/eww-monitoring-panel update panel_opacity={}")))
          ;; UX Enhancement: Workspace Pills - full implementation
          (scroll
            :hscroll true
            :vscroll false
            :visible {current_view_index == 0}
            :class "workspace-pills-scroll"
            (box
              :class "workspace-pills"
              :orientation "h"
              :space-evenly false
              (for ws in {monitoring_data.workspaces ?: []}
                (eventbox
                  :cursor "pointer"
                  :onclick "swaymsg workspace ''${ws.name} &"
                  :tooltip "Switch to workspace ''${ws.name}"
                  (label
                    :class {"workspace-pill" + (ws.focused ? " focused" : "") + (ws.urgent ? " urgent" : "")}
                    :text "''${ws.name}")))))))

      ;; Panel body - uses stack widget for proper tab switching
      ;; Note: Previous "multiple tabs" issue was caused by orphaned eww processes, not stack bugs
      ;; GitHub #1192 (index reset on reopen) is handled by ExecStartPost re-sync
      ;; Index mapping: 0=windows, 1=projects, 2=apps, 3=health, 4=events, 5=traces, 6=devices
      (defwidget panel-body []
        (stack
          :selected current_view_index
          :transition "none"
          :vexpand true
          :same-size false
          (box :class "view-container" :vexpand true (windows-view))
          (box :class "view-container" :vexpand true (projects-view))
          (box :class "view-container" :vexpand true (apps-view))
          (box :class "view-container" :vexpand true (health-view))
          (box :class "view-container" :vexpand true (events-view))
          (box :class "view-container" :vexpand true (traces-view))
          (box :class "view-container" :vexpand true (devices-view))))

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
                ;; Action button row at top
                (box
                  :class "windows-actions-row"
                  :orientation "h"
                  :space-evenly false
                  :halign "end"
                  :spacing 8
                  ;; Expand/Collapse All button
                  (eventbox
                    :cursor "pointer"
                    :onclick {windows_all_expanded ? "eww --config $HOME/.config/eww-monitoring-panel update windows_expanded_projects='[]' windows_all_expanded=false" : "eww --config $HOME/.config/eww-monitoring-panel update windows_expanded_projects='all' windows_all_expanded=true"}
                    :tooltip {windows_all_expanded ? "Collapse all worktrees" : "Expand all worktrees"}
                    (box
                      :class "expand-all-btn"
                      :orientation "h"
                      :space-evenly false
                      :spacing 4
                      (label :class "expand-all-icon" :text {windows_all_expanded ? "󰅀" : "󰅂"})
                      (label :class "expand-all-text" :text {windows_all_expanded ? "Collapse" : "Expand"})))
                  ;; Close All button
                  (eventbox
                    :cursor "pointer"
                    :onclick "${closeAllWindowsScript}/bin/close-all-windows-action &"
                    :tooltip "Close all scoped windows"
                    (box
                      :class "close-all-btn"
                      :orientation "h"
                      :space-evenly false
                      :spacing 4
                      (label :class "close-all-icon" :text "󰅖")
                      (label :class "close-all-text" :text "Close All"))))
                ;; Feature 117: Active AI Sessions bar - shows all windows with AI assistant badges
                ;; Three visual states:
                ;;   - working: AI actively processing (pulsating red indicator)
                ;;   - needs_attention: AI finished, awaiting user (bell icon, highlight border)
                ;;   - idle: AI session ready for more work (muted indicator)
                (box
                  :class "ai-sessions-bar"
                  :visible {arraylength(monitoring_data.ai_sessions ?: []) > 0}
                  :orientation "h"
                  :space-evenly false
                  :spacing 6
                  ;; Chips for each AI session
                  (for session in {monitoring_data.ai_sessions ?: []}
                    (eventbox
                      :cursor "pointer"
                      :onclick "${focusWindowScript}/bin/focus-window-action ''${session.project} ''${session.id} &"
                      :tooltip {"󱜙 Click to focus\n󰙅 " + (session.project != "" ? session.project : "Unknown") + "\n󰚩 " + (session.source == "claude-code" ? "Claude Code" : (session.source == "codex" ? "Codex" : session.source)) + "\n" + (session.state == "working" ? "⏳ Processing..." : (session.needs_attention ? "🔔 Needs attention" : "💤 Ready for input"))}
                      (box
                        ;; Dynamic class based on state: working, attention, idle
                        :class {"ai-session-chip" + (session.state == "working" ? " working" : (session.needs_attention ? " attention" : " idle"))}
                        :orientation "h"
                        :space-evenly false
                        :spacing 4
                        ;; State indicator icon
                        ;; Working: pulsating spinner, Attention: bell, Idle: moon
                        (label
                          :class {"ai-session-indicator" + (session.state == "working" ? " badge-opacity-" + (spinner_opacity == "0.4" ? "04" : (spinner_opacity == "0.6" ? "06" : (spinner_opacity == "0.8" ? "08" : "10"))) : "")}
                          :text {session.state == "working" ? spinner_frame : (session.needs_attention ? "󰂞" : "󰤄")})
                        ;; Source icon (SVG images for claude and codex)
                        (image
                          :class "ai-session-source-icon"
                          :path {session.source == "claude-code" ? "/etc/nixos/assets/icons/claude.svg" : (session.source == "codex" ? "/etc/nixos/assets/icons/chatgpt.svg" : "/etc/nixos/assets/icons/anthropic.svg")}
                          :image-width 14
                          :image-height 14)))))
                ;; Projects list
                (for project in {monitoring_data.projects ?: []}
                  (project-widget :project project)))))))

      ;; Project display widget
      ;; UX Enhancement: Active project gets highlighted
      ;; Multiple projects can be expanded simultaneously
      ;; Click header to toggle expand/collapse, right-click reveals actions
      (defwidget project-widget [project]
        (box
          :class {"project " + (project.scope == "scoped" ? "scoped-project" : "global-project") + (project.is_active ? " project-active" : "")}
          :orientation "v"
          :space-evenly false
          ; Project header - click to toggle individual expand/collapse, right-click for actions
          (eventbox
            :onclick "${toggleWindowsProjectExpandScript}/bin/toggle-windows-project-expand ''${project.name} &"
            :onrightclick "${toggleProjectContextScript}/bin/toggle-project-context ''${project.name} &"
            :cursor "pointer"
            :tooltip {(windows_expanded_projects == "all" || jq(windows_expanded_projects, ". | index(\"" + project.name + "\") != null")) ? "Click to collapse" : "Click to expand"}
            (box
              :class "project-header"
              :orientation "h"
              :space-evenly false
              ;; Expand/collapse icon
              (label
                :class "expand-icon"
                :text {(windows_expanded_projects == "all" || jq(windows_expanded_projects, ". | index(\"" + project.name + "\") != null")) ? "󰅀" : "󰅂"})
              (label
                :class "project-name"
                :text "''${project.scope == 'scoped' ? '󱂬' : '󰞇'} ''${project.name}")
              ;; UX Enhancement: Active indicator (filled circle)
              (label
                :class "active-indicator"
                :visible {project.is_active}
                :tooltip "Active project"
                :text "●")
              (box
                :hexpand true
                :halign "end"
                :orientation "h"
                :space-evenly false
                (label
                  :class "window-count-badge"
                  :text "''${project.window_count}")
                ;; Feature 119: Hover-visible close button for quick project close
                (eventbox
                  :cursor "pointer"
                  :class "hover-close-btn project-hover-close"
                  :onclick "${closeWorktreeScript}/bin/close-worktree-action ''${project.name} &"
                  :tooltip "Close all windows in this project"
                  (label
                    :class "hover-close-icon"
                    :text "󰅖")))))
          ;; Project action bar (reveals on right-click)
          (revealer
            :reveal {context_menu_project == project.name}
            :transition "slidedown"
            :duration "100ms"
            (box
              :class "project-action-bar"
              :orientation "h"
              :space-evenly false
              :halign "end"
              ;; Switch to project button (only for scoped projects)
              (eventbox
                :visible {project.scope == "scoped"}
                :cursor "pointer"
                :onclick "${switchProjectScript}/bin/switch-project-action ''${project.name}; ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update context_menu_project= &"
                :tooltip "Switch to this worktree"
                (label :class "action-btn action-switch" :text "󰌑"))
              ;; Close all windows for this project
              (eventbox
                :cursor "pointer"
                :onclick "${closeWorktreeScript}/bin/close-worktree-action ''${project.name}; ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update context_menu_project= &"
                :tooltip "Close all windows for this project"
                (label :class "action-btn action-close-project" :text "󰅖"))
              ;; Dismiss action bar
              (eventbox
                :cursor "pointer"
                :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update context_menu_project="
                :tooltip "Close menu"
                (label :class "action-btn action-dismiss" :text "󰅙"))))
          ;; Windows list - shown when this project is expanded
          ;; Expanded when: "all" mode OR project name is in the expanded array
          (revealer
            :reveal {windows_expanded_projects == "all" || jq(windows_expanded_projects, ". | index(\"" + project.name + "\") != null")}
            :transition "slidedown"
            :duration "150ms"
            (box
              :class "windows-container"
              :orientation "v"
              :space-evenly false
              (for window in {project.windows ?: []}
                (window-widget :window window))))))

      ;; Compact window widget for sidebar - Single line with badges + JSON expand
      ;; Click main area to focus window
      ;; Hover expand icon (󰅂) to reveal JSON panel - intentional action required
      ;; Right-click shows inline action bar below the window item
      (defwidget window-widget [window]
        (box
          :class "window-container"
          :orientation "v"
          :space-evenly false
          ;; Main window row with icon trigger for JSON expand
          (box
            :class "window-row"
            :orientation "h"
            :space-evenly false
            ;; Main clickable area (focuses window)
            ;; Feature 093: Added click handler for window focus with project switching
            ;; Right-click toggles inline action bar for this specific window
            (eventbox
              :onclick "${focusWindowScript}/bin/focus-window-action ''${window.project} ''${window.id} &"
              :onrightclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=''${context_menu_window_id == window.id ? 0 : window.id}"
              :cursor "pointer"
              :hexpand true
              (box
                :class "window ''${window.scope == 'scoped' ? 'scoped-window' : 'global-window'} ''${window.state_classes} ''${clicked_window_id == window.id ? ' clicked' : ""} ''${strlength(window.icon_path) > 0 ? 'has-icon' : 'no-icon'}"
                :orientation "h"
                :space-evenly false
                :hexpand true
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
                  :halign "end"
                  ;; Feature 119: Removed workspace badge - user doesn't use workspace numbers
                  (label
                    :class "badge badge-pwa"
                    :text "PWA"
                    :visible {window.is_pwa ?: false})
                  ;; Feature 095: Notification badge with state-based icons
                  ;; "working" state = animated braille spinner (teal, pulsing glow)
                  ;; "stopped" state = bell icon with count (peach, attention-grabbing)
                  ;; Badge data comes from daemon badge_service.py, triggered by Claude Code hooks
                  ;; Feature 107: spinner_frame now updated via separate defpoll (not monitoring_data)
                  ;; Feature 107: Focus-aware badge styling (dimmed when window is focused, but NOT for working state)
                  ;; Feature 110: Added opacity class for pulsating fade effect
                  ;; Note: Working state badges stay bright regardless of focus for visibility
                  (label
                    :class {"badge badge-notification" + ((window.badge?.state ?: "stopped") == "working" ? " badge-working badge-opacity-" + (spinner_opacity == "0.4" ? "04" : (spinner_opacity == "0.6" ? "06" : (spinner_opacity == "0.8" ? "08" : "10"))) : " badge-stopped" + ((window.focused ?: false) ? " badge-focused-window" : ""))}
                    :text {((window.badge?.state ?: "stopped") == "working" ? spinner_frame : "󰂚 " + (window.badge?.count ?: ""))}
                    :tooltip {(window.badge?.state ?: "stopped") == "working"
                      ? "Claude Code is working... [" + (window.badge?.source ?: "claude-code") + "]"
                      : (window.badge?.count ?: "0") + " notification(s) - awaiting input [" + (window.badge?.source ?: "unknown") + "]"}
                    :visible {(window.badge?.count ?: "") != "" || (window.badge?.state ?: "") == "working"}))))
            ;; JSON expand trigger icon - click to toggle (Feature 109: Changed from hover to click for stability)
            ;; Feature 119: Hidden when debug_mode is false
            (eventbox
              :cursor "pointer"
              :visible debug_mode
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update hover_window_id=''${hover_window_id == window.id ? 0 : window.id}"
              :tooltip "Click to view JSON"
              (box
                :class {"json-expand-trigger" + (hover_window_id == window.id ? " expanded" : "")}
                :valign "center"
                (label
                  :class "json-expand-icon"
                  :text {hover_window_id == window.id ? "󰅀" : "󰅂"})))
            ;; Feature 099: Environment variables trigger icon - click to expand
            ;; Feature 119: Hidden when debug_mode is false
            (eventbox
              :cursor "pointer"
              :visible debug_mode
              :onclick "${fetchWindowEnvScript} ''${window.pid ?: 0} ''${window.id} &"
              :tooltip "Click to view environment variables"
              (box
                :class {"env-expand-trigger" + (env_window_id == window.id ? " expanded" : "")}
                :valign "center"
                (label
                  :class "env-expand-icon"
                  :text {env_window_id == window.id ? "󰘵" : "󰀫"})))
            ;; Feature 119: Hover-visible close button for quick window close
            (eventbox
              :cursor "pointer"
              :class "hover-close-btn"
              :onclick "${closeWindowScript}/bin/close-window-action ''${window.id}"
              :tooltip "Close window"
              (label
                :class "hover-close-icon"
                :text "󰅖")))
          ;; Inline action bar (slides down on right-click)
          (revealer
            :reveal {context_menu_window_id == window.id}
            :transition "slidedown"
            :duration "100ms"
            (box
              :class "window-action-bar"
              :orientation "h"
              :space-evenly false
              :halign "end"
              (eventbox
                :cursor "pointer"
                :onclick "swaymsg [con_id=''${window.id}] focus && eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=0"
                :tooltip "Focus window"
                (label :class "action-btn action-focus" :text "󰈈"))
              (eventbox
                :cursor "pointer"
                :onclick "swaymsg [con_id=''${window.id}] floating toggle && eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=0"
                :tooltip "Toggle floating"
                (label :class "action-btn action-float" :text "󰖲"))
              (eventbox
                :cursor "pointer"
                :onclick "swaymsg [con_id=''${window.id}] fullscreen toggle && eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=0"
                :tooltip "Toggle fullscreen"
                (label :class "action-btn action-fullscreen" :text "󰊓"))
              (eventbox
                :cursor "pointer"
                :onclick "swaymsg [con_id=''${window.id}] move scratchpad && eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=0"
                :tooltip "Move to scratchpad"
                (label :class "action-btn action-scratchpad" :text "󰘓"))
              ;; Feature 101: Start trace action
              (eventbox
                :cursor "pointer"
                :onclick "${startWindowTraceScript} ''${window.id} '\"''${window.title}\"' &"
                :tooltip "Start tracing this window"
                (label :class "action-btn action-trace" :text "󱂛"))
              (eventbox
                :cursor "pointer"
                :onclick "${closeWindowScript}/bin/close-window-action ''${window.id}"
                :tooltip "Close window"
                (label :class "action-btn action-close" :text "󰅖"))))
          ;; JSON panel (slides down when expand icon is clicked - Feature 109: Removed hover handlers for stability)
          ;; Feature 119: Only visible when debug_mode is enabled
          (revealer
            :reveal {debug_mode && hover_window_id == window.id}
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
                  :onclick "notify-send 'JSON Preview Disabled' 'JSON copy is temporarily disabled to reduce CPU usage' &"
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
                  :text "(JSON preview disabled to reduce CPU)"
                  :wrap false))))
          ;; Feature 099: Environment variables panel (slides down when env icon is clicked)
          ;; Feature 119: Only visible when debug_mode is enabled
          (revealer
            :reveal {debug_mode && env_window_id == window.id}
            :transition "slidedown"
            :duration "150ms"
            (box
              :class "window-env-panel"
              :orientation "v"
              :space-evenly false
              ;; Header with title and close button
              (box
                :class "env-panel-header"
                :orientation "h"
                :space-evenly false
                (label
                  :class "env-panel-title"
                  :halign "start"
                  :hexpand true
                  :text "󰀫 Environment Variables (PID: ''${window.pid ?: 'N/A'})")
                (eventbox
                  :cursor "pointer"
                  :onclick "eww --config $HOME/.config/eww-monitoring-panel update env_window_id=0 env_filter=''''''"
                  :tooltip "Close"
                  (label
                    :class "env-close-btn"
                    :text "󰅖")))
              ;; Filter input
              (box
                :class "env-filter-box"
                :orientation "h"
                :space-evenly false
                (label
                  :class "env-filter-icon"
                  :text "󰈲")
                (input
                  :class "env-filter-input"
                  :hexpand true
                  :value env_filter
                  :onchange "eww --config $HOME/.config/eww-monitoring-panel update env_filter='{}'"
                  :timeout "150ms")
                (eventbox
                  :cursor "pointer"
                  :onclick "eww --config $HOME/.config/eww-monitoring-panel update env_filter=''''''"
                  :tooltip "Clear filter"
                  :visible {env_filter != ""}
                  (label
                    :class "env-filter-clear"
                    :text "󰅖")))
              ;; Loading state
              (revealer
                :reveal {env_loading}
                :transition "slidedown"
                :duration "100ms"
                (box
                  :class "env-loading"
                  :halign "center"
                  (label :text "󰦖 Loading environment...")))
              ;; Error state
              (revealer
                :reveal {env_error != ""}
                :transition "slidedown"
                :duration "100ms"
                (box
                  :class "env-error"
                  :halign "start"
                  (label :text "󰀦 ''${env_error}")))
              ;; I3PM variables section (prominent display)
              ;; Note: Using fixed classes and structure to prevent scroll reset on parent updates
              (box
                :class "env-section env-section-i3pm"
                :orientation "v"
                :space-evenly false
                :visible {!env_loading && env_error == "" && arraylength(env_i3pm_vars) > 0}
                (label
                  :class "env-section-title"
                  :halign "start"
                  :text "I3PM Variables")
                (scroll
                  :class "env-scroll-i3pm"
                  :vscroll true
                  :hscroll false
                  :vexpand false
                  :height 120
                  (box
                    :class "env-vars-list env-vars-list-i3pm"
                    :orientation "v"
                    :space-evenly false
                    (for var in {env_i3pm_vars}
                      (box
                        :class "env-var-row"
                        :orientation "h"
                        :space-evenly false
                        :visible {env_filter == "" || matches(var.key, "(?i).*''${env_filter}.*") || matches(var.value, "(?i).*''${env_filter}.*")}
                        (label
                          :class "env-var-key"
                          :halign "start"
                          :text "''${var.key}")
                        (label
                          :class "env-var-value"
                          :halign "start"
                          :hexpand true
                          :limit-width 50
                          :text "''${var.value}")))))
              ;; Other variables section
              ;; Note: Using fixed classes and structure to prevent scroll reset on parent updates
              (box
                :class "env-section env-section-other"
                :orientation "v"
                :space-evenly false
                :visible {!env_loading && env_error == "" && arraylength(env_other_vars) > 0}
                (label
                  :class "env-section-title"
                  :halign "start"
                  :text "Other Variables (''${arraylength(env_other_vars)})")
                (scroll
                  :class "env-scroll-other"
                  :vscroll true
                  :hscroll false
                  :vexpand false
                  :height 100
                  (box
                    :class "env-vars-list env-vars-list-other"
                    :orientation "v"
                    :space-evenly false
                    (for var in {env_other_vars}
                      (box
                        :class "env-var-row"
                        :orientation "h"
                        :space-evenly false
                        :visible {env_filter == "" || matches(var.key, "(?i).*''${env_filter}.*") || matches(var.value, "(?i).*''${env_filter}.*")}
                        (label
                          :class "env-var-key env-var-key-other"
                          :halign "start"
                          :text "''${var.key}")
                        (label
                          :class "env-var-value env-var-value-other"
                          :halign "start"
                          :hexpand true
                          :limit-width 50
                          :text "''${var.value}")))))))))))

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
            :onclick "${projectCreateOpenScript}/bin/project-create-open"
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
            :onclick "${appCreateOpenScript}/bin/app-create-open"
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
      ;; Projects View - matches windows-view structure with scroll at top level
      (defwidget projects-view []
        (scroll
          :vscroll true
          :hscroll false
          :vexpand true
          (box
            :class "content-container"
            :orientation "v"
            :space-evenly false
            :vexpand true
            ;; Feature 094 US3: Projects tab header with New Project button (T066)
            ;; Feature 099 UX: Added filter, expand/collapse all (icons only)
            (box
              :class "projects-header-container"
              :orientation "v"
              :space-evenly false
              :visible {!project_creating}
              ;; Row 1: Title and action buttons
              (box
                :class "projects-header"
                :orientation "h"
                :space-evenly false
                (label
                  :class "projects-header-title"
                  :halign "start"
                  :hexpand true
                  :text "Projects")
                ;; Expand/Collapse All toggle (icon only)
                (button
                  :class "header-icon-button expand-collapse-btn"
                  :onclick "${toggleExpandAllScript}/bin/toggle-expand-all-projects"
                  :tooltip {projects_all_expanded ? "Collapse all" : "Expand all"}
                  {projects_all_expanded ? "󰅀" : "󰅂"})
                ;; New project button (icon only)
                (button
                  :class "header-icon-button new-project-btn"
                  :onclick "${projectCreateOpenScript}/bin/project-create-open"
                  :tooltip "Create new project"
                  "󰐕"))
              ;; Row 2: Filter/search input
              (box
                :class "projects-filter-row"
                :orientation "h"
                :space-evenly false
                (box
                  :class "filter-input-container"
                  :orientation "h"
                  :space-evenly false
                  :hexpand true
                  (label
                    :class "filter-icon"
                    :text "󰍉")
                  (input
                    :class "project-filter-input"
                    :hexpand true
                    :value project_filter
                    :onchange "eww --config $HOME/.config/eww-monitoring-panel update project_filter={}"
                    :timeout "100ms")
                  (button
                    :class "filter-clear-button"
                    :visible {project_filter != ""}
                    :onclick "eww --config $HOME/.config/eww-monitoring-panel update 'project_filter='"
                    :tooltip "Clear filter"
                    "󰅖"))
                ;; Result count when filtering - count matching worktrees
                (label
                  :class "filter-count"
                  :visible {project_filter != ""}
                  :text {jq(projects_data.discovered_repositories ?: [], "[.[].worktrees[]? | select((.branch // \"\") | test(\"(?i).*" + project_filter + ".*\") or ((.branch_number // \"\") | test(\"^" + project_filter + "\")))] | length")})))
            ;; Feature 094 US3: Project create form (T067)
            (revealer
              :transition "slidedown"
              :reveal project_creating
              :duration "200ms"
              (project-create-form))
            ;; Feature 099 T020: Worktree create form
            (revealer
              :transition "slidedown"
              :reveal worktree_creating
              :duration "200ms"
              (worktree-create-form :parent_project worktree_form_parent_project))
            ;; Feature 094 US4: Delete confirmation dialog (T088)
            (project-delete-confirmation)
            ;; Feature 102: Worktree delete confirmation dialog
            (worktree-delete-confirmation)
            ;; Error state
            (box
              :class "error-message"
              :visible {projects_data.status == "error"}
              (label :text "Error: ''${projects_data.error ?: 'Unknown error'}"))
            ;; Feature 100: Bare Repositories from repos.json (replaces legacy main_projects)
            ;; Shows repositories discovered via `i3pm discover`
            (box
              :class "projects-list"
              :orientation "v"
              :space-evenly false
              (for repo in {projects_data.discovered_repositories ?: []}
                (box
                  :orientation "v"
                  :space-evenly false
                  ;; Filter matches: repo fields OR any worktree branch/number
                  :visible {project_filter == "" ||
                            matches(repo.name ?: "", "(?i).*" + replace(project_filter, " ", ".*") + ".*") ||
                            matches(repo.qualified_name ?: "", "(?i).*" + replace(project_filter, " ", ".*") + ".*") ||
                            matches(repo.account ?: "", "(?i).*" + project_filter + ".*") ||
                            matches(repo.display_name ?: "", "(?i).*" + replace(project_filter, " ", ".*") + ".*") ||
                            jq(repo.worktrees ?: [], "any(.[]; (.branch // \"\") | test(\"(?i).*" + project_filter + ".*\"))") ||
                            jq(repo.worktrees ?: [], "any(.[]; (.branch_number // \"\") | test(\"^" + project_filter + "\"))")}
                  (discovered-repo-card :repo repo)
                  ;; Nested worktrees (visible when parent is expanded)
                  (revealer
                    :transition "slidedown"
                    :duration "150ms"
                    :reveal {expanded_projects == "all" || jq(expanded_projects, "index(\"" + repo.qualified_name + "\") != null")}
                    (box
                      :orientation "v"
                      :space-evenly false
                      :class "worktrees-container"
                      (for wt in {repo.worktrees ?: []}
                        (box
                          :visible {project_filter == "" ||
                                    matches(wt.branch ?: "", "(?i).*" + project_filter + ".*") ||
                                    matches(wt.branch_number ?: "", "^" + project_filter) ||
                                    matches(wt.display_name ?: "", "(?i).*" + project_filter + ".*")}
                          (discovered-worktree-card :worktree wt)))))))))))

      ;; Feature 100: Discovered bare repository card
      (defwidget discovered-repo-card [repo]
        (eventbox
          :onhover "eww --config $HOME/.config/eww-monitoring-panel update hover_project_name=''${repo.qualified_name}"
          :onhoverlost "eww --config $HOME/.config/eww-monitoring-panel update hover_project_name='''"
          (box
            :class {"repository-card project-card discovered-repo" + (repo.is_active ? " active-project" : "") + (repo.has_dirty_worktrees ? " has-dirty" : "")}
            :orientation "v"
            :space-evenly false
            (box
              :class "project-card-header"
              :orientation "h"
              :space-evenly false
              :hexpand true
              ;; Expand/collapse toggle
              (eventbox
                :cursor "pointer"
                :onclick "${toggleProjectExpandedScript}/bin/toggle-project-expanded ''${repo.qualified_name}"
                :tooltip {(expanded_projects == "all" || jq(expanded_projects, "index(\"" + repo.qualified_name + "\") != null")) ? "Collapse worktrees" : "Expand worktrees"}
                (box
                  :class "expand-toggle"
                  :valign "center"
                  (label
                    :class "expand-icon"
                    :text {(expanded_projects == "all" || jq(expanded_projects, "index(\"" + repo.qualified_name + "\") != null")) ? "󰅀" : "󰅂"})))
              ;; Main content
              (box
                :class "project-main-content"
                :orientation "h"
                :space-evenly false
                :hexpand true
                (box
                  :class "project-icon-container"
                  :orientation "v"
                  :valign "center"
                  (label
                    :class "project-icon"
                    :text "''${repo.icon}"))
                (box
                  :class "project-info"
                  :orientation "v"
                  :space-evenly false
                  :hexpand true
                  (box
                    :orientation "h"
                    :space-evenly false
                    (label
                      :class "project-card-name"
                      :halign "start"
                      :limit-width 20
                      :truncate true
                      :text "''${repo.qualified_name}"
                      :tooltip "''${repo.qualified_name}")
                    (label
                      :class "worktree-count-badge"
                      :visible {(repo.worktree_count ?: 0) > 0}
                      :text "''${repo.worktree_count} 🌿"))
                  (label
                    :class "project-card-path"
                    :halign "start"
                    :limit-width 25
                    :truncate true
                    :text "''${repo.directory_display ?: repo.directory}"
                    :tooltip "''${repo.directory}")))
              ;; Action buttons (visible on hover) - Feature 102: Added to discovered-repo-card
              (box
                :class "project-action-bar"
                :orientation "h"
                :space-evenly false
                :visible {hover_project_name == repo.qualified_name && !project_deleting}
                ;; Copy directory path to clipboard
                (eventbox
                  :cursor "pointer"
                  :onclick "echo -n ''\'''${repo.directory}' | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification='Copied: ''${repo.directory}' success_notification_visible=true && (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification_visible=false) &"
                  :tooltip "Copy directory path"
                  (label :class "action-btn action-copy" :text "󰆏"))
                ;; [+ New Worktree] button
                (eventbox
                  :cursor "pointer"
                  :onclick "${worktreeCreateOpenScript}/bin/worktree-create-open ''${repo.qualified_name}"
                  :tooltip "Create new worktree"
                  (label :class "action-btn action-add" :text "󰐕")))
              ;; Status badges
              (box
                :class "project-badges"
                :orientation "h"
                :space-evenly false
                (label
                  :class "badge badge-active"
                  :visible {repo.is_active}
                  :text "●"
                  :tooltip "Active")
                (label
                  :class "badge badge-dirty"
                  :visible {repo.has_dirty_worktrees}
                  :text "●"
                  :tooltip "Has uncommitted changes"))))))

      ;; Feature 100: Discovered worktree card (nested under repo)
      ;; Feature 101: Click to switch to worktree context for app launching
      ;; Feature 102: Discovered worktree card with hover actions for delete
      ;; Note: Using Eww onhover/onhoverlost because CSS :hover doesn't work with nested eventbox
      (defwidget discovered-worktree-card [worktree]
        (box
          :class {"worktree-card-wrapper" + (worktree.is_main ? " is-main-worktree" : "")}
          (eventbox
            :cursor "pointer"
            :onclick "i3pm worktree switch ''${worktree.qualified_name}"
            :onhover "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update hover_worktree_name=''${worktree.qualified_name}"
            :onhoverlost "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update hover_worktree_name='''"
            (box
              :class {"worktree-card" + (worktree.is_active ? " active-worktree" : "") + (worktree.git_is_dirty ? " dirty-worktree" : "")}
              :orientation "h"
              :space-evenly false
              ;; Main content
              (box
                :orientation "h"
                :space-evenly false
                :hexpand true
                ;; Active indicator dot - valign start to prevent stretching on hover
                (label
                  :class {worktree.is_active ? "active-indicator" : "active-indicator-placeholder"}
                  :valign "start"
                  :text "●"
                  :tooltip {worktree.is_active ? "Active worktree" : ""})
                ;; Feature 109: Branch number badge, main icon, or feature branch icon - valign start to prevent stretching
                (box
                  :class "branch-number-badge-container"
                  :valign "start"
                  (eventbox
                    :cursor {(worktree.branch_number ?: "") != "" ? "pointer" : "default"}
                    :onclick {(worktree.branch_number ?: "") != "" ? "echo -n '#''${worktree.branch_number}' | wl-copy && notify-send -t 1500 'Copied' '#''${worktree.branch_number}'" : ""}
                    :tooltip {(worktree.branch_number ?: "") != "" ? "Click to copy #''${worktree.branch_number}" : (worktree.is_main ? "Main branch" : "Feature branch")}
                    (label
                      :class {(worktree.branch_number ?: "") != "" ? "branch-number-badge" : (worktree.is_main ? "branch-main-badge" : "branch-feature-badge")}
                      :text {(worktree.branch_number ?: "") != "" ? worktree.branch_number : (worktree.is_main ? "⚑" : "🌿")})))
                (box
                  :class "worktree-info"
                  :orientation "v"
                  :space-evenly false
                  :hexpand true
                  (box
                    :orientation "h"
                    :space-evenly false
                    ;; Feature 109: Show description for numbered branches, full name otherwise
                    (label
                      :class "worktree-branch"
                      :halign "start"
                      :limit-width 25
                      :truncate true
                      :text {(worktree.has_branch_number ?: false) ? (worktree.branch_description ?: worktree.branch) : worktree.branch}
                      :tooltip "''${worktree.branch}")
                    (label
                      :class "worktree-commit"
                      :halign "start"
                      :limit-width 10
                      :text {" @ " + (worktree.commit ?: "unknown")})
                    ;; Feature 108 T019: Conflict indicator (highest priority)
                    (label
                      :class "git-conflict"
                      :visible {worktree.git_has_conflicts ?: false}
                      :text " ''${worktree.git_conflict_indicator}"
                      :tooltip "Has unresolved merge conflicts")
                    ;; Dirty indicator (T027: with tooltip showing file breakdown)
                    (label
                      :class "git-dirty"
                      :visible {worktree.git_is_dirty}
                      :text " ''${worktree.git_dirty_indicator}"
                      :tooltip {(worktree.git_staged_count ?: 0) > 0 || (worktree.git_modified_count ?: 0) > 0 || (worktree.git_untracked_count ?: 0) > 0 ?
                        ((worktree.git_staged_count ?: 0) > 0 ? "''${worktree.git_staged_count} staged" : "") +
                        ((worktree.git_staged_count ?: 0) > 0 && ((worktree.git_modified_count ?: 0) > 0 || (worktree.git_untracked_count ?: 0) > 0) ? ", " : "") +
                        ((worktree.git_modified_count ?: 0) > 0 ? "''${worktree.git_modified_count} modified" : "") +
                        ((worktree.git_modified_count ?: 0) > 0 && (worktree.git_untracked_count ?: 0) > 0 ? ", " : "") +
                        ((worktree.git_untracked_count ?: 0) > 0 ? "''${worktree.git_untracked_count} untracked" : "")
                        : "Uncommitted changes"})
                    ;; T028: Sync indicator with tooltip showing commit counts
                    (label
                      :class "git-sync"
                      :visible {(worktree.git_sync_indicator ?: "") != ""}
                      :text " ''${worktree.git_sync_indicator}"
                      :tooltip {((worktree.git_ahead ?: 0) > 0 ? "''${worktree.git_ahead} commits to push" : "") +
                        ((worktree.git_ahead ?: 0) > 0 && (worktree.git_behind ?: 0) > 0 ? ", " : "") +
                        ((worktree.git_behind ?: 0) > 0 ? "''${worktree.git_behind} commits to pull" : "")})
                    ;; Feature 108 T018/T037: Merge badge with tooltip
                    (label
                      :class "badge-merged"
                      :visible {worktree.git_is_merged ?: false}
                      :text " ✓"
                      :tooltip "Branch merged into main")
                    ;; Feature 108 T032/T034: Stale indicator with tooltip
                    (label
                      :class "badge-stale"
                      :visible {worktree.git_is_stale ?: false}
                      :text " 💤"
                      :tooltip "No activity in 30+ days"))
                  ;; Feature 109: Path row with copy button on hover
                  (box
                    :class "worktree-path-row"
                    :orientation "h"
                    :space-evenly false
                    (label
                      :class "worktree-path"
                      :halign "start"
                      :limit-width 28
                      :truncate true
                      :text "''${worktree.directory_display}"
                      :tooltip "''${worktree.path}")
                    ;; Copy directory button (visible on hover)
                    (eventbox
                      :class {"copy-btn-container" + (hover_worktree_name == worktree.qualified_name ? " visible" : "")}
                      :cursor "pointer"
                      :onclick "echo -n '#{worktree.path}' | wl-copy && notify-send -t 1500 'Copied' '#{worktree.directory_display}'"
                      :tooltip "Copy directory path"
                      (label
                        :class "copy-btn"
                        :text "")))
                  ;; Feature 108 T029: Last commit info (visible on hover)
                  (label
                    :class "worktree-last-commit"
                    :halign "start"
                    :visible {hover_worktree_name == worktree.qualified_name && (worktree.git_last_commit_relative ?: "") != ""}
                    :limit-width 50
                    :truncate true
                    :text {(worktree.git_last_commit_relative ?: "") + (worktree.git_last_commit_message != "" ? " - " + (worktree.git_last_commit_message ?: "") : "")}
                    :tooltip {worktree.git_status_tooltip ?: ""})))
              ;; Feature 102: Action buttons (visible on hover, hidden for main worktree)
              ;; Feature 109 T027: Added Git action button for lazygit launch
              ;; Feature 109 T052-T057: Added Terminal, Editor, File Manager, Copy Path buttons
              (box
                :class {"worktree-action-bar" + (hover_worktree_name == worktree.qualified_name && !worktree.is_main ? " visible" : "")}
                :orientation "h"
                :space-evenly false
                :halign "end"
                ;; Feature 109 T053: Terminal button - opens scratchpad terminal in worktree directory
                (eventbox
                  :cursor "pointer"
                  :onclick "i3pm scratchpad toggle ''${worktree.qualified_name}"
                  :tooltip "Open terminal (t)"
                  (label :class "action-btn action-terminal" :text ""))
                ;; Feature 109 T054: VS Code button - opens code editor in worktree directory
                (eventbox
                  :cursor "pointer"
                  :onclick "code --folder-uri file://''${worktree.path}"
                  :tooltip "Open in VS Code (e)"
                  (label :class "action-btn action-editor" :text "󰨞"))
                ;; Feature 109 T055: File Manager button - opens yazi in worktree directory
                (eventbox
                  :cursor "pointer"
                  :onclick "ghostty -e yazi ''${worktree.path}"
                  :tooltip "Open file manager (f)"
                  (label :class "action-btn action-files" :text "󰉋"))
                ;; Feature 109 T027: Git button - launches lazygit with context-aware view
                (eventbox
                  :cursor "pointer"
                  :onclick "${pkgs.ghostty}/bin/ghostty -e lazygit -p ''${worktree.path}"
                  :tooltip "Open lazygit (Shift+L)"
                  (label :class "action-btn action-git" :text "󰊢"))
                ;; Feature 109 T056: Copy Path button
                (eventbox
                  :cursor "pointer"
                  :onclick "echo -n ''\'''${worktree.path}' | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification='Copied: ''${worktree.path}' success_notification_visible=true && (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification_visible=false) &"
                  :tooltip "Copy path (y)"
                  (label :class "action-btn action-copy" :text "󰆏"))
                ;; Delete button with confirmation
                (eventbox
                  :cursor "pointer"
                  :onclick "${worktreeDeleteOpenScript}/bin/worktree-delete-open ''${worktree.qualified_name} ''${worktree.branch} ''${worktree.git_is_dirty}"
                  :tooltip "Delete worktree (d)"
                  (label :class "action-btn action-delete" :text "󰆴")))
              ;; Status badges
              (box
                :class "worktree-badges"
                :orientation "h"
                :space-evenly false
                (label
                  :class "badge badge-active"
                  :visible {worktree.is_active}
                  :text "●"
                  :tooltip "Active worktree")
                (label
                  :class "badge badge-main"
                  :visible {worktree.is_main}
                  :text "M"
                  :tooltip "Main worktree"))))))

      ;; Feature 099 T012: Repository project card with expand/collapse toggle, worktree count badge
      (defwidget repository-project-card [project]
        (eventbox
          :onhover "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update hover_project_name=''${project.name}"
          :onhoverlost "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update hover_project_name='''"
          (box
            ;; UX2: Add "selected" class when this project is keyboard-selected
            :class {"repository-card project-card" + (project.is_active ? " active-project" : "") + (project.has_dirty_worktrees ? " has-dirty" : "") + (project_selected_name == project.name ? " selected" : "")}
            :orientation "v"
            :space-evenly false
            ;; Row 1: Expand toggle + Icon + Name/Path + Badges + Actions
            (box
              :class "project-card-header"
              :orientation "h"
              :space-evenly false
              :hexpand true
              ;; Feature 099 T015: Expand/collapse toggle
              (eventbox
                :cursor "pointer"
                :onclick "${toggleProjectExpandedScript}/bin/toggle-project-expanded ''${project.name}"
                :tooltip {(expanded_projects == "all" || jq(expanded_projects, "index(\"" + project.name + "\") != null")) ? "Collapse worktrees" : "Expand worktrees"}
                (box
                  :class "expand-toggle"
                  :valign "center"
                  (label
                    :class "expand-icon"
                    :text {(expanded_projects == "all" || jq(expanded_projects, "index(\"" + project.name + "\") != null")) ? "󰅀" : "󰅂"})))
              ;; Main content area - clickable for project switch
              (eventbox
                :cursor "pointer"
                :hexpand true
                :onclick "i3pm worktree switch ''${project.name}"
                (box
                  :class "project-main-content"
                  :orientation "h"
                  :space-evenly false
                  :hexpand true
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
                    :hexpand true
                    (box
                      :orientation "h"
                      :space-evenly false
                      (label
                        :class "project-card-name"
                        :halign "start"
                        :limit-width 15
                        :truncate true
                        :text "''${project.display_name ?: project.name}"
                        :tooltip "''${project.display_name ?: project.name}")
                      ;; Feature 099 T012: Worktree count badge (when collapsed or always)
                      (label
                        :class "worktree-count-badge"
                        :visible {(project.worktree_count ?: 0) > 0}
                        :text "''${project.worktree_count} 🌿"
                        :tooltip "''${project.worktree_count} worktrees"))
                    (label
                      :class "project-card-path"
                      :halign "start"
                      :limit-width 18
                      :truncate true
                      :text "''${project.directory_display ?: project.directory}"
                      :tooltip "''${project.directory}"))))
              ;; Action buttons (visible on hover)
              (box
                :class "project-action-bar"
                :orientation "h"
                :space-evenly false
                :visible {hover_project_name == project.name && editing_project_name != project.name && !project_deleting}
                ;; UX4: Copy directory path to clipboard
                (eventbox
                  :cursor "pointer"
                  :onclick "echo -n ''\'''${project.directory}' | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification='Copied: ''${project.directory}' success_notification_visible=true && (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification_visible=false) &"
                  :tooltip "Copy directory path"
                  (label :class "action-btn action-copy" :text "󰆏"))
                ;; Feature 099 T019: [+ New Worktree] button
                (eventbox
                  :cursor "pointer"
                  :onclick "${worktreeCreateOpenScript}/bin/worktree-create-open ''${project.name}"
                  :tooltip "Create new worktree"
                  (label :class "action-btn action-add" :text "󰐕"))
                (eventbox
                  :cursor "pointer"
                  :onclick "${projectEditOpenScript}/bin/project-edit-open \"''${project.name}\" \"''${project.display_name ?: project.name}\" \"''${project.icon}\" \"''${project.directory}\" \"''${project.scope ?: 'scoped'}\" \"''${project.remote.enabled}\" \"''${project.remote.host}\" \"''${project.remote.user}\" \"''${project.remote.remote_dir}\" \"''${project.remote.port}\""
                  :tooltip "Edit project"
                  (label :class "action-btn action-edit" :text "󰏫"))
                (eventbox
                  :cursor "pointer"
                  :onclick "${projectDeleteOpenScript}/bin/project-delete-open \"''${project.name}\" \"''${project.display_name ?: project.name}\""
                  :tooltip "Delete project"
                  (label :class "action-btn action-delete" :text "󰆴")))
              ;; Status badges
              (box
                :class "project-badges"
                :orientation "h"
                :space-evenly false
                (label
                  :class "badge badge-active"
                  :visible {project.is_active}
                  :text "●"
                  :tooltip "Active project")
                (label
                  :class "badge badge-dirty"
                  :visible {project.has_dirty_worktrees}
                  :text "●"
                  :tooltip "Has dirty worktrees")
                (label
                  :class "badge badge-missing"
                  :visible {project.status == "missing"}
                  :text "⚠"
                  :tooltip "Directory not found")))
            ;; Row 2: Git branch (full width row)
            (box
              :class "git-branch-row"
              :orientation "h"
              :space-evenly false
              :visible {(project.git_branch ?: "") != ""}
              (label
                :class "git-branch-icon"
                :text "󰘬")
              (label
                :class "git-branch-text"
                :wrap true
                :xalign 0
                :text "''${project.git_branch}"
                :tooltip "Branch: ''${project.git_branch}")
              (label
                :class "git-dirty"
                :visible {project.git_is_dirty}
                :text "''${project.git_dirty_indicator}"
                :tooltip "Uncommitted changes")))))

      ;; Feature 099 T054: Orphaned worktree card widget
      (defwidget orphaned-worktree-card [project]
        (box
          :class "orphaned-worktree-card"
          :orientation "h"
          :space-evenly false
          (label
            :class "orphaned-icon"
            :text "⚠️")
          (box
            :class "orphaned-info"
            :orientation "v"
            :space-evenly false
            :hexpand true
            (label
              :class "orphaned-name"
              :halign "start"
              :text "''${project.display_name ?: project.name}")
            (label
              :class "orphaned-path"
              :halign "start"
              :text "''${project.directory_display ?: project.directory}"))
          (box
            :class "orphaned-actions"
            :orientation "h"
            :space-evenly false
            (eventbox
              :cursor "pointer"
              :onclick "i3pm worktree recover ''${project.name}"
              :tooltip "Recover (register parent repository)"
              (label :class "action-btn action-recover" :text "󰑓"))
            (eventbox
              :cursor "pointer"
              :onclick "${worktreeDeleteScript}/bin/worktree-delete ''${project.name}"
              :tooltip "Delete orphaned entry"
              (label :class "action-btn action-delete" :text "󰆴")))))

      ;; Original project-card kept for backward compatibility
      (defwidget project-card [project]
        (eventbox
          :onhover "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update hover_project_name=''${project.name}"
          :onhoverlost "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update hover_project_name='''"
          (box
            :class {"project-card" + (project.is_active ? " active-project" : "")}
            :orientation "v"
            :space-evenly false
            ;; Row 1: Icon + Name/Path + Actions + JSON trigger (like window-widget pattern)
            (box
              :class "project-card-header"
              :orientation "h"
              :space-evenly false
              :hexpand true
              ;; Main content area - clickable, takes remaining space leaving room for JSON trigger sibling
              (eventbox
                :cursor "pointer"
                :hexpand true
                (box
                  :class "project-main-content"
                  :orientation "h"
                  :space-evenly false
                  :hexpand true
                  ;; Icon
                  (box
                    :class "project-icon-container"
                    :orientation "v"
                    :valign "center"
                    (label
                      :class "project-icon"
                      :text "''${project.icon}"))
                  ;; Project info - takes remaining space within main content
                  (box
                    :class "project-info"
                    :orientation "v"
                    :space-evenly false
                    :hexpand true
                    (label
                      :class "project-card-name"
                      :halign "start"
                      :limit-width 15
                      :truncate true
                      :text "''${project.display_name ?: project.name}"
                      :tooltip "''${project.display_name ?: project.name}")
                    (label
                      :class "project-card-path"
                      :halign "start"
                      :limit-width 18
                      :truncate true
                      :text "''${project.directory_display ?: project.directory}"
                      :tooltip "''${project.directory}"))
                  ;; Action buttons (visible on hover)
                  (box
                    :class "project-action-bar"
                    :orientation "h"
                    :space-evenly false
                    :visible {hover_project_name == project.name && editing_project_name != project.name && !project_deleting}
                    (eventbox
                      :cursor "pointer"
                      :onclick "${projectEditOpenScript}/bin/project-edit-open \"''${project.name}\" \"''${project.display_name ?: project.name}\" \"''${project.icon}\" \"''${project.directory}\" \"''${project.scope ?: 'scoped'}\" \"''${project.remote.enabled}\" \"''${project.remote.host}\" \"''${project.remote.user}\" \"''${project.remote.remote_dir}\" \"''${project.remote.port}\""
                      :tooltip "Edit project"
                      (label :class "action-btn action-edit" :text "󰏫"))
                    (eventbox
                      :cursor "pointer"
                      :onclick "${projectDeleteOpenScript}/bin/project-delete-open \"''${project.name}\" \"''${project.display_name ?: project.name}\""
                      :tooltip "Delete project"
                      (label :class "action-btn action-delete" :text "󰆴")))))
              ;; JSON expand trigger icon - SIBLING at header level (like Windows tab)
              ;; NO halign/width - let GTK box layout handle positioning naturally
              (eventbox
                :onhover "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update json_hover_project=''${project.name}"
                :onhoverlost "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update json_hover_project='''"
                :tooltip "Hover to view JSON"
                (box
                  :class {"json-expand-trigger" + (json_hover_project == project.name ? " expanded" : "")}
                  :valign "center"
                  (label
                    :class "json-expand-icon"
                    :text {json_hover_project == project.name ? "󰅀" : "󰅂"}))))
            ;; Row 2: Git branch (full width row)
            (box
              :class "git-branch-row"
              :orientation "h"
              :space-evenly false
              :visible {(project.git_branch ?: "") != ""}
              (label
                :class "git-branch-icon"
                :text "󰘬")
              (label
                :class "git-branch-text"
                :wrap true
                :xalign 0
                :text "''${project.git_branch}"
                :tooltip "Branch: ''${project.git_branch}")
              ;; Git dirty indicator
              (label
                :class "git-dirty"
                :visible {project.git_is_dirty}
                :text "''${project.git_dirty_indicator}"
                :tooltip "Uncommitted changes"))
            ;; Row 3: Badges + Actions
            (box
              :class "project-card-meta"
              :orientation "h"
              :space-evenly false
              ;; Badges (left aligned)
              (label
                :class "badge badge-active"
                :visible {project.is_active}
                :text "●"
                :tooltip "Active project")
              (label
                :class "badge badge-missing"
                :visible {project.status == "missing"}
                :text "⚠"
                :tooltip "Directory not found")
              (label
                :class "badge badge-remote"
                :visible {project.is_remote}
                :text "󰒍"
                :tooltip "Remote project"))
            ;; JSON panel (slides down when expand icon is hovered) - like Window tab
            (revealer
              :reveal {json_hover_project == project.name && editing_project_name != project.name}
              :transition "slidedown"
              :duration "150ms"
              (eventbox
                :onhover "eww --config $HOME/.config/eww-monitoring-panel update json_hover_project=''${project.name}"
                :onhoverlost "eww --config $HOME/.config/eww-monitoring-panel update json_hover_project='''"
                (box
                  :class "project-json-tooltip"
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
                      :text "Project JSON: ''${project.name}")
                    (eventbox
                      :cursor "pointer"
                      :onclick "${copyProjectJsonScript} ''${project.name} &"
                      :tooltip "Copy JSON to clipboard"
                      (label
                        :class {"json-copy-btn" + (copied_project_name == project.name ? " copied" : "")}
                        :text {copied_project_name == project.name ? "󰄬" : "󰆏"})))
                  ;; Scrollable JSON content with syntax highlighting
                  (scroll
                    :vscroll true
                    :hscroll false
                    :vexpand false
                    :height 200
                    (label
                      :class "json-content"
                      :halign "start"
                      :text "(JSON preview disabled to reduce CPU)"
                      :wrap false)))))
            ;; Feature 094: Inline edit form (T038)
            (revealer
              :reveal {editing_project_name == project.name}
              :transition "slidedown"
              :duration "300ms"
              (project-edit-form :project project)))))

      (defwidget worktree-card [project]
        (eventbox
          :onhover "eww --config $HOME/.config/eww-monitoring-panel update hover_project_name=''${project.name}"
          :onhoverlost "eww --config $HOME/.config/eww-monitoring-panel update hover_project_name='''"
          (box
            ;; UX2: Add "selected" class when this worktree is keyboard-selected
            :class {"worktree-card" + (project_selected_name == project.name ? " selected" : "")}
            :orientation "h"
            :space-evenly false
            ;; Worktree tree indicator
            (label
              :class "worktree-tree"
              :text "├─")
            ;; Icon
            (box
              :class "project-icon-container"
              :orientation "v"
              :valign "center"
              (label
                :class "project-icon worktree-icon"
                :text "''${project.icon}"))
            ;; UX5: Branch number badge (from Feature 098 branch_metadata)
            (label
              :class "branch-number-badge"
              :visible {(project.branch_metadata.number ?: "") != ""}
              :text "''${project.branch_metadata.number ?: ""}"
              :tooltip "Branch #''${project.branch_metadata.number ?: ""} (''${project.branch_metadata.type ?: "feature"})")
            ;; Project info - takes remaining space
            (box
              :class "project-info"
              :orientation "v"
              :space-evenly false
              :hexpand true
              (box
                :orientation "h"
                :space-evenly false
                (label
                  :class "project-card-name worktree-name"
                  :halign "start"
                  :limit-width 16
                  :truncate true
                  :text "''${project.display_name ?: project.name}"))
              (label
                :class "project-card-path"
                :halign "start"
                :limit-width 22
                :truncate true
                :text "''${project.directory_display ?: project.directory}"))
            ;; Git branch - styled like project-card
            (box
              :class "git-branch-container worktree-branch"
              :orientation "h"
              :space-evenly false
              :hexpand true
              :visible {(project.branch_name ?: "") != ""}
              (label
                :class "git-branch-icon"
                :text "󰘬")
              (label
                :class "git-branch-text"
                :wrap true
                :xalign 0
                :text "''${project.branch_name}"
                :tooltip "Branch: ''${project.branch_name}")
              ;; Feature 099 T050: Dirty indicator (● red)
              (label
                :class "git-dirty"
                :visible {project.git_is_dirty}
                :text "''${project.git_dirty_indicator}"
                :tooltip "Uncommitted changes")
              ;; Feature 099 T051: Ahead/behind count display (↑3 ↓2)
              (label
                :class "git-sync-ahead"
                :visible {(project.git_ahead ?: 0) > 0}
                :text "↑''${project.git_ahead}"
                :tooltip "''${project.git_ahead} commits ahead of remote")
              (label
                :class "git-sync-behind"
                :visible {(project.git_behind ?: 0) > 0}
                :text "↓''${project.git_behind}"
                :tooltip "''${project.git_behind} commits behind remote"))
            ;; Remote indicator
            (label
              :class "badge badge-remote"
              :visible {project.is_remote}
              :text "󰒍")
            ;; Action buttons (visible on hover)
            (box
              :class "worktree-actions"
              :visible {hover_project_name == project.name && editing_project_name != project.name}
              :orientation "h"
              :space-evenly false
              ;; UX4: Copy directory path to clipboard
              (eventbox
                :cursor "pointer"
                :onclick "echo -n ''\'''${project.directory}' | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification='Copied: ''${project.directory}' success_notification_visible=true && (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification_visible=false) &"
                :tooltip "Copy directory path"
                (label :class "action-btn action-copy" :text "󰆏"))
              (eventbox
                :cursor "pointer"
                :onclick "${worktreeEditOpenScript}/bin/worktree-edit-open \"''${project.name}\" \"''${project.display_name ?: project.name}\" \"''${project.icon}\" \"''${project.branch_name}\" \"''${project.worktree_path}\" \"''${project.parent_project}\""
                :tooltip "Edit worktree"
                (label :class "action-btn action-edit" :text "󰏫"))
              (eventbox
                :cursor "pointer"
                :onclick "${worktreeDeleteScript}/bin/worktree-delete ''${project.name}"
                :tooltip "''${worktree_delete_confirm == project.name ? 'Click again to confirm' : 'Delete worktree'}"
                (label :class {"action-btn action-delete" + (worktree_delete_confirm == project.name ? " confirm" : "")} :text "''${worktree_delete_confirm == project.name ? '❗' : '󰆴'}")))
            ;; Active indicator
            (label
              :class "active-indicator"
              :visible {project.is_active}
              :text "●"))))

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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update edit_form_display_name={}")
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update edit_form_icon={}")
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
                    :onchange "eww --config $HOME/.config/eww-monitoring-panel update edit_form_remote_host={}")
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
                    :onchange "eww --config $HOME/.config/eww-monitoring-panel update edit_form_remote_user={}")
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
                    :onchange "eww --config $HOME/.config/eww-monitoring-panel update edit_form_remote_dir={}")
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
                    :onchange "eww --config $HOME/.config/eww-monitoring-panel update edit_form_remote_port={}")
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
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update panel_focus_mode=false && eww --config $HOME/.config/eww-monitoring-panel update editing_project_name=''' && eww --config $HOME/.config/eww-monitoring-panel update edit_form_error='''"
              "Cancel")
            ;; Feature 096 T021: Save button with loading state
            ;; Script reads editing_project_name from eww variable internally
            ;; Run in background (&) to avoid eww onclick timeout (2s default)
            (button
              :class "''${save_in_progress ? 'save-button-loading' : (validation_state.valid ? 'save-button' : 'save-button-disabled')}"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update save_in_progress=true && project-edit-save &"
              "''${save_in_progress ? 'Saving...' : 'Save'}"))))

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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update edit_form_display_name={}"))
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update edit_form_icon={}"))
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
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update panel_focus_mode=false && eww --config $HOME/.config/eww-monitoring-panel update editing_project_name=''' && eww --config $HOME/.config/eww-monitoring-panel update edit_form_error='''"
              "Cancel")
            ;; Run in background (&) to avoid eww onclick timeout (2s default)
            (button
              :class "save-button"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update save_in_progress=true && worktree-edit-save ''${project.name} &"
              "Save"))))

      ;; Feature 094 US5 T057-T058: Worktree create form widget
      ;; Shown when worktree_creating is true
      ;; Feature 102: Description is primary input, other fields auto-populate
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
          ;; Feature 102: Description field (PRIMARY INPUT)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Feature Description *")
            (input
              :class "field-input"
              :value worktree_form_description
              ;; Feature 102: Auto-populate all other fields from description
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update worktree_form_description='{}' && worktree-auto-populate '{}' &")
            (label
              :class "field-hint"
              :halign "start"
              :text "e.g., Add user authentication system"))
          ;; Branch name field (auto-generated, editable)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Branch Name")
            (input
              :class "field-input"
              :value worktree_form_branch_name
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update worktree_form_branch_name='{}'"
              :tooltip "Auto-generated from description, editable")
            (label
              :class "field-hint"
              :halign "start"
              :text "Auto-generated: NNN-short-name"))
          ;; Worktree path field (auto-populated, editable)
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Worktree Path")
            (input
              :class "field-input"
              :value worktree_form_path
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update worktree_form_path='{}'"
              :tooltip "Auto-generated from branch name, editable")
            (label
              :class "field-hint"
              :halign "start"
              :text "Auto-filled from branch name"))
          ;; Display name field (auto-populated, editable)
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update edit_form_display_name='{}'"
              :tooltip "Auto-generated from description, editable")
            (label
              :class "field-hint"
              :halign "start"
              :text "Auto-filled: NNN - Description"))
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update edit_form_icon='{}'"))
          ;; Feature 112: Speckit scaffolding checkbox (checked by default)
          (box
            :class "form-field form-field-checkbox"
            :orientation "h"
            :space-evenly false
            (checkbox
              :checked worktree_form_speckit
              :onchecked "eww --config $HOME/.config/eww-monitoring-panel update worktree_form_speckit=true"
              :onunchecked "eww --config $HOME/.config/eww-monitoring-panel update worktree_form_speckit=false")
            (label
              :class "field-label checkbox-label"
              :halign "start"
              :text "Setup speckit (creates specs directory)"))
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
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update panel_focus_mode=false && eww --config $HOME/.config/eww-monitoring-panel update worktree_creating=false && eww --config $HOME/.config/eww-monitoring-panel update worktree_form_description=''' && eww --config $HOME/.config/eww-monitoring-panel update worktree_form_branch_name=''' && eww --config $HOME/.config/eww-monitoring-panel update worktree_form_path=''' && eww --config $HOME/.config/eww-monitoring-panel update worktree_form_parent_project=''' && eww --config $HOME/.config/eww-monitoring-panel update worktree_form_repo_path=''' && eww --config $HOME/.config/eww-monitoring-panel update worktree_form_speckit=true && eww --config $HOME/.config/eww-monitoring-panel update edit_form_error='''"
              "Cancel")
            ;; Run in background (&) to avoid eww onclick timeout (2s default)
            (button
              :class "save-button"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update save_in_progress=true && worktree-create &"
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_form_name={}")
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_form_display_name={}"))
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_form_icon={}"))
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_form_working_dir={}")
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
              :onchecked "eww --config $HOME/.config/eww-monitoring-panel update create_form_remote_enabled=true"
              :onunchecked "eww --config $HOME/.config/eww-monitoring-panel update create_form_remote_enabled=false")
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
                  :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_form_remote_host={}")
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
                  :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_form_remote_user={}"))
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
                  :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_form_remote_dir={}")
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
                  :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_form_remote_port={}"))))
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
              :onclick "${projectCreateCancelScript}/bin/project-create-cancel"
              "Cancel")
            ;; Feature 096: Save button with loading state
            ;; Run in background (&) to avoid eww onclick timeout (2s default)
            (button
              :class "''${save_in_progress ? 'save-button-loading' : 'save-button'}"
              :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update save_in_progress=true && ${projectCreateSaveScript}/bin/project-create-save &"
              "''${save_in_progress ? 'Creating...' : 'Create'}"))))

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
                    :onchecked "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update delete_force=true"
                    :onunchecked "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update delete_force=false")
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
                :onclick "${projectDeleteCancelScript}/bin/project-delete-cancel"
                "Cancel")
              ;; Run in background (&) to avoid eww onclick timeout (2s default)
              (button
                :class "confirm-delete-button ''${delete_project_has_worktrees && !delete_force ? 'disabled' : '''}"
                :onclick {delete_project_has_worktrees && !delete_force ? "" : "${projectDeleteConfirmScript}/bin/project-delete-confirm &"}
                :tooltip "''${delete_project_has_worktrees && !delete_force ? 'Check force delete to proceed' : 'Permanently delete project'}"
                "🗑 Delete")))))

      ;; Feature 102: Worktree delete confirmation dialog
      (defwidget worktree-delete-confirmation []
        (revealer
          :reveal worktree_delete_dialog_visible
          :transition "slidedown"
          :duration "200ms"
          (box
            :class "delete-confirmation-dialog worktree-delete-dialog"
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
                :text "Delete Worktree"))
            ;; Worktree name display
            (label
              :class "project-name-display"
              :halign "start"
              :text "🌿 ''${worktree_delete_branch}")
            ;; Warning message
            (label
              :class "warning-message"
              :halign "start"
              :wrap true
              :text "This will remove the worktree directory and its contents. The branch will remain in git.")
            ;; Dirty worktree warning (shown only if worktree has uncommitted changes)
            (revealer
              :reveal worktree_delete_is_dirty
              :transition "slidedown"
              :duration "150ms"
              (box
                :class "worktree-warning dirty-warning"
                :orientation "v"
                :space-evenly false
                (label
                  :class "warning-icon"
                  :halign "start"
                  :text "⚠ This worktree has uncommitted changes")
                (label
                  :class "warning-detail"
                  :halign "start"
                  :wrap true
                  :text "Any uncommitted work will be lost. Consider committing or stashing changes first.")))
            ;; Action buttons
            (box
              :class "dialog-actions"
              :orientation "h"
              :space-evenly false
              :halign "end"
              (button
                :class "cancel-delete-button"
                :onclick "${worktreeDeleteCancelScript}/bin/worktree-delete-cancel"
                "Cancel")
              ;; Run in background (&) to avoid eww onclick timeout (2s default)
              (button
                :class "confirm-delete-button"
                :onclick "${worktreeDeleteConfirmScript}/bin/worktree-delete-confirm &"
                :tooltip "Permanently delete worktree"
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
                :onclick "${appDeleteCancelScript}/bin/app-delete-cancel"
                "Cancel")
              (button
                :class "confirm-delete-app-button"
                :onclick "${appDeleteConfirmScript}/bin/app-delete-confirm"
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_app_name={}")
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_app_display_name={}"))
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
                  :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_app_command={}"))
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
                :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_app_parameters={}")
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
                :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_app_expected_class={}")
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
                  :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_app_start_url={}")
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
                  :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_app_scope_url={}")
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_app_workspace={}")
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
              :onchange "eww --config $HOME/.config/eww-monitoring-panel update create_app_icon={}")
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
              :onclick "${appCreateCancelScript}/bin/app-create-cancel"
              "Cancel")
            (button
              :class "save-button"
              :onclick "${appCreateSaveScript}/bin/app-create-save"
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
                  :onclick "${projectConflictResolveScript}/bin/project-conflict-resolve keep-file ''${conflict_project_name}"
                  "Keep File Changes")
                (button
                  :class "conflict-button conflict-keep-ui"
                  :onclick "${projectConflictResolveScript}/bin/project-conflict-resolve keep-ui ''${conflict_project_name}"
                  "Keep My Changes")
                (button
                  :class "conflict-button conflict-merge"
                  :onclick "${projectConflictResolveScript}/bin/project-conflict-resolve merge-manual ''${conflict_project_name}"
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

      ;; Feature 096 T019: Error notification toast (persists until dismissed)
      (defwidget error-notification-toast []
        (revealer
          :reveal error_notification_visible
          :transition "slidedown"
          :duration "200ms"
          (box
            :class "error-notification-toast"
            :orientation "h"
            :space-evenly false
            :halign "center"
            (label
              :class "error-icon"
              :text "[ERR]")
            (label
              :class "error-message"
              :text error_notification)
            (button
              :class "error-dismiss"
              :onclick "eww update error_notification_visible=false error_notification=\"\""
              "x"))))

      ;; Feature 096 T019: Warning notification toast (auto-dismiss after 5s)
      (defwidget warning-notification-toast []
        (revealer
          :reveal warning_notification_visible
          :transition "slidedown"
          :duration "200ms"
          (box
            :class "warning-notification-toast"
            :orientation "h"
            :space-evenly false
            :halign "center"
            (label
              :class "warning-icon"
              :text "[!]")
            (label
              :class "warning-message"
              :text warning_notification)
            (button
              :class "warning-dismiss"
              :onclick "eww update warning_notification_visible=false warning_notification=\"\""
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
                :onclick "${appCreateOpenScript}/bin/app-create-open"
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
                    :text "󰆍"))
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
                :onclick "${appDeleteOpenScript}/bin/app-delete-open ''${app.name} ''${app.display_name} ''${app.ulid}"
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
              :onclick "${restartServiceScript}/bin/restart-service ''${service.service_name} ''${service.is_user_service ? 'true' : 'false'} &"
              :tooltip "Restart ''${service.display_name}"
              "⟳"))))

      ;; Feature 092: Events/Logs View - Real-time Sway IPC event log (T024)
      (defwidget events-view []
        (box
          :class "events-view-container"
          :orientation "v"
          :vexpand true
          :space-evenly false
          ;; Filter panel (collapsible)
          (box
            :class "filter-panel"
            :orientation "v"
            :space-evenly false
            :visible "''${events_data.status == 'ok'}"
            ;; Filter header (always visible)
            (eventbox
              :cursor "pointer"
              :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update filter_panel_expanded=''${!filter_panel_expanded}"
              (box
                :class "filter-header"
                :orientation "h"
                :space-evenly false
                (label
                  :class "filter-title"
                  :halign "start"
                  :hexpand true
                  :text "󰈙 Filter Events")
                (label
                  :class "filter-toggle"
                  :text "''${filter_panel_expanded ? '▼' : '▶'}")))
            ;; Filter controls (expandable)
            (box
              :class "filter-controls"
              :orientation "v"
              :space-evenly false
              :visible filter_panel_expanded
              ;; Global controls
              (box
                :class "filter-global-controls"
                :orientation "h"
                :space-evenly false
                (button
                  :class "filter-button"
                  :onclick "eww --config $HOME/.config/eww-monitoring-panel update filter_window_new=true filter_window_close=true filter_window_focus=true filter_window_blur=true filter_window_move=true filter_window_floating=true filter_window_fullscreen_mode=true filter_window_title=true filter_window_mark=true filter_window_urgent=true filter_workspace_focus=true filter_workspace_init=true filter_workspace_empty=true filter_workspace_move=true filter_workspace_rename=true filter_workspace_urgent=true filter_workspace_reload=true filter_output_connected=true filter_output_disconnected=true filter_output_profile_changed=true filter_output_unspecified=true filter_binding_run=true filter_mode_change=true filter_shutdown_exit=true filter_tick_manual=true filter_i3pm_project_switch=true filter_i3pm_project_clear=true filter_i3pm_visibility_hidden=true filter_i3pm_visibility_shown=true filter_i3pm_scratchpad_move=true filter_i3pm_scratchpad_show=true filter_i3pm_launch_intent=true filter_i3pm_launch_queued=true filter_i3pm_launch_complete=true filter_i3pm_launch_failed=true filter_i3pm_state_cached=true filter_i3pm_state_restored=true filter_i3pm_command_queued=true filter_i3pm_command_executed=true filter_i3pm_command_result=true filter_i3pm_command_batch=true filter_i3pm_trace_started=true filter_i3pm_trace_stopped=true filter_i3pm_trace_event=true"
                  "Select All")
                (button
                  :class "filter-button"
                  :onclick "eww --config $HOME/.config/eww-monitoring-panel update filter_window_new=false filter_window_close=false filter_window_focus=false filter_window_blur=false filter_window_move=false filter_window_floating=false filter_window_fullscreen_mode=false filter_window_title=false filter_window_mark=false filter_window_urgent=false filter_workspace_focus=false filter_workspace_init=false filter_workspace_empty=false filter_workspace_move=false filter_workspace_rename=false filter_workspace_urgent=false filter_workspace_reload=false filter_output_connected=false filter_output_disconnected=false filter_output_profile_changed=false filter_output_unspecified=false filter_binding_run=false filter_mode_change=false filter_shutdown_exit=false filter_tick_manual=false filter_i3pm_project_switch=false filter_i3pm_project_clear=false filter_i3pm_visibility_hidden=false filter_i3pm_visibility_shown=false filter_i3pm_scratchpad_move=false filter_i3pm_scratchpad_show=false filter_i3pm_launch_intent=false filter_i3pm_launch_queued=false filter_i3pm_launch_complete=false filter_i3pm_launch_failed=false filter_i3pm_state_cached=false filter_i3pm_state_restored=false filter_i3pm_command_queued=false filter_i3pm_command_executed=false filter_i3pm_command_result=false filter_i3pm_command_batch=false filter_i3pm_trace_started=false filter_i3pm_trace_stopped=false filter_i3pm_trace_event=false"
                  "Clear All")
                ;; Feature 102 T053: Sort-by-duration toggle
                (box
                  :class "sort-controls"
                  :orientation "h"
                  :space-evenly false
                  :hexpand true
                  :halign "end"
                  (label
                    :class "sort-label"
                    :text "Sort: ")
                  (button
                    :class {"sort-button" + (events_sort_mode == "time" ? " active" : "")}
                    :onclick "eww --config $HOME/.config/eww-monitoring-panel update events_sort_mode=time"
                    :tooltip "Sort by time (most recent first)"
                    "󰃰 Time")
                  (button
                    :class {"sort-button" + (events_sort_mode == "duration" ? " active" : "")}
                    :onclick "eww --config $HOME/.config/eww-monitoring-panel update events_sort_mode=duration"
                    :tooltip "Sort by duration (slowest first)"
                    "󱎫 Duration")))
              ;; Window events category
              (box
                :class "filter-category-group"
                :orientation "v"
                :space-evenly false
                (label
                  :class "filter-category-title"
                  :halign "start"
                  :text "Window Events (10)")
                (box
                  :class "filter-checkboxes"
                  :orientation "h"
                  :space-evenly false
                  (filter-checkbox :label "new" :var "filter_window_new" :value filter_window_new)
                  (filter-checkbox :label "close" :var "filter_window_close" :value filter_window_close)
                  (filter-checkbox :label "focus" :var "filter_window_focus" :value filter_window_focus)
                  (filter-checkbox :label "blur" :var "filter_window_blur" :value filter_window_blur)
                  (filter-checkbox :label "move" :var "filter_window_move" :value filter_window_move)
                  (filter-checkbox :label "floating" :var "filter_window_floating" :value filter_window_floating)
                  (filter-checkbox :label "fullscreen" :var "filter_window_fullscreen_mode" :value filter_window_fullscreen_mode)
                  (filter-checkbox :label "title" :var "filter_window_title" :value filter_window_title)
                  (filter-checkbox :label "mark" :var "filter_window_mark" :value filter_window_mark)
                  (filter-checkbox :label "urgent" :var "filter_window_urgent" :value filter_window_urgent)))
              ;; Workspace events category
              (box
                :class "filter-category-group"
                :orientation "v"
                :space-evenly false
                (label
                  :class "filter-category-title"
                  :halign "start"
                  :text "Workspace Events (7)")
                (box
                  :class "filter-checkboxes"
                :orientation "h"
                  :space-evenly false
                  (filter-checkbox :label "focus" :var "filter_workspace_focus" :value filter_workspace_focus)
                  (filter-checkbox :label "init" :var "filter_workspace_init" :value filter_workspace_init)
                  (filter-checkbox :label "empty" :var "filter_workspace_empty" :value filter_workspace_empty)
                  (filter-checkbox :label "move" :var "filter_workspace_move" :value filter_workspace_move)
                  (filter-checkbox :label "rename" :var "filter_workspace_rename" :value filter_workspace_rename)
                  (filter-checkbox :label "urgent" :var "filter_workspace_urgent" :value filter_workspace_urgent)
                  (filter-checkbox :label "reload" :var "filter_workspace_reload" :value filter_workspace_reload)))
              ;; Feature 102 T047: Output events category (connected/disconnected/profile_changed)
              (box
                :class "filter-category-group"
                :orientation "v"
                :space-evenly false
                (label
                  :class "filter-category-title"
                  :halign "start"
                  :text "Output Events (4)")
                (box
                  :class "filter-checkboxes"
                  :orientation "h"
                  :space-evenly false
                  (filter-checkbox :label "connected" :var "filter_output_connected" :value filter_output_connected)
                  (filter-checkbox :label "disconnected" :var "filter_output_disconnected" :value filter_output_disconnected)
                  (filter-checkbox :label "profile" :var "filter_output_profile_changed" :value filter_output_profile_changed)
                  (filter-checkbox :label "other" :var "filter_output_unspecified" :value filter_output_unspecified)))
              ;; Binding/Mode/System events
              (box
                :class "filter-category-group"
                :orientation "v"
                :space-evenly false
                (label
                  :class "filter-category-title"
                  :halign "start"
                  :text "System Events (4)")
                (box
                  :class "filter-checkboxes"
                  :orientation "h"
                  :space-evenly false
                  (filter-checkbox :label "binding" :var "filter_binding_run" :value filter_binding_run)
                  (filter-checkbox :label "mode" :var "filter_mode_change" :value filter_mode_change)
                  (filter-checkbox :label "shutdown" :var "filter_shutdown_exit" :value filter_shutdown_exit)
                  (filter-checkbox :label "tick" :var "filter_tick_manual" :value filter_tick_manual)))
              ;; Feature 102: i3pm Events category (T014)
              (box
                :class "filter-category-group i3pm-events-category"
                :orientation "v"
                :space-evenly false
                (label
                  :class "filter-category-title i3pm-title"
                  :halign "start"
                  :text "󱂬 i3pm Events (19)")
                ;; Project events sub-category
                (box
                  :class "filter-subcategory"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "filter-subcategory-title"
                    :halign "start"
                    :text "Project")
                  (box
                    :class "filter-checkboxes"
                    :orientation "h"
                    :space-evenly false
                    (filter-checkbox :label "switch" :var "filter_i3pm_project_switch" :value filter_i3pm_project_switch)
                    (filter-checkbox :label "clear" :var "filter_i3pm_project_clear" :value filter_i3pm_project_clear)))
                ;; Visibility events sub-category
                (box
                  :class "filter-subcategory"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "filter-subcategory-title"
                    :halign "start"
                    :text "Visibility")
                  (box
                    :class "filter-checkboxes"
                    :orientation "h"
                    :space-evenly false
                    (filter-checkbox :label "hidden" :var "filter_i3pm_visibility_hidden" :value filter_i3pm_visibility_hidden)
                    (filter-checkbox :label "shown" :var "filter_i3pm_visibility_shown" :value filter_i3pm_visibility_shown)))
                ;; Scratchpad events sub-category
                (box
                  :class "filter-subcategory"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "filter-subcategory-title"
                    :halign "start"
                    :text "Scratchpad")
                  (box
                    :class "filter-checkboxes"
                    :orientation "h"
                    :space-evenly false
                    (filter-checkbox :label "move" :var "filter_i3pm_scratchpad_move" :value filter_i3pm_scratchpad_move)
                    (filter-checkbox :label "show" :var "filter_i3pm_scratchpad_show" :value filter_i3pm_scratchpad_show)))
                ;; Launch events sub-category
                (box
                  :class "filter-subcategory"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "filter-subcategory-title"
                    :halign "start"
                    :text "Launch")
                  (box
                    :class "filter-checkboxes"
                    :orientation "h"
                    :space-evenly false
                    (filter-checkbox :label "intent" :var "filter_i3pm_launch_intent" :value filter_i3pm_launch_intent)
                    (filter-checkbox :label "queued" :var "filter_i3pm_launch_queued" :value filter_i3pm_launch_queued)
                    (filter-checkbox :label "complete" :var "filter_i3pm_launch_complete" :value filter_i3pm_launch_complete)
                    (filter-checkbox :label "failed" :var "filter_i3pm_launch_failed" :value filter_i3pm_launch_failed)))
                ;; State events sub-category
                (box
                  :class "filter-subcategory"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "filter-subcategory-title"
                    :halign "start"
                    :text "State")
                  (box
                    :class "filter-checkboxes"
                    :orientation "h"
                    :space-evenly false
                    (filter-checkbox :label "cached" :var "filter_i3pm_state_cached" :value filter_i3pm_state_cached)
                    (filter-checkbox :label "restored" :var "filter_i3pm_state_restored" :value filter_i3pm_state_restored)))
                ;; Command events sub-category
                (box
                  :class "filter-subcategory"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "filter-subcategory-title"
                    :halign "start"
                    :text "Command")
                  (box
                    :class "filter-checkboxes"
                    :orientation "h"
                    :space-evenly false
                    (filter-checkbox :label "queued" :var "filter_i3pm_command_queued" :value filter_i3pm_command_queued)
                    (filter-checkbox :label "executed" :var "filter_i3pm_command_executed" :value filter_i3pm_command_executed)
                    (filter-checkbox :label "result" :var "filter_i3pm_command_result" :value filter_i3pm_command_result)
                    (filter-checkbox :label "batch" :var "filter_i3pm_command_batch" :value filter_i3pm_command_batch)))
                ;; Trace events sub-category
                (box
                  :class "filter-subcategory"
                  :orientation "v"
                  :space-evenly false
                  (label
                    :class "filter-subcategory-title"
                    :halign "start"
                    :text "Trace")
                  (box
                    :class "filter-checkboxes"
                    :orientation "h"
                    :space-evenly false
                    (filter-checkbox :label "started" :var "filter_i3pm_trace_started" :value filter_i3pm_trace_started)
                    (filter-checkbox :label "stopped" :var "filter_i3pm_trace_stopped" :value filter_i3pm_trace_stopped)
                    (filter-checkbox :label "event" :var "filter_i3pm_trace_event" :value filter_i3pm_trace_event))))))
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
          ;; Feature 102 T065: Burst indicator - show when events are being collapsed due to high event rate
          (box
            :visible {(events_data.burst_active ?: false) || (events_data.total_collapsed ?: 0) > 0}
            :class "burst-indicator"
            :orientation "h"
            :space-evenly false
            :halign "center"
            (label
              :class {"burst-badge" + ((events_data.burst_active ?: false) ? " burst-active" : " burst-inactive")}
              :tooltip "High event rate detected (>100/sec). Events are being collapsed to prevent UI overload."
              :text {"󰈐 " + ((events_data.burst_active ?: false) ? "Burst: " + (events_data.burst_collapsed_current ?: 0) + " events collapsing..." : (events_data.total_collapsed ?: 0) + " events collapsed")}))
          ;; Events list (scroll container) with filtering
          (scroll
            :vscroll true
            :hscroll false
            :vexpand true
            :visible {events_data.status == "ok" && events_data.event_count > 0}
            (box
              :class "events-list"
              :orientation "v"
              :space-evenly false
              ;; Feature 102 T053: Iterate through events with sort mode selection
              ;; time = chronological (events), duration = slowest first (events_by_duration)
              (for event in {events_sort_mode == "duration" ? (events_data.events_by_duration ?: []) : (events_data.events ?: [])}
                (box
                  :visible {
                    ;; Sway window events
                    event.event_type == "window::new" ? filter_window_new :
                    event.event_type == "window::close" ? filter_window_close :
                    event.event_type == "window::focus" ? filter_window_focus :
                    event.event_type == "window::move" ? filter_window_move :
                    event.event_type == "window::floating" ? filter_window_floating :
                    event.event_type == "window::fullscreen_mode" ? filter_window_fullscreen_mode :
                    event.event_type == "window::title" ? filter_window_title :
                    event.event_type == "window::mark" ? filter_window_mark :
                    event.event_type == "window::urgent" ? filter_window_urgent :
                    ;; Feature 102 T049: Window blur filter
                    event.event_type == "window::blur" ? filter_window_blur :
                    ;; Sway workspace events
                    event.event_type == "workspace::focus" ? filter_workspace_focus :
                    event.event_type == "workspace::init" ? filter_workspace_init :
                    event.event_type == "workspace::empty" ? filter_workspace_empty :
                    event.event_type == "workspace::move" ? filter_workspace_move :
                    event.event_type == "workspace::rename" ? filter_workspace_rename :
                    event.event_type == "workspace::urgent" ? filter_workspace_urgent :
                    event.event_type == "workspace::reload" ? filter_workspace_reload :
                    ;; Feature 102 T047: Sway output events (connected/disconnected/profile_changed)
                    event.event_type == "output::connected" ? filter_output_connected :
                    event.event_type == "output::disconnected" ? filter_output_disconnected :
                    event.event_type == "output::profile_changed" ? filter_output_profile_changed :
                    event.event_type == "output::unspecified" ? filter_output_unspecified :
                    ;; Sway other events
                    event.event_type == "binding::run" ? filter_binding_run :
                    event.event_type == "mode::change" ? filter_mode_change :
                    event.event_type == "shutdown::exit" ? filter_shutdown_exit :
                    event.event_type == "tick::manual" ? filter_tick_manual :
                    ;; Feature 102: i3pm project events (T014)
                    event.event_type == "project::switch" ? filter_i3pm_project_switch :
                    event.event_type == "project::clear" ? filter_i3pm_project_clear :
                    ;; Feature 102: i3pm visibility events
                    event.event_type == "visibility::hidden" ? filter_i3pm_visibility_hidden :
                    event.event_type == "visibility::shown" ? filter_i3pm_visibility_shown :
                    ;; Feature 102: i3pm scratchpad events
                    event.event_type == "scratchpad::move" ? filter_i3pm_scratchpad_move :
                    event.event_type == "scratchpad::show" ? filter_i3pm_scratchpad_show :
                    ;; Feature 102: i3pm launch events
                    event.event_type == "launch::intent" ? filter_i3pm_launch_intent :
                    event.event_type == "launch::queued" ? filter_i3pm_launch_queued :
                    event.event_type == "launch::complete" ? filter_i3pm_launch_complete :
                    event.event_type == "launch::failed" ? filter_i3pm_launch_failed :
                    ;; Feature 102: i3pm state events
                    event.event_type == "state::cached" ? filter_i3pm_state_cached :
                    event.event_type == "state::restored" ? filter_i3pm_state_restored :
                    ;; Feature 102: i3pm command events (US2)
                    event.event_type == "command::queued" ? filter_i3pm_command_queued :
                    event.event_type == "command::executed" ? filter_i3pm_command_executed :
                    event.event_type == "command::result" ? filter_i3pm_command_result :
                    event.event_type == "command::batch" ? filter_i3pm_command_batch :
                    ;; Feature 102: i3pm trace events
                    event.event_type == "trace::started" ? filter_i3pm_trace_started :
                    event.event_type == "trace::stopped" ? filter_i3pm_trace_stopped :
                    event.event_type == "trace::event" ? filter_i3pm_trace_event :
                    true
                  }
                  (event-card :event event)))))))

      ;; Feature 092: Event card widget - Single event display (T025)
      ;; Feature 102: Added source indicator (T015-T016), trace indicator (T028), causality visualization (T036-T038)
      (defwidget event-card [event]
        (box
          :class {"event-card event-category-" + event.category + (event.source == "i3pm" ? " event-source-i3pm" : " event-source-sway") + ((event.trace_id ?: "") != "" ? " event-has-trace" : "") + ((event.correlation_id ?: "") != "" ? " event-in-chain" : "") + ((event.causality_depth ?: 0) > 0 ? " event-child-depth-" + (event.causality_depth ?: 0) : "")}
          :orientation "h"
          :space-evenly false
          ;; Feature 102 (T037): Indentation for causality depth
          :style {"margin-left: " + ((event.causality_depth ?: 0) * 16) + "px;"}
          ;; Feature 102 (T036): Causality chain indicator
          (box
            :class "event-chain-indicator"
            :visible {(event.correlation_id ?: "") != ""}
            :width 3
            :vexpand true)
          ;; Feature 102: Source indicator badge (T016)
          (label
            :class {"event-source-badge " + (event.source == "i3pm" ? "source-i3pm" : "source-sway")}
            :tooltip {event.source == 'i3pm' ? 'i3pm internal event' : 'Sway IPC event'}
            :text {event.source == 'i3pm' ? '󱂬' : '󰌪'})
          ;; Feature 102 (T028-T030): Trace indicator icon - click to navigate to Traces tab
          ;; Feature 102 T066: Show evicted indicator if trace no longer in buffer
          (eventbox
            :visible {(event.trace_id ?: "") != ""}
            :cursor "pointer"
            :onclick {"${navigateToTraceScript} " + (event.trace_id ?: "") + " &"}
            :tooltip {(event.trace_evicted ?: false) ? 'Trace evicted from buffer' : 'Click to view trace: ' + (event.trace_id ?: "")}
            (label
              :class {"event-trace-indicator" + ((event.trace_evicted ?: false) ? " trace-evicted" : "")}
              :text {(event.trace_evicted ?: false) ? '󰈄' : '󰈙'}))
          ;; Feature 102 T067: Orphaned event indicator (child without visible parent)
          (label
            :class "event-orphaned-indicator"
            :visible {(event.parent_missing ?: false)}
            :tooltip "Parent event not in current view (may have been evicted)"
            :text "󰋇")
          ;; Feature 102 T052: Duration badge for slow events (>100ms)
          (label
            :class {"event-duration-badge" + ((event.processing_duration_ms ?: 0) > 500 ? " duration-critical" : (event.processing_duration_ms ?: 0) > 100 ? " duration-slow" : "")}
            :visible {(event.processing_duration_ms ?: 0) > 100}
            :tooltip "Processing took ''${event.processing_duration_ms ?: 0}ms - slow event (>100ms)"
            :text "''${event.processing_duration_ms ?: 0}ms")
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

      ;; Feature 092: Filter checkbox widget - single checkbox for an event type
      (defwidget filter-checkbox [label var value]
        (eventbox
          :cursor "pointer"
          :onclick "eww --config $HOME/.config/eww-monitoring-panel update ''${var}=''${!value}"
          (box
            :class "filter-checkbox-item"
            :orientation "h"
            :space-evenly false
            (label
              :class "filter-checkbox-icon"
              :text "''${value ? '☑' : '☐'}")
            (label
              :class "filter-checkbox-label"
              :text label))))

      ;; Feature 101: Traces View - Window tracing for debugging
      (defwidget traces-view []
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
              :visible {traces_data.status == "error"}
              (label :text "⚠ ''${traces_data.error ?: 'Unknown error'}"))
            ;; Summary header with template selector dropdown
            (box
              :class "traces-summary"
              :orientation "h"
              :space-evenly false
              :visible {traces_data.status == "ok"}
              (label
                :class "traces-count"
                :halign "start"
                :hexpand true
                :text "''${traces_data.trace_count ?: 0} trace(s) (''${traces_data.active_count ?: 0} active)")
              ;; Feature 102 T059: Template selector dropdown button
              (box
                :class "template-selector-container"
                :orientation "v"
                :space-evenly false
                (eventbox
                  :cursor "pointer"
                  :onclick "eww --config $HOME/.config/eww-monitoring-panel update template_dropdown_open=''${!template_dropdown_open}"
                  (box
                    :class {"template-add-button" + (template_dropdown_open ? " active" : "")}
                    :tooltip "Start trace from template"
                    (label :text "󰐕 New")))
                ;; Dropdown menu
                (box
                  :class "template-dropdown"
                  :visible template_dropdown_open
                  :orientation "v"
                  :space-evenly false
                  (for template in {trace_templates}
                    (eventbox
                      :cursor "pointer"
                      :onclick "${startTraceFromTemplateScript} ''${template.id} &"
                      (box
                        :class "template-item"
                        :orientation "h"
                        :space-evenly false
                        (label
                          :class "template-icon"
                          :text "''${template.icon}")
                        (box
                          :orientation "v"
                          :space-evenly false
                          :hexpand true
                          (label
                            :class "template-name"
                            :halign "start"
                            :text "''${template.name}")
                          (label
                            :class "template-description"
                            :halign "start"
                            :limit-width 40
                            :text "''${template.description}")))))))
              (label
                :class "traces-help"
                :halign "end"
                :tooltip "Start a trace with: i3pm trace start --class <pattern>"
                :text "ℹ"))
            ;; Empty state
            (box
              :class "traces-empty"
              :visible {traces_data.status == "ok" && (traces_data.trace_count ?: 0) == 0}
              :orientation "v"
              :space-evenly false
              (label
                :class "empty-icon"
                :text "󱂛")
              (label
                :class "empty-title"
                :text "No active traces")
              (label
                :class "empty-hint"
                :text "Start a trace with:")
              (label
                :class "empty-command"
                :text "i3pm trace start --class <pattern>"))
            ;; Traces list
            (box
              :class "traces-list"
              :orientation "v"
              :space-evenly false
              :visible {traces_data.status == "ok" && (traces_data.trace_count ?: 0) > 0}
              (for trace in {traces_data.traces ?: []}
                (trace-card :trace trace))))))

      ;; Feature 116: Devices View - Comprehensive device controls dashboard
      ;; Shows volume, brightness, bluetooth, battery, thermal, and network status
      ;; Uses device-backend.py from eww-device-controls module
      (defwidget devices-view []
        (scroll
          :vscroll true
          :hscroll false
          :vexpand true
          (box
            :class "content-container devices-content"
            :orientation "v"
            :space-evenly false
            :spacing 16
            ;; Audio section
            (box
              :class "devices-section"
              :orientation "v"
              :space-evenly false
              (label :class "section-title" :halign "start" :text "󰕾 Audio")
              (box
                :class "section-content"
                :orientation "v"
                :space-evenly false
                :spacing 8
                (box
                  :class "device-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 8
                  (label :class "device-label" :text "Output")
                  (label :class "device-value" :hexpand true :halign "end" :text "''${devices_state.volume.current_device ?: 'Unknown'}"))
                (box
                  :class "slider-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 8
                  (label :class "slider-icon" :text "''${devices_state.volume.icon ?: '󰕾'}")
                  (scale
                    :class "device-slider"
                    :hexpand true
                    :min 0 :max 100
                    :value "''${devices_state.volume.volume ?: 50}"
                    :onchange "$HOME/.config/eww/eww-device-controls/scripts/volume-control.sh set {} &")
                  (label :class "slider-value" :text "''${devices_state.volume.volume ?: 50}%")
                  (eventbox
                    :cursor "pointer"
                    :onclick "$HOME/.config/eww/eww-device-controls/scripts/volume-control.sh mute &"
                    (label :class "''${devices_state.volume.muted ?: false ? 'mute-btn muted' : 'mute-btn'}"
                           :text "''${devices_state.volume.muted ?: false ? '󰝟' : '󰕾'}")))))
            ;; Display section (laptop only - brightness controls)
            (box
              :class "devices-section"
              :orientation "v"
              :space-evenly false
              :visible {devices_state.hardware.has_brightness ?: false}
              (label :class "section-title" :halign "start" :text "󰛨 Display")
              (box
                :class "section-content"
                :orientation "v"
                :space-evenly false
                :spacing 8
                (box
                  :class "slider-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 8
                  (label :class "slider-icon" :text "󰃞")
                  (label :class "slider-label" :text "Screen")
                  (scale
                    :class "device-slider"
                    :hexpand true
                    :min 5 :max 100
                    :value "''${devices_state.brightness.display ?: 50}"
                    :onchange "$HOME/.config/eww/eww-device-controls/scripts/brightness-control.sh set {} &")
                  (label :class "slider-value" :text "''${devices_state.brightness.display ?: 50}%"))
                (box
                  :class "slider-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 8
                  :visible {devices_state.hardware.has_keyboard_backlight ?: false}
                  (label :class "slider-icon" :text "󰌌")
                  (label :class "slider-label" :text "Keyboard")
                  (scale
                    :class "device-slider"
                    :hexpand true
                    :min 0 :max 100
                    :value "''${devices_state.brightness.keyboard ?: 0}"
                    :onchange "$HOME/.config/eww/eww-device-controls/scripts/brightness-control.sh set {} --device keyboard &")
                  (label :class "slider-value" :text "''${devices_state.brightness.keyboard ?: 0}%"))))
            ;; Bluetooth section
            (box
              :class "devices-section"
              :orientation "v"
              :space-evenly false
              (label :class "section-title" :halign "start" :text "󰂯 Bluetooth")
              (box
                :class "section-content"
                :orientation "v"
                :space-evenly false
                :spacing 8
                (box
                  :class "toggle-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 12
                  (label :class "toggle-icon" :text "󰂯")
                  (label :class "toggle-label" :hexpand true :text "Bluetooth")
                  (button
                    :class "''${devices_state.bluetooth.enabled ?: false ? 'toggle-btn on' : 'toggle-btn off'}"
                    :onclick "$HOME/.config/eww/eww-device-controls/scripts/bluetooth-control.sh power toggle &"
                    (label :text "''${devices_state.bluetooth.enabled ?: false ? '󰔡' : '󰨙'}")))
                (box
                  :class "device-list"
                  :orientation "v"
                  :space-evenly false
                  :spacing 4
                  :visible "''${devices_state.bluetooth.enabled ?: false}"
                  (for device in "''${devices_state.bluetooth.devices ?: []}"
                    (box
                      :class "''${device.connected ? 'device-item connected' : 'device-item'}"
                      :orientation "h"
                      :space-evenly false
                      :spacing 8
                      (label :class "device-icon" :text "''${device.icon ?: '󰂯'}")
                      (label :class "device-name" :hexpand true :text "''${device.name}")
                      (eventbox
                        :cursor "pointer"
                        :onclick "$HOME/.config/eww/eww-device-controls/scripts/bluetooth-control.sh ''${device.connected ? 'disconnect' : 'connect'} ''${device.mac} &"
                        (label :class "connect-btn" :text "''${device.connected ? 'Disconnect' : 'Connect'}")))))))
            ;; Power section (laptop only - battery and power profiles)
            (box
              :class "devices-section"
              :orientation "v"
              :space-evenly false
              :visible {devices_state.hardware.has_battery ?: false}
              (label :class "section-title" :halign "start" :text "󰂄 Power")
              (box
                :class "section-content"
                :orientation "v"
                :space-evenly false
                :spacing 8
                ;; Battery status row
                (box
                  :class "battery-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 8
                  (label :class {"battery-icon " + (devices_state.battery.level ?: "normal") + (devices_state.battery.state == "charging" ? " charging" : "")}
                         :text "''${devices_state.battery.icon ?: '󰁹'}")
                  (box
                    :class "battery-info"
                    :orientation "v"
                    :space-evenly false
                    :hexpand true
                    (box
                      :orientation "h"
                      :space-evenly false
                      :spacing 8
                      (label :class "battery-percent" :text "''${devices_state.battery.percentage ?: 100}%")
                      (label :class "battery-state"
                             :text "''${devices_state.battery.state == 'charging' ? '󰂄 Charging' : devices_state.battery.state == 'discharging' ? '󰂃 Discharging' : '󰁹 Full'}"))
                    (label :class "battery-time"
                           :halign "start"
                           :visible {devices_state.battery.time_remaining != "null"}
                           :text {devices_state.battery.time_remaining ?: ""})))
                ;; Battery details (health, cycles, power draw)
                (box
                  :class "battery-details"
                  :orientation "h"
                  :space-evenly true
                  :visible {devices_state.battery.health != "null"}
                  (box
                    :class "detail-item"
                    :orientation "v"
                    :space-evenly false
                    (label :class "detail-label" :text "Health")
                    (label :class "detail-value" :text "''${devices_state.battery.health ?: 100}%"))
                  (box
                    :class "detail-item"
                    :orientation "v"
                    :space-evenly false
                    :visible {devices_state.battery.power_draw != "null"}
                    (label :class "detail-label" :text "Power")
                    (label :class "detail-value" :text "''${devices_state.battery.power_draw ?: 0}W")))
                ;; Power profile selector
                (box
                  :class "power-profiles"
                  :orientation "h"
                  :space-evenly true
                  :spacing 6
                  :visible {devices_state.hardware.has_power_profiles ?: false}
                  (button
                    :class {"profile-btn profile-saver " + (devices_state.power_profile.current == "power-saver" ? "active" : "")}
                    :onclick "$HOME/.config/eww/eww-device-controls/scripts/power-profile-control.sh set power-saver &"
                    (label :text "󰾆"))
                  (button
                    :class {"profile-btn profile-balanced " + (devices_state.power_profile.current == "balanced" ? "active" : "")}
                    :onclick "$HOME/.config/eww/eww-device-controls/scripts/power-profile-control.sh set balanced &"
                    (label :text "󰾅"))
                  (button
                    :class {"profile-btn profile-performance " + (devices_state.power_profile.current == "performance" ? "active" : "")}
                    :onclick "$HOME/.config/eww/eww-device-controls/scripts/power-profile-control.sh set performance &"
                    (label :text "󱐋")))))
            ;; Thermal section
            (box
              :class "devices-section"
              :orientation "v"
              :space-evenly false
              (label :class "section-title" :halign "start" :text "󰔐 Thermal")
              (box
                :class "section-content"
                :orientation "v"
                :space-evenly false
                :spacing 8
                (box
                  :class "thermal-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 8
                  (label :class "thermal-icon" :text "󰔐")
                  (box
                    :class "thermal-info"
                    :orientation "v"
                    :space-evenly false
                    (label :class "thermal-label" :halign "start" :text "CPU")
                    (label :class "thermal-value" :halign "start" :text "''${devices_state.thermal.cpu_temp ?: 0}°C"))
                  (progress
                    :class "thermal-bar"
                    :hexpand true
                    :value "''${devices_state.thermal.cpu_temp ?: 0}"))
                (box
                  :class "fan-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 8
                  :visible "''${devices_state.thermal.fan_speed != 'null'}"
                  (label :class "fan-icon" :text "󰈐")
                  (label :class "fan-label" :text "Fan")
                  (label :class "fan-value" :hexpand true :halign "end" :text "''${devices_state.thermal.fan_speed ?: 0} RPM"))))
            ;; Network section
            (box
              :class "devices-section"
              :orientation "v"
              :space-evenly false
              (label :class "section-title" :halign "start" :text "󰖩 Network")
              (box
                :class "section-content"
                :orientation "v"
                :space-evenly false
                :spacing 8
                ;; WiFi row
                (box
                  :class "network-row wifi-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 8
                  :visible {devices_state.hardware.has_wifi ?: true}
                  (label :class "''${devices_state.network.wifi_connected ?: false ? 'network-icon connected' : 'network-icon disconnected'}"
                         :text "''${devices_state.network.wifi_icon ?: '󰤯'}")
                  (box
                    :class "network-info"
                    :orientation "v"
                    :space-evenly false
                    (label :class "network-type" :halign "start" :text "WiFi")
                    (label :class "network-value" :halign "start"
                           :text "''${devices_state.network.wifi_connected ?: false ? devices_state.network.wifi_ssid ?: 'Connected' : (devices_state.network.wifi_enabled ?: false ? 'Not Connected' : 'Disabled')}")))
                ;; Ethernet row (if connected)
                (box
                  :class "network-row ethernet-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 8
                  :visible {devices_state.network.ethernet_connected ?: false}
                  (label :class "network-icon connected" :text "󰈀")
                  (box
                    :class "network-info"
                    :orientation "v"
                    :space-evenly false
                    (label :class "network-type" :halign "start" :text "Ethernet")
                    (label :class "network-value" :halign "start"
                           :text "''${devices_state.network.ethernet_ip ?: 'Connected'}")))
                ;; Tailscale row
                (box
                  :class "network-row tailscale-row"
                  :orientation "h"
                  :space-evenly false
                  :spacing 8
                  (label :class "''${devices_state.network.tailscale_connected ?: false ? 'network-icon connected' : 'network-icon disconnected'}"
                         :text "󰖂")
                  (box
                    :class "network-info"
                    :orientation "v"
                    :space-evenly false
                    (label :class "network-type" :halign "start" :text "Tailscale")
                    (label :class "network-value" :halign "start"
                           :text "''${devices_state.network.tailscale_connected ?: false ? devices_state.network.tailscale_ip ?: 'Connected' : 'Disconnected'}"))))))))

      ;; Feature 101: Trace card widget - displays single trace info with expandable events
      ;; Feature 102 (T031): Added highlight class for navigation animation
      (defwidget trace-card [trace]
        (box
          :class {"trace-card " + (trace.is_active ? "trace-active" : "trace-stopped") + (expanded_trace_id == trace.trace_id ? " trace-expanded" : "") + (highlight_trace_id == trace.trace_id ? " trace-highlight" : "")}
          :orientation "v"
          :space-evenly false
          ;; Main trace info row (clickable to expand)
          (eventbox
            :cursor "pointer"
            :onclick "${fetchTraceEventsScript} ''${trace.trace_id} &"
            :tooltip "Click to expand/collapse events"
            (box
              :class "trace-card-header"
              :orientation "h"
              :space-evenly false
              ;; Expand/collapse indicator
              (label
                :class "trace-expand-icon"
                :text {expanded_trace_id == trace.trace_id ? "󰅀" : "󰅂"})
              ;; Status icon
              (label
                :class "trace-status-icon"
                :text "''${trace.status_icon}")
              ;; Trace details
              (box
                :class "trace-details"
                :orientation "v"
                :space-evenly false
                :hexpand true
                ;; Trace ID and status
                (box
                  :class "trace-header"
                  :orientation "h"
                  :space-evenly false
                  (label
                    :class "trace-id"
                    :halign "start"
                    :hexpand true
                    :limit-width 30
                    :text "''${trace.trace_id}")
                  (label
                    :class "trace-status-label"
                    :halign "end"
                    :text "''${trace.status_label}"))
                ;; Matcher info
                (label
                  :class "trace-matcher"
                  :halign "start"
                  :limit-width 40
                  :text "''${trace.matcher_display}")
                ;; Stats line
                (box
                  :class "trace-stats"
                  :orientation "h"
                  :space-evenly false
                  (label
                    :class "trace-events"
                    :text "''${trace.event_count} events")
                  (label
                    :class "trace-separator"
                    :text " · ")
                  (label
                    :class "trace-duration"
                    :text "''${trace.duration_display}")
                  (label
                    :class "trace-separator"
                    :visible {trace.window_id != "null" && trace.window_id != ""}
                    :text " · ")
                  (label
                    :class "trace-window-id"
                    :visible {trace.window_id != "null" && trace.window_id != ""}
                    :text "win:''${trace.window_id}")))
              ;; Action buttons
              (box
                :class "trace-actions"
                :orientation "h"
                :space-evenly false
                :halign "end"
                ;; Copy to clipboard button (for LLM analysis)
                (eventbox
                  :cursor "pointer"
                  :onclick "${copyTraceDataScript} ''${trace.trace_id} &"
                  :tooltip "Copy trace timeline to clipboard"
                  (label
                    :class {"trace-copy-btn" + (copied_trace_id == trace.trace_id ? " copied" : "")}
                    :text {copied_trace_id == trace.trace_id ? "󰄬" : "󰆏"}))
                ;; Open in terminal button
                (button
                  :class "trace-action-btn"
                  :tooltip "Show full timeline in terminal"
                  :onclick "ghostty -e i3pm trace show ''${trace.trace_id} &"
                  "󰋽")
                ;; Stop/Remove button
                (button
                  :class "trace-action-btn trace-stop-btn"
                  :tooltip "''${trace.is_active ? 'Stop trace' : 'Remove trace'}"
                  :onclick "i3pm trace stop ''${trace.trace_id} &"
                  "''${trace.is_active ? '⏹' : '🗑'}"))))
          ;; Expandable events timeline
          (revealer
            :reveal {expanded_trace_id == trace.trace_id}
            :transition "slidedown"
            :duration "150ms"
            (box
              :class "trace-events-panel"
              :orientation "v"
              :space-evenly false
              ;; Loading state
              (box
                :class "trace-events-loading"
                :visible {trace_events_loading}
                :halign "center"
                (label :text "Loading events..."))
              ;; Events list
              (scroll
                :vscroll true
                :hscroll false
                :height 200
                :visible {!trace_events_loading}
                (box
                  :class "trace-events-list"
                  :orientation "v"
                  :space-evenly false
                  (for event in {trace_events}
                    (trace-event-row :event event))))))))

      ;; Feature 101: Single event row in expanded trace timeline
      (defwidget trace-event-row [event]
        (box
          :class {"trace-event-row " + (event.event_type ?: "unknown")}
          :orientation "h"
          :space-evenly false
          ;; Timestamp
          (label
            :class "event-time"
            :text "''${event.time_display ?: '--:--:--'}")
          ;; Event type badge
          (label
            :class {"event-type-badge " + (event.event_type ?: "unknown")}
            :text "''${event.event_type ?: 'unknown'}")
          ;; Description and changes
          (box
            :class "event-content"
            :orientation "v"
            :space-evenly false
            :hexpand true
            (label
              :class "event-description"
              :halign "start"
              :wrap true
              :limit-width 50
              :text {event.description ?: ""})
            (label
              :class "event-changes"
              :halign "start"
              :wrap true
              :visible {(event.changes ?: "") != ""}
              :text {event.changes ?: ""}))))

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
        background-image: none;
      }

      /* GTK3 button reset - removes theme gradients that override background-color */
      button {
        background-image: none;
      }

      /* Panel Container - Sidebar Style with rounded corners and transparency */
      /* Background controlled by inline :style for dynamic opacity slider */
      .panel-container {
        border-radius: 12px;
        padding: 6px;
        margin: 4px;
        border: 2px solid rgba(137, 180, 250, 0.2);
        /* transition not supported in GTK CSS */
      }

      .panel-container * {
        /* Prevent any child from exceeding container bounds */
        min-width: 0;
      }

      /* Feature 086: Focused state with glowing border effect */
      /* Background still controlled by inline :style - just add border/shadow effects */
      .panel-container.focused {
        border: 2px solid ${mocha.mauve};
        box-shadow: 0 0 20px rgba(203, 166, 247, 0.4),
                    0 0 40px rgba(203, 166, 247, 0.2),
                    inset 0 0 15px rgba(203, 166, 247, 0.05);
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

      /* Feature 119: Debug Mode Toggle Button */
      .debug-toggle {
        font-size: 14px;
        color: ${mocha.subtext0};
        padding: 2px 6px;
        margin-left: 8px;
        border-radius: 4px;
        background-color: rgba(49, 50, 68, 0.3);
        transition: all 150ms ease;
      }

      .debug-toggle:hover {
        color: ${mocha.text};
        background-color: rgba(49, 50, 68, 0.5);
      }

      .debug-toggle.active {
        color: ${mocha.yellow};
        background-color: rgba(249, 226, 175, 0.2);
      }

      /* Opacity Control Slider */
      .opacity-control {
        margin-left: 8px;
        padding: 2px 6px;
        border-radius: 4px;
        background-color: rgba(49, 50, 68, 0.3);
      }

      .opacity-icon {
        font-size: 12px;
        color: ${mocha.subtext0};
        margin-right: 4px;
      }

      .opacity-slider {
        min-width: 60px;
        min-height: 8px;
      }

      .opacity-slider trough {
        min-height: 4px;
        background-color: rgba(49, 50, 68, 0.6);
        border-radius: 2px;
      }

      .opacity-slider highlight {
        background-color: ${mocha.blue};
        border-radius: 2px;
      }

      .opacity-slider slider {
        min-width: 10px;
        min-height: 10px;
        background-color: ${mocha.lavender};
        border-radius: 50%;
        margin: -3px;
      }

      .opacity-slider slider:hover {
        background-color: ${mocha.blue};
      }

      /* UX Enhancement: Workspace Pills (CSS only test) */
      .workspace-pills-scroll {
        margin-top: 6px;
      }

      .workspace-pills {
        padding: 2px 0;
      }

      .workspace-pill {
        font-size: 11px;
        padding: 4px 10px;
        margin-right: 4px;
        border-radius: 12px;
        background-color: rgba(49, 50, 68, 0.5);
        color: ${mocha.subtext0};
        border: 1px solid ${mocha.surface0};
      }

      .workspace-pill:hover {
        background-color: rgba(69, 71, 90, 0.6);
        color: ${mocha.text};
        border-color: ${mocha.overlay0};
      }

      .workspace-pill.focused {
        background-color: rgba(137, 180, 250, 0.3);
        color: ${mocha.blue};
        border-color: ${mocha.blue};
        font-weight: bold;
        box-shadow: 0 0 6px rgba(137, 180, 250, 0.4);
      }

      .workspace-pill.urgent {
        background-color: rgba(243, 139, 168, 0.3);
        color: ${mocha.red};
        border-color: ${mocha.red};
        box-shadow: 0 0 6px rgba(243, 139, 168, 0.4);
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
        background-image: none;
        color: ${mocha.subtext0};
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
      }

      .tab label {
        color: ${mocha.subtext0};
      }

      .tab:hover {
        background-color: rgba(69, 71, 90, 0.5);
        background-image: none;
        color: ${mocha.text};
        border-color: ${mocha.overlay0};
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
      }

      .tab:hover label {
        color: ${mocha.text};
      }

      .tab.active {
        background-color: rgba(137, 180, 250, 0.6);
        background-image: none;
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
        background-image: none;
        box-shadow: 0 0 12px rgba(137, 180, 250, 0.6);
      }

      .tab.active:hover label {
        color: ${mocha.base};
      }

      /* Panel Body - Compact */
      .panel-body {
        background-color: transparent;  /* Transparent to allow panel_opacity slider to work */
        padding: 4px;
        min-height: 0;  /* Enable proper flex shrinking for scrolling */
        min-width: 0;  /* GTK fix: prevent overflow */
      }

      /* View container - transparent to allow panel_opacity slider to work */
      .view-container {
        background-color: transparent;
      }

      .content-container {
        padding: 8px 24px 8px 12px;  /* Extra right padding for visible card borders */
      }

      .projects-list {
        min-width: 0;  /* GTK fix: prevent overflow */
      }

      /* Project Widget */
      .project {
        margin-bottom: 12px;
        padding: 8px;
        background-color: rgba(49, 50, 68, 0.15);
        border-radius: 8px;
        border: 1px solid rgba(108, 112, 134, 0.3);
      }

      .scoped-project {
        border-left: 3px solid ${mocha.teal};
      }

      .global-project {
        border-left: 3px solid ${mocha.mauve};
      }

      /* UX Enhancement: Active project highlight */
      .project-active {
        background-color: rgba(137, 180, 250, 0.1);
        border-left-color: ${mocha.blue};
      }

      .project-active .project-header {
        background-color: rgba(137, 180, 250, 0.15);
      }

      .project-active .project-name {
        color: ${mocha.blue};
      }

      .active-indicator {
        font-size: 9px;
        font-weight: bold;
        color: ${mocha.blue};
        background-color: rgba(137, 180, 250, 0.2);
        padding: 1px 6px;
        border-radius: 3px;
        margin-left: 6px;
      }

      .project-header {
        padding: 6px 8px;
        border-bottom: 1px solid ${mocha.overlay0};
        margin-bottom: 6px;
        border-radius: 4px 4px 0 0;
        transition: background-color 0.15s ease;
      }

      .project-header:hover {
        background-color: rgba(137, 180, 250, 0.1);
      }

      /* Project action bar (right-click menu) */
      .project-action-bar {
        padding: 4px 8px;
        background-color: rgba(24, 24, 37, 0.95);
        border-radius: 4px;
        margin-top: 4px;
        margin-bottom: 4px;
      }

      .project-action-bar .action-btn {
        font-size: 14px;
        padding: 4px 8px;
        margin: 0 2px;
        border-radius: 4px;
        transition: background-color 0.15s ease;
      }

      .project-action-bar .action-btn:hover {
        background-color: rgba(137, 180, 250, 0.2);
      }

      .action-switch {
        color: ${mocha.teal};
      }

      .action-close-project {
        color: ${mocha.red};
      }

      .action-dismiss {
        color: ${mocha.subtext0};
      }

      /* Close All button */
      .windows-actions-row {
        padding: 4px 8px;
        margin-bottom: 8px;
      }

      .expand-all-btn {
        padding: 4px 10px;
        background-color: rgba(137, 180, 250, 0.15);
        border: 1px solid ${mocha.blue};
        border-radius: 4px;
        transition: background-color 0.15s ease;
      }

      .expand-all-btn:hover {
        background-color: rgba(137, 180, 250, 0.3);
      }

      .expand-all-icon {
        color: ${mocha.blue};
        font-size: 12px;
      }

      .expand-all-text {
        color: ${mocha.text};
        font-size: 11px;
        font-weight: 500;
      }

      .close-all-btn {
        padding: 4px 10px;
        background-color: rgba(243, 139, 168, 0.15);
        border: 1px solid ${mocha.red};
        border-radius: 4px;
        transition: background-color 0.15s ease;
      }

      .close-all-btn:hover {
        background-color: rgba(243, 139, 168, 0.3);
      }

      .close-all-icon {
        color: ${mocha.red};
        font-size: 12px;
      }

      .close-all-text {
        color: ${mocha.text};
        font-size: 11px;
        font-weight: 500;
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

      /* Feature 119: .badge-workspace removed - workspace badges no longer used */

      /* Feature 095: Notification badge base styling */
      .badge-notification {
        font-weight: bold;
        padding: 2px 6px;
        border-radius: 4px;
        margin-left: 6px;
        font-size: 10px;
      }

      /* Feature 095: Stopped state - bell icon with warm peach glow (attention-grabbing) */
      .badge-stopped {
        color: ${mocha.base};
        background: linear-gradient(135deg, ${mocha.peach}, ${mocha.red});
        border: 1px solid ${mocha.peach};
        box-shadow: 0 0 8px rgba(250, 179, 135, 0.6),
                    0 0 16px rgba(250, 179, 135, 0.3),
                    inset 0 1px 0 rgba(255, 255, 255, 0.2);
        /* GTK CSS doesn't support text-shadow */
      }

      /* Feature 110: Working state - pulsating red circle on subtle background */
      .badge-working {
        color: ${mocha.red};
        background: transparent;
        border: none;
        box-shadow: none;
        font-size: 28px;
        font-weight: bold;
        min-width: 32px;
        min-height: 32px;
      }

      /* Feature 110: Opacity classes for pulsating fade effect */
      .badge-opacity-04 { opacity: 0.4; }
      .badge-opacity-06 { opacity: 0.6; }
      .badge-opacity-08 { opacity: 0.8; }
      .badge-opacity-10 { opacity: 1.0; }

      /* Feature 107: Dimmed badge when window is already focused */
      .badge-focused-window {
        opacity: 0.4;
        box-shadow: none;
        /* GTK CSS doesn't support filter: grayscale() */
      }

      /* Feature 117: AI Sessions bar - minimal, refined design */
      /* Three visual states: working (red pulsing), attention (warm glow), idle (subtle) */
      .ai-sessions-bar {
        padding: 4px 0;
        margin-bottom: 8px;
      }

      /* Base chip styling - minimal, pill-shaped */
      .ai-session-chip {
        background: rgba(49, 50, 68, 0.5);
        border-radius: 12px;
        padding: 3px 8px;
        border: none;
        transition: all 150ms ease;
      }

      .ai-session-chip:hover {
        background: rgba(69, 71, 90, 0.7);
      }

      /* Working state: subtle red glow, pulsing indicator */
      .ai-session-chip.working {
        background: rgba(243, 139, 168, 0.12);
      }

      .ai-session-chip.working:hover {
        background: rgba(243, 139, 168, 0.2);
      }

      .ai-session-chip.working .ai-session-indicator {
        color: ${mocha.red};
      }

      /* Attention state: warm peach/yellow glow */
      .ai-session-chip.attention {
        background: linear-gradient(135deg, rgba(250, 179, 135, 0.15), rgba(249, 226, 175, 0.1));
      }

      .ai-session-chip.attention:hover {
        background: linear-gradient(135deg, rgba(250, 179, 135, 0.25), rgba(249, 226, 175, 0.15));
      }

      .ai-session-chip.attention .ai-session-indicator {
        color: ${mocha.peach};
      }

      /* Idle state: very subtle, muted */
      .ai-session-chip.idle {
        background: rgba(49, 50, 68, 0.3);
      }

      .ai-session-chip.idle:hover {
        background: rgba(69, 71, 90, 0.5);
      }

      .ai-session-chip.idle .ai-session-indicator {
        color: ${mocha.overlay0};
      }

      /* Session indicator - small like inline badges */
      .ai-session-indicator {
        font-size: 12px;
        font-weight: bold;
      }

      /* Source icon styling - SVG image */
      .ai-session-source-icon {
        opacity: 0.7;
        margin-top: 1px;
      }

      .ai-session-chip.working .ai-session-source-icon {
        opacity: 1.0;
      }

      .ai-session-chip.attention .ai-session-source-icon {
        opacity: 1.0;
      }

      /* JSON Expand Trigger Icon - Intentional hover target */
      .window-row {
        /* Ensure row aligns items properly */
      }

      .json-expand-trigger {
        padding: 4px 8px;
        margin-left: 8px;
        border-radius: 4px;
        background-color: rgba(137, 180, 250, 0.15);
        border: 1px dashed rgba(137, 180, 250, 0.35); /* debug border to confirm visibility */
        /* GTK CSS doesn't support transition */
        opacity: 0.7;
        /* Ensure trigger doesn't get squeezed out */
        min-width: 28px;
        min-height: 24px;
      }

      .json-expand-trigger:hover {
        background-color: rgba(137, 180, 250, 0.2);
        opacity: 1;
      }

      .json-expand-trigger.expanded {
        background-color: rgba(137, 180, 250, 0.3);
        opacity: 1;
      }

      .json-expand-icon {
        font-size: 16px;
        color: ${mocha.blue};
        min-width: 18px;
        /* GTK CSS doesn't support transition */
      }

      .json-expand-trigger:hover .json-expand-icon {
        color: ${mocha.sapphire};
      }

      .json-expand-trigger.expanded .json-expand-icon {
        color: ${mocha.sky};
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

      /* Feature 099: Environment Variables Panel */
      .env-expand-trigger {
        padding: 2px 6px;
        margin: 0 2px;
        border-radius: 4px;
        /* transition not supported in GTK CSS */
        background-color: transparent;
      }

      .env-expand-trigger:hover {
        background-color: rgba(148, 226, 213, 0.15);
      }

      .env-expand-trigger.expanded {
        background-color: rgba(148, 226, 213, 0.25);
      }

      .env-expand-icon {
        font-size: 12px;
        color: ${mocha.teal};
        /* transition not supported in GTK CSS */
      }

      .env-expand-trigger:hover .env-expand-icon {
        color: ${mocha.green};
      }

      .window-env-panel {
        background-color: rgba(24, 24, 37, 0.98);
        border: 2px solid ${mocha.teal};
        border-radius: 8px;
        padding: 0;
        margin: 4px 0 8px 0;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6),
                    0 0 0 1px rgba(148, 226, 213, 0.3);
      }

      .env-panel-header {
        background-color: rgba(148, 226, 213, 0.15);
        border-bottom: 1px solid ${mocha.teal};
        padding: 8px 12px;
        border-radius: 6px 6px 0 0;
      }

      .env-panel-title {
        font-size: 11px;
        font-weight: bold;
        color: ${mocha.teal};
      }

      .env-close-btn {
        font-size: 14px;
        padding: 4px 8px;
        background-color: rgba(243, 139, 168, 0.2);
        color: ${mocha.red};
        border: 1px solid ${mocha.red};
        border-radius: 4px;
        min-width: 24px;
      }

      .env-close-btn:hover {
        background-color: rgba(243, 139, 168, 0.4);
        box-shadow: 0 0 8px rgba(243, 139, 168, 0.4);
      }

      /* Feature 099: Filter input styles */
      .env-filter-box {
        background-color: rgba(30, 30, 46, 0.6);
        border: 1px solid ${mocha.surface1};
        border-radius: 4px;
        padding: 4px 8px;
        margin: 8px 12px;
      }

      .env-filter-box:focus-within {
        border-color: ${mocha.teal};
        background-color: rgba(30, 30, 46, 0.8);
      }

      .env-filter-icon {
        font-size: 12px;
        color: ${mocha.subtext0};
        padding-right: 6px;
      }

      .env-filter-input {
        background-color: transparent;
        border: none;
        outline: none;
        font-family: "JetBrains Mono", "Fira Code", monospace;
        font-size: 11px;
        color: ${mocha.text};
        min-width: 150px;
      }

      .env-filter-input:focus {
        border: none;
        outline: none;
      }

      .env-filter-clear {
        font-size: 12px;
        padding: 2px 4px;
        color: ${mocha.overlay0};
        border-radius: 3px;
      }

      .env-filter-clear:hover {
        color: ${mocha.red};
        background-color: rgba(243, 139, 168, 0.2);
      }

      .env-loading {
        padding: 16px;
        color: ${mocha.subtext0};
        font-size: 12px;
        font-style: italic;
      }

      .env-error {
        padding: 12px;
        color: ${mocha.red};
        font-size: 11px;
        background-color: rgba(243, 139, 168, 0.1);
        border-radius: 0 0 6px 6px;
      }

      .env-section {
        padding: 8px 12px;
      }

      .env-section-i3pm {
        background-color: rgba(148, 226, 213, 0.05);
        border-bottom: 1px solid rgba(148, 226, 213, 0.2);
      }

      .env-section-other {
        background-color: rgba(30, 30, 46, 0.4);
      }

      .env-section-title {
        font-size: 10px;
        font-weight: bold;
        color: ${mocha.teal};
        margin-bottom: 6px;
      }

      .env-section-other .env-section-title {
        color: ${mocha.subtext0};
      }

      .env-vars-list {
        padding: 0;
      }

      .env-var-row {
        padding: 3px 0;
        border-bottom: 1px solid rgba(108, 112, 134, 0.1);
      }

      .env-var-row:last-child {
        border-bottom: none;
      }

      .env-var-key {
        font-family: "JetBrains Mono", "Fira Code", monospace;
        font-size: 10px;
        font-weight: bold;
        color: ${mocha.green};
        min-width: 180px;
        padding-right: 8px;
      }

      .env-var-key-other {
        color: ${mocha.overlay0};
        font-weight: normal;
      }

      .env-var-value {
        font-family: "JetBrains Mono", "Fira Code", monospace;
        font-size: 10px;
        color: ${mocha.peach};
      }

      .env-var-value-other {
        color: ${mocha.subtext0};
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

      /* Project Card Styles - Simplified to match window-widget style */
      .project-card {
        background-color: rgba(49, 50, 68, 0.3);
        border-left: 2px solid ${mocha.surface1};
        border-radius: 2px;
        padding: 8px 10px;
        margin-bottom: 4px;
        min-width: 0;  /* GTK fix: prevent overflow */
      }

      .project-card:hover {
        background-color: rgba(49, 50, 68, 0.5);
        border-left-color: ${mocha.overlay0};
      }

      .project-card.active-project {
        border-left-color: ${mocha.teal};
        background-color: rgba(148, 226, 213, 0.12);
      }

      .project-card-header {
        /* Header row - horizontal layout */
        min-width: 0;  /* GTK fix: prevent overflow */
      }

      .project-main-content {
        /* Main content wrapper - contains icon, info, action-bar */
        min-width: 0;  /* GTK fix: prevent overflow, allow truncation */
      }

      .git-branch-row {
        /* Row 2: Git branch on its own row for full width */
        margin-top: 4px;
        padding-top: 4px;
        border-top: 1px solid rgba(69, 71, 90, 0.3);
      }

      .project-card-meta {
        /* Row 3: Badges only */
        margin-top: 4px;
      }

      .git-branch-container {
        /* Used in worktree-card for inline branch display */
        margin-right: 6px;
        min-width: 0;
      }

      .git-branch-icon {
        font-family: "JetBrainsMono Nerd Font", monospace;
        color: ${mocha.teal};
        font-size: 12px;
        margin-right: 4px;
      }

      .git-branch-text {
        color: ${mocha.subtext0};
        font-size: 11px;
        min-width: 0;
      }

      /* Feature 108 T022: Dirty indicator uses red per spec */
      .git-dirty {
        color: ${mocha.red};
        font-size: 11px;
        margin-left: 4px;
      }

      /* Feature 099 T051: Ahead/behind git sync indicators */
      .git-sync-ahead {
        color: ${mocha.green};
        font-size: 10px;
        margin-left: 6px;
        font-weight: bold;
      }

      .git-sync-behind {
        color: ${mocha.yellow};
        font-size: 10px;
        margin-left: 4px;
        font-weight: bold;
      }

      /* Feature 108 T020: Merge badge (teal) */
      .badge-merged {
        color: ${mocha.teal};
        font-size: 10px;
        margin-left: 4px;
        font-weight: bold;
      }

      /* Feature 108 T021: Conflict indicator (red) */
      .git-conflict {
        color: ${mocha.red};
        font-size: 11px;
        margin-left: 4px;
        font-weight: bold;
      }

      /* Feature 108 T033: Stale indicator (gray/faded) */
      .badge-stale {
        color: ${mocha.overlay0};
        font-size: 10px;
        margin-left: 4px;
        opacity: 0.8;
      }

      /* Feature 108 T022: Verify dirty indicator uses red */
      /* Note: .git-dirty already defined above with peach color - changing to red per spec */

      .project-icon-container {
        background-color: rgba(137, 180, 250, 0.1);
        border-radius: 6px;
        padding: 4px 6px;
        margin-right: 8px;
        min-width: 28px;
      }

      .project-icon {
        font-size: 16px;
      }

      .project-info {
        min-width: 0;  /* GTK fix: prevent hexpand from overflowing container */
      }

      .project-card-name {
        font-size: 12px;
        font-weight: bold;
        color: ${mocha.text};
      }

      .project-card-path {
        font-size: 9px;
        color: ${mocha.subtext0};
        font-family: "JetBrainsMono Nerd Font", monospace;
        margin-top: 1px;
      }

      /* Project badges - compact pill style */
      .project-badges {
        margin-left: 6px;
      }

      .badge {
        font-size: 9px;
        padding: 1px 5px;
        border-radius: 8px;
        margin-left: 3px;
        font-weight: 500;
      }

      .badge-active {
        color: ${mocha.green};
        font-size: 8px;
      }

      .badge-scope {
        font-size: 10px;
        padding: 1px 4px;
        color: ${mocha.teal};
        background-color: rgba(148, 226, 213, 0.15);
        border-radius: 4px;
      }

      .badge-scoped {
        color: ${mocha.teal};
      }

      .badge-global {
        color: ${mocha.peach};
        background-color: rgba(250, 179, 135, 0.15);
      }

      .badge-remote {
        color: ${mocha.mauve};
        background-color: rgba(203, 166, 247, 0.15);
        font-size: 10px;
        padding: 1px 4px;
      }

      /* Feature 097: Git status row styles */
      .project-git-status {
        padding: 2px 6px;
        background-color: rgba(69, 71, 90, 0.3);
        border-radius: 4px;
        font-size: 10px;
      }

      .git-branch-icon {
        color: ${mocha.mauve};
        font-size: 11px;
        margin-right: 3px;
      }

      .git-branch-name {
        color: ${mocha.subtext0};
        font-size: 10px;
      }

      .git-dirty-indicator {
        color: ${mocha.yellow};
        font-size: 10px;
        margin-left: 4px;
        font-weight: bold;
      }

      .git-sync-status {
        color: ${mocha.sapphire};
        font-size: 10px;
        margin-left: 4px;
      }

      /* Feature 099: Repository project card styles */
      .repository-card {
        /* Inherits from .project-card, add repository-specific styles */
      }

      .repository-card.has-dirty {
        /* Visual indicator when repository has dirty worktrees */
        border-left-color: ${mocha.peach};
      }

      .expand-toggle {
        padding: 2px 6px;
        margin-right: 4px;
        border-radius: 4px;
        background-color: rgba(69, 71, 90, 0.3);
      }

      .expand-toggle:hover {
        background-color: rgba(69, 71, 90, 0.5);
      }

      .expand-icon {
        font-family: "JetBrainsMono Nerd Font", monospace;
        font-size: 12px;
        color: ${mocha.subtext0};
      }

      .worktree-count-badge {
        font-size: 9px;
        color: ${mocha.green};
        background-color: rgba(166, 227, 161, 0.15);
        padding: 1px 5px;
        border-radius: 8px;
        margin-left: 6px;
      }

      .badge-dirty {
        color: ${mocha.peach};
        font-size: 8px;
      }

      /* Feature 099: Worktrees container (nested under repository) */
      .worktrees-container {
        margin-left: 20px;
        padding-left: 8px;
        border-left: 1px solid rgba(69, 71, 90, 0.5);
      }

      /* Feature 099: Orphaned worktrees section */
      .orphaned-section {
        margin-top: 12px;
        padding-top: 8px;
        border-top: 1px dashed ${mocha.peach};
      }

      .orphaned-header {
        font-size: 11px;
        color: ${mocha.peach};
        font-weight: bold;
        margin-bottom: 8px;
      }

      .orphaned-worktree-card {
        background-color: rgba(250, 179, 135, 0.1);
        border-left: 2px solid ${mocha.peach};
        border-radius: 2px;
        padding: 6px 8px;
        margin-bottom: 4px;
      }

      .orphaned-icon {
        margin-right: 6px;
        font-size: 14px;
      }

      .orphaned-info {
        min-width: 0;
      }

      .orphaned-name {
        font-size: 11px;
        color: ${mocha.text};
      }

      .orphaned-path {
        font-size: 9px;
        color: ${mocha.subtext0};
        font-family: "JetBrainsMono Nerd Font", monospace;
      }

      .orphaned-actions {
        /* GTK doesn't support margin-left: auto; use hexpand on sibling instead */
      }

      .action-recover {
        color: ${mocha.green};
      }

      .action-add {
        color: ${mocha.green};
      }

      /* Feature 097: Missing status warning badge */
      .badge-missing {
        color: ${mocha.yellow};
        font-size: 12px;
        margin-right: 4px;
      }

      /* Feature 097: Source type badges */
      .badge-source-type {
        font-size: 10px;
        padding: 1px 3px;
        border-radius: 4px;
        margin-right: 2px;
      }

      .badge-source-local {
        color: ${mocha.blue};
      }

      .badge-source-worktree {
        color: ${mocha.green};
      }

      .badge-source-remote {
        color: ${mocha.mauve};
      }

      /* Project action bar - compact buttons on hover */
      .project-action-bar {
        margin-left: 6px;
        background-color: rgba(30, 30, 46, 0.8);
        border-radius: 6px;
        padding: 2px 4px;
      }

      .action-btn {
        font-size: 12px;
        padding: 3px 6px;
        border-radius: 4px;
        min-width: 20px;
      }

      .action-edit {
        color: ${mocha.blue};
      }

      .action-edit:hover {
        background-color: rgba(137, 180, 250, 0.2);
        color: ${mocha.sapphire};
      }

      .action-delete {
        color: ${mocha.overlay0};
      }

      .action-delete:hover {
        background-color: rgba(243, 139, 168, 0.2);
        color: ${mocha.red};
      }

      .action-json {
        color: ${mocha.overlay0};
      }

      .action-json:hover,
      .action-json.expanded {
        background-color: rgba(137, 180, 250, 0.2);
        color: ${mocha.blue};
      }

      /* Project JSON tooltip - same style as window JSON */
      .project-json-tooltip {
        background-color: rgba(24, 24, 37, 0.98);
        border: 2px solid ${mocha.teal};
        border-radius: 8px;
        padding: 0;
        margin: 4px 0 8px 0;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6),
                    0 0 0 1px rgba(148, 226, 213, 0.3);
      }

      .project-json-tooltip .json-tooltip-header {
        background-color: rgba(148, 226, 213, 0.15);
        border-bottom: 1px solid ${mocha.teal};
      }

      .project-json-tooltip .json-tooltip-title {
        color: ${mocha.teal};
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
      /* Feature 102: Eww-based hover for action buttons (CSS :hover doesn't work with nested eventbox) */
      .worktree-card-wrapper {
        /* Wrapper owns spacing - eventbox covers full clickable area */
        margin-left: 16px;
        margin-bottom: 2px;
        padding-bottom: 2px;
      }

      /* Worktree action bar - hidden by default, visible on hover via Eww variable */
      .worktree-action-bar {
        opacity: 0;
        transition: opacity 150ms ease-in-out;
        padding-left: 8px;
      }

      .worktree-action-bar.visible {
        opacity: 1;
      }

      .worktree-action-bar .action-btn {
        font-size: 14px;
        padding: 4px 8px;
        margin: 0 2px;
        border-radius: 4px;
        transition: background-color 0.15s ease;
      }

      .worktree-action-bar .action-btn:hover {
        background-color: rgba(137, 180, 250, 0.2);
      }

      .worktree-action-bar .action-delete {
        color: ${mocha.red};
      }

      .worktree-action-bar .action-delete:hover {
        background-color: rgba(243, 139, 168, 0.2);
      }

      /* Feature 109: Worktree action button colors */
      .worktree-action-bar .action-terminal {
        color: ${mocha.green};
      }

      .worktree-action-bar .action-terminal:hover {
        background-color: rgba(166, 227, 161, 0.2);
      }

      .worktree-action-bar .action-editor {
        color: ${mocha.blue};
      }

      .worktree-action-bar .action-editor:hover {
        background-color: rgba(137, 180, 250, 0.2);
      }

      .worktree-action-bar .action-files {
        color: ${mocha.yellow};
      }

      .worktree-action-bar .action-files:hover {
        background-color: rgba(249, 226, 175, 0.2);
      }

      .worktree-action-bar .action-git {
        color: ${mocha.peach};
      }

      .worktree-action-bar .action-git:hover {
        background-color: rgba(250, 179, 135, 0.2);
      }

      .worktree-action-bar .action-copy {
        color: ${mocha.lavender};
      }

      .worktree-action-bar .action-copy:hover {
        background-color: rgba(180, 190, 254, 0.2);
      }

      .worktree-card {
        background-color: rgba(49, 50, 68, 0.3);
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
        padding: 6px 8px;
        /* margins moved to wrapper for better hover continuity */
      }

      .worktree-tree {
        color: ${mocha.overlay0};
        font-size: 11px;
        margin-right: 4px;
        font-family: monospace;
        min-width: 16px;
      }

      .worktree-icon {
        font-size: 14px;
      }

      .worktree-name {
        font-size: 11px;
        color: ${mocha.subtext0};
      }

      .worktree-badges {
        margin-left: 4px;
      }

      /* Feature 109: Branch number badge - prominent, clickable */
      .branch-number-badge-container {
        margin-right: 6px;
      }

      .branch-number-badge {
        font-size: 9px;
        font-weight: bold;
        font-family: monospace;
        color: ${mocha.mantle};
        background: linear-gradient(135deg, ${mocha.mauve} 0%, ${mocha.pink} 100%);
        padding: 1px 4px;
        border-radius: 3px;
        min-width: 20px;
        /* text-align not supported in GTK CSS - use :halign in yuck widget instead */
      }

      .branch-number-badge:hover {
        background: linear-gradient(135deg, ${mocha.pink} 0%, ${mocha.mauve} 100%);
        opacity: 0.9;
      }

      /* Main branch badge - styled container like feature number badge */
      .branch-main-badge {
        font-size: 10px;
        font-weight: bold;
        padding: 1px 4px;
        border-radius: 3px;
        min-width: 20px;
        color: ${mocha.mantle};
        background: linear-gradient(135deg, ${mocha.blue} 0%, ${mocha.sapphire} 100%);
      }

      /* Feature branch badge (without number) - styled container like feature number badge */
      .branch-feature-badge {
        font-size: 10px;
        font-weight: bold;
        padding: 1px 4px;
        border-radius: 3px;
        min-width: 20px;
        color: ${mocha.mantle};
        background: linear-gradient(135deg, ${mocha.green} 0%, ${mocha.teal} 100%);
      }

      /* Feature 109: Path row with copy button */
      .worktree-path-row {
        margin-top: 2px;
      }

      .copy-btn-container {
        opacity: 0;
        transition: opacity 150ms ease-in-out;
        margin-left: 4px;
      }

      .copy-btn-container.visible {
        opacity: 1;
      }

      .copy-btn {
        font-size: 10px;
        color: ${mocha.subtext0};
        padding: 2px 4px;
        border-radius: 3px;
        /* transition: all not reliable in GTK CSS */
      }

      .copy-btn:hover {
        color: ${mocha.teal};
        background-color: rgba(148, 226, 213, 0.15);
      }

      /* Feature 094 US5: Branch indicator badge */
      .badge-branch {
        font-size: 9px;
        color: ${mocha.teal};
        background-color: rgba(148, 226, 213, 0.15);
        padding: 1px 4px;
        border-radius: 4px;
        font-family: monospace;
      }

      /* Feature 094 US5: Worktree action buttons */
      .worktree-actions {
        margin-left: 4px;
        background-color: rgba(30, 30, 46, 0.8);
        border-radius: 4px;
        padding: 1px 3px;
      }

      .worktree-action-btn {
        background-color: transparent;
        border: none;
        padding: 2px 4px;
        border-radius: 4px;
        font-size: 11px;
        min-width: 20px;
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

      /* Feature 100: Discovered Bare Repositories section styles */
      .discovered-repos-section {
        margin-top: 12px;
        padding-top: 8px;
        border-top: 1px solid ${mocha.surface0};
      }

      .discovered-repos-header {
        font-size: 12px;
        font-weight: bold;
        color: ${mocha.teal};
        margin-bottom: 8px;
        padding-left: 4px;
      }

      .discovered-repo {
        border-left-color: ${mocha.teal};
      }

      .discovered-repo:hover {
        background-color: rgba(148, 226, 213, 0.08);
      }

      .worktree-indent {
        min-width: 16px;
        color: ${mocha.overlay0};
      }

      .worktree-branch {
        font-size: 11px;
        font-weight: 500;
        color: ${mocha.text};
      }

      .worktree-commit {
        font-size: 10px;
        color: ${mocha.overlay0};
        font-family: "JetBrainsMono Nerd Font", monospace;
      }

      .worktree-path {
        font-size: 9px;
        color: ${mocha.subtext0};
      }

      /* Feature 108 T029: Last commit info styling (shown on hover) */
      .worktree-last-commit {
        font-size: 9px;
        font-style: italic;
        color: ${mocha.overlay0};
        margin-top: 2px;
      }

      .active-worktree {
        background-color: rgba(148, 226, 213, 0.15);
        border: 1px solid ${mocha.teal};
      }

      /* Active indicator dot */
      .active-indicator {
        color: ${mocha.teal};
        font-size: 8px;
        margin-right: 4px;
      }

      .active-indicator-placeholder {
        color: transparent;
        font-size: 8px;
        margin-right: 4px;
      }

      .dirty-worktree {
        border-left-color: ${mocha.peach};
      }

      .git-dirty {
        color: ${mocha.peach};
        font-weight: bold;
      }

      .git-sync {
        font-size: 10px;
        color: ${mocha.blue};
        margin-left: 4px;
      }

      .badge-main {
        font-size: 8px;
        color: ${mocha.green};
        background-color: rgba(166, 227, 161, 0.15);
        padding: 1px 4px;
        border-radius: 3px;
        margin-left: 4px;
      }

      /* Feature 094 US3: Project create form styles (T066-T067) */
      .projects-header-container {
        background-color: rgba(30, 30, 46, 0.4);
        border-bottom: 1px solid ${mocha.surface0};
        margin-bottom: 8px;
      }

      .projects-header {
        padding: 8px 12px;
      }

      .projects-header-title {
        font-size: 14px;
        font-weight: bold;
        color: ${mocha.text};
      }

      /* Header icon buttons (expand/collapse, new project) */
      .header-icon-button {
        background-color: transparent;
        color: ${mocha.subtext0};
        padding: 4px 8px;
        border-radius: 6px;
        font-size: 16px;
        border: none;
        margin-left: 4px;
      }

      .header-icon-button:hover {
        background-color: ${mocha.surface0};
        color: ${mocha.blue};
      }

      .expand-collapse-btn:hover {
        color: ${mocha.teal};
      }

      .new-project-btn:hover {
        color: ${mocha.green};
      }

      /* Feature 099 UX1: Filter/Search row */
      .projects-filter-row {
        padding: 4px 12px 8px 12px;
      }

      .filter-input-container {
        background-color: ${mocha.mantle};
        border: 1px solid ${mocha.surface1};
        border-radius: 6px;
        padding: 6px 10px;
        min-height: 28px;
      }

      .filter-input-container:focus-within {
        border-color: ${mocha.blue};
        background-color: ${mocha.base};
      }

      .filter-icon {
        color: ${mocha.subtext0};
        font-size: 14px;
        margin-right: 8px;
      }

      .project-filter-input {
        background-color: transparent;
        color: ${mocha.text};
        font-size: 12px;
        border: none;
        outline: none;
        min-width: 120px;
      }


      .filter-clear-button {
        background-color: transparent;
        color: ${mocha.subtext0};
        padding: 2px 4px;
        border: none;
        font-size: 12px;
        border-radius: 4px;
      }

      .filter-clear-button:hover {
        color: ${mocha.red};
        background-color: rgba(243, 139, 168, 0.2);
      }

      .filter-count {
        color: ${mocha.subtext0};
        font-size: 11px;
        margin-left: 8px;
        padding: 2px 6px;
        background-color: rgba(137, 180, 250, 0.15);
        border-radius: 4px;
      }

      /* Feature 099 UX5: Branch number badge - superseded by Feature 109 styling above */

      /* Feature 099 UX4: Copy button */
      .action-copy {
        color: ${mocha.blue};
      }

      .action-copy:hover {
        color: ${mocha.sapphire};
      }

      /* Feature 099 UX2: Keyboard navigation - selected project highlight */
      .project-card.selected,
      .repository-card.selected,
      .worktree-card.selected {
        background-color: rgba(137, 180, 250, 0.15);
        border-color: ${mocha.blue};
        box-shadow: 0 0 8px rgba(137, 180, 250, 0.3);
      }

      .project-card.selected .project-card-name,
      .repository-card.selected .project-card-name,
      .worktree-card.selected .worktree-name {
        color: ${mocha.blue};
      }

      /* Keyboard hints shown in panel focus mode */
      .keyboard-hints {
        padding: 6px 12px;
        background-color: rgba(49, 50, 68, 0.8);
        border-top: 1px solid ${mocha.surface1};
        font-size: 10px;
        color: ${mocha.subtext0};
      }

      .keyboard-hint {
        margin-right: 12px;
      }

      .keyboard-hint-key {
        background-color: ${mocha.surface1};
        color: ${mocha.text};
        padding: 2px 5px;
        border-radius: 3px;
        font-family: monospace;
        font-weight: bold;
        margin-right: 4px;
      }

      /* Old button styles removed - using header-icon-button now */

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

      /* Feature 096 T019: Error notification toast (Catppuccin red #f38ba8) */
      .error-notification-toast {
        background-color: rgba(243, 139, 168, 0.95);
        border: 1px solid ${mocha.red};
        border-radius: 8px;
        padding: 10px 16px;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
        margin-top: 10px;
      }

      .error-notification-toast .error-icon {
        font-size: 16px;
        color: ${mocha.mantle};
        font-weight: bold;
      }

      .error-notification-toast .error-message {
        font-size: 13px;
        color: ${mocha.mantle};
        font-weight: 500;
      }

      .error-notification-toast .error-dismiss {
        background-color: transparent;
        border: none;
        font-size: 12px;
        color: ${mocha.mantle};
        opacity: 0.7;
        padding: 2px 6px;
        margin-left: 8px;
      }

      .error-notification-toast .error-dismiss:hover {
        opacity: 1;
      }

      /* Feature 096 T019: Warning notification toast (Catppuccin yellow #f9e2af) */
      .warning-notification-toast {
        background-color: rgba(249, 226, 175, 0.95);
        border: 1px solid ${mocha.yellow};
        border-radius: 8px;
        padding: 10px 16px;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
        margin-top: 10px;
      }

      .warning-notification-toast .warning-icon {
        font-size: 16px;
        color: ${mocha.mantle};
        font-weight: bold;
      }

      .warning-notification-toast .warning-message {
        font-size: 13px;
        color: ${mocha.mantle};
        font-weight: 500;
      }

      .warning-notification-toast .warning-dismiss {
        background-color: transparent;
        border: none;
        font-size: 12px;
        color: ${mocha.mantle};
        opacity: 0.7;
        padding: 2px 6px;
        margin-left: 8px;
      }

      .warning-notification-toast .warning-dismiss:hover {
        opacity: 1;
      }

      /* UX Enhancement: Context menu styles */
      .context-menu-overlay {
        background-color: rgba(0, 0, 0, 0.5);
        padding: 20px;
      }

      .context-menu {
        background-color: ${mocha.base};
        border: 1px solid ${mocha.overlay0};
        border-radius: 8px;
        padding: 8px 0;
        /* Feature 119: Reduced min-width for narrower panel */
        min-width: 150px;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
      }

      .context-menu-header {
        padding: 8px 12px;
        border-bottom: 1px solid ${mocha.surface0};
        margin-bottom: 4px;
      }

      .context-menu-title {
        font-size: 12px;
        font-weight: bold;
        color: ${mocha.subtext0};
      }

      .context-menu-close {
        padding: 2px 6px;
        border-radius: 4px;
      }

      .context-menu-close:hover {
        background-color: ${mocha.surface0};
      }

      .context-menu-item {
        padding: 8px 12px;
      }

      .context-menu-item:hover {
        background-color: ${mocha.surface0};
      }

      .context-menu-item.danger:hover {
        background-color: rgba(243, 139, 168, 0.2);
      }

      .context-menu-item.danger .menu-label {
        color: ${mocha.red};
      }

      .menu-icon {
        font-size: 14px;
        color: ${mocha.subtext0};
        min-width: 24px;
      }

      .menu-label {
        font-size: 13px;
        color: ${mocha.text};
      }

      /* Inline action bar for window context actions */
      .window-action-bar {
        background-color: ${mocha.surface0};
        border-radius: 0 0 6px 6px;
        padding: 4px 8px;
        margin-top: 2px;
      }

      .action-btn {
        font-size: 16px;
        padding: 6px 10px;
        border-radius: 4px;
        color: ${mocha.subtext0};
        margin: 0 2px;
      }

      .action-btn:hover {
        background-color: ${mocha.surface1};
        color: ${mocha.text};
      }

      .action-focus:hover {
        color: ${mocha.blue};
      }

      .action-float:hover {
        color: ${mocha.yellow};
      }

      .action-fullscreen:hover {
        color: ${mocha.green};
      }

      .action-scratchpad:hover {
        color: ${mocha.mauve};
      }

      /* Feature 101: Trace action button */
      .action-trace {
        color: ${mocha.overlay0};
      }

      .action-trace:hover {
        background-color: rgba(180, 190, 254, 0.2);
        color: ${mocha.lavender};
      }

      .action-close {
        color: ${mocha.overlay0};
      }

      .action-close:hover {
        background-color: rgba(243, 139, 168, 0.2);
        color: ${mocha.red};
      }

      /* Feature 119: Hover-visible close buttons */
      .hover-close-btn {
        opacity: 0;
        padding: 4px 8px;
        margin-left: 4px;
        border-radius: 6px;
        background-color: transparent;
        transition: opacity 150ms ease-in-out, background-color 150ms ease-in-out;
      }

      .hover-close-icon {
        font-size: 14px;
        color: ${mocha.overlay0};
        transition: color 150ms ease-in-out;
      }

      /* Show close button on window row hover */
      .window-row:hover .hover-close-btn {
        opacity: 1;
      }

      /* Show close button on project header hover */
      .project-header:hover .hover-close-btn {
        opacity: 1;
      }

      .hover-close-btn:hover {
        background-color: rgba(243, 139, 168, 0.2);
      }

      .hover-close-btn:hover .hover-close-icon {
        color: ${mocha.red};
      }

      /* Project close button slightly larger */
      .project-hover-close {
        padding: 2px 6px;
      }

      .project-hover-close .hover-close-icon {
        font-size: 12px;
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

      /* Feature 112: Checkbox field styling for speckit option */
      .form-field-checkbox {
        margin-top: 8px;
        margin-bottom: 8px;

        checkbox {
          min-width: 18px;
          min-height: 18px;
        }

        .checkbox-label {
          margin-left: 8px;
          color: ${mocha.subtext0};
          font-size: 12px;
        }
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

      /* Enhanced form buttons with Catppuccin pill style */
      .cancel-button {
        background-color: rgba(49, 50, 68, 0.6);
        border: 1px solid ${mocha.surface1};
        border-radius: 8px;
        padding: 8px 18px;
        margin-right: 10px;
        font-size: 12px;
        font-weight: 500;
        color: ${mocha.subtext0};
      }

      .cancel-button:hover {
        background-color: rgba(69, 71, 90, 0.8);
        border-color: ${mocha.overlay0};
        color: ${mocha.text};
      }

      .save-button {
        background-color: ${mocha.blue};
        border: none;
        border-radius: 8px;
        padding: 8px 20px;
        font-size: 12px;
        color: ${mocha.base};
        font-weight: bold;
        box-shadow: 0 2px 8px rgba(137, 180, 250, 0.3);
      }

      .save-button:hover {
        background-color: ${mocha.sapphire};
        box-shadow: 0 4px 12px rgba(116, 199, 236, 0.4);
      }

      /* T039: Disabled save button (validation failed) */
      .save-button-disabled {
        background-color: ${mocha.surface0};
        border: 1px solid ${mocha.surface1};
        border-radius: 8px;
        padding: 8px 20px;
        font-size: 12px;
        color: ${mocha.overlay0};
        font-weight: bold;
        opacity: 0.6;
      }

      /* Feature 096 T021: Loading state save button */
      .save-button-loading {
        background-color: rgba(137, 180, 250, 0.2);
        border: 1px solid ${mocha.blue};
        border-radius: 8px;
        padding: 8px 20px;
        font-size: 12px;
        color: ${mocha.blue};
        font-weight: bold;
        font-style: italic;
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
        /* GTK CSS doesn't support letter-spacing */
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
        padding: 0 8px 8px 8px;
      }

      .events-list {
        padding: 4px;
        margin-top: 4px;
      }

      /* Feature 102 T065: Burst indicator styles */
      .burst-indicator {
        padding: 6px 12px;
        margin: 4px 8px;
        border-radius: 4px;
        background-color: rgba(249, 226, 175, 0.1);
        border: 1px solid rgba(249, 226, 175, 0.3);
      }

      .burst-badge {
        font-size: 12px;
        color: ${mocha.yellow};
        font-weight: bold;
      }

      .burst-badge.burst-active {
        color: ${mocha.red};
        /* Animated pulse effect for active burst */
      }

      .burst-badge.burst-inactive {
        color: ${mocha.subtext0};
      }

      .event-card {
        background-color: ${mocha.surface0};
        border-left: 3px solid ${mocha.overlay0};
        border-radius: 4px;
        padding: 8px;
        margin-bottom: 6px;
        /* GTK CSS doesn't support transition */
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

      /* Feature 102: i3pm event category styles (T015) */
      .event-card.event-category-project {
        border-left-color: ${mocha.peach};
      }

      .event-card.event-category-visibility {
        border-left-color: ${mocha.mauve};
      }

      .event-card.event-category-scratchpad {
        border-left-color: ${mocha.pink};
      }

      .event-card.event-category-launch {
        border-left-color: ${mocha.green};
      }

      .event-card.event-category-state {
        border-left-color: ${mocha.sapphire};
      }

      .event-card.event-category-command {
        border-left-color: ${mocha.sky};
      }

      .event-card.event-category-trace {
        border-left-color: ${mocha.lavender};
      }

      /* Feature 102: Source indicator styles (T015-T016) */
      .event-source-badge {
        font-size: 14px;
        margin-right: 8px;
        min-width: 18px;
        padding: 2px;
        border-radius: 3px;
      }

      .event-source-badge.source-i3pm {
        color: ${mocha.peach};
        background-color: rgba(250, 179, 135, 0.15);
      }

      .event-source-badge.source-sway {
        color: ${mocha.blue};
        background-color: rgba(137, 180, 250, 0.1);
      }

      /* Feature 102: i3pm event card distinction (T015) */
      .event-card.event-source-i3pm {
        background-color: rgba(250, 179, 135, 0.05);
      }

      .event-card.event-source-i3pm:hover {
        background-color: rgba(250, 179, 135, 0.1);
      }

      /* Feature 102 (T028): Trace indicator icon styles */
      .event-trace-indicator {
        font-size: 14px;
        margin-right: 6px;
        color: ${mocha.mauve};
        min-width: 16px;
        opacity: 0.9;
      }

      /* Feature 102 T066: Evicted trace indicator */
      .event-trace-indicator.trace-evicted {
        color: ${mocha.overlay0};
        opacity: 0.6;
      }

      /* Feature 102 T067: Orphaned event indicator */
      .event-orphaned-indicator {
        font-size: 12px;
        margin-right: 6px;
        color: ${mocha.yellow};
        opacity: 0.8;
      }

      /* Feature 102 T052: Duration badge styles for slow events */
      .event-duration-badge {
        font-size: 10px;
        font-weight: 600;
        margin-right: 6px;
        padding: 2px 6px;
        border-radius: 8px;
        min-width: 40px;
      }

      .event-duration-badge.duration-slow {
        color: ${mocha.yellow};
        background-color: rgba(249, 226, 175, 0.2);
      }

      .event-duration-badge.duration-critical {
        color: ${mocha.red};
        background-color: rgba(243, 139, 168, 0.2);
      }

      /* Highlight events that are part of a trace */
      .event-card.event-has-trace {
        border-left: 2px solid ${mocha.mauve};
      }

      /* Feature 102 (T036): Causality chain indicator */
      .event-chain-indicator {
        background-color: ${mocha.lavender};
        border-radius: 1px;
        margin-right: 8px;
        /* GTK CSS doesn't support min-height: 100% - use fixed height */
        min-height: 20px;
      }

      /* Feature 102 (T037): Causality chain event styling */
      .event-card.event-in-chain {
        border-left: 2px solid ${mocha.lavender};
        /* GTK CSS doesn't support transition */
      }

      /* Feature 102 (T038): Hover highlighting for causality chain */
      .event-card.event-in-chain:hover {
        background-color: rgba(180, 190, 254, 0.15);
      }

      /* Feature 102 (T037): Child event depth indicators */
      .event-card.event-child-depth-1 {
        border-left-color: ${mocha.sapphire};
      }
      .event-card.event-child-depth-2 {
        border-left-color: ${mocha.sky};
      }
      .event-card.event-child-depth-3 {
        border-left-color: ${mocha.teal};
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

      /* Feature 092: Event Filter Panel Styling */
      .filter-panel {
        background-color: transparent;
        padding: 0;
        margin: 0 4px 0 4px;
      }

      .filter-header {
        padding: 6px 8px;
        background-color: ${mocha.surface0};
        border-radius: 4px;
        border: 1px solid ${mocha.overlay0};
        margin-bottom: 0;
      }

      .filter-header:hover {
        background-color: ${mocha.surface1};
        border-color: ${mocha.blue};
      }

      .filter-title {
        font-size: 11px;
        font-weight: 600;
        color: ${mocha.blue};
      }

      .filter-toggle {
        font-size: 9px;
        color: ${mocha.subtext0};
        margin-left: 8px;
      }

      .filter-controls {
        padding: 8px 4px;
        background-color: ${mocha.mantle};
        border-radius: 6px;
        margin-top: 4px;
        border: 1px solid ${mocha.overlay0};
      }

      .filter-global-controls {
        padding: 6px 4px;
        margin-bottom: 8px;
      }

      .filter-button {
        background-color: ${mocha.surface0};
        color: ${mocha.text};
        border: 1px solid ${mocha.overlay0};
        border-radius: 3px;
        padding: 4px 10px;
        margin-right: 6px;
        font-size: 10px;
        font-weight: 500;
      }

      .filter-button:hover {
        background-color: ${mocha.surface1};
        border-color: ${mocha.blue};
      }

      /* Feature 102 T053: Sort controls */
      .sort-controls {
        /* GTK CSS doesn't support margin-left: auto; use hexpand on sibling instead */
        padding-left: 12px;
      }

      .sort-label {
        font-size: 10px;
        color: ${mocha.subtext0};
        margin-right: 6px;
      }

      .sort-button {
        background-color: ${mocha.surface0};
        color: ${mocha.subtext0};
        border: 1px solid ${mocha.surface1};
        border-radius: 3px;
        padding: 3px 8px;
        margin-left: 4px;
        font-size: 10px;
      }

      .sort-button:hover {
        background-color: ${mocha.surface1};
        color: ${mocha.text};
      }

      .sort-button.active {
        background-color: ${mocha.blue};
        color: ${mocha.base};
        border-color: ${mocha.blue};
      }

      .filter-category-group {
        background-color: ${mocha.base};
        border-radius: 4px;
        padding: 6px;
        margin-bottom: 6px;
        border: 1px solid ${mocha.surface0};
      }

      .filter-category-title {
        font-size: 10px;
        font-weight: 600;
        color: ${mocha.teal};
        margin-bottom: 4px;
        padding: 2px 0;
        border-bottom: 1px solid ${mocha.surface0};
      }

      .filter-checkboxes {
        padding: 2px 0;
      }

      .filter-checkbox-item {
        padding: 2px 6px;
        margin-right: 8px;
        border-radius: 3px;
        background-color: transparent;
      }

      .filter-checkbox-item:hover {
        background-color: ${mocha.surface0};
      }

      .filter-checkbox-icon {
        font-size: 12px;
        color: ${mocha.blue};
        margin-right: 3px;
      }

      .filter-checkbox-label {
        font-size: 9px;
        color: ${mocha.text};
        font-family: monospace;
      }

      /* Feature 102: i3pm filter category styling (T014) */
      .i3pm-events-category {
        border-color: ${mocha.peach};
        background-color: rgba(250, 179, 135, 0.05);
      }

      .i3pm-title {
        color: ${mocha.peach};
      }

      .filter-subcategory {
        padding-left: 8px;
        margin-top: 4px;
        border-left: 2px solid ${mocha.surface1};
      }

      .filter-subcategory-title {
        font-size: 9px;
        font-weight: 500;
        color: ${mocha.subtext0};
        margin-bottom: 2px;
        margin-top: 4px;
      }

      /* Feature 101: Traces View Styling */
      .traces-summary {
        padding: 8px 12px;
        background-color: ${mocha.surface0};
        border-radius: 6px;
        margin-bottom: 8px;
      }

      .traces-count {
        font-size: 12px;
        font-weight: 600;
        color: ${mocha.teal};
      }

      .traces-help {
        font-size: 12px;
        color: ${mocha.subtext0};
      }

      /* Feature 102 T059: Template selector dropdown */
      .template-selector-container {
        /* GTK CSS doesn't support position: relative */
        margin-right: 8px;
      }

      .template-add-button {
        background-color: ${mocha.surface0};
        color: ${mocha.text};
        border: 1px solid ${mocha.overlay0};
        border-radius: 4px;
        padding: 4px 10px;
        font-size: 11px;
        font-weight: 500;
      }

      .template-add-button:hover {
        background-color: ${mocha.surface1};
        border-color: ${mocha.blue};
      }

      .template-add-button.active {
        background-color: ${mocha.blue};
        color: ${mocha.base};
        border-color: ${mocha.blue};
      }

      .template-dropdown {
        /* GTK CSS doesn't support position: absolute, top, right, z-index */
        margin-top: 4px;
        background-color: ${mocha.surface0};
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
        padding: 4px;
        /* Feature 119: Reduced min-width for narrower panel */
        min-width: 180px;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
      }

      .template-item {
        padding: 8px 10px;
        border-radius: 4px;
        margin: 2px 0;
      }

      .template-item:hover {
        background-color: ${mocha.surface1};
      }

      .template-icon {
        font-size: 18px;
        color: ${mocha.teal};
        margin-right: 10px;
        min-width: 24px;
      }

      .template-name {
        font-size: 12px;
        font-weight: 600;
        color: ${mocha.text};
        margin-bottom: 2px;
      }

      .template-description {
        font-size: 10px;
        color: ${mocha.subtext0};
      }

      .traces-empty {
        padding: 40px 20px;
        /* text-align not supported in GTK CSS - use :halign in yuck instead */
      }

      .traces-empty .empty-icon {
        font-size: 48px;
        color: ${mocha.overlay0};
        margin-bottom: 12px;
      }

      .traces-empty .empty-title {
        font-size: 14px;
        font-weight: 600;
        color: ${mocha.subtext0};
        margin-bottom: 8px;
      }

      .traces-empty .empty-hint {
        font-size: 11px;
        color: ${mocha.subtext0};
        margin-bottom: 4px;
      }

      .traces-empty .empty-command {
        font-size: 11px;
        color: ${mocha.peach};
        font-family: monospace;
        background-color: ${mocha.surface0};
        padding: 4px 8px;
        border-radius: 4px;
      }

      .traces-list {
        padding: 0 4px;
      }

      .trace-card {
        background-color: ${mocha.surface0};
        border-radius: 6px;
        padding: 10px 12px;
        margin-bottom: 6px;
        border-left: 3px solid ${mocha.overlay0};
      }

      .trace-card:hover {
        background-color: ${mocha.surface1};
      }

      .trace-card.trace-active {
        border-left-color: ${mocha.red};
        background-color: rgba(243, 139, 168, 0.1);
      }

      .trace-card.trace-stopped {
        border-left-color: ${mocha.overlay0};
        opacity: 0.8;
      }

      .trace-status-icon {
        font-size: 18px;
        margin-right: 10px;
        min-width: 24px;
      }

      .trace-header {
        margin-bottom: 4px;
      }

      .trace-id {
        font-size: 11px;
        font-family: monospace;
        color: ${mocha.blue};
        font-weight: 600;
      }

      .trace-status-label {
        font-size: 9px;
        font-weight: 700;
        padding: 2px 6px;
        border-radius: 3px;
        background-color: ${mocha.surface1};
        color: ${mocha.text};
      }

      .trace-active .trace-status-label {
        background-color: ${mocha.red};
        color: ${mocha.base};
      }

      .trace-stopped .trace-status-label {
        background-color: ${mocha.surface1};
        color: ${mocha.subtext0};
      }

      .trace-matcher {
        font-size: 10px;
        color: ${mocha.subtext0};
        font-family: monospace;
        margin-bottom: 4px;
      }

      .trace-stats {
        font-size: 10px;
        color: ${mocha.subtext0};
      }

      .trace-events {
        color: ${mocha.green};
      }

      .trace-separator {
        color: ${mocha.overlay0};
      }

      .trace-duration {
        color: ${mocha.yellow};
      }

      .trace-window-id {
        color: ${mocha.mauve};
        font-family: monospace;
      }

      .trace-actions {
        margin-left: 10px;
      }

      .trace-action-btn {
        background-color: ${mocha.surface1};
        color: ${mocha.text};
        border: 1px solid ${mocha.overlay0};
        border-radius: 4px;
        padding: 4px 8px;
        font-size: 12px;
        margin-bottom: 4px;
        min-width: 28px;
      }

      .trace-action-btn:hover {
        background-color: ${mocha.surface1};
        border-color: ${mocha.blue};
      }

      .trace-stop-btn:hover {
        background-color: ${mocha.red};
        border-color: ${mocha.red};
        color: ${mocha.base};
      }

      /* Feature 101: Trace copy button - matches json-copy-btn pattern */
      .trace-copy-btn {
        font-size: 14px;
        padding: 4px 8px;
        background-color: rgba(137, 180, 250, 0.2);
        color: ${mocha.blue};
        border: 1px solid ${mocha.blue};
        border-radius: 4px;
        min-width: 28px;
        margin-right: 4px;
      }

      .trace-copy-btn:hover {
        background-color: rgba(137, 180, 250, 0.3);
        box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
      }

      .trace-copy-btn:active {
        background-color: rgba(137, 180, 250, 0.5);
        box-shadow: 0 0 12px rgba(137, 180, 250, 0.6);
      }

      .trace-copy-btn.copied {
        background-color: rgba(166, 227, 161, 0.3);
        color: ${mocha.green};
        border: 1px solid ${mocha.green};
        box-shadow: 0 0 12px rgba(166, 227, 161, 0.5),
                    inset 0 0 8px rgba(166, 227, 161, 0.2);
        font-weight: bold;
      }

      .trace-copy-btn.copied:hover {
        background-color: rgba(166, 227, 161, 0.4);
        box-shadow: 0 0 16px rgba(166, 227, 161, 0.6);
      }

      /* Feature 101: Expanded trace card styles */
      .trace-card.trace-expanded {
        border-left-color: ${mocha.lavender};
        background-color: rgba(180, 190, 254, 0.1);
      }

      .trace-card-header {
        padding: 4px 0;
      }

      .trace-expand-icon {
        font-size: 12px;
        color: ${mocha.overlay0};
        margin-right: 6px;
        min-width: 16px;
      }

      .trace-expanded .trace-expand-icon {
        color: ${mocha.lavender};
      }

      /* Feature 102 (T031): Highlight for navigation (GTK CSS doesn't support keyframes) */
      .trace-card.trace-highlight {
        border: 2px solid ${mocha.mauve};
        background-color: rgba(203, 166, 247, 0.15);
      }

      .trace-events-panel {
        margin-top: 8px;
        padding-top: 8px;
        border-top: 1px solid ${mocha.surface1};
      }

      .trace-events-loading {
        padding: 12px;
        color: ${mocha.subtext0};
        font-size: 11px;
        font-style: italic;
      }

      .trace-events-list {
        padding: 0;
      }

      .trace-event-row {
        padding: 6px 8px;
        margin-bottom: 2px;
        background-color: ${mocha.base};
        border-radius: 4px;
        border-left: 2px solid ${mocha.overlay0};
      }

      .trace-event-row:hover {
        background-color: ${mocha.surface0};
      }

      /* Event type specific colors */
      .trace-event-row.trace\:\:start {
        border-left-color: ${mocha.green};
      }

      .trace-event-row.trace\:\:stop {
        border-left-color: ${mocha.red};
      }

      .trace-event-row.window\:\:new {
        border-left-color: ${mocha.blue};
      }

      .trace-event-row.window\:\:focus {
        border-left-color: ${mocha.yellow};
      }

      .trace-event-row.window\:\:move {
        border-left-color: ${mocha.peach};
      }

      .trace-event-row.mark\:\:added {
        border-left-color: ${mocha.mauve};
      }

      .event-time {
        font-family: monospace;
        font-size: 10px;
        color: ${mocha.subtext0};
        min-width: 60px;
        margin-right: 8px;
      }

      .event-type-badge {
        font-size: 9px;
        font-weight: 600;
        padding: 2px 6px;
        border-radius: 3px;
        background-color: ${mocha.surface1};
        color: ${mocha.text};
        margin-right: 8px;
        min-width: 80px;
        /* text-align not supported in GTK CSS - use :halign in yuck widget instead */
      }

      /* Event type badge colors */
      .event-type-badge.trace\:\:start {
        background-color: rgba(166, 227, 161, 0.2);
        color: ${mocha.green};
      }

      .event-type-badge.trace\:\:stop {
        background-color: rgba(243, 139, 168, 0.2);
        color: ${mocha.red};
      }

      .event-type-badge.window\:\:new {
        background-color: rgba(137, 180, 250, 0.2);
        color: ${mocha.blue};
      }

      .event-type-badge.window\:\:focus {
        background-color: rgba(249, 226, 175, 0.2);
        color: ${mocha.yellow};
      }

      .event-type-badge.window\:\:move {
        background-color: rgba(250, 179, 135, 0.2);
        color: ${mocha.peach};
      }

      .event-type-badge.mark\:\:added {
        background-color: rgba(203, 166, 247, 0.2);
        color: ${mocha.mauve};
      }

      .event-content {
        padding-left: 4px;
      }

      .event-description {
        font-size: 10px;
        color: ${mocha.text};
      }

      .event-changes {
        font-size: 9px;
        color: ${mocha.subtext0};
        font-family: monospace;
        margin-top: 2px;
      }

      /* ========================================
       * Feature 116: Devices Tab Styling
       * ======================================== */

      .devices-content {
        padding: 10px;
      }

      .devices-section {
        background-color: ${mocha.surface0};
        border-radius: 8px;
        padding: 10px 12px;
        margin-bottom: 8px;
        border: 1px solid ${mocha.surface1};

        .section-title {
          font-size: 11px;
          font-weight: 600;
          color: ${mocha.blue};
          margin-bottom: 8px;
          padding-bottom: 6px;
          border-bottom: 1px solid ${mocha.surface1};
          letter-spacing: 0.5px;
        }

        .section-content {
          padding: 2px 0;
        }
      }

      /* Audio Section */
      .device-row {
        padding: 4px 6px;
        background-color: ${mocha.mantle};
        border-radius: 6px;
        margin-bottom: 6px;

        .device-label {
          font-size: 10px;
          color: ${mocha.subtext0};
          min-width: 45px;
        }

        .device-value {
          font-size: 10px;
          color: ${mocha.text};
        }
      }

      .slider-row {
        padding: 4px 2px;

        .slider-icon {
          font-size: 14px;
          color: ${mocha.blue};
          min-width: 20px;
        }

        .device-slider {
          min-width: 100px;
          margin: 0 6px;

          trough {
            background-color: ${mocha.surface1};
            border-radius: 3px;
            min-height: 4px;
          }

          highlight {
            background-color: ${mocha.blue};
            border-radius: 3px;
          }

          slider {
            background-color: ${mocha.text};
            border-radius: 50%;
            min-width: 10px;
            min-height: 10px;
            margin: -3px;
          }
        }

        .slider-value {
          font-size: 10px;
          font-weight: 600;
          color: ${mocha.text};
          min-width: 28px;
          margin-right: 4px;
        }

        .mute-btn {
          font-size: 12px;
          color: ${mocha.subtext0};
          padding: 3px 6px;
          border-radius: 4px;
          background-color: ${mocha.surface1};

          &:hover {
            background-color: ${mocha.overlay0};
            color: ${mocha.text};
          }

          &.muted {
            color: ${mocha.red};
            background-color: shade(${mocha.red}, 0.3);
          }
        }
      }

      /* Bluetooth Section */
      .toggle-row {
        padding: 4px 2px;

        .toggle-icon {
          font-size: 14px;
          color: ${mocha.blue};
          min-width: 20px;
        }

        .toggle-label {
          font-size: 11px;
          font-weight: 500;
          color: ${mocha.text};
        }

        .toggle-btn {
          min-width: 32px;
          min-height: 20px;
          border-radius: 10px;
          border: none;
          padding: 2px 8px;

          label {
            font-size: 11px;
          }

          &.on {
            background-color: ${mocha.green};
            color: ${mocha.base};
          }

          &.off {
            background-color: ${mocha.surface1};
            color: ${mocha.overlay0};
          }

          &:hover {
            opacity: 0.9;
          }
        }
      }

      .device-list {
        padding-top: 4px;
        margin-top: 2px;

        .device-item {
          background-color: ${mocha.mantle};
          border-radius: 5px;
          padding: 6px 8px;
          margin-bottom: 4px;

          &.connected {
            border-left: 2px solid ${mocha.green};
            background-color: shade(${mocha.green}, 0.2);
          }

          .device-icon {
            font-size: 12px;
            color: ${mocha.subtext0};
            min-width: 18px;
          }

          .device-name {
            font-size: 10px;
            color: ${mocha.text};
          }

          .connect-btn {
            font-size: 9px;
            font-weight: 500;
            color: ${mocha.blue};
            padding: 3px 6px;
            background-color: ${mocha.surface1};
            border-radius: 4px;

            &:hover {
              background-color: ${mocha.blue};
              color: ${mocha.base};
            }
          }
        }
      }

      /* Power Section */
      .battery-row {
        padding: 6px;
        background-color: ${mocha.mantle};
        border-radius: 6px;
        margin-bottom: 6px;

        .battery-icon {
          font-size: 18px;
          color: ${mocha.green};
          min-width: 26px;

          &.low {
            color: ${mocha.yellow};
          }

          &.critical {
            color: ${mocha.red};
          }

          &.charging {
            color: ${mocha.teal};
          }
        }

        .battery-info {
          .battery-percent {
            font-size: 14px;
            font-weight: 600;
            color: ${mocha.text};
          }

          .battery-state {
            font-size: 10px;
            color: ${mocha.subtext0};
          }

          .battery-time {
            font-size: 9px;
            color: ${mocha.subtext0};
            margin-top: 2px;
          }
        }
      }

      .battery-details {
        padding: 6px;
        background-color: ${mocha.mantle};
        border-radius: 6px;
        margin-bottom: 6px;

        .detail-item {
          .detail-label {
            font-size: 9px;
            color: ${mocha.subtext0};
          }

          .detail-value {
            font-size: 11px;
            font-weight: 600;
            color: ${mocha.text};
          }
        }
      }

      .power-profiles {
        padding: 4px;
        background-color: ${mocha.mantle};
        border-radius: 6px;

        .profile-btn {
          padding: 6px 12px;
          border-radius: 5px;
          border: none;
          background-image: none;

          label {
            font-size: 14px;
          }
        }

        /* Power Saver - Green theme */
        .profile-btn.profile-saver {
          background-color: ${mocha.surface0};
          background-image: none;

          label {
            color: ${mocha.green};
          }
        }

        .profile-btn.profile-saver:hover {
          background-color: ${mocha.surface1};
          background-image: none;
        }

        .profile-btn.profile-saver.active {
          background-color: ${mocha.green};
          background-image: none;

          label {
            color: ${mocha.base};
          }
        }

        /* Balanced - Blue theme */
        .profile-btn.profile-balanced {
          background-color: ${mocha.surface0};
          background-image: none;

          label {
            color: ${mocha.blue};
          }
        }

        .profile-btn.profile-balanced:hover {
          background-color: ${mocha.surface1};
          background-image: none;
        }

        .profile-btn.profile-balanced.active {
          background-color: ${mocha.blue};
          background-image: none;

          label {
            color: ${mocha.base};
          }
        }

        /* Performance - Peach/Orange theme */
        .profile-btn.profile-performance {
          background-color: ${mocha.surface0};
          background-image: none;

          label {
            color: ${mocha.peach};
          }
        }

        .profile-btn.profile-performance:hover {
          background-color: ${mocha.surface1};
          background-image: none;
        }

        .profile-btn.profile-performance.active {
          background-color: ${mocha.peach};
          background-image: none;

          label {
            color: ${mocha.base};
          }
        }
      }

      /* Display Section */
      .slider-label {
        font-size: 10px;
        color: ${mocha.subtext0};
        min-width: 50px;
      }

      /* Thermal Section */
      .thermal-row {
        padding: 6px;
        background-color: ${mocha.mantle};
        border-radius: 6px;
        margin-bottom: 6px;

        .thermal-icon {
          font-size: 16px;
          color: ${mocha.peach};
          min-width: 22px;
        }

        .thermal-info {
          min-width: 50px;
          margin-right: 8px;

          .thermal-label {
            font-size: 9px;
            color: ${mocha.subtext0};
          }

          .thermal-value {
            font-size: 12px;
            font-weight: 600;
            color: ${mocha.text};
          }
        }

        .thermal-bar {
          min-height: 6px;
          border-radius: 3px;

          trough {
            background-color: ${mocha.surface1};
            border-radius: 3px;
            min-height: 6px;
          }

          progress {
            background-color: ${mocha.peach};
            border-radius: 3px;
          }
        }
      }

      .fan-row {
        padding: 6px;
        background-color: ${mocha.mantle};
        border-radius: 6px;

        .fan-icon {
          font-size: 14px;
          color: ${mocha.sapphire};
          min-width: 22px;
        }

        .fan-label {
          font-size: 10px;
          color: ${mocha.subtext0};
          min-width: 30px;
        }

        .fan-value {
          font-size: 11px;
          font-weight: 500;
          color: ${mocha.text};
        }
      }

      /* Network Section */
      .network-row {
        padding: 6px;
        background-color: ${mocha.mantle};
        border-radius: 6px;
        margin-bottom: 6px;

        .network-icon {
          font-size: 16px;
          min-width: 22px;

          &.connected {
            color: ${mocha.green};
          }

          &.disconnected {
            color: ${mocha.overlay0};
          }
        }

        .network-info {
          .network-type {
            font-size: 9px;
            color: ${mocha.subtext0};
          }

          .network-value {
            font-size: 11px;
            font-weight: 500;
            color: ${mocha.text};
          }
        }
      }
    '';

    # Systemd user service for Eww monitoring panel (T018)
    systemd.user.services.eww-monitoring-panel = {
      Unit = {
        Description = "Eww Monitoring Panel for Window/Project State";
        Documentation = "file:///etc/nixos/specs/085-sway-monitoring-widget/quickstart.md";
        # Feature 117: Depend on i3-project-daemon for IPC connectivity
        # Without this, deflisten/defpoll scripts fail on startup
        # Feature 121: Use sway-session.target for proper Sway lifecycle binding
        After = [ "sway-session.target" "i3-project-daemon.service" ];
        Wants = [ "i3-project-daemon.service" ];
        PartOf = [ "sway-session.target" ];
      };

      Service = {
        Type = "simple";
        # Use wrapper script that manages daemon + handles toggle signals
        # All eww processes (daemon + GTK renderers) stay in service cgroup
        # No orphans possible since toggle sends signal instead of spawning processes
        ExecStart = "${wrapperScript}/bin/eww-monitoring-panel-wrapper";
        # Clean shutdown: use 'eww kill' which properly cleans up THIS service's socket
        ExecStopPost = "${pkgs.bash}/bin/bash -c '${pkgs.eww}/bin/eww --config %h/.config/eww-monitoring-panel kill 2>/dev/null || true'";
        Restart = "on-failure";
        RestartSec = "3s";
        # Critical: control-group ensures ALL child processes are killed when service stops
        # This now works correctly since all eww commands run within the wrapper
        KillMode = "control-group";
      };

      Install = {
        # Feature 121: Auto-start with Sway session (uses swaymsg for workspace data)
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}
# Rebuild trigger 1765901724
