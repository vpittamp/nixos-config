{ fallbackIconPath, ... }:

''
  (defwidget workspace-button [number_label workspace_name app_name icon_path icon_fallback workspace_id focused visible urgent pending empty ?compact]
    (button
      :class {
        "workspace-button "
        + (pending ? "pending " : "")
        + (focused ? "focused " : "")
        + ((visible && !focused) ? "visible " : "")
        + (urgent ? "urgent " : "")
        + ((icon_path != "") ? "has-icon " : "no-icon ")
        + (empty ? "empty " : "populated ")
        + ((compact ?: false) ? "compact" : "")
      }
      :tooltip { app_name != "" ? (number_label + " · " + app_name) : workspace_name }
      :onclick {
        "swaymsg workspace \""
        + replace(workspace_name, "\"", "\\\"")
        + "\""
      }
      (box :class "workspace-pill" :orientation "h" :space-evenly false :spacing {(compact ?: false) ? 1 : 3}
        (image :class "workspace-icon-image"
               :path {icon_path != "" ? icon_path : "${fallbackIconPath}"}
               :image-width 16
               :image-height 16)
        (label :class "workspace-number"
               :text number_label
               :visible {!((compact ?: false) && !focused && !urgent && !pending)})))
  )

  (defwidget workspace-separator []
    (box :class "workspace-separator"
      (box :class "separator-line")))

  (defwidget workspace-strip [output_label markup_var]
    (box :class "workspace-bar" :orientation "h" :space-evenly false :hexpand true
      (scroll :class "workspace-scroll" :hscroll true :vscroll false :hexpand true
        (box :class "workspace-strip"
             :orientation "h"
             :halign "center"
          (literal :content markup_var)))))
''
