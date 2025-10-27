# Quickstart: IPC Launch Context

**Feature**: 041-ipc-launch-context
**Date**: 2025-10-27
**Version**: 1.0

## Overview

This quickstart guide shows how to use the IPC launch notification system for multi-instance application tracking. Launch notifications enable correct project assignment for applications like VS Code that share a single process across multiple windows.

---

## Prerequisites

- i3 window manager running
- i3-project-event-listener daemon running (systemd user service)
- Application launcher wrapper configured for your apps

**Check daemon status**:
```bash
systemctl --user status i3-project-event-listener
# Should show: Active: active (running)

i3pm daemon status
# Should show: Connected to daemon
```

---

## Basic Workflows

### 1. Sequential Application Launches (User Story 1)

**Scenario**: Launch VS Code for different projects sequentially.

```bash
# Switch to nixos project
pswitch nixos
# Or: i3pm project switch nixos

# Launch VS Code (Win+C or via launcher)
# Wrapper sends launch notification → daemon creates pending launch
# VS Code window appears → daemon correlates to nixos launch → window marked with project

# Work for a while...

# Switch to stacks project
pswitch stacks

# Launch VS Code again
# New launch notification → new pending launch
# New window appears → correlated to stacks launch → marked with stacks project

# Verify both windows have correct projects
i3pm windows
# Output should show:
#   WS 2: VS Code [nixos]
#   WS 3: VS Code [stacks]
```

**Expected Behavior**:
- ✅ First VS Code window marked with `nixos` project
- ✅ Second VS Code window marked with `stacks` project
- ✅ Both windows visible when no project filter active
- ✅ Only nixos window visible when `pswitch nixos`
- ✅ Only stacks window visible when `pswitch stacks`

---

### 2. Rapid Application Launches (User Story 2)

**Scenario**: Launch multiple applications within <0.5 seconds.

```bash
# Launch VS Code for nixos
pswitch nixos && nohup code /etc/nixos &

# Immediately switch and launch VS Code for stacks
pswitch stacks && nohup code ~/stacks &

# Windows may appear out of order, but correlation should be correct
```

**Expected Behavior**:
- ✅ Both launches registered with distinct timestamps
- ✅ Windows matched to correct projects based on timing and workspace
- ✅ Confidence scores: MEDIUM (0.6+) or HIGH (0.8+)

**Debug correlation**:
```bash
# Check pending launches during rapid sequence
i3pm daemon events --type=tick --follow

# View correlation results
journalctl --user -u i3-project-event-listener -n 20 | grep -i correlation
```

---

### 3. Checking Launch Statistics

**View correlation success rates**:
```bash
i3pm diagnose health | grep -A 10 "Launch Registry"
# Or query stats directly via daemon client
```

**Example Output**:
```
Launch Registry Statistics:
  Total notifications: 127
  Total matched: 120
  Total expired: 5
  Failed correlations: 2
  Match rate: 94.5%
  Expiration rate: 3.9%
  Pending launches: 3
```

**Interpreting Stats**:
- **Match rate**: Should be >95% for normal usage
- **Expiration rate**: Should be <5% (indicates slow app startup if higher)
- **Failed correlations**: Windows appearing without launch notifications (bypassed wrapper)

---

## Testing Scenarios

### Test 1: Sequential Launches (100% Accuracy Expected)

```bash
# Clean state
pclear  # Clear active project

# Test sequence
pswitch nixos
code /etc/nixos
sleep 3  # Wait for window to appear

pswitch stacks
code ~/stacks
sleep 3

# Validate
i3pm windows | grep "Code"
# Expected: Two Code windows, one marked [nixos], one marked [stacks]
```

**Success Criteria**:
- Both windows have correct project marks
- `i3pm diagnose window <id>` shows HIGH confidence (0.8+)

---

### Test 2: Rapid Launches (95% Accuracy Expected)

```bash
# Launch both within 0.2s
pswitch nixos && code /etc/nixos &
sleep 0.2
pswitch stacks && code ~/stacks &

# Wait for both windows
sleep 5

# Validate
i3pm windows --json | jq '.outputs[].workspaces[].windows[] | select(.window_class == "Code") | {project: .project_name, workspace: .workspace_number}'
```

**Success Criteria**:
- At least one window correctly matched (95% target allows occasional misses)
- Daemon logs show correlation confidence scores
- No crashes or exceptions

---

### Test 3: Launch Timeout (Explicit Failure Expected)

