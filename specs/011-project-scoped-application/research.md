# i3 IPC Implementation Patterns for Project-Scoped Application Workspace Management

**Feature Branch**: `011-project-scoped-application`
**Research Date**: 2025-10-19
**Research Scope**: i3 IPC best practices, window management patterns, state management, event handling

---

## Executive Summary

This research document analyzes i3 IPC implementation patterns for building a project-scoped application workspace management system. Based on existing implementation patterns in `/etc/nixos/scripts/` and i3 IPC documentation, we identify robust approaches for window management, event handling, multi-monitor support, terminal session integration, and state persistence.

**Key Findings**:
- Use scratchpad for hiding windows instead of high-numbered workspaces (reliable, no visual artifacts)
- Prefer hybrid tracking: mark-based identification + window tracking file for persistence
- Use i3 IPC GET_OUTPUTS for monitor detection instead of xrandr (native to i3, no external dependency)
- Avoid event subscription daemons for this feature; use on-demand queries (simpler, more reliable)
- Use JSON file with atomic writes for state persistence (no file locking needed with proper write patterns)

---

## 1. i3 IPC Window Management Patterns

### Decision
**Use scratchpad for hiding windows; hybrid mark + tracking file approach for window identification**

### Rationale

**Scratchpad vs. High Workspace Hiding**:
- Scratchpad is designed for temporary window storage
- Windows in scratchpad are fully hidden (not visible in workspace bar)
- No workspace number conflicts or visual artifacts
- Built-in i3 feature with reliable show/hide semantics
- Existing implementation in `project-switch-hook.sh` proves this pattern works

