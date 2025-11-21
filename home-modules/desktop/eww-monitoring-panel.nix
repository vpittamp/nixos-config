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

  # Python with required packages for both modes (one-shot and streaming)
  # pyxdg required for XDG icon theme lookup (resolves icon names like "firefox" to paths)
  pythonForBackend = pkgs.python3.withPackages (ps: [ ps.i3ipc ps.pyxdg ]);

  # Python backend script for monitoring data
  # Supports both one-shot mode (no args) and stream mode (--listen)
  # Version: 2025-11-20-v5 (use pythonWithPackages correctly)
  monitoringDataScript = pkgs.writeShellScriptBin "monitoring-data-backend" ''
    #!${pkgs.bash}/bin/bash
    # Version: 2025-11-20-v5

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
  toggleFocusScript = pkgs.writeShellScriptBin "toggle-panel-focus" ''
    #!${pkgs.bash}/bin/bash
    # Feature 086: Enter monitoring focus mode
    PANEL_APP_ID="eww-monitoring-panel"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Check if panel is visible first
    if ! $EWW_CMD active-windows | ${pkgs.gnugrep}/bin/grep -q "monitoring-panel"; then
      echo "Panel not visible - use Mod+M to show it first"
      exit 0
    fi

    # Focus the panel window
    ${pkgs.sway}/bin/swaymsg "[app_id=\"$PANEL_APP_ID\"] focus" 2>/dev/null

    # Update eww variable to show focus indicator
    $EWW_CMD update panel_focused=true

    # Reset selection index
    $EWW_CMD update selected_index=0

    # Enter Sway monitoring mode (captures all keys)
    ${pkgs.sway}/bin/swaymsg 'mode "📊 Monitor"'
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

  # Feature 086: Navigation script for monitoring panel
  monitorPanelNavScript = pkgs.writeShellScriptBin "monitor-panel-nav" ''
    #!${pkgs.bash}/bin/bash
    # Feature 086: Handle navigation within monitoring panel
    ACTION="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get current state
    current_index=$($EWW_CMD get selected_index 2>/dev/null || echo "-1")
    current_view=$($EWW_CMD get current_view 2>/dev/null || echo "windows")

    # Get max items based on current view (simplified - expand later)
    max_items=10  # Placeholder - would need to query actual data

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
        # When select is pressed, set selected_window_id based on current selection
        # This would need actual window data - placeholder for now
        echo "Select action at index $current_index" | ${pkgs.systemd}/bin/systemd-cat -t monitor-panel-nav
        # For now, just log - will expand when we have window list data
        ;;
      back)
        # Clear selection or go back in detail view
        $EWW_CMD update selected_window_id=0
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
    ];

    # Eww Yuck widget configuration (T009-T014)
    # Version: v8-focusable-shadow (Build: 2025-11-20-17:10)
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

      ;; Current view state (windows, projects, apps, health)
      (defvar current_view "windows")

      ;; Selected window ID for detail view (0 = none selected)
      (defvar selected_window_id 0)

      ;; Feature 086: Panel focus state (updated by toggle-panel-focus script)
      ;; When true, panel has keyboard focus and shows visual indicator
      (defvar panel_focused false)

      ;; Feature 086: Selected index for keyboard navigation (-1 = none)
      ;; Updated by j/k or up/down in monitoring mode
      (defvar selected_index -1)

      ;; Event-driven state variable (updated by daemon publisher)
      (defvar panel_state "{}")


      ;; Main monitoring panel window - Sidebar layout
      ;; Non-focusable overlay: stays visible but allows interaction with apps underneath
      ;; Tab switching via global Sway keybindings (Alt+1-4) since widget doesn't capture input
      ;; Use output name directly since monitor indices vary by platform
      (defwindow monitoring-panel
        :monitor "${primaryOutput}"
        :geometry (geometry
          :anchor "right center"
          :x "0px"
          :y "0px"
          :width "450px"
          :height "1000px")
        :namespace "eww-monitoring-panel"
        :stacking "overlay"
        :focusable "ondemand"
        :exclusive false
        :windowtype "normal"
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
            (button
              :class "tab ''${current_view == 'windows' ? 'active' : ""}"
              :onclick "eww update current_view=windows"
              :tooltip "Windows (Alt+1)"
              "󰖯")
            (button
              :class "tab ''${current_view == 'projects' ? 'active' : ""}"
              :onclick "eww update current_view=projects"
              :tooltip "Projects (Alt+2)"
              "󱂬")
            (button
              :class "tab ''${current_view == 'apps' ? 'active' : ""}"
              :onclick "eww update current_view=apps"
              :tooltip "Apps (Alt+3)"
              "󰀻")
            (button
              :class "tab ''${current_view == 'health' ? 'active' : ""}"
              :onclick "eww update current_view=health"
              :tooltip "Health (Alt+4)"
              "")
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
      (defwidget panel-body []
        (box
          :class "panel-body"
          :orientation "v"
          :vexpand true
          ;; Stack layout - only show one view at a time, each taking full height
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
            (health-view))))

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

      ;; Compact window widget for sidebar - Single line with badges
      ;; Click to show detail view (stores window ID)
      (defwidget window-widget [window]
        (eventbox
          :onclick "eww --config $HOME/.config/eww-monitoring-panel update selected_window_id=''${window.id}"
          :cursor "pointer"
          (box
            :class "window ''${window.scope == 'scoped' ? 'scoped-window' : 'global-window'} ''${window.state_classes} ''${strlength(window.icon_path) > 0 ? 'has-icon' : 'no-icon'}"
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
                :visible "''${window.is_pwa ?: false}")))))

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

      ;; Health View - System diagnostics
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
            ;; Health cards
            (box
              :class "health-cards"
              :orientation "v"
              :space-evenly false
              ;; Daemon status
              (health-card
                :title "Daemon Status"
                :value "''${health_data.health.daemon_status ?: 'unknown'}"
                :status {health_data.health.daemon_status == "healthy" ? "ok" : "error"})
              ;; Connection status
              (health-card
                :title "Sway IPC"
                :value "''${health_data.health.sway_ipc_connected ?: false ? 'Connected' : 'Disconnected'}"
                :status {health_data.health.sway_ipc_connected ?: false ? "ok" : "error"})
              ;; Counts
              (health-card
                :title "Windows"
                :value "''${health_data.health.window_count ?: 0}"
                :status "ok")
              (health-card
                :title "Workspaces"
                :value "''${health_data.health.workspace_count ?: 0}"
                :status "ok")
              (health-card
                :title "Projects"
                :value "''${health_data.health.project_count ?: 0}"
                :status "ok")
              (health-card
                :title "Monitors"
                :value "''${health_data.health.monitor_count ?: 0}"
                :status "ok")))))

      (defwidget health-card [title value status]
        (box
          :class "health-card health-''${status}"
          :orientation "h"
          :space-evenly false
          (label
            :class "health-card-title"
            :halign "start"
            :hexpand true
            :text title)
          (label
            :class "health-card-value"
            :halign "end"
            :text value)))

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

      /* Panel Container - Sidebar Style with rounded corners and transparency */
      .panel-container {
        background-color: rgba(30, 30, 46, 0.85);
        border-radius: 12px;
        padding: 8px;
        margin: 8px;
        border: 2px solid rgba(137, 180, 250, 0.1);
        transition: all 200ms ease-in-out;
      }

      /* Feature 086: Focused state with glowing border effect */
      .panel-container.focused {
        border: 2px solid ${mocha.mauve};
        box-shadow: 0 0 20px rgba(203, 166, 247, 0.4),
                    0 0 40px rgba(203, 166, 247, 0.2),
                    inset 0 0 15px rgba(203, 166, 247, 0.05);
        background-color: rgba(30, 30, 46, 0.95);
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
        background-color: ${mocha.mantle};
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
        background-color: ${mocha.surface0};
        color: ${mocha.subtext0};
        border: 1px solid ${mocha.overlay0};
        border-radius: 6px;
      }

      .tab:hover {
        background-color: ${mocha.surface1};
        color: ${mocha.text};
        border-color: ${mocha.overlay0};
      }

      .tab.active {
        background-color: ${mocha.blue};
        color: ${mocha.base};
        border-color: ${mocha.blue};
        font-weight: bold;
      }

      /* Panel Body - Compact */
      .panel-body {
        background-color: ${mocha.base};
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
        background-color: ${mocha.surface0};
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
        background-color: ${mocha.base};
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
        background-color: ${mocha.mantle};
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
        background-color: ${mocha.surface0};
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
        background-color: ${mocha.surface0};
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
        background-color: ${mocha.surface0};
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

      /* Window Detail View Styles */
      .detail-view {
        background-color: ${mocha.base};
        padding: 8px;
      }

      .detail-header {
        background-color: ${mocha.surface0};
        border-radius: 8px;
        padding: 8px 12px;
        margin-bottom: 8px;
      }

      .detail-back-btn {
        font-size: 12px;
        padding: 6px 12px;
        background-color: ${mocha.surface1};
        color: ${mocha.text};
        border: 1px solid ${mocha.overlay0};
        border-radius: 4px;
      }

      .detail-back-btn:hover {
        background-color: ${mocha.blue};
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
        background-color: ${mocha.surface0};
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
        background-color: ${mocha.surface0};
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
        Restart = "on-failure";
        RestartSec = "3s";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
