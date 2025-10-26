# Workspace Assignment Implementation Analysis (T026)

**Feature**: 039-create-a-new
**Task**: T026
**Date**: 2025-10-26

## Current Implementation Location

**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py`
**Lines**: 506-560
**Function**: `on_window_new()` event handler

## Implementation Analysis

### Current Architecture

The workspace assignment logic is currently **embedded** in the window::new event handler. It implements:

**Priority Tier Implemented**: Priority 3 only (I3PM_APP_NAME registry lookup)

```python
# Feature 037 T026-T029: Guaranteed workspace assignment on launch
# If window has I3PM_APP_NAME, look up preferred workspace in registry
if window_env and window_env.app_name and application_registry:
    app_name = window_env.app_name
    app_def = application_registry.get(app_name)

    if app_def and "preferred_workspace" in app_def:
        preferred_ws = app_def["preferred_workspace"]
        current_workspace = container.workspace()

        # Check if window is already on preferred workspace
        if current_workspace and current_workspace.num != preferred_ws:
            # Move window to preferred workspace
            await conn.command(
                f'[con_id="{container.id}"] move to workspace number {preferred_ws}'
            )
```

### Assessment

**Strengths**:
- ✅ Event-driven architecture (no polling)
- ✅ Uses application registry for configuration
- ✅ Includes workspace tracking for state preservation
- ✅ Error handling with try/except
- ✅ Comprehensive logging

**Limitations**:
- ❌ **Only implements Priority 3** (registry lookup)
- ❌ Missing Priority 1 (app-specific handlers like VS Code)
- ❌ Missing Priority 2 (I3PM_TARGET_WORKSPACE env var)
- ❌ Missing Priority 4 (window class matching fallback)
- ❌ Logic embedded in handler (not modular/testable)
- ❌ No explicit fallback to current workspace

### Compliance with Research.md

**Research.md Section 6** specifies 4-tier priority:

| Tier | Method | Status |
|------|--------|--------|
| 1 | App-specific handlers (VS Code title parsing) | ❌ **NOT IMPLEMENTED** |
| 2 | I3PM_TARGET_WORKSPACE environment variable | ❌ **NOT IMPLEMENTED** |
| 3 | I3PM_APP_NAME registry lookup | ✅ **IMPLEMENTED** |
| 4 | Window class matching (tiered) | ❌ **NOT IMPLEMENTED** |

**Compliance**: **25%** (1 of 4 tiers implemented)

## Recommendation for T027

### Create Consolidated Service

Extract workspace assignment to **dedicated service module**:

**New File**: `home-modules/desktop/i3-project-event-daemon/services/workspace_assigner.py`

**Service Should Implement**:

1. ✅ **Full 4-tier priority system**
2. ✅ **Modular, testable design**
3. ✅ **App-specific handler registry**
4. ✅ **Window class normalization** (from research.md Section 1)
5. ✅ **Explicit fallback behavior**
6. ✅ **Performance metrics** (<100ms per assignment)

### Benefits of Extraction

1. **Testability**: Can unit test workspace assignment logic independently
2. **Reusability**: Can be called from multiple handlers (window::new, daemon startup scan)
3. **Maintainability**: Single responsibility principle
4. **Extensibility**: Easy to add new priority tiers or app-specific handlers
5. **Performance**: Can optimize without touching handler code

### API Design

```python
class WorkspaceAssigner:
    """
    Assigns windows to workspaces using 4-tier priority system.
    """

    async def assign_workspace(
        self,
        window: WindowIdentity,
        i3pm_env: Optional[I3PMEnvironment],
        registry: Dict[str, Any],
        current_workspace: int
    ) -> WorkspaceAssignment:
        """
        Assign workspace using priority tiers:
        1. App-specific handler
        2. I3PM_TARGET_WORKSPACE env var
        3. I3PM_APP_NAME registry lookup
        4. Window class matching
        5. Fallback to current workspace

        Returns: WorkspaceAssignment with workspace number and source tier
        """
```

## Performance Baseline

**Current Implementation**:
- **Latency**: Unknown (no metrics collection)
- **Success Rate**: Unknown (no tracking)
- **Target**: <100ms per assignment (plan.md line 42)

**Test Coverage**:
- ✅ Integration tests created (T021)
- ✅ Target: 95% success rate (SC-002)
- ✅ Target: <200ms total latency

## Decision

**PROCEED** with T027 to create consolidated `workspace_assigner.py` service implementing:
- Full 4-tier priority system
- Window class normalization
- App-specific handler registry
- Comprehensive error handling
- Performance metrics

**Location Identified**: `handlers.py:506-560` is the best (and only) implementation.

**Action**: Extract and enhance, do not delete original until service is tested.

---

**Next Task**: T027 - Create workspace_assigner.py service
