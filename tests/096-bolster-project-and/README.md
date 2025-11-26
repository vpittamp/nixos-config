# Feature 096: Bolster Project & Worktree CRUD Operations - Test Suite

This directory contains tests for Feature 096 which enhances the monitoring panel's CRUD operations for projects and worktrees.

## Test Structure

```
tests/096-bolster-project-and/
├── unit/                          # Python unit tests
│   ├── test_conflict_detection.py # T006-T008: Conflict detection logic
│   └── test_shell_script_execution.py # T009-T011: Shell script behavior
├── integration/                   # End-to-end Python tests
│   └── test_crud_end_to_end.py   # T028, T040, T053: Full CRUD workflows
├── sway-tests/                    # Sway-test JSON-based UI tests
├── screenshots/                   # Visual regression testing
│   └── baseline/                  # Reference screenshots
├── scripts/                       # Helper utilities
│   ├── capture-screenshot.sh     # grim-based screenshot capture
│   ├── compare-screenshots.py    # PIL-based image diff
│   └── eww-debug.sh              # Eww troubleshooting helper
└── conftest.py                   # Shared pytest fixtures
```

## Running Tests

```bash
# Run all Feature 096 tests
python -m pytest tests/096-bolster-project-and/ -v

# Run only unit tests
python -m pytest tests/096-bolster-project-and/unit/ -v

# Run only integration tests
python -m pytest tests/096-bolster-project-and/integration/ -v

# Run with coverage
python -m pytest tests/096-bolster-project-and/ --cov=home-modules/tools/i3_project_manager
```

## Key Test Areas

### 1. Conflict Detection (T006-T008)

Tests verify the bug fix where conflict detection no longer returns false positives:
- **Before fix**: Compared mtime BEFORE read vs AFTER write (always different)
- **After fix**: Compares mtime BEFORE read vs BEFORE write (detects external changes only)

```python
# Key assertion in test_conflict_detection.py
assert result['conflict'] is False, "No false positive when no external modification"
```

### 2. Shell Script Error Handling (T009-T011)

Tests verify the shell script no longer exits with error when `conflict=true`:
- **Before fix**: `exit 1` when conflict detected (even though save succeeded)
- **After fix**: Shows warning notification but continues success flow

### 3. CRUD End-to-End (T028, T040, T053)

Tests the complete create/edit/delete workflows via Python's `ProjectEditor`:
- Project creation with validation
- Project editing with data preservation
- Project deletion with backup creation

## Screenshot Testing Methodology (T085)

### Capturing Baselines

```bash
# Capture a screenshot of the monitoring panel
./scripts/capture-screenshot.sh monitoring-panel baseline/panel-default.png

# Capture with specific region
./scripts/capture-screenshot.sh --region "0,0 400x600" baseline/sidebar.png
```

### Comparing Screenshots

```bash
# Compare current vs baseline
./scripts/compare-screenshots.py \
    screenshots/baseline/panel-default.png \
    screenshots/current/panel-default.png \
    --threshold 0.05  # 5% difference allowed
```

### GTK Inspector for CSS Debugging (T085)

When debugging visual issues with the eww widgets:

1. **Enable GTK Inspector**:
   ```bash
   GTK_DEBUG=interactive eww --config ~/.config/eww-monitoring-panel open monitoring-panel
   ```

2. **Or use keyboard shortcut** (in eww window):
   - Press `Ctrl+Shift+I` to open Inspector

3. **Useful Inspector tabs**:
   - **CSS**: View and live-edit styles
   - **Objects**: Inspect widget hierarchy
   - **Visual**: See widget bounds, margins, padding

4. **Using eww-debug.sh**:
   ```bash
   # Restart eww with debug mode and follow logs
   ./scripts/eww-debug.sh restart

   # Show all CRUD-related variable states
   ./scripts/eww-debug.sh vars

   # Follow eww logs
   ./scripts/eww-debug.sh logs
   ```

## Fixture Reference

### `temp_projects_dir`

Creates a temporary directory for project JSON files that is automatically cleaned up after tests.

### `sample_project_config`

Provides a valid project configuration dict with:
- Valid emoji icon (`\U0001F4C1` - folder emoji)
- Actual existing directory
- Valid scope (`scoped`)

```python
@pytest.fixture
def sample_project_config(temp_projects_dir):
    project_dir = temp_projects_dir / "test-project-dir"
    project_dir.mkdir(parents=True, exist_ok=True)
    return {
        "name": "test-project",
        "display_name": "Test Project",
        "icon": "\U0001F4C1",
        "directory": str(project_dir),
        "scope": "scoped",
    }
```

## Troubleshooting

### Tests fail with Pydantic validation errors

Ensure fixtures provide:
- Valid emoji for `icon` field (single emoji character)
- Existing directory path for `directory` field
- Valid scope value (`scoped` or `global`)

### Shell script tests skip

If tests skip with "project-edit-save not in PATH", run:
```bash
sudo nixos-rebuild switch --flake .#m1 --impure
```

### Eww widget not updating

1. Check if daemon is running:
   ```bash
   systemctl --user status eww-monitoring-panel
   ```

2. Use debug helper:
   ```bash
   ./scripts/eww-debug.sh vars
   ```

3. Restart eww:
   ```bash
   systemctl --user restart eww-monitoring-panel
   ```
