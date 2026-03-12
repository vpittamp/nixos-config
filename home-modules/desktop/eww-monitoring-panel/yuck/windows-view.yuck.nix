{ pkgs, focusWindowScript, focusAiSessionScript, focusActiveAiSessionScript, toggleAiSessionPinScript, toggleAiGroupCollapseScript, closeWorktreeScript, closeAllWindowsScript, closeWindowScript, toggleWindowsProjectExpandScript, toggleProjectContextScript, switchProjectScript, openRemoteSessionWindowScript, openLangfuseTraceScript, iconPaths, activeAiGroupMaxVisibleSessions ? 2, ... }:

''
  ;; Feature 138: Pinned active AI rail for quick session switching.
  ;; Rendered from main.yuck outside of windows-view scroll container.
  (defwidget active-ai-rail []
    (box
      :class "active-ai-rail-container"
      :visible {current_view_index == 0}
      :orientation "v"
      :space-evenly false
      :hexpand true
      :halign "fill"
      (revealer
        :reveal {ai_mru_switcher_visible && arraylength((monitoring_data.active_ai_sessions_mru ?: monitoring_data.active_ai_sessions ?: [])) > 0}
        :transition "slidedown"
        :duration "80ms"
        (box
          :class "active-ai-mru-switcher"
          :orientation "h"
          :space-evenly false
          :spacing 4
          (label :class "active-ai-mru-title" :text "Recent")
          (for session in {arraylength((monitoring_data.active_ai_sessions_mru ?: monitoring_data.active_ai_sessions ?: [])) <= 6 ? (monitoring_data.active_ai_sessions_mru ?: monitoring_data.active_ai_sessions ?: []) : jq((monitoring_data.active_ai_sessions_mru ?: monitoring_data.active_ai_sessions ?: []), ".[:6]")}
            (eventbox
              :cursor "pointer"
              :onclick "${focusActiveAiSessionScript}/bin/focus-active-ai-session-action \"''${session.session_key ?: ""}\" &"
              :tooltip {"Focus " + (session.display_project ?: session.project ?: "unknown")}
              (box
                :class {"active-ai-mru-chip"
                  + ((ai_sessions_selected_key == (session.session_key ?: "")) ? " selected" : "")
                  + ((session.is_current_window ?: false) ? " current-window" : "")}
                :orientation "h"
                :space-evenly false
                :spacing 3
                (image
                  :class "active-ai-chip-icon"
                  :path {(session.tool ?: "unknown") == "claude-code"
                    ? "${iconPaths.claude}"
                    : ((session.tool ?: "unknown") == "codex"
                      ? "${iconPaths.codex}"
                      : ((session.tool ?: "unknown") == "gemini"
                        ? "${iconPaths.gemini}"
                        : "${iconPaths.anthropic}"))}
                  :image-width 13
                  :image-height 13)
                (label
                  :class "active-ai-mru-chip-text"
                  :text {session.display_project ?: session.project ?: "unknown"}
                  :limit-width 14
                  :truncate true))))))
      (box
        :class "active-ai-rail"
        :orientation "v"
        :space-evenly false
        :spacing 5
        :hexpand true
        :halign "fill"
        (box
          :class "active-ai-group-header"
          :orientation "h"
          :space-evenly false
          :spacing 8
          (label :class "active-ai-rail-title" :text "Active AI")
          (label
            :class "active-ai-rail-total"
            :text {arraylength((monitoring_data.active_ai_sessions_mru ?: monitoring_data.active_ai_sessions ?: [])) + " sessions"}))
        (box
          :class "active-ai-group-list"
          :orientation "v"
          :space-evenly false
          :spacing 4
          :hexpand true
          :halign "fill"
          (for group in {jq((monitoring_data.active_ai_sessions_mru ?: monitoring_data.active_ai_sessions ?: []), "group_by(.display_project // .project // \"unknown\") | map({project:(.[0].display_project // .[0].project // \"unknown\"), sessions:.})")}
            (box
              :class "active-ai-group"
              :orientation "v"
              :space-evenly false
              :spacing 2
              :hexpand true
              :halign "fill"
              (eventbox
                :cursor "pointer"
                :onclick "${toggleAiGroupCollapseScript}/bin/toggle-ai-group-collapse-action \"''${group.project ?: "unknown"}\" &"
                :tooltip "Collapse/expand project AI sessions"
                (box
                  :class "active-ai-group-row"
                  :orientation "h"
                  :space-evenly false
                  :hexpand true
                  :halign "fill"
                  (label
                    :class "active-ai-group-chevron"
                    :text {jq(ai_group_collapsed_projects, ". | index(\"" + (group.project ?: "unknown") + "\") != null") ? "󰅂" : "󰅀"})
                  (label
                    :class "active-ai-group-project"
                    :text {group.project ?: "unknown"}
                    :limit-width 24
                    :truncate true)
                  (label
                    :class "active-ai-group-count"
                    :text {arraylength(group.sessions ?: [])})))
              (revealer
                :reveal {!jq(ai_group_collapsed_projects, ". | index(\"" + (group.project ?: "unknown") + "\") != null")}
                :transition "slidedown"
                :duration "120ms"
                (box
                  :class "active-ai-chip-list"
                  :orientation "h"
                  :space-evenly false
                  :spacing 4
                  :hexpand true
                  :halign "fill"
                  (for session in {arraylength(group.sessions ?: []) <= ${toString activeAiGroupMaxVisibleSessions} ? (group.sessions ?: []) : jq(group.sessions ?: [], ".[:${toString activeAiGroupMaxVisibleSessions}]")}
                    (box
                      :class "active-ai-chip-wrap"
                      :orientation "h"
                      :space-evenly false
                      :spacing 3
                      (eventbox
                        :cursor "pointer"
                        :onclick "${focusActiveAiSessionScript}/bin/focus-active-ai-session-action \"''${session.session_key ?: ""}\" &"
                        :tooltip {session.display_tool + " · " + (session.stage_label ?: session.otel_state ?: "idle") + " · " + (session.display_project ?: session.project ?: "unknown")
                          + ((session.stage_detail ?: "") != "" ? (" · " + (session.stage_detail ?: "")) : "")
                          + (((session.window_project ?: "") != "" && (session.window_project ?: "") != (session.display_project ?: session.project ?: "")) ? (" · via " + (session.window_project ?: "")) : "")
                          + " · " + ((session.execution_mode ?: "local") == "ssh" ? "remote" : "local")
                          + ((session.host_name ?: "") != "" ? ("@" + (session.host_name ?: "")) : "")
                          + ((session.native_session_id ?: "") != "" ? " · SID " + session.native_session_id : ((session.session_id ?: "") != "" ? " · SID " + session.session_id : ""))
                          + ((session.tmux_pane ?: "") != "" ? " · pane " + session.tmux_pane : ((session.display_target ?: "") != "" ? " · " + session.display_target : ""))
                          + ((session.confidence_level ?: "") != "" ? " · confidence " + session.confidence_level : "")
                          + ((session.output_unseen ?: session.review_pending ?: false) ? " · Unseen output" : "")
                          + ((session.stale ?: false) ? (" · stale " + (session.stale_age_seconds ?: 0) + "s") : "")
                          + " · Click to focus"}
                        (box
                          :class {"active-ai-chip " +
                            (session.stage_class ?: ("stage-" + (session.otel_state ?: "idle"))) + " " +
                            (session.stage_visual_state ?: "idle") +
                            ((session.pulse_working ?: false) ? " pulse-working" : "") +
                            ((session.output_unseen ?: session.review_pending ?: false) ? " review-pending" : "") +
                            ((session.tool ?: "unknown") == "claude-code" ? " tool-claude-code" : ((session.tool ?: "unknown") == "codex" ? " tool-codex" : ((session.tool ?: "unknown") == "gemini" ? " tool-gemini" : " tool-unknown"))) +
                            ((session.stale ?: false) ? " stale" : "") +
                            (((session.confidence_level ?: "") != "") ? (" confidence-" + (session.confidence_level ?: "")) : "") +
                            ((ai_sessions_selected_key == (session.session_key ?: "")) ? " selected" : "") +
                            ((session.is_current_window ?: false) ? " current-window" : "")}
                          :orientation "h"
                          :space-evenly false
                          :spacing 4
                          (image
                            :class "active-ai-chip-icon"
                            :path {(session.tool ?: "unknown") == "claude-code"
                              ? "${iconPaths.claude}"
                              : ((session.tool ?: "unknown") == "codex"
                                ? "${iconPaths.codex}"
                                : ((session.tool ?: "unknown") == "gemini"
                                  ? "${iconPaths.gemini}"
                                  : "${iconPaths.anthropic}"))}
                            :image-width 15
                            :image-height 15)
                          (label
                            :class "active-ai-chip-text"
                            :text {session.display_tool ?: session.tool ?: "AI"}
                            :limit-width 14
                            :truncate true)
                          (label
                            :class {"active-ai-chip-stage " + (session.stage_class ?: "stage-idle")}
                            :xalign 0.5
                            :text {session.stage_glyph ?: "·"})
                          (label
                            :class "active-ai-chip-marker current"
                            :visible {session.is_current_window ?: false}
                            :text "Now")
                          (label
                            :class "active-ai-chip-marker remote"
                            :visible {(session.execution_mode ?: "local") == "ssh"}
                            :text "SSH")
                          (label
                            :class "active-ai-chip-marker action"
                            :visible {session.needs_user_action ?: false}
                            :text "Action")
                          (label
                            :class "active-ai-chip-unread-dot"
                            :visible {session.output_unseen ?: session.review_pending ?: false}
                            :text "•")
                          (label
                            :class "active-ai-chip-marker unread"
                            :visible {session.output_unseen ?: session.review_pending ?: false}
                            :text "New")))
                      (eventbox
                        :cursor "pointer"
                        :onclick "${toggleAiSessionPinScript}/bin/toggle-ai-session-pin-action \"''${session.session_key ?: ""}\" &"
                        :tooltip {(session.pinned ?: false) ? "Unpin session" : "Pin session"}
                        (label
                          :class {"active-ai-pin-btn" + ((session.pinned ?: false) ? " pinned" : "")}
                          :text {(session.pinned ?: false) ? "󰐃" : "󰓎"}))))
                  (eventbox
                    :visible {arraylength(group.sessions ?: []) > ${toString activeAiGroupMaxVisibleSessions}}
                    :cursor "default"
                    :tooltip {jq(group.sessions ?: [], ".[${toString activeAiGroupMaxVisibleSessions}:] | map((.display_tool // .tool // \"AI\") + \" · \" + (.stage_label // .otel_state // \"Idle\")) | join(\"\\n\")")}
                    (box
                      :class "active-ai-overflow-chip"
                      :orientation "h"
                      :space-evenly false
                      :spacing 3
                      (label :class "active-ai-overflow-icon" :text "󰇘")
                      (label
                        :class "active-ai-overflow-text"
                        :text {"+''${arraylength(group.sessions ?: []) - ${toString activeAiGroupMaxVisibleSessions}}"})))))))
        (label
          :class "active-ai-empty-state"
          :visible {arraylength((monitoring_data.active_ai_sessions_mru ?: monitoring_data.active_ai_sessions ?: [])) == 0}
          :text "No active or unread sessions")
        (revealer
          :reveal {ai_sessions_selected_key != ""}
          :transition "slidedown"
          :duration "120ms"
          (box
            :class "active-ai-timeline"
            :orientation "v"
            :space-evenly false
            (for session in {(monitoring_data.active_ai_sessions_mru ?: monitoring_data.active_ai_sessions ?: [])}
              (box
                :visible {ai_sessions_selected_key == (session.session_key ?: "")}
                :orientation "v"
                :space-evenly false
                (label
                  :class "active-ai-timeline-title"
                  :text {(session.display_tool ?: session.tool ?: "AI") + " · " + (session.display_project ?: session.project ?: "unknown")}
                  :truncate true)
                (label
                  :class "active-ai-timeline-line"
                  :text {"Stage: " + (session.stage_label ?: session.otel_state ?: "idle") + ((session.stage_detail ?: "") != "" ? (" · " + (session.stage_detail ?: "")) : "")})
                (label
                  :class "active-ai-timeline-line"
                  :text {"Activity: " + ((session.is_streaming ?: false) ? "streaming" : ((session.pending_tools ?: 0) > 0 ? ("tools " + (session.pending_tools ?: 0)) : (session.activity_freshness ?: "fresh"))) + " · source " + (session.identity_source ?: "unknown")})
                (label
                  :class "active-ai-timeline-line"
                  :text {"Updated: " + (session.activity_age_label ?: "just now") + ((session.remote_source_stale ?: false) ? " · remote source stale" : "")})
                (label
                  :class "active-ai-timeline-line"
                  :text {"Target: " + ((session.display_target ?: "") != "" ? (session.display_target ?: "") : ("win " + (session.window_id ?: 0)))}
                  :truncate true)
                (label
                  :class "active-ai-timeline-line"
                  :text {((session.native_session_id ?: "") != "" ? ("SID " + (session.native_session_id ?: "")) : ((session.session_id ?: "") != "" ? ("SID " + (session.session_id ?: "")) : "SID n/a")) + ((session.updated_at ?: "") != "" ? (" · " + (session.updated_at ?: "")) : "")}
                  :truncate true)
                (label
                  :class "active-ai-timeline-line subtle"
                  :visible {(session.trace_id ?: "") != ""}
                  :text {"Trace: " + (session.trace_id ?: "")}
                  :truncate true)))))))))

  ;; Windows View - Project-based hierarchy with real-time updates
  ;; Shows detail view when a window is selected, otherwise shows list
  (defwidget windows-view []
    (box
      :orientation "v"
      :space-evenly false
      :vexpand true
      (active-ai-rail)
      (scroll
        :vscroll true
        :hscroll false
        :vexpand true
        (box
          :class "content-container windows-content-container"
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
            ; Show empty state when no projects and no error
            (box
              :visible {monitoring_data.status != "error" && arraylength(monitoring_data.projects ?: []) == 0}
              (empty-state))
            ; Show projects when no error and has projects
            (box
              :visible {monitoring_data.status != "error" && arraylength(monitoring_data.projects ?: []) > 0}
              :orientation "v"
              :space-evenly false
              ;; Action button row at top
              (box
                :class "windows-actions-row"
                :orientation "h"
                :space-evenly false
                :hexpand true
                :halign "end"
                :spacing 0
                (box :hexpand true)
                (eventbox
                  :onhoverlost {windows_bulk_actions_open ? "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update windows_bulk_actions_open=false" : ""}
                  (box
                    :class "windows-actions-menu-wrap"
                    :orientation "v"
                    :space-evenly false
                    :halign "end"
                    (eventbox
                      :cursor "pointer"
                      :onclick {windows_bulk_actions_open ? "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update windows_bulk_actions_open=false" : "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update windows_bulk_actions_open=true"}
                      :tooltip "Window actions"
                      (box
                        :class {"windows-actions-trigger" + (windows_bulk_actions_open ? " open" : "")}
                        :orientation "h"
                        :space-evenly false
                        :spacing 0
                        (label :class "windows-actions-trigger-icon" :text "󰇙")))
                    (revealer
                      :reveal {windows_bulk_actions_open}
                      :transition "slidedown"
                      :duration "100ms"
                      (box
                        :class "windows-actions-menu"
                        :orientation "v"
                        :space-evenly false
                        (eventbox
                          :cursor "pointer"
                          :onclick {windows_all_expanded ? "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update windows_expanded_projects='[]' windows_all_expanded=false windows_bulk_actions_open=false" : "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update windows_expanded_projects='all' windows_all_expanded=true windows_bulk_actions_open=false"}
                          :tooltip {windows_all_expanded ? "Collapse all worktrees" : "Expand all worktrees"}
                          (box
                            :class "windows-actions-menu-item"
                            :orientation "h"
                            :space-evenly false
                            :spacing 6
                            (label :class "windows-actions-menu-item-icon" :text {windows_all_expanded ? "󰅀" : "󰅂"})
                            (label :class "windows-actions-menu-item-text" :text {windows_all_expanded ? "Collapse All" : "Expand All"})))
                        (eventbox
                          :cursor "pointer"
                          :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update windows_bulk_actions_open=false; ${closeAllWindowsScript}/bin/close-all-windows-action &"
                          :tooltip "Close all scoped windows"
                          (box
                            :class "windows-actions-menu-item danger"
                            :orientation "h"
                            :space-evenly false
                            :spacing 6
                            (label :class "windows-actions-menu-item-icon" :text "󰅖")
                            (label :class "windows-actions-menu-item-text" :text "Close All"))))))))
              ;; Projects list
              (for project in {monitoring_data.projects ?: []}
                (project-widget :project project))))))))

  (defwidget project-widget [project]
    (box
      :class {"project " + (project.scope == "scoped" ? "scoped-project" : "global-project") + (project.is_active ? " project-active" : "") +
              ((project.remote_enabled ?: false) ? " project-ssh-active" : "")}
      :orientation "v"
      :space-evenly false
      (eventbox
        :onclick "${toggleWindowsProjectExpandScript}/bin/toggle-windows-project-expand ''${project.card_id ?: project.name} &"
        :onhover {"eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update hovered_project_key='" + (project.card_id ?: project.name) + "'"}
        :onhoverlost {hovered_project_key == (project.card_id ?: project.name) ? "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update hovered_project_key=" : ""}
        :cursor "pointer"
        :tooltip {(windows_expanded_projects == "all" || jq(windows_expanded_projects, ". | index(\"" + (project.card_id ?: project.name) + "\") != null")) ? "Click to collapse" : "Click to expand"}
        (box
          :class {"project-header" + ((project.remote_enabled ?: false) ? " project-header-ssh-active" : "")}
          :orientation "h"
          :space-evenly false
          (label
            :class "expand-icon"
            :text {(windows_expanded_projects == "all" || jq(windows_expanded_projects, ". | index(\"" + (project.card_id ?: project.name) + "\") != null")) ? "󰅀" : "󰅂"})
          (label
            :class {"project-name" + ((project.remote_enabled ?: false) ? " project-name-ssh-active" : "")}
            :limit-width 30
            :truncate true
            :tooltip {
              (project.remote_enabled ?: false)
              ? ("''${project.name}\nSSH Active: " + (project.remote_target ?: "") + ((project.remote_directory_display ?: "") != "" ? "\n" + (project.remote_directory_display ?: "") : ""))
              : "''${project.name}"
            }
            :text "''${project.scope == 'scoped' ? '󱂬' : '󰞇'} ''${project.name}")
          (label
            :class "active-indicator"
            :visible {project.is_active}
            :tooltip "Active project"
            :text "●")
          (label
            :class "project-variant-pill local"
            :visible {(project.variant ?: "") == "local" && (project.has_remote_variant ?: false)}
            :text "󰌽"
            :tooltip "Local project card")
          (label
            :class "project-variant-pill remote"
            :visible {(project.variant ?: "") == "ssh" || (project.remote_enabled ?: false)}
            :text "☁"
            :tooltip {"Remote: " + (project.remote_target ?: "") + ((project.remote_directory_display ?: "") != "" ? " • " + (project.remote_directory_display ?: "") : "")})
          (box
            :hexpand true
            :halign "end"
            :orientation "h"
            :space-evenly false
            (box
              :class {"project-action-rail" + (hovered_project_key == (project.card_id ?: project.name) ? " visible" : "")}
              :orientation "h"
              :space-evenly false
              :spacing 2
              (eventbox
                :cursor "pointer"
                :onclick "${closeWorktreeScript}/bin/close-worktree-action ''${project.scope == 'global' ? 'global' : project.name} ''${project.execution_mode} ''${project.connection_key} &"
                :tooltip "Close all windows in this project"
                (label
                  :class "project-action-btn project-action-close"
                  :text "󰅖"))))))
      (revealer
        :reveal {windows_expanded_projects == "all" || jq(windows_expanded_projects, ". | index(\"" + (project.card_id ?: project.name) + "\") != null")}
        :transition "slidedown"
        :duration "150ms"
        (box
          :class "windows-container"
          :orientation "v"
          :space-evenly false
          (for window in {project.windows ?: []}
            (window-widget :window window))))))

  (defwidget window-widget [window]
    (eventbox
      :cursor "default"
      :onhover "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update hovered_window_id=''${window.id}"
      :onhoverlost {hovered_window_id == window.id ? "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update hovered_window_id=0" : ""}
      (box
        :class "window-container"
        :orientation "v"
        :hexpand true
        :space-evenly false
        (box
          :class "window-row ''${window.state_classes}"
          :orientation "h"
          :hexpand true
          :halign "fill"
          :spacing 4
          :space-evenly false
          (box
            :class "window-main"
            :hexpand true
            :halign "fill"
            (eventbox
              :onclick {(window.is_remote_session ?: false)
                ? "${openRemoteSessionWindowScript}/bin/open-remote-session-window-action ''${window.project} ''${window.remote_session_name} ''${window.execution_mode} &"
                : "${focusWindowScript}/bin/focus-window-action ''${window.project} ''${window.id} ''${window.execution_mode} &"}
              :cursor "pointer"
              :hexpand true
              :halign "fill"
              (box
                :class "window"
                :orientation "h"
                :space-evenly false
                :hexpand true
                :halign "fill"
                (box
                  :class "window-icon-container"
                  :valign "center"
                  (image :class "window-icon-image"
                         :path {strlength(window.icon_path) > 0 ? window.icon_path : "${iconPaths.tmux}"}
                         :image-width 20
                         :image-height 20))
                (box
                  :class "window-info"
                  :orientation "v"
                  :space-evenly false
                  :hexpand true
                  :halign "fill"
                  (label
                    :class "window-app-name"
                    :halign "start"
                    :hexpand true
                    :text {(window.is_remote_session ?: false) ? (window.remote_session_name ?: window.display_name) : window.display_name}
                    :truncate true)
                  (label
                    :class "window-title"
                    :halign "start"
                    :hexpand true
                    :text {(window.is_remote_session ?: false) ? (window.remote_session_summary ?: (window.title ?: "Remote session")) : (window.title ?: '#' + window.id)}
                    :truncate true)
                  (label
                    :class "window-ssh-target"
                    :visible {(window.focused ?: false) && ((window.project_remote_enabled ?: false) || (window.is_remote_session ?: false))}
                    :halign "start"
                    :hexpand true
                    :truncate true
                    :text {(window.project_remote_target ?: "") != "" ? ("☁ • " + (window.project_remote_target ?: "")) : "☁ session"}))))
          )
          (box
            :class "window-row-meta"
            :orientation "h"
            :space-evenly false
            :hexpand false
            :halign "end"
            ;; Feature 136: Multi-indicator support - AI badges OUTSIDE focus eventbox for independent click handling
            (box
              :class "window-badges"
              :orientation "h"
              :space-evenly false
              :halign "end"
              (label
                :class "badge badge-pwa"
                :text "PWA"
                :visible {window.is_pwa ?: false})
              ;; Feature 136: Iterate over otel_badges array (max 3 visible)
              (for badge in {arraylength(window.otel_badges ?: []) <= 3 ? (window.otel_badges ?: []) : jq(window.otel_badges ?: [], ".[:3]")}
                (box
                  :class "ai-badge-inline-group"
                  :orientation "h"
                  :space-evenly false
                  :spacing 2
                  (eventbox
                    :class {"ai-badge-hover " +
                      (badge.stage_class ?: ("stage-" + (badge.otel_state ?: "idle"))) + " " +
                      (badge.stage_visual_state ?: "idle") +
                      ((badge.pulse_working ?: false) ? " pulse-working" : "") +
                      ((badge.output_unseen ?: badge.review_pending ?: false) ? " review-pending" : "") +
                      ((badge.otel_tool ?: "unknown") == "claude-code" ? " tool-claude-code" : ((badge.otel_tool ?: "unknown") == "codex" ? " tool-codex" : ((badge.otel_tool ?: "unknown") == "gemini" ? " tool-gemini" : " tool-unknown"))) +
                      ((badge.stale ?: false) ? " stale" : "") +
                      (((badge.confidence_level ?: "") != "") ? (" confidence-" + (badge.confidence_level ?: "")) : "")}
                    :onhover {"eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update hovered_ai_badge_key='" + (badge.badge_key ?: "") + "'"}
                    :onhoverlost {hovered_ai_badge_key == (badge.badge_key ?: "") ? "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update hovered_ai_badge_key=" : ""}
                    :cursor {(badge.window_id ?: 0) != 0 ? "pointer" : ((badge.trace_id ?: "") != "" ? "pointer" : "default")}
                    :onclick {(badge.window_id ?: 0) != 0
                      ? "${focusAiSessionScript}/bin/focus-ai-session-action ''${badge.focus_project ?: badge.window_project ?: window.project} ''${badge.window_id ?: window.id} ''${badge.focus_execution_mode ?: badge.execution_mode ?: window.execution_mode ?: "local"} ''${badge.focus_connection_key ?: badge.connection_key ?: window.connection_key ?: ""} ''${badge.tmux_pane ?: ""} ''${badge.tmux_session ?: ""} ''${badge.tmux_window ?: ""} ''${badge.pty ?: ""} &"
                      : ((badge.trace_id ?: "") != "" ? "${openLangfuseTraceScript}/bin/open-langfuse-trace " + badge.trace_id + " &" : "")
                    }
                    :tooltip {((badge.otel_tool ?: "unknown") == "claude-code" ? "Claude Code" : ((badge.otel_tool ?: "unknown") == "codex" ? "Codex CLI" : ((badge.otel_tool ?: "unknown") == "gemini" ? "Gemini CLI" : (badge.otel_tool ?: "Unknown")))) + " · " + (badge.stage_label ?: badge.otel_state ?: "Idle") + ((badge.stage_detail ?: "") != "" ? (" · " + (badge.stage_detail ?: "")) : "") + ((badge.output_unseen ?: badge.review_pending ?: false) ? " · Unseen output" : "") + " · " + ((badge.execution_mode ?: "local") == "ssh" ? "remote" : "local") + ((badge.host_name ?: "") != "" ? ("@" + (badge.host_name ?: "")) : "") + ((badge.native_session_id ?: "") != "" ? " · SID " + badge.native_session_id : ((badge.session_id ?: "") != "" ? " · SID " + badge.session_id : "")) + ((badge.pid ?: "") != "" ? " · PID " + badge.pid : "") + ((badge.tmux_pane ?: "") != "" ? " · pane " + badge.tmux_pane : "") + ((badge.confidence_level ?: "") != "" ? " · confidence " + badge.confidence_level : "") + ((badge.stale ?: false) ? (" · stale " + (badge.stale_age_seconds ?: 0) + "s") : "") + ((badge.window_id ?: 0) != 0 ? " · Click to focus session" : ((badge.trace_id ?: "") != "" ? " · Click for trace" : ""))}
                    (box
                      :orientation "h"
                      :space-evenly false
                      :spacing 1
                      (image
                        :class {"ai-badge-icon" +
                          " " + (badge.stage_visual_state ?: "idle") +
                          ((badge.pulse_working ?: false) ? " pulse-working" : "") +
                          ((badge.otel_tool ?: "unknown") == "claude-code" ? " tool-claude-code" : ((badge.otel_tool ?: "unknown") == "codex" ? " tool-codex" : ((badge.otel_tool ?: "unknown") == "gemini" ? " tool-gemini" : " tool-unknown")))}
                        :path {(badge.otel_tool ?: "unknown") == "claude-code"
                          ? "${iconPaths.claude}"
                          : ((badge.otel_tool ?: "unknown") == "codex"
                            ? "${iconPaths.codex}"
                            : ((badge.otel_tool ?: "unknown") == "gemini"
                              ? "${iconPaths.gemini}"
                              : "${iconPaths.anthropic}"))}
                        :image-width {(badge.stage_visual_state ?: "idle") == "working" ? 18 : (((badge.stage_visual_state ?: "idle") == "attention") ? 17 : 16)}
                        :image-height {(badge.stage_visual_state ?: "idle") == "working" ? 18 : (((badge.stage_visual_state ?: "idle") == "attention") ? 17 : 16)})
                      (label
                        :class "ai-badge-unread-dot"
                        :visible {badge.output_unseen ?: badge.review_pending ?: false}
                        :text "●")))
                  (box
                    :class "ai-badge-quick-actions"
                    :orientation "h"
                    :space-evenly false
                    :spacing 1
                    :visible {hovered_ai_badge_key == (badge.badge_key ?: "")}
                    (eventbox
                      :cursor "pointer"
                      :visible {(badge.window_id ?: 0) != 0}
                      :onclick "${focusAiSessionScript}/bin/focus-ai-session-action ''${badge.focus_project ?: badge.window_project ?: window.project} ''${badge.window_id ?: window.id} ''${badge.focus_execution_mode ?: badge.execution_mode ?: window.execution_mode ?: "local"} ''${badge.focus_connection_key ?: badge.connection_key ?: window.connection_key ?: ""} ''${badge.tmux_pane ?: ""} ''${badge.tmux_session ?: ""} ''${badge.tmux_window ?: ""} ''${badge.pty ?: ""} &"
                      :tooltip "Focus session"
                      (label :class "ai-badge-quick-btn" :text "󰌑"))
                    (eventbox
                      :cursor "pointer"
                      :visible {(badge.native_session_id ?: "") != "" || (badge.session_id ?: "") != ""}
                      :onclick {((badge.native_session_id ?: "") != "" ? "printf %s '" + (badge.native_session_id ?: "") + "' | ${pkgs.wl-clipboard}/bin/wl-copy" : "printf %s '" + (badge.session_id ?: "") + "' | ${pkgs.wl-clipboard}/bin/wl-copy") + " &"}
                      :tooltip "Copy session id"
                      (label :class "ai-badge-quick-btn" :text "󰆏"))
                    (eventbox
                      :cursor "pointer"
                      :visible {(badge.trace_id ?: "") != ""}
                      :onclick {"${openLangfuseTraceScript}/bin/open-langfuse-trace " + (badge.trace_id ?: "") + " &"}
                      :tooltip "Open trace"
                      (label :class "ai-badge-quick-btn" :text "󱂬")))))
              ;; Feature 136: Overflow badge when more than 3 sessions
              (label
                :class "badge badge-overflow"
                :text {"+''${arraylength(window.otel_badges ?: []) - 3}"}
                :visible {arraylength(window.otel_badges ?: []) > 3}
                :tooltip {jq(window.otel_badges ?: [], ".[3:] | map(.otel_tool + \": \" + (.stage_label // .otel_state // \"idle\")) | join(\"\\n\")")}))
            (box
              :class {"window-action-rail" + ((hovered_window_id == window.id) && !(window.is_remote_session ?: false) ? " visible" : "")}
              :orientation "h"
              :space-evenly false
              :spacing 2
              (eventbox
                :cursor "pointer"
                :onclick "${closeWindowScript}/bin/close-window-action ''${window.id} &"
                :tooltip "Close window"
                (label
                  :class "window-action-btn window-action-close"
                  :text "󰅖"))))))))
''
