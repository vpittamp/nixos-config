# Quickstart: Dynamic Window Management Testing

**Feature**: 021-lets-create-a
**Date**: 2025-10-21

## Overview

This quickstart provides testing scenarios for each user story in the specification. Each scenario is independently executable and validates the feature end-to-end.

## Prerequisites

1. NixOS system with i3 window manager (Hetzner reference platform recommended)
2. i3pm daemon running (`systemctl --user status i3-project-event-listener`)
3. Python 3.11+ with i3ipc.aio installed
4. Test files generated in `tests/i3_project_manager/`

## User Story Testing Scenarios

### US1: Pattern-Based Window Classification Without Rebuilds

**Goal**: Verify users can modify window rules and see changes without NixOS rebuild

**Test Steps**:
```bash
# 1. Create test window-rules.json
cat > ~/.config/i3/window-rules.json <<'EOF'
[
  {
    "pattern_rule": {
      "pattern": "glob:test-*",
      "scope": "scoped",
      "priority": 200,
      "description": "Test pattern for verification"
    },
    "workspace": 5
  }
]
EOF

# 2. Reload daemon (should detect file change automatically within 1 second)
# Or manually trigger: systemctl --user reload i3-project-event-listener

# 3. Launch test window with matching class
alacritty --class test-app &

# 4. Verify window assigned to workspace 5
i3-msg -t get_tree | jq '.nodes[].nodes[].nodes[] | select(.window_properties.class=="test-app") | .workspace'
# Expected: 5

# 5. Modify rule (change workspace from 5 to 7)
jq '.[0].workspace = 7' ~/.config/i3/window-rules.json > /tmp/rules.json
mv /tmp/rules.json ~/.config/i3/window-rules.json

# 6. Launch another test window
alacritty --class test-app2 &

# 7. Verify new window uses updated rule (workspace 7)
i3-msg -t get_tree | jq '.nodes[].nodes[].nodes[] | select(.window_properties.class=="test-app2") | .workspace'
# Expected: 7

# 8. Cleanup
pkill -f "test-app"
```

**Success Criteria**:
- [x] File modification detected within <1 second (SC-001)
- [x] New windows use updated rules without any rebuild
- [x] Pattern matching completes in <1ms (verified via daemon logs or performance tests)

**Automated Test**: `pytest tests/i3_project_manager/scenarios/test_dynamic_reload.py`

---

### US2: Firefox PWA Detection and Classification

**Goal**: Verify Firefox PWAs are correctly detected and classified by title

**Test Steps**:
```bash
# 1. Create PWA classification rule
cat > ~/.config/i3/window-rules.json <<'EOF'
[
  {
    "pattern_rule": {
      "pattern": "glob:FFPWA-*",
      "scope": "global",
      "priority": 200,
      "description": "Firefox PWAs - title-based detection"
    },
    "workspace": 4
  }
]
EOF

# 2. Launch Firefox PWA (YouTube example)
# Note: Requires firefoxpwa installed and PWA created
firefoxpwa site launch 01K665SPD8EPMP3JTW02JM1M0Z &

# 3. Wait for window creation
sleep 2

# 4. Verify PWA detected with correct class
i3-msg -t get_tree | jq '.nodes[].nodes[].nodes[] | select(.window_properties.class | startswith("FFPWA-")) | {class: .window_properties.class, title: .name, workspace: .workspace}'
# Expected: {class: "FFPWA-01K665SPD8EPMP3JTW02JM1M0Z", title: "YouTube", workspace: 4}

# 5. Verify classification via daemon IPC
i3pm classify --window-class "FFPWA-01K665SPD8EPMP3JTW02JM1M0Z" --window-title "YouTube"
# Expected: scope=global, workspace=4, source=window_rule

# 6. Cleanup
i3-msg '[class="^FFPWA-.*"] kill'
```

**Success Criteria**:
- [x] PWA detected by FFPWA-* class pattern (SC-003)
- [x] Classified as global with workspace 4
- [x] Title pattern matching works for multiple PWAs

**Automated Test**: `pytest tests/i3_project_manager/scenarios/test_pwa_detection.py`

---

### US3: Terminal Application Detection

**Goal**: Verify terminal apps (yazi, lazygit, k9s) detected by title pattern

