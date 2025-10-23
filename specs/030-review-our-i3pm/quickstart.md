# Quickstart: i3pm Production Readiness

**Feature**: 030-review-our-i3pm
**Date**: 2025-10-23
**Status**: Implementation Ready

## Overview

This quickstart guide walks through implementing and testing the i3pm production readiness features. The implementation extends existing Python daemon and Deno CLI tools with layout persistence, production-scale validation, error recovery, onboarding tools, and security hardening.

**CRITICAL**: This feature follows forward-only development (Constitution Principle XII). The legacy Python TUI (15,445 LOC in `home-modules/tools/i3-project-manager/`) will be **completely deleted** in the same commit as new features. No backwards compatibility layers, no migration period, no feature flags.

---

## Prerequisites

- NixOS 23.11+ with i3wm 4.20+
- Python 3.11+ with existing i3-project-daemon installed
- Deno 1.40+ with existing i3pm CLI v2.0 installed
- systemd user services enabled
- Existing Features 015, 025, 029 working correctly

**Verify Prerequisites**:
```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Check CLI version
i3pm --version  # Should show v2.0+

# Check existing features work
i3pm project list
i3pm windows --tree
i3pm daemon events --source=all --limit=5
```

---

## Phase 0: Development Environment Setup

### 1. Branch and Workspace

```bash
# Already on feature branch
git branch  # Should show: * 030-review-our-i3pm

# Verify spec and plan exist
ls -l specs/030-review-our-i3pm/
# Should see: spec.md, plan.md, research.md, data-model.md, contracts/, quickstart.md
```

### 2. Install Development Dependencies

```nix
# Add to home.packages in user/packages.nix
with pkgs; [
  # Python testing
  python311Packages.pytest
  python311Packages.pytest-asyncio
  python311Packages.pytest-cov
  python311Packages.pydantic

  # Type checking
  python311Packages.mypy

  # Load testing
  xdotool  # For synthetic window spawning
]
```

Apply changes:
```bash
sudo nixos-rebuild dry-build --flake .#hetzner
sudo nixos-rebuild switch --flake .#hetzner
```

### 3. Test Framework Setup

```bash
# Verify test framework exists
ls -l home-modules/tools/i3-project-test/

# Run existing tests to establish baseline
cd home-modules/tools/i3-project-test
pytest -v

# Expected: All existing tests should pass
```

---

## Phase 1: Layout Persistence Implementation

### Task 1.1: Python Daemon - Layout Capture Module

**Location**: `home-modules/tools/i3-project-daemon/layout/`

**Steps**:
1. Create module directory structure
2. Implement `capture.py` - captures current workspace state via i3 IPC
3. Implement `models.py` - Pydantic data models from data-model.md
4. Implement `discovery.py` - launch command discovery (desktop files → proc cmdline → user prompt)
5. Write unit tests in `tests/i3pm-production/unit/test_layout_capture.py`

**Key Implementation Points**:
```python
# capture.py - Main capture function
async def capture_workspace_layout(i3_conn, workspace_num: int) -> WorkspaceLayout:
    tree = await i3_conn.get_tree()
    workspace = find_workspace(tree, workspace_num)

    windows = []
    for window in extract_windows(workspace):
        launch_cmd = await discover_launch_command(window)
        placeholder = WindowPlaceholder(
            window_class=window.window_class,
            launch_command=launch_cmd,
            geometry=WindowGeometry.from_rect(window.rect),
            marks=[m for m in window.marks if m.startswith("project:")]
        )
        windows.append(placeholder)

    return WorkspaceLayout(...)
```

**Testing**:
```bash
# Unit tests
pytest tests/i3pm-production/unit/test_layout_capture.py -v

# Integration test with live i3
pytest tests/i3pm-production/integration/test_layout_workflow.py::test_capture -v
```

**Validation Criteria**:
- Captures all windows on workspace with correct geometry
- Discovers launch commands for >90% of common applications
- Handles windows without desktop files gracefully
- Completes capture in <1 second for 15 windows

---

### Task 1.2: Python Daemon - Layout Restore Module

**Location**: `home-modules/tools/i3-project-daemon/layout/restore.py`

