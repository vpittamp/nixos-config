{ monitoringDataScript, pulsePhaseScript, ai_sessions_data_path ? "$XDG_RUNTIME_DIR/otel-ai-monitor.pipe", ... }:

''
  ;; CRITICAL: Define current_view_index BEFORE defpolls that use :run-while
  ;; Otherwise :run-while conditions don't work and all polls run continuously
  (defvar current_view_index 0)  ;; Default to Windows tab (tabs 2,3,4,5,6 disabled)

  ;; Deflisten: Windows view data (event-driven with 5s heartbeat)
  ;; Uses --listen mode for instant updates on Sway events + inotify for badges
  ;; Much lower CPU than defpoll (no Python startup overhead every poll)
  (deflisten monitoring_data
    :initial "{\"status\":\"connecting\",\"projects\":[],\"project_count\":0,\"monitor_count\":0,\"workspace_count\":0,\"window_count\":0,\"timestamp\":0,\"timestamp_friendly\":\"Initializing...\",\"error\":null}"
    `${monitoringDataScript}/bin/monitoring-data-backend --listen`)

  ;; Feature 123: AI sessions data via OpenTelemetry (same source as eww-top-bar)
  ;; Used to show pulsating indicator on windows running AI assistants
  ;; Falls back to empty state if pipe doesn't exist
  (deflisten ai_sessions_data
    :initial "{\"type\":\"session_list\",\"sessions\":[],\"timestamp\":0,\"has_working\":false}"
    `cat ${ai_sessions_data_path} 2>/dev/null || echo '{\"type\":\"error\",\"error\":\"pipe_missing\",\"sessions\":[],\"timestamp\":0,\"has_working\":false}'`)

  ;; Defpoll: Projects view data (10s refresh - slowed from 5s for CPU savings)
  ;; Only runs when Projects tab is active (index 1)
  (defpoll projects_data
    :interval "10s"
    :run-while {current_view_index == 1}
    :initial "{\"status\":\"loading\",\"projects\":[],\"project_count\":0,\"active_project\":null}"
    `${monitoringDataScript}/bin/monitoring-data-backend --mode projects`)

  ;; Defpoll: Apps view data - DISABLED for CPU savings
  ;; Tab 2 is hidden, so this poll never needs to run
  (defpoll apps_data
    :interval "5s"
    :run-while false
    :initial "{\"status\":\"disabled\",\"apps\":[],\"app_count\":0}"
    `echo '{}'`)

  ;; Defpoll: Health view data - DISABLED for CPU savings
  ;; Tab 3 is hidden, so this poll never needs to run
  (defpoll health_data
    :interval "30s"
    :run-while false
    :initial "{\"status\":\"disabled\",\"health\":{}}"
    `echo '{\"status\":\"disabled\",\"health\":{}}'`)

  ;; Feature 101: Defpoll: Window traces view data - DISABLED for CPU savings
  ;; Tab 5 is hidden, so this poll never needs to run
  (defpoll traces_data
    :interval "2s"
    :run-while false
    :initial "{\"status\":\"disabled\",\"traces\":[],\"trace_count\":0,\"active_count\":0,\"stopped_count\":0}"
    `echo '{\"status\":\"disabled\",\"traces\":[],\"trace_count\":0,\"active_count\":0,\"stopped_count\":0}'`)

  ;; Feature 110: Pulsating animation phase
  ;; Animation runs via opacity transitions toggled by this variable
  (defpoll pulse_phase
    :interval "500ms"
    :run-while {monitoring_data.has_working_badge ?: false}
    :initial "0"
    `${pulsePhaseScript}/bin/eww-monitoring-panel-pulse-phase`)

  ;; Feature 092: Defpoll: Sway event log - DISABLED for CPU savings
  ;; Tab 4 is hidden, so this poll never needs to run
  (defpoll events_data
    :interval "2s"
    :run-while false
    :initial "{\"status\":\"disabled\",\"events\":[],\"event_count\":0,\"daemon_available\":false,\"ipc_connected\":false,\"timestamp\":0,\"timestamp_friendly\":\"Disabled\"}"
    `echo '{}'`)

  ;; Feature 094 T039: Form validation state
  ;; Changed from deflisten to defvar - validation is rarely used and causes process issues
  ;; Validation handled via explicit update commands when forms are opened
  (defvar validation_state "{\"valid\":true,\"editing\":false,\"errors\":{},\"warnings\":{},\"timestamp\":\"\"}")

  ;; Feature 116: Defpoll: Device state - DISABLED for CPU savings
  ;; Tab 6 is hidden, so this poll never needs to run
  (defpoll devices_state
    :interval "2s"
    :run-while false
    :initial "{\"volume\":{\"volume\":50,\"muted\":false,\"icon\":\"󰕾\",\"current_device\":\"Unknown\"},\"bluetooth\":{\"enabled\":false,\"scanning\":false,\"devices\":[]},\"brightness\":{\"display\":50,\"keyboard\":0},\"battery\":{\"percentage\":100,\"state\":\"full\",\"icon\":\"󰁹\",\"level\":\"normal\",\"time_remaining\":\"\"},\"thermal\":{\"cpu_temp\":0,\"level\":\"normal\",\"icon\":\"󰔏\"},\"network\":{\"tailscale_connected\":false,\"wifi_connected\":false},\"hardware\":{\"has_battery\":false,\"has_brightness\":false,\"has_keyboard_backlight\":false,\"has_bluetooth\":true,\"has_power_profiles\":false,\"has_thermal_sensors\":true},\"power_profile\":{\"current\":\"balanced\",\"available\":[],\"icon\":\"󰾅\"}}"
    `echo '{}'`)

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

  ;; Feature 125: Panel dock mode state (toggled by Mod+Shift+M)
  ;; When false, panel floats over windows (overlay mode)
  ;; When true (default), panel reserves screen space (docked mode with exclusive zone)
  ;; Read from state file - no external 'eww update' needed (avoids daemon race)
  (defpoll panel_dock_mode :interval "2s"
    :initial "true"
    "MODE=$(cat $HOME/.local/state/eww-monitoring-panel/dock-mode 2>/dev/null); [[ \"$MODE\" == \"docked\" ]] && echo true || echo false")

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

  ;; Panel transparency control (10-100, default 100% = fully opaque)
  ;; Adjustable via slider in header - persists across tabs
  (defvar panel_opacity 100)

  ;; Feature 092: Event filter state (all enabled by default)
  (defvar filter_window_new true)
  (defvar filter_window_close true)
  (defvar filter_window_focus true)
  (defvar filter_window_move true)
  (defvar filter_window_floating true)
  (defvar filter_window_fullscreen_mode true)
  (defvar filter_window_title true)
  (defvar filter_window_mark true)
  (defvar filter_window_urgent true)
  (defvar filter_window_blur true)
  (defvar filter_workspace_focus true)
  (defvar filter_workspace_init true)
  (defvar filter_workspace_empty true)
  (defvar filter_workspace_move true)
  (defvar filter_workspace_rename true)
  (defvar filter_workspace_urgent true)
  (defvar filter_workspace_reload true)
  (defvar filter_output_connected true)
  (defvar filter_output_disconnected true)
  (defvar filter_output_profile_changed true)
  (defvar filter_output_unspecified true)
  (defvar filter_binding_run true)
  (defvar filter_mode_change true)
  (defvar filter_shutdown_exit true)
  (defvar filter_tick_manual true)

  ;; Feature 102: i3pm internal event filters (T014)
  (defvar filter_i3pm_project_switch true)
  (defvar filter_i3pm_project_clear true)
  (defvar filter_i3pm_visibility_hidden true)
  (defvar filter_i3pm_visibility_shown true)
  (defvar filter_i3pm_scratchpad_move true)
  (defvar filter_i3pm_scratchpad_show true)
  (defvar filter_i3pm_launch_intent true)
  (defvar filter_i3pm_launch_queued true)
  (defvar filter_i3pm_launch_complete true)
  (defvar filter_i3pm_launch_failed true)
  (defvar filter_i3pm_state_cached true)
  (defvar filter_i3pm_state_restored true)
  (defvar filter_i3pm_command_queued true)
  (defvar filter_i3pm_command_executed true)
  (defvar filter_i3pm_command_result true)
  (defvar filter_i3pm_command_batch true)
  (defvar filter_i3pm_trace_started true)
  (defvar filter_i3pm_trace_stopped true)
  (defvar filter_i3pm_trace_event true)

  (defvar filter_panel_expanded false)
  (defvar events_sort_mode "time")
  (defvar hover_project_name "")
  (defvar hover_app_name "")
  (defvar copied_project_name "")
  (defvar hover_worktree_name "")
  (defvar json_hover_project "")
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
  (defvar edit_form_error "")
  (defvar project_creating false)
  (defvar create_form_name "")
  (defvar create_form_display_name "")
  (defvar create_form_icon "📦")
  (defvar create_form_working_dir "")
  (defvar create_form_scope "scoped")
  (defvar create_form_remote_enabled false)
  (defvar create_form_remote_host "")
  (defvar create_form_remote_user "")
  (defvar create_form_remote_dir "")
  (defvar create_form_remote_port "22")
  (defvar create_form_error "")
  (defvar app_creating false)
  (defvar create_app_type "regular")
  (defvar create_app_name "")
  (defvar create_app_display_name "")
  (defvar create_app_command "")
  (defvar create_app_parameters "")
  (defvar create_app_expected_class "")
  (defvar create_app_scope "scoped")
  (defvar create_app_workspace "1")
  (defvar create_app_monitor_role "")
  (defvar create_app_icon "")
  (defvar create_app_floating false)
  (defvar create_app_floating_size "")
  (defvar create_app_start_url "")
  (defvar create_app_scope_url "")
  (defvar create_app_error "")
  (defvar create_app_ulid_result "")
  (defvar worktree_creating false)
  (defvar worktree_form_description "")
  (defvar worktree_form_branch_name "")
  (defvar worktree_form_path "")
  (defvar worktree_form_parent_project "")
  (defvar worktree_form_repo_path "")
  (defvar worktree_form_speckit true)
  (defvar worktree_form_agent "claude")
  (defvar worktree_delete_branch "")
  (defvar worktree_delete_is_dirty false)
  (defvar worktree_delete_confirm "")
  (defvar worktree_delete_dialog_visible false)
  (defvar worktree_delete_name "")
  (defvar expanded_projects "all")
  (defvar project_filter "")
  (defvar project_selected_index -1)
  (defvar project_selected_name "")
  (defvar projects_all_expanded true)
  (defvar project_deleting false)
  (defvar delete_project_name "")
  (defvar delete_project_display_name "")
  (defvar delete_project_has_worktrees false)
  (defvar delete_force false)
  (defvar delete_error "")
  (defvar delete_success_message "")
  (defvar app_deleting false)
  (defvar delete_app_name "")
  (defvar delete_app_display_name "")
  (defvar delete_app_is_pwa false)
  (defvar delete_app_ulid "")
  (defvar delete_app_error "")
  (defvar save_in_progress false)
  (defvar success_notification "")
  (defvar success_notification_visible false)
  (defvar error_notification "")
  (defvar error_notification_visible false)
  (defvar warning_notification "")
  (defvar warning_notification_visible false)
  (defvar conflict_dialog_visible false)
  (defvar conflict_file_content "")
  (defvar conflict_ui_content "")
  (defvar conflict_project_name "")
  (defvar editing_app_name "")
  (defvar edit_display_name "")
  (defvar edit_workspace "")
  (defvar edit_icon "")
  (defvar edit_start_url "")
  (defvar expanded_trace_id "")
  (defvar trace_events "[]")
  (defvar trace_events_loading false)
  (defvar copied_trace_id "")
  (defvar highlight_event_id "")
  (defvar highlight_trace_id "")
  (defvar navigate_to_tab "")
  (defvar template_dropdown_open false)
  (defvar trace_templates "[{\"id\":\"debug-app-launch\",\"name\":\"Debug App Launch\",\"icon\":\"󰘳\",\"description\":\"Pre-launch trace for debugging app startup\"},{\"id\":\"debug-project-switch\",\"name\":\"Debug Project Switch\",\"icon\":\"󰓩\",\"description\":\"Trace all scoped windows during project switch\"},{\"id\":\"debug-focus-chain\",\"name\":\"Debug Focus Chain\",\"icon\":\"󰋴\",\"description\":\"Track focus and blur events for the currently focused window\"}]")
  (defvar spinner_frame "⠋")
''
