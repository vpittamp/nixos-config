# Phase 0: Research & Technology Decisions

**Feature**: Project-Scoped Scratchpad Terminal
**Date**: 2025-11-05

## Research Questions

From Technical Context unknowns and design decisions needed:

1. **How should scratchpad terminals be uniquely identified and tracked?**
2. **What is the optimal terminal launch mechanism with environment variable injection?**
3. **How should terminal state be synchronized between daemon and Sway IPC?**
4. **What Sway scratchpad commands are needed for show/hide/toggle operations?**
5. **How should window events be filtered to distinguish scratchpad terminals from regular windows?**

## Research Findings

### 1. Terminal Identification & Tracking

**Decision**: Use Sway window marks combined with I3PM_* environment variables

**Rationale**:
- Sway marks are persistent across hide/show operations and queryable via `GET_MARKS` IPC
- I3PM_* environment variables (read from `/proc/<pid>/environ`) provide application identity verification
- Combined approach: mark format `scratchpad:PROJECT_NAME`, env var `I3PM_SCRATCHPAD=true`
- Matches existing i3pm window identification patterns (Principle XI compliance)

**Implementation Pattern**:
```python
# Mark scratchpad terminal on launch
mark = f"scratchpad:{project_name}"
await sway.command(f'[con_id={window_id}] mark {mark}')

# Query scratchpad terminals
tree = await sway.get_tree()
scratchpad_windows = [w for w in tree.descendants() if any(m.startswith("scratchpad:") for m in w.marks)]

# Verify via environment variables
env_vars = read_process_environ(window.pid)
is_scratchpad = env_vars.get("I3PM_SCRATCHPAD") == "true"
```

**Alternatives Considered**:
- App_id modification: Rejected - would conflict with Alacritty's default app_id and complicate window filtering
- Database storage only: Rejected - Sway IPC is authoritative (Principle XI), daemon state can desync
- Window title modification: Rejected - user-visible and fragile

### 2. Terminal Launch Mechanism

**Decision**: Subprocess launch with environment variable injection via `env` parameter

**Rationale**:
- Python's `asyncio.create_subprocess_exec()` allows custom environment dictionaries
- Inject I3PM_* variables before launch: `I3PM_SCRATCHPAD=true`, `I3PM_PROJECT_NAME`, `I3PM_WORKING_DIR`
- Launch command: `alacritty --working-directory /path/to/project`
- Alacritty respects `--working-directory` flag for initial directory

**Implementation Pattern**:
```python
async def launch_scratchpad_terminal(project_name: str, working_dir: Path) -> int:
    """Launch Alacritty terminal with project environment variables."""
    env = {
        **os.environ,  # Inherit user environment
        "I3PM_SCRATCHPAD": "true",
        "I3PM_PROJECT_NAME": project_name,
        "I3PM_WORKING_DIR": str(working_dir),
        "I3PM_APP_ID": f"scratchpad-{project_name}-{int(time.time())}",
    }

    proc = await asyncio.create_subprocess_exec(
        "alacritty",
        "--working-directory", str(working_dir),
        env=env,
    )

    return proc.pid
```

**Alternatives Considered**:
- Wrapper script: Rejected - adds complexity, harder to debug, violates Principle VI (declarative over imperative)
- Alacritty config file generation: Rejected - config is global, can't be project-specific at launch time
- Desktop file creation: Rejected - unnecessary indirection, harder to pass dynamic parameters

### 3. Daemon State Synchronization

**Decision**: In-memory state with Sway IPC validation on every operation

**Rationale**:
- Daemon maintains `Dict[str, ScratchpadTerminal]` mapping project → terminal metadata
- Before show/hide operations, validate window exists via Sway IPC `GET_TREE`
- On window close event, remove from daemon state
- Event-driven updates via Sway IPC window subscriptions (Principle XI compliance)

**State Model (Pydantic)**:
```python
from pydantic import BaseModel
from typing import Optional

class ScratchpadTerminal(BaseModel):
    project_name: str
    pid: int
    window_id: int
    mark: str
    working_dir: Path
    created_at: float
    last_shown_at: Optional[float] = None

    def is_valid(self) -> bool:
        """Check if process is still running."""
        return psutil.pid_exists(self.pid)
```

