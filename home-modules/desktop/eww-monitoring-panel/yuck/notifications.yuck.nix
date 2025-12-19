{ ... }:

''
  ;; Success Notification Toast
  (defwidget success-notification-toast []
    (revealer
      :reveal success_notification_visible
      :transition "slidedown"
      :duration "300ms"
      (box
        :class "notification-toast success"
        :orientation "h"
        :space-evenly false
        (label :class "notif-icon" :text "󰄬")
        (label :class "notif-message" :text success_notification :hexpand true :halign "start")
        (button :class "notif-close" :onclick "eww update success_notification_visible=false success_notification=\"\"" "󰅖"))))

  ;; Error Notification Toast
  (defwidget error-notification-toast []
    (revealer
      :reveal error_notification_visible
      :transition "slidedown"
      :duration "300ms"
      (box
        :class "notification-toast error"
        :orientation "h"
        :space-evenly false
        (label :class "notif-icon" :text "󰅖")
        (label :class "notif-message" :text error_notification :hexpand true :halign "start")
        (button :class "notif-close" :onclick "eww update error_notification_visible=false error_notification=\"\"" "󰅖"))))

  ;; Warning Notification Toast
  (defwidget warning-notification-toast []
    (revealer
      :reveal warning_notification_visible
      :transition "slidedown"
      :duration "300ms"
      (box
        :class "notification-toast warning"
        :orientation "h"
        :space-evenly false
        (label :class "notif-icon" :text "⚠️")
        (label :class "notif-message" :text warning_notification :hexpand true :halign "start")
        (button :class "notif-close" :onclick "eww update warning_notification_visible=false warning_notification=\"\"" "󰅖"))))
''