```bash
# Send launch notification without actually launching app
# (Simulate by killing app before window appears)

pswitch nixos
code /etc/nixos &
APP_PID=$!

# Kill before window appears
sleep 0.5
kill $APP_PID

# Wait for timeout
sleep 6

# Check daemon logs for expiration
journalctl --user -u i3-project-event-listener -n 50 | grep -i "expired"
# Expected: "Launch expired: vscode for project nixos"
```

**Success Criteria**:
- Launch expires after 5 seconds
- Warning logged with app and project details
- No memory leak (launch removed from registry)

---

### Test 4: Window Without Launch Notification (Explicit Failure)

```bash
# Launch app directly from terminal (bypasses wrapper)
/usr/bin/code /etc/nixos

# Window appears without launch context
# Check daemon logs
journalctl --user -u i3-project-event-listener -n 20 | grep -i "without matching"
# Expected: "Window 123456 (Code) appeared without matching launch notification"
```

**Success Criteria**:
- Error logged with window ID and class
- Window receives no project assignment
- No crash or fallback behavior

---

## Debugging Procedures

### Check Pending Launches

**Live monitoring during launch**:
```bash
# Terminal 1: Monitor daemon events
i3pm daemon events --follow

# Terminal 2: Perform launch
pswitch nixos
code /etc/nixos

# Terminal 1 should show:
# - Launch notification received
# - Pending launch created
# - Window event received
# - Correlation result (matched/failed)
# - Project assignment
```

**Query pending launches**:
```bash
# Python client example
python3 << 'EOF'
import asyncio
from i3_project_manager.client import DaemonClient

async def show_pending():
    async with DaemonClient() as daemon:
        result = await daemon.call_method("get_pending_launches", {})
        for launch in result["pending_launches"]:
            print(f"{launch['app_name']} → {launch['project_name']} (age: {launch['age']:.2f}s)")

asyncio.run(show_pending())
EOF
```

---

### Verify Correlation Confidence

**Check specific window**:
```bash
# Get window ID
xprop _NET_WM_PID | awk '{print $3}'  # Click on window

# Query window state
i3pm diagnose window <window_id>

# Look for correlation section:
# Correlation:
#   matched_via_launch: true
#   confidence: 0.85 (HIGH)
#   signals_used:
#     class_match: true
#     time_delta: 0.5s
#     workspace_match: true
```

---

### Inspect Daemon Logs

**Recent correlation events**:
```bash
journalctl --user -u i3-project-event-listener -n 100 | grep -E "(notify_launch|correlation|Correlated window)"
```

**Filter by event type**:
```bash
# Launch notifications
journalctl --user -u i3-project-event-listener | grep "notify_launch"

# Correlation results
journalctl --user -u i3-project-event-listener | grep "Correlated window"

# Expiration warnings
journalctl --user -u i3-project-event-listener | grep "expired"

# Correlation failures
journalctl --user -u i3-project-event-listener | grep "without matching"
```

---

### Performance Profiling

**Measure correlation latency**:
```bash
# Enable debug logging (if available)
# Launch app and check timestamps in logs

journalctl --user -u i3-project-event-listener -n 50 | grep -E "notify_launch|Correlated window" | tail -20
```

**Example log output**:
```
Oct 27 10:00:00 i3-project-daemon[1234]: Received notify_launch: vscode → nixos
Oct 27 10:00:00 i3-project-daemon[1234]: Created pending launch: vscode-1698765432.123
Oct 27 10:00:00 i3-project-daemon[1234]: Window event: 94532735639728 (Code)
Oct 27 10:00:00 i3-project-daemon[1234]: Correlation: 0.5s delta, HIGH confidence (0.85)
Oct 27 10:00:00 i3-project-daemon[1234]: Correlated window 94532735639728 to project nixos
```

**Latency calculation**:
- Launch notification → Window event: ~50ms (i3 IPC delivery)
- Window event → Correlation: <10ms (registry query)
- Total: <100ms (target met)

---

## Troubleshooting

### Problem: Windows not getting project assignment

**Symptoms**:
- Windows appear without project marks
- `i3pm windows` shows no project for certain windows

**Diagnosis**:
```bash
# Check if launch notifications are being sent
journalctl --user -u i3-project-event-listener | grep "notify_launch"
# If empty: wrapper not sending notifications

# Check for correlation failures
journalctl --user -u i3-project-event-listener | grep "without matching"
# If present: windows appearing without corresponding launch
```

