# EWW Monitoring Panel: Tailscale Management Tab (Ryzen)

## Summary
Add a dedicated **Tailscale** tab to `eww-monitoring-panel` on `ryzen` using the existing tab/stack architecture and a hybrid data model:
1. Local machine and cluster operations via `tailscale`, `kubectl`, and `systemctl`.
2. Optional Tailnet API integration (OAuth client credentials) for cross-device metadata/actions.
3. Optional `tsnet`-based Go bridge service for future remote-safe management API consolidation.

This preserves current panel behavior, activates an existing disabled tab slot, and introduces guarded “safe ops” actions.

## Current-State Review
- Panel architecture already supports tab indices `0..6`.
- Active tabs: `0=Windows`, `1=Projects`.
- Disabled/stub tabs are present and can be activated incrementally.
- Data paths are already split between event-driven streams and gated polling.
- Existing wrapper/service-health patterns should be reused.

## Target Tab Mapping
- `0 = windows`
- `1 = projects`
- `2 = tailscale` (new active tab)
- `3 = apps` (stub)
- `4 = health` (stub)
- `5 = events` (stub)
- `6 = devices` (stub)

## Public Interface Changes

### 1) Backend mode in `monitoring_data.py`
Add `--mode tailscale` returning JSON:
- `status`: `ok|error|partial`
- `timestamp`
- `self`: host online state, Tailscale IPs, DNS name, tailnet, exit node, route state
- `service`: `tailscaled` state
- `peers`: counts and small sample
- `kubernetes`: context reachability + ingress/services/workloads summary
- `api`: optional Tailnet API state/data
- `actions`: capability booleans for UI action gating
- `error`: message on failure/degraded mode

### 2) Nix options (`programs.eww-monitoring-panel.tailscale`)
- `enable` (bool)
- `pollInterval` (string, default `8s`)
- `k8sNamespaces` (list)
- `enableApi` (bool)
- `apiCredentialsFile` (path)
- `enableTsnetBridge` (bool)
- `tsnetHostname` (string)

### 3) Action wrapper interface
Create `tailscale-tab-action <verb> [args...]` with verbs:
- `reconnect`
- `restart-service`
- `set-exit-node <node|none>`
- `k8s-rollout-restart <namespace> <deployment>`
- `k8s-restart-daemonset <namespace> <name>`
- optional API verbs (when enabled):
  - `api-refresh-devices`
  - `api-toggle-device-tags <deviceId> <tags-json>`

### 4) Optional tsnet bridge HTTP surface
- `GET /v1/health`
- `GET /v1/tailscale/summary`
- `GET /v1/k8s/summary`
- `POST /v1/actions/<verb>`

## Implementation Steps

1. **UI activation**
- Add `yuck/tailscale-view.yuck.nix`.
- Update `yuck/main.yuck.nix`:
  - visible tab button for Tailscale (Alt+3)
  - panel-body stack index `2` -> `(tailscale-view)`.

2. **Variables and polling**
- Add `defpoll tailscale_data` in `yuck/variables.yuck.nix`.
- Gate via `:run-while {current_view_index == 2}`.
- Keep conservative polling (`8s` default).

3. **Backend mode**
- Extend `home-modules/tools/i3_project_manager/cli/monitoring_data.py`:
  - parse `--mode tailscale`
  - add `query_tailscale_data()` with bounded timeouts:
    - `tailscale status --json`
    - `systemctl is-active tailscaled`
    - bounded `kubectl` summaries
  - return partial payload on sub-component errors.

4. **Script integration**
- Add `home-modules/desktop/eww-monitoring-panel/scripts/tailscale.nix`.
- Export actions and helper scripts in `scripts/default.nix`.
- Wire scripts through `default.nix` and Yuck includes.

5. **Optional Tailnet API integration**
- If `enableApi=true` and credentials exist:
  - acquire token
  - fetch devices/services metadata
- if unavailable, degrade gracefully to local-only mode.

6. **Optional tsnet bridge service**
- Add Go project at `home-modules/tools/tailscale-bridge/`.
- Package + user service: `i3pm-tailscale-bridge.service`.
- Default to localhost query path with fallback to local CLI.

7. **Styling**
- Add tab-specific SCSS blocks in `scss.nix`:
  - status cards
  - Kubernetes rows/badges
  - action bar/confirm patterns
- preserve existing Catppuccin visual language.

8. **Keybinding/docs alignment**
- Keep `Alt+3` routing to `current_view_index=2`.
- Update comments/docs where tab index labels changed.

## Testing Matrix

1. **UI/Nav**
- Alt+1/2/3 switch correctly.
- Dock/overlay mode unaffected.

2. **Data resilience**
- Missing `tailscale` or broken `kubectl` -> no crash; partial/error payload only.
- Long-running commands hit timeout and degrade gracefully.

3. **Action safety**
- All write actions require confirmation.
- Duplicate click lock/debounce works.
- Notifications reflect success/failure.

4. **Hybrid behavior**
- Works fully in local-only mode.
- Optional API enrichments appear when credentials valid.
- API token failures degrade without breaking tab.

5. **Service stability**
- `eww-monitoring-panel` still maintains single-window invariant.
- Optional bridge failures do not block panel startup.

6. **Ryzen K8s scope**
- Ingress + workload summaries load from selected context.
- Rollout restart action reflects status on subsequent poll.

## Assumptions / Defaults
- Primary target host is `ryzen`.
- `services.tailscale.enable = true`.
- Initial action scope is **Safe Ops** (guarded writes only).
- Kubernetes first-class scope is **Ingress + Workloads**.
- Tailnet API and tsnet bridge remain optional and non-blocking.

## Reference URLs
- https://tailscale.com/kb/1522/tsnet-server
- https://tailscale.com/kb/1215/oauth-clients
- https://tailscale.com/client-api
- https://tailscale.com/kb/1236/kubernetes-operator
- https://tailscale.com/kb/1441/kubernetes-operator-connector
- https://tailscale.com/kb/1444/kubernetes-operator-proxyclass
