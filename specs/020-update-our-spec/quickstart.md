# Quick Start Guide: App Discovery & Auto-Classification System

**Branch**: `020-update-our-spec` | **Date**: 2025-10-21 | **Spec**: [spec.md](spec.md)

## Overview

This guide provides a fast path to implementing the four app discovery enhancements to i3pm:
1. **Pattern-Based Auto-Classification** - Create rules like `pwa-*` → global
2. **Automated Window Class Detection** - Detect WM_CLASS via Xvfb isolation
3. **Interactive Classification Wizard** - Visual TUI for bulk classification
4. **Real-Time Window Inspection** - Inspect and classify any window instantly

**Estimated Reading Time**: 10 minutes
**Estimated Implementation Time**: 4-6 weeks (phased approach)

---

## Prerequisites

### Required Knowledge

- Python 3.11+ with async/await patterns
- i3 IPC protocol (via i3ipc.aio library)
- Textual TUI framework basics
- NixOS package management and home-manager
- pytest for testing

### Required Tools

```bash
# Verify Python version
python3 --version  # Must be >= 3.11

# Verify i3 IPC connection
i3-msg -t get_version

# Verify existing i3pm installation
which i3pm
i3pm --version

# Verify dependencies
which xvfb-run  # For Xvfb detection (optional but recommended)
which xdotool   # For window selection in inspector
which xprop     # For X11 property inspection
```

### Existing Codebase Structure

```
home-modules/tools/i3_project_manager/
├── core/
│   ├── config.py           # AppClassConfig - EXTEND for patterns
│   ├── app_discovery.py    # AppDiscovery - ACTIVATE Xvfb detection
│   └── i3_client.py        # i3 IPC wrapper (reuse)
├── cli/
│   └── commands.py         # CLI commands - ADD new commands
└── tests/
    └── i3_project_manager/ # Existing test structure - EXTEND
```

**Key Insight**: ~60-80% of code already exists. This feature **extends** existing modules, not a from-scratch implementation.

---

## 30-Second Architecture Overview

```
User Actions
    │
    ├─> CLI Commands (cli/commands.py)
    │       └─> Pattern CRUD, Detect, Wizard, Inspector
    │
    ├─> TUI Applications (tui/wizard.py, tui/inspector.py)
    │       └─> Interactive visual workflows
    │
    └─> Core Services (core/)
            ├─> PatternMatcher - Match glob/regex patterns
            ├─> AppDiscovery - Detect WM_CLASS via Xvfb
            └─> AppClassConfig - Manage app-classes.json

Data Flow:
    .desktop files → AppDiscovery → DetectionResult
                          ↓
    User creates patterns → PatternMatcher → AppClassification
                          ↓
    Wizard reviews/edits → app-classes.json
                          ↓
    Daemon reloads config → Auto-classify new windows
```

**Key Principle**: Single source of truth is `app-classes.json`. All components read/write this file atomically.

---

## Phase 0: Environment Setup (30 minutes)

### 1. Create Feature Branch

```bash
cd /etc/nixos
git checkout -b 020-update-our-spec main
```

### 2. Review Existing Implementation

```bash
# Review pattern infrastructure (already ~80% complete)
cat home-modules/tools/i3_project_manager/core/config.py

# Review app discovery scaffold (~60% complete)
cat home-modules/tools/i3_project_manager/core/app_discovery.py

# Review TUI framework (Feature 019 foundation)
ls home-modules/tools/i3_project_manager/tui/
```

### 3. Verify Dependencies

```bash
# Check pyproject.toml dependencies
cat home-modules/tools/pyproject.toml

# Required dependencies (add if missing):
# - i3ipc (async i3 IPC) - ✅ Already present
# - textual (TUI framework) - ✅ Already present
# - rich (terminal formatting) - ✅ Already present
# - argcomplete (shell completion) - ADD if missing
```

### 4. Set Up Development Environment

```bash
# Create virtual environment (optional for testing)
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies in development mode
pip install -e home-modules/tools/

# Run existing tests to verify baseline
cd home-modules/tools
pytest tests/i3_project_manager/ -v
```

---

## Phase 1: Pattern-Based Classification (Week 1)

**Goal**: Users can create pattern rules for auto-classification

### Step 1.1: Create Data Models (2 hours)

Create `home-modules/tools/i3_project_manager/models/pattern.py`:

```python
from dataclasses import dataclass
from typing import Literal
import re
import fnmatch

@dataclass
class PatternRule:
    """Pattern-based window class classification rule."""
    pattern: str
    scope: Literal["scoped", "global"]
    priority: int = 0
    description: str = ""

    def __post_init__(self):
        """Validate pattern syntax."""
        if not self.pattern:
            raise ValueError("Pattern cannot be empty")
        if self.priority < 0:
            raise ValueError("Priority must be non-negative")

        # Validate regex if prefixed with "regex:"
        if self.pattern.startswith("regex:"):
            try:
                re.compile(self.pattern[6:])
            except re.error as e:
                raise ValueError(f"Invalid regex: {e}")

    def matches(self, window_class: str) -> bool:
        """Test if window class matches this pattern."""
        if self.pattern.startswith("glob:"):
            return fnmatch.fnmatch(window_class, self.pattern[5:])
        elif self.pattern.startswith("regex:"):
            return bool(re.match(self.pattern[6:], window_class))
        else:  # Literal match
            return window_class == self.pattern
```

**Test Immediately**:
```python
# tests/i3_project_manager/unit/test_pattern.py
def test_glob_pattern_matches():
    rule = PatternRule(pattern="glob:pwa-*", scope="global", priority=100)
    assert rule.matches("pwa-youtube") is True
    assert rule.matches("firefox") is False

def test_regex_pattern_matches():
    rule = PatternRule(pattern="regex:^(neo)?vim$", scope="scoped", priority=90)
    assert rule.matches("vim") is True
    assert rule.matches("neovim") is True
    assert rule.matches("gvim") is False

def test_invalid_regex_raises():
    with pytest.raises(ValueError, match="Invalid regex"):
        PatternRule(pattern="regex:^[invalid", scope="scoped")
```

### Step 1.2: Implement Pattern Matcher (4 hours)

Create `home-modules/tools/i3_project_manager/core/pattern_matcher.py`:

```python
from functools import lru_cache
from typing import Optional
from ..models.pattern import PatternRule

class PatternMatcher:
    """Pattern matching engine with LRU cache for performance."""

    def __init__(self, patterns: list[PatternRule]):
        # Sort by priority (descending) for first-match-wins
        self.patterns = sorted(patterns, key=lambda p: p.priority, reverse=True)

    @lru_cache(maxsize=1024)
    def match(self, window_class: str) -> Optional[str]:
        """Return scope if pattern matches, None otherwise."""
        for pattern in self.patterns:
            if pattern.matches(window_class):
                return pattern.scope
        return None

    def get_matching_pattern(self, window_class: str) -> Optional[PatternRule]:
        """Return the matching pattern rule (for debugging)."""
        for pattern in self.patterns:
            if pattern.matches(window_class):
                return pattern
        return None
```

**Performance Benchmark**:
```python
# tests/i3_project_manager/unit/test_pattern_matcher.py
import time

def test_pattern_matching_performance():
    """Verify <1ms matching time with 100+ patterns."""
    patterns = [
        PatternRule(f"glob:app-{i}-*", "global", i)
        for i in range(100)
    ]
    matcher = PatternMatcher(patterns)

    start = time.perf_counter()
    for _ in range(1000):
        matcher.match("app-50-test")
    elapsed = time.perf_counter() - start

    # Should average <1ms per match (1000 matches in <1 second)
    assert elapsed < 1.0, f"Took {elapsed}s for 1000 matches"
```

### Step 1.3: Extend AppClassConfig (2 hours)

Modify `home-modules/tools/i3_project_manager/core/config.py`:

