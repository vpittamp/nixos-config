{ ... }:

''
  (defwidget ai-diagnostics-view []
    (box
      :class "ai-diagnostics-container"
      :orientation "v"
      :space-evenly false
      :vexpand true
      (box
        :class "ai-diagnostics-header"
        :orientation "h"
        :space-evenly false
        (label :class "ai-diagnostics-title" :text "AI Monitor Diagnostics")
        (label :class "ai-diagnostics-updated"
          :text {"Updated " + (monitoring_data.timestamp_friendly ?: "now")}))
      (box
        :class "ai-diagnostics-grid"
        :orientation "v"
        :space-evenly false
        (label :class "ai-diagnostics-row"
          :text {"Focus success rate: " + (((monitoring_data.ai_monitor_metrics.focus_success_rate ?: 0.0) * 100.0) + "%")})
        (label :class "ai-diagnostics-row"
          :text {"Focus attempts: " + (monitoring_data.ai_monitor_metrics.focus_attempts ?: 0)})
        (label :class "ai-diagnostics-row"
          :text {"Focus successes: " + (monitoring_data.ai_monitor_metrics.focus_success ?: 0) + " · failures: " + (monitoring_data.ai_monitor_metrics.focus_fail ?: 0)})
        (label :class "ai-diagnostics-row"
          :text {"Active sessions: " + (monitoring_data.ai_monitor_metrics.active_sessions ?: 0) + " · working: " + (monitoring_data.ai_monitor_metrics.working_sessions ?: 0)})
        (label :class "ai-diagnostics-row"
          :text {"Attention: " + (monitoring_data.ai_monitor_metrics.attention_sessions ?: 0) + " · stale: " + (monitoring_data.ai_monitor_metrics.stale_sessions ?: 0)})
        (label :class "ai-diagnostics-row"
          :text {"Pinned: " + (monitoring_data.ai_monitor_metrics.pinned_sessions ?: 0)}))
      (box
        :class "ai-diagnostics-last-focus"
        :orientation "v"
        :space-evenly false
        (label
          :class "ai-diagnostics-subtitle"
          :text "Last Focus Event")
        (label
          :class "ai-diagnostics-line"
          :text {((monitoring_data.ai_monitor_metrics.last_focus.project ?: "") != "" ? (monitoring_data.ai_monitor_metrics.last_focus.project ?: "") : "n/a")
            + " · win " + (monitoring_data.ai_monitor_metrics.last_focus.window_id ?: "n/a")})
        (label
          :class "ai-diagnostics-line"
          :text {"mode " + (monitoring_data.ai_monitor_metrics.last_focus.execution_mode ?: "local")
            + " · " + (monitoring_data.ai_monitor_metrics.last_focus.status ?: "unknown")})
        (label
          :class "ai-diagnostics-line subtle"
          :text {(monitoring_data.ai_monitor_metrics.last_focus.timestamp ?: 0) > 0
            ? ("epoch " + (monitoring_data.ai_monitor_metrics.last_focus.timestamp ?: 0))
            : "no focus events yet"}))))
''
