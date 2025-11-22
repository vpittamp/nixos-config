# Feature Specification: Daemon Health Monitoring System

**Feature Branch**: `088-daemon-health-monitor`
**Created**: 2025-11-22
**Status**: Draft
**Input**: User description: "Monitor all critical NixOS/home-manager services and daemons centrally, with health indicators in Eww monitoring panel's Health tab. Remove legacy/unused daemons. Ensure system functionality persists across rebuilds and reboots."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quick Health Status Check (Priority: P1)

After a NixOS rebuild or system reboot, a user wants to verify that all critical services are running correctly without manually checking each service individually.

**Why this priority**: This is the most common scenario - users need immediate visibility into system health to detect issues before they impact workflow. This is the core value proposition and must work independently.

**Independent Test**: Can be fully tested by performing a NixOS rebuild, rebooting the system, opening the monitoring panel (Mod+M), switching to Health tab (Alt+4 or press 4), and verifying all service indicators show green/healthy status. Delivers immediate diagnostic value even without other features.

**Acceptance Scenarios**:

1. **Given** the system has just rebooted, **When** the user opens the monitoring panel and switches to the Health tab, **Then** all critical daemon status indicators appear with current health state (healthy/degraded/critical)
2. **Given** a daemon has stopped unexpectedly, **When** the user views the Health tab, **Then** the failed daemon shows a red/critical indicator with the service name clearly visible
3. **Given** all daemons are running normally, **When** the user views the Health tab, **Then** all indicators show green/healthy status with uptime information

---

### User Story 2 - Identify Failed Services After Rebuild (Priority: P1)

After a NixOS rebuild that activates new home-manager configuration, a user discovers some functionality is broken (e.g., workspace mode not working, top bar missing) and needs to quickly identify which daemon stopped.

**Why this priority**: This addresses the primary pain point described - losing functionality after config changes. Users need to immediately identify and restart failed services. This is critical for system usability.

**Independent Test**: Can be tested by intentionally breaking a service configuration (e.g., invalid path in service definition), running nixos-rebuild switch, then viewing the Health tab to verify the broken service is clearly flagged with actionable error information. Delivers diagnostic value independently.

**Acceptance Scenarios**:

1. **Given** a NixOS rebuild has completed with home-manager activation, **When** a daemon fails to start due to configuration error, **Then** the Health tab shows the daemon as critical with error details
2. **Given** the workspace-preview-daemon has stopped, **When** the user opens the Health tab, **Then** the service shows as stopped with timestamp of last known healthy state
3. **Given** multiple Eww services are down, **When** the user views the Health tab, **Then** each failed service appears separately with distinct health indicators

---

### User Story 3 - Restart Failed Services Quickly (Priority: P2)

A user identifies a failed daemon in the Health tab and wants to restart it without remembering the exact systemctl command or service name.

**Why this priority**: This enhances the diagnostic workflow by enabling remediation directly from the health panel. While less critical than detection (P1), it significantly improves user experience by reducing manual terminal work.

**Independent Test**: Can be tested by stopping a user service (systemctl --user stop eww-top-bar), viewing it as failed in Health tab, clicking a restart action button, and verifying the service restarts successfully. Delivers value independently without requiring other features.

**Acceptance Scenarios**:

1. **Given** a daemon shows critical status in the Health tab, **When** the user clicks a restart button next to the service, **Then** the daemon restarts and the indicator updates to healthy within 5 seconds
2. **Given** a system service (i3-project-daemon) has failed, **When** the user attempts to restart it from the Health tab, **Then** the system prompts for sudo privileges and restarts the service
3. **Given** a service restart fails due to configuration error, **When** the restart action completes, **Then** the Health tab displays the failure reason with link to service logs

---

### User Story 4 - Monitor Service Performance Metrics (Priority: P3)

A power user wants to monitor daemon resource usage (CPU, memory) and uptime to identify performance degradation or resource leaks over time.

**Why this priority**: This provides advanced monitoring capabilities for optimization and troubleshooting, but is not essential for basic health checking. Most users only need up/down status (P1/P2).

**Independent Test**: Can be tested by running the system for 24+ hours, viewing the Health tab, and verifying uptime, memory usage, and CPU metrics are displayed accurately for long-running daemons. Delivers performance insights independently.

**Acceptance Scenarios**:

1. **Given** daemons have been running for several hours, **When** the user views the Health tab, **Then** each service shows uptime in human-friendly format (e.g., "5h 23m")
2. **Given** a daemon is consuming excessive memory, **When** the user views the Health tab, **Then** the memory usage appears in yellow/warning state if above 80% of configured limit
3. **Given** a daemon has restarted multiple times, **When** the user views the Health tab, **Then** a restart counter appears indicating instability

---

### Edge Cases

