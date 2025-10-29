# Sway Configuration Manager Test Suite

**Feature**: 047 - Dynamic Sway Configuration Management Architecture
**Task**: T055 - Validation error test suite

## Overview

This test suite validates 100% syntax error detection before configuration reload (Success Criteria SC-006).

## Test Coverage

### 1. Keybinding Syntax Validation (`test_validation_errors.py::TestKeybindingSyntaxValidation`)

Tests for common keybinding syntax errors:
- ✅ Double plus signs (`Mod++Return`)
- ✅ Trailing plus signs (`Mod+`)
- ✅ Empty key combinations
- ✅ Invalid modifier keys

### 2. Window Rule Regex Validation (`test_validation_errors.py::TestWindowRuleRegexValidation`)

Tests for regex pattern errors in window rule criteria:
- ✅ Unclosed brackets (`[invalid(regex`)
- ✅ Incomplete named groups (`(?P<invalid>`)
- ✅ Invalid quantifiers (`***`)
- ✅ Invalid backslash escapes

### 3. Workspace Assignment Validation (`test_validation_errors.py::TestWorkspaceAssignmentValidation`)

Tests for workspace assignment errors:
- ✅ Workspace numbers below 1 (minimum)
- ✅ Workspace numbers above 70 (maximum)
- ✅ Negative workspace numbers

### 4. Schema Validation (`test_validation_errors.py::TestSchemaValidation`)

Tests for JSON Schema structural validation:
- ✅ Missing required fields
- ✅ Invalid field types
- ✅ Extra/unknown fields (if strict mode enabled)

### 5. Comprehensive Validation (`test_validation_errors.py::TestComprehensiveValidation`)

Tests for end-to-end validation scenarios:
- ✅ Multiple error types in one configuration
- ✅ Validation errors provide helpful suggestions
- ✅ Validation errors include file paths

## Running Tests

### Run all tests:

```bash
cd /etc/nixos/home-modules/desktop/sway-config-manager
pytest
```

### Run specific test class:

```bash
pytest tests/test_validation_errors.py::TestKeybindingSyntaxValidation
```

### Run specific test:

```bash
pytest tests/test_validation_errors.py::TestKeybindingSyntaxValidation::test_double_plus_in_key_combo
```

### Run with verbose output:

```bash
pytest -v
```

### Run with coverage (if pytest-cov installed):

```bash
pytest --cov=config --cov-report=term-missing
```

## Test Environment

### Requirements:

- Python 3.11+
- pytest
- pytest-asyncio
- All dependencies from `requirements.txt`

### Optional (for Sway IPC tests):

- Running Sway session
- i3ipc.aio library
- Sway IPC socket accessible

## Test Fixtures

Common test fixtures are defined in `conftest.py`:

- `temp_config_dir`: Temporary configuration directory
- `valid_keybindings`: Valid keybinding test data
- `valid_window_rules`: Valid window rule test data
- `valid_workspace_assignments`: Valid workspace assignment test data
- `invalid_*`: Various invalid configuration data for error testing

## Success Criteria

**SC-006**: 100% syntax error detection before configuration reload

The test suite validates that:
1. All syntax errors are detected before reload
2. Validation errors include helpful suggestions
3. Validation errors include file paths for debugging
4. Multiple error types can be detected in one pass

## Integration with CI/CD

These tests can be run in CI/CD pipelines:

```bash
# Run tests and fail on any errors
pytest --tb=short --color=yes

# Generate JUnit XML report for CI
pytest --junit-xml=test-results.xml

# Generate coverage report
pytest --cov=config --cov-report=xml
```

## Future Test Categories

Additional test categories can be added:

1. **Integration Tests** (`tests/integration/`):
   - Full daemon initialization
   - Configuration reload workflows
   - Rollback scenarios

2. **Performance Tests** (`tests/performance/`):
   - Validation speed benchmarks
   - Reload timing tests
   - Memory usage tests

3. **End-to-End Tests** (`tests/e2e/`):
   - Complete user workflows
   - Multi-project scenarios
   - Version control integration

## Troubleshooting

### Import errors:

Ensure the package is installed in development mode:
```bash
cd /etc/nixos/home-modules/desktop/sway-config-manager
pip install -e .
```

### Async test failures:

Ensure pytest-asyncio is installed:
```bash
pip install pytest-asyncio
```

### Sway IPC tests skipped:

Sway IPC tests require a running Sway session. They are marked with `@pytest.mark.sway_ipc` and can be run selectively:
```bash
pytest -m sway_ipc
```

Or skipped:
```bash
pytest -m "not sway_ipc"
```
