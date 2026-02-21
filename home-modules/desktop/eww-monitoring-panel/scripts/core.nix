{ pkgs, config, pythonForBackend, mocha, hostname, cfg, clipboardSyncScript, ... }:

let
  monitoringDataScript = pkgs.writeShellScriptBin "monitoring-data-backend" ''
    #!${pkgs.bash}/bin/bash
    # Version: 2025-12-24-v16 (Feature 135: Fix inotify watching OTEL sessions file atomic writes)

    # Add user profile bin to PATH so i3pm can be found by subprocess calls
    export PATH="${config.home.profileDirectory}/bin:$PATH"

    # Set PYTHONPATH to tools directory for i3_project_manager imports
    export PYTHONPATH="${../../../tools}"

    # Feature 117: Set daemon socket path (user service at XDG_RUNTIME_DIR)
    export I3PM_DAEMON_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

    # Use Python with i3ipc package included
    # Pass through all arguments (e.g., --listen flag)
    exec ${pythonForBackend}/bin/python3 ${../../../tools/i3_project_manager/cli/monitoring_data.py} "$@"
  '';

  projectsDataStreamScript = pkgs.writeShellScriptBin "eww-monitoring-projects-stream" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    DATA_FILE="$RUNTIME_DIR/eww-monitoring-projects.json"
    VERSION_FILE="$RUNTIME_DIR/eww-monitoring-projects.version"
    INOTIFYWAIT="${pkgs.inotify-tools}/bin/inotifywait"
    ${pkgs.coreutils}/bin/mkdir -p "$RUNTIME_DIR"

    emit_data() {
      if [[ -s "$DATA_FILE" ]]; then
        ${pkgs.coreutils}/bin/cat "$DATA_FILE"
      else
        ${pkgs.coreutils}/bin/printf '%s\n' '{"status":"loading","discovered_repositories":[],"repo_count":0,"worktree_count":0,"active_project":null}'
      fi
    }

    emit_data
    while true; do
      if [[ -x "$INOTIFYWAIT" ]]; then
        CHANGED=$("$INOTIFYWAIT" -q -e close_write,create,moved_to,delete --format "%f" "$RUNTIME_DIR" 2>/dev/null || true)
        if [[ "$CHANGED" == "eww-monitoring-projects.json" || "$CHANGED" == "eww-monitoring-projects.version" ]]; then
          emit_data
        fi
      else
        ${pkgs.coreutils}/bin/sleep 2
        emit_data
      fi
    done
  '';

  dockModeStreamScript = pkgs.writeShellScriptBin "eww-monitoring-dock-mode-stream" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    STATE_FILE="$HOME/.local/state/eww-monitoring-panel/dock-mode"
    INOTIFYWAIT="${pkgs.inotify-tools}/bin/inotifywait"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$STATE_FILE")"

    while true; do
      MODE="$(${pkgs.coreutils}/bin/cat "$STATE_FILE" 2>/dev/null || true)"
      if [[ "$MODE" == "docked" ]]; then
        ${pkgs.coreutils}/bin/printf 'true\n'
      else
        ${pkgs.coreutils}/bin/printf 'false\n'
      fi
      "$INOTIFYWAIT" -qq -e modify,create,delete "$STATE_FILE" 2>/dev/null || ${pkgs.coreutils}/bin/sleep 2
    done
  '';

  # Feature 110: Spinner animation uses CSS transition (defpoll toggles pulse_phase)
  # GTK3 supports CSS transitions but EWW doesn't support @keyframes properly

  # Service wrapper script - manages daemon and handles toggle signals
  # This keeps all eww processes (daemon + GTK renderers) in the service cgroup
  # preventing orphaned processes when toggle is invoked from keybindings
  # Feature 125: Updated to support dock mode persistence and two window definitions
  wrapperScript = pkgs.writeShellScriptBin "eww-monitoring-panel-wrapper" ''
    #!${pkgs.bash}/bin/bash

    EWW="${pkgs.eww}/bin/eww"
    GREP="${pkgs.gnugrep}/bin/grep"
    CONFIG="$HOME/.config/eww-monitoring-panel"
    TIMEOUT="${pkgs.coreutils}/bin/timeout"
    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    PID_FILE="$RUNTIME_DIR/eww-monitoring-panel-wrapper.pid"
    STATE_DIR="$HOME/.local/state/eww-monitoring-panel"
    DOCK_MODE_FILE="$STATE_DIR/dock-mode"
    PANEL_WINDOW_ID="monitoring-panel-main"

    ${pkgs.coreutils}/bin/mkdir -p "$RUNTIME_DIR" "$STATE_DIR"

    # Write wrapper PID for toggle script to send signals directly to this process only
    echo $$ > "$PID_FILE"

    # Cleanup on exit
    cleanup() {
      rm -f "$PID_FILE"
      kill $DAEMON_PID 2>/dev/null
    }
    trap cleanup EXIT

    # Start daemon in background, capture PID
    $EWW --config "$CONFIG" daemon --no-daemonize &
    DAEMON_PID=$!

    # Wait for daemon ready (max 6 seconds)
    for i in $(seq 1 30); do
      $TIMEOUT 1s $EWW --no-daemonize --config "$CONFIG" ping 2>/dev/null && break
      ${pkgs.coreutils}/bin/sleep 0.2
    done

    # Feature 125: Read dock mode state and open correct window
    # Default to docked mode if state file doesn't exist or is invalid
    DOCK_MODE="docked"
    if [[ -f "$DOCK_MODE_FILE" ]]; then
      SAVED_MODE=$(${pkgs.coreutils}/bin/cat "$DOCK_MODE_FILE" 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '[:space:]')
      if [[ "$SAVED_MODE" == "overlay" ]]; then
        DOCK_MODE="overlay"
      fi
    fi

    open_target_window() {
      local target_window="$1"
      local attempt
      for attempt in $(seq 1 5); do
        # eww can occasionally return a transient IPC error even when the
        # window opens successfully; verify using active-windows before failing.
        $TIMEOUT 2s $EWW --no-daemonize --config "$CONFIG" open --id "$PANEL_WINDOW_ID" "$target_window" >/dev/null 2>&1 || true
        if $TIMEOUT 1s $EWW --no-daemonize --config "$CONFIG" active-windows 2>/dev/null | $GREP -q "^$PANEL_WINDOW_ID:"; then
          return 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.2
      done
      return 1
    }

    # Open exactly one panel window to prevent duplicate widgets.
    if [[ "$DOCK_MODE" == "docked" ]]; then
      TARGET_WINDOW="monitoring-panel-docked"
    else
      TARGET_WINDOW="monitoring-panel-overlay"
    fi

    if ! open_target_window "$TARGET_WINDOW"; then
      # Do not crash-loop the service on transient IPC/startup races.
      # Keep daemon/streams alive and allow manual toggle/reopen to recover.
      echo "[eww-monitoring-panel] startup window open verification failed; continuing without fatal exit" >&2
    fi

    # Feature 125: Toggle handler - called when SIGUSR1 received
    # SOLUTION: Stop service to hide (releases struts), start to show
    # This avoids eww daemon auto-spawn issues with eww open --toggle
    toggle_panel() {
      # Stop the service - this exits the wrapper and releases all resources
      exec ${pkgs.systemd}/bin/systemctl --user stop eww-monitoring-panel.service
    }

    trap toggle_panel SIGUSR1

    # Wait for daemon (re-wait after signal interrupts)
    while kill -0 $DAEMON_PID 2>/dev/null; do
      wait $DAEMON_PID || true
    done
  '';

  # Toggle script for panel visibility.
  toggleScript = pkgs.writeShellScriptBin "toggle-monitoring-panel" ''
    #!${pkgs.bash}/bin/bash
    # Feature 125: Toggle panel visibility via service start/stop
    # This avoids eww daemon auto-spawn issues with eww open --toggle

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    ${pkgs.coreutils}/bin/mkdir -p "$RUNTIME_DIR"
    FLOCK_FILE="$RUNTIME_DIR/eww-monitoring-panel-control.flock"
    LOCK_FILE="$RUNTIME_DIR/eww-monitoring-panel-toggle.lock"
    exec 9>"$FLOCK_FILE"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0

    # Debounce: prevent rapid toggling
    if [[ -f "$LOCK_FILE" ]]; then
      LOCK_AGE=$(($(${pkgs.coreutils}/bin/date +%s) - $(${pkgs.coreutils}/bin/stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
      if [[ $LOCK_AGE -lt 1 ]]; then
        exit 0
      fi
    fi
    ${pkgs.coreutils}/bin/touch "$LOCK_FILE"

    # Toggle: if running -> stop (hide), if stopped -> start (show)
    if ${pkgs.systemd}/bin/systemctl --user is-active --quiet eww-monitoring-panel.service; then
      ${pkgs.systemd}/bin/systemctl --user stop eww-monitoring-panel.service
    else
      ${pkgs.systemd}/bin/systemctl --user start eww-monitoring-panel.service
    fi
  '';

  # Feature 125: toggle-panel-focus and exit-monitor-mode scripts REMOVED
  # Focus mode functionality replaced by dock mode toggle (Mod+Shift+M)

  # Feature 125: Toggle between overlay and docked modes (Mod+Shift+M)
  # Uses persisted state + service restart for robust mode transitions.
  toggleDockModeScript = pkgs.writeShellScriptBin "toggle-panel-dock-mode" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    STATE_DIR="$HOME/.local/state/eww-monitoring-panel"
    STATE_FILE="$STATE_DIR/dock-mode"
    ${pkgs.coreutils}/bin/mkdir -p "$RUNTIME_DIR"
    ${pkgs.coreutils}/bin/mkdir -p "$STATE_DIR"
    FLOCK_FILE="$RUNTIME_DIR/eww-monitoring-panel-control.flock"
    LOCK_FILE="$RUNTIME_DIR/eww-monitoring-panel-dock.lock"
    exec 9>"$FLOCK_FILE"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0

    # Debounce: prevent rapid toggling
    if [[ -f "$LOCK_FILE" ]]; then
      LOCK_AGE=$(($(${pkgs.coreutils}/bin/date +%s) - $(${pkgs.coreutils}/bin/stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
      if [[ $LOCK_AGE -lt 1 ]]; then
        exit 0
      fi
    fi
    ${pkgs.coreutils}/bin/touch "$LOCK_FILE"

    CURRENT_MODE="docked"
    if [[ -f "$STATE_FILE" ]]; then
      SAVED_MODE="$(${pkgs.coreutils}/bin/cat "$STATE_FILE" 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '[:space:]')"
      if [[ "$SAVED_MODE" == "overlay" ]]; then
        CURRENT_MODE="overlay"
      fi
    fi

    if [[ "$CURRENT_MODE" == "overlay" ]]; then
      ${pkgs.coreutils}/bin/printf '%s' "docked" > "$STATE_FILE"
    else
      ${pkgs.coreutils}/bin/printf '%s' "overlay" > "$STATE_FILE"
    fi

    if ${pkgs.systemd}/bin/systemctl --user is-active --quiet eww-monitoring-panel.service; then
      ${pkgs.systemd}/bin/systemctl --user restart eww-monitoring-panel.service
    else
      ${pkgs.systemd}/bin/systemctl --user start eww-monitoring-panel.service
    fi
  '';

  # Refresh projects tab data on-demand to avoid high-frequency large JSON updates.
  # Writes payload to runtime file to avoid `eww update` argv size limits.
  refreshProjectsDataScript = pkgs.writeShellScriptBin "refresh-projects-data" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    I3PM="${config.home.profileDirectory}/bin/i3pm"
    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    ${pkgs.coreutils}/bin/mkdir -p "$RUNTIME_DIR"
    FLOCK_FILE="$RUNTIME_DIR/refresh-projects-data.flock"
    PROJECTS_FILE="$RUNTIME_DIR/eww-monitoring-projects.json"
    VERSION_FILE="$RUNTIME_DIR/eww-monitoring-projects.version"
    exec 9>"$FLOCK_FILE"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0

    # Keep repos.json fresh so new/removed worktrees appear in the Projects view.
    ${pkgs.coreutils}/bin/timeout 8s "$I3PM" discover >/dev/null 2>&1 || true

    if ${monitoringDataScript}/bin/monitoring-data-backend --mode projects 2>/dev/null | ${pkgs.jq}/bin/jq -c '.' > "$PROJECTS_FILE" 2>/dev/null; then
      :
    else
      ${pkgs.coreutils}/bin/cat > "$PROJECTS_FILE" <<'EOF'
{"status":"error","discovered_repositories":[],"repo_count":0,"worktree_count":0,"active_project":null,"error":"Failed to refresh projects data"}
EOF
    fi

    # Touch a version marker to signal listeners even when JSON content is unchanged.
    ${pkgs.coreutils}/bin/date +%s%N > "$VERSION_FILE"
  '';

  monitoringPanelHealthGuardScript = pkgs.writeShellScriptBin "eww-monitoring-panel-health-guard" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SERVICE="eww-monitoring-panel.service"
    WINDOW="''${EWW_MONITORING_GUARD_WINDOW:-5 minutes ago}"
    # Default threshold raised to avoid restart thrash from transient startup
    # channel-close noise while still catching sustained failures.
    THRESHOLD="''${EWW_MONITORING_GUARD_THRESHOLD:-10}"
    COOLDOWN_SECONDS="''${EWW_MONITORING_GUARD_COOLDOWN_SECONDS:-600}"
    STATE_DIR="$HOME/.local/state/eww-monitoring-panel"
    STAMP_FILE="$STATE_DIR/health-guard-last-restart"
    LOCK_FILE="$STATE_DIR/health-guard.flock"
    EWW="${pkgs.eww}/bin/eww"
    CONFIG="$HOME/.config/eww-monitoring-panel"

    ${pkgs.coreutils}/bin/mkdir -p "$STATE_DIR"
    exec 9>"$LOCK_FILE"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0

    if ! ${pkgs.systemd}/bin/systemctl --user is-active "$SERVICE" >/dev/null 2>&1; then
      exit 0
    fi

    WINDOW_COUNT="$($EWW --no-daemonize --config "$CONFIG" active-windows 2>/dev/null | ${pkgs.gnugrep}/bin/grep -Ec ': monitoring-panel-(overlay|docked)$' || true)"
    WINDOW_COUNT="''${WINDOW_COUNT:-0}"
    if [[ "$WINDOW_COUNT" -gt 1 ]]; then
      echo "health-guard: detected $WINDOW_COUNT monitoring panel windows; restarting $SERVICE" \
        | ${pkgs.systemd}/bin/systemd-cat -t eww-monitoring-panel-health-guard
      ${pkgs.systemd}/bin/systemctl --user restart "$SERVICE"
      exit 0
    fi

    ERROR_COUNT="$(${pkgs.systemd}/bin/journalctl --user -u "$SERVICE" --since "$WINDOW" --no-pager 2>/dev/null \
      | ${pkgs.gnugrep}/bin/grep -c 'Failed to send success response from application thread' || true)"

    if [[ -z "$ERROR_COUNT" || "$ERROR_COUNT" -lt "$THRESHOLD" ]]; then
      exit 0
    fi

    NOW="$(${pkgs.coreutils}/bin/date +%s)"
    LAST_RESTART=0
    if [[ -f "$STAMP_FILE" ]]; then
      LAST_RESTART="$(${pkgs.coreutils}/bin/cat "$STAMP_FILE" 2>/dev/null || echo 0)"
    fi
    AGE=$((NOW - LAST_RESTART))

    if [[ "$AGE" -lt "$COOLDOWN_SECONDS" ]]; then
      echo "health-guard: threshold hit ($ERROR_COUNT) but cooldown active ($AGE < $COOLDOWN_SECONDS)" \
        | ${pkgs.systemd}/bin/systemd-cat -t eww-monitoring-panel-health-guard
      exit 0
    fi

    echo "$NOW" > "$STAMP_FILE"
    echo "health-guard: restarting $SERVICE after $ERROR_COUNT errors in window '$WINDOW'" \
      | ${pkgs.systemd}/bin/systemd-cat -t eww-monitoring-panel-health-guard
    ${pkgs.systemd}/bin/systemctl --user restart "$SERVICE"
  '';

  monitoringPanelSmokeTestScript = pkgs.writeShellScriptBin "monitoring-panel-smoke-test" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    DURATION="''${1:-60}"
    EWW="${pkgs.eww}/bin/eww"
    CONFIG="$HOME/.config/eww-monitoring-panel"
    SERVICE="eww-monitoring-panel.service"

    count_windows() {
      local windows count
      windows="$($EWW --no-daemonize --config "$CONFIG" active-windows 2>/dev/null || true)"
      if [[ -z "$windows" ]]; then
        echo 0
        return
      fi
      echo "$windows" | ${pkgs.gnugrep}/bin/grep -Ec ': monitoring-panel-(overlay|docked)$' || true
    }

    assert_single_window() {
      local label count
      label="$1"
      count="$(count_windows)"
      if [[ "$count" -ne 1 ]]; then
        echo "Smoke test failed ($label): expected 1 monitoring panel window, got $count" >&2
        $EWW --no-daemonize --config "$CONFIG" active-windows 2>/dev/null || true
        exit 1
      fi
    }

    wait_for_single_window() {
      local label attempts count
      label="$1"
      attempts=0
      while [[ "$attempts" -lt 20 ]]; do
        count="$(count_windows)"
        if [[ "$count" -eq 1 ]]; then
          return 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.4
        attempts=$((attempts + 1))
      done
      echo "Smoke test timeout ($label): panel never stabilized to one window" >&2
      $EWW --no-daemonize --config "$CONFIG" active-windows 2>/dev/null || true
      return 1
    }

    ${pkgs.systemd}/bin/systemctl --user start "$SERVICE"
    wait_for_single_window "initial stabilization"
    assert_single_window "initial"

    toggle-panel-dock-mode >/dev/null 2>&1 || true
    wait_for_single_window "after first dock toggle"
    assert_single_window "after first dock toggle"

    toggle-panel-dock-mode >/dev/null 2>&1 || true
    wait_for_single_window "after second dock toggle"
    assert_single_window "after second dock toggle"

    # Rapid action stress: run multiple dock toggles and reconcile quickly.
    for _i in 1 2 3; do
      toggle-panel-dock-mode >/dev/null 2>&1 || true
      wait_for_single_window "after stress cycle $_i"
      assert_single_window "after stress cycle $_i"
    done

    monitor-panel-tab 1 >/dev/null 2>&1 || true
    refresh-projects-data >/dev/null 2>&1 || true
    ${pkgs.coreutils}/bin/sleep 2
    assert_single_window "after projects refresh"

    START="$(${pkgs.coreutils}/bin/date --iso-8601=seconds)"
    ${pkgs.coreutils}/bin/sleep "$DURATION"
    ERROR_COUNT="$(${pkgs.systemd}/bin/journalctl --user -u "$SERVICE" --since "$START" --no-pager 2>/dev/null \
      | ${pkgs.gnugrep}/bin/grep -c 'Failed to send success response from application thread' || true)"

    if [[ -n "$ERROR_COUNT" && "$ERROR_COUNT" -gt 0 ]]; then
      echo "Smoke test failed: found $ERROR_COUNT channel-closed errors in $DURATION seconds" >&2
      exit 1
    fi

    echo "Smoke test passed: single-window invariant holds and no channel-closed errors in $DURATION seconds."
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
    if ! $TIMEOUT 2s $EWW --no-daemonize --config "$CONFIG" ping >/dev/null 2>&1; then
      exit 0
    fi

    # Run sequentially with --kill-after to prevent orphans from rapid tab switching
    $TIMEOUT --kill-after=1s 2s $EWW --no-daemonize --config "$CONFIG" update current_view_index="$INDEX" || true

    # Refresh projects payload when entering Projects tab.
    if [[ "$INDEX" == "1" ]]; then
      ${refreshProjectsDataScript}/bin/refresh-projects-data >/dev/null 2>&1 &
    fi
  '';

  # Wrapper script: Get current monitoring panel view index
  # Usage: monitor-panel-get-view
  # Returns: 0-5 (or empty if panel not running)
  # Used by Sway keybindings for conditional routing (e.g., projects tab-specific actions)
  monitorPanelGetViewScript = pkgs.writeShellScriptBin "monitor-panel-get-view" ''
    #!${pkgs.bash}/bin/bash
    # Get current monitoring panel view index
    # Returns: 0=windows, 1=projects, 2=apps, 3=health, 4=events, 5=traces

    ${pkgs.eww}/bin/eww --no-daemonize --config "$HOME/.config/eww-monitoring-panel" get current_view_index 2>/dev/null || echo "-1"
  '';

  # Wrapper script: Check if current view is projects tab
  # Usage: monitor-panel-is-projects && do_something
  # Exit code: 0 if on projects tab, 1 otherwise
  # Simplifies Sway keybinding conditionals
  monitorPanelIsProjectsScript = pkgs.writeShellScriptBin "monitor-panel-is-projects" ''
    #!${pkgs.bash}/bin/bash
    # Check if monitoring panel is on projects tab (index 1)
    # Exit code: 0 = on projects tab, 1 = not on projects tab

    VIEW=$(${pkgs.eww}/bin/eww --no-daemonize --config "$HOME/.config/eww-monitoring-panel" get current_view_index 2>/dev/null)
    [ "$VIEW" = "1" ]
  '';

  # Feature 094: Project CRUD handler wrapper (T037)
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
    EWW_CMD="${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel"

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
          # Feature 125: exit-monitor-mode removed (focus mode replaced by dock mode)
        fi
        ;;
    esac
  '';

  # Feature 099 UX2: Projects tab keyboard navigation script
  handleKeyScript = pkgs.writeShellScript "monitoring-panel-keyhandler" ''
    KEY="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel"
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
  inherit monitoringDataScript projectsDataStreamScript dockModeStreamScript
          wrapperScript toggleScript toggleDockModeScript
          refreshProjectsDataScript monitoringPanelHealthGuardScript monitoringPanelSmokeTestScript
          monitorPanelTabScript monitorPanelGetViewScript monitorPanelIsProjectsScript
          swayNCToggleScript restartServiceScript monitorPanelNavScript handleKeyScript;
}
