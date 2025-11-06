# Critical Analysis: Window Matching - i3run vs Our I3PM Environment System

**Date**: 2025-01-06
**Context**: Evaluating i3run's multi-criteria window matching against our superior I3PM_* environment variable injection system

## TL;DR

**Recommendation**: **DO NOT adopt i3run's multi-criteria matching**. Our environment variable system is objectively superior for window identification. Focus spec on Run-Raise-Hide UX patterns and scratchpad management, not window matching.

---

## Our Current System (Feature 057/058)

### Architecture

```
Application Launch (via Sway exec)
  ↓
app-launcher-wrapper.sh injects I3PM_* environment variables
  ├→ I3PM_APP_NAME: Application identifier (e.g., "firefox", "vscode")
  ├→ I3PM_APP_ID: Unique instance ID (app-project-pid-timestamp)
  ├→ I3PM_PROJECT_NAME: Associated project (if scoped)
  ├→ I3PM_SCOPE: "global" or "scoped"
  ├→ I3PM_TARGET_WORKSPACE: Preferred workspace number
  └→ I3PM_EXPECTED_CLASS: Expected window class
  ↓
Process launches with environment inherited
  ↓
Window appears in Sway
  ↓
Daemon queries /proc/<pid>/environ via window_environment.py
  ├→ Reads I3PM_* variables directly from process
  ├→ Traverses up to 3 parent processes (wrapper scripts)
  ├→ 100% deterministic matching
  └→ Query time: <5ms average
  ↓
window_matcher.py matches window to application
  ├→ Direct lookup via I3PM_APP_NAME
  ├→ Unique identification via I3PM_APP_ID
  └→ Project association via I3PM_PROJECT_NAME
```

### Key Advantages

1. **100% Deterministic**: No fuzzy matching, no heuristics, no ambiguity
2. **Launch-time Injection**: Variables set at launch, immutable
3. **Multi-instance Native**: Each instance has unique I3PM_APP_ID
4. **Project-aware**: Built-in I3PM_PROJECT_NAME for filtering
5. **Fast Queries**: /proc read is <5ms, cached in memory
6. **Works with ALL apps**: Including PWAs, Electron, terminals, GUI apps
7. **No window property dependencies**: Doesn't break if class/title changes
8. **Scriptable**: Environment variables visible to window_env tool

### Coverage (from startup_validation.py)

- **Target**: 100% of windows have I3PM_* variables
- **Validation**: Startup check logs coverage report
- **Reality**: ~95-98% coverage (some system windows excluded)

---

## i3run's Approach

### Multi-Criteria Matching

i3run identifies windows by:
- **class**: X11 window class (WM_CLASS property)
- **instance**: X11 instance name (second part of WM_CLASS)
- **title**: Window title (dynamic, changes frequently)
- **conid**: Sway container ID (transient, changes on restart)
- **winid**: X11 window ID (not applicable to Wayland)

### Matching Logic

```bash
# i3run lines 113-116
for k in instance class title conid winid; do
  [[ ${_o[$k]} ]] || continue
  _criteria+=(--$k "${_o[$k]}")
done
```

All criteria use AND logic - window must match ALL specified criteria.

### Problems with This Approach

1. **Non-Deterministic**:
   - Window class can vary by launch method (firefox vs Firefox)
   - Title changes dynamically (document name, tab title)
   - Instance not set by all applications
   - No way to identify specific instance of multi-instance apps

2. **Launch-time Race Conditions**:
   - Must wait for window to appear before checking properties
   - Window may appear before properties fully set
   - i3run has complex timeout/retry logic (lines 742-794)

3. **PWA Problem**:
   - PWAs launched via Firefox have class "firefox"
   - Cannot distinguish YouTube PWA from Claude PWA
   - i3run cannot solve this without external state

4. **Multi-Instance Ambiguity**:
   - Two VS Code windows have identical class="Code"
   - Two terminals have identical class="Alacritty"
   - i3run's solution: --rename with xdotool (doesn't work on Wayland!)