**Steps**:
1. Implement layout loading from JSON file
2. Implement i3 `append_layout` command execution
3. Implement application launching with command execution
4. Implement window swallow monitoring with timeout
5. Write unit and integration tests

**Key Implementation Points**:
```python
# restore.py - Flicker-free restoration
async def restore_workspace_layout(i3_conn, layout: WorkspaceLayout):
    # 1. Prepare i3 layout (append_layout)
    i3_layout = layout.to_i3_json()
    await i3_conn.command(f'workspace {layout.workspace_num}; append_layout {layout_path}')

    # 2. Launch applications (they'll be swallowed into layout)
    for window_placeholder in layout.windows:
        await launch_application(window_placeholder.launch_command)
        await asyncio.sleep(0.1)  # Stagger launches

    # 3. Monitor swallow completion (timeout 5s per window)
    await wait_for_swallows(i3_conn, timeout=5.0)

    # 4. Apply marks to swallowed windows
    for window in await get_workspace_windows(i3_conn, layout.workspace_num):
        for mark in window_placeholder.marks:
            await i3_conn.command(f'[id={window.id}] mark {mark}')
```

**Testing**:
```bash
# Integration test - full save/restore cycle
pytest tests/i3pm-production/integration/test_layout_workflow.py::test_save_restore_cycle -v

# Scenario test - 15 windows, 3 workspaces
pytest tests/i3pm-production/scenarios/test_production_scale.py::test_layout_restore_complex -v
```

**Validation Criteria**:
- Restores layout without visible flicker (windows appear in final positions)
- Handles missing applications gracefully (warns user, continues with rest)
- Completes restoration in <5s for 15 windows
- 95%+ window position accuracy

---

### Task 1.3: Deno CLI - Layout Commands

**Location**: `home-modules/tools/i3pm-cli/src/commands/layout.ts`

**Steps**:
1. Implement `i3pm layout save` command with parseArgs()
2. Implement `i3pm layout restore` command
3. Implement `i3pm layout list` command
4. Implement `i3pm layout diff` command (compare saved vs current)
5. Add progress indicators using @std/cli utilities

**Key Implementation Points**:
```typescript
// layout.ts - Save command
export async function layoutSave(args: LayoutSaveArgs): Promise<void> {
  // Call daemon IPC: layout.save
  const response = await daemonClient.call("layout.save", {
    project: args.project,
    name: args.name,
    workspaces: args.workspaces,
    discover_commands: !args.noDiscovery,
  });

  // Display results
  console.log(`✓ Layout saved: ${response.layout_file}`);
  console.log(`  Workspaces: ${response.workspaces_captured}`);
  console.log(`  Windows: ${response.windows_captured}`);

  if (response.commands_missing.length > 0) {
    console.warn(`  Warning: ${response.commands_missing.length} windows without launch commands`);
    // Prompt for manual commands if interactive
  }
}
```

**Testing**:
```bash
# Deno unit tests
cd home-modules/tools/i3pm-cli
deno test src/commands/layout_test.ts -v

# Manual testing
i3pm layout save --project=nixos --name=test-layout
i3pm layout list --project=nixos
i3pm layout restore --project=nixos --name=test-layout --dry-run
i3pm layout restore --project=nixos --name=test-layout
```

**Validation Criteria**:
- Commands follow existing i3pm CLI patterns
- Progress indicators show during long operations
- Error messages provide actionable guidance
- --help output is comprehensive

---

## Phase 2: Production-Scale Validation

### Task 2.1: Synthetic Load Generation

**Location**: `home-modules/tools/i3-project-test/load_gen/`

**Steps**:
1. Implement window spawner (spawn N windows across projects)
2. Implement metrics collector (latency, memory, CPU)
3. Write load testing scenarios

