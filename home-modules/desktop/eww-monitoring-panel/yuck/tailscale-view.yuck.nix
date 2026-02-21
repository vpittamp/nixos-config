{ pkgs, tailscaleTabActionScript, ... }:

''
  (defwidget tailscale-view []
    (scroll
      :vscroll true
      :hscroll false
      :vexpand true
      (box
        :class "content-container tailscale-view"
        :orientation "v"
        :space-evenly false
        :spacing 10
        (box
          :visible {!tailscale_tab_enabled}
          :class "tailscale-card tailscale-disabled"
          (label :text "Tailscale tab disabled for this host"))
        (box
          :visible {tailscale_tab_enabled}
          :orientation "v"
          :space-evenly false
          :spacing 10
          (box
            :class {"tailscale-card tailscale-status " + (tailscale_data.status == "ok" ? "ok" : (tailscale_data.status == "partial" ? "partial" : "error"))}
            :orientation "v"
            :space-evenly false
            (box
              :orientation "h"
              :space-evenly false
              (label :class "tailscale-title" :text "Tailscale")
              (label :class "tailscale-pill" :text {tailscale_data.status}))
            (label :class "tailscale-meta" :text {"Host: " + (tailscale_data.self.hostname ?: "unknown")})
            (label :class "tailscale-meta" :text {"DNS: " + (tailscale_data.self.dns_name ?: "unknown")})
            (label :class "tailscale-meta" :text {"Online: " + ((tailscale_data.self.online ?: false) ? "yes" : "no") + " • Backend: " + (tailscale_data.self.backend_state ?: "unknown")})
            (label :class "tailscale-meta" :text {"IP: " + jq(tailscale_data.self.tailscale_ips ?: [], ".[0] // \"n/a\"")})
            (label :class "tailscale-meta" :text {"Tailnet: " + (tailscale_data.self.tailnet ?: "unknown")})
            (label
              :visible {(tailscale_data.error ?: "") != ""}
              :class "tailscale-error"
              :text {"Error: " + (tailscale_data.error ?: "")}))

          (box
            :class "tailscale-card tailscale-peers"
            :orientation "v"
            :space-evenly false
            (label :class "tailscale-subtitle" :text "Peers")
            (label
              :class "tailscale-meta"
              :text {"Total: " + (tailscale_data.peers.total ?: 0) + " • Online: " + (tailscale_data.peers.online ?: 0) + " • Offline: " + (tailscale_data.peers.offline ?: 0)})
            (for peer in {tailscale_data.peers.sample ?: []}
              (box
                :class "tailscale-peer-row"
                :orientation "h"
                :space-evenly false
                (label :class "tailscale-peer-host" :text {peer.hostname ?: "unknown"})
                (label :class {(peer.online ?: false) ? "tailscale-peer-online" : "tailscale-peer-offline"} :text {(peer.online ?: false) ? "online" : "offline"}))))

          (box
            :class "tailscale-card tailscale-k8s"
            :orientation "v"
            :space-evenly false
            (label :class "tailscale-subtitle" :text "Kubernetes")
            (label :class "tailscale-meta" :text {"Available: " + ((tailscale_data.kubernetes.available ?: false) ? "yes" : "no")})
            (label :class "tailscale-meta" :text {"Context: " + (tailscale_data.kubernetes.context ?: "none")})
            (label :class "tailscale-meta" :text {"Namespaces: " + (tailscale_data.kubernetes.namespace_scope ?: "all")})
            (label :class "tailscale-meta" :text {"Ingress: " + (tailscale_data.kubernetes.ingress_count ?: 0) + " • Services: " + (tailscale_data.kubernetes.service_count ?: 0)})
            (label :class "tailscale-meta" :text {"Deployments: " + (tailscale_data.kubernetes.deployment_count ?: 0) + " • DaemonSets: " + (tailscale_data.kubernetes.daemonset_count ?: 0)})
            (label :class "tailscale-meta" :text {"Pods: " + (tailscale_data.kubernetes.pod_count ?: 0)})
            (label
              :visible {(tailscale_data.kubernetes.error ?: "") != ""}
              :class "tailscale-error"
              :text {"K8s: " + (tailscale_data.kubernetes.error ?: "")}))

          (box
            :visible {tailscale_confirm_action != ""}
            :class "tailscale-confirm-banner"
            (label :text {"Confirm pending: " + tailscale_confirm_action + " (click again within 5s)"}))

          (box
            :class "tailscale-card tailscale-actions"
            :orientation "v"
            :space-evenly false
            (label :class "tailscale-subtitle" :text "Actions")
            (box
              :class "tailscale-input-row"
              :orientation "h"
              :space-evenly false
              (input
                :class "tailscale-input"
                :hexpand true
                :value tailscale_action_namespace
                :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update tailscale_action_namespace={}"
                :tooltip "Namespace")
              (input
                :class "tailscale-input"
                :hexpand true
                :value tailscale_action_target
                :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update tailscale_action_target={}"
                :tooltip "Deployment or DaemonSet name"))
            (box
              :class "tailscale-actions-row"
              :orientation "h"
              :space-evenly false
              (button
                :class {tailscale_action_in_progress ? "tailscale-action-btn disabled" : "tailscale-action-btn"}
                :visible {tailscale_data.actions.reconnect ?: false}
                :onclick {tailscale_action_in_progress ? "" : "${tailscaleTabActionScript}/bin/tailscale-tab-action reconnect &"}
                :tooltip "Rebind tailscale transport (double click to confirm)"
                "Reconnect")
              (button
                :class {tailscale_action_in_progress ? "tailscale-action-btn disabled" : "tailscale-action-btn"}
                :visible {tailscale_data.actions.k8s_rollout_restart ?: false}
                :onclick {tailscale_action_in_progress ? "" : "${tailscaleTabActionScript}/bin/tailscale-tab-action k8s-rollout-restart &"}
                :tooltip "Rollout restart deployment (double click to confirm)"
                "Restart Deploy")
              (button
                :class {tailscale_action_in_progress ? "tailscale-action-btn disabled" : "tailscale-action-btn"}
                :visible {tailscale_data.actions.k8s_restart_daemonset ?: false}
                :onclick {tailscale_action_in_progress ? "" : "${tailscaleTabActionScript}/bin/tailscale-tab-action k8s-restart-daemonset &"}
                :tooltip "Rollout restart daemonset (double click to confirm)"
                "Restart DS")))))))
''
