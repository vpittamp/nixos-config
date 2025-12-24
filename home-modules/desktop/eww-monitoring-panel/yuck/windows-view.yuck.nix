{ pkgs, focusWindowScript, closeWorktreeScript, closeAllWindowsScript, toggleWindowsProjectExpandScript, toggleProjectContextScript, switchProjectScript, ... }:

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
                    :spacing 4
                    (image
                      :class {"ai-badge-icon" +
                        (session.state == "working"
                          ? " working" + (pulse_phase == "1" ? " rotate-phase" : "")
                          : (session.state == "completed"
                            ? " completed"
                            : (session.needs_attention ? " attention" : " idle")))}
                      :path {session.source == "claude-code"
                        ? "/etc/nixos/assets/icons/claude.svg"
                        : (session.source == "codex"
                          ? "/etc/nixos/assets/icons/codex.svg"
                          : (session.source == "gemini"
                            ? "/etc/nixos/assets/icons/gemini.svg"
                            : "/etc/nixos/assets/icons/anthropic.svg"))}
                      :image-width 18
                      :image-height 18)))))
            ;; Projects list
            (for project in {monitoring_data.projects ?: []}
              (project-widget :project project))))))) 

  (defwidget project-widget [project]
    (box
      :class {"project " + (project.scope == "scoped" ? "scoped-project" : "global-project") + (project.is_active ? " project-active" : "")}
      :orientation "v"
      :space-evenly false
      (eventbox
        :onclick "${toggleWindowsProjectExpandScript}/bin/toggle-windows-project-expand ''${project.name} &"
        :onrightclick "${toggleProjectContextScript}/bin/toggle-project-context ''${project.name} &"
        :cursor "pointer"
        :tooltip {(windows_expanded_projects == "all" || jq(windows_expanded_projects, ". | index(\"" + project.name + "\") != null")) ? "Click to collapse" : "Click to expand"}
        (box
          :class "project-header"
          :orientation "h"
          :space-evenly false
          (label
            :class "expand-icon"
            :text {(windows_expanded_projects == "all" || jq(windows_expanded_projects, ". | index(\"" + project.name + "\") != null")) ? "󰅀" : "󰅂"})
          (label
            :class "project-name"
            :text "''${project.scope == 'scoped' ? '󱂬' : '󰞇'} ''${project.name}")
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
            (eventbox
              :cursor "pointer"
              :class "hover-close-btn project-hover-close"
              :onclick "${closeWorktreeScript}/bin/close-worktree-action ''${project.name} &"
              :tooltip "Close all windows in this project"
              (label
                :class "hover-close-icon"
                :text "󰅖")))))
      (revealer
        :reveal {context_menu_project == project.name}
        :transition "slidedown"
        :duration "100ms"
        (box
          :class "project-action-bar"
          :orientation "h"
          :space-evenly false
          :halign "end"
          (eventbox
            :visible {project.scope == "scoped"}
            :cursor "pointer"
            :onclick "${switchProjectScript}/bin/switch-project-action ''${project.name}; eww --config $HOME/.config/eww-monitoring-panel update context_menu_project= &"
            :tooltip "Switch to this worktree"
            (label :class "action-btn action-switch" :text "󰌑"))
          (eventbox
            :cursor "pointer"
            :onclick "${closeWorktreeScript}/bin/close-worktree-action ''${project.name}; eww --config $HOME/.config/eww-monitoring-panel update context_menu_project= &"
            :tooltip "Close all windows for this project"
            (label :class "action-btn action-close-project" :text "󰅖"))
          (eventbox
            :cursor "pointer"
            :onclick "eww --config $HOME/.config/eww-monitoring-panel update context_menu_project="
            :tooltip "Close menu"
            (label :class "action-btn action-dismiss" :text "󰅙"))))
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

  (defwidget window-widget [window]
    (box
      :class "window-container"
      :orientation "v"
      :space-evenly false
      (box
        :class "window-row"
        :orientation "h"
        :space-evenly false
        (eventbox
          :onclick "${focusWindowScript}/bin/focus-window-action ''${window.project} ''${window.id} &"
          :onrightclick "eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=''${context_menu_window_id == window.id ? 0 : window.id}"
          :cursor "pointer"
          :hexpand true
                      (box
                        :class "window ''${window.scope == 'scoped' ? 'scoped-window' : 'global-window'} ''${window.state_classes} ''${clicked_window_id == window.id ? ' clicked' : ""} ''${strlength(window.icon_path) > 0 ? 'has-icon' : 'no-icon'}"
                        :orientation "h"
          
            :space-evenly false
            :hexpand true
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
            (box
              :class "window-badges"
              :orientation "h"
              :space-evenly false
              :halign "end"
              (label
                :class "badge badge-pwa"
                :text "PWA"
                :visible {window.is_pwa ?: false})
              (image
                :class {"ai-badge-icon" +
                  ((window.badge.otel_state ?: "none") == "working"
                    ? " working" + (pulse_phase == "1" ? " rotate-phase" : "")
                    : ((window.badge.otel_state ?: "none") == "completed"
                      ? " completed"
                      : ((window.badge.otel_state ?: "none") == "attention"
                        ? " attention"
                        : " idle")))}
                :path {window.badge.otel_tool == "claude-code"
                  ? "/etc/nixos/assets/icons/claude.svg"
                  : (window.badge.otel_tool == "codex"
                    ? "/etc/nixos/assets/icons/codex.svg"
                    : (window.badge.otel_tool == "gemini"
                      ? "/etc/nixos/assets/icons/gemini.svg"
                      : "/etc/nixos/assets/icons/anthropic.svg"))}
                :image-width 16
                :image-height 16
                :visible {(window.badge.otel_tool ?: "none") != "none"})
              (label
                :class "badge badge-urgent"
                :text "!"
                :visible {window.urgent ?: false})
              (label
                :class "badge badge-floating"
                :text "⚓"
                :visible {window.floating ?: false})
              (label
                :class "badge badge-sticky"
                :text "📌"
                :visible {window.sticky ?: false})
              (label
                :class "badge badge-fullscreen"
                :text "󰊓"
                :visible {window.fullscreen != 0})
              (eventbox
                :class "json-expand-trigger"
                :onhover "eww update hover_window_id=''${window.id}"
                :onhoverlost "eww update hover_window_id=0"
                (label :class "expand-icon" :text "󰅂")))))
        (eventbox
          :cursor "pointer"
          :class "hover-close-btn window-hover-close"
          :onclick "swaymsg [con_id=''${window.id}] kill"
          :tooltip "Close window"
          (label :class "hover-close-icon" :text "󰅖")))
      (revealer
        :reveal {hover_window_id == window.id}
        :transition "slidedown"
        :duration "150ms"
        (box
          :class "window-json-panel"
          (scroll
            :hscroll true
            :vscroll false
            (label :class "json-text" :text "''${window.json_repr}"))))
      (revealer
        :reveal {context_menu_window_id == window.id}
        :transition "slidedown"
        :duration "100ms"
        (box
          :class "window-action-bar"
          :orientation "h"
          :space-evenly true
          (eventbox :cursor "pointer" :onclick "swaymsg [con_id=''${window.id}] focus && eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=0" :tooltip "Focus" (label :class "action-btn" :text "󰌑"))
          (eventbox :cursor "pointer" :onclick "swaymsg [con_id=''${window.id}] floating toggle && eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=0" :tooltip "Float" (label :class "action-btn" :text "󰊓"))
          (eventbox :cursor "pointer" :onclick "swaymsg [con_id=''${window.id}] fullscreen toggle && eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=0" :tooltip "Full" (label :class "action-btn" :text "󰊓"))
          (eventbox :cursor "pointer" :onclick "swaymsg [con_id=''${window.id}] move scratchpad && eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=0" :tooltip "Hide" (label :class "action-btn" :text "󰅙"))))))
''