**Key Implementation Points**:
```python
# window_spawner.py
async def spawn_windows(count: int, projects: list[str]) -> list[int]:
    """Spawn windows distributed across projects."""
    window_ids = []

    for i in range(count):
        project = projects[i % len(projects)]
        # Spawn lightweight window (xterm or similar)
        cmd = f'xterm -title "Load Test {i}" -e "sleep 3600"'
        subprocess.Popen(cmd, shell=True)
        await asyncio.sleep(0.05)  # Stagger spawns

        # Mark window with project
        # ... mark logic
        window_ids.append(window_id)

    return window_ids

# metrics_collector.py
class MetricsCollector:
    async def collect_switch_latency(self, project: str) -> float:
        start = time.time()
        await switch_project(project)
        return (time.time() - start) * 1000  # ms

    def get_daemon_memory_mb(self) -> float:
        pid = get_daemon_pid()
        proc = psutil.Process(pid)
        return proc.memory_info().rss / 1024 / 1024
```

**Testing Scenarios**:
```bash
# Scenario 1: 500 windows, 10 projects, 100 project switches
pytest tests/i3pm-production/scenarios/test_production_scale.py::test_500_windows -v

# Scenario 2: 30-day uptime simulation (compressed time)
pytest tests/i3pm-production/scenarios/test_30day_uptime.py -v

# Scenario 3: Monitor reconfiguration during load
pytest tests/i3pm-production/scenarios/test_monitor_stress.py -v
```

**Success Criteria** (from spec SC-001, SC-002, SC-008, SC-009):
- Project switch <300ms (p95) for 50 windows
- Memory stays below 50MB with 500+ windows
- CPU <1% idle, <5% active
- Monitor reconfiguration <2s (p95)

---

### Task 2.2: Memory Leak Detection

**Strategy**: Run daemon for extended period (simulated 30 days) with periodic memory measurements.

```python
# test_30day_uptime.py
async def test_memory_stability():
    baseline_memory = get_daemon_memory_mb()

    # Simulate 30 days of activity (100,000 events)
    for _ in range(100_000):
        await simulate_event()  # window open/close, project switch, etc.

        if (_ % 10_000 == 0):
            current_memory = get_daemon_memory_mb()
            growth = current_memory - baseline_memory
            assert growth < 10, f"Memory leak detected: {growth}MB growth"

    final_memory = get_daemon_memory_mb()
    assert final_memory < 50, f"Memory usage too high: {final_memory}MB"
```

---

## Phase 3: Error Recovery and Resilience

### Task 3.1: Daemon Recovery Module

**Location**: `home-modules/tools/i3-project-daemon/recovery/`

**Steps**:
1. Implement state validator (compare daemon state vs i3 IPC)
2. Implement automatic recovery (rebuild state from i3 marks)
3. Add reconnection logic for i3 IPC failures

**Key Implementation Points**:
```python
# recovery.py
async def recover_from_i3_restart():
    """Recover daemon state after i3 restarts."""
    logger.info("i3 restart detected, rebuilding state...")

    # Reconnect to i3
    i3_conn = await connect_to_i3_with_retry(max_attempts=5)

    # Rebuild state from i3 marks (authoritative source)
    marks = await i3_conn.get_marks()
    project_marks = [m for m in marks if m.startswith("project:")]

    # Reconstruct in-memory state
    window_project_map = {}
    for mark in project_marks:
        project_name = mark.replace("project:", "")
        windows = await get_windows_with_mark(i3_conn, mark)
        for window in windows:
            window_project_map[window.id] = project_name

    logger.info(f"State rebuilt: {len(window_project_map)} windows tracked")
    return window_project_map
```

**Testing**:
```bash
# Integration test - daemon recovery
pytest tests/i3pm-production/integration/test_daemon_recovery.py::test_i3_restart -v

# Scenario test - daemon crash during project switch
pytest tests/i3pm-production/scenarios/test_error_recovery.py::test_partial_switch_recovery -v
```

**Success Criteria** (SC-010):
- Recovery completes within 5s (99% of cases)
- State fully restored from i3 marks
- No manual intervention required

---

## Phase 4: User Onboarding Tools

### Task 4.1: Interactive Project Creation Wizard

**Location**: `home-modules/tools/i3pm-cli/src/commands/project.ts` (extend), `src/ui/wizard.ts` (new)

