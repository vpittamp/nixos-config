{ pkgs, projectDeleteCancelScript, projectDeleteConfirmScript, worktreeDeleteCancelScript, worktreeDeleteConfirmScript, appDeleteCancelScript, appDeleteConfirmScript, ... }:

''
  ;; Conflict Resolution Dialog
  (defwidget conflict-resolution-dialog []
    (revealer
      :reveal conflict_dialog_visible
      :transition "crossfade"
      :duration "200ms"
      (box
        :class "dialog-overlay"
        (box
          :class "dialog-content"
          :orientation "v"
          :space-evenly false
          (label :class "dialog-title" :text "File Conflict Detected")
          (label :class "dialog-body" :wrap true
                 :text "The project configuration file was modified externally. How would you like to proceed?")
          (box
            :class "dialog-actions"
            :orientation "h"
            :space-evenly true
            (button :class "dialog-btn" :onclick "project-conflict-resolve keep-file ''${editing_project_name}" "Keep File")
            (button :class "dialog-btn" :onclick "project-conflict-resolve keep-ui ''${editing_project_name}" "Keep UI")
            (button :class "dialog-btn" :onclick "project-conflict-resolve merge-manual ''${editing_project_name}" "Manual Merge"))))))

  ;; Project Delete Confirmation
  (defwidget project-delete-confirmation []
    (revealer
      :reveal project_deleting
      :transition "slidedown"
      :duration "200ms"
      (box
        :class "delete-confirmation-dialog"
        :orientation "v"
        :space-evenly false
        (box
          :class "dialog-header"
          :orientation "h"
          :space-evenly false
          (label :class "dialog-icon warning" :text "⚠️")
          (label :class "dialog-title" :halign "start" :text "Delete Project"))
        (label :class "project-name-display" :halign "start" :text "''${delete_project_display_name}")
        (label :class "warning-message" :halign "start" :wrap true
               :text "This action is permanent. The project configuration file will be moved to a .deleted backup.")
        (revealer
          :reveal delete_project_has_worktrees
          :transition "slidedown"
          :duration "150ms"
          (box
            :class "worktree-warning"
            :orientation "v"
            :space-evenly false
            (label :class "warning-icon" :halign "start" :text "⚠ This project has worktrees")
            (label :class "warning-detail" :halign "start" :wrap true
                   :text "Worktrees will become orphaned if you force delete. Consider deleting worktrees first.")
            (box
              :class "force-delete-option"
              :orientation "h"
              :space-evenly false
              (checkbox
                :class "force-delete-checkbox"
                :checked delete_force
                :onchecked "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update delete_force=true"
                :onunchecked "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update delete_force=false")
              (label :class "force-delete-label" :halign "start" :text "Force delete (orphan worktrees)"))))
        (revealer
          :reveal {delete_error != ""}
          :transition "slidedown"
          :duration "150ms"
          (label :class "error-message" :halign "start" :wrap true :text delete_error))
        (box
          :class "dialog-actions"
          :orientation "h"
          :space-evenly false
          :halign "end"
          (button :class "cancel-delete-button" :onclick "${projectDeleteCancelScript}/bin/project-delete-cancel" "Cancel")
          (button :class "confirm-delete-button ''${delete_project_has_worktrees && !delete_force ? 'disabled' : ""}"
                  :onclick {delete_project_has_worktrees && !delete_force ? "" : "${projectDeleteConfirmScript}/bin/project-delete-confirm &"}
                  "🗑 Delete"))))) 

  ;; Worktree Delete Confirmation
  (defwidget worktree-delete-confirmation []
    (revealer
      :reveal worktree_delete_dialog_visible
      :transition "slidedown"
      :duration "200ms"
      (box
        :class "delete-confirmation-dialog worktree-delete-dialog"
        :orientation "v"
        :space-evenly false
        (box
          :class "dialog-header"
          :orientation "h"
          :space-evenly false
          (label :class "dialog-icon warning" :text "⚠️")
          (label :class "dialog-title" :halign "start" :text "Delete Worktree"))
        (label :class "project-name-display" :halign "start" :text "🌿 ''${worktree_delete_branch}")
        (label :class "warning-message" :halign "start" :wrap true
               :text "This will remove the worktree directory and its contents. The branch will remain in git.")
        (revealer
          :reveal worktree_delete_is_dirty
          :transition "slidedown"
          :duration "150ms"
          (box
            :class "worktree-warning dirty-warning"
            :orientation "v"
            :space-evenly false
            (label :class "warning-icon" :halign "start" :text "⚠ This worktree has uncommitted changes")
            (label :class "warning-detail" :halign "start" :wrap true
                   :text "Any uncommitted work will be lost. Consider committing or stashing changes first.")))
        (box
          :class "dialog-actions"
          :orientation "h"
          :space-evenly false
          :halign "end"
          (button :class "cancel-delete-button" :onclick "${worktreeDeleteCancelScript}/bin/worktree-delete-cancel" "Cancel")
          (button :class "confirm-delete-button" :onclick "${worktreeDeleteConfirmScript}/bin/worktree-delete-confirm &" "🗑 Delete")))))

  ;; App Delete Confirmation
  (defwidget app-delete-confirmation []
    (revealer
      :reveal app_deleting
      :transition "slidedown"
      :duration "200ms"
      (box
        :class "app-delete-confirmation-dialog"
        :orientation "v"
        :space-evenly false
        (box
          :class "dialog-header"
          :orientation "h"
          :space-evenly false
          (label :class "dialog-icon warning" :text "⚠️")
          (label :class "dialog-title" :halign "start" :text "Delete Application"))
        (label :class "app-name-display" :halign "start" :text "''${delete_app_display_name}")
        (label :class "warning-message" :halign "start" :wrap true
               :text "This action is permanent. The application will be removed from the registry. A NixOS rebuild is required to apply changes.")
        (revealer
          :reveal delete_app_is_pwa
          :transition "slidedown"
          :duration "150ms"
          (box
            :class "pwa-warning"
            :orientation "v"
            :space-evenly false
            (label :class "warning-icon" :halign "start" :text "⚠ This is a PWA (Progressive Web App)")
            (label :class "warning-detail" :halign "start" :wrap true
                   :text "After removing from registry, run pwa-uninstall to fully remove the PWA from Firefox.")))
        (revealer
          :reveal {delete_app_error != ""}
          :transition "slidedown"
          :duration "150ms"
          (label :class "error-message" :halign "start" :wrap true :text delete_app_error))
        (box
          :class "dialog-actions"
          :orientation "h"
          :space-evenly false
          :halign "end"
          (button :class "cancel-delete-app-button" :onclick "${appDeleteCancelScript}/bin/app-delete-cancel" "Cancel")
          (button :class "confirm-delete-app-button" :onclick "${appDeleteConfirmScript}/bin/app-delete-confirm" "🗑 Delete")))))
''