5. **Configuration Burden**:
   - User must manually specify class, instance, title for each app
   - Must update config if app changes window properties
   - No automatic project association

---

## i3king's Approach (Window Rules)

### Architecture

i3king is a daemon that:
- Listens to i3 IPC window:new events
- Matches windows against rules file (`~/.config/i3king/rules`)
- Executes i3-msg commands when rules match

### Rule Syntax

```ini
[class=Firefox instance=Navigator title=.*YouTube.*]
move to workspace 2; floating enable
```

### Advantages Over Native Sway Rules

1. **Dynamic reloading**: Can update rules without compositor restart
2. **GLOBAL/DEFAULT rules**: Match any window with exclusions
3. **ON_CLOSE rules**: Execute commands when windows close
4. **TITLE rules**: Dynamic title formatting with regex
5. **Auto-restart**: Reapplies rules if IPC socket reconnects

### Comparison to Our System

| Feature | i3king | Our Sway Dynamic Config (Feature 047) |
|---------|--------|---------------------------------------|
| Hot-reload rules | ✅ Yes | ✅ Yes (window-rules.json) |
| Git versioning | ❌ No | ✅ Yes (auto-commit) |
| Validation | ❌ No | ✅ Yes (syntax/semantic) |
| Window matching | Window properties | **I3PM_* environment** |
| Multi-instance support | ❌ No | ✅ Yes (unique APP_ID) |
| Project awareness | ❌ No | ✅ Yes (I3PM_PROJECT_NAME) |
| Rule format | Custom INI | JSON (machine-readable) |
| Integration | External daemon | Native daemon (i3pm) |

**Verdict**: i3king's hot-reload capability is **already implemented** in Feature 047 (Sway Dynamic Configuration Management), and our version has superior matching via environment variables.

---

## What i3run DOES Offer That We Should Adopt

### 1. Run-Raise-Hide State Machine ✅ ADOPT

**Value**: Excellent UX pattern for single-keybinding application toggle

```
State                           | Action
--------------------------------|------------------
Not found                       | Launch with command
On different workspace          | Switch to workspace + focus
On current workspace, unfocused | Focus window
On current workspace, focused   | Hide to scratchpad
Hidden in scratchpad            | Show on current workspace
```

**Implementation**: State machine in daemon or CLI command, uses Sway IPC queries for state detection

**Why we need this**: Currently we have separate commands for launch/focus/hide. Single toggle command is more ergonomic.

### 2. Summon Mode ✅ ADOPT

**Value**: Bring window to current workspace instead of switching workspace

```bash
# Current behavior (switch workspace)
i3pm launch firefox  # → switches to workspace 3 where firefox is running

# Summon mode (move window)
i3pm launch firefox --summon  # → brings firefox to current workspace
```

**Implementation**: Simple Sway IPC command change:
- Current: `workspace <ws>; focus`
- Summon: `[con_id=<id>] move to workspace current; focus`

**Why we need this**: Multi-workspace workflows benefit from bringing windows rather than switching

### 3. Scratchpad State Preservation ✅ ADOPT

**Value**: Remember floating state before hiding, restore when showing

i3run implementation (lines 706-724):
```bash
# Hide to scratchpad
i3var set "hidden${conid}" "${floating_state}"  # Save state
[con_id=$conid] floating enable, move scratchpad

# Show from scratchpad
floating_state=$(i3var get "hidden${conid}")
[con_id=$conid] scratchpad show
[con_id=$conid] floating ${floating_state}  # Restore state
i3var set "hidden${conid}"  # Clear variable
```

**Implementation**: Store `{conid: {floating: bool, geometry: {x, y, w, h}}}` in daemon memory

**Why we need this**: Scratchpad terminal (Feature 062) already does this, but we should generalize for all apps

### 4. Force-Launch Mode ✅ ADOPT (Limited)

**Value**: Launch new instance even if window exists

```bash
i3pm launch alacritty           # → focuses existing terminal
i3pm launch alacritty --force   # → launches new terminal
```