```python
class AppClassConfig:
    """Manage app-classes.json with pattern support."""

    def __init__(self, config_path: Path = Path.home() / ".config/i3/app-classes.json"):
        self.config_path = config_path
        self.scoped_classes: list[str] = []
        self.global_classes: list[str] = []
        self.class_patterns: list[PatternRule] = []  # NEW
        self._load()

    def _load(self):
        """Load configuration from JSON file."""
        if not self.config_path.exists():
            return

        data = json.loads(self.config_path.read_text())
        self.scoped_classes = data.get("scoped_classes", [])
        self.global_classes = data.get("global_classes", [])

        # NEW: Load pattern rules
        patterns_data = data.get("class_patterns", [])
        self.class_patterns = [
            PatternRule(**p) for p in patterns_data
        ]

    def is_scoped(self, window_class: str) -> bool:
        """Determine if window class is scoped (with pattern support)."""
        # Precedence: explicit lists > patterns > heuristics
        if window_class in self.scoped_classes:
            return True
        if window_class in self.global_classes:
            return False

        # NEW: Check pattern matches
        from .pattern_matcher import PatternMatcher
        matcher = PatternMatcher(self.class_patterns)
        scope = matcher.match(window_class)
        if scope == "scoped":
            return True
        if scope == "global":
            return False

        # Fallback to heuristics
        return self._heuristic_classification(window_class)

    def add_pattern(self, pattern: PatternRule):
        """Add new pattern rule."""
        self.class_patterns.append(pattern)
        self._save()

    def remove_pattern(self, pattern_str: str):
        """Remove pattern rule by exact pattern string."""
        self.class_patterns = [
            p for p in self.class_patterns if p.pattern != pattern_str
        ]
        self._save()

    def _save(self):
        """Save configuration to JSON file (atomic write)."""
        data = {
            "scoped_classes": self.scoped_classes,
            "global_classes": self.global_classes,
            "class_patterns": [
                {
                    "pattern": p.pattern,
                    "scope": p.scope,
                    "priority": p.priority,
                    "description": p.description
                }
                for p in self.class_patterns
            ]
        }

        # Atomic write: temp file + rename
        temp_path = self.config_path.with_suffix(".tmp")
        temp_path.write_text(json.dumps(data, indent=2))
        temp_path.rename(self.config_path)
```

### Step 1.4: Add CLI Commands (4 hours)

Modify `home-modules/tools/i3_project_manager/cli/commands.py`:

```python
@click.group(name="app-classes")
def app_classes_group():
    """Manage application classifications."""
    pass

@app_classes_group.command(name="add-pattern")
@click.argument("pattern")
@click.argument("scope", type=click.Choice(["scoped", "global"]))
@click.option("--priority", type=int, default=0)
@click.option("--description", default="")
def add_pattern(pattern: str, scope: str, priority: int, description: str):
    """Add a new pattern rule for auto-classification."""
    from ..core.config import AppClassConfig
    from ..models.pattern import PatternRule

    try:
        rule = PatternRule(
            pattern=pattern,
            scope=scope,
            priority=priority,
            description=description
        )
    except ValueError as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)

    config = AppClassConfig()
    config.add_pattern(rule)

    click.echo(f"✓ Added pattern rule:")
    click.echo(f"  Pattern:     {pattern}")
    click.echo(f"  Scope:       {scope}")
    click.echo(f"  Priority:    {priority}")
    click.echo(f"  Description: {description}")
    click.echo(f"\nConfiguration updated: {config.config_path}")

    # Reload daemon
    reload_daemon()

@app_classes_group.command(name="list-patterns")
@click.option("--format", type=click.Choice(["table", "json"]), default="table")
def list_patterns(format: str):
    """List all configured pattern rules."""
    from ..core.config import AppClassConfig
    from rich.table import Table
    from rich.console import Console

    config = AppClassConfig()

    if format == "json":
        import json
        output = {
            "patterns": [
                {
                    "pattern": p.pattern,
                    "scope": p.scope,
                    "priority": p.priority,
                    "description": p.description
                }
                for p in config.class_patterns
            ],
            "total": len(config.class_patterns),
            "config_file": str(config.config_path)
        }
        click.echo(json.dumps(output, indent=2))
    else:
        table = Table(title=f"Pattern Rules ({len(config.class_patterns)} total)")
        table.add_column("Priority")
        table.add_column("Pattern")
        table.add_column("Scope")
        table.add_column("Description")

        for pattern in sorted(config.class_patterns, key=lambda p: p.priority, reverse=True):
            table.add_row(
                str(pattern.priority),
                pattern.pattern,
                pattern.scope,
                pattern.description
            )

        Console().print(table)
```

### Step 1.5: Integration Testing (4 hours)

```python
# tests/i3_project_manager/integration/test_pattern_workflow.py
def test_pattern_workflow_end_to_end():
    """Test complete pattern creation → matching → classification workflow."""
    config = AppClassConfig()

    # Add pattern rule
    rule = PatternRule(pattern="glob:pwa-*", scope="global", priority=100)
    config.add_pattern(rule)

    # Verify pattern matches
    assert config.is_scoped("pwa-youtube") is False  # Global
    assert config.is_scoped("pwa-spotify") is False  # Global

    # Verify explicit list takes precedence
    config.scoped_classes.append("pwa-special")
    assert config.is_scoped("pwa-special") is True  # Explicit > pattern

    # Remove pattern
    config.remove_pattern("glob:pwa-*")
    assert config.is_scoped("pwa-youtube") is True  # Falls back to heuristic
```

**Acceptance Criteria** (from spec.md User Story 1):
- ✅ Pattern syntax validation
- ✅ Precedence: explicit > patterns > heuristics
- ✅ Performance: <1ms matching with 100+ patterns
- ✅ CLI commands: add-pattern, list-patterns, remove-pattern, test-pattern

---

## Phase 2: Xvfb Detection (Week 2)

**Goal**: Automatically detect WM_CLASS for apps without StartupWMClass

### Step 2.1: Activate Existing Xvfb Code (4 hours)

The `app_discovery.py` already has Xvfb detection scaffolded. Activate it:

```python
# home-modules/tools/i3_project_manager/core/app_discovery.py

from contextlib import contextmanager
import subprocess
import time

@contextmanager
def isolated_xvfb(display_num: int = 99):
    """Context manager for isolated Xvfb session."""
    xvfb_proc = None
    try:
        # Start Xvfb on isolated display
        xvfb_proc = subprocess.Popen([
            "Xvfb",
            f":{display_num}",
            "-screen", "0", "1920x1080x24",
            "-nolisten", "tcp",
            "-noreset"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        time.sleep(0.5)  # Wait for X server startup
        yield f":{display_num}"

    finally:
        if xvfb_proc:
            xvfb_proc.terminate()
            try:
                xvfb_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                xvfb_proc.kill()
                xvfb_proc.wait()

def detect_window_class_xvfb(desktop_file: Path, timeout: int = 10) -> Optional[str]:
    """Detect WM_CLASS using Xvfb isolation."""
    with isolated_xvfb() as display:
        env = os.environ.copy()
        env["DISPLAY"] = display

        # Launch app in background
        exec_cmd = _parse_exec_from_desktop(desktop_file)
        app_proc = subprocess.Popen(
            exec_cmd,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        # Wait for window to appear and get WM_CLASS
        start = time.time()
        while time.time() - start < timeout:
            try:
                # Use xdotool to find window
                result = subprocess.run(
                    ["xdotool", "search", "--sync", "--onlyvisible", "--class", ".", "--limit", "1"],
                    env=env,
                    capture_output=True,
                    timeout=1
                )
                if result.returncode == 0 and result.stdout:
                    window_id = result.stdout.decode().strip()

                    # Get WM_CLASS with xprop
                    result = subprocess.run(
                        ["xprop", "-id", window_id, "WM_CLASS"],
                        env=env,
                        capture_output=True,
                        timeout=1
                    )
                    if result.returncode == 0:
                        # Parse: WM_CLASS(STRING) = "instance", "class"
                        output = result.stdout.decode()
                        match = re.search(r'"([^"]+)",\s*"([^"]+)"', output)
                        if match:
                            return match.group(2)  # Return class, not instance
            except subprocess.TimeoutExpired:
                pass

            time.sleep(0.5)

        return None  # Detection failed

    finally:
        # Cleanup: terminate app process
        if app_proc:
            app_proc.terminate()
            try:
                app_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                app_proc.kill()
```

### Step 2.2: Add Detection CLI Command (2 hours)

```python
@app_classes_group.command(name="detect")
@click.option("--all-missing", is_flag=True)
@click.option("--isolated", is_flag=True, default=True)
@click.option("--cache", is_flag=True)
@click.option("--verbose", is_flag=True)
def detect(all_missing: bool, isolated: bool, cache: bool, verbose: bool):
    """Detect window classes for applications using Xvfb isolation."""
    from ..core.app_discovery import AppDiscovery, detect_window_class_xvfb

    discovery = AppDiscovery()
    apps = discovery.discover_apps()

    # Filter to apps without known WM_CLASS
    if all_missing:
        config = AppClassConfig()
        apps = [
            app for app in apps
            if app.window_class is None or app.window_class not in (
                config.scoped_classes + config.global_classes
            )
        ]

    click.echo(f"Detecting window classes for {len(apps)} applications...")

    results = []
    for i, app in enumerate(apps, 1):
        if verbose:
            click.echo(f"\n[{i}/{len(apps)}] {app.name}...")
            click.echo(f"  Desktop file: {app.desktop_file}")

        detected_class = detect_window_class_xvfb(app.desktop_file)

        result = DetectionResult(
            desktop_file=str(app.desktop_file),
            app_name=app.name,
            detected_class=detected_class,
            detection_method="xvfb" if detected_class else "failed",
            confidence=1.0 if detected_class else 0.0,
            error_message=None if detected_class else "Xvfb detection timed out"
        )
        results.append(result)

        if verbose:
            if detected_class:
                click.echo(f"  Detected:     {detected_class}")
                click.echo(f"  Confidence:   100%")
            else:
                click.echo(f"  Detection:    FAILED")

    # Summary
    successful = sum(1 for r in results if r.detected_class is not None)
    click.echo(f"\nSummary:")
    click.echo(f"  Successful: {successful}/{len(results)}")
    click.echo(f"  Failed:     {len(results) - successful}/{len(results)}")

    # Cache results
    if cache:
        cache_path = Path.home() / ".cache/i3pm/detected-classes.json"
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_data = {
            "results": [asdict(r) for r in results],
            "cache_version": "1.0",
            "last_updated": datetime.now().isoformat()
        }
        cache_path.write_text(json.dumps(cache_data, indent=2))
        click.echo(f"  Cache:      {cache_path}")
```

**Acceptance Criteria** (from spec.md User Story 2):
- ✅ Xvfb isolation (separate DISPLAY)
- ✅ Timeout handling (10s default)
- ✅ Cleanup (100% reliable, no zombies)
- ✅ Performance: 10 apps in <60s

---

## Phase 3: Window Inspector (Week 3)

**Goal**: Real-time window property inspection with direct classification

### Step 3.1: Create Inspector TUI (8 hours)

See [contracts/tui-inspector.md](contracts/tui-inspector.md) for complete specification.

Key implementation file: `home-modules/tools/i3_project_manager/tui/inspector.py`

**Minimal Viable Inspector**:
```python
from textual.app import App, ComposeResult
from textual.widgets import Static, DataTable
from i3ipc.aio import Connection

class InspectorApp(App):
    """Window property inspector TUI."""

    BINDINGS = [
        ("s", "classify_scoped", "Mark as Scoped"),
        ("g", "classify_global", "Mark as Global"),
        ("r", "refresh", "Refresh"),
        ("escape", "exit", "Exit"),
    ]

    def __init__(self, window_id: int):
        super().__init__()
        self.window_id = window_id
        self.window_props = None

    async def on_mount(self) -> None:
        """Load window properties on startup."""
        await self.refresh_properties()

    async def refresh_properties(self):
        """Query i3 for window properties."""
        i3 = await Connection().connect()
        tree = await i3.get_tree()

        # Find window by con_id
        window = tree.find_by_id(self.window_id)
        if not window:
            self.exit(message="Window not found")
            return

        self.window_props = WindowProperties(
            window_id=window.id,
            window_class=window.window_class,
            instance=window.window_instance,
            title=window.name,
            marks=window.marks,
            workspace=window.workspace().name,
            current_classification=self._get_classification(window.window_class),
            suggested_classification=self._suggest_classification(window.window_class),
            reasoning=self._explain_classification(window.window_class)
        )

        self.query_one("#properties-table", DataTable).clear()
        self._populate_properties_table()

    def _get_classification(self, window_class: str) -> str:
        """Determine current classification status."""
        config = AppClassConfig()
        if window_class in config.scoped_classes:
            return "scoped"
        elif window_class in config.global_classes:
            return "global"
        else:
            return "unclassified"

    async def action_classify_scoped(self):
        """Classify window as scoped."""
        config = AppClassConfig()
        if self.window_props.window_class not in config.scoped_classes:
            config.scoped_classes.append(self.window_props.window_class)
            config._save()
            reload_daemon()
            self.notify(f"✓ Classified '{self.window_props.window_class}' as scoped")
            await self.refresh_properties()
```

**Acceptance Criteria** (from spec.md User Story 4):
- ✅ Click mode (xdotool selectwindow)
- ✅ Focused mode (i3 GET_TREE → find_focused)
- ✅ Property display (<100ms)
- ✅ Direct classification (s/g keys)
- ✅ Live mode (i3 event subscriptions)

---

## Phase 4: Classification Wizard (Weeks 4-5)

**Goal**: Visual interface for bulk classification

### Step 4.1: Create Wizard TUI (12 hours)

See [contracts/tui-wizard.md](contracts/tui-wizard.md) for complete specification.

Key implementation file: `home-modules/tools/i3_project_manager/tui/wizard.py`

**Architecture**:
1. **Main Screen**: Sortable table of all apps with keyboard navigation
2. **Detail Panel**: Show suggestion reasoning for selected app
3. **Filter/Sort Controls**: Dropdown menus for filtering and sorting
4. **Keyboard Actions**: s/g/u for classification, Space for multi-select
5. **Undo/Redo Stack**: Ctrl+Z/Ctrl+Y for undoing changes

**Key Challenge**: Virtualized table rendering for 1000+ apps with <50ms responsiveness

**Solution**: Use Textual's built-in virtualization:
```python
from textual.widgets import DataTable

table = DataTable(id="app-table", virtual=True)  # Only renders visible rows
```

**Acceptance Criteria** (from spec.md User Story 3):
- ✅ Visual classification workflow
- ✅ Keyboard navigation (<50ms response)
- ✅ Bulk actions (Accept All with confidence threshold)
- ✅ Undo/redo support
- ✅ Memory usage <100MB with 1000+ apps

---

## Testing Strategy

### Unit Tests (20+ tests per phase)

```bash
# Pattern matching
pytest tests/i3_project_manager/unit/test_pattern_matcher.py -v

# Data models
pytest tests/i3_project_manager/unit/test_models.py -v

# Configuration management
pytest tests/i3_project_manager/unit/test_config.py -v
```

### Integration Tests (10+ tests per phase)

```bash
# Xvfb detection (mocked)
pytest tests/i3_project_manager/integration/test_xvfb_detection.py -v

# Wizard workflow
pytest tests/i3_project_manager/integration/test_wizard_workflow.py -v

# Inspector workflow
pytest tests/i3_project_manager/integration/test_inspector_workflow.py -v
```

### Scenario Tests (End-to-End)

```bash
# Pattern creation → matching → classification
pytest tests/i3_project_manager/scenarios/test_pattern_lifecycle.py -v

# Discovery → detection → wizard → save
pytest tests/i3_project_manager/scenarios/test_classification_e2e.py -v
```

---

## Deployment

### 1. Update NixOS Package

```nix
# home-modules/tools/i3-project-manager.nix
{ pkgs, ... }:

pkgs.python3Packages.buildPythonApplication {
  pname = "i3-project-manager";
  version = "0.3.0";  # Bump version

  src = ./.;

  propagatedBuildInputs = with pkgs.python3Packages; [
    i3ipc
    textual
    rich
    argcomplete  # NEW
    # ... existing dependencies
  ];

  # Add runtime dependencies for Xvfb detection
  buildInputs = with pkgs; [
    xvfb-run
    xdotool
    xprop
  ];
}
```

### 2. Test NixOS Rebuild

```bash
# Dry build first
sudo nixos-rebuild dry-build --flake .#hetzner

# If successful, apply
sudo nixos-rebuild switch --flake .#hetzner
```

### 3. Verify Installation

```bash
# Verify commands available
i3pm app-classes --help
i3pm app-classes add-pattern --help
i3pm app-classes wizard --help
i3pm app-classes inspect --help

# Test pattern creation
i3pm app-classes add-pattern "glob:pwa-*" global --priority=100

# Test wizard launch
i3pm app-classes wizard

# Test inspector launch
i3pm app-classes inspect --focused
```

---

## Troubleshooting

### Common Issues

**Issue 1: Xvfb not found**
```bash
# Error: xvfb-run: command not found

# Fix: Install Xvfb
nix-env -iA nixpkgs.xorg.xorgserver  # Or add to NixOS config
```

**Issue 2: Pattern not matching**
```bash
# Test pattern explicitly
i3pm app-classes test-pattern "glob:pwa-*" "pwa-youtube"

# Check pattern syntax
i3pm app-classes list-patterns --format=json
```

**Issue 3: Daemon not reloading**
```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Manual reload
systemctl --user restart i3-project-event-listener

# Verify config loaded
cat ~/.config/i3/app-classes.json
```

---

## Next Steps

1. **Read Full Specification**: [spec.md](spec.md) for all 63 functional requirements
2. **Review Data Models**: [data-model.md](data-model.md) for entity definitions
3. **Study CLI Contracts**: [contracts/cli-commands.md](contracts/cli-commands.md)
4. **Study TUI Contracts**: [contracts/tui-wizard.md](contracts/tui-wizard.md), [contracts/tui-inspector.md](contracts/tui-inspector.md)
5. **Review Research Decisions**: [research.md](research.md) for architectural rationale

---

**Document Version**: 1.0
**Last Updated**: 2025-10-21
**Phase**: 1 (Quick Start) - COMPLETE
