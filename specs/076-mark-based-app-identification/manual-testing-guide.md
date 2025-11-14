# Manual Testing Guide: Feature 076 Mark-Based App Identification

**Purpose**: Validate Feature 076 implementation after NixOS rebuild
**Prerequisites**:
- NixOS rebuilt with Feature 076 code
- Sway session running
- i3-project-event-listener daemon active
- At least one test layout saved

**Date Created**: 2025-11-14
**Status**: Ready for execution

---

## Pre-Flight Checks

```bash
# 1. Verify daemon is running
systemctl --user is-active i3-project-event-listener
# Expected: active

# 2. Verify MarkManager is loaded
journalctl --user -u i3-project-event-listener --since "5 minutes ago" | grep "MarkManager initialized"
# Expected: "MarkManager initialized" in logs

# 3. Check current project
pcurrent
# Expected: nixos (or your test project)
```

---

## Test 1: Mark Injection Performance (T044)

**Goal**: Measure mark injection latency (<15ms target for 3 marks)

```bash
# Launch an app via app-registry wrapper
Win+Return  # Launch terminal (Ghostty)

# Check logs for injection performance
journalctl --user -u i3-project-event-listener -f | grep "Feature 076 Performance: Injected"

# Expected output:
# Feature 076 Performance: Injected 4 marks on window 12345 in 8.23ms (target: <15ms for 3 marks)
```

**Acceptance Criteria**:
- ✅ Mark injection completes in <15ms for 3-4 marks
- ✅ No errors in daemon logs
- ✅ Window receives all expected marks

**Record Measurements**:
- 3 marks: ___ ms
- 4 marks: ___ ms
- 5 marks: ___ ms

---

## Test 2: Mark Verification After Launch

**Goal**: Verify marks are correctly injected on window

```bash
# Get window ID of focused terminal
window_id=$(swaymsg -t get_tree | jq '.. | select(.focused?==true) | .id')

# Check marks on window
swaymsg -t get_tree | jq ".. | select(.id==$window_id) | .marks"

# Expected output:
# [
#   "i3pm_app:terminal",
#   "i3pm_project:nixos",
#   "i3pm_ws:1",
#   "i3pm_scope:scoped"
# ]
```

**Acceptance Criteria**:
- ✅ Window has i3pm_app mark with correct app name
- ✅ Window has i3pm_project mark (if scoped app)
- ✅ Window has i3pm_ws mark with workspace number
- ✅ Window has i3pm_scope mark (scoped/global)

---

## Test 3: Layout Save with Marks

**Goal**: Verify marks are persisted in layout files

```bash
# 1. Launch multiple apps
Win+Return  # Terminal
Win+C       # VS Code
Win+G       # Lazygit

# 2. Save layout
i3pm layout save test-marks

# 3. Examine saved layout file
cat ~/.local/share/i3pm/layouts/nixos/test-marks.json | jq '.windows[] | {app: .app_registry_name, marks: .marks_metadata}'

# Expected output:
# {
#   "app": "terminal",
#   "marks": {
#     "app": "terminal",
#     "project": "nixos",
#     "workspace": "1",
#     "scope": "scoped"
#   }
# }
# ... (repeated for each window)
```

**Acceptance Criteria**:
- ✅ Layout file contains marks_metadata for each window
- ✅ marks_metadata.app matches app_registry_name
- ✅ All mark fields (project, workspace, scope) are present
- ✅ JSON is valid and parseable

---

## Test 4: Mark Query Performance (T044)

**Goal**: Measure window query latency (<20ms target for 10 windows)

```bash
# Launch 10 windows across different workspaces
# (Use app launcher or manual launches)

# Check query performance in logs when restoring
journalctl --user -u i3-project-event-listener -f | grep "Feature 076 Performance: Found"

# Expected output:
# Feature 076 Performance: Found 3 windows matching query in 12.45ms (target: <20ms for 10 windows)
```

**Record Measurements**:
- 5 windows: ___ ms
- 10 windows: ___ ms
- 20 windows: ___ ms

