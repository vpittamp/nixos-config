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

          ;; === Card 1: Status (with copy actions for DNS/IP) ===
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
            (box
              :class "tailscale-copyable-row"
              :orientation "h"
              :space-evenly false
              (label :class "tailscale-meta" :hexpand true :text {"DNS: " + (tailscale_data.self.dns_name ?: "unknown")})
              (eventbox
                :cursor "pointer"
                :onclick {"echo -n '" + (tailscale_data.self.dns_name ?: "") + "' | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update success_notification='Copied DNS' success_notification_visible=true && (sleep 2 && ${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update success_notification_visible=false) &"}
                :tooltip "Copy DNS name"
                (label :class "tailscale-copy-btn" :text "󰆏")))
            (box
              :class "tailscale-copyable-row"
              :orientation "h"
              :space-evenly false
              (label :class "tailscale-meta" :hexpand true :text {"IP: " + (tailscale_data.self.ip ?: "n/a")})
              (eventbox
                :cursor "pointer"
                :onclick {"echo -n '" + (tailscale_data.self.ip ?: "") + "' | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update success_notification='Copied IP' success_notification_visible=true && (sleep 2 && ${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update success_notification_visible=false) &"}
                :tooltip "Copy IP address"
                (label :class "tailscale-copy-btn" :text "󰆏")))
            (label :class "tailscale-meta" :text {"Online: " + ((tailscale_data.self.online ?: false) ? "yes" : "no") + " • Backend: " + (tailscale_data.self.backend_state ?: "unknown")})
            (label :class "tailscale-meta" :text {"Tailnet: " + (tailscale_data.self.tailnet ?: "unknown")})
            (label
              :visible {(tailscale_data.error ?: "") != ""}
              :class "tailscale-error"
              :text {"Error: " + (tailscale_data.error ?: "")}))

          ;; === Card 2: Peers (search, filter pills, expandable rows, copy) ===
          (box
            :class "tailscale-card tailscale-peers"
            :orientation "v"
            :space-evenly false
            ;; Header with summary counts
            (box
              :orientation "h"
              :space-evenly false
              (label :class "tailscale-subtitle" :hexpand true :text "Peers")
              (label :class "tailscale-filter-count"
                :text {(tailscale_data.peers.total ?: 0) + " total • " + (tailscale_data.peers.direct ?: 0) + " direct"}))
            ;; Search bar
            (box
              :class "tailscale-filter-row"
              :orientation "h"
              :space-evenly false
              (box
                :class "filter-input-container"
                :orientation "h"
                :space-evenly false
                :hexpand true
                (label :class "filter-icon" :text "󰍉")
                (input
                  :class "tailscale-filter-input"
                  :hexpand true
                  :value tailscale_peer_filter
                  :onchange "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update tailscale_peer_filter={}"
                  :timeout "100ms")
                (button
                  :class "filter-clear-button"
                  :visible {tailscale_peer_filter != ""}
                  :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update 'tailscale_peer_filter='"
                  :tooltip "Clear filter"
                  "󰅖")))
            ;; Quick filter pills
            (box
              :class "tailscale-quick-filters"
              :orientation "h"
              :space-evenly false
              :spacing 4
              (button
                :class {tailscale_quick_filter == "all" ? "tailscale-quick-pill active" : "tailscale-quick-pill"}
                :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update tailscale_quick_filter=all"
                {"All: " + (tailscale_data.peers.total ?: 0)})
              (button
                :class {tailscale_quick_filter == "online" ? "tailscale-quick-pill active" : "tailscale-quick-pill"}
                :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update tailscale_quick_filter=online"
                {"On: " + (tailscale_data.peers.online ?: 0)})
              (button
                :class {tailscale_quick_filter == "offline" ? "tailscale-quick-pill active" : "tailscale-quick-pill"}
                :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update tailscale_quick_filter=offline"
                {"Off: " + (tailscale_data.peers.offline ?: 0)})
              (button
                :class {tailscale_quick_filter == "tagged" ? "tailscale-quick-pill active" : "tailscale-quick-pill"}
                :onclick "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update tailscale_quick_filter=tagged"
                {"Tag: " + (tailscale_data.peers.tagged ?: 0)}))
            ;; Peer list
            (for peer in {tailscale_data.peers.all ?: []}
              (box
                :visible {
                  (tailscale_quick_filter == "all"
                   || (tailscale_quick_filter == "online" && (peer.online ?: false))
                   || (tailscale_quick_filter == "offline" && !(peer.online ?: false))
                   || (tailscale_quick_filter == "tagged" && (peer.is_tagged ?: false)))
                  && (tailscale_peer_filter == ""
                      || matches(peer.hostname ?: "", "(?i).*" + tailscale_peer_filter + ".*")
                      || matches(peer.dns_name ?: "", "(?i).*" + tailscale_peer_filter + ".*")
                      || matches(peer.ip ?: "", "(?i).*" + tailscale_peer_filter + ".*")
                      || matches(peer.tags_str ?: "", "(?i).*" + tailscale_peer_filter + ".*"))}
                :orientation "v"
                :space-evenly false
                ;; Collapsed peer row
                (box
                  :class "tailscale-peer-row"
                  :orientation "h"
                  :space-evenly false
                  (label
                    :class {(peer.online ?: false) ? "tailscale-dot-online" : "tailscale-dot-offline"}
                    :text "●")
                  (eventbox
                    :cursor "pointer"
                    :hexpand true
                    :onclick {tailscale_expanded_peer == (peer.hostname ?: "")
                      ? "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update 'tailscale_expanded_peer='"
                      : "eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update 'tailscale_expanded_peer=" + (peer.hostname ?: "") + "'"}
                    (label
                      :class "tailscale-peer-host"
                      :halign "start"
                      :text {peer.hostname ?: "unknown"}))
                  (label
                    :class {(peer.connection ?: "relay") == "direct" ? "tailscale-conn-direct" : "tailscale-conn-relay"}
                    :text {(peer.connection ?: "relay") == "direct" ? "direct" : ("relay:" + (peer.relay ?: "?"))})
                  (eventbox
                    :cursor "pointer"
                    :onclick {"echo -n '" + (peer.ip ?: "") + "' | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update success_notification='Copied IP' success_notification_visible=true && (sleep 2 && ${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update success_notification_visible=false) &"}
                    :tooltip {"Copy IP: " + (peer.ip ?: "")}
                    (label :class "tailscale-copy-btn" :text "󰆏"))
                  (eventbox
                    :cursor "pointer"
                    :onclick {"echo -n '" + (peer.dns_name ?: "") + "' | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update success_notification='Copied DNS' success_notification_visible=true && (sleep 2 && ${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel update success_notification_visible=false) &"}
                    :tooltip {"Copy DNS: " + (peer.dns_name ?: "")}
                    (label :class "tailscale-copy-btn" :text "󰆏")))
                ;; Expanded detail (revealer)
                (revealer
                  :transition "slidedown"
                  :reveal {tailscale_expanded_peer == (peer.hostname ?: "")}
                  :duration "150ms"
                  (box
                    :class "tailscale-peer-detail"
                    :orientation "v"
                    :space-evenly false
                    :spacing 2
                    (box :orientation "h" :space-evenly false
                      (label :class "tailscale-detail-label" :text "DNS  ")
                      (label :class "tailscale-detail-value" :text {peer.dns_name ?: "n/a"}))
                    (box :orientation "h" :space-evenly false
                      (label :class "tailscale-detail-label" :text "IP   ")
                      (label :class "tailscale-detail-value" :text {(peer.ip ?: "n/a") + ((peer.ip6 ?: "") != "" ? (" / " + (peer.ip6 ?: "")) : "")}))
                    (box :orientation "h" :space-evenly false
                      (label :class "tailscale-detail-label" :text "OS   ")
                      (label :class "tailscale-detail-value" :text {(peer.os ?: "?") + " • " + ((peer.connection ?: "relay") == "direct" ? ("Direct: " + (peer.cur_addr ?: "")) : ("Relay: " + (peer.relay ?: "?")))}))
                    (box :orientation "h" :space-evenly false
                      (label :class "tailscale-detail-label" :text "Tags ")
                      (label :class "tailscale-detail-value" :text {(peer.tags_str ?: "") == "" ? "(none)" : (peer.tags_str ?: "")}))
                    (box :orientation "h" :space-evenly false
                      (label :class "tailscale-detail-label" :text "Key  ")
                      (label :class "tailscale-detail-value" :text {(peer.key_expiry ?: "") == "" ? "no expiry" : (peer.key_expiry ?: "")})))))))

          ;; === Card 3: Kubernetes (unchanged) ===
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

          ;; === Confirm banner (unchanged) ===
          (box
            :visible {tailscale_confirm_action != ""}
            :class "tailscale-confirm-banner"
            (label :text {"Confirm pending: " + tailscale_confirm_action + " (click again within 5s)"}))

          ;; === Card 4: Actions (unchanged) ===
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
