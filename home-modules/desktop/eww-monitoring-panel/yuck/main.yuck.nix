{ primaryOutput, panelWidth, toggleDockModeScript, ... }:

''
  ;; Feature 125: Two window definitions for overlay vs docked modes
  ;; Only one is open at a time, controlled by toggle-panel-dock-mode script
  ;; Both share the same monitoring-panel-content widget

  ;; Overlay mode window (default) - Floats over windows, no space reservation
  (defwindow monitoring-panel-overlay
    :monitor "${primaryOutput}"
    :geometry (geometry
      :anchor "right center"
      :x "0px"
      :y "0px"
      :width "${toString panelWidth}px"
      :height "90%")
    :namespace "eww-monitoring-panel"
    :stacking "fg"
    :focusable "ondemand"
    :exclusive false
    :windowtype "dock"
    (monitoring-panel-content))

  ;; Docked mode window - Reserves screen space via exclusive zone
  (defwindow monitoring-panel-docked
    :monitor "${primaryOutput}"
    :geometry (geometry
      :anchor "right center"
      :x "0px"
      :y "0px"
      :width "${toString panelWidth}px"
      :height "90%")
    :namespace "eww-monitoring-panel"
    :stacking "fg"
    :focusable "ondemand"
    :exclusive true
    :reserve (struts :side "right" :distance "${toString (panelWidth + 4)}px")
    :windowtype "dock"
    (monitoring-panel-content))

  ;; Main panel content widget with keyboard navigation
  (defwidget monitoring-panel-content []
    (revealer
      :transition "crossfade"
      :reveal {panel_visible}
      :duration "150ms"
      (eventbox
        :cursor "default"
        (box
          :class {panel_focused ? "panel-container focused" : "panel-container"}
          :style "background-color: rgba(30, 30, 46, ''${panel_dock_mode ? '1.0' : '0.85'});"
          :orientation "v"
          :space-evenly false
          (panel-header)
          (panel-body)
          (panel-footer)
          (conflict-resolution-dialog)
          (success-notification-toast)
          (error-notification-toast)
          (warning-notification-toast))))

  ;; Panel header with tab navigation
  (defwidget panel-header []
    (box
      :class "panel-header"
      :orientation "v"
      :space-evenly false
      (box
        :class "tabs"
        :orientation "h"
        :space-evenly true
        (eventbox
          :cursor "pointer"
          :onclick "eww --config $HOME/.config/eww-monitoring-panel update current_view_index=0"
          (button
            :class "tab ''${current_view_index == 0 ? 'active' : ""}"
            :tooltip "Windows (Alt+1)"
            "󰖯"))
        (eventbox
          :cursor "pointer"
          :onclick "eww --config $HOME/.config/eww-monitoring-panel update current_view_index=1"
          (button
            :class "tab ''${current_view_index == 1 ? 'active' : ""}"
            :tooltip "Projects (Alt+2)"
            "󱂬"))
        (eventbox
          :cursor "pointer"
          :onclick "${toggleDockModeScript}/bin/toggle-panel-dock-mode &"
          (button
            :class "tab mode-toggle"
            :tooltip "Toggle dock mode (Mod+Shift+M)"
            "󰔡")))))

  ;; Panel body - uses stack widget for proper tab switching
  (defwidget panel-body []
    (stack
      :selected current_view_index
      :transition "none"
      :vexpand true
      :same-size false
      (box :class "view-container" :vexpand true (windows-view))
      (box :class "view-container" :vexpand true (projects-view))
      (box :class "view-container" :vexpand true (label :text "Apps view disabled"))
      (box :class "view-container" :vexpand true (label :text "Health view disabled"))
      (box :class "view-container" :vexpand true (label :text "Events view disabled"))
      (box :class "view-container" :vexpand true (label :text "Traces view disabled"))
      (box :class "view-container" :vexpand true (label :text "Devices view disabled"))))

  (include "./variables.yuck")
  (include "./windows-view.yuck")
  (include "./projects-view.yuck")
  (include "./forms.yuck")
  (include "./dialogs.yuck")
  (include "./notifications.yuck")
  (include "./popups.yuck")
  (include "./disabled-stubs.yuck")
''
