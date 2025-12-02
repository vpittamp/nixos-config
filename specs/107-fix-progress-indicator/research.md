# Research: Fix Progress Indicator Focus State and Event Efficiency

**Date**: 2025-12-01 | **Feature**: 107-fix-progress-indicator

## Research Questions

### R1: How should badge display distinguish focused vs unfocused windows?

**Decision**: Add `is_focused` comparison to badge CSS class in Eww widget, combining existing `window.focused` with badge state visibility.

**Rationale**:
- Window focus state already exists in monitoring data (`window.focused` boolean at line 958 in `monitoring_data.py`)
- Eww widget already has access to this field via `{window.focused}` in window rendering
- Badge visibility currently uses only badge state: `{(window.badge?.count ?: "") != "" || (window.badge?.state ?: "") == "working"}`
- **Missing**: Badge CSS class should include focus-aware styling (dimmed/muted when focused)

**Implementation**:
```lisp
;; Current (Feature 095):
:class {"badge badge-notification" + ((window.badge?.state ?: "stopped") == "working" ? " badge-working" : " badge-stopped")}

;; Proposed (Feature 107):
:class {"badge badge-notification"
  + ((window.badge?.state ?: "stopped") == "working" ? " badge-working" : " badge-stopped")
  + (window.focused ? " badge-focused-window" : "")}
```

```css
/* Feature 107: Dimmed badge when window is already focused */
.badge-notification.badge-focused-window {
  opacity: 0.4;
  box-shadow: none;  /* Remove glow effect */
  filter: grayscale(50%);
}
```

**Alternatives Considered**:
- **Hide badge entirely when focused**: Rejected - user would lose awareness that notification occurred
- **Different icon for focused**: Added complexity with minimal value - dimming is universally understood

---

### R2: Why are hooks using file-based state instead of IPC?

**Decision**: Current file-based approach was intentional fallback for reliability; IPC client script exists but hooks don't use it.

**Root Cause Analysis**:
- `badge-ipc-client.sh` exists with full JSON-RPC support (lines 1-183)
- Hooks (`prompt-submit-notification.sh`, `stop-notification.sh`) use file-based approach:
  ```bash
  BADGE_STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
  cat > "$BADGE_FILE" <<EOF
  {"window_id": $WINDOW_ID, "state": "working", ...}
  EOF
  ```
- Reason: During Feature 095 implementation, file-based was simpler for MVP

**Decision**: Migrate hooks to use IPC with file fallback.

**Implementation Strategy**:
1. Hook scripts attempt IPC first via `badge-ipc-client.sh`
2. If IPC fails (socket not found, timeout), fall back to file-based
3. Daemon reads from IPC primarily, checks files on initial load and periodically as cleanup

**Updated Hook Pattern**:
```bash
# Try IPC first (fast path)
if [ -S "/run/i3-project-daemon/ipc.sock" ]; then
    if badge-ipc create "$WINDOW_ID" "claude-code" >/dev/null 2>&1; then
        exit 0  # Success via IPC
    fi
fi

# Fallback to file-based (reliability path)
BADGE_STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
mkdir -p "$BADGE_STATE_DIR"
cat > "$BADGE_STATE_DIR/$WINDOW_ID.json" <<EOF
{"window_id": $WINDOW_ID, "state": "working", "source": "claude-code", "timestamp": $(date +%s)}
EOF
```

---

### R3: How to optimize spinner animation updates?

**Decision**: Decouple spinner frame from full monitoring data refresh using a separate Eww `defvar`.

**Current Problem** (Feature 095):
- When "working" badge exists, `monitoring_data.py` polls every 50ms
- Each poll triggers full `query_monitoring_data()` → JSON serialize → Eww update
- Spinner changes every 120ms but system refreshes every 50ms = 20 updates/second
- Full refresh involves daemon IPC, tree transformation, badge loading

**Proposed Solution**:
1. Add separate Eww variable `(defvar spinner_frame "⠋")`
2. Spinner update only changes this single variable (no full data refresh)
3. Badge widget reads from `spinner_frame` var instead of `monitoring_data.spinner_frame`
4. Animation driven by simple timer script (outside deflisten)

**Implementation**:
```lisp
;; New spinner variable (updated independently)
(defvar spinner_frame "⠋")

;; Animation script (runs as background process when working badge exists)
(defpoll _spinner_poll
  :interval "120ms"
  :run-while {monitoring_data.has_working_badge}
  `echo "${SPINNER_FRAMES[$(($(date +%s%3N) / 120 % 10))]}"`
  :onchange "eww update spinner_frame=$value")

;; Widget uses spinner_frame var
(label
  :class "badge badge-notification badge-working"
  :text {spinner_frame}
  :visible {(window.badge?.state ?: "") == "working"})
```

**Estimated Performance Impact**:
- Current: 20 full updates/sec during animation → ~20 daemon IPC calls/sec
- Proposed: 8-10 spinner-only updates/sec → 0 daemon IPC calls/sec during animation
- CPU reduction: ~90% during "working" state

**Alternative Considered**:
- **CSS animation**: GTK CSS doesn't support keyframe animations on text content. Rejected.
- **Separate deflisten for spinner**: Adds complexity, still requires background process. Rejected.

---

### R4: Should badge state include `is_window_focused` field?

**Decision**: No - badge data remains unchanged; focus state comes from existing window data.

**Rationale**:
- Window focus state already in monitoring data via `window.focused` boolean
- Adding `is_focused` to badge creates duplicate/stale data (badge focus != actual focus after switch)
- Eww widget has access to both: `window.focused` (current focus) and `window.badge` (notification state)
- Focus state changes frequently; badge state is relatively stable
- Keeping them separate prevents coupling and potential race conditions

**Data Flow**:
```
Sway IPC (focus event) → monitoring_data.py → window.focused
Claude Code hook (stop event) → badge files/IPC → window.badge.state
Eww widget combines both: badge visibility + focus-aware styling
```

---

### R5: What performance targets should guide implementation?

**Decision**: Maintain Feature 095 targets with additional CPU constraint during animation.

**Performance Targets**:
| Metric | Target | Current | Proposed |
|--------|--------|---------|----------|
| Badge appearance latency | <100ms | 0-500ms (polling) | <50ms (IPC) |
| Badge clear latency (focus) | <100ms | <100ms | <100ms (unchanged) |
| CPU during "working" state | <2% | 5-10% (polling) | <1% (defvar) |
| CPU during idle | <0.5% | <0.5% | <0.5% (unchanged) |
| Memory overhead | <10KB | ~10KB | ~10KB (unchanged) |

**Measurement Approach**:
1. Badge latency: Timestamp in hook → timestamp in Eww render (journalctl + eww logs)
2. CPU: `htop` filter on `monitoring-data-backend` process during animation
3. Memory: `/proc/<pid>/status` VmRSS field

---

## Summary of Decisions

| Question | Decision | Impact |
|----------|----------|--------|
| **R1: Focus state in badge** | CSS class modifier based on `window.focused` | Visual distinction without data changes |
| **R2: Hooks IPC vs file** | IPC primary with file fallback | Lower latency, maintains reliability |
| **R3: Spinner optimization** | Separate `defvar` for spinner, no full refresh | ~90% CPU reduction during animation |
| **R4: Badge focus field** | No - use existing `window.focused` | Avoid data duplication, prevent staleness |
| **R5: Performance targets** | <100ms latency, <2% CPU, <10KB memory | Measurable success criteria |

## Open Questions (None)

All technical questions resolved. Ready to proceed to Phase 1 (Data Model & Contracts).