**Implementation**:
```typescript
// wizard.ts - Interactive prompts
import { prompt, promptSecret } from "@std/cli";

export async function projectCreationWizard(): Promise<ProjectConfig> {
  console.log("=== i3pm Project Creation Wizard ===\n");

  const name = await prompt("Project name (lowercase, alphanumeric + hyphens):");
  const displayName = await prompt("Display name:", { default: name });
  const directory = await prompt("Project directory (absolute path):");

  // Suggest classifications based on currently open windows
  const suggestions = await suggestClassifications();
  console.log("\nRecommended application classifications:");
  suggestions.forEach(s => console.log(`  ${s.class} → ${s.scope_type}`));

  const customizeClasses = await confirm("Customize classifications?");
  // ... classification customization

  return { name, displayName, directory, scopedClasses: [...] };
}
```

**Testing**:
```bash
# Manual testing (interactive)
i3pm project create --interactive

# Automated testing (mock prompts)
deno test src/ui/wizard_test.ts -v
```

---

### Task 4.2: i3pm doctor Command

**Location**: `home-modules/tools/i3pm-cli/src/commands/doctor.ts` (new)

**Implementation**:
```typescript
// doctor.ts - Configuration validation and diagnostics
export async function runDoctor(): Promise<DiagnosticReport> {
  const checks: DiagnosticCheck[] = [
    checkDaemonRunning(),
    checkI3Connection(),
    checkProjectConfigs(),
    checkClassificationRules(),
    checkLayoutFiles(),
    checkMonitorConfig(),
  ];

  console.log("Running i3pm diagnostics...\n");

  for (const check of checks) {
    const result = await check.run();
    console.log(`${result.passed ? '✓' : '✗'} ${check.name}`);

    if (!result.passed) {
      console.log(`  Error: ${result.error}`);
      console.log(`  Fix: ${result.suggestedFix}`);
    }
  }

  return { checks, allPassed: checks.every(c => c.passed) };
}
```

**Common Checks**:
- Daemon running and responsive
- i3 IPC connection established
- Project configuration files valid JSON
- Classification rules have valid regex patterns
- Layout files have correct schema version
- Monitor configurations reference existing outputs

---

## Phase 5: Security Hardening

### Task 5.1: IPC Authentication

**Location**: `home-modules/tools/i3-project-daemon/security/auth.py` (new)

**Implementation**:
```python
# auth.py - UID-based authentication
import socket
import struct
import os

async def authenticate_ipc_client(sock: socket.socket) -> bool:
    """Authenticate client via UNIX socket peer credentials."""
    try:
        # Get peer credentials (Linux SO_PEERCRED)
        creds = sock.getsockopt(
            socket.SOL_SOCKET,
            socket.SO_PEERCRED,
            struct.calcsize('3i')
        )
        pid, uid, gid = struct.unpack('3i', creds)

        # Verify UID matches daemon's UID
        if uid != os.getuid():
            logger.warning(f"IPC authentication failed: UID {uid} != {os.getuid()}")
            raise PermissionError(f"UID mismatch: expected {os.getuid()}, got {uid}")

        logger.debug(f"IPC client authenticated: PID {pid}, UID {uid}")
        return True

    except Exception as e:
        logger.error(f"Authentication error: {e}")
        return False
```

**Testing**:
```bash
# Unit test
pytest tests/i3pm-production/unit/test_ipc_auth.py -v

# Integration test - attempt connection from different UID (should fail)
sudo -u otheruser i3pm daemon status  # Should error: UID mismatch
```

---

### Task 5.2: Sensitive Data Sanitization

**Location**: `home-modules/tools/i3-project-daemon/security/sanitize.py` (new)

**Implementation**:
```python
# sanitize.py - Regex-based sanitization
import re

SANITIZE_PATTERNS = [
    (r'(api[_-]?key|token|secret)[=:\s]+[A-Za-z0-9_-]{20,}', 'API_KEY_REDACTED'),
    (r'Bearer\s+[A-Za-z0-9_-]{20,}', 'BEARER_TOKEN_REDACTED'),
    (r'(password|passwd|pwd)[=:\s]+\S+', 'PASSWORD_REDACTED'),
    # ... more patterns from research.md
]

def sanitize_text(text: str) -> str:
    """Remove sensitive patterns from text."""
    for pattern, replacement in SANITIZE_PATTERNS:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return text

def sanitize_event(event: Event) -> Event:
    """Sanitize event data before logging/export."""
    if "command_line" in event.data:
        event.data["command_line"] = sanitize_text(event.data["command_line"])
    if "window_title" in event.data:
        event.data["window_title"] = sanitize_text(event.data["window_title"])
    return event
```