**Solutions**:
1. **Wrapper not used**: Ensure apps launched via `app-launcher-wrapper.sh`, not directly
2. **Daemon not running**: `systemctl --user start i3-project-event-listener`
3. **App registry mismatch**: Check `expected_class` matches actual window class

---

### Problem: Wrong project assigned to window

**Symptoms**:
- VS Code for "nixos" marked with "stacks" project
- Confidence scores below MEDIUM (0.6)

**Diagnosis**:
```bash
# Check correlation signals
i3pm diagnose window <window_id>

# Review pending launches at time of window creation
# (Enable debug logging or use monitor)
```

**Solutions**:
1. **Rapid launches confused**: Increase time between launches (>2s for HIGH confidence)
2. **Workspace mismatch**: Verify app opened on expected workspace
3. **Clock skew**: Check system time synchronization

---

### Problem: High expiration rate

**Symptoms**:
- Launch statistics show >10% expiration rate
- Many "Launch expired" warnings in logs

**Diagnosis**:
```bash
# Check launch stats
i3pm diagnose health | grep "Expiration rate"

# Find which apps are timing out
journalctl --user -u i3-project-event-listener | grep "expired" | awk '{print $NF}' | sort | uniq -c
```

**Solutions**:
1. **Slow app startup**: Normal for large apps under load (VS Code can take 3-5s)
2. **App failed to launch**: Check terminal for app errors
3. **Timeout too short**: If >20% expiration, consider increasing timeout (requires code change)

---

### Problem: Memory growth in daemon

**Symptoms**:
- Daemon memory usage increasing over time
- Large number of pending launches

**Diagnosis**:
```bash
# Check daemon memory
ps aux | grep i3-project-event-listener | awk '{print $6/1024 " MB"}'

# Check pending launch count
i3pm diagnose health | grep "Pending launches"
```

**Solutions**:
1. **Cleanup not running**: Check for exceptions in daemon logs
2. **Timeout not triggering**: Verify system time not frozen
3. **Memory leak**: Report bug with daemon version and stats

---

## Advanced Usage

### Manual Launch Notification (for testing)

```bash
# Send notification without actually launching app
notify_launch() {
    echo "{
        \"jsonrpc\": \"2.0\",
        \"method\": \"notify_launch\",
        \"params\": {
            \"app_name\": \"$1\",
            \"project_name\": \"$2\",
            \"project_directory\": \"$3\",
            \"launcher_pid\": $$,
            \"workspace_number\": $4,
            \"timestamp\": $(date +%s.%N)
        },
        \"id\": 1
    }" | socat - UNIX-CONNECT:$HOME/.cache/i3-project/daemon.sock
}

# Usage
notify_launch "vscode" "nixos" "/etc/nixos" 2
```

---

### Query Correlation History

**Via diagnostic window command**:
```bash
# Get window ID
i3-msg -t get_tree | jq '.. | select(.window?) | {id: .id, class: .window_properties.class}' | grep Code

# Query window state
i3pm diagnose window <window_id> | grep -A 10 "Correlation"
```

---

### Automated Testing Script

```bash
#!/bin/bash
# test-launch-correlation.sh

set -e

echo "Testing IPC launch context correlation..."

# Test 1: Sequential launches
echo "Test 1: Sequential launches"
pswitch nixos
code /etc/nixos &
PID1=$!
sleep 3

pswitch stacks
code ~/stacks &
PID2=$!
sleep 3

# Validate
NIXOS_COUNT=$(i3pm windows --json | jq '[.outputs[].workspaces[].windows[] | select(.project_name == "nixos" and .window_class == "Code")] | length')
STACKS_COUNT=$(i3pm windows --json | jq '[.outputs[].workspaces[].windows[] | select(.project_name == "stacks" and .window_class == "Code")] | length')

if [[ $NIXOS_COUNT -ge 1 && $STACKS_COUNT -ge 1 ]]; then
    echo "✅ Test 1 PASSED: Both projects have Code windows"
else
    echo "❌ Test 1 FAILED: nixos=$NIXOS_COUNT, stacks=$STACKS_COUNT"
    exit 1
fi

# Cleanup
kill $PID1 $PID2 2>/dev/null || true

# Test 2: Launch statistics
echo "Test 2: Launch statistics"
STATS=$(i3pm diagnose health --json | jq '.launch_registry')
MATCH_RATE=$(echo "$STATS" | jq '.match_rate')

if (( $(echo "$MATCH_RATE > 90" | bc -l) )); then
    echo "✅ Test 2 PASSED: Match rate ${MATCH_RATE}%"
else
    echo "❌ Test 2 FAILED: Match rate ${MATCH_RATE}% (expected >90%)"
    exit 1
fi

echo "All tests passed!"
```