**Acceptance Criteria**:
- ✅ Query completes in <20ms for 10 windows
- ✅ Query completes in <30ms for 20 windows
- ✅ No performance degradation with many windows

---

## Test 5: Idempotent Restoration (Workflow 3 from quickstart.md)

**Goal**: Verify multiple restores create zero duplicates

```bash
# 1. Count windows before restore
before=$(swaymsg -t get_tree | jq '[recurse(.nodes[]?, .floating_nodes[]?) | select(.pid? and .pid > 0)] | length')
echo "Windows before: $before"

# 2. First restore (from clean state)
i3pm layout restore nixos test-marks

# Wait for apps to launch
sleep 3

# 3. Count windows after first restore
after1=$(swaymsg -t get_tree | jq '[recurse(.nodes[]?, .floating_nodes[]?) | select(.pid? and .pid > 0)] | length')
echo "Windows after restore 1: $after1"

# 4. Second restore (all apps already running)
i3pm layout restore nixos test-marks
sleep 1

# 5. Count windows after second restore
after2=$(swaymsg -t get_tree | jq '[recurse(.nodes[]?, .floating_nodes[]?) | select(.pid? and .pid > 0)] | length')
echo "Windows after restore 2: $after2"

# 6. Third restore
i3pm layout restore nixos test-marks
sleep 1

# 7. Count windows after third restore
after3=$(swaymsg -t get_tree | jq '[recurse(.nodes[]?, .floating_nodes[]?) | select(.pid? and .pid > 0)] | length')
echo "Windows after restore 3: $after3"
```

**Acceptance Criteria**:
- ✅ Window count remains constant: after1 == after2 == after3
- ✅ Logs show "Window already exists with marks - skipping launch"
- ✅ Zero duplicate windows created
- ✅ No extra processes spawned

**Record Results**:
- Restore 1 window count: ___
- Restore 2 window count: ___
- Restore 3 window count: ___
- Delta: ___ (should be 0)

---

## Test 6: Mark Cleanup Performance (T044)

**Goal**: Measure mark cleanup latency after window close

```bash
# 1. Launch a terminal
Win+Return

# 2. Get window ID
window_id=$(swaymsg -t get_tree | jq '.. | select(.focused?==true) | .id')

# 3. Verify marks exist
swaymsg -t get_tree | jq ".. | select(.id==$window_id) | .marks"

# 4. Close window and monitor cleanup
journalctl --user -u i3-project-event-listener -f | grep "Feature 076 Performance: Cleaned up"

# 5. Close the window
swaymsg "[con_id=$window_id] kill"

# Expected log output:
# Feature 076 Performance: Cleaned up 4 marks from window 12345 in 3.21ms
```

**Record Measurements**:
- Cleanup 3 marks: ___ ms
- Cleanup 4 marks: ___ ms
- Cleanup 5 marks: ___ ms

**Acceptance Criteria**:
- ✅ Cleanup completes in <10ms
- ✅ All i3pm_* marks removed from Sway
- ✅ No orphaned marks remain

---

## Test 7: Backward Compatibility with Old Layouts

**Goal**: Verify layouts without marks_metadata still work

```bash
# 1. Create a layout file without marks_metadata (simulate old layout)
cat > ~/.local/share/i3pm/layouts/nixos/old-format.json <<'EOF'
{
  "focused_workspace": "1",
  "windows": [
    {
      "window_class": "Ghostty",
      "instance": "ghostty",
      "title_pattern": "Terminal",
      "launch_command": "i3pm app launch terminal",
      "geometry": {"x": 0, "y": 0, "width": 800, "height": 600},
      "marks": [],
      "floating": false,
      "cwd": "/home/vpittamp",
      "app_registry_name": "terminal",
      "focused": true,
      "restoration_mark": "i3pm-restore-12345678"
    }
  ]
}
EOF

# 2. Restore old layout
i3pm layout restore nixos old-format

# 3. Check logs for backward compatibility warning
journalctl --user -u i3-project-event-listener -f | grep "No mark metadata in saved layout"

# Expected output:
# Feature 076: No mark metadata in saved layout for Ghostty.
# Layout restoration may be slower and less reliable.
# Consider re-saving this layout with: i3pm layout save <name>
```