**Testing**:
```bash
# Unit test
pytest tests/i3pm-production/unit/test_sanitization.py -v

# Verify sanitization in logs
i3pm daemon events --limit=50 | grep -E "(password|token|key)"  # Should show REDACTED
```

---

## Phase 6: Integration and Validation

### Task 6.1: Complete Test Suite Execution

```bash
# Run all unit tests
pytest tests/i3pm-production/unit/ -v --cov=home-modules/tools/i3-project-daemon

# Run all integration tests
pytest tests/i3pm-production/integration/ -v

# Run all scenario tests (includes load tests)
pytest tests/i3pm-production/scenarios/ -v

# Generate coverage report
pytest --cov=home-modules/tools/i3-project-daemon --cov-report=html
# View: htmlcov/index.html

# Target: 80%+ code coverage (SC-007)
```

---

### Task 6.2: Performance Validation

**Verify Success Criteria**:
```bash
# SC-001: Project switch latency <300ms (p95) for 50 windows
pytest tests/i3pm-production/scenarios/test_production_scale.py::test_switch_latency -v

# SC-002: 30-day uptime without memory leaks
pytest tests/i3pm-production/scenarios/test_30day_uptime.py -v

# SC-008: CPU usage <1% idle, <5% active
# Monitor during normal operation
ps aux | grep i3-project-event-listener

# SC-009: Monitor reconfiguration <2s (p95)
pytest tests/i3pm-production/scenarios/test_monitor_stress.py -v
```

**Generate Performance Report**:
```python
# Run load tests and collect metrics
results = await run_performance_tests()

# Generate report
generate_report(results, output="performance-report.json")

# Verify all success criteria met
assert results.switch_latency_p95 < 300  # ms
assert results.memory_max < 50  # MB
assert results.cpu_idle_avg < 1  # %
assert results.monitor_reconfig_p95 < 2000  # ms
```

---

### Task 6.3: User Acceptance Testing

**Manual Testing Checklist**:
- [ ] Create new project via wizard (`i3pm project create --interactive`)
- [ ] Switch between 3 projects with 10+ windows each
- [ ] Save layout with 15 windows across 3 workspaces
- [ ] Restart i3 and restore layout
- [ ] Verify layout restoration accuracy (positions, sizes)
- [ ] Run `i3pm doctor` and verify all checks pass
- [ ] Disconnect/reconnect monitor and verify workspace reassignment
- [ ] Check daemon status after 24 hours uptime
- [ ] Export diagnostic report and verify no sensitive data leaked

---

## Phase 7: Legacy Code Deletion

### Task 7.1: Identify and Remove Legacy Python TUI

**Critical Step**: Delete legacy code in same commit as new features.

```bash
# Find all references to legacy TUI
grep -r "i3-project-manager" home-modules/
grep -r "i3-project-manager" configurations/
grep -r "i3-project-manager" flake.nix

# Verify what's being deleted
du -sh home-modules/tools/i3-project-manager/
# Should show ~15,445 LOC

# Remove the entire directory
rm -rf home-modules/tools/i3-project-manager/

# Remove from NixOS config
# Edit home-modules/tools/default.nix - remove i3-project-manager import
# Edit any files that reference the old TUI

# Remove deprecated shell aliases (if any point to old TUI)
grep -r "i3-project-manager" home-modules/shell/
# Remove any aliases that call old commands

# Verify no remnants
git status  # Should show i3-project-manager/ as deleted
git grep "i3-project-manager"  # Should return nothing or only historical references
```

**Validation**:
```bash
# Ensure system still builds without legacy code
sudo nixos-rebuild dry-build --flake .#hetzner

# Should succeed - legacy code fully removed
```

---

## Phase 8: Documentation and Deployment

### Task 8.1: Update Documentation

