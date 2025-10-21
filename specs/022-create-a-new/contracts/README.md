# API Contracts - Enhanced i3pm TUI

**Feature**: Enhanced i3pm TUI with Comprehensive Management & Automated Testing
**Branch**: `022-create-a-new`
**Date**: 2025-10-21

## Overview

This directory contains Python interface contracts (abstract base classes) defining the APIs for all major feature components. These contracts serve as:

1. **Implementation Contracts**: Concrete classes must implement these interfaces
2. **Testing Boundaries**: Mock implementations can be created for unit testing
3. **Documentation**: Contracts document expected behavior with docstrings
4. **Type Safety**: Enable static type checking with mypy

## Contract Files

### layout_manager.py

**Functional Requirements**: FR-001 through FR-008

**Key Interfaces**:
- `ILayoutManager`: Layout save/restore/delete/export operations
- `IWindowLauncher`: Application launching with window matching

**Key Data Structures**:
- `LayoutSaveRequest`, `LayoutSaveResponse`
- `LayoutRestoreRequest`, `LayoutRestoreResponse`
- `RestoreAllRequest`, `RestoreAllResponse`
- `CloseAllRequest`, `CloseAllResponse`

**Covered User Stories**:
- User Story 1: Complete Layout Management Workflow (P1)

---

### workspace_config.py

**Functional Requirements**: FR-009 through FR-013

**Key Interfaces**:
- `IWorkspaceConfigManager`: Workspace-to-monitor assignment management

**Key Data Structures**:
- `WorkspaceAssignment`
- `MonitorInfo`, `MonitorConfiguration`
- `WorkspaceConfigUpdateRequest`, `WorkspaceConfigUpdateResponse`
- `WorkspaceRedistributionRequest`, `WorkspaceRedistributionResponse`

**Covered User Stories**:
- User Story 2: Workspace-to-Monitor Assignment Configuration (P1)
- User Story 8: Monitor Detection and Workspace Redistribution (P2)

---

### test_framework.py

**Functional Requirements**: FR-029 through FR-033

**Key Interfaces**:
- `ITestFramework`: Automated TUI testing using Textual Pilot
- `IMockDaemonClient`: Mock daemon for isolated testing

**Key Data Structures**:
- `TestScenario`, `TestAction`, `TestAssertion`
- `TestResult`, `TestSuiteResult`
- `AssertionResult`, `AssertionType`, `TestActionType`

**Covered User Stories**:
- User Story 7: Automated TUI Testing Framework (P1)

---

## Contracts Not Created

The following functional requirements do NOT require new contracts as they are covered by existing implementations or are TUI-only concerns:

### Window Classification (FR-014 through FR-018)

Existing interfaces in `/etc/nixos/home-modules/tools/i3_project_manager/core/`:
- `AppClassification` model (models.py lines 453-575)
- `PatternRule` model (models/pattern.py)

TUI screen will use existing models directly without new service layer.

### Auto-Launch Configuration (FR-019 through FR-023)

Existing interface:
- `AutoLaunchApp` model (models.py lines 26-71)
- `Project.auto_launch` list

TUI screen will manipulate Project.auto_launch list directly.

### Navigation & UX (FR-024 through FR-028)

TUI implementation concerns:
- Vim-style navigation: Textual Binding configuration
- Mouse support: Textual built-in feature
- Breadcrumb navigation: Custom `BreadcrumbWidget` (data-model.md)
- Contextual keybindings: Screen.BINDINGS lists
- Inline validation: Input widget validation

No service layer contracts needed - pure UI implementation.

---

## Implementation Guidelines

### Using Contracts

1. **Import contract interface**:
```python
from specs.contracts.layout_manager import ILayoutManager, LayoutSaveRequest
```

2. **Implement concrete class**:
```python
class LayoutManager(ILayoutManager):
    def __init__(self, i3_connection, project_dir: Path):
        self.i3 = i3_connection
        self.project_dir = project_dir

    async def save_layout(self, request: LayoutSaveRequest) -> LayoutSaveResponse:
        # Implementation
        ...
```

3. **Use in TUI**:
```python
class LayoutManagerScreen(Screen):
    def __init__(self, layout_manager: ILayoutManager):
        super().__init__()
        self.layout_manager = layout_manager

    async def action_save_layout(self, layout_name: str):
        request = LayoutSaveRequest(...)
        response = await self.layout_manager.save_layout(request)
        ...
```

### Testing with Contracts

1. **Create mock implementation**:
```python
class MockLayoutManager(ILayoutManager):
    def __init__(self):
        self.save_calls = []

    async def save_layout(self, request: LayoutSaveRequest) -> LayoutSaveResponse:
        self.save_calls.append(request)
        return LayoutSaveResponse(success=True, ...)
```

2. **Use in tests**:
```python
async def test_layout_save_action():
    mock_manager = MockLayoutManager()
    screen = LayoutManagerScreen(mock_manager)

    await screen.action_save_layout("test-layout")

    assert len(mock_manager.save_calls) == 1
    assert mock_manager.save_calls[0].layout_name == "test-layout"
```

### Type Checking

Enable mypy type checking:

```bash
mypy --strict home-modules/tools/i3_project_manager/
```

All contract implementations should pass strict type checking.

---

## Contract Evolution

### Adding New Methods

When adding methods to existing contracts:

1. Add method to abstract base class with `@abstractmethod` decorator
2. Update all implementing classes
3. Add tests for new method
4. Update this README

### Breaking Changes

When making breaking changes (changing method signatures):

1. Create new contract version (e.g., `ILayoutManagerV2`)
2. Deprecate old contract with warnings
3. Provide migration guide
4. Maintain backward compatibility for 1 release cycle

### Backward Compatibility

All request/response dataclasses should use optional fields with defaults for new additions:

```python
@dataclass
class LayoutSaveRequest:
    project_name: str
    layout_name: str
    capture_launch_commands: bool = True  # New field with default
```

---

## Contract Validation

### Checklist for New Contracts

- [ ] All methods have `@abstractmethod` decorator
- [ ] All methods have comprehensive docstrings
- [ ] All request/response dataclasses defined
- [ ] Example usage provided in docstring or separate example
- [ ] Validation logic included where appropriate
- [ ] Performance constraints documented
- [ ] Error cases documented with raises clauses
- [ ] Type hints complete for all parameters and returns

### Review Criteria

1. **Completeness**: Does contract cover all functional requirements?
2. **Clarity**: Are method signatures and docstrings clear?
3. **Testability**: Can contract be easily mocked for testing?
4. **Type Safety**: Are all types properly annotated?
5. **Error Handling**: Are error cases documented?
6. **Performance**: Are timing constraints specified?

---

## Related Documentation

- [spec.md](../spec.md) - Feature specification with functional requirements
- [data-model.md](../data-model.md) - Entity definitions and relationships
- [research.md](../research.md) - Research findings informing contract design
- [plan.md](../plan.md) - Implementation plan with technical context

---

**Status**: ✅ **COMPLETED** - All required contracts defined and documented.

**Coverage**:
- Layout Management: ✅ Complete
- Workspace Configuration: ✅ Complete
- Test Framework: ✅ Complete
- Window Classification: ✅ Uses existing models
- Auto-Launch: ✅ Uses existing models
- Navigation/UX: ✅ TUI implementation only