**Test Steps**:
```bash
# 1. Create title-based classification rule
cat > ~/.config/i3/window-rules.json <<'EOF'
[
  {
    "pattern_rule": {
      "pattern": "title:^Yazi:.*",
      "scope": "scoped",
      "priority": 300,
      "description": "Yazi file manager in terminal"
    },
    "workspace": 5
  },
  {
    "pattern_rule": {
      "pattern": "Ghostty",
      "scope": "scoped",
      "priority": 100,
      "description": "Default ghostty terminal"
    },
    "workspace": 1
  }
]
EOF

# 2. Launch plain ghostty terminal (should go to workspace 1)
ghostty &
sleep 1
i3-msg -t get_tree | jq '.nodes[].nodes[].nodes[] | select(.window_properties.class=="Ghostty" and (.name | startswith("Yazi:") | not)) | .workspace'
# Expected: 1

# 3. Launch yazi in ghostty with custom title (should go to workspace 5)
ghostty -e bash -c 'echo -ne "\033]0;Yazi: /etc/nixos\007"; yazi /etc/nixos' &
sleep 2
i3-msg -t get_tree | jq '.nodes[].nodes[].nodes[] | select(.window_properties.class=="Ghostty" and (.name | startswith("Yazi:"))) | .workspace'
# Expected: 5

# 4. Verify title pattern precedence (priority 300 > priority 100)
i3pm classify --window-class "Ghostty" --window-title "Yazi: /home/user"
# Expected: scope=scoped, workspace=5, source=window_rule

# 5. Cleanup
i3-msg '[class="Ghostty"] kill'
```

**Success Criteria**:
- [x] Title pattern correctly matches terminal apps (SC-004)
- [x] Priority ordering works (title:^Yazi:.* priority 300 > Ghostty priority 100)
- [x] Plain terminals and titled terminals classified differently

**Automated Test**: `pytest tests/i3_project_manager/scenarios/test_terminal_classification.py`

---

### US4: Dynamic Workspace-to-Monitor Assignment

**Goal**: Verify workspaces redistribute across monitors when connecting/disconnecting

**Test Steps (requires 2+ monitors or xrandr simulation)**:
```bash
# 1. Create workspace config
cat > ~/.config/i3/workspace-config.json <<'EOF'
[
  {"number": 1, "name": "Terminal", "icon": "󰨊", "default_output_role": "primary"},
  {"number": 2, "name": "Editor", "icon": "", "default_output_role": "primary"},
  {"number": 3, "name": "Browser", "icon": "󰈹", "default_output_role": "secondary"},
  {"number": 4, "name": "Media", "icon": "", "default_output_role": "secondary"}
]
EOF

# 2. Query current monitor configuration
i3pm monitor-config
# Expected: Shows active monitors with roles assigned

# 3. Verify workspace assignments with 1 monitor
i3-msg -t get_workspaces | jq '.[] | {num: .num, output: .output}'
# Expected: All workspaces on primary output

# 4. Simulate second monitor connection (if available)
# xrandr --output DP-2 --auto --right-of DP-1

# 5. Trigger workspace reassignment
i3-msg 'restart'  # Or wait for output event detection
sleep 2

# 6. Verify workspaces redistributed (WS 1-2 primary, WS 3-9 secondary)
i3-msg -t get_workspaces | jq '.[] | {num: .num, output: .output}'
# Expected: WS 1-2 on primary, WS 3-4 on secondary

# 7. Measure redistribution time (should be <500ms)
time (i3-msg 'restart' && sleep 0.5 && i3-msg -t get_workspaces > /dev/null)
# Expected: <500ms total

# 8. Cleanup (if simulated)
# xrandr --output DP-2 --off
```

**Success Criteria**:
- [x] Monitor count detected via i3 GET_OUTPUTS (SC-005)
- [x] Workspace redistribution completes in <500ms
- [x] Distribution rules applied: 1 monitor (all primary), 2 monitors (1-2 primary, 3-9 secondary)

**Automated Test**: `pytest tests/i3_project_manager/scenarios/test_monitor_redistribution.py`

---

### US5: Workspace Metadata with Names and Icons

**Goal**: Verify workspace names and icons displayed in i3bar