**Files to Update**:
1. `/etc/nixos/CLAUDE.md` - Add production readiness features
2. `/etc/nixos/docs/I3PM_ARCHITECTURE.md` - Document new modules
3. `/etc/nixos/specs/030-review-our-i3pm/quickstart.md` - This file (finalize)
4. Add `/etc/nixos/docs/I3PM_TROUBLESHOOTING.md` - Common issues and fixes

**Documentation Requirements** (from spec):
- Architecture documentation
- Troubleshooting guide
- API documentation (daemon-ipc.json)
- Security documentation (threat model)
- Migration guide (if needed)
- Testing guide
- Performance tuning guide

---

### Task 7.2: One-Time Migration Tool

**Purpose**: Help users migrate existing project definitions, then delete itself.

**Implementation**: `home-modules/tools/i3pm-cli/src/commands/migrate.ts`

```typescript
// migrate.ts - Self-deleting migration command
export async function migrateFromLegacy(): Promise<void> {
  console.log("=== i3pm Legacy Migration (One-Time) ===\n");

  // 1. Find old project configs
  const legacyPath = "~/.config/i3-project-manager/projects/";
  const legacyProjects = await findLegacyProjects(legacyPath);

  if (legacyProjects.length === 0) {
    console.log("✓ No legacy projects found. Migration not needed.");
    return;
  }

  console.log(`Found ${legacyProjects.length} legacy projects:\n`);
  legacyProjects.forEach(p => console.log(`  - ${p.name}`));

  // 2. Convert to new format
  for (const legacy of legacyProjects) {
    const newProject = convertToNewFormat(legacy);
    await saveProject(newProject);
    console.log(`✓ Migrated: ${legacy.name}`);
  }

  // 3. Delete old configs
  await Deno.remove(legacyPath, { recursive: true });
  console.log("\n✓ Deleted legacy configuration directory");

  // 4. Remove this migration command from CLI
  console.log("\n✓ Migration complete. This command will now be removed.");
  await removeMigrationCommand();  // Delete migrate.ts and references

  console.log("\nRestart your shell to complete migration.");
}
```

**Usage** (one-time only):
```bash
# User runs once
i3pm migrate-from-legacy

# Command migrates, then deletes itself
# Subsequent runs: command not found (intentional)
```

---

### Task 7.3: NixOS Integration

**Update NixOS Configuration**:
```nix
# home-modules/tools/default.nix
# Ensure new modules are included
./i3-project-daemon/layout
./i3-project-daemon/monitoring
./i3-project-daemon/security
./i3-project-daemon/recovery

# No changes to systemd service - extends existing daemon
```

**Apply Changes**:
```bash
# Test configuration
sudo nixos-rebuild dry-build --flake .#hetzner

# Apply to reference platform (Hetzner i3wm)
sudo nixos-rebuild switch --flake .#hetzner

# Test on other platforms
# WSL
sudo nixos-rebuild switch --flake .#wsl

# M1 Mac
sudo nixos-rebuild switch --flake .#m1 --impure
```

---

### Task 7.3: Git Commit and Documentation

```bash
# Stage all changes INCLUDING deletions
git add specs/030-review-our-i3pm/
git add home-modules/tools/i3-project-daemon/
git add home-modules/tools/i3pm-cli/
git add tests/i3pm-production/
git add docs/

# Stage legacy code deletion (CRITICAL)
git add -A home-modules/tools/i3-project-manager/  # Captures deletion of 15,445 LOC
git add home-modules/tools/default.nix             # Removes legacy import
git add home-modules/shell/                         # Remove legacy aliases

# Verify deletions staged
git status | grep "deleted:"  # Should show i3-project-manager files

# Commit with comprehensive message
git commit -m "feat(i3pm): Complete production readiness + DELETE legacy TUI (Feature 030)

NEW FEATURES:
- Layout persistence and restoration with launch command discovery
- Production-scale validation (500+ windows, 30-day uptime)
- Error recovery and automatic state rebuilding
- User onboarding tools (wizard, doctor command)
- Security hardening (IPC auth, sensitive data sanitization)
- Comprehensive test suite (80%+ coverage)
- One-time migration: i3pm migrate-from-legacy

LEGACY CODE DELETED (Forward-Only Development):
- ❌ Removed entire i3-project-manager/ directory (15,445 LOC)
- ❌ Deleted legacy Python TUI completely
- ❌ No backwards compatibility layers
- ❌ No feature flags or dual support
- ✅ Optimal solution only

Success criteria validated:
- SC-001: Project switch <300ms (p95) ✓
- SC-002: 30-day uptime without leaks ✓
- SC-007: 80%+ test coverage ✓
- SC-008: CPU <1% idle, <5% active ✓

Constitution Principle XII enforced: Clean break from legacy.

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

# Push to remote
git push origin 030-review-our-i3pm
```

