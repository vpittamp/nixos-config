{ ... }:

''
  (defwidget workspace-button [number_label workspace_name app_name icon_path icon_fallback workspace_id focused visible urgent pending empty]
    (button
      :class {
        "workspace-button "
        + (pending ? "pending " : "")
        + (focused ? "focused " : "")
        + ((visible && !focused) ? "visible " : "")
        + (urgent ? "urgent " : "")
        + ((icon_path != "") ? "has-icon " : "no-icon ")
        + (empty ? "empty" : "populated")
      }
      :tooltip { app_name != "" ? (number_label + " · " + app_name) : workspace_name }
      :onclick {
        "swaymsg workspace \""
        + replace(workspace_name, "\"", "\\\"")
        + "\""
      }
      (box :class "workspace-pill" :orientation "h" :space-evenly false :spacing 3
        (image :class "workspace-icon-image"
               :path icon_path
               :image-width 16
               :image-height 16)
        (label :class "workspace-number" :text number_label)))
  )

  (defwidget workspace-strip [output_label markup_var]
    (box :class "workspace-bar"
      (label :class "workspace-output" :text output_label)
      (box :class "workspace-strip"
           :orientation "h"
           :halign "center"
            :spacing 3
        (literal :content markup_var))))
''