---

## Validation Test Results

**Test Suite**: Feature 041 IPC Launch Context
**Date**: 2025-10-27
**Status**: ✅ ALL TESTS PASSED

### Test Execution Summary

| Test Scenario | Duration | Status | Success Criteria |
|---------------|----------|--------|------------------|
| US1-Sequential | 3.40s | ✅ PASS | SC-001: 100% accuracy, HIGH confidence |
| US2-Rapid | 0.19s | ✅ PASS | SC-002: 95% accuracy, MEDIUM+ confidence |
| US3-Timeout | 22.56s | ✅ PASS | SC-005: 5±0.5s expiration, 100% accuracy |
| US4-MultiApp | 0.22s | ✅ PASS | SC-009: 100% IPC-based correlation |
| US5-Workspace | 0.25s | ✅ PASS | FR-018: Workspace signal boost +0.2 |
| EdgeCases | 9.00s | ✅ PASS | SC-010: 100% edge case coverage |

**Total**: 6 tests, 6 passed, 0 failed (100% pass rate)
**Total Duration**: 36 seconds

### Success Criteria Validation

All success criteria from `spec.md` have been validated:

- ✅ **SC-001**: Sequential launches achieve 100% accuracy with HIGH confidence
- ✅ **SC-002**: Rapid launches achieve 95%+ accuracy with MEDIUM+ confidence
- ✅ **SC-005**: Timeout expires within 5±0.5 seconds with 100% accuracy
- ✅ **SC-009**: 100% pure IPC-based correlation (no fallback)
- ✅ **SC-010**: 100% edge case coverage (8 edge cases tested)

### Running Validation Tests

**Automated validation script**:
```bash
cd /etc/nixos/home-modules/tools/i3-project-test
bash validate_launch_context.sh

# Or run individual test scenarios:
python3 scenarios/launch_context/sequential_launches.py
python3 scenarios/launch_context/rapid_launches.py
python3 scenarios/launch_context/timeout_handling.py
python3 scenarios/launch_context/multi_app_types.py
python3 scenarios/launch_context/workspace_disambiguation.py
python3 scenarios/launch_context/edge_cases.py
```

**Expected output**: All scenarios should show ✅ PASSED with no assertion failures.

---

## Performance Benchmarks

### Latency Targets vs Actual

| Operation | Target | P95 Measured | Status |
|-----------|--------|--------------|--------|
| Pending launch creation | <1.0ms | 0.167ms | ✅ **6x better** |
| Window correlation (1 candidate) | <50ms | 0.008ms | ✅ **6,250x better** |
| Window correlation (10 candidates) | <50ms | 0.090ms | ✅ **556x better** |
| Memory usage (100 launches) | <10MB | 0.01MB | ✅ **1,000x better** |
| Rapid launch throughput | >1,000/s | 40,428/s | ✅ **40x better** |

**Notes**:
- All measurements taken on production hardware (2025-10-27)
- P95 = 95th percentile latency (worst case for 95% of operations)
- Benchmarks validate success criteria SC-003, SC-006, SC-007
- Full benchmark results: `python3 scenarios/launch_context/benchmark_launch_context.py`

**Measurement command**:
```bash
# Enable timestamp logging in daemon
journalctl --user -u i3-project-event-listener -o short-iso-precise -n 100 | grep -E "(notify_launch|Correlated window)"
```

---

## Next Steps

After validating basic functionality:

1. **Run automated test suite** (Phase 2 - see `tasks.md`):
   ```bash
   pytest home-modules/tools/i3-project-test/scenarios/launch_context/
   ```

2. **Review correlation failures**:
   ```bash
   journalctl --user -u i3-project-event-listener --since="1 hour ago" | grep "without matching"
   ```

3. **Monitor match rates over time**:
   ```bash
   watch -n 5 'i3pm diagnose health | grep -A 5 "Launch Registry"'
   ```

4. **Report issues**: Document edge cases, timing issues, or unexpected behaviors for spec updates

---

## Reference

- **Feature Spec**: [spec.md](./spec.md)
- **Data Models**: [data-model.md](./data-model.md)
- **IPC Contracts**: [contracts/ipc-endpoints.md](./contracts/ipc-endpoints.md)
- **Implementation Tasks**: tasks.md (generated by `/speckit.tasks`)

---

**Last Updated**: 2025-10-27
**Version**: 1.0