---

## Success Validation Checklist

Before considering feature complete, verify:

### Functional Requirements
- [ ] FR-001-006: Core stability (500+ windows, auto-recovery, error reporting)
- [ ] FR-007-014: Layout persistence (save, restore, command discovery, flicker-free)
- [ ] FR-015-019: Monitor management (detection, reassignment, validation)
- [ ] FR-020-025: Monitoring and diagnostics (health metrics, snapshots, correlation)
- [ ] FR-026-029: Testing (automated suite, synthetic load, schema validation)
- [ ] FR-030-034: Security (IPC auth, sanitization, multi-user isolation)
- [ ] FR-035-039: User experience (wizard, doctor, tutorials, help)
- [ ] FR-040-042: Backwards compatibility (import legacy, migration tool)

### Success Criteria
- [ ] SC-001: Project switch <300ms (p95) for 50 windows
- [ ] SC-002: 30-day uptime, <50MB memory, 10k+ events
- [ ] SC-003: Layout restore 95% accuracy (positions/sizes)
- [ ] SC-004: Layout restoration without flicker (90% of cases)
- [ ] SC-005: New user setup <15 minutes
- [ ] SC-006: 90% bugs diagnosed with built-in tools
- [ ] SC-007: 80%+ test coverage
- [ ] SC-008: CPU <1% idle, <5% active
- [ ] SC-009: Monitor reconfig <2s (p95)
- [ ] SC-010: Daemon recovery <5s (99% of cases)
- [ ] SC-011: Clear error messages (100% of cases)
- [ ] SC-012: Event correlation >80% confidence (75% of cases)

### Platform Testing
- [ ] Hetzner i3wm (reference platform)
- [ ] WSL (headless)
- [ ] M1 Mac (ARM64)
- [ ] Containers (minimal profile)

### Constitution Compliance
- [ ] No violations introduced
- [ ] Modular composition maintained
- [ ] Test-before-apply followed
- [ ] Documentation updated
- [ ] Forward-only development (no backwards compat layers)

---

## Troubleshooting

### Common Issues

**Issue**: Layout restore fails with "command not found"
**Solution**: Run `i3pm doctor` to validate launch commands. Manually specify commands for missing applications.

**Issue**: High memory usage after 24 hours
**Solution**: Check for memory leaks with `pytest tests/i3pm-production/scenarios/test_30day_uptime.py`. Review event buffer pruning logic.

**Issue**: Project switch latency >500ms
**Solution**: Profile with `i3pm daemon events --follow` during switch. Check for blocking i3 IPC calls. Verify CPU not throttled.

**Issue**: Test suite fails on WSL
**Solution**: Ensure systemd user services enabled (`systemctl --user status`). Check X11 display available (`echo $DISPLAY`).

---

## Next Steps

After completing Feature 030, consider:
1. **Feature 031**: Browser profile management per project
2. **Feature 032**: AI-powered project detection from git repos
3. **Feature 033**: Project templates marketplace
4. **Feature 034**: Advanced layout features (diff, merge, i3-resurrect compatibility)
5. **Feature 035**: Performance optimizations for >1000 windows

---

## References

- **Specification**: [spec.md](./spec.md)
- **Implementation Plan**: [plan.md](./plan.md)
- **Research Decisions**: [research.md](./research.md)
- **Data Model**: [data-model.md](./data-model.md)
- **API Contracts**: [contracts/](./contracts/)
- **Constitution**: [.specify/memory/constitution.md](../.specify/memory/constitution.md)

---

**Status**: Ready for implementation (Phase 2 complete)
**Last Updated**: 2025-10-23