**Synchronization Pattern**:
```python
async def validate_terminal(self, project_name: str) -> bool:
    """Validate scratchpad terminal exists in Sway IPC state."""
    terminal = self.scratchpad_terminals.get(project_name)
    if not terminal:
        return False

    # Validate process exists
    if not terminal.is_valid():
        del self.scratchpad_terminals[project_name]
        return False

    # Validate window exists in Sway
    tree = await self.sway.get_tree()
    window = tree.find_by_id(terminal.window_id)
    if not window:
        del self.scratchpad_terminals[project_name]
        return False

    return True
```

**Alternatives Considered**:
- JSON file persistence: Rejected - adds file I/O overhead, doesn't help with stale state (Sway restarts invalidate it)
- SQLite storage: Rejected - overkill for ephemeral single-user state
- No validation: Rejected - violates Principle XI (Sway IPC as authoritative source)

### 4. Sway Scratchpad Commands

**Decision**: Use Sway's built-in scratchpad commands via IPC

**Rationale**:
- Sway provides `move scratchpad`, `scratchpad show`, and criteria-based selection
- Commands are atomic and reliable
- Floating window configuration can be set with `for_window` rules or explicit commands

**Command Patterns**:
```python
# Move window to scratchpad (hide)
await sway.command(f'[con_mark="{mark}"] move scratchpad')

# Show window from scratchpad
await sway.command(f'[con_mark="{mark}"] scratchpad show')

# Toggle (show if hidden, hide if visible) - check state first
tree = await sway.get_tree()
window = next((w for w in tree.descendants() if mark in w.marks), None)
if window and window.parent.name != "__i3_scratch":  # Visible
    await sway.command(f'[con_mark="{mark}"] move scratchpad')
else:  # Hidden
    await sway.command(f'[con_mark="{mark}"] scratchpad show')

# Set floating and dimensions on launch
await sway.command(f'[con_mark="{mark}"] floating enable, resize set 1400 850, move position center')
```

**Sway Scratchpad Mechanics**:
- Windows moved to scratchpad go into `__i3_scratch` workspace (invisible)
- Process continues running while in scratchpad
- `scratchpad show` brings window to current workspace
- Multiple `scratchpad show` cycles through scratchpad windows (need criteria to target specific window)

**Alternatives Considered**:
- Custom hide/show via workspace moves: Rejected - reinvents the wheel, scratchpad is designed for this
- Minimize/unminimize: Rejected - not available in Sway, minimize is X11 concept

### 5. Window Event Filtering

**Decision**: Filter window events by mark prefix `scratchpad:` and I3PM_SCRATCHPAD env var

**Rationale**:
- Sway window events fire for all windows (new, close, focus, move)
- Need to identify scratchpad terminal events vs regular terminals vs other windows
- Two-stage filtering: mark check (fast) → env var validation (slower, only when needed)

**Event Handler Pattern**:
```python
async def on_window_new(self, event):
    """Handle new window creation events."""
    window = event.container

    # Wait for window to be fully initialized
    await asyncio.sleep(0.1)

    # Check if this is a potential scratchpad terminal
    if not window.app_id or "alacritty" not in window.app_id.lower():
        return  # Not a terminal

    # Read environment variables to confirm
    try:
        env_vars = read_process_environ(window.pid)
    except (ProcessLookupError, PermissionError):
        return  # Can't read process, skip

    if env_vars.get("I3PM_SCRATCHPAD") != "true":
        return  # Not a scratchpad terminal

    # This is a scratchpad terminal - mark and configure it
    project_name = env_vars.get("I3PM_PROJECT_NAME", "global")
    mark = f"scratchpad:{project_name}"

    await self.sway.command(f'[con_id={window.id}] mark {mark}')
    await self.sway.command(f'[con_id={window.id}] floating enable, resize set 1400 850, move position center')

    # Track in daemon state
    self.scratchpad_terminals[project_name] = ScratchpadTerminal(
        project_name=project_name,
        pid=window.pid,
        window_id=window.id,
        mark=mark,
        working_dir=Path(env_vars.get("I3PM_WORKING_DIR", "~")),
        created_at=time.time(),
    )

async def on_window_close(self, event):
    """Handle window close events."""
    window = event.container

    # Check if this is a tracked scratchpad terminal
    for mark in window.marks:
        if mark.startswith("scratchpad:"):
            project_name = mark.replace("scratchpad:", "")
            if project_name in self.scratchpad_terminals:
                del self.scratchpad_terminals[project_name]
                logger.info(f"Scratchpad terminal closed for project: {project_name}")
            break
```

**Alternatives Considered**:
- Poll for changes: Rejected - event-driven is more efficient and responsive (Principle XI)
- Filter by app_id modification: Rejected - would require Alacritty wrapper or config
- No filtering, handle all windows: Rejected - wasteful, violates single responsibility

## Best Practices & Integration Patterns

### Sway Keybinding Integration

**Pattern**: Add keybinding to Sway configuration that triggers daemon JSON-RPC call

**Implementation**:
```nix
# home-modules/desktop/sway.nix
bindsym $mod+Shift+Return exec i3pm scratchpad toggle
```

**CLI command calls daemon**:
```typescript
// home-modules/tools/i3pm-deno/src/commands/scratchpad.ts
export async function toggleScratchpad() {
  const client = new DaemonClient();
  await client.connect();

  const result = await client.call("scratchpad.toggle", {});
  console.log(result.message);
}
```

**Daemon JSON-RPC handler**:
```python
# home-modules/tools/i3pm/src/daemon/rpc_handlers.py
async def handle_scratchpad_toggle(self, params: dict) -> dict:
    """Toggle scratchpad terminal for current project."""
    current_project = self.state.current_project
    if not current_project:
        current_project = "global"

    terminal = self.scratchpad_manager.get_terminal(current_project)

    if not terminal:
        # Launch new terminal
        working_dir = self.get_project_working_dir(current_project)
        await self.scratchpad_manager.launch_terminal(current_project, working_dir)
        return {"status": "launched", "project": current_project}

    # Validate and toggle existing terminal
    if not await self.scratchpad_manager.validate_terminal(current_project):
        # Terminal died, relaunch
        working_dir = self.get_project_working_dir(current_project)
        await self.scratchpad_manager.launch_terminal(current_project, working_dir)
        return {"status": "relaunched", "project": current_project}

    # Toggle visibility
    await self.scratchpad_manager.toggle_terminal(current_project)
    return {"status": "toggled", "project": current_project}
```

### Testing Strategy

**Unit Tests** (70%):
- `ScratchpadTerminal` model validation
- Mark generation/parsing functions
- State synchronization logic
- Environment variable injection

**Integration Tests** (20%):
- Daemon JSON-RPC endpoint calls
- Sway IPC command execution
- Window event subscription and filtering
- Process lifecycle management

**End-to-End Tests** (10%):
- Full user workflow: keybinding → terminal launch → toggle → multi-project isolation
- Automated via ydotool for keybinding simulation
- State verification via Sway IPC queries

**Test Example (E2E)**:
```python
# tests/scenarios/test_user_workflows.py
import pytest
import asyncio
import subprocess
from i3ipc.aio import Connection

@pytest.mark.asyncio
async def test_scratchpad_terminal_launch_and_toggle():
    """Test US-001: Quick Terminal Access - first launch, hide, show."""
    # Given: User is in project "nixos"
    subprocess.run(["i3pm", "project", "switch", "nixos"], check=True)
    await asyncio.sleep(0.5)  # Allow project switch to complete

    # When: User presses Mod+Shift+Return (simulated)
    subprocess.run(["ydotool", "key", "125:1", "42:1", "28:1", "28:0", "42:0", "125:0"], check=True)
    await asyncio.sleep(2)  # Allow terminal launch

    # Then: Alacritty terminal appears as floating window
    async with Connection() as sway:
        tree = await sway.get_tree()
        scratchpad_windows = [w for w in tree.descendants()
                            if "scratchpad:nixos" in w.marks]

        assert len(scratchpad_windows) == 1, "Scratchpad terminal not found"
        window = scratchpad_windows[0]

        assert window.floating == "user_on", "Terminal not floating"
        assert window.rect.width == 1400, f"Terminal width {window.rect.width}, expected 1400"
        assert window.rect.height == 850, f"Terminal height {window.rect.height}, expected 850"

    # When: User presses Mod+Shift+Return again (hide)
    subprocess.run(["ydotool", "key", "125:1", "42:1", "28:1", "28:0", "42:0", "125:0"], check=True)
    await asyncio.sleep(0.5)

    # Then: Terminal hidden to scratchpad
    async with Connection() as sway:
        tree = await sway.get_tree()
        scratchpad = tree.scratchpad()

        assert len(scratchpad.descendants()) > 0, "No windows in scratchpad"
        assert any("scratchpad:nixos" in w.marks for w in scratchpad.descendants()), \
            "Scratchpad terminal not in scratchpad"

    # When: User presses Mod+Shift+Return again (show)
    subprocess.run(["ydotool", "key", "125:1", "42:1", "28:1", "28:0", "42:0", "125:0"], check=True)
    await asyncio.sleep(0.5)

    # Then: Same terminal appears (process still running)
    async with Connection() as sway:
        tree = await sway.get_tree()
        scratchpad_windows = [w for w in tree.descendants()
                            if "scratchpad:nixos" in w.marks]

        assert len(scratchpad_windows) == 1, "Scratchpad terminal not restored"
        restored_window = scratchpad_windows[0]

        # Verify it's the same window (same PID)
        assert restored_window.pid == window.pid, "Different terminal process (should be same)"
```

## Technology Stack Summary

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Daemon Core** | Python 3.11+, asyncio | Matches existing i3pm daemon, async i3 IPC |
| **IPC Client** | i3ipc.aio | Async Sway IPC, event subscriptions |
| **State Management** | In-memory dict, Pydantic models | Ephemeral state, validated types |
| **CLI Frontend** | TypeScript/Deno | Matches i3pm CLI, fast startup |
| **Terminal Emulator** | Alacritty | Project standard, supports --working-directory |
| **Testing Framework** | pytest + pytest-asyncio | Python async testing standard |
| **UI Automation** | ydotool | Wayland keyboard input simulation |
| **State Verification** | Sway IPC GET_TREE/GET_MARKS | Authoritative window state |
| **Configuration** | NixOS modules | Declarative keybinding configuration |

## Open Questions

**Q1**: Should scratchpad terminals be automatically hidden when switching projects?
**A1**: No - keep terminals hidden in scratchpad, only show on explicit keybinding. Matches spec FR-010 "remain in scratchpad (not visible)".

**Q2**: How to handle global mode scratchpad terminal (no active project)?
**A2**: Use project name "global", working directory = home directory. Persists across all project switches.

**Q3**: Should terminal dimensions be configurable?
**A3**: Start with hardcoded 1400x850 per spec FR-002. Future enhancement: make configurable via daemon config file.

**Q4**: How to handle terminal already visible when toggle called?
**A4**: Hide to scratchpad (inverse operation). Keybinding is toggle, not separate show/hide.

## Implementation Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Window event timing (terminal launch → marking) | Medium | Add 100ms delay after window creation, retry marking up to 3 times |
| Process environment reading permission denied | Low | Already working for existing i3pm features, same pattern |
| Scratchpad conflicts with existing project filtering | Medium | Use distinct marks (`scratchpad:` prefix), separate from project marks |
| Terminal fails to launch (missing Alacritty) | Low | Validate Alacritty available at daemon startup, fail-fast with clear error |
| Daemon state desync from Sway IPC | Medium | Always validate via Sway IPC before operations, event-driven updates |

## Next Steps (Phase 1)

1. Generate `data-model.md` with detailed entity schemas (ScratchpadTerminal, ScratchpadManager state)
2. Create JSON-RPC contract in `contracts/scratchpad-rpc.json` (toggle, launch, status methods)
3. Generate `quickstart.md` with user-facing commands and workflows
4. Update `.claude_code/context.md` with scratchpad architecture patterns
