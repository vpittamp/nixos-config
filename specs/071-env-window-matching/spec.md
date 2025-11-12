# Feature Specification: Environment Variable-Based Window Matching

**Feature Branch**: `057-env-window-matching`
**Created**: 2025-11-03
**Status**: Draft
**Input**: User description: "create a new feature to explore how we match windows in our python module that manages our sway windows/workspaces/projects etc;  we've updated our logic to inject environment variables when we launch applications that corresond to the current project, use a unique app id, etc.  we used to only do this for regular applications, but we've now succesfully implemented this for firefox pwa's.  given this is the case, i want to explore whether our window matching logic (and perhaps other operations) can be simplified to use environment variables to understand the nature of the application (application type, instance, etc.) instead of having multiple levels of logic that involve non-deterministic properties such as window class, title, etc.  we must test to be sure the environment variables result in a determistic method, and there are no gaps in our process of assigning the environment variables, etc;  we also need to make sure that querying for environment variables provides a reasonable performance in terms of latency.  if it does meet these requirements, then this might simplify our logic in several places, and could be foundational to our system of managing projects, restoring layouts, navigating, etc.  don't worry about backwards compatibility.  determine the optimal solution, and then implement it, discarding legacy approaches, code, files that are no longer part of the optimal solution."

## User Scenarios & Testing *(mandatory)*

**Test-Driven Development Approach** (Principle XIV):
- All tests MUST be written BEFORE implementation
- Tests MUST execute autonomously without manual intervention
- State verification via Sway IPC tree queries when UI simulation not needed
- Test suite MUST be runnable in headless CI/CD environment
- Follow test-first iteration: spec → tests → implement → run → fix → repeat until passing

### User Story 1 - Deterministic Window Identification (Priority: P1)

When a user launches any application (regular application or Firefox PWA), the system must reliably identify that window using environment variables injected at launch time, without relying on non-deterministic properties like window class or title.

**Why this priority**: This is the foundational capability that all other features depend on. Without deterministic window identification, project management, workspace assignment, and layout restoration cannot work reliably.

**Test Automation Strategy**:
- **Type**: Integration test (Sway IPC + /proc filesystem)
- **Approach**: Programmatic application launch + state verification
- **Tools**: pytest-asyncio, i3ipc.aio (Sway IPC), /proc filesystem access
- **Execution**: Fully autonomous - no UI simulation needed
- **Validation**: Query Sway IPC tree for window, read /proc/<pid>/environ, assert I3PM_* variables present

**Automated Test Implementation**:
```python
@pytest.mark.asyncio
async def test_deterministic_window_identification():
    """Test window identification via I3PM_* environment variables."""
    # Launch VS Code programmatically with project context
    proc = await asyncio.create_subprocess_exec(
        "i3pm", "app", "launch", "vscode",
        env={**os.environ, "I3PM_PROJECT_NAME": "nixos"}
    )
    await asyncio.sleep(0.5)  # Wait for window creation

    # Query Sway IPC for new window
    async with i3ipc.aio.Connection() as sway:
        tree = await sway.get_tree()
        vscode_windows = find_windows_by_class(tree, "Code")
        assert len(vscode_windows) > 0, "VS Code window not created"

        window = vscode_windows[-1]  # Most recent window

        # Read environment variables from /proc
        env_vars = read_process_environ(window.pid)

        # Assert I3PM_* variables present
        assert "I3PM_APP_ID" in env_vars
        assert env_vars["I3PM_APP_NAME"] == "vscode"
        assert env_vars["I3PM_PROJECT_NAME"] == "nixos"

        # Assert unique instance ID
        assert env_vars["I3PM_APP_ID"].startswith("vscode-nixos-")
```

**Acceptance Scenarios**:

1. **Given** a user launches VS Code from project "nixos", **When** the window appears in Sway, **Then** the system reads I3PM_PROJECT_NAME="nixos", I3PM_APP_NAME="vscode", and I3PM_APP_ID from the window's process environment
2. **Given** a user launches two different Firefox PWAs (e.g., Claude and YouTube), **When** both windows appear, **Then** each window has distinct I3PM_APP_ID values and correct I3PM_APP_NAME values
3. **Given** a user launches the same application twice in the same project, **When** both windows appear, **Then** each window has the same I3PM_APP_NAME and I3PM_PROJECT_NAME but different I3PM_APP_ID values
4. **Given** a window from a native Wayland application (app_id available), **When** the system checks its identity, **Then** the system uses environment variables instead of app_id for identification
5. **Given** a window from an XWayland application (only window class available), **When** the system checks its identity, **Then** the system uses environment variables instead of window class for identification

