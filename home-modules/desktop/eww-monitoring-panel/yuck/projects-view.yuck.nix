{ pkgs, config, toggleExpandAllScript, projectCreateOpenScript, toggleProjectExpandedScript, worktreeCreateOpenScript, worktreeDeleteOpenScript, switchProjectScript, ... }:

let
  # Full path to i3pm (user profile binary, not in standard PATH for EWW onclick commands)
  i3pm = "${config.home.profileDirectory}/bin/i3pm";
in

''
  ;; Projects View - Project list with metadata
  (defwidget projects-view []
    (scroll
      :vscroll true
      :hscroll false
      :vexpand true
      (box
        :class "projects-header-container"
        :orientation "v"
        :space-evenly false
        :visible {!project_creating}
        (box
          :class "projects-header"
          :orientation "h"
          :space-evenly false
          (label
            :class "projects-header-title"
            :halign "start"
            :hexpand true
            :text "Projects")
          (button
            :class "header-icon-button expand-collapse-btn"
            :onclick "${toggleExpandAllScript}/bin/toggle-expand-all-projects"
            :tooltip {projects_all_expanded ? "Collapse all" : "Expand all"}
            {projects_all_expanded ? "󰅀" : "󰅂"})
          (button
            :class "header-icon-button new-project-btn"
            :onclick "${projectCreateOpenScript}/bin/project-create-open"
            :tooltip "Create new project"
            "󰐕"))
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
          (label
            :class "filter-count"
            :visible {project_filter != ""}
            :text {jq(projects_data.discovered_repositories ?: [], "[.[].worktrees[]? | select(((.branch // \"\") | test(\"(?i).*\" + project_filter + \".*\")) or ((.branch_number // \"\") | test(\"^\" + project_filter + \"\")))] | length")}))
        (revealer
          :transition "slidedown"
          :reveal project_creating
          :duration "200ms"
          (project-create-form))
    (revealer
      :transition "slidedown"
      :reveal worktree_creating
      :duration "200ms"
      (worktree-create-form :parent_project worktree_form_parent_project))
    (project-delete-confirmation)
    (worktree-delete-confirmation)
    (box
      :class "error-message"
      :visible {projects_data.status == "error"}
      (label :text "Error: ''${projects_data.error ?: 'Unknown error'}"))
    (box
      :class "projects-list"
      :orientation "v"
      :space-evenly false
      (for repo in {projects_data.discovered_repositories ?: []}
        (box
          :orientation "v"
          :space-evenly false
          :visible {project_filter == "" ||
                    matches(repo.name ?: "", "(?i).*" + replace(project_filter, " ", ".*") + ".*") ||
                    matches(repo.qualified_name ?: "", "(?i).*" + replace(project_filter, " ", ".*") + ".*") ||
                    matches(repo.account ?: "", "(?i).*" + project_filter + ".*") ||
                    matches(repo.display_name ?: "", "(?i).*" + replace(project_filter, " ", ".*") + ".*") ||
                    jq(repo.worktrees ?: [], "any(.[]; (.branch // \"\") | test(\"(?i).*\" + project_filter + \".*\"))") ||
                    jq(repo.worktrees ?: [], "any(.[]; (.branch_number // \"\") | test(\"^\" + project_filter + \"\"))")}
          (discovered-repo-card :repo repo)
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
                  :limit-width 30
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
                :limit-width 40
                :truncate true
                :text "''${repo.directory_display ?: repo.directory}"
                :tooltip "''${repo.directory}")))
          (box
            :class "project-action-bar"
            :orientation "h"
            :space-evenly false
            :visible {hover_project_name == repo.qualified_name && !project_deleting}
            (eventbox
              :cursor "pointer"
              :onclick "echo -n ''\'''${repo.directory}' | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification='Copied: ''${repo.directory}' success_notification_visible=true && (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification_visible=false) &"
              :tooltip "Copy directory path"
              (label :class "action-btn action-copy" :text "󰆏"))
            (eventbox
              :cursor "pointer"
              :onclick "${worktreeCreateOpenScript}/bin/worktree-create-open ''${repo.qualified_name}"
              :tooltip "Create new worktree"
              (label :class "action-btn action-add" :text "󰐕")))
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

  (defwidget discovered-worktree-card [worktree]
    (box
      :class {"worktree-card-wrapper" + (worktree.is_main ? " is-main-worktree" : "")}
      (eventbox
        :cursor "pointer"
        :onclick "${switchProjectScript}/bin/switch-project-action ''${worktree.qualified_name}"
        :onhover "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update hover_worktree_name=''${worktree.qualified_name}"
        :onhoverlost "${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update hover_worktree_name='''"
        (box
          :class {"worktree-card" + (worktree.is_active ? " active-worktree" : "") + (worktree.git_is_dirty ? " dirty-worktree" : "")}
          :orientation "h"
          :space-evenly false
          (box
            :orientation "h"
            :space-evenly false
            :hexpand true
            (label
              :class {worktree.is_active ? "active-indicator" : "active-indicator-placeholder"}
              :valign "start"
              :text "●"
              :tooltip {worktree.is_active ? "Active worktree" : ""})
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
              (label
                :class "worktree-branch"
                :halign "start"
                :limit-width 28
                :truncate true
                :text {(worktree.has_branch_number ?: false) ? (worktree.branch_description ?: worktree.branch) : worktree.branch}
                :tooltip "''${worktree.branch}")
              (label
                :class "worktree-commit"
                :halign "start"
                :limit-width 15
                :text {" @ " + (worktree.commit ?: "unknown")})
              (label
                :class "git-conflict"
                :visible {worktree.git_has_conflicts ?: false}
                :text " ''${worktree.git_conflict_indicator}"
                :tooltip "Has unresolved merge conflicts")
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
              (label
                :class "git-sync"
                :visible {(worktree.git_sync_indicator ?: "") != ""}
                :text " ''${worktree.git_sync_indicator}"
                :tooltip {((worktree.git_ahead ?: 0) > 0 ? "''${worktree.git_ahead} commits to push" : "") + 
                  ((worktree.git_ahead ?: 0) > 0 && (worktree.git_behind ?: 0) > 0 ? ", " : "") + 
                  ((worktree.git_behind ?: 0) > 0 ? "''${worktree.git_behind} commits to pull" : "")})
              (label
                :class "badge-merged"
                :visible {worktree.git_is_merged ?: false}
                :text " ✓"
                :tooltip "Branch merged into main")
              (label
                :class "badge-stale"
                :visible {worktree.git_is_stale ?: false}
                :text " 💤"
                :tooltip "No activity in 30+ days"))
            (box
              :class "worktree-path-row"
              :orientation "h"
              :space-evenly false
              (label
                :class "worktree-path"
                :halign "start"
                :limit-width 35
                :truncate true
                :text "''${worktree.directory_display}"
                :tooltip "''${worktree.path}")
              (eventbox
                :class {"copy-btn-container" + (hover_worktree_name == worktree.qualified_name ? " visible" : "")}
                :cursor "pointer"
                :onclick "echo -n '#{worktree.path}' | wl-copy && notify-send -t 1500 'Copied' '#{worktree.directory_display}'"
                :tooltip "Copy directory path"
                (label
                  :class "copy-btn"
                  :text "")))
            (label
              :class "worktree-last-commit"
              :halign "start"
              :visible {hover_worktree_name == worktree.qualified_name && (worktree.git_last_commit_relative ?: "") != ""}
              :limit-width 38
              :truncate true
              :text {(worktree.git_last_commit_relative ?: "") + (worktree.git_last_commit_message != "" ? " - " + (worktree.git_last_commit_message ?: "") : "")}
              :tooltip {worktree.git_status_tooltip ?: ""})))
          (box
            :class {"worktree-action-bar" + (hover_worktree_name == worktree.qualified_name && !worktree.is_main ? " visible" : "")}
            :orientation "h"
            :space-evenly false
            :halign "end"
            (eventbox
              :cursor "pointer"
              :onclick "${i3pm} scratchpad toggle ''${worktree.qualified_name}"
              :tooltip "Open terminal (t)"
              (label :class "action-btn action-terminal" :text ""))
            (eventbox
              :cursor "pointer"
              :onclick "echo -n ''\'''${worktree.path}' | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification='Copied: ''${worktree.path}' success_notification_visible=true && (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update success_notification_visible=false) &"
              :tooltip "Copy path (y)"
              (label :class "action-btn action-copy" :text "󰆏"))
            (eventbox
              :cursor "pointer"
              :onclick "${worktreeDeleteOpenScript}/bin/worktree-delete-open ''${worktree.qualified_name} ''${worktree.branch} ''${worktree.git_is_dirty}"
              :tooltip "Delete worktree (d)"
              (label :class "action-btn action-delete" :text "󰆴")))
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
''