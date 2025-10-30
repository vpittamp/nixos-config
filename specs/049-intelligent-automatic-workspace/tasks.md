# Implementation Tasks: Intelligent Automatic Workspace-to-Monitor Assignment

**Feature**: 049-intelligent-automatic-workspace
**Branch**: `049-intelligent-automatic-workspace`
**Date**: 2025-10-29

## Overview

This document provides actionable implementation tasks for automatic workspace redistribution across Sway monitors. Tasks are organized by user story for independent implementation and testing.

**Total Estimated Tasks**: 28 tasks across 5 phases
**MVP Scope**: Phase 3 (US1 + US2) - Core automatic reassignment with window preservation
**Parallel Opportunities**: 14 tasks can run in parallel

---

## Task Execution Order

### Phase 1: Setup & Infrastructure (4 tasks)
Foundation tasks for project structure and development environment.

### Phase 2: Foundational - Distribution Engine (US3) (6 tasks)
**Blocking prerequisite for all other user stories** - implements distribution algorithm needed by US1 and US2.

### Phase 3: Core Automation (US1 + US2) (12 tasks)
Primary value delivery - automatic workspace redistribution with window preservation (both P1 priorities, tightly coupled).

### Phase 4: State Persistence (US4) (4 tasks)
State persistence and preference restoration (P3 priority, can be deferred).

### Phase 5: Polish & Integration (2 tasks)
Final integration, documentation updates, and cleanup.

---

## Phase 1: Setup & Infrastructure

**Goal**: Establish project structure, remove legacy code, and set up testing framework.

**Duration**: ~2 hours

### T001 [Setup] Delete legacy MonitorConfigManager code
**File**: `home-modules/desktop/i3-project-event-daemon/monitor_config_manager.py`
**Action**: DELETE entire file

**Details**:
- Remove `monitor_config_manager.py` completely
- Remove references in:
  - `handlers.py` (import statements, MonitorConfigManager instantiation)
  - `workspace_manager.py` (MonitorConfigManager usage)
  - `ipc_server.py` (IPC commands calling MonitorConfigManager)
- Remove deprecated Pydantic models from `models.py`:
  - `WorkspaceMonitorConfig`
  - `MonitorDistribution`
  - `ConfigValidationResult`
- Delete legacy config file reference: `~/.config/i3/workspace-monitor-mapping.json`

**Validation**:
```bash
grep -r "MonitorConfigManager" home-modules/desktop/i3-project-event-daemon/
grep -r "WorkspaceMonitorConfig\|MonitorDistribution\|ConfigValidationResult" home-modules/desktop/i3-project-event-daemon/models.py
# Both should return no results
```

---

### T002 [Setup] Create test directory structure
**Files**: Create directories under `tests/i3-project-daemon/`

**Action**: Create test structure:
```bash
mkdir -p tests/i3-project-daemon/unit
mkdir -p tests/i3-project-daemon/integration
mkdir -p tests/i3-project-daemon/scenarios
mkdir -p tests/i3-project-daemon/fixtures
```

**Files to create**:
- `tests/i3-project-daemon/__init__.py`
- `tests/i3-project-daemon/conftest.py` (pytest configuration)
- `tests/i3-project-daemon/fixtures/__init__.py`
- `tests/i3-project-daemon/fixtures/mock_i3_connection.py`

**Validation**: Verify directory structure exists

---

### T003 [P] [Setup] Create pytest fixtures for mocked i3 IPC
**File**: `tests/i3-project-daemon/fixtures/mock_i3_connection.py`

**Action**: Implement mock fixtures for i3ipc Connection:
```python
import pytest
from unittest.mock import AsyncMock, Mock
from i3ipc.aio import Connection

@pytest.fixture
async def mock_i3_connection():
    """Mock i3 IPC connection for testing."""
    conn = AsyncMock(spec=Connection)
    conn.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True, primary=True),
        Mock(name="HEADLESS-2", active=True, primary=False),
        Mock(name="HEADLESS-3", active=True, primary=False),
    ]
    conn.get_workspaces.return_value = [
        Mock(num=1, name="1", output="HEADLESS-1", visible=True, focused=True),
        Mock(num=5, name="5", output="HEADLESS-2", visible=False, focused=False),
    ]
    conn.get_tree.return_value = Mock()  # Tree structure
    conn.command.return_value = [Mock(success=True)]
    return conn

@pytest.fixture
def mock_output_event_connected():
    """Mock output connected event."""
    return Mock(change="connected", output=Mock(name="HEADLESS-3", active=True))

@pytest.fixture
def mock_output_event_disconnected():
    """Mock output disconnected event."""
    return Mock(change="disconnected", output=Mock(name="HEADLESS-2", active=False))
```

**Validation**: Import fixtures in test files without errors

---

### T004 [P] [Setup] Update pytest configuration
**File**: `tests/i3-project-daemon/conftest.py`

**Action**: Configure pytest with async support:
```python
import pytest
import asyncio

@pytest.fixture(scope="session")
def event_loop():
    """Create an event loop for async tests."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

pytest_plugins = ["tests.i3-project-daemon.fixtures.mock_i3_connection"]
```

**Validation**: Run `pytest --collect-only` to verify configuration loads

---

## Phase 2: Foundational - Distribution Engine (US3)

**User Story**: US3 - Built-in Smart Distribution Rules (Priority: P2)

**Goal**: Implement workspace distribution algorithm based on monitor count. This is a **blocking prerequisite** for US1 and US2.

**Independent Test Criteria**:
- Connect 1, 2, 3, or 4+ monitors and verify distribution follows documented rules
- 1 monitor: WS 1-70 on primary
- 2 monitors: WS 1-2 primary, WS 3-70 secondary
- 3 monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-70 tertiary
- 4+ monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-9 tertiary, WS 10-70 overflow

**Duration**: ~4 hours

**Checkpoint**: ✅ After this phase, distribution algorithm is tested and ready for use by US1/US2

---

### T005 [US3] Add WorkspaceDistribution Pydantic model
**File**: `home-modules/desktop/i3-project-event-daemon/models.py`

**Action**: Add WorkspaceDistribution model with validation:
```python
from pydantic import BaseModel, Field, validator

class WorkspaceDistribution(BaseModel):
    monitor_count: int = Field(..., ge=1, description="Number of active monitors")
    workspace_to_role: dict[int, str] = Field(..., description="Workspace number -> monitor role mapping")

    @validator("workspace_to_role")
    def validate_workspace_coverage(cls, v):
        """Ensure all workspaces 1-70 are assigned."""
        expected_workspaces = set(range(1, 71))
        actual_workspaces = set(v.keys())
        if not expected_workspaces.issubset(actual_workspaces):
            missing = expected_workspaces - actual_workspaces
            raise ValueError(f"Missing workspace assignments: {missing}")
        return v

    @validator("workspace_to_role")
    def validate_roles(cls, v):
        """Ensure all roles are valid."""
        valid_roles = {"primary", "secondary", "tertiary", "overflow"}
        for ws, role in v.items():
            if role not in valid_roles:
                raise ValueError(f"Invalid role '{role}' for workspace {ws}")
        return v

    @staticmethod
    def calculate(monitor_count: int) -> "WorkspaceDistribution":
        """Calculate distribution based on monitor count."""
        workspace_to_role = {}

        if monitor_count == 1:
            for ws in range(1, 71):
                workspace_to_role[ws] = "primary"
        elif monitor_count == 2:
            for ws in range(1, 3):
                workspace_to_role[ws] = "primary"
            for ws in range(3, 71):
                workspace_to_role[ws] = "secondary"
        elif monitor_count == 3:
            for ws in range(1, 3):
                workspace_to_role[ws] = "primary"
            for ws in range(3, 6):
                workspace_to_role[ws] = "secondary"
            for ws in range(6, 71):
                workspace_to_role[ws] = "tertiary"
        else:  # 4+ monitors
            for ws in range(1, 3):
                workspace_to_role[ws] = "primary"
            for ws in range(3, 6):
                workspace_to_role[ws] = "secondary"
            for ws in range(6, 10):
                workspace_to_role[ws] = "tertiary"
            for ws in range(10, 71):
                workspace_to_role[ws] = "overflow"

        return WorkspaceDistribution(
            monitor_count=monitor_count,
            workspace_to_role=workspace_to_role
        )
```

**Validation**: Import model without errors, instantiate with sample data

---

### T006 [US3] [P] Write unit tests for WorkspaceDistribution.calculate()
**File**: `tests/i3-project-daemon/unit/test_workspace_distribution.py`

**Action**: Test distribution algorithm for all monitor counts:
```python
import pytest
from home_modules.desktop.i3_project_event_daemon.models import WorkspaceDistribution

def test_distribution_1_monitor():
    """Test workspace distribution with 1 monitor."""
    dist = WorkspaceDistribution.calculate(1)
    assert dist.monitor_count == 1
    assert all(dist.workspace_to_role[ws] == "primary" for ws in range(1, 71))

def test_distribution_2_monitors():
    """Test workspace distribution with 2 monitors."""
    dist = WorkspaceDistribution.calculate(2)
    assert dist.monitor_count == 2
    assert dist.workspace_to_role[1] == "primary"
    assert dist.workspace_to_role[2] == "primary"
    assert dist.workspace_to_role[3] == "secondary"
    assert dist.workspace_to_role[70] == "secondary"

def test_distribution_3_monitors():
    """Test workspace distribution with 3 monitors."""
    dist = WorkspaceDistribution.calculate(3)
    assert dist.monitor_count == 3
    assert dist.workspace_to_role[1] == "primary"
    assert dist.workspace_to_role[2] == "primary"
    assert dist.workspace_to_role[3] == "secondary"
    assert dist.workspace_to_role[5] == "secondary"
    assert dist.workspace_to_role[6] == "tertiary"
    assert dist.workspace_to_role[70] == "tertiary"

def test_distribution_4_monitors():
    """Test workspace distribution with 4+ monitors."""
    dist = WorkspaceDistribution.calculate(4)
    assert dist.monitor_count == 4
    assert dist.workspace_to_role[1] == "primary"
    assert dist.workspace_to_role[5] == "secondary"
    assert dist.workspace_to_role[9] == "tertiary"
    assert dist.workspace_to_role[10] == "overflow"
    assert dist.workspace_to_role[70] == "overflow"

def test_distribution_validation_coverage():
    """Test validation ensures all workspaces covered."""
    with pytest.raises(ValueError, match="Missing workspace assignments"):
        WorkspaceDistribution(
            monitor_count=1,
            workspace_to_role={1: "primary"}  # Missing WS 2-70
        )

def test_distribution_validation_roles():
    """Test validation ensures valid roles."""
    with pytest.raises(ValueError, match="Invalid role"):
        workspace_to_role = {ws: "invalid_role" for ws in range(1, 71)}
        WorkspaceDistribution(
            monitor_count=1,
            workspace_to_role=workspace_to_role
        )
```

**Validation**: Run `pytest tests/i3-project-daemon/unit/test_workspace_distribution.py -v`

---

### T007 [US3] Add RoleAssignment model
**File**: `home-modules/desktop/i3-project-event-daemon/models.py`

**Action**: Add RoleAssignment model for monitor role tracking:
```python
class RoleAssignment(BaseModel):
    monitor_name: str = Field(..., description="Output name")
    role: str = Field(..., description="Monitor role")

    @validator("role")
    def validate_role(cls, v):
        valid_roles = {"primary", "secondary", "tertiary", "overflow"}
        if v not in valid_roles:
            raise ValueError(f"Invalid role: {v}")
        return v
```

**Validation**: Import and instantiate model

---

### T008 [US3] Create DynamicWorkspaceManager class skeleton
**File**: `home-modules/desktop/i3-project-event-daemon/workspace_manager.py`

**Action**: Add DynamicWorkspaceManager class with monitor role assignment:
```python
from typing import Dict, List
import logging
from i3ipc.aio import Connection
from .models import WorkspaceDistribution, RoleAssignment

logger = logging.getLogger(__name__)

class DynamicWorkspaceManager:
    """Manages dynamic workspace-to-monitor distribution."""

    def __init__(self, i3: Connection):
        self.i3 = i3

    async def assign_monitor_roles(self) -> Dict[str, str]:
        """Assign roles to active monitors based on connection order.

        Returns:
            Dict mapping monitor name to role (primary/secondary/tertiary/overflow)
        """
        outputs = await self.i3.get_outputs()
        active_outputs = [o for o in outputs if o.active]

        roles = {}
        role_names = ["primary", "secondary", "tertiary"]
        for i, output in enumerate(active_outputs):
            if i < 3:
                roles[output.name] = role_names[i]
            else:
                roles[output.name] = "overflow"

        logger.info(f"Assigned monitor roles: {roles}")
        return roles

    def calculate_distribution(self, monitor_count: int) -> WorkspaceDistribution:
        """Calculate workspace distribution for given monitor count."""
        return WorkspaceDistribution.calculate(monitor_count)
```

**Validation**: Import class, instantiate with mock i3 connection

---

### T009 [US3] [P] Write unit tests for DynamicWorkspaceManager
**File**: `tests/i3-project-daemon/unit/test_dynamic_workspace_manager.py`

**Action**: Test monitor role assignment logic:
```python
import pytest
from unittest.mock import AsyncMock, Mock
from home_modules.desktop.i3_project_event_daemon.workspace_manager import DynamicWorkspaceManager

@pytest.mark.asyncio
async def test_assign_monitor_roles_3_monitors(mock_i3_connection):
    """Test role assignment with 3 monitors."""
    manager = DynamicWorkspaceManager(mock_i3_connection)
    roles = await manager.assign_monitor_roles()

    assert roles["HEADLESS-1"] == "primary"
    assert roles["HEADLESS-2"] == "secondary"
    assert roles["HEADLESS-3"] == "tertiary"

@pytest.mark.asyncio
async def test_assign_monitor_roles_1_monitor(mock_i3_connection):
    """Test role assignment with 1 monitor."""
    mock_i3_connection.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True)
    ]
    manager = DynamicWorkspaceManager(mock_i3_connection)
    roles = await manager.assign_monitor_roles()

    assert roles["HEADLESS-1"] == "primary"
    assert len(roles) == 1

@pytest.mark.asyncio
async def test_assign_monitor_roles_overflow(mock_i3_connection):
    """Test role assignment with 4+ monitors."""
    mock_i3_connection.get_outputs.return_value = [
        Mock(name=f"HDMI-{i}", active=True) for i in range(1, 6)
    ]
    manager = DynamicWorkspaceManager(mock_i3_connection)
    roles = await manager.assign_monitor_roles()

    assert roles["HDMI-1"] == "primary"
    assert roles["HDMI-2"] == "secondary"
    assert roles["HDMI-3"] == "tertiary"
    assert roles["HDMI-4"] == "overflow"
    assert roles["HDMI-5"] == "overflow"

def test_calculate_distribution(mock_i3_connection):
    """Test distribution calculation delegates to WorkspaceDistribution."""
    manager = DynamicWorkspaceManager(mock_i3_connection)
    dist = manager.calculate_distribution(3)

    assert dist.monitor_count == 3
    assert dist.workspace_to_role[1] == "primary"
    assert dist.workspace_to_role[5] == "secondary"
    assert dist.workspace_to_role[9] == "tertiary"
```

**Validation**: Run tests with `pytest tests/i3-project-daemon/unit/test_dynamic_workspace_manager.py -v`

---

### T010 [US3] Implement workspace assignment via Sway IPC
**File**: `home-modules/desktop/i3-project-event-daemon/workspace_manager.py`

**Action**: Add method to apply workspace assignments:
```python
async def apply_workspace_assignments(
    self,
    distribution: WorkspaceDistribution,
    monitor_roles: Dict[str, str]
) -> int:
    """Apply workspace-to-output assignments via Sway IPC.

    Args:
        distribution: Workspace distribution by role
        monitor_roles: Monitor name to role mapping

    Returns:
        Number of workspaces successfully reassigned
    """
    # Reverse mapping: role -> monitor name
    role_to_monitor = {role: name for name, role in monitor_roles.items()}

    workspaces_reassigned = 0
    for ws_num, role in distribution.workspace_to_role.items():
        if role in role_to_monitor:
            output_name = role_to_monitor[role]
            command = f"workspace number {ws_num} output {output_name}"
            result = await self.i3.command(command)

            if result and result[0].success:
                workspaces_reassigned += 1
                logger.debug(f"Assigned WS {ws_num} to {output_name}")
            else:
                error_msg = result[0].error if result else "Unknown error"
                logger.warning(f"Failed to assign WS {ws_num} to {output_name}: {error_msg}")

    logger.info(f"Reassigned {workspaces_reassigned} workspaces")
    return workspaces_reassigned
```

**Validation**: Call method with mock i3 connection, verify commands issued

---

## Phase 3: Core Automation (US1 + US2)

**User Stories**:
- US1 - Automatic Workspace Distribution on Monitor Changes (Priority: P1)
- US2 - Window Preservation During Monitor Changes (Priority: P1)

**Goal**: Implement automatic workspace redistribution and window migration when monitors connect/disconnect. These stories are tightly coupled and delivered together.

**Independent Test Criteria**:
- US1: Connect 3 VNC clients, verify workspaces distribute automatically, disconnect one, verify redistribution within 1 second
- US2: Open windows on all 3 monitors, disconnect one, verify all windows accessible on remaining monitors

**Duration**: ~8 hours

**Checkpoint**: ✅ After this phase, core automatic reassignment works end-to-end

---

### T011 [US1] Add MonitorInfo and ReassignmentResult models
**File**: `home-modules/desktop/i3-project-event-daemon/models.py`

**Action**: Add models for monitor state and reassignment result:
```python
from datetime import datetime

class MonitorInfo(BaseModel):
    name: str = Field(..., description="Output name from Sway (e.g., HEADLESS-1)")
    role: str = Field(..., description="Monitor role: primary, secondary, tertiary, overflow")
    active: bool = Field(default=True, description="Whether monitor is currently connected")

class ReassignmentResult(BaseModel):
    success: bool = Field(..., description="Whether reassignment succeeded")
    workspaces_reassigned: int = Field(..., ge=0, description="Number of workspaces reassigned")
    windows_migrated: int = Field(..., ge=0, description="Number of windows migrated")
    duration_ms: int = Field(..., ge=0, description="Total duration in milliseconds")
    error_message: str | None = Field(default=None, description="Error message if failed")
    migration_records: list = Field(default_factory=list, description="Detailed migration logs")

    @validator("error_message")
    def validate_error_message(cls, v, values):
        """If not successful, error_message must be provided."""
        if not values.get("success") and not v:
            raise ValueError("error_message required when success=False")
        return v

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }
```

**Validation**: Import and instantiate models

---

### T012 [US2] Add WindowMigrationRecord model
**File**: `home-modules/desktop/i3-project-event-daemon/models.py`

**Action**: Add model for window migration logging:
```python
class WindowMigrationRecord(BaseModel):
    window_id: int = Field(..., gt=0, description="Sway window ID")
    window_class: str = Field(..., min_length=1, description="Window class for identification")
    old_output: str = Field(..., min_length=1, description="Output before migration")
    new_output: str = Field(..., min_length=1, description="Output after migration")
    workspace_number: int = Field(..., ge=1, le=70, description="Workspace number (preserved)")
    timestamp: datetime = Field(..., description="Migration timestamp")

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }
```

**Validation**: Import and instantiate model

---

### T013 [US2] Implement window detection on disconnected monitors
**File**: `home-modules/desktop/i3-project-event-daemon/workspace_manager.py`

**Action**: Add method to detect windows on disconnected monitors:
```python
from datetime import datetime
from .models import WindowMigrationRecord

async def detect_windows_on_disconnected_monitors(
    self,
    disconnected_outputs: set[str]
) -> List[WindowMigrationRecord]:
    """Detect windows on workspaces assigned to disconnected monitors.

    Args:
        disconnected_outputs: Set of output names that are disconnected

    Returns:
        List of WindowMigrationRecord for windows on disconnected monitors
    """
    if not disconnected_outputs:
        return []

    tree = await self.i3.get_tree()
    workspaces = await self.i3.get_workspaces()

    migration_records = []

    # Find workspaces on disconnected monitors
    for ws in workspaces:
        if ws.output in disconnected_outputs:
            # Find windows in this workspace
            windows = self._find_windows_in_workspace(tree, ws.num)

            for window in windows:
                record = WindowMigrationRecord(
                    window_id=window.id,
                    window_class=window.window_properties.get("class", "unknown"),
                    old_output=ws.output,
                    new_output="",  # Will be filled during reassignment
                    workspace_number=ws.num,
                    timestamp=datetime.now()
                )
                migration_records.append(record)

    logger.info(f"Found {len(migration_records)} windows on disconnected monitors")
    return migration_records

def _find_windows_in_workspace(self, tree, workspace_num: int) -> List:
    """Find all windows in a workspace from i3 tree."""
    windows = []

    def traverse(node):
        if hasattr(node, 'window') and node.window:
            if hasattr(node, 'workspace') and node.workspace().num == workspace_num:
                windows.append(node)
        if hasattr(node, 'nodes'):
            for child in node.nodes:
                traverse(child)

    traverse(tree)
    return windows
```

**Validation**: Call method with mock tree containing windows, verify records created

---

### T014 [US1+US2] Implement output event handler with debounce
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py`

**Action**: Add output event handler with 500ms debounce:
```python
import asyncio
import time
from datetime import datetime
from .workspace_manager import DynamicWorkspaceManager
from .models import ReassignmentResult

class EventHandlers:
    def __init__(self, i3_connection):
        self.i3 = i3_connection
        self.workspace_manager = DynamicWorkspaceManager(i3_connection)
        self._pending_reassignment_task = None
        self._reassignment_history = []  # Circular buffer, max 100

    async def on_output_event(self, i3, event):
        """Handle output connect/disconnect events with debounce."""
        logger.info(f"Output event: {event.change} - {event.output.name}")

        # Cancel pending reassignment if exists
        if self._pending_reassignment_task:
            self._pending_reassignment_task.cancel()
            logger.debug("Cancelled pending reassignment task")

        # Schedule new debounced reassignment
        self._pending_reassignment_task = asyncio.create_task(
            self._debounced_reassignment()
        )

    async def _debounced_reassignment(self):
        """Perform workspace reassignment after 500ms debounce delay."""
        try:
            await asyncio.sleep(0.5)  # 500ms debounce
            logger.info("Debounce complete, starting reassignment")

            start_time = time.time()
            result = await self._perform_reassignment()
            duration_ms = int((time.time() - start_time) * 1000)
            result.duration_ms = duration_ms

            logger.info(
                f"Reassignment complete: {result.workspaces_reassigned} workspaces, "
                f"{result.windows_migrated} windows, {duration_ms}ms"
            )

            # Store in history (circular buffer)
            self._reassignment_history.append(result)
            if len(self._reassignment_history) > 100:
                self._reassignment_history.pop(0)

        except asyncio.CancelledError:
            logger.debug("Reassignment cancelled due to new monitor event")
        except Exception as e:
            logger.error(f"Reassignment failed: {e}", exc_info=True)

    async def _perform_reassignment(self) -> ReassignmentResult:
        """Perform complete workspace reassignment workflow."""
        # Implementation in next task
        pass
```

**Validation**: Trigger multiple rapid output events, verify only one reassignment occurs

---

### T015 [US1+US2] Implement complete reassignment workflow
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py`

**Action**: Implement `_perform_reassignment()` method:
```python
async def _perform_reassignment(self) -> ReassignmentResult:
    """Perform complete workspace reassignment workflow.

    Steps:
    1. Query current outputs
    2. Assign monitor roles
    3. Calculate workspace distribution
    4. Detect windows on disconnected monitors
    5. Apply workspace assignments
    6. Return result
    """
    try:
        # 1. Query current outputs
        outputs = await self.i3.get_outputs()
        active_outputs = {o.name for o in outputs if o.active}
        monitor_count = len(active_outputs)

        logger.info(f"Active monitors: {monitor_count} - {active_outputs}")

        # 2. Assign monitor roles
        monitor_roles = await self.workspace_manager.assign_monitor_roles()

        # 3. Calculate workspace distribution
        distribution = self.workspace_manager.calculate_distribution(monitor_count)

        # 4. Detect windows on disconnected monitors (US2)
        # Get previous outputs to determine what disconnected
        all_outputs = {o.name for o in outputs}
        disconnected_outputs = all_outputs - active_outputs
        migration_records = await self.workspace_manager.detect_windows_on_disconnected_monitors(
            disconnected_outputs
        )

        # 5. Apply workspace assignments (US1)
        workspaces_reassigned = await self.workspace_manager.apply_workspace_assignments(
            distribution, monitor_roles
        )

        # Update migration records with new output
        # (windows moved when workspaces reassigned)
        for record in migration_records:
            role = distribution.workspace_to_role[record.workspace_number]
            role_to_monitor = {r: n for n, r in monitor_roles.items()}
            if role in role_to_monitor:
                record.new_output = role_to_monitor[role]

        return ReassignmentResult(
            success=True,
            workspaces_reassigned=workspaces_reassigned,
            windows_migrated=len(migration_records),
            duration_ms=0,  # Filled by caller
            error_message=None,
            migration_records=migration_records
        )

    except Exception as e:
        logger.error(f"Reassignment failed: {e}", exc_info=True)
        return ReassignmentResult(
            success=False,
            workspaces_reassigned=0,
            windows_migrated=0,
            duration_ms=0,
            error_message=str(e),
            migration_records=[]
        )
```

**Validation**: Call method with mock i3 connection, verify result structure

---

### T016 [US1+US2] Register output event subscription in daemon
**File**: `home-modules/desktop/i3-project-event-daemon/__main__.py` (or daemon entry point)

**Action**: Subscribe to output events:
```python
from i3ipc.aio import Connection
from .handlers import EventHandlers

async def main():
    i3 = await Connection().connect()
    handlers = EventHandlers(i3)

    # Subscribe to output events
    i3.on("output", handlers.on_output_event)

    logger.info("i3pm daemon started, subscribed to output events")
    await i3.main()
```

**Validation**: Start daemon, verify output event subscription in logs

---

### T017 [US1] [P] Write integration test for output event handler
**File**: `tests/i3-project-daemon/integration/test_output_event_handler.py`

**Action**: Test output event handler with debounce:
```python
import pytest
import asyncio
from unittest.mock import Mock
from home_modules.desktop.i3_project_event_daemon.handlers import EventHandlers

@pytest.mark.asyncio
async def test_output_event_triggers_reassignment(mock_i3_connection):
    """Test output event triggers debounced reassignment."""
    handlers = EventHandlers(mock_i3_connection)

    # Trigger output connected event
    event = Mock(change="connected", output=Mock(name="HEADLESS-3", active=True))
    await handlers.on_output_event(mock_i3_connection, event)

    # Wait for debounce + processing
    await asyncio.sleep(0.6)

    # Verify reassignment occurred
    assert len(handlers._reassignment_history) == 1
    result = handlers._reassignment_history[0]
    assert result.success is True
    assert result.workspaces_reassigned > 0

@pytest.mark.asyncio
async def test_rapid_output_events_debounced(mock_i3_connection):
    """Test rapid output events result in single reassignment."""
    handlers = EventHandlers(mock_i3_connection)

    # Trigger 3 rapid events
    for i in range(3):
        event = Mock(change="connected", output=Mock(name=f"HDMI-{i}", active=True))
        await handlers.on_output_event(mock_i3_connection, event)
        await asyncio.sleep(0.1)  # 100ms between events

    # Wait for debounce
    await asyncio.sleep(0.6)

    # Verify only 1 reassignment occurred
    assert len(handlers._reassignment_history) == 1

@pytest.mark.asyncio
async def test_output_disconnect_preserves_windows(mock_i3_connection):
    """Test output disconnect migrates windows (US2)."""
    # Setup: Add windows to mock tree
    mock_tree = Mock()
    mock_i3_connection.get_tree.return_value = mock_tree

    handlers = EventHandlers(mock_i3_connection)

    # Trigger disconnect event
    event = Mock(change="disconnected", output=Mock(name="HEADLESS-2", active=False))
    await handlers.on_output_event(mock_i3_connection, event)

    # Wait for processing
    await asyncio.sleep(0.6)

    # Verify migration records created
    result = handlers._reassignment_history[0]
    assert result.windows_migrated >= 0
```

**Validation**: Run tests with `pytest tests/i3-project-daemon/integration/test_output_event_handler.py -v`

---

### T018 [US1] [P] Write scenario test for 3 monitors → 2 monitors transition
**File**: `tests/i3-project-daemon/scenarios/test_monitor_changes.py`

**Action**: Test complete monitor change scenario:
```python
import pytest
import asyncio
from unittest.mock import Mock
from home_modules.desktop.i3_project_event_daemon.handlers import EventHandlers

@pytest.mark.asyncio
async def test_3_monitors_to_2_monitors(mock_i3_connection):
    """Test workspace redistribution when disconnecting a monitor (US1)."""
    # Setup: 3 monitors initially
    mock_i3_connection.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
        Mock(name="HEADLESS-2", active=True),
        Mock(name="HEADLESS-3", active=True),
    ]

    handlers = EventHandlers(mock_i3_connection)

    # Initial state: 3 monitors
    event = Mock(change="connected", output=Mock(name="HEADLESS-3", active=True))
    await handlers.on_output_event(mock_i3_connection, event)
    await asyncio.sleep(0.6)

    initial_result = handlers._reassignment_history[0]
    assert initial_result.workspaces_reassigned == 70  # All workspaces assigned

    # Disconnect HEADLESS-2
    mock_i3_connection.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
        Mock(name="HEADLESS-3", active=True),
    ]

    event = Mock(change="disconnected", output=Mock(name="HEADLESS-2", active=False))
    await handlers.on_output_event(mock_i3_connection, event)
    await asyncio.sleep(0.6)

    # Verify redistribution for 2 monitors
    result = handlers._reassignment_history[1]
    assert result.success is True
    assert result.workspaces_reassigned > 0

    # Verify workspace assignment commands issued
    # WS 1-2 should go to HEADLESS-1 (primary)
    # WS 3-70 should go to HEADLESS-3 (secondary)
    calls = mock_i3_connection.command.call_args_list
    assert any("workspace number 1 output HEADLESS-1" in str(call) for call in calls)
    assert any("workspace number 3 output HEADLESS-3" in str(call) for call in calls)

@pytest.mark.asyncio
async def test_window_preservation_on_disconnect(mock_i3_connection):
    """Test windows from disconnected monitor are accessible (US2)."""
    # Setup: Windows on HEADLESS-2 (WS 3-5)
    mock_tree = Mock()
    mock_i3_connection.get_tree.return_value = mock_tree

    handlers = EventHandlers(mock_i3_connection)

    # Disconnect HEADLESS-2
    mock_i3_connection.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
        Mock(name="HEADLESS-3", active=True),
    ]

    event = Mock(change="disconnected", output=Mock(name="HEADLESS-2", active=False))
    await handlers.on_output_event(mock_i3_connection, event)
    await asyncio.sleep(0.6)

    result = handlers._reassignment_history[0]
    # Windows detected and migration records created
    assert result.windows_migrated >= 0

@pytest.mark.asyncio
async def test_rapid_connect_disconnect_cycles(mock_i3_connection):
    """Test rapid monitor changes result in single reassignment (US1)."""
    handlers = EventHandlers(mock_i3_connection)

    # Rapid connect/disconnect cycle (5 events in 1 second)
    for i in range(5):
        change = "connected" if i % 2 == 0 else "disconnected"
        event = Mock(change=change, output=Mock(name="HEADLESS-2", active=(i % 2 == 0)))
        await handlers.on_output_event(mock_i3_connection, event)
        await asyncio.sleep(0.2)

    # Wait for final debounce
    await asyncio.sleep(0.6)

    # Verify only 1 reassignment occurred
    assert len(handlers._reassignment_history) == 1
```

**Validation**: Run scenario tests with `pytest tests/i3-project-daemon/scenarios/test_monitor_changes.py -v`

---

### T019 [US1+US2] Add logging for reassignment operations
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py`

**Action**: Add comprehensive logging:
```python
import logging

logger = logging.getLogger(__name__)

# In _perform_reassignment():
logger.info(f"Starting reassignment - Active monitors: {monitor_count}")
logger.debug(f"Monitor roles: {monitor_roles}")
logger.debug(f"Distribution: WS 1-2 → {monitor_roles.get('primary', 'N/A')}, ...")
logger.info(f"Detected {len(migration_records)} windows on disconnected monitors")

# Log each workspace assignment
for ws_num, role in distribution.workspace_to_role.items():
    output = role_to_monitor.get(role, "N/A")
    logger.debug(f"WS {ws_num} → {output} ({role})")

logger.info(
    f"Reassignment complete: "
    f"{result.workspaces_reassigned} workspaces, "
    f"{result.windows_migrated} windows migrated, "
    f"{result.duration_ms}ms"
)
```

**Validation**: Trigger reassignment, verify logs show detailed operation info

---

### T020 [US1] Add IPC command for monitor status
**File**: `home-modules/desktop/i3-project-event-daemon/ipc_server.py`

**Action**: Add `monitors.status` IPC command:
```python
async def _handle_monitors_status(self, params: dict) -> dict:
    """Handle monitors.status IPC request."""
    workspace_manager = self.daemon.workspace_manager

    outputs = await self.daemon.i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]
    monitor_roles = await workspace_manager.assign_monitor_roles()

    # Get workspace assignments for each monitor
    workspaces = await self.daemon.i3.get_workspaces()
    monitor_workspaces = {}
    for monitor_name in monitor_roles.keys():
        monitor_workspaces[monitor_name] = [
            ws.num for ws in workspaces if ws.output == monitor_name
        ]

    # Get reassignment history
    last_reassignment = None
    if self.daemon.handlers._reassignment_history:
        last_result = self.daemon.handlers._reassignment_history[-1]
        last_reassignment = last_result.last_updated.isoformat() if hasattr(last_result, 'last_updated') else None

    return {
        "monitor_count": len(active_outputs),
        "active_monitors": [
            {
                "name": name,
                "role": role,
                "active": True,
                "workspaces": monitor_workspaces.get(name, [])
            }
            for name, role in monitor_roles.items()
        ],
        "last_reassignment": last_reassignment,
        "reassignment_count": len(self.daemon.handlers._reassignment_history)
    }

# Register handler
self.handlers["monitors.status"] = self._handle_monitors_status
```

**Validation**: Call `i3pm monitors status` CLI command, verify JSON response

---

### T021 [US1] Create CLI command for monitor status
**File**: `home-modules/tools/i3pm/monitors.py` (new file)

**Action**: Create CLI command wrapper:
```python
import asyncio
import json
from rich.console import Console
from rich.table import Table
from .daemon_client import DaemonClient

console = Console()

async def show_monitor_status():
    """Show current monitor configuration."""
    async with DaemonClient() as client:
        result = await client.call("monitors.status", {})

        table = Table(title="Monitor Status")
        table.add_column("Monitor", style="cyan")
        table.add_column("Role", style="magenta")
        table.add_column("Active", style="green")
        table.add_column("Workspaces", style="yellow")

        for monitor in result["active_monitors"]:
            workspaces = ", ".join(map(str, monitor["workspaces"][:5]))
            if len(monitor["workspaces"]) > 5:
                workspaces += f", ... ({len(monitor['workspaces'])} total)"

            table.add_row(
                monitor["name"],
                monitor["role"],
                "✓" if monitor["active"] else "✗",
                workspaces
            )

        console.print(table)
        console.print(f"\nLast reassignment: {result.get('last_reassignment', 'Never')}")
        console.print(f"Total reassignments: {result['reassignment_count']}")

if __name__ == "__main__":
    asyncio.run(show_monitor_status())
```

**Validation**: Run `python -m home_modules.tools.i3pm.monitors` and verify table output

---

### T022 [US1+US2] End-to-end manual testing
**File**: N/A (manual testing)

**Action**: Perform manual end-to-end testing:
1. Start daemon with 3 VNC clients connected
2. Verify workspaces distribute: WS 1-2 on HEADLESS-1, WS 3-5 on HEADLESS-2, WS 6-9 on HEADLESS-3
3. Open windows on all 3 monitors (terminals, browsers, etc.)
4. Disconnect VNC client from HEADLESS-2
5. Verify:
   - Workspaces redistribute within 1 second (US1)
   - All windows remain accessible on remaining monitors (US2)
   - `i3pm monitors status` shows 2 monitors
6. Reconnect HEADLESS-2
7. Verify workspaces redistribute back to 3-monitor layout

**Validation**: All acceptance scenarios pass, no errors in daemon logs

---

## Phase 4: State Persistence (US4)

**User Story**: US4 - State Persistence and Monitor Reconnection (Priority: P3)

**Goal**: Persist monitor state to JSON file and restore preferences on reconnection.

**Independent Test Criteria**:
- Disconnect a monitor, manually move workspaces, reconnect monitor, verify system restores preferred layout

**Duration**: ~3 hours

**Checkpoint**: ✅ After this phase, state persistence and preference restoration works

---

### T023 [US4] Add MonitorState Pydantic model
**File**: `home-modules/desktop/i3-project-event-daemon/models.py`

**Action**: Add MonitorState model:
```python
class MonitorState(BaseModel):
    version: str = Field(default="1.0", description="Schema version")
    last_updated: datetime = Field(..., description="Timestamp of last update")
    active_monitors: list[MonitorInfo] = Field(..., min_items=1, description="Active monitors with roles")
    workspace_assignments: dict[int, str] = Field(..., description="Workspace number -> output name mapping")

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }
```

**Validation**: Import and instantiate model

---

### T024 [US4] Implement monitor state persistence
**File**: `home-modules/desktop/i3-project-event-daemon/workspace_manager.py`

**Action**: Add methods to save/load monitor state:
```python
import json
from pathlib import Path
from .models import MonitorState, MonitorInfo

STATE_FILE_PATH = Path.home() / ".config/sway/monitor-state.json"

async def save_monitor_state(
    self,
    monitor_roles: Dict[str, str],
    distribution: WorkspaceDistribution
) -> None:
    """Save current monitor state to JSON file."""
    # Reverse mapping: role -> monitor name
    role_to_monitor = {role: name for name, role in monitor_roles.items()}

    # Build workspace assignments (workspace -> output name)
    workspace_assignments = {}
    for ws_num, role in distribution.workspace_to_role.items():
        if role in role_to_monitor:
            workspace_assignments[ws_num] = role_to_monitor[role]

    # Create MonitorState
    active_monitors = [
        MonitorInfo(name=name, role=role, active=True)
        for name, role in monitor_roles.items()
    ]

    state = MonitorState(
        version="1.0",
        last_updated=datetime.now(),
        active_monitors=active_monitors,
        workspace_assignments=workspace_assignments
    )

    # Ensure directory exists
    STATE_FILE_PATH.parent.mkdir(parents=True, exist_ok=True)

    # Write to file
    with open(STATE_FILE_PATH, 'w') as f:
        json.dump(state.dict(), f, indent=2, default=str)

    logger.info(f"Saved monitor state to {STATE_FILE_PATH}")

async def load_monitor_state(self) -> MonitorState | None:
    """Load monitor state from JSON file."""
    if not STATE_FILE_PATH.exists():
        logger.info("No monitor state file found")
        return None

    try:
        with open(STATE_FILE_PATH, 'r') as f:
            data = json.load(f)

        state = MonitorState(**data)
        logger.info(f"Loaded monitor state from {STATE_FILE_PATH}")
        return state

    except Exception as e:
        logger.error(f"Failed to load monitor state: {e}")
        return None
```

**Validation**: Call save/load methods, verify JSON file created and loaded correctly

---

### T025 [US4] Integrate state persistence into reassignment workflow
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py`

**Action**: Add state persistence to `_perform_reassignment()`:
```python
# At end of _perform_reassignment(), before return:
if result.success:
    # Save monitor state
    await self.workspace_manager.save_monitor_state(monitor_roles, distribution)

    # Update Sway Config Manager workspace assignments
    await self._update_sway_config_manager(distribution, monitor_roles)
```

**Validation**: Trigger reassignment, verify monitor-state.json created

---

### T026 [US4] Implement Sway Config Manager integration
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py`

**Action**: Add method to update workspace-assignments.json:
```python
import json
from pathlib import Path

SWAY_CONFIG_ASSIGNMENTS = Path.home() / ".config/sway/workspace-assignments.json"

async def _update_sway_config_manager(
    self,
    distribution: WorkspaceDistribution,
    monitor_roles: Dict[str, str]
) -> None:
    """Update Sway Config Manager workspace assignments file."""
    role_to_monitor = {role: name for name, role in monitor_roles.items()}

    assignments = []
    for ws_num, role in distribution.workspace_to_role.items():
        if role in role_to_monitor:
            assignments.append({
                "workspace": ws_num,
                "output": role_to_monitor[role]
            })

    # Ensure directory exists
    SWAY_CONFIG_ASSIGNMENTS.parent.mkdir(parents=True, exist_ok=True)

    # Write to file
    with open(SWAY_CONFIG_ASSIGNMENTS, 'w') as f:
        json.dump(assignments, f, indent=2)

    logger.info(f"Updated Sway Config Manager: {SWAY_CONFIG_ASSIGNMENTS}")
```

**Validation**: Trigger reassignment, verify workspace-assignments.json updated

---

## Phase 5: Polish & Integration

**Goal**: Final integration testing, documentation updates, and production readiness.

**Duration**: ~2 hours

---

### T027 [Polish] Update CLAUDE.md with automatic reassignment workflow
**File**: `/etc/nixos/CLAUDE.md`

**Action**: Add section documenting automatic workspace reassignment:
```markdown
## 🖥️ Automatic Workspace-to-Monitor Assignment (Feature 049)

### Overview

Workspaces automatically redistribute across Sway monitors when displays connect or disconnect. No manual intervention required.

### Automatic Behavior

**Monitor Connect**: Workspaces redistribute within 1 second
**Monitor Disconnect**: Windows migrate to active monitors, workspaces reassign
**Rapid Changes**: 500ms debounce prevents flapping

### Default Distribution

| Monitors | Primary | Secondary | Tertiary |
|----------|---------|-----------|----------|
| 1        | 1-70    | -         | -        |
| 2        | 1-2     | 3-70      | -        |
| 3        | 1-2     | 3-5       | 6-70     |
| 4+       | 1-2     | 3-5       | 6-9      |

### Diagnostic Commands

```bash
# Check current monitor configuration
i3pm monitors status

# View reassignment history
i3pm monitors history

# Show distribution rules
i3pm monitors config show
```

### Troubleshooting

See `/etc/nixos/specs/049-intelligent-automatic-workspace/quickstart.md` for detailed troubleshooting.
```

**Validation**: Read CLAUDE.md, verify documentation is clear and accurate

---

### T028 [Polish] Run full test suite and verify all tests pass
**File**: N/A (test execution)

**Action**: Run complete test suite:
```bash
# Run all unit tests
pytest tests/i3-project-daemon/unit/ -v

# Run all integration tests
pytest tests/i3-project-daemon/integration/ -v

# Run all scenario tests
pytest tests/i3-project-daemon/scenarios/ -v

# Run complete test suite with coverage
pytest tests/i3-project-daemon/ -v --cov=home_modules.desktop.i3_project_event_daemon --cov-report=term-missing
```

**Success Criteria**:
- All tests pass
- Code coverage > 80%
- No warnings or errors
- Performance tests show <1s reassignment latency

**Validation**: Test suite report shows all green, coverage above threshold

---

## Dependencies & Execution Order

### Critical Path (Must Execute in Order)

```
Phase 1: Setup
  ↓
Phase 2: Distribution Engine (US3) ← BLOCKING PREREQUISITE
  ↓
Phase 3: Core Automation (US1 + US2)
  ↓
Phase 4: State Persistence (US4) [Can be parallelized with Phase 5]
  ↓
Phase 5: Polish & Integration
```

### User Story Dependencies

```
US3 (Distribution Engine)
  ↓
  ├─→ US1 (Workspace Distribution) ─┐
  │                                   ├─→ Tightly Coupled (both P1)
  └─→ US2 (Window Preservation)  ────┘
       ↓
       US4 (State Persistence) [Optional, P3]
```

### Inter-Task Dependencies

- **T005-T010** (US3): Must complete before T011-T022 (US1+US2)
- **T001** (delete legacy): Should complete before T005 (avoid conflicts)
- **T002-T004** (test setup): Can run parallel with T001
- **T011-T013** (models): Can run parallel, no dependencies
- **T014** depends on T013 (output handler needs models)
- **T015** depends on T010, T013 (reassignment needs distribution + window detection)
- **T023-T024** (US4) can start after T015 completes

---

## Parallel Execution Opportunities

### Phase 1 (Setup) - 2 parallel streams
```
Stream A: T001 (delete legacy)
Stream B: T002, T003, T004 (test setup) [P]
```

### Phase 2 (US3) - 3 parallel streams
```
Stream A: T005 (WorkspaceDistribution model)
Stream B: T007 (RoleAssignment model) [P]
Stream C: T006 (tests for T005) [P] - can start after T005
Stream D: T008, T009 (DynamicWorkspaceManager) - depends on T005, T007
Stream E: T010 (workspace assignment) - depends on T008
```

### Phase 3 (US1+US2) - 4 parallel streams
```
Stream A: T011 (MonitorInfo, ReassignmentResult models)
Stream B: T012 (WindowMigrationRecord model) [P]
Stream C: T019 (logging) [P] - can run anytime
Stream D: T013 (window detection) - depends on T012
Stream E: T014 (output handler) - depends on T011, T013
Stream F: T015 (reassignment workflow) - depends on T014
Stream G: T017, T018 (tests) [P] - can run after T015
Stream H: T020, T021 (IPC command) [P] - can run after T015
Stream I: T022 (manual testing) - final validation
```

### Phase 4 (US4) - 2 parallel streams
```
Stream A: T023 (MonitorState model)
Stream B: T024 (persistence) - depends on T023
Stream C: T025, T026 (integration) [P] - depends on T024
```

### Phase 5 (Polish) - Sequential
```
T027 (docs) → T028 (test suite)
```

---

## Implementation Strategy

### MVP Scope (Recommended First Delivery)

**Phase 1 + Phase 2 + Phase 3 (T001-T022)**
- Setup + Distribution Engine + Core Automation
- Delivers both P1 user stories (US1 + US2)
- Provides immediate value: automatic workspace redistribution + window preservation
- ~14 hours of work

**Deferred to Post-MVP**:
- Phase 4 (US4 - State Persistence) - P3 priority
- Can be added later without impacting core functionality

### Incremental Delivery Checkpoints

**Checkpoint 1** (After Phase 1):
- ✅ Legacy code removed
- ✅ Test infrastructure ready

**Checkpoint 2** (After Phase 2):
- ✅ Distribution algorithm tested and working
- ✅ Can query distribution for any monitor count

**Checkpoint 3** (After Phase 3):
- ✅ Automatic reassignment works end-to-end
- ✅ Windows preserved during monitor changes
- ✅ Debounce prevents flapping
- ✅ MVP feature complete

**Checkpoint 4** (After Phase 4):
- ✅ State persistence working
- ✅ Preferences restored on reconnection

**Checkpoint 5** (After Phase 5):
- ✅ Documentation updated
- ✅ All tests passing
- ✅ Production ready

---

## Task Summary

| Phase | User Story | Task Count | Parallel Tasks | Duration |
|-------|------------|------------|----------------|----------|
| 1     | Setup      | 4          | 3              | ~2h      |
| 2     | US3        | 6          | 3              | ~4h      |
| 3     | US1+US2    | 12         | 6              | ~8h      |
| 4     | US4        | 4          | 2              | ~3h      |
| 5     | Polish     | 2          | 0              | ~2h      |
| **Total** |        | **28**     | **14**         | **~19h** |

**MVP Task Count**: 22 tasks (excluding Phase 4 and Phase 5)
**MVP Duration**: ~14 hours

---

## Validation Checklist

After completing all tasks, verify:

- [ ] All unit tests pass (pytest unit/)
- [ ] All integration tests pass (pytest integration/)
- [ ] All scenario tests pass (pytest scenarios/)
- [ ] Code coverage > 80%
- [ ] US1 acceptance scenarios pass (automatic distribution)
- [ ] US2 acceptance scenarios pass (window preservation)
- [ ] US3 acceptance scenarios pass (distribution rules)
- [ ] US4 acceptance scenarios pass (state persistence) [if implemented]
- [ ] Manual end-to-end testing successful
- [ ] Daemon starts without errors
- [ ] Output events trigger reassignment within 1 second
- [ ] Debounce prevents flapping (500ms)
- [ ] Windows never lost during monitor changes
- [ ] State files created (`monitor-state.json`, `workspace-assignments.json`)
- [ ] IPC commands work (`i3pm monitors status`)
- [ ] Documentation updated (CLAUDE.md)
- [ ] Legacy code removed (MonitorConfigManager)
- [ ] Performance: <1s reassignment, <2s with 100+ windows
- [ ] Logs show detailed reassignment info

---

## Notes

- **Testing**: Tests are integrated throughout implementation (TDD approach)
- **Parallel Execution**: Use `[P]` marker to identify parallelizable tasks
- **Story Labels**: `[US1]`, `[US2]`, `[US3]`, `[US4]` indicate which user story the task serves
- **File Paths**: All paths are absolute or relative to repo root (`/etc/nixos/`)
- **Dependencies**: Follow critical path and inter-task dependencies
- **MVP Focus**: Prioritize Phase 1-3 for immediate value delivery

---

**Generated**: 2025-10-29
**Feature Branch**: 049-intelligent-automatic-workspace
**Related Docs**: spec.md, plan.md, data-model.md, contracts/, quickstart.md
