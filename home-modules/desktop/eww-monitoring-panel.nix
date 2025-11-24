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
      (defvar filter_workspace_focus true)
      (defvar filter_workspace_init true)
      (defvar filter_workspace_empty true)
      (defvar filter_workspace_move true)
      (defvar filter_workspace_rename true)
      (defvar filter_workspace_urgent true)
      (defvar filter_workspace_reload true)
      (defvar filter_output_unspecified true)
      (defvar filter_binding_run true)
      (defvar filter_mode_change true)
      (defvar filter_shutdown_exit true)
      (defvar filter_tick_manual true)

      ;; Filter panel visibility (false = collapsed, true = expanded)
      (defvar filter_panel_expanded false)


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
            (panel-footer))))

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
        (box
          :class "windows-view-container"
          :orientation "v"
          :vexpand true
          ;; Show detail view when window is selected
          (box
            :visible {selected_window_id != 0}
            :vexpand true
            (window-detail-view))
          ;; Show list view when no window is selected
          (scroll
            :vscroll true
            :hscroll false
            :vexpand true
            :visible {selected_window_id == 0}
            (box
              :class "content-container"
              :orientation "v"
              :space-evenly false
              ; Show error state when status is "error"
              (box
                :visible "''${monitoring_data.status == 'error'}"
                (error-state))
              ; Show empty state when no windows and no error
              (box
                :visible "''${monitoring_data.status != 'error' && (monitoring_data.window_count ?: 0) == 0}"
                (empty-state))
              ; Show projects when no error and has windows
              (box
                :visible "''${monitoring_data.status != 'error' && (monitoring_data.window_count ?: 0) > 0}"
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
                    :limit-width 25
                    :truncate true)
                  (label
                    :class "window-title"
                    :halign "start"
                    :text "''${window.title ?: '#' + window.id}"
                    :limit-width 35
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
                    :visible "''${window.is_pwa ?: false}"))))
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
                    :onclick "${pkgs.writeShellScript "copy-json" ''
                      EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
                      # Copy JSON to clipboard
                      ${pkgs.coreutils}/bin/echo -n "$1" | ${pkgs.coreutils}/bin/base64 -d | ${pkgs.wl-clipboard}/bin/wl-copy
                      # Show visual feedback by setting copied state
                      $EWW_CMD update copied_window_id=$2
                      # Auto-reset after 2 seconds
                      (sleep 2 && $EWW_CMD update copied_window_id=0) &
                    ''} ''${window.json_base64} ''${window.id} &"
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
            ;; Error state
            (box
              :class "error-message"
              :visible {projects_data.status == "error"}
              (label :text "⚠ ''${projects_data.error ?: 'Unknown error'}"))
            ;; Project list
            (for project in {projects_data.projects ?: []}
              (project-card :project project)))))

      (defwidget project-card [project]
        (box
          :class "project-card ''${project.is_active ? 'active-project' : ""}"
          :orientation "v"
          :space-evenly false
          (box
            :class "project-card-header"
            :orientation "h"
            :space-evenly false
            (label
              :class "project-icon"
              :text "''${project.icon ?: '󱂬'}")
            (box
              :class "project-info"
              :orientation "v"
              :space-evenly false
              :hexpand true
              (label
                :class "project-card-name"
                :halign "start"
                :text "''${project.display_name ?: project.name}")
              (label
                :class "project-card-path"
                :halign "start"
                :text "''${project.directory}"))
            (label
              :class "active-indicator"
              :visible {project.is_active}
              :text "●"))))

      ;; Apps View - Application registry browser
      (defwidget apps-view []
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
              :visible {apps_data.status == "error"}
              (label :text "⚠ ''${apps_data.error ?: 'Unknown error'}"))
            ;; Apps list
            (for app in {apps_data.apps ?: []}
              (app-card :app app)))))

      (defwidget app-card [app]
        (box
          :class "app-card"
          :orientation "v"
          :space-evenly false
          (box
            :class "app-card-header"
            :orientation "h"
            :space-evenly false
            (label
              :class "app-icon"
              :text "''${app.scope == 'scoped' ? '󱂬' : '󰞇'}")
            (box
              :class "app-info"
              :orientation "v"
              :space-evenly false
              :hexpand true
              (label
                :class "app-card-name"
                :halign "start"
                :text "''${app.display_name ?: app.name}")
              (label
                :class "app-card-details"
                :halign "start"
                :text "WS ''${app.preferred_workspace ?: '?'} · ''${app.scope} · ''${app.running_instances ?: 0} running"))
            (label
              :class "app-running-indicator"
              :visible {app.running_instances > 0}
              :text "●"))))

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
          ;; Filter panel (collapsible)
          (box
            :class "filter-panel"
            :orientation "v"
            :space-evenly false
            :visible "''${events_data.status == 'ok'}"
            ;; Filter header (always visible)
            (eventbox
              :cursor "pointer"
              :onclick "eww --config $HOME/.config/eww-monitoring-panel update filter_panel_expanded=''${!filter_panel_expanded}"
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
                  :onclick "eww --config $HOME/.config/eww-monitoring-panel update filter_window_new=true filter_window_close=true filter_window_focus=true filter_window_move=true filter_window_floating=true filter_window_fullscreen_mode=true filter_window_title=true filter_window_mark=true filter_window_urgent=true filter_workspace_focus=true filter_workspace_init=true filter_workspace_empty=true filter_workspace_move=true filter_workspace_rename=true filter_workspace_urgent=true filter_workspace_reload=true filter_output_unspecified=true filter_binding_run=true filter_mode_change=true filter_shutdown_exit=true filter_tick_manual=true"
                  "Select All")
                (button
                  :class "filter-button"
                  :onclick "eww --config $HOME/.config/eww-monitoring-panel update filter_window_new=false filter_window_close=false filter_window_focus=false filter_window_move=false filter_window_floating=false filter_window_fullscreen_mode=false filter_window_title=false filter_window_mark=false filter_window_urgent=false filter_workspace_focus=false filter_workspace_init=false filter_workspace_empty=false filter_workspace_move=false filter_workspace_rename=false filter_workspace_urgent=false filter_workspace_reload=false filter_output_unspecified=false filter_binding_run=false filter_mode_change=false filter_shutdown_exit=false filter_tick_manual=false"
                  "Clear All"))
              ;; Window events category
              (box
                :class "filter-category-group"
                :orientation "v"
                :space-evenly false
                (label
                  :class "filter-category-title"
                  :halign "start"
                  :text "Window Events (9)")
                (box
                  :class "filter-checkboxes"
                  :orientation "h"
                  :space-evenly false
                  (filter-checkbox :label "new" :var "filter_window_new" :value filter_window_new)
                  (filter-checkbox :label "close" :var "filter_window_close" :value filter_window_close)
                  (filter-checkbox :label "focus" :var "filter_window_focus" :value filter_window_focus)
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
              ;; Output/Binding/Mode/System events
              (box
                :class "filter-category-group"
                :orientation "v"
                :space-evenly false
                (label
                  :class "filter-category-title"
                  :halign "start"
                  :text "Other Events (5)")
                (box
                  :class "filter-checkboxes"
                  :orientation "h"
                  :space-evenly false
                  (filter-checkbox :label "output" :var "filter_output_unspecified" :value filter_output_unspecified)
                  (filter-checkbox :label "binding" :var "filter_binding_run" :value filter_binding_run)
                  (filter-checkbox :label "mode" :var "filter_mode_change" :value filter_mode_change)
                  (filter-checkbox :label "shutdown" :var "filter_shutdown_exit" :value filter_shutdown_exit)
                  (filter-checkbox :label "tick" :var "filter_tick_manual" :value filter_tick_manual)))))
          ;; Error state
          (box
            :visible "''${events_data.status == 'error'}"
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
            :visible "''${events_data.status == 'ok' && events_data.event_count == 0}"
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
          ;; Events list (scroll container) with filtering
          (scroll
            :vscroll true
            :hscroll false
            :vexpand true
            :visible "''${events_data.status == 'ok' && events_data.event_count > 0}"
            (box
              :class "events-list"
              :orientation "v"
              :space-evenly false
              ;; Iterate through events with filter logic
              (for event in {events_data.events ?: []}
                (box
                  :visible {
                    event.event_type == "window::new" ? filter_window_new :
                    event.event_type == "window::close" ? filter_window_close :
                    event.event_type == "window::focus" ? filter_window_focus :
                    event.event_type == "window::move" ? filter_window_move :
                    event.event_type == "window::floating" ? filter_window_floating :
                    event.event_type == "window::fullscreen_mode" ? filter_window_fullscreen_mode :
                    event.event_type == "window::title" ? filter_window_title :
                    event.event_type == "window::mark" ? filter_window_mark :
                    event.event_type == "window::urgent" ? filter_window_urgent :
                    event.event_type == "workspace::focus" ? filter_workspace_focus :
                    event.event_type == "workspace::init" ? filter_workspace_init :
                    event.event_type == "workspace::empty" ? filter_workspace_empty :
                    event.event_type == "workspace::move" ? filter_workspace_move :
                    event.event_type == "workspace::rename" ? filter_workspace_rename :
                    event.event_type == "workspace::urgent" ? filter_workspace_urgent :
                    event.event_type == "workspace::reload" ? filter_workspace_reload :
                    event.event_type == "output::unspecified" ? filter_output_unspecified :
                    event.event_type == "binding::run" ? filter_binding_run :
                    event.event_type == "mode::change" ? filter_mode_change :
                    event.event_type == "shutdown::exit" ? filter_shutdown_exit :
                    event.event_type == "tick::manual" ? filter_tick_manual :
                    true
                  }
                  (event-card :event event)))))))

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
        all: unset;
      }

      window {
        background-color: transparent;
      }

      /* Panel Container - Sidebar Style with rounded corners and transparency */
      .panel-container {
        background-color: rgba(30, 30, 46, 0.50);
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
        animation: pulse 2s ease-in-out infinite;
      }

      @keyframes pulse {
        0% { opacity: 1; }
        50% { opacity: 0.7; }
        100% { opacity: 1; }
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
        background-color: rgba(49, 50, 68, 0.4);
        color: ${mocha.subtext0};
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
        /* transition not supported in GTK CSS */
      }

      .tab:hover {
        background-color: rgba(69, 71, 90, 0.5);
        color: ${mocha.text};
        border-color: ${mocha.overlay0};
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
      }

      .tab.active {
        background-color: rgba(137, 180, 250, 0.6);
        color: ${mocha.base};
        border-color: ${mocha.blue};
        font-weight: bold;
        box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
      }

      .tab.active:hover {
        background-color: rgba(137, 180, 250, 0.7);
        box-shadow: 0 0 12px rgba(137, 180, 250, 0.6);
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
        font-size: 20px;
        margin-right: 8px;
      }

      .project-info {
        margin-right: 8px;
      }

      .project-card-name {
        font-size: 13px;
        font-weight: bold;
        color: ${mocha.text};
        margin-bottom: 2px;
      }

      .project-card-path {
        font-size: 10px;
        color: ${mocha.subtext0};
      }

      .active-indicator {
        color: ${mocha.teal};
        font-size: 14px;
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
      }

      .window-title {
        font-size: 10px;
        color: ${mocha.subtext0};
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

      /* Feature 092: Event Filter Panel Styling */
      .filter-panel {
        background-color: ${mocha.mantle};
        border-radius: 8px;
        padding: 8px;
        margin: 8px 4px;
        border: 1px solid ${mocha.overlay0};
      }

      .filter-header {
        padding: 8px;
        background-color: ${mocha.surface0};
        border-radius: 6px;
        margin-bottom: 4px;
      }

      .filter-header:hover {
        background-color: ${mocha.surface1};
      }

      .filter-title {
        font-size: 12px;
        font-weight: 600;
        color: ${mocha.blue};
      }

      .filter-toggle {
        font-size: 10px;
        color: ${mocha.subtext0};
        margin-left: 8px;
      }

      .filter-controls {
        padding: 8px 4px;
      }

      .filter-global-controls {
        padding: 8px;
        margin-bottom: 12px;
      }

      .filter-button {
        background-color: ${mocha.surface0};
        color: ${mocha.text};
        border: 1px solid ${mocha.overlay0};
        border-radius: 4px;
        padding: 6px 12px;
        margin-right: 8px;
        font-size: 11px;
        font-weight: 500;
      }

      .filter-button:hover {
        background-color: ${mocha.surface1};
        border-color: ${mocha.blue};
      }

      .filter-category-group {
        background-color: ${mocha.base};
        border-radius: 6px;
        padding: 8px;
        margin-bottom: 8px;
        border: 1px solid ${mocha.surface0};
      }

      .filter-category-title {
        font-size: 11px;
        font-weight: 600;
        color: ${mocha.teal};
        margin-bottom: 8px;
        padding: 4px 0;
        border-bottom: 1px solid ${mocha.surface0};
      }

      .filter-checkboxes {
        padding: 4px 0;
      }

      .filter-checkbox-item {
        padding: 4px 8px;
        margin-right: 12px;
        border-radius: 4px;
        background-color: transparent;
      }

      .filter-checkbox-item:hover {
        background-color: ${mocha.surface0};
      }

      .filter-checkbox-icon {
        font-size: 14px;
        color: ${mocha.blue};
        margin-right: 4px;
      }

      .filter-checkbox-label {
        font-size: 10px;
        color: ${mocha.text};
        font-family: monospace;
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