---

### User Story 2 - Environment Variable Coverage Validation (Priority: P1)

The system must validate that all launched applications (100% coverage) receive the required I3PM_* environment variables, with no gaps in the injection process.

**Why this priority**: Any gap in environment variable injection breaks the deterministic identification model. This must be verified before relying on environment variables as the primary identification mechanism.

**Test Automation Strategy**:
- **Type**: Integration test (application registry + Sway IPC + /proc)
- **Approach**: Parametrized tests for all registered applications
- **Tools**: pytest-asyncio with @pytest.mark.parametrize, app registry parser
- **Execution**: Fully autonomous - launches apps programmatically, validates coverage
- **Validation**: Query all windows, check I3PM_* presence, report coverage percentage

**Automated Test Implementation**:
```python
@pytest.mark.parametrize("app_name", get_all_registered_apps())
@pytest.mark.asyncio
async def test_environment_variable_coverage(app_name):
    """Test that all registered apps have I3PM_* environment variables."""
    # Launch application programmatically
    proc = await asyncio.create_subprocess_exec(
        "i3pm", "app", "launch", app_name
    )
    await asyncio.sleep(0.5)  # Wait for window creation

    # Query Sway for new window
    async with i3ipc.aio.Connection() as sway:
        tree = await sway.get_tree()
        windows = find_windows_by_app_name(tree, app_name)

        assert len(windows) > 0, f"{app_name} window not created"
        window = windows[-1]

        # Read environment from /proc
        env_vars = read_process_environ(window.pid)

        # Assert required I3PM_* variables present
        assert "I3PM_APP_ID" in env_vars, f"{app_name}: Missing I3PM_APP_ID"
        assert "I3PM_APP_NAME" in env_vars, f"{app_name}: Missing I3PM_APP_NAME"
        assert "I3PM_SCOPE" in env_vars, f"{app_name}: Missing I3PM_SCOPE"

        # Validate values
        assert env_vars["I3PM_APP_NAME"] == app_name
        assert env_vars["I3PM_SCOPE"] in ("global", "scoped")

# Coverage validation test
@pytest.mark.asyncio
async def test_overall_coverage_percentage():
    """Test that 100% of launched windows have I3PM_* variables."""
    report = await validate_environment_coverage()

    assert report.coverage_percentage == 100.0, \
        f"Coverage: {report.coverage_percentage}%, expected 100%"
    assert report.status == "PASS"
    assert len(report.missing_windows) == 0
```

**Acceptance Scenarios**:

1. **Given** the system has N registered applications in the app registry, **When** each application is launched, **Then** 100% of windows have I3PM_APP_ID, I3PM_APP_NAME, and I3PM_SCOPE environment variables
2. **Given** a user launches a Firefox PWA, **When** the PWA window appears, **Then** the window's process has I3PM_APP_ID, I3PM_APP_NAME, I3PM_SCOPE, and I3PM_PROJECT_NAME (if launched from a project)
3. **Given** a user launches an application without an active project, **When** the window appears, **Then** I3PM_PROJECT_NAME and I3PM_PROJECT_DIR are empty strings (not missing)
4. **Given** a child process spawned by a launched application, **When** checking its environment, **Then** the child process inherits all I3PM_* variables from the parent or the system can traverse to the parent to find them
5. **Given** an application launched via command line instead of the launcher, **When** the window appears, **Then** the system detects missing I3PM_* variables and logs a warning

---

### User Story 3 - Performance Benchmark for Environment Variable Queries (Priority: P1)

The system must measure the latency of querying environment variables from /proc/<pid>/environ to ensure it meets performance requirements for real-time window management.

**Why this priority**: If environment variable queries are too slow, they will create lag in window management operations, degrading user experience. Performance validation is essential before replacing existing logic.