**Test Steps**:
```bash
# 1. Create workspace config with names and icons
cat > ~/.config/i3/workspace-config.json <<'EOF'
[
  {"number": 1, "name": "Terminal", "icon": "󰨊"},
  {"number": 2, "name": "Editor", "icon": ""},
  {"number": 3, "name": "Browser", "icon": "󰈹"}
]
EOF

# 2. Reload daemon
systemctl --user reload i3-project-event-listener

# 3. Query workspace config via daemon
i3pm workspace-config
# Expected: Shows names and icons for each workspace

# 4. Verify i3bar shows icons (manual check)
# Switch to workspace 1: i3-msg 'workspace 1'
# Check i3bar shows: "󰨊 1: Terminal"

# 5. Verify query API
curl -X POST http://localhost:5555 -H "Content-Type: application/json" -d '{
  "jsonrpc": "2.0",
  "method": "get_workspace_config",
  "params": {},
  "id": 1
}'
# Expected: {"jsonrpc":"2.0","result":{"workspaces":[{"number":1,"name":"Terminal","icon":"󰨊"},...]},"id":1}
```

**Success Criteria**:
- [x] Workspace config loaded from JSON
- [x] Names and icons available via daemon IPC
- [x] i3bar displays correct metadata (manual verification)

**Automated Test**: `pytest tests/i3_project_manager/scenarios/test_workspace_metadata.py`

---

## Integration Testing

### Test Runner Command

```bash
# Run all scenario tests
pytest tests/i3_project_manager/scenarios/ -v

# Run specific user story test
pytest tests/i3_project_manager/scenarios/test_pwa_detection.py -v

# Run with coverage
pytest tests/i3_project_manager/ --cov=home-modules/desktop/i3-project-event-daemon --cov=home-modules/tools/i3_project_manager --cov-report=html

# Run in CI mode (JSON output)
pytest tests/i3_project_manager/scenarios/ --json-report --json-report-file=test-results.json
```

### Performance Benchmarks

```bash
# Benchmark pattern matching performance
pytest tests/i3_project_manager/unit/test_pattern_matcher.py::test_performance_100_rules -v
# Expected: <1ms average classification time

# Benchmark config reload time
pytest tests/i3_project_manager/integration/test_config_reload.py::test_reload_100_rules -v
# Expected: <100ms reload time

# Benchmark workspace reassignment
pytest tests/i3_project_manager/integration/test_workspace_manager.py::test_reassign_all_workspaces -v
# Expected: <500ms total time
```

## Troubleshooting

### Common Issues

1. **Daemon not detecting file changes**:
   ```bash
   # Check watchdog is active
   journalctl --user -u i3-project-event-listener | grep watchdog

   # Manual reload trigger
   systemctl --user reload i3-project-event-listener
   ```

2. **Windows not classified correctly**:
   ```bash
   # Check current active project
   i3pm current

   # Debug classification for specific window
   i3pm classify --window-class "Code" --debug

   # View recent events
   i3pm events --limit=20 --type=window
   ```

3. **Workspace assignment not working**:
   ```bash
   # Verify i3 outputs
   i3-msg -t get_outputs | jq '.[] | {name: .name, active: .active, primary: .primary}'

   # Verify workspace assignments
   i3-msg -t get_workspaces | jq '.[] | {num: .num, output: .output}'

   # Check daemon monitor config
   i3pm monitor-config
   ```

4. **Pattern not matching**:
   ```bash
   # Test pattern syntax
   python3 -c "
   from i3_project_manager.models.pattern import PatternRule
   rule = PatternRule(pattern='glob:test-*', scope='scoped', priority=100)
   print(rule.matches('test-app'))  # Should print True
   "

   # View pattern matching cache statistics
   i3pm rules --show-cache-info
   ```

## Manual Verification Checklist

After completing automated tests, perform manual verification:

- [ ] Launch various applications, verify correct workspace assignment
- [ ] Connect/disconnect monitor, verify workspace redistribution
- [ ] Modify window-rules.json, verify reload within 1 second
- [ ] Switch projects, verify scoped_classes take precedence
- [ ] Check i3bar shows workspace names and icons
- [ ] Verify no performance degradation (daemon CPU <1%, memory <20MB)

## Next Steps

After quickstart validation:

1. Run full test suite: `pytest tests/i3_project_manager/ -v`
2. Review test coverage report: `open htmlcov/index.html`
3. Create migration tool: `i3pm migrate-rules` (from static i3.nix rules)
4. Document user guide in `docs/WINDOW_RULES.md`