- What happens when a daemon is intentionally disabled by the user (e.g., WayVNC on M1 in local-only mode)? Should show as "disabled" not "critical"
- How does the system handle transient failures (daemon restarts within 5 seconds)? Should debounce status updates to avoid flickering
- What happens when systemd socket activation means a service isn't running but is "ready"? Should detect socket-activated services as healthy
- How does monitoring handle headless vs hybrid mode differences (some services only active in specific modes)? Should conditionally display based on active monitor profile
- What happens when the monitoring script itself crashes or hangs? Should have watchdog/fallback to show "monitoring unavailable"
- How to handle legacy services that exist in systemd but are no longer used? Should exclude from monitoring list entirely (cleanup requirement)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST monitor health status of all Python-based daemons (i3-project-daemon, workspace-preview-daemon, sway-tree-monitor, sway-config-manager)
- **FR-002**: System MUST monitor health status of all Eww widget services (eww-top-bar, eww-workspace-bar, eww-monitoring-panel, eww-quick-panel)
- **FR-003**: System MUST monitor health status of core Sway-related services (swaync, sway-overview/sov, i3wsr, wayvnc instances)
- **FR-004**: System MUST monitor health status of application launcher services (elephant/Walker)
- **FR-005**: System MUST display service health state in the Eww monitoring panel Health tab using existing defpoll mechanism (5-second refresh interval)
- **FR-006**: System MUST categorize health states as: healthy (green), degraded (yellow), critical (red), disabled (gray), unknown (orange)
- **FR-007**: System MUST show service name, current status (active/inactive/failed), and uptime for each monitored daemon
- **FR-008**: System MUST detect and exclude legacy/unused services from monitoring list during implementation
- **FR-009**: System MUST provide per-service restart capability accessible from the Health tab
- **FR-010**: System MUST differentiate between system services (require sudo) and user services (no sudo) for restart actions
- **FR-011**: System MUST handle conditionally-enabled services (e.g., WayVNC disabled in local-only mode) by showing "disabled" state instead of "critical"
- **FR-012**: System MUST query service status via systemctl for user services and system services independently
- **FR-013**: System MUST detect socket-activated services (i3-project-daemon.socket) and show socket status as part of health check
- **FR-014**: System MUST update health data every 5 seconds via existing defpoll mechanism in monitoring_data.py --mode health
- **FR-015**: System MUST display memory usage and CPU quota for services with systemd resource limits configured
- **FR-016**: System MUST show last restart timestamp for services that have recently restarted
- **FR-017**: System MUST provide visual grouping of services by category (Core Daemons, UI Services, System Services, Optional Services)

### Key Entities *(include if feature involves data)*

- **ServiceHealth**: Represents health state of a single daemon/service
  - Attributes: service_name, display_name, status (active/inactive/failed/disabled), health_state (healthy/degraded/critical/disabled/unknown), uptime_seconds, memory_usage_mb, cpu_percent, last_restart_time, is_user_service (boolean), is_socket_activated (boolean), restart_count, category (core/ui/system/optional)
  - Relationships: Part of overall system health, grouped by category

- **ServiceCategory**: Logical grouping of related services
  - Attributes: category_name (Core Daemons/UI Services/System Services/Optional Services), services (list of ServiceHealth), healthy_count, total_count
  - Relationships: Contains multiple ServiceHealth entities

- **SystemHealth**: Overall health summary
  - Attributes: total_services, healthy_count, degraded_count, critical_count, disabled_count, last_update_timestamp, monitoring_functional (boolean)
  - Relationships: Aggregates all ServiceHealth entities

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can identify all failed daemons within 3 seconds of opening the Health tab (no need to run manual systemctl commands)
- **SC-002**: Service health status updates appear within 5 seconds of a daemon state change (matching existing defpoll interval)
- **SC-003**: Users can successfully restart a failed service from the Health tab with a single click/keystroke within 2 seconds
- **SC-004**: 100% of critical system daemons (i3-project-daemon, workspace-preview-daemon, eww services, swaync, elephant) are monitored and accurately reported
- **SC-005**: Zero legacy/unused services appear in the monitoring list after implementation cleanup
- **SC-006**: Health tab UI remains responsive with all service indicators visible without scrolling on standard display size (1080p/1200p)
- **SC-007**: System correctly distinguishes between disabled services (gray) and failed services (red) with 100% accuracy
- **SC-008**: Users can determine root cause of workflow issues (e.g., workspace mode broken = workspace-preview-daemon down) within 10 seconds

### Assumptions

- Users have sudo access configured for system service management (i3-project-daemon)
- Systemd is the service manager (NixOS standard)
- Existing monitoring_data.py --mode health infrastructure provides the query mechanism (no new backend needed, just enhance existing health query)
- Health tab UI in Eww monitoring panel already exists with placeholder health indicators (Feature 085)
- Users are familiar with Mod+M keybinding to open monitoring panel and Alt+4/4 to switch to Health tab
- Service names in monitoring list should match systemd unit names for consistency (e.g., "eww-top-bar" not "Eww Top Bar Widget")
- Restart actions will use systemctl commands (systemctl --user restart for user services, sudo systemctl restart for system services)
- Conditional service detection (e.g., WayVNC only in headless mode) can be determined by checking ~/.config/sway/monitor-profile.current or service enable state
- Memory/CPU limits are defined in service definitions (can be queried via systemd show)

### Out of Scope

- Real-time event-driven health updates (<5s latency) - use existing 5s defpoll interval
- Historical health metrics or graphing - only current state
- Log viewing/parsing from Health tab - users can click service name to open journal in terminal
- Service configuration editing from Health tab - use Nix configuration files
- Dependency graph visualization - show flat list grouped by category
- Alert notifications when services fail - may be future enhancement
- Custom health check scripts beyond systemd status - rely on systemd service state only
- Monitoring non-systemd processes - only systemd services
- Automatic service restart on failure detection - require explicit user action