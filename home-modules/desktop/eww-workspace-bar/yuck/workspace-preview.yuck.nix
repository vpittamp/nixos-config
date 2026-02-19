{ fallbackIconPath, ... }:

''
  ;; Feature 057: User Story 2 - Workspace Preview Card Widget (T041)
  ;; Enhanced with prominent mode + digits display (Option 1 UX)
  (defwidget workspace-preview-card []
    (box :class "preview-card"
         :orientation "v"
         :space-evenly false

      ;; Option A: Unified Smart Detection - Project Mode Preview
      (box :class "project-preview"
           :orientation "v"
           :space-evenly false
           :visible {workspace_preview_data.type == "project"}
        ;; Project search header with icon
        (box :class "preview-header"
             :orientation "v"
             :halign "center"
          (label :class "preview-mode-digits"
                 :text {"🔍 " + workspace_preview_data.accumulated_chars})
          ;; Project match with icon
          (box :class "project-match-box"
               :orientation "h"
               :space-evenly false
               :spacing 8
               :halign "center"
               :visible {workspace_preview_data.matched_project != ""}
            (label :class "project-icon"
                   :text {workspace_preview_data.project_icon ?: "📁"})
            (label :class "preview-subtitle"
                   :text {"Project: " + workspace_preview_data.matched_project}))
          ;; No match / searching text
          (label :class "preview-subtitle"
                 :visible {workspace_preview_data.matched_project == ""}
                 :text {workspace_preview_data.no_match == true
                        ? "No project found"
                        : "Type project name..."}))
        ;; Match indicator
        (box :class "preview-body"
             :orientation "v"
             :halign "center"
          (label :class {workspace_preview_data.matched_project != "" ? "preview-match" : "preview-no-match"}
                 :text {workspace_preview_data.matched_project != ""
                        ? "✓ Match found - Press Enter"
                        : (workspace_preview_data.no_match == true
                           ? "No matches - Try different letters"
                           : "")})))

      ;; Feature 072: T020-T024 - All Windows Preview (User Story 1)
      (box :class "all-windows-preview"
           :orientation "v"
           :space-evenly false
           :visible {workspace_preview_data.type == "all_windows"}
        ;; Header with counts
        (box :class "preview-header"
             :orientation "v"
             :halign "center"
          (label :class "preview-mode-digits"
                 :text "🪟 All Windows")
          (label :class "preview-subtitle"
                 :text {workspace_preview_data.total_window_count + " window" +
                        (workspace_preview_data.total_window_count != 1 ? "s" : "") +
                        " across " + workspace_preview_data.total_workspace_count +
                        " workspace" + (workspace_preview_data.total_workspace_count != 1 ? "s" : "")}))

        ;; Instructional state (when no digits typed yet)
        (box :class "preview-body"
             :orientation "v"
             :halign "center"
             :visible {workspace_preview_data.instructional == true}
          (label :class "preview-subtitle"
                 :text "Type workspace number to filter, or :project for project mode"))

        ;; Empty state (no windows open anywhere)
        (box :class "preview-body"
             :orientation "v"
             :halign "center"
             :visible {workspace_preview_data.empty == true && workspace_preview_data.instructional != true}
          (label :class "preview-empty"
                 :text "No windows open"))

        ;; Scrollable workspace groups list (Feature 072: T021)
        (scroll :class "workspace-groups-scroll"
                :vscroll true
                :hscroll false
                :height 600
                :visible {workspace_preview_data.empty == false && workspace_preview_data.instructional != true}
          (box :class "workspace-groups"
               :orientation "v"
               :space-evenly false
               :spacing 12
            (for group in {workspace_preview_data.workspace_groups ?: []}
              (box :class "workspace-group"
                   :orientation "v"
                   :space-evenly false
                   :spacing 4
                ;; Workspace header
                (box :class {"workspace-group-header" +
                             ((workspace_preview_data.selection_state?.item_type == "workspace_heading" &&
                               workspace_preview_data.selection_state?.workspace_num == group.workspace_num)
                              ? (workspace_preview_data.selection_state?.move_mode ? " selected-move-mode" : " selected")
                              : "")}
                     :orientation "h"
                     :space-evenly false
                     :spacing 8
                  (label :class "workspace-group-number"
                         :text {"Workspace " + group.workspace_num + ((group.workspace_name ?: "") != "" ? " (" + group.workspace_name + ")" : "")})
                  (label :class "workspace-group-count"
                         :text {group.window_count + " window" + (group.window_count != 1 ? "s" : "")})
                  (label :class "workspace-group-monitor"
                         :text {group.monitor_output}))

                ;; Window entries for this workspace
                (box :class "workspace-group-windows"
                     :orientation "v"
                     :space-evenly false
                     :spacing 4
                  (for window in {group.windows ?: []}
                    (box :class {"preview-app" +
                                 ((window.focused && !(workspace_preview_data.selection_state?.visible ?: false)) ? " focused" : "") +
                                 ((workspace_preview_data.selection_state?.item_type == "window" &&
                                   workspace_preview_data.selection_state?.window_id == window.window_id)
                                  ? (workspace_preview_data.selection_state?.move_mode ? " selected-move-mode" : " selected")
                                  : "")}
                         :orientation "h"
                         :space-evenly false
                         :spacing 8
                      (image :class "preview-app-icon"
                             :path {window.icon_path != "" ? window.icon_path : "${fallbackIconPath}"}
                             :image-width 24
                             :image-height 24)
                      (label :class "preview-app-name"
                             :text {window.name}
                             :limit-width 30
                             :truncate true))))))))

        ;; Footer: Truncation indicator
        (box :class "preview-footer"
             :visible {(workspace_preview_data.total_workspace_count ?: 0) > 20}
          (label :class "preview-count"
                 :text {"... and " + ((workspace_preview_data.total_workspace_count ?: 0) - 20) + " more workspaces (type digits to filter)"})))

      ;; Feature 078: T022-T025 - Project List Preview
      (box :class "project-list-preview"
           :orientation "v"
           :space-evenly false
           :visible {workspace_preview_data.type == "project_list"}
        ;; Header with filter input
        (box :class "preview-header"
             :orientation "v"
             :halign "center"
          (label :class "preview-mode-digits"
                 :text {"🔍 :" + workspace_preview_data.accumulated_chars})
          (label :class "preview-subtitle"
                 :text {workspace_preview_data.total_count + " project" +
                        (workspace_preview_data.total_count != 1 ? "s" : "") +
                        (workspace_preview_data.accumulated_chars != "" ? " matching" : "")}))

        ;; Empty state
        (box :class "preview-body"
             :orientation "v"
             :halign "center"
             :visible {workspace_preview_data.empty == true}
          (label :class "preview-empty"
                 :text "No matching projects"))

        ;; Scrollable project list
        (scroll :class "project-list-scroll"
                :vscroll true
                :hscroll false
                :height 500
                :visible {workspace_preview_data.empty == false}
          (box :class "project-list"
               :orientation "v"
               :space-evenly false
               :spacing 8
            (for project in {workspace_preview_data.projects ?: []}
              (box :class {"project-item" + (project.selected ? " selected" : "") +
                           ((project.indentation_level ?: 0) > 0 ? " indent-1" : "")}
                   :orientation "v"
                   :space-evenly false
                   :spacing 2
                (box :class "project-item-header"
                     :orientation "h"
                     :space-evenly false
                     :spacing 8
                     :valign "center"
                  (label :class "project-icon"
                         :text {project.is_worktree ? "🌿" : (project.icon ?: "📁")})
                  (label :class "project-name"
                         :text {(project.branch_number ?: "") != ""
                                ? project.branch_number + " - " + project.display_name
                                : project.display_name}
                         :limit-width 35
                         :truncate true
                         :hexpand true)
                  (label :class "project-time"
                         :text {project.relative_time}
                         :halign "end"))
                (box :class "project-item-metadata"
                     :orientation "h"
                     :space-evenly false
                     :spacing 6
                  (label :class {project.is_worktree ? "project-badge-worktree" : "project-badge-root"}
                         :text {project.is_worktree ? "worktree" : "root project"})
                  (label :class "project-parent"
                         :text {"← " + project.parent_project_name}
                         :visible {project.parent_project_name != "null" && project.parent_project_name != ""})
                  (box :class "project-git-indicators"
                       :orientation "h"
                       :space-evenly false
                       :spacing 4
                       :visible {project.git_status != "null" && project.git_status != ""}
                    (label :class {(project.git_status ?: {"is_clean": true}).is_clean ? "project-git-clean" : "project-git-dirty"}
                           :text {(project.git_status ?: {"is_clean": true}).is_clean ? "✓ clean" : "✗ dirty"})
                    (label :class "project-git-ahead"
                           :text {"↑" + (project.git_status ?: {"ahead_count": 0}).ahead_count}
                           :visible {(project.git_status ?: {"ahead_count": 0}).ahead_count > 0})
                    (label :class "project-git-behind"
                           :text {"↓" + (project.git_status ?: {"behind_count": 0}).behind_count}
                           :visible {(project.git_status ?: {"behind_count": 0}).behind_count > 0}))
                  (label :class "project-warning"
                         :text "⚠️ missing"
                         :visible {!project.directory_exists}))))))

        ;; Footer: Keyboard hints
        (box :class "preview-footer"
          (label :class "preview-hint"
                 :text "↑↓ Navigate • Enter Switch • Esc Cancel")))

      ;; Workspace Mode Preview
      (box :class "workspace-preview"
           :orientation "v"
           :space-evenly false
           :visible {workspace_preview_data.type != "project" && workspace_preview_data.type != "all_windows" && workspace_preview_data.type != "project_list"}
        (box :class "preview-header"
             :orientation "v"
             :space-evenly false
             :halign "center"
          (label :class "preview-mode-digits"
                 :halign "center"
                 :text {workspace_preview_data.instructional == true
                        ? (workspace_preview_data.mode == "move" ? "⇒ __" : "→ __")
                        : (workspace_preview_data.mode == "move" ? "⇒ " : "→ ") +
                          (workspace_preview_data.accumulated_digits ?: workspace_preview_data.workspace_num)})
          (label :class "preview-subtitle"
                 :halign "center"
                 :text {workspace_preview_data.instructional == true
                        ? (workspace_preview_data.mode == "move"
                           ? "Type workspace + monitor (e.g., 231 = WS 23 → Monitor 1)"
                           : "Type workspace number...")
                        : (workspace_preview_data.mode == "move"
                           ? (workspace_preview_data.target_monitor != ""
                              ? "Move WS " + workspace_preview_data.workspace_num + " → " + workspace_preview_data.target_monitor
                              : "Move workspace (type monitor: 1-3)")
                           : "Navigate to Workspace " + workspace_preview_data.workspace_num)}))

        (box :class "preview-body"
             :orientation "v"
             :visible {workspace_preview_data.empty == true && workspace_preview_data.instructional != true}
          (label :class "preview-empty"
                 :text "Empty workspace"))

        (box :class "preview-apps"
             :orientation "v"
             :space-evenly false
             :spacing 4
             :visible {workspace_preview_data.empty == false && workspace_preview_data.instructional != true}
          (for app in {workspace_preview_data.apps ?: []}
            (box :class {"preview-app" + (app.focused ? " focused" : "")}
                 :orientation "h"
                 :space-evenly false
                 :spacing 8
              (image :class "preview-app-icon"
                     :path {app.icon_path != "" ? app.icon_path : "${fallbackIconPath}"}
                     :image-width 24
                     :image-height 24)
              (label :class "preview-app-name"
                     :text {app.name}
                     :limit-width 30
                     :truncate true))))

        (box :class "preview-footer"
             :visible {workspace_preview_data.empty == false && workspace_preview_data.instructional != true}
          (label :class "preview-count"
                 :text {workspace_preview_data.window_count + " window" + (workspace_preview_data.window_count != 1 ? "s" : "")}))

        (box :class "keyboard-hints-footer"
             :visible {keyboard_hints != ""}
          (label :class "keyboard-hints"
                 :text keyboard_hints)))))
''
