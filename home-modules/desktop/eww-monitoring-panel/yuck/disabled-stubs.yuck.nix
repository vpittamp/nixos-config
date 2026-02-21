{ ... }:

''
  ;; Disabled View Stubs - These replace heavy widget implementations
  ;; Tabs 3-6 are hidden and these stubs prevent loading their full widget trees

  ;; Legacy compatibility: if an older path still renders apps-view at Tab 2,
  ;; route it to tailscale-view instead of showing an empty disabled stub.
  (defwidget apps-view []
    (tailscale-view))
  (defwidget app-card [app]
    (box))

  ;; Health View - DISABLED (Tab 3)
  (defwidget health-view []
    (box (label :text "Health view disabled")))
  (defwidget service-health-card [service]
    (box))

  ;; Events View - DISABLED (Tab 4)
  (defwidget events-view []
    (box :class "events-view-container" (label :text "Events view disabled")))
  (defwidget filter-checkbox [label var value]
    (box))

  ;; Traces View - DISABLED (Tab 5)
  (defwidget traces-view []
    (box (label :text "Traces view disabled")))
  (defwidget trace-card [trace]
    (box (label :text "Trace card disabled")))

  ;; Devices View - DISABLED (Tab 6)
  (defwidget devices-view []
    (box (label :text "Devices view disabled")))

  ;; Panel Footer - Timestamp display
  (defwidget panel-footer []
    (box
      :class "panel-footer"
      :orientation "h"
      :halign "center"
      (label
        :class "timestamp"
        :text "''${monitoring_data.timestamp_friendly ?: 'Initializing...'}")))

  (defwidget window-detail-view []
    (box :class "detail-view" (label :text "Detail view disabled")))

  (defwidget detail-row [label value]
    (box))

  (defwidget error-state []
    (box :class "error-state" (label :text "Error state")))

  (defwidget empty-state []
    (box :class "empty-state" (label :text "Empty state")))
''
