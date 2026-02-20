{ pkgs, projectCreateOpenScript, projectCreateSaveScript, projectCreateCancelScript, worktreeCreateOpenScript, worktreeAutoPopulateScript, worktreeDeleteOpenScript, worktreeDeleteConfirmScript, worktreeDeleteCancelScript, appDeleteOpenScript, appDeleteConfirmScript, appDeleteCancelScript, ... }:

''
  ;; Project Edit Form
  (defwidget project-edit-form [project]
    (box
      :class "edit-form"
      :orientation "v"
      :space-evenly false
      (label
        :class "edit-form-header"
        :halign "start"
        :text "Edit Project")
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Display Name")
        (input
          :class "field-input"
          :value edit_form_display_name
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_display_name={}")
        (revealer
          :reveal {validation_state.errors.display_name != ""}
          :transition "slidedown"
          :duration "150ms"
          (label
            :class "field-error"
            :halign "start"
            :wrap true
            :text {validation_state.errors.display_name ?: ""})))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Icon (emoji or path)")
        (input
          :class "field-input"
          :value edit_form_icon
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_icon={}")
        (revealer
          :reveal {validation_state.errors.icon != ""}
          :transition "slidedown"
          :duration "150ms"
          (label
            :class "field-error"
            :halign "start"
            :wrap true
            :text {validation_state.errors.icon ?: ""})))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Directory (read-only)")
        (label
          :class "field-value-readonly"
          :halign "start"
          :wrap true
          :text edit_form_directory))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Scope")
        (box
          :class "radio-group"
          :orientation "h"
          :space-evenly false
          (button
            :class "''${edit_form_scope == 'scoped' ? 'radio-button selected' : 'radio-button'}"
            :onclick "eww update edit_form_scope='scoped'"
            "Scoped")
          (button
            :class "''${edit_form_scope == 'global' ? 'radio-button selected' : 'radio-button'}"
            :onclick "eww update edit_form_scope='global'"
            "Global")))
      (box
        :class "form-section"
        :orientation "v"
        :space-evenly false
        (box
          :class "form-field"
          :orientation "h"
          :space-evenly false
          (checkbox
            :checked edit_form_remote_enabled
            :onchecked "eww update edit_form_remote_enabled=true"
            :onunchecked "eww update edit_form_remote_enabled=false")
          (label
            :class "field-label"
            :text "Enable Remote SSH"))
        (revealer
          :reveal edit_form_remote_enabled
          :transition "slidedown"
          :duration "200ms"
          (box
            :class "remote-fields"
            :orientation "v"
            :space-evenly false
            (box
              :class "form-field"
              :orientation "v"
              :space-evenly false
              (label
                :class "field-label"
                :halign "start"
                :text "SSH Host")
              (input
                :class "field-input"
                :value edit_form_remote_host
                :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_remote_host={}")
              (revealer
                :reveal {validation_state.errors["remote.host"] != ""}
                :transition "slidedown"
                :duration "150ms"
                (label
                  :class "field-error"
                  :halign "start"
                  :wrap true
                  :text {validation_state.errors["remote.host"] ?: ""})))
            (box
              :class "form-field"
              :orientation "v"
              :space-evenly false
              (label
                :class "field-label"
                :halign "start"
                :text "SSH User")
              (input
                :class "field-input"
                :value edit_form_remote_user
                :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_remote_user={}")
              (revealer
                :reveal {validation_state.errors["remote.user"] != ""}
                :transition "slidedown"
                :duration "150ms"
                (label
                  :class "field-error"
                  :halign "start"
                  :wrap true
                  :text {validation_state.errors["remote.user"] ?: ""})))
            (box
              :class "form-field"
              :orientation "v"
              :space-evenly false
              (label
                :class "field-label"
                :halign "start"
                :text "Remote Directory")
              (input
                :class "field-input"
                :value edit_form_remote_dir
                :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_remote_dir={}")
              (revealer
                :reveal {validation_state.errors["remote.working_dir"] != ""}
                :transition "slidedown"
                :duration "150ms"
                (label
                  :class "field-error"
                  :halign "start"
                  :wrap true
                  :text {validation_state.errors["remote.working_dir"] ?: ""})))
            (box
              :class "form-field"
              :orientation "v"
              :space-evenly false
              (label
                :class "field-label"
                :halign "start"
                :text "SSH Port")
              (input
                :class "field-input"
                :value edit_form_remote_port
                :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_remote_port={}")
              (revealer
                :reveal {validation_state.errors["remote.port"] != ""}
                :transition "slidedown"
                :duration "150ms"
                (label
                  :class "field-error"
                  :halign "start"
                  :wrap true
                  :text {validation_state.errors["remote.port"] ?: ""}))))))
      (revealer
        :reveal {edit_form_error != ""}
        :transition "slidedown"
        :duration "200ms"
        (label
          :class "error-message"
          :halign "start"
          :wrap true
          :text edit_form_error))
      (box
        :class "form-actions"
        :orientation "h"
        :space-evenly false
        :halign "end"
        (button
          :class "cancel-button"
          :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update panel_focus_mode=false && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update editing_project_name=''' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_error='''"
          "Cancel")
        (button
          :class "''${save_in_progress ? 'save-button-loading' : (validation_state.valid ? 'save-button' : 'save-button-disabled')}"
          :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update save_in_progress=true && project-edit-save &"
          "''${save_in_progress ? 'Saving...' : 'Save'}"))))

  ;; Worktree Edit Form
  (defwidget worktree-edit-form [project]
    (box
      :class "edit-form worktree-edit-form"
      :orientation "v"
      :space-evenly false
      (label
        :class "edit-form-header"
        :halign "start"
        :text "Rename Worktree")
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "New Branch Name")
        (input
          :class "field-input"
          :value worktree_form_branch_name
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_branch_name='{}'"))
      (box
        :class "form-field readonly-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Current Qualified Name (read-only)")
        (label
          :class "field-readonly"
          :halign "start"
          :text {project.name ?: worktree_form_parent_project}))
      (box
        :class "form-field readonly-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Path (read-only)")
        (label
          :class "field-readonly"
          :halign "start"
          :limit-width 40
          :truncate true
          :tooltip worktree_form_path
          :text worktree_form_path))
      (box
        :class "form-field readonly-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Parent Project (read-only)")
        (label
          :class "field-readonly"
          :halign "start"
          :text worktree_form_parent_project))
      (revealer
        :reveal {edit_form_error != ""}
        :transition "slidedown"
        :duration "200ms"
        (label
          :class "error-message"
          :halign "start"
          :wrap true
          :text edit_form_error))
      (box
        :class "form-actions"
        :orientation "h"
        :space-evenly false
        :halign "end"
        (button
          :class "cancel-button"
          :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update panel_focus_mode=false && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update editing_project_name=''' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_error='''"
          "Cancel")
        (button
          :class "save-button"
          :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update save_in_progress=true && worktree-edit-save ''${project.name} &"
          "Save"))))

  ;; Worktree Create Form
  (defwidget worktree-create-form [parent_project]
    (box
      :class "edit-form worktree-create-form"
      :orientation "v"
      :space-evenly false
      (label
        :class "edit-form-header"
        :halign "start"
        :text "Create Worktree")
      (box
        :class "form-field readonly-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Parent Project")
        (label
          :class "field-readonly"
          :halign "start"
          :text parent_project))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Feature Description *")
        (input
          :class "field-input"
          :value worktree_form_description
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_description='{}' && worktree-auto-populate '{}' &")
        (label
          :class "field-hint"
          :halign "start"
          :text "e.g., Add user authentication system"))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Branch Name")
        (input
          :class "field-input"
          :value worktree_form_branch_name
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_branch_name='{}' && worktree-update-path '{}' &"
          :tooltip "Auto-generated from description, editable")
        (label
          :class "field-hint"
          :halign "start"
          :text "Auto-generated suggestion; editable to any valid git branch name"))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Base Branch")
        (input
          :class "field-input"
          :value worktree_form_base_branch
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_base_branch='{}'")
        (label
          :class "field-hint"
          :halign "start"
          :text "Branch to create from (e.g., main, develop)"))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Worktree Path")
        (input
          :class "field-input"
          :value worktree_form_path
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_path='{}'"
          :tooltip "Auto-generated from branch name, editable")
        (label
          :class "field-hint"
          :halign "start"
          :text "Auto-filled from branch name"))
      (box
        :class "form-field form-field-checkbox"
        :orientation "h"
        :space-evenly false
        (checkbox
          :checked worktree_form_remote_enabled
          :onchecked "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_enabled=true"
          :onunchecked "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_enabled=false")
        (label
          :class "field-label checkbox-label"
          :halign "start"
          :text "Configure SSH remote profile"))
      (revealer
        :reveal worktree_form_remote_enabled
        :transition "slidedown"
        :duration "200ms"
        (box
          :class "remote-fields"
          :orientation "v"
          :space-evenly false
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "SSH Host")
            (input
              :class "field-input"
              :value worktree_form_remote_host
              :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_host={}"))
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "SSH User")
            (input
              :class "field-input"
              :value worktree_form_remote_user
              :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_user={}"))
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Remote Directory")
            (input
              :class "field-input"
              :value worktree_form_remote_dir
              :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_dir={}")
            (label
              :class "field-hint"
              :halign "start"
              :text "Auto-filled from branch name, editable"))
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "SSH Port")
            (input
              :class "field-input"
              :value worktree_form_remote_port
              :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_port={}"))))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Display Name")
        (input
          :class "field-input"
          :value edit_form_display_name
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_display_name='{}'"
          :tooltip "Auto-generated from description, editable")
        (label
          :class "field-hint"
          :halign "start"
          :text "Auto-filled: NNN - Description"))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Icon")
        (input
          :class "field-input"
          :value edit_form_icon
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_icon='{}'"))
      (revealer
        :reveal {edit_form_error != ""}
        :transition "slidedown"
        :duration "200ms"
        (label
          :class "error-message"
          :halign "start"
          :wrap true
          :text edit_form_error))
      (box
        :class "form-actions"
        :orientation "h"
        :space-evenly false
        :halign "end"
        (button
          :class "cancel-button"
          :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update panel_focus_mode=false && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_creating=false && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_description=''' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_branch_name=''' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_base_branch='main' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_path=''' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_parent_project=''' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_repo_path=''' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_enabled=false && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_host='ryzen' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_user=''' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_dir=''' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_port='22' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update worktree_form_remote_base=''' && eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update edit_form_error='''"
          "Cancel")
        (button
          :class "save-button"
          :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update save_in_progress=true && worktree-create &"
          "Create"))))

  ;; Project Create Form
  (defwidget project-create-form []
    (box
      :class "edit-form project-create-form"
      :orientation "v"
      :space-evenly false
      (label
        :class "edit-form-header"
        :halign "start"
        :text "Create New Project")
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Project Name *")
        (input
          :class "field-input"
          :value create_form_name
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update create_form_name={}")
        (label
          :class "field-hint"
          :halign "start"
          :text "Lowercase, hyphens only (e.g., my-project)"))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Display Name")
        (input
          :class "field-input"
          :value create_form_display_name
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update create_form_display_name={}"))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Icon")
        (input
          :class "field-input icon-input"
          :value create_form_icon
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update create_form_icon={}"))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Working Directory *")
        (input
          :class "field-input"
          :value create_form_working_dir
          :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update create_form_working_dir={}")
        (label
          :class "field-hint"
          :halign "start"
          :text "Absolute path to project directory"))
      (box
        :class "form-field"
        :orientation "v"
        :space-evenly false
        (label
          :class "field-label"
          :halign "start"
          :text "Scope")
        (box
          :class "scope-buttons"
          :orientation "h"
          :space-evenly false
          (button
            :class "scope-btn ''${create_form_scope == 'scoped' ? 'active' : '''}"
            :onclick "eww update create_form_scope='scoped'"
            "Scoped")
          (button
            :class "scope-btn ''${create_form_scope == 'global' ? 'active' : '''}"
            :onclick "eww update create_form_scope='global'"
            "Global"))) 
      (box
        :class "form-field remote-toggle"
        :orientation "h"
        :space-evenly false
        (checkbox
          :checked create_form_remote_enabled
          :onchecked "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update create_form_remote_enabled=true"
          :onunchecked "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update create_form_remote_enabled=false")
        (label
          :class "field-label"
          :halign "start"
          :text "Remote Project (SSH)"))
      (revealer
        :reveal create_form_remote_enabled
        :transition "slidedown"
        :duration "200ms"
        (box
          :class "remote-fields"
          :orientation "v"
          :space-evenly false
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "SSH Host *")
            (input
              :class "field-input"
              :value create_form_remote_host
              :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update create_form_remote_host={}")
            (label
              :class "field-hint"
              :halign "start"
              :text "e.g., hetzner-sway.tailnet"))
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "SSH User *")
            (input
              :class "field-input"
              :value create_form_remote_user
              :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update create_form_remote_user={}"))
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "Remote Directory *")
            (input
              :class "field-input"
              :value create_form_remote_dir
              :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update create_form_remote_dir={}")
            (label
              :class "field-hint"
              :halign "start"
              :text "Absolute path on remote (e.g., /home/user/project)"))
          (box
            :class "form-field"
            :orientation "v"
            :space-evenly false
            (label
              :class "field-label"
              :halign "start"
              :text "SSH Port")
            (input
              :class "field-input port-input"
              :value create_form_remote_port
              :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update create_form_remote_port={}"))))
      (revealer
        :reveal {create_form_error != ""}
        :transition "slidedown"
        :duration "200ms"
        (label
          :class "error-message"
          :halign "start"
          :wrap true
          :text create_form_error))
      (box
        :class "form-actions"
        :orientation "h"
        :space-evenly false
        :halign "end"
        (button
          :class "cancel-button"
          :onclick "${projectCreateCancelScript}/bin/project-create-cancel"
          "Cancel")
        (button
          :class "''${save_in_progress ? 'save-button-loading' : 'save-button'}"
          :onclick "${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update save_in_progress=true && ${projectCreateSaveScript}/bin/project-create-save &"
          "''${save_in_progress ? 'Creating...' : 'Create'}"))))
''