**Implementation**: Skip window lookup, always execute launch command

**Why we need this**: Useful for multi-instance apps (terminals, browsers, VS Code)

**Note**: We already support this via unique I3PM_APP_ID, but need explicit flag

### 5. Mouse-Relative Positioning ❓ MAYBE ADOPT

**Value**: Position floating windows near cursor (ergonomic for mouse users)

i3run implementation (lines 825-860):
- Get cursor position via xdotool
- Calculate window position (cursor - window_size/2)
- Adjust if window would extend off-screen (respect gap margins)
- Execute: `[con_id=$id] move absolute position $x $y`

**Implementation**: Query cursor via `swaymsg -t get_inputs` (input device state)

**Why uncertain**:
- Adds complexity (cursor queries, geometry calculations)
- Only useful for floating windows
- Keyboard-driven users don't benefit
- Gap margin configuration (I3RUN_*_GAP env vars) is another config layer

**Recommendation**: Defer to later phase or separate feature

---

## What i3run Does NOT Offer That We Already Have

### 1. Launch Notification (Feature 041)

**Our advantage**: Pre-launch notification to daemon enables Tier 0 correlation

i3run: Launches app, waits for window to appear, then matches by criteria (race conditions)

Our system: Daemon knows launch is coming, correlates window on appearance

### 2. Project-Scoped Filtering (Feature 037)

**Our advantage**: I3PM_PROJECT_NAME enables automatic window visibility control

i3run: No concept of project scope or context-aware window management

Our system: Windows automatically hide/show based on active project

### 3. Multi-Instance Tracking

**Our advantage**: I3PM_APP_ID provides unique identifier for each instance

i3run: Cannot reliably track multiple instances of same application

Our system: Each instance has unique ID, enabling independent management

### 4. Startup Validation

**Our advantage**: Daemon validates all windows have I3PM_* variables at startup

i3run: No coverage validation or quality assurance

Our system: Logs coverage report, warns about missing environment

---

## Revised Feature Scope

### Core Features to Implement

1. **Run-Raise-Hide State Machine** (Priority: P1)
   - Single command intelligently handles: launch/focus/hide/show
   - Uses existing I3PM_* environment for window identification
   - No multi-criteria matching needed

2. **Summon Mode** (Priority: P1)
   - Option to move window to current workspace vs switching workspace
   - Simple flag: `--summon` or `--goto` (default)

3. **Scratchpad State Preservation** (Priority: P2)
   - Generalize Feature 062's scratchpad logic to all applications
   - Store: {conid: {floating: bool, geometry: {x, y, w, h}}}
   - Restore on show

4. **Force-Launch Flag** (Priority: P2)
   - Explicit flag to launch new instance: `--force`
   - Skips window lookup, always executes command

5. **CLI Interface** (Priority: P1)
   - New command: `i3pm run <app-name>` or `i3pm launch <app-name>`
   - Flags: `--summon`, `--force`, `--hide`, `--nohide`
   - Uses existing registry for app configuration

### Features to REJECT

1. **Multi-Criteria Window Matching** ❌
   - Reason: I3PM_* environment variables are superior
   - Our system: 100% deterministic, fast, project-aware
   - i3run: Non-deterministic, slow, configuration burden

2. **Window Property Matching** ❌
   - Reason: Already solved by environment injection
   - i3run uses class/instance/title (fragile, ambiguous)
   - We use I3PM_APP_NAME/I3PM_APP_ID (deterministic, unique)

3. **Window Renaming** ❌
   - Reason: Incompatible with Wayland, unnecessary with our system
   - i3run uses xdotool to modify WM_CLASS (X11-only)
   - We set unique I3PM_APP_ID at launch (works on Wayland)

4. **External Rule Files** ❌
   - Reason: Already have Feature 047 (dynamic config) + application registry
   - i3king uses custom INI format
   - We use JSON with validation + Git versioning

### Features to DEFER

1. **Mouse-Relative Positioning** (Priority: P3 or separate feature)
   - Reason: Niche use case, adds complexity
   - Consider for future enhancement
   - Requires cursor query + geometry calculations

---

## Updated Functional Requirements

Reduce from 38 requirements to ~15-20 focused requirements:

### Core Application Control

- **FR-001**: System MUST support Run-Raise-Hide pattern (5-state machine)
- **FR-002**: System MUST use existing I3PM_* environment variables for window identification (NO multi-criteria matching)
- **FR-003**: System MUST integrate with existing app-launcher-wrapper.sh for launching
- **FR-004**: System MUST query daemon for window state via IPC

### Workspace Behavior

- **FR-005**: System MUST support goto mode (switch to window's workspace) as default
- **FR-006**: System MUST support summon mode (move window to current workspace) via flag
- **FR-007**: System MUST preserve window properties (floating, geometry) when moving between workspaces

### Scratchpad Management

- **FR-008**: System MUST preserve window floating state when hiding to scratchpad
- **FR-009**: System MUST preserve window geometry when hiding to scratchpad
- **FR-010**: System MUST restore original state when showing from scratchpad
- **FR-011**: System MUST support explicit hide/nohide flags to override smart toggle

### Multi-Instance Support

- **FR-012**: System MUST support force-launch flag to create new instance
- **FR-013**: System MUST use existing I3PM_APP_ID for instance differentiation (no new mechanism needed)

### CLI Interface

- **FR-014**: System MUST provide `i3pm run <app-name>` command accepting flags: --summon, --force, --hide, --nohide
- **FR-015**: System MUST return container ID on success (for scripting)

### Error Handling

- **FR-016**: System MUST handle launch failures gracefully (command not found, timeout)
- **FR-017**: System MUST handle missing window gracefully (window closed before operation)

---

## Implementation Strategy

### Phase 1: Core State Machine (P1)

1. Add `i3pm run <app-name>` command to CLI
2. Implement 5-state detection:
   - Query Sway tree for window by I3PM_APP_NAME
   - Check workspace, focus, scratchpad state
3. Implement state transitions:
   - Not found → launch via app-launcher-wrapper.sh
   - Different WS → switch workspace + focus
   - Same WS unfocused → focus
   - Same WS focused → hide to scratchpad
   - Scratchpad → show on current workspace

### Phase 2: Summon Mode (P1)

1. Add `--summon` flag to CLI
2. Modify state transition for "different WS":
   - Default: `workspace <ws>; [con_id=<id>] focus`
   - Summon: `[con_id=<id>] move to workspace current; focus`

### Phase 3: Scratchpad State Preservation (P2)

1. Add state storage to daemon:
   - `scratchpad_state: Dict[int, WindowState]`
   - `WindowState = {floating: bool, geometry: {x, y, w, h}}`
2. Store state before hiding:
   - Query window rect via Sway IPC
   - Save to `scratchpad_state[conid]`
3. Restore state after showing:
   - Retrieve from `scratchpad_state[conid]`
   - Apply: `[con_id=<id>] floating <enable|disable>; move absolute position <x> <y>; resize set <w> <h>`
   - Clear from storage

### Phase 4: Force-Launch (P2)

1. Add `--force` flag to CLI
2. Skip window lookup, always execute launch command
3. Use existing I3PM_APP_ID for instance differentiation

---

## Conclusion

**i3run's multi-criteria window matching is OBSOLETE** given our I3PM_* environment variable system. We have objectively superior window identification.

**What we SHOULD adopt from i3run**:
1. ✅ Run-Raise-Hide UX pattern (5-state machine)
2. ✅ Summon mode (move vs switch workspace)
3. ✅ Scratchpad state preservation (floating, geometry)
4. ✅ Force-launch flag (multi-instance)

**What we should REJECT**:
1. ❌ Multi-criteria matching (class/instance/title/conid/winid)
2. ❌ Window renaming (xdotool-based, Wayland-incompatible)
3. ❌ External rule files (we have Feature 047 + registry)

**Result**: Simpler, cleaner feature focused on UX improvements, not window matching reinvention.