**Acceptance Criteria**:
- ✅ Old layout restores without errors
- ✅ Warning message suggests re-saving layout
- ✅ Fallback to /proc-based detection works
- ✅ Apps launch correctly despite missing marks

---

## Test 8: Mark-Based Detection vs /proc Fallback

**Goal**: Compare mark-based detection speed vs /proc fallback

```bash
# 1. Time mark-based restore (with marks_metadata)
time i3pm layout restore nixos test-marks

# Record: ___ seconds

# 2. Time /proc-based restore (without marks_metadata)
time i3pm layout restore nixos old-format

# Record: ___ seconds

# 3. Compare performance
echo "Mark-based restore: X.Xs"
echo "/proc-based restore: Y.Ys"
echo "Speedup: Zx faster"
```

**Expected Results**:
- Mark-based restore: ~2-3 seconds (for 5 apps)
- /proc-based restore: ~7-8 seconds (for 5 apps)
- **Speedup: 3x faster with marks**

---

## Test 9: Custom Metadata Extensibility (User Story 3)

**Goal**: Verify custom metadata fields work correctly

```bash
# This test requires modifying mark injection to include custom metadata
# Skip for now - validate model support only

# Verify custom metadata validation works
pytest tests/unit/test_mark_models.py::TestMarkMetadata::test_custom_key_validation -v

# Expected: All tests pass
```

---

## Performance Benchmark Summary (T044)

After completing all tests, update quickstart.md with actual measurements:

| Operation | Target | Measured | Pass/Fail |
|-----------|--------|----------|-----------|
| Inject 3 marks | <15ms | ___ ms | _____ |
| Inject 5 marks | <25ms | ___ ms | _____ |
| Query 10 windows | <20ms | ___ ms | _____ |
| Query 20 windows | <30ms | ___ ms | _____ |
| Cleanup 4 marks | <10ms | ___ ms | _____ |
| Restore 5 apps (mark-based) | ~2-3s | ___ s | _____ |
| Restore 5 apps (/proc fallback) | ~7-8s | ___ s | _____ |
| Speedup ratio | 3x | ___ x | _____ |

---

## Validation Checklist (T047)

All 9 workflows from quickstart.md:

- [ ] Workflow 1: Save Layout with Marks (Automatic)
- [ ] Workflow 2: Restore Layout Using Marks (Automatic)
- [ ] Workflow 3: Idempotent Restore (Zero Duplicates) ← **Critical**
- [ ] Workflow 4: Query Windows by Marks (Python API)
- [ ] Workflow 5: Debug Mark Injection
- [ ] Workflow 6: Test Mark Cleanup
- [ ] Workflow 7: Run Unit Tests
- [ ] Workflow 8: Run Integration Tests
- [ ] Workflow 9: Run End-to-End Tests

---

## Troubleshooting

### Issue: Marks Not Injected

```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Check daemon logs for errors
journalctl --user -u i3-project-event-listener -f | grep -i error

# Verify window::new handler is registered
journalctl --user -u i3-project-event-listener --since "5 minutes ago" | grep "window::new"
```

### Issue: Marks Not Cleaned Up

```bash
# Check for orphaned marks
swaymsg -t get_marks | grep ^i3pm_

# Manual cleanup if needed
for mark in $(swaymsg -t get_marks | grep ^i3pm_); do
  swaymsg unmark $mark
done
```

### Issue: Restore Creates Duplicates

```bash
# Check if marks are in layout file
cat ~/.local/share/i3pm/layouts/nixos/test-marks.json | jq '.windows[].marks_metadata'

# If missing, re-save layout
i3pm layout save test-marks
```

---

## Next Steps After Testing

1. Run all tests above
2. Record actual performance measurements
3. Update quickstart.md with measured benchmarks (T044)
4. Update tasks.md to mark T044, T047 as complete
5. Create pull request or commit changes
6. Deploy to production

---

**Testing Status**: ⏳ PENDING (requires active Sway session)
**Estimated Time**: 30-45 minutes for complete validation