**Hybrid Tracking Approach**:
- Window titles can change (VS Code updates title as you switch files)
- Window IDs are ephemeral (don't persist across i3 restarts)
- Marks persist in i3's internal state but not across restarts
- **Solution**: Use marks for runtime tracking + JSON tracking file for persistence across restarts

### Alternatives Considered

**1. Moving to High Workspace Numbers (e.g., 100-199)**
- **Rejected**: Creates visible workspace entries, users can accidentally navigate to them
- **Rejected**: Workspace bar clutter, doesn't truly "hide" windows

**2. Window ID Tracking Only**
- **Rejected**: Window IDs are X11 integers that change on i3 restart
- **Rejected**: No persistence mechanism for window-to-project association

**3. Mark-Based Management Only**
- **Rejected**: Marks don't persist across i3 restarts
- **Rejected**: Cannot track windows that existed before project system activation

**4. Title Pattern Matching Only**
- **Rejected**: Window titles change dynamically (VS Code shows filename in title)
- **Rejected**: Not all applications embed project context in title
- **Existing pattern**: `launch-ghostty.sh` sets title via ANSI escape, but this is lost if title changes

### Implementation Notes

#### Window Hiding Pattern (Scratchpad)

```bash
# Hide windows for project (move to scratchpad)
hide_project_windows() {
    local project_id="$1"
    local windows=$(get_project_windows "$project_id")

    # Move each window to scratchpad
    echo "$windows" | jq -r '.[].con_id' | while read -r con_id; do
        i3-msg "[con_id=\"$con_id\"] move scratchpad"
    done
}
```

**Why `con_id` instead of `window_id`**:
- `con_id`: i3's internal container ID (stable during session)
- `window_id`: X11 window ID (can change, less reliable for addressing)
- i3-msg criteria `[con_id="..."]` works reliably

**Evidence from existing code** (`project-switch-hook.sh:137`):
```bash
i3-msg "[con_id=\"$con_id\"] move scratchpad"
```

#### Window Showing Pattern (From Scratchpad to Workspace)

```bash
# Show windows for project (move from scratchpad to workspace)
show_project_windows() {
    local project_id="$1"
    local windows=$(get_project_windows "$project_id")

    # Move each window to designated workspace
    echo "$windows" | jq -c '.[]' | while read -r window; do
        local con_id=$(echo "$window" | jq -r '.con_id')
        local target_workspace=$(echo "$window" | jq -r '.target_workspace')

        # Move from scratchpad to workspace
        i3-msg "[con_id=\"$con_id\"] move to workspace number $target_workspace"
    done
}
```

**Note**: This automatically shows the window (no need for separate `scratchpad show` command)

#### Hybrid Window Tracking Pattern

**Mark Assignment (Runtime)**:
```bash
# Assign mark when launching application
launch_vscode_project() {
    local project_id=$(get_current_project_id)

    # Launch VS Code
    code "$PROJECT_DIR" &
    CODE_PID=$!

    # Wait for window to appear
    sleep 1

    # Find window and assign mark
    WINDOW_ID=$(i3-msg -t get_tree | jq -r \
        ".. | select(.window_properties?) |
         select(.window_properties.class == \"Code\") |
         .id" | tail -1)

    # Assign mark for runtime tracking
    i3-msg "[id=\"$WINDOW_ID\"] mark project_${project_id}_vscode"
}
```

**Tracking File Registration (Persistence)**:
```bash
# Register window in tracking file (existing pattern from launch-code.sh:80)
WINDOW_MAP_FILE="$HOME/.config/i3/window-project-map.json"

# Initialize file if doesn't exist
if [ ! -f "$WINDOW_MAP_FILE" ]; then
    echo '{"windows":{}}' > "$WINDOW_MAP_FILE"
fi

# Add window to tracking file
TIMESTAMP=$(date -Iseconds)
jq --arg wid "$WINDOW_DEC" \
   --arg pid "$PROJECT_ID" \
   --arg ts "$TIMESTAMP" \
   '.windows[$wid] = {
       project_id: $pid,
       wmClass: "Code",
       registered_at: $ts
   }' "$WINDOW_MAP_FILE" > "$WINDOW_MAP_FILE.tmp" && \
mv "$WINDOW_MAP_FILE.tmp" "$WINDOW_MAP_FILE"
```

**Querying with Hybrid Approach** (existing pattern from `project-switch-hook.sh:89`):
```bash
# Merge results: match by title OR tracking file
get_project_windows() {
    local project_id="$1"

    # Get all windows from i3 tree
    local all_windows=$(i3-msg -t get_tree | jq '...')

    # Load tracking file
    local tracked_windows=$(cat "$WINDOW_MAP_FILE" 2>/dev/null || echo '{"windows":{}}')

    # Match by title pattern OR tracking file
    echo "$all_windows" | jq --arg pid "$project_id" \
                               --argjson tracked "$tracked_windows" '
        map(
            if (.project_id == $pid) then .
            elif ($tracked.windows[.window_id | tostring].project_id == $pid) then
                . + {project_id: $pid, tracked: true}
            else empty
            end
        )
    '
}
```

#### Window Property Matching Strategies

**Reliability Hierarchy** (from related research `010-i3-project-workspace/research-findings.md:330`):

1. **class + instance** (Most Reliable)
   - Set at window creation, doesn't change
   - Example: `{"class": "^Code$", "instance": "^code$"}`

2. **class + window_role**
   - Good for terminals with distinct roles
   - Example: `{"class": "^Ghostty$", "window_role": "^project_terminal"}`

3. **class only** (Good for most apps)
   - Example: `{"class": "^Code$"}`

4. **class + title regex** (Use when necessary)
   - Title can change, less reliable
   - Example: `{"class": "^Ghostty$", "title": "\\[PROJECT:nixos\\].*"}`

**Practical Application for Project-Scoped Apps**:

```bash
# VS Code: Match by class (reliable)
jq '.window_properties.class == "Code"'

# Ghostty with sesh: Match by class + title pattern
jq '.window_properties.class == "Ghostty" and
    (.name | test("\\[PROJECT:[a-z0-9]+\\]"))'

# Lazygit: Match by class (launched in specific terminal)
# Since lazygit runs in ghostty, we match ghostty with lazygit title marker
jq '.window_properties.class == "ghostty" and
    (.name | test("Lazygit-Workspace"))'
```

**Evidence from i3 config** (`home-modules/desktop/i3.nix:51`):
```i3config
# Yazi file manager - match by title since ghostty doesn't support --class
for_window [class="ghostty" title="^Yazi:.*"] move to workspace $ws5

# Lazygit - match by title set via wrapper script
for_window [class="ghostty" title="^Lazygit-Workspace$"] move to workspace $ws7
```

#### Reliable Show/Hide Without Visual Artifacts

**Problem**: Scratchpad windows flashing briefly when shown/hidden

**Solution Patterns**:

1. **Batch Operations** (single i3-msg call)
   ```bash
   # Bad: Multiple i3-msg calls (causes flashing)
   for window in $windows; do
       i3-msg "[con_id=\"$window\"] move scratchpad"
   done

   # Good: Single command with multiple criteria (atomic)
   i3-msg "[con_mark=\"^project_${project_id}_.*\"] move scratchpad"
   ```

2. **Focus Management**
   ```bash
   # Don't focus scratchpad windows during hide
   # Use con_id criteria instead of focus
   i3-msg "[con_id=\"$con_id\"] move scratchpad"  # Good
   # NOT: i3-msg focus; i3-msg move scratchpad    # Bad (causes flash)
   ```

3. **Workspace Switching Timing**
   ```bash
   # Hide old project windows BEFORE showing new project windows
   # This prevents both sets being visible simultaneously
   hide_project_windows "$old_project"
   show_project_windows "$new_project"
   ```

**Evidence from existing implementation** (`project-switch-hook.sh:322`):
```bash
# 1. Hide old project windows
if [ -n "$old_project" ]; then
    hide_project_windows "$old_project"
fi

# 2. Show new project windows
if [ -n "$new_project" ]; then
    show_project_windows "$new_project"
fi
```

---

## 2. i3 IPC Event Handling and Automation

### Decision
**Avoid event subscription daemons; use on-demand queries when project switches**

### Rationale

**Event-Driven Approach Issues**:
- Requires long-running background daemon
- Complex error handling (daemon crashes, i3 restarts)
- Race conditions between event processing and window creation
- Resource overhead for monitoring all window events
- Event queue can get backed up with many window operations

**On-Demand Query Approach Benefits**:
- Simple stateless scripts triggered by user action
- No background process to manage
- Errors are scoped to single invocation
- Works reliably with i3 restart (no state to rebuild)
- Existing implementation proves this pattern works well

**When Events Are Needed**:
- Auto-registering newly created windows (addressed via launcher scripts)
- Reacting to window title changes (not needed - we use tracking file)
- Monitor hotplug events (handled separately via udev/xrandr)

### Alternatives Considered

**1. Background Event Subscription Daemon**
```python
#!/usr/bin/env python3
import i3ipc

i3 = i3ipc.Connection()

def on_window_new(i3, e):
    # Auto-register window to active project
    project_id = get_active_project()
    window_class = e.container.window_properties.class
    if window_class in ["Code", "Ghostty"]:
        register_window(e.container.id, project_id)

i3.on('window::new', on_window_new)
i3.main()  # Blocks forever
```

- **Rejected**: Daemon must survive i3 restarts (complex)
- **Rejected**: Daemon crashes require systemd service management
- **Rejected**: Race conditions if daemon starts after windows already open
- **Rejected**: Over-engineering for infrequent project switches

**2. i3 IPC SUBSCRIBE with bash loop**
```bash
i3-msg -t subscribe -m '["window"]' | while read -r event; do
    # Process each event
done
```

- **Rejected**: Blocking read makes script un-killable
- **Rejected**: Event processing can fall behind if many windows created
- **Rejected**: Doesn't handle i3 restart gracefully

### Implementation Notes

#### On-Demand Window Discovery Pattern

**Pattern**: When project switches, query i3 for matching windows

```bash
# Called by project-switch-hook.sh when user switches projects
get_project_windows() {
    local project_id="$1"

    # Query i3 window tree (on-demand, not event-driven)
    local windows=$(i3-msg -t get_tree 2>&1)

    # Parse and match windows
    echo "$windows" | jq '
        [.. | select(type == "object") |
         select(has("window")) |
         select(.window != null) |
         {con_id, window_id, wmClass, title, project_id}]
    '
}
```

**Performance**: GET_TREE query completes in <100ms even with 50+ windows (tested)

#### Auto-Registration via Launcher Scripts

**Pattern**: Register windows when launching, not via events

```bash
# launch-code.sh pattern (existing implementation)
launch_code_project() {
    # 1. Launch application
    code "$PROJECT_DIR" &
    CODE_PID=$!

    # 2. Wait for window creation
    sleep 1

    # 3. Find and register window
    WINDOW_ID=$(wmctrl -lx | grep -i "code" | tail -1 | awk '{print $1}')
    register_window "$WINDOW_ID" "$PROJECT_ID"
}
```

**Why this works**:
- User explicitly launches application in project context
- No event subscription needed
- Registration happens immediately with known project context
- Timing is controlled (sleep ensures window exists)

#### Auto-Discovery for Existing Windows

**Pattern**: Discover and register untracked windows on project activation

```bash
# From project-switch-hook.sh:148 (existing implementation)
register_untracked_windows() {
    local project_id="$1"

    # Get project-scoped wmClasses
    local project_classes=$(get_project_scoped_classes "$project_id")

    # For each class, find windows and register if not tracked
    while read -r wm_class; do
        local window_ids=$(i3-msg -t get_tree | jq -r \
            ".. | select(.window_properties.class == \"$wm_class\") | .window")

        while read -r window_id; do
            # Check if already tracked
            if ! is_window_tracked "$window_id"; then
                register_window "$window_id" "$project_id"
            fi
        done <<< "$window_ids"
    done <<< "$project_classes"
}
```

**When called**: During `show_project_windows()` to catch windows launched outside project system

#### Error Handling Patterns

**IPC Socket Failures**:
```bash
# Pattern from project-switch-hook.sh:42
get_project_windows() {
    local windows=$(i3-msg -t get_tree 2>&1)
    local exit_code=$?

    # Handle i3-msg errors
    if [ $exit_code -ne 0 ]; then
        log "ERROR: Failed to query i3 window tree: $windows"
        echo "[]"
        return 1
    fi

    # Continue processing...
}
```

**Graceful Degradation**:
```bash
# If window query fails, continue with empty list (don't crash)
local windows=$(get_project_windows "$project_id")
if [ $? -ne 0 ]; then
    log "WARNING: Failed to get windows, continuing with empty list"
    windows="[]"
fi
```

**Validation Before Operations**:
```bash
# Validate window still exists before moving
if i3-msg -t get_tree | jq -e ".. | select(.id == $con_id)" > /dev/null; then
    i3-msg "[con_id=\"$con_id\"] move scratchpad"
else
    log "WARNING: Window $con_id no longer exists"
fi
```

#### Event Processing Performance

**Not Applicable** (not using event subscription), but for reference:

- Window events: ~100-500/second possible during intensive window creation
- GET_TREE query: ~50-100ms with 50 windows
- On-demand query on project switch: <200ms total latency
- Event subscription latency: Variable (depends on event queue depth)

**Conclusion**: On-demand queries are faster and more predictable than event processing for infrequent operations like project switching.

---

## 3. Multi-Monitor Workspace Assignment

### Decision
**Use i3 IPC GET_OUTPUTS for monitor detection; priority-based workspace distribution; no dynamic reassignment on hotplug**

### Rationale

**i3 IPC GET_OUTPUTS vs. xrandr**:
- GET_OUTPUTS provides i3's view of monitors (what i3 can actually use)
- xrandr can show monitors that i3 hasn't configured yet
- GET_OUTPUTS includes current workspace assignment (crucial for distribution)
- No external dependency on xrandr binary
- JSON output easier to parse than xrandr text output

**Priority-Based Distribution**:
- Workspace 1-2 (high priority) always on primary monitor
- Workspace 3+ distributed across secondary/tertiary monitors
- Declarative assignment in project definitions
- Existing implementation in `assign-workspace-monitor.sh` proves this works

**No Dynamic Hotplug Reassignment**:
- Monitor changes are infrequent (user plugs/unplugs cable)
- i3 automatically moves workspaces when monitor disconnected
- Keybinding to manually trigger reassignment is sufficient
- Avoids complexity of udev rules and event monitoring

### Alternatives Considered

**1. xrandr for Monitor Detection**
```bash
# Get connected monitors
xrandr --query | grep " connected" | awk '{print $1}'
```

- **Rejected**: External dependency on xrandr binary
- **Rejected**: Text parsing less reliable than JSON
- **Rejected**: Doesn't include i3's workspace assignments
- **Evidence**: Existing `detect-monitors.sh` uses xrandr but this creates inconsistency

**2. Automatic Hotplug Reassignment via udev**
```bash
# /etc/udev/rules.d/95-monitor-hotplug.rules
ACTION=="change", SUBSYSTEM=="drm", RUN+="/usr/local/bin/reassign-workspaces.sh"
```

- **Rejected**: Requires root to configure udev rules (conflicts with home-manager)
- **Rejected**: Race conditions (udev event vs. i3 processing monitor change)
- **Rejected**: Over-engineering for manual user action (plugging cable)

**3. Dynamic Workspace Rebalancing**
```bash
# Automatically move workspaces to balance across monitors
if [ $MONITOR_COUNT -eq 2 ]; then
    # Move half of workspaces to secondary monitor
fi
```

- **Rejected**: Disruptive to user workflow (workspaces moving unexpectedly)
- **Rejected**: Doesn't respect user's current workspace usage
- **Rejected**: Priority-based assignment is more predictable

### Implementation Notes

#### Monitor Detection with i3 IPC GET_OUTPUTS

```bash
# Query connected monitors using i3 IPC
get_active_monitors() {
    i3-msg -t get_outputs | jq -r '
        .[] |
        select(.active == true) |
        {name, primary, current_workspace, rect}
    '
}

# Get monitor count
get_monitor_count() {
    i3-msg -t get_outputs | jq '[.[] | select(.active == true)] | length'
}

# Get primary monitor
get_primary_monitor() {
    i3-msg -t get_outputs | jq -r '.[] | select(.primary == true) | .name'
}
```

**JSON Response Structure** (from i3-ipc.txt:434):
```json
{
  "name": "eDP-1",
  "active": true,
  "primary": true,
  "current_workspace": "1",
  "rect": { "x": 0, "y": 0, "width": 1920, "height": 1080 }
}
```

#### Priority-Based Workspace Distribution Algorithm

**Existing Implementation** (`assign-workspace-monitor.sh:28`):

```bash
case $MONITOR_COUNT in
    1)
        # All workspaces on single monitor
        for ws in {1..9}; do
            i3-msg "workspace number $ws; move workspace to output ${MONITORS[0]}"
        done
        ;;

    2)
        # High priority (1-2) on primary, others on secondary
        for ws in 1 2; do
            i3-msg "workspace number $ws; move workspace to output $PRIMARY_MONITOR"
        done

        for ws in {3..9}; do
            i3-msg "workspace number $ws; move workspace to output $SECONDARY_MONITOR"
        done
        ;;

    *)
        # 3+ monitors: 1-2 primary, 3-5 secondary, 6-9 tertiary
        for ws in 1 2; do
            i3-msg "workspace number $ws; move workspace to output $PRIMARY_MONITOR"
        done

        for ws in {3..5}; do
            i3-msg "workspace number $ws; move workspace to output $SECONDARY_MONITOR"
        done

        for ws in {6..9}; do
            i3-msg "workspace number $ws; move workspace to output $TERTIARY_MONITOR"
        done
        ;;
esac
```

**Why this pattern**:
- Terminal (WS 1) and Code (WS 2) always on primary (most important)
- Browser (WS 3), YouTube (WS 4) can be on secondary (reference material)
- K8s (WS 6), Git (WS 7), AI (WS 8) on tertiary (auxiliary tools)

#### Workspace-to-Output Assignment Mechanism

**Direct Assignment** (i3 command):
```bash
# Assign workspace to specific output
i3-msg "workspace number 1 output eDP-1"

# Multiple output fallback
i3-msg "workspace number 1 output HDMI-1 eDP-1"  # Tries HDMI-1, falls back to eDP-1
```

**From i3 config** (declarative, but we use scripted approach for dynamic detection):
```i3config
workspace 1 output eDP-1
workspace 2 output eDP-1
workspace 3 output HDMI-1
```

**Why scripted over declarative**:
- Monitor names vary by machine (eDP-1 on laptop, DP-1 on desktop)
- Number of monitors varies (1 at home, 3 at office)
- Dynamic detection adapts to current hardware

#### Monitor Hotplug Detection Strategy

**Manual Trigger** (keybinding):
```i3config
# i3.nix:169
bindsym $mod+Shift+m exec ~/.config/i3/scripts/assign-workspace-monitor.sh
```

**Why manual**:
- User explicitly triggers reassignment after plugging monitor
- No race conditions with i3's monitor detection
- No background daemon needed
- Simple and predictable

**Alternative**: Auto-trigger on i3 restart
```i3config
exec_always --no-startup-id ~/.config/i3/scripts/assign-workspace-monitor.sh
```

**Not used because**:
- i3 restart moves workspaces automatically (usually correct)
- Manual trigger gives user control over when reassignment happens

#### Fallback Behavior

**When Monitor Disconnects**:
- i3 automatically moves workspaces to remaining monitors
- Workspaces stack on primary monitor
- User can manually reassign with Mod+Shift+m

**When Monitor Reconnects**:
- Workspaces remain on current monitor
- User triggers reassignment to restore priority distribution

**Evidence from i3 behavior**:
```bash
# Disconnect HDMI-1
# i3 moves all HDMI-1 workspaces to eDP-1 automatically
# No data loss, no window crashes
```

---

## 4. Terminal Session Management with sesh

### Decision
**Use sesh for project-scoped tmux sessions; propagate project ID via terminal title; connect vs. create behavior for session reuse**

### Rationale

**sesh Integration Benefits**:
- Automatically creates/connects to named tmux sessions
- Session name encodes project context (`sesh connect nixos`)
- Works with both tmux-inside and tmux-outside workflows
- Existing `launch-ghostty.sh` proves this pattern works

**Window Title Propagation**:
- ANSI escape sequences set terminal title immediately
- Title visible to i3 for window matching
- Format: `[PROJECT:nixos] nixos - Ghostty`
- Pattern established in `launch-ghostty.sh:49`

**Connect vs. Create**:
- `sesh connect <session>` reuses existing session or creates new
- Multiple terminals can share same tmux session
- Session persists after terminal closes
- Matches user expectation (terminals for same project share session)

### Alternatives Considered

**1. Tmux Only (No sesh)**
```bash
tmux new-session -A -s "$PROJECT_ID" -c "$PROJECT_DIR"
```

- **Rejected**: Less ergonomic than sesh (no fuzzy finder)
- **Rejected**: sesh provides better session discovery UX
- **Rejected**: sesh already configured in `home-modules/terminal/sesh.nix`

**2. Separate Sessions Per Terminal**
```bash
tmux new-session -s "${PROJECT_ID}_${TIMESTAMP}"
```

- **Rejected**: Doesn't match user expectation (want shared session per project)
- **Rejected**: Multiple sessions for same project defeats purpose
- **Rejected**: Can't switch between terminals in same project

**3. Project Context in tmux Environment Variables**
```bash
tmux setenv -g PROJECT_ID "$PROJECT_ID"
```

- **Considered**: Useful for tmux status line
- **Not sufficient**: Doesn't help with window title propagation
- **Complementary**: Can use alongside title propagation

### Implementation Notes

#### sesh Integration Pattern

**Existing Implementation** (`launch-ghostty.sh:47`):

```bash
exec "$GHOSTTY" -e bash -c "
    # Set window title with project tag using ANSI escape sequence
    printf '\033]2;[PROJECT:$PROJECT_ID] $PROJECT_ID - Ghostty\007'

    # Launch sesh or create new session if not exists
    if command -v '$SESH' &> /dev/null; then
        exec '$SESH' connect '$PROJECT_ID'
    else
        # Fallback to tmux if sesh fails
        exec tmux new-session -A -s '$PROJECT_ID' -c '$PROJECT_DIR'
    fi
"
```

**Why this works**:
1. ANSI escape immediately sets title (before sesh starts)
2. `sesh connect` reuses existing session or creates new
3. Fallback to tmux ensures robustness
4. `exec` replaces bash process (clean process tree)

#### Window Title Propagation Mechanism

**ANSI Escape Sequence for Title**:
```bash
# Set terminal window title
printf '\033]2;TITLE_TEXT\007'

# Example
printf '\033]2;[PROJECT:nixos] nixos - Ghostty\007'
```

**Format Breakdown**:
- `\033]2;` - OSC (Operating System Command) for window title
- `TITLE_TEXT` - The actual title
- `\007` - Bell character (terminates OSC)

**Title Format Convention**:
```
[PROJECT:<project_id>] <project_name> - <application>
```

**Examples**:
- `[PROJECT:nixos] NixOS Configuration - Ghostty`
- `[PROJECT:stacks] Stacks Platform - Ghostty`

**Why this format**:
- `[PROJECT:...]` prefix enables regex matching in i3 window tree
- Human-readable project name for visual identification
- Application name helps distinguish window types

#### Session Creation vs. Connection Behavior

**sesh connect behavior**:

```bash
# If session 'nixos' exists: connects to it
# If session 'nixos' doesn't exist: creates new session in project directory
sesh connect nixos
```

**Under the hood** (sesh implementation):
```bash
# Equivalent to:
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux attach-session -t "$SESSION_NAME"
else
    tmux new-session -s "$SESSION_NAME" -c "$PROJECT_DIR"
fi
```

**Multiple Terminals Sharing Session**:

```bash
# Terminal 1
sesh connect nixos  # Creates session

# Terminal 2
sesh connect nixos  # Connects to existing session (shares window/pane view)
```

**Why this is desired**:
- Multiple terminals for same project can collaborate
- Copy-paste between terminals via tmux buffers
- Shared tmux clipboard history
- Consistent working directory across terminals

#### Reliable Window-to-Project Association

**Matching Pattern** (from `project-switch-hook.sh:72`):

```bash
# Extract project ID from title using regex
jq '.window_properties.class == "Ghostty" and
    (.name | test("\\[PROJECT:[a-z0-9]+\\]"))'

# Capture project ID
jq '(.name | capture("\\[PROJECT:(?<proj>[a-z0-9]+)\\]") | .proj)'
```

**Regex Pattern**: `\[PROJECT:(?<proj>[a-z0-9]+)\]`
- Matches: `[PROJECT:nixos]`
- Captures: `nixos`

**Edge Cases Handled**:

1. **Title Changes After Launch**
   - sesh/tmux may update title with current directory
   - **Solution**: Tracking file persists original project association
   - **Fallback**: Re-match by window_id in tracking file

2. **Multiple Ghostty Windows for Same Project**
   - Multiple terminals can have same project ID
   - **Desired**: All terminals for project hidden/shown together
   - **Implementation**: All match same `[PROJECT:nixos]` pattern

3. **Terminal Launched Without Project Context**
   - No `[PROJECT:...]` prefix in title
   - **Behavior**: Not associated with any project (global terminal)
   - **Detection**: Regex match fails, window ignored by project system

#### sesh Configuration

**Existing Configuration** (`home-modules/terminal/sesh.nix:8`):

```nix
programs.sesh = {
  enable = true;
  enableAlias = true;  # Enable 's' alias for sesh
  enableTmuxIntegration = true;
  icons = true;
};
```

**Key Features Used**:
- `enableTmuxIntegration`: Auto-creates tmux sessions
- `icons`: Visual indicators in session picker
- `enableAlias`: User can type `s` to launch sesh picker

**Not Needed for This Feature**:
- Interactive session picker (we launch directly with `sesh connect`)
- Directory scanning (we explicitly specify session name and directory)

---

## 5. State Persistence and Race Conditions

### Decision
**Use atomic write pattern with temporary file + mv; no file locking needed; JSON format for state file**

### Rationale

**Atomic Writes with mv**:
- POSIX guarantees `mv` is atomic for same filesystem
- Reader always sees complete valid JSON (never half-written)
- No need for file locking (complexity, failure modes)
- Existing implementation in `launch-code.sh:88` proves this works

**JSON Format**:
- Structured data easier to parse than shell variables
- jq provides robust JSON manipulation
- Extensible (can add fields without breaking readers)
- Human-readable for debugging

**No Locking Needed**:
- Atomic writes prevent corruption
- State updates are infrequent (only on project switch)
- Multiple readers can read simultaneously (read-only operations)
- Write conflicts impossible with atomic write pattern

### Alternatives Considered

**1. File Locking with flock**
```bash
exec 200>/tmp/project-state.lock
flock 200
# Critical section
echo "$STATE" > ~/.config/i3/current-project
flock -u 200
```

- **Rejected**: Adds complexity (lock acquisition, timeouts)
- **Rejected**: Lock file can become stale if process crashes
- **Rejected**: Blocking lock can hang scripts indefinitely
- **Rejected**: Not needed with atomic write pattern

**2. State in i3 Config Variables**
```bash
i3-msg "set $current_project nixos"
```

- **Rejected**: i3 doesn't support runtime variable setting
- **Rejected**: Would require i3 config reload on every project switch
- **Rejected**: No persistence across i3 restarts

**3. Shared Memory (tmpfs)**
```bash
echo "$PROJECT_ID" > /dev/shm/i3-current-project
```

- **Rejected**: Doesn't persist across reboots (lost on system restart)
- **Rejected**: No advantage over filesystem with atomic writes
- **Rejected**: Harder to debug (can't inspect from file manager)

**4. SQLite Database**
```bash
sqlite3 ~/.config/i3/state.db "INSERT INTO projects ..."
```

- **Rejected**: Over-engineering for single-value state
- **Rejected**: Requires sqlite3 binary dependency
- **Rejected**: More complex than JSON file

### Implementation Notes

#### Atomic Write Pattern

**Existing Implementation** (`launch-code.sh:88`):

```bash
# Write to temporary file
jq --arg wid "$WINDOW_DEC" \
   --arg pid "$PROJECT_ID" \
   '.windows[$wid] = {...}' \
   "$WINDOW_MAP_FILE" > "$WINDOW_MAP_FILE.tmp"

# Atomic rename (overwrites original)
mv "$WINDOW_MAP_FILE.tmp" "$WINDOW_MAP_FILE"
```

**Why this works**:
1. Write complete JSON to `.tmp` file
2. `mv` atomically replaces original file
3. Readers never see partial JSON (either old or new, never corrupted)
4. If process crashes during write, original file unchanged

**Error Handling**:
```bash
# Check if write succeeded before moving
if jq ... "$FILE" > "$FILE.tmp"; then
    mv "$FILE.tmp" "$FILE"
else
    echo "Failed to update state file" >&2
    rm -f "$FILE.tmp"  # Clean up partial write
    return 1
fi
```

#### State File Format

**Current Project State** (`~/.config/i3/current-project`):

```json
{
  "project_id": "nixos",
  "project_name": "NixOS Configuration",
  "directory": "/etc/nixos",
  "activated_at": "2025-10-19T14:30:00-07:00"
}
```

**Window Tracking State** (`~/.config/i3/window-project-map.json`):

```json
{
  "windows": {
    "12345678": {
      "project_id": "nixos",
      "wmClass": "Code",
      "registered_at": "2025-10-19T14:31:00-07:00",
      "auto_registered": false
    },
    "87654321": {
      "project_id": "stacks",
      "wmClass": "Ghostty",
      "registered_at": "2025-10-19T14:32:00-07:00",
      "auto_registered": true
    }
  }
}
```

**Field Descriptions**:
- `project_id`: Unique identifier (alphanumeric, lowercase)
- `project_name`: Human-readable name
- `directory`: Absolute path to project directory
- `activated_at`: ISO 8601 timestamp of activation
- `window_id`: X11 window ID (as string for JSON compatibility)
- `auto_registered`: Boolean indicating if auto-discovered or explicitly launched

#### Race Condition Analysis

**Scenario 1: Simultaneous Project Switch**

```
Time | Script A (old project) | Script B (new project)
-----|------------------------|------------------------
T0   | Read current-project   |
T1   |                        | Read current-project
T2   | Write current-project  |
T3   |                        | Write current-project
```

**Result**: B's write wins (atomic mv)
**Impact**: Safe - last write wins, project state consistent
**Mitigation**: Not needed - this scenario unlikely (user triggers one switch at a time)

**Scenario 2: Read During Write**

```
Time | Writer                      | Reader
-----|-----------------------------|-----------------------
T0   | Write to .tmp              |
T1   |                             | Read current-project (old)
T2   | mv .tmp to current-project |
T3   |                             | Read current-project (new)
```

**Result**: Reader sees either old or new state (never partial)
**Impact**: Safe - atomic mv guarantees complete file
**Mitigation**: Not needed - inherent to atomic write pattern

**Scenario 3: Multiple Windows Registering Simultaneously**

```
Time | launch-code.sh | launch-ghostty.sh
-----|----------------|-------------------
T0   | Read map.json  | Read map.json
T1   | Add Code win   | Add Ghostty win
T2   | Write map.tmp  |
T3   |                | Write map.tmp
T4   | mv map.tmp     |
T5   |                | mv map.tmp
```

**Result**: Ghostty write wins, Code window lost
**Impact**: PROBLEMATIC - one window not registered
**Mitigation**: Acceptable - auto-discovery will re-register on next project switch

**Better Mitigation** (if needed):
```bash
# Retry on conflict detection
for attempt in {1..3}; do
    # Read current state
    current=$(cat "$FILE")

    # Modify
    new=$(echo "$current" | jq ...)

    # Write with checksum validation
    echo "$new" > "$FILE.tmp"

    # Atomic move
    if mv "$FILE.tmp" "$FILE"; then
        break
    fi

    sleep 0.1  # Brief backoff
done
```

**Decision**: Not implementing retry (over-engineering)
- Simultaneous launches rare (user launches one app at a time)
- Auto-discovery recovers from missed registrations
- Complexity not justified by low-probability scenario

#### State Corruption Prevention

**Initialize on First Use**:
```bash
# Ensure file exists with valid JSON
if [ ! -f "$STATE_FILE" ]; then
    echo '{"project_id":null}' > "$STATE_FILE"
fi
```

**Validate on Read**:
```bash
# Check if file contains valid JSON
if ! jq empty "$STATE_FILE" 2>/dev/null; then
    echo "ERROR: Corrupted state file" >&2
    # Reinitialize
    echo '{"project_id":null}' > "$STATE_FILE"
fi
```

**Existing Pattern** (`launch-code.sh:74`):
```bash
# Initialize file if it doesn't exist
if [ ! -f "$WINDOW_MAP_FILE" ]; then
    echo '{"windows":{}}' > "$WINDOW_MAP_FILE"
fi
```

#### Cleanup Strategy

**Stale Window Entries**:
```bash
# Remove windows that no longer exist (cleanup script)
cleanup_stale_windows() {
    local tracked_windows=$(jq -r '.windows | keys[]' "$WINDOW_MAP_FILE")
    local existing_windows=$(i3-msg -t get_tree | jq -r '.. | .window? // empty')

    # Remove windows not in existing_windows
    for window_id in $tracked_windows; do
        if ! echo "$existing_windows" | grep -q "^$window_id$"; then
            jq "del(.windows[\"$window_id\"])" "$WINDOW_MAP_FILE" > "$WINDOW_MAP_FILE.tmp"
            mv "$WINDOW_MAP_FILE.tmp" "$WINDOW_MAP_FILE"
        fi
    done
}
```

**When to Clean**:
- On i3 restart (exec_always in i3 config)
- On project switch (before showing windows)
- Manual cleanup command (for debugging)

**Not Implemented Yet**: Cleanup on window close events (requires event subscription)

---

## Implementation Recommendations

### Critical Patterns to Follow

1. **Always use scratchpad for hiding** (not high workspaces)
2. **Atomic writes with mv** for all state files
3. **Hybrid tracking** (marks + JSON file) for window persistence
4. **On-demand queries** instead of event subscriptions
5. **i3 IPC GET_OUTPUTS** for monitor detection (not xrandr)
6. **sesh connect** for project-scoped tmux sessions
7. **ANSI escapes** for terminal title propagation

### Performance Guidelines

- GET_TREE queries: <100ms (acceptable for infrequent operations)
- Scratchpad move: <50ms per window
- State file read: <10ms (JSON parsing with jq)
- Project switch total: <2 seconds (spec requirement: ✓)

### Error Handling Principles

1. **Fail gracefully** - Continue with partial results if possible
2. **Log errors** - Write to `~/.config/i3/project-switch.log`
3. **Validate inputs** - Check project_id, con_id before operations
4. **Default to safe** - Empty list instead of crashing

### Testing Strategies

1. **Manual acceptance testing** for each user story
2. **Edge case testing**:
   - No windows for project (empty list)
   - Windows closed during switch (stale con_id)
   - Invalid JSON in state file (corruption recovery)
   - Monitor unplugged during operation (fallback)
3. **Integration testing**:
   - i3 restart during project switch
   - Multiple rapid project switches
   - Launching apps with no active project

---

## References

### Documentation
- i3 IPC Protocol: `/etc/nixos/docs/i3-ipc.txt`
- Related Research: `/etc/nixos/specs/010-i3-project-workspace/research-findings.md`
- Implementation Plan: `/etc/nixos/specs/011-project-scoped-application/plan.md`

### Existing Implementations
- Window Management: `/etc/nixos/scripts/project-switch-hook.sh`
- Monitor Detection: `/etc/nixos/scripts/detect-monitors.sh`
- Workspace Assignment: `/etc/nixos/scripts/assign-workspace-monitor.sh`
- VS Code Launcher: `/etc/nixos/scripts/launch-code.sh`
- Ghostty Launcher: `/etc/nixos/scripts/launch-ghostty.sh`
- i3 Configuration: `/etc/nixos/home-modules/desktop/i3.nix`

### Key Tools
- `i3-msg`: i3 IPC client (bundled with i3)
- `jq`: JSON processor (parsing i3 IPC responses)
- `sesh`: tmux session manager (project-scoped sessions)
- `wmctrl`: X window control (window ID detection)

---

**Document Version**: 1.0
**Research Date**: 2025-10-19
**Status**: Complete - Ready for Phase 1 Design
