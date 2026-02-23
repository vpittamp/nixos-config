{ pkgs, focusWindowScript, focusAiSessionScript, closeWorktreeScript, closeAllWindowsScript, closeWindowScript, toggleWindowsProjectExpandScript, toggleProjectContextScript, switchProjectScript, openRemoteSessionWindowScript, openLangfuseTraceScript, iconPaths, ... }:

''
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
              :halign "end"
              :spacing 8
              ;; Expand/Collapse All button
              (eventbox
                :cursor "pointer"
                :onclick {windows_all_expanded ? "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update windows_expanded_projects='[]' windows_all_expanded=false" : "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update windows_expanded_projects='all' windows_all_expanded=true"}
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
                :onhover "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update hovered_close_all=true"
                :onhoverlost "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update hovered_close_all=false"
                :onclick "${closeAllWindowsScript}/bin/close-all-windows-action &"
                :tooltip "Close all scoped windows"
                (box
                  :class {"close-all-btn" + (!hovered_close_all ? " icon-only" : "")}
                  :orientation "h"
                  :space-evenly false
                  :spacing 4
                  (label :class "close-all-icon" :text "󰅖")
                  (label :class "close-all-text" :visible {hovered_close_all} :text "Close All"))))
            ;; Feature 117: Active AI Sessions bar - DISABLED
            (box
              :class "ai-sessions-bar"
              :visible false
              :orientation "h"
              :space-evenly false
              :spacing 6
              (for session in {monitoring_data.ai_sessions ?: []}
                (eventbox
                  :cursor "pointer"
                  :onclick "${focusWindowScript}/bin/focus-window-action ''${session.project} ''${session.id} &"
                  :tooltip {"󱜙 Click to focus\n󰙅 " + (session.project != "" ? session.project : "Unknown") + "\n󰚩 " + (session.source == "claude-code" ? "Claude Code" : (session.source == "codex" ? "Codex" : session.source)) + "\n" + (session.state == "working" ? "⏳ Processing..." : (session.state == "completed" ? "✓ Completed - awaiting input" : (session.needs_attention ? "🔔 Needs attention" : "💤 Ready for input")))}
                  (box
                    :class {"ai-session-chip" + (session.state == "working" ? " working" : (session.state == "completed" ? " completed" : (session.needs_attention ? " attention" : " idle")))}
                    :orientation "h"
                    :space-evenly false
                    :spacing 2
                    (image
                      :class {"ai-badge-icon" +
                        (session.state == "working"
                          ? " working"
                          : (session.state == "completed"
                            ? " completed"
                            : (session.needs_attention ? " attention" : " idle")))}
                      :path {session.source == "claude-code"
                        ? "${iconPaths.claude}"
                        : (session.source == "codex"
                          ? "${iconPaths.codex}"
                          : (session.source == "gemini"
                            ? "${iconPaths.gemini}"
                            : "${iconPaths.anthropic}"))}
                      :image-width 18
                      :image-height 18)))))
            ;; Projects list
            (for project in {monitoring_data.projects ?: []}
              (project-widget :project project)))))))

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
            :class "badge badge-local"
            :visible {(project.variant ?: "") == "local" && (project.has_remote_variant ?: false)}
            :text "󰌽"
            :tooltip "Local project card")
          (label
            :class "badge badge-remote"
            :visible {(project.variant ?: "") == "ssh" || (project.remote_enabled ?: false)}
            :text "☁"
            :tooltip {"Remote: " + (project.remote_target ?: "") + ((project.remote_directory_display ?: "") != "" ? " • " + (project.remote_directory_display ?: "") : "")})
          (box
            :hexpand true
            :halign "end"
            :orientation "h"
            :space-evenly false
            (label
              :class "window-count-badge"
              :text "''${project.window_count}")
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
              ;; Feature 136: Iterate over otel_badges array (max 3 visible) with status icons
              (for badge in {arraylength(window.otel_badges ?: []) <= 3 ? (window.otel_badges ?: []) : jq(window.otel_badges ?: [], ".[:3]")}
                (eventbox
                  :class "ai-badge-hover"
                  :cursor {(badge.window_id ?: 0) != 0 ? "pointer" : ((badge.trace_id ?: "") != "" ? "pointer" : "default")}
                  :onclick {(badge.window_id ?: 0) != 0
                    ? "${focusAiSessionScript}/bin/focus-ai-session-action ''${badge.project ?: window.project} ''${badge.window_id ?: window.id} ''${window.execution_mode ?: "local"} ''${badge.tmux_pane ?: ""} ''${badge.tmux_session ?: ""} ''${badge.tmux_window ?: ""} ''${badge.pty ?: ""} &"
                    : ((badge.trace_id ?: "") != "" ? "${openLangfuseTraceScript}/bin/open-langfuse-trace " + badge.trace_id + " &" : "")
                  }
                  :tooltip {((badge.otel_tool ?: "unknown") == "claude-code" ? "Claude Code" : ((badge.otel_tool ?: "unknown") == "codex" ? "Codex CLI" : ((badge.otel_tool ?: "unknown") == "gemini" ? "Gemini CLI" : (badge.otel_tool ?: "Unknown")))) + " · " + ((badge.otel_state ?: "idle") == "working" ? "⏳ Working" : ((badge.otel_state ?: "idle") == "completed" ? "✓ Ready" : ((badge.otel_state ?: "idle") == "attention" ? "⚠ Attention" : "💤 Idle"))) + ((badge.pid ?: "") != "" ? " · PID " + badge.pid : "") + ((badge.tmux_pane ?: "") != "" ? " · pane " + badge.tmux_pane : "") + ((badge.window_id ?: 0) != 0 ? " · Click to focus session" : ((badge.trace_id ?: "") != "" ? " · Click for trace" : ""))}
                  (box
                    :orientation "h"
                    :space-evenly false
                    :spacing 1
                    (image
                      :class {"ai-badge-icon" +
                        ((badge.otel_state ?: "idle") == "working"
                          ? " working"
                          : ((badge.otel_state ?: "idle") == "completed"
                            ? " completed"
                            : ((badge.otel_state ?: "idle") == "attention"
                              ? " attention"
                              : " idle")))}
                      :path {(badge.otel_tool ?: "unknown") == "claude-code"
                        ? "${iconPaths.claude}"
                        : ((badge.otel_tool ?: "unknown") == "codex"
                          ? "${iconPaths.codex}"
                          : ((badge.otel_tool ?: "unknown") == "gemini"
                            ? "${iconPaths.gemini}"
                            : "${iconPaths.anthropic}"))}
                      :image-width 16
                      :image-height 16)
                    ;; Status icon next to each badge (restored from b658b3dc)
                    (label
                      :class {"ai-session-status-icon" +
                        ((badge.otel_state ?: "idle") == "working" ? " working"
                          : ((badge.otel_state ?: "idle") == "completed" ? " completed"
                            : ((badge.otel_state ?: "idle") == "attention" ? " attention" : "")))}
                      :visible {(badge.otel_state ?: "idle") != "idle"}
                      :text {(badge.otel_state ?: "idle") == "working" ? "●"
                        : ((badge.otel_state ?: "idle") == "completed" ? "✓"
                          : ((badge.otel_state ?: "idle") == "attention" ? "!" : ""))}))))
              ;; Feature 136: Overflow badge when more than 3 sessions
              (label
                :class "badge badge-overflow"
                :text {"+''${arraylength(window.otel_badges ?: []) - 3}"}
                :visible {arraylength(window.otel_badges ?: []) > 3}
                :tooltip {jq(window.otel_badges ?: [], ".[3:] | map(.otel_tool + \": \" + .otel_state) | join(\"\\n\")")}))
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