**Test Automation Strategy**:
- **Type**: Performance/benchmark test
- **Approach**: Measure latency statistics (avg, p50, p95, p99, max) for /proc reads
- **Tools**: pytest-benchmark or custom timing harness with statistics library
- **Execution**: Fully autonomous - creates test processes, measures /proc read times
- **Validation**: Assert p95 latency < 10ms, average < 1ms, handles 100 windows in <100ms

**Automated Test Implementation**:
```python
@pytest.mark.benchmark
@pytest.mark.asyncio
async def test_environment_query_performance():
    """Benchmark /proc/<pid>/environ read performance."""
    import time
    import statistics

    # Create test processes with known environments
    test_pids = []
    for i in range(100):
        proc = await asyncio.create_subprocess_exec(
            "sleep", "60",
            env={**os.environ, f"TEST_VAR_{i}": "value"}
        )
        test_pids.append(proc.pid)

    # Benchmark environment reads
    latencies_ms = []
    for pid in test_pids:
        start = time.perf_counter()
        env_vars = read_process_environ(pid)
        end = time.perf_counter()
        latencies_ms.append((end - start) * 1000)  # Convert to ms

    # Calculate statistics
    avg_latency = statistics.mean(latencies_ms)
    p50 = statistics.median(latencies_ms)
    p95 = sorted(latencies_ms)[int(len(latencies_ms) * 0.95)]
    p99 = sorted(latencies_ms)[int(len(latencies_ms) * 0.99)]
    max_latency = max(latencies_ms)

    # Assert performance requirements
    assert avg_latency < 1.0, \
        f"Average latency {avg_latency:.2f}ms exceeds 1ms target"
    assert p95 < 10.0, \
        f"p95 latency {p95:.2f}ms exceeds 10ms target"
    assert sum(latencies_ms) < 100.0, \
        f"Total time {sum(latencies_ms):.2f}ms exceeds 100ms for 100 windows"

    # Cleanup test processes
    for proc in test_pids:
        os.kill(proc, signal.SIGTERM)

    # Log performance report
    print(f"\nPerformance Benchmark Results:")
    print(f"  Samples: {len(latencies_ms)}")
    print(f"  Average: {avg_latency:.2f}ms")
    print(f"  p50: {p50:.2f}ms")
    print(f"  p95: {p95:.2f}ms")
    print(f"  p99: {p99:.2f}ms")
    print(f"  Max: {max_latency:.2f}ms")
    print(f"  Status: PASS")
```

**Acceptance Scenarios**:

1. **Given** the system needs to identify a newly created window, **When** reading environment variables from /proc/<pid>/environ, **Then** the operation completes in under 10ms on average
2. **Given** the system needs to filter 50 windows based on project association, **When** reading environment variables for all windows, **Then** the total operation completes in under 100ms
3. **Given** a window's direct PID has no I3PM_* variables, **When** traversing up to 3 parent processes, **Then** the environment lookup completes in under 20ms
4. **Given** a process that has exited before environment query, **When** attempting to read /proc/<pid>/environ, **Then** the system handles FileNotFoundError gracefully without crashing and completes in under 5ms
5. **Given** high system load (100+ processes), **When** querying multiple window environments simultaneously, **Then** the system maintains sub-10ms average latency per query

---

### User Story 4 - Simplified Window Matching Logic (Priority: P2)

After validating deterministic identification and performance, the system should replace multi-level fallback logic (app_id → window class → title matching) with environment variable-based identification.

**Why this priority**: Simplification reduces code complexity and eliminates race conditions from non-deterministic properties. This is a high-value refactor but depends on P1 validation.

**Independent Test**: Can be tested by removing old matching logic (app_id, window class, title) and verifying all window identification operations work correctly using only environment variables. Delivers simplified codebase.

**Acceptance Scenarios**:

1. **Given** a window appears in Sway, **When** the system needs to identify its application type, **Then** it reads I3PM_APP_NAME instead of checking app_id or window class
2. **Given** a window with multiple instances, **When** the system needs to distinguish between instances, **Then** it uses I3PM_APP_ID instead of window title patterns
3. **Given** the old window matching code paths (app_id, class, title fallbacks), **When** refactoring is complete, **Then** these code paths are removed entirely
4. **Given** a Firefox PWA that previously required window class pattern matching, **When** identifying the window, **Then** the system uses I3PM_APP_NAME without class-based logic
5. **Given** workspace assignment rules, **When** determining where to place a new window, **Then** the system reads I3PM_TARGET_WORKSPACE instead of looking up workspace by window class

---

### User Story 5 - Project Association via Environment Variables (Priority: P2)

The system should determine window-to-project association by reading I3PM_PROJECT_NAME from the process environment, replacing mark-based or tag-based association.

**Why this priority**: Project association is a core capability for window filtering and project switching. Environment-based association is more reliable than marks but requires P1 validation first.

**Independent Test**: Can be tested by switching between projects and verifying window visibility is controlled by I3PM_PROJECT_NAME and I3PM_SCOPE. Delivers deterministic project filtering.

**Acceptance Scenarios**:

1. **Given** a window launched in project "nixos", **When** checking project association, **Then** I3PM_PROJECT_NAME="nixos" indicates the window belongs to that project
2. **Given** a global application (I3PM_SCOPE="global"), **When** switching projects, **Then** the window remains visible regardless of I3PM_PROJECT_NAME
3. **Given** a scoped application (I3PM_SCOPE="scoped"), **When** switching to a different project, **Then** the window hides because I3PM_PROJECT_NAME doesn't match the active project
4. **Given** the old mark-based filtering logic, **When** refactoring is complete, **Then** all project association uses environment variables and mark-based code is removed
5. **Given** a window with I3PM_PROJECT_NAME="personal", **When** the user switches to project "nixos", **Then** the window moves to scratchpad without checking window marks

---

### User Story 6 - Layout Restoration via Environment Variables (Priority: P3)

The system should use environment variables to restore window layouts, matching saved windows by I3PM_APP_ID and I3PM_APP_NAME instead of window class or title.

**Why this priority**: Layout restoration enhances user productivity but is not critical for basic functionality. This builds on the simplified matching logic from P2.

**Independent Test**: Can be tested by saving a layout with multiple windows, closing all windows, launching them again, and verifying they restore to saved positions using I3PM_APP_ID matching. Delivers layout persistence.

**Acceptance Scenarios**:

1. **Given** a saved layout with 5 windows identified by I3PM_APP_ID, **When** restoring the layout, **Then** the system launches applications and matches windows by I3PM_APP_ID to restore positions
2. **Given** a window that existed when the layout was saved, **When** the same window (same I3PM_APP_ID) is launched, **Then** it appears on the workspace and position from the saved layout
3. **Given** a layout saved with window classes/titles (old format), **When** attempting to restore, **Then** the system migrates to I3PM_APP_ID-based matching
4. **Given** multiple instances of the same application (same I3PM_APP_NAME, different I3PM_APP_ID), **When** restoring layout, **Then** each instance restores to its correct position based on I3PM_APP_ID
5. **Given** a window whose I3PM_APP_ID no longer exists, **When** restoring layout, **Then** the system reports missing window and continues with remaining windows

---

### Edge Cases

- What happens when a process exits before its environment variables can be read? (FileNotFoundError handling, graceful degradation to fallback identification if needed)
- How does the system handle child processes that don't inherit I3PM_* variables? (Parent PID traversal up to 3 levels)
- What happens when reading /proc/<pid>/environ fails due to permission denied? (Log warning, treat as unmanaged window)
- How does the system identify windows launched outside the launcher (e.g., from command line)? (Missing I3PM_* variables, fallback to unmanaged window classification)
- What happens if a Firefox PWA is launched manually without environment injection? (Detected as gap in coverage, validation test should catch this)
- How does the system handle race conditions where window appears before PID is available? (Delayed property re-check with 100ms retry, as implemented in Feature 053)
- What happens when /proc/<pid>/environ contains invalid UTF-8? (Skip invalid variables, continue with valid ones)
- How does the system perform when querying 100+ windows simultaneously? (Async I/O, parallel queries, target <1 second total for 100 windows)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST read I3PM_APP_ID, I3PM_APP_NAME, I3PM_PROJECT_NAME, I3PM_PROJECT_DIR, I3PM_SCOPE from /proc/<pid>/environ for every window
- **FR-002**: System MUST validate that 100% of launched applications (regular apps and PWAs) have I3PM_APP_ID and I3PM_APP_NAME environment variables
- **FR-003**: System MUST query /proc/<pid>/environ with average latency under 10ms per window
- **FR-004**: System MUST handle FileNotFoundError (process exited) and PermissionError (access denied) gracefully without crashing
- **FR-005**: System MUST traverse up to 3 parent processes to find I3PM_* variables if child process doesn't have them
- **FR-006**: System MUST identify windows by I3PM_APP_NAME instead of app_id, window_class, or window_properties
- **FR-007**: System MUST distinguish between window instances using I3PM_APP_ID instead of window title
- **FR-008**: System MUST determine project association using I3PM_PROJECT_NAME instead of window marks
- **FR-009**: System MUST determine window scope (global vs scoped) using I3PM_SCOPE instead of registry lookups based on class
- **FR-010**: System MUST remove all code paths that use app_id, window_class, or title for primary window identification (these may remain for diagnostic logging only)
- **FR-011**: System MUST provide benchmark tool to measure environment variable query latency across N windows
- **FR-012**: System MUST log validation report showing coverage percentage (windows with I3PM_* variables / total windows launched)
- **FR-013**: System MUST report performance metrics (p50, p95, p99 latency) for environment variable queries
- **FR-014**: System MUST save window layouts using I3PM_APP_ID as the primary identifier
- **FR-015**: System MUST restore window layouts by matching I3PM_APP_ID between saved state and current windows
- **FR-016**: System MUST detect windows launched outside the launcher (missing I3PM_* variables) and classify them as unmanaged
- **FR-017**: System MUST handle invalid UTF-8 in /proc/<pid>/environ by skipping invalid variables and continuing

### Key Entities

- **Window Environment**: Parsed I3PM_* environment variables from a window's process (I3PM_APP_ID, I3PM_APP_NAME, I3PM_PROJECT_NAME, I3PM_PROJECT_DIR, I3PM_SCOPE, I3PM_ACTIVE, I3PM_LAUNCH_TIME, I3PM_LAUNCHER_PID, I3PM_TARGET_WORKSPACE)
- **Window Identity**: Unique identifier for a window instance (I3PM_APP_ID) and application type (I3PM_APP_NAME)
- **Project Association**: Relationship between window and project based on I3PM_PROJECT_NAME and I3PM_SCOPE
- **Window Matching Rule**: Logic that determines which windows belong to a project, application type, or scope using environment variables
- **Performance Benchmark**: Measurement of latency for environment variable queries (average, p50, p95, p99, max)
- **Coverage Report**: Validation results showing percentage of windows with complete I3PM_* variables
- **Layout Snapshot**: Saved state of windows including I3PM_APP_ID, workspace, position, size for restoration

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: System achieves 100% environment variable coverage for all launched applications (0 gaps in injection)
- **SC-002**: Environment variable queries complete in under 10ms on average (95th percentile under 15ms)
- **SC-003**: Window identification operations complete in under 20ms end-to-end (including parent traversal if needed)
- **SC-004**: Window filtering for project switching completes in under 100ms for 50 windows
- **SC-005**: Codebase complexity reduces by at least 30% (measured by lines of code and cyclomatic complexity in window matching modules)
- **SC-006**: Zero regressions in window management functionality (all existing tests pass with new environment-based logic)
- **SC-007**: Layout restoration matches 100% of windows by I3PM_APP_ID (no mismatches or duplicate assignments)
- **SC-008**: System handles 100+ concurrent window environment queries in under 1 second total
- **SC-009**: Parent process traversal (up to 3 levels) completes in under 20ms for edge cases
- **SC-010**: Validation benchmark runs on every system start and reports coverage percentage to logs

## Assumptions

- All applications are launched through the centralized launcher that injects I3PM_* environment variables
- Child processes inherit environment variables from parent processes in most cases
- /proc filesystem is available and readable (standard Linux environment)
- Window PIDs are available via Sway IPC or xprop (already implemented in Feature 053)
- Performance benchmarks run on modern hardware (SSD for /proc access, multi-core CPU)
- Environment variables are set at process creation and remain constant for process lifetime
- Firefox PWAs are launched via firefoxpwa CLI with environment variable support (already implemented in Feature 056)
- System prioritizes correctness over backward compatibility (legacy matching logic can be removed)

## Out of Scope

- Backward compatibility with layouts saved using window class/title identifiers (migration to I3PM_APP_ID is acceptable)
- Support for applications not launched via the centralized launcher (these remain unmanaged)
- Real-time migration of existing window marks to environment variables (existing windows keep marks until next launch)
- Support for non-Linux operating systems (no /proc filesystem)
- Support for X11-only systems without Wayland (system is Sway-focused)
- Performance optimization beyond stated latency targets (10ms average is sufficient)
- Environment variable encryption or security (I3PM_* variables are not sensitive)

---

## Test Execution Plan *(Principle XIV - Test-Driven Development)*

This feature follows **Principle XIV: Test-Driven Development & Autonomous Testing** from the constitution.

### Test-First Development Workflow

1. **Write Tests BEFORE Implementation**:
   - Phase 0: Write all automated tests during spec/plan phase
   - Tests for User Stories 1-3 (P1) must pass before implementing P2 features
   - Tests serve as executable specification and acceptance criteria

2. **Autonomous Test Execution**:
   - All tests run without manual user intervention
   - Test suite executable via `pytest tests/057-env-window-matching/` with zero configuration
   - Tests create/cleanup resources automatically (launch apps, create processes, query state)
   - Headless operation compatible with CI/CD environments

3. **State Verification Strategy**:
   - **Sway IPC tree queries**: Validate window creation, workspace assignment, window properties
   - **/proc filesystem access**: Validate environment variable injection and parsing
   - **Application registry parsing**: Validate coverage across all registered applications
   - **Performance benchmarking**: Measure and assert latency targets

4. **Test Iteration Loop**:
   ```
   spec → write tests → implement → run tests → debug/fix → repeat until all tests pass → commit
   ```

5. **Test Organization**:
   ```
   tests/057-env-window-matching/
   ├── unit/
   │   ├── test_window_environment_parsing.py    # WindowEnvironment data model
   │   ├── test_proc_filesystem_reader.py        # /proc read logic
   │   └── test_validation_rules.py              # Environment variable validation
   ├── integration/
   │   ├── test_sway_ipc_integration.py          # Sway IPC + /proc integration
   │   ├── test_app_launch_coverage.py           # Coverage validation per app
   │   └── test_parent_traversal.py              # Parent PID traversal
   ├── performance/
   │   ├── test_env_query_benchmark.py           # /proc read latency
   │   ├── test_batch_query_benchmark.py         # Bulk window query latency
   │   └── test_parent_traversal_benchmark.py    # Parent traversal overhead
   └── scenarios/
       ├── test_window_identification_e2e.py     # Full workflow: launch → identify → verify
       ├── test_coverage_validation_e2e.py       # Full coverage test across registry
       └── test_project_association_e2e.py       # Project switching with env vars
   ```

6. **Test Execution Targets**:
   - **Unit tests**: <1 second total (fast feedback loop)
   - **Integration tests**: <10 seconds total (Sway IPC + /proc operations)
   - **Performance tests**: <30 seconds total (100+ samples for statistical confidence)
   - **End-to-end scenarios**: <60 seconds total (full workflows with cleanup)
   - **Full test suite**: <2 minutes (acceptable for CI/CD)

7. **Continuous Validation**:
   - Run full test suite on every commit before push
   - CI/CD pipeline blocks merge if tests fail
   - Coverage validation runs on system startup (daemon integration)
   - Performance benchmarks logged to system journal for regression tracking

### Test Success Criteria

**All tests must pass before feature is considered complete**:
- ✅ 100% of registered applications pass coverage validation
- ✅ Performance benchmarks meet all latency targets (p95 < 10ms)
- ✅ Parent traversal handles edge cases without errors
- ✅ No regressions in existing window management tests
- ✅ Code removal (legacy matching logic) verified via negative tests

**Test-Driven Benefits**:
- Executable specification ensures implementation matches requirements
- Autonomous tests enable rapid iteration without manual validation
- Performance validation prevents latency regressions
- Coverage validation ensures 100% environment injection reliability
- State verification via Sway IPC provides ground truth for correctness
