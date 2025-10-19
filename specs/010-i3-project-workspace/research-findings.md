# i3 Window Manager IPC and Layout Research Findings

## Executive Summary

This document presents research findings on i3 window manager's IPC protocol and layout mechanisms for implementing a project workspace management system. The research covers six critical areas: IPC protocol usage, tooling choices, layout saving/restoration, window matching reliability, monitor assignment, and workspace switching.

---

## 1. i3 IPC Protocol: Querying Workspace State and Window Information

### Decision
**Use `i3-msg` with JSON output piped to `jq` for bash scripts**

### Rationale
- `i3-msg` is the official command-line interface to i3's IPC socket
- Native integration with i3, no external dependencies beyond `jq`
- Returns structured JSON that's easy to parse with standard tools
- Low overhead communication via Unix socket
- Well-documented and stable API

### Implementation Notes

#### Key IPC Message Types
```bash
# Get all workspaces
i3-msg -t get_workspaces

# Get complete window tree
i3-msg -t get_tree

# Get outputs (monitors)
i3-msg -t get_outputs

# Execute commands
i3-msg 'workspace 1'
```

#### Practical Parsing Examples

**Get focused workspace name:**
```bash
i3-msg -t get_workspaces | jq -r '.[] | select(.focused==true).name'
```

**Get focused workspace number:**
```bash
i3-msg -t get_workspaces | jq -r '.[] | select(.focused==true).num'
```

**List all workspace names:**
```bash
i3-msg -t get_workspaces | jq -r '.[].name'
```

**Get windows on current workspace:**
```bash
i3-msg -t get_tree | jq -r '.. | select(.type?) | select(.type=="con") | select(.window?) | {name, window_properties}'
```

**Extract window WM_CLASS:**
```bash
i3-msg -t get_tree | jq -r '.. | select(.window_properties?) | .window_properties.class'
```

#### IPC Socket Access
The IPC socket path is available via:
- Environment variable: `$I3SOCK`
- Command: `i3 --get-socketpath`
- Default location: `/run/user/$UID/i3/ipc-socket.*`

### Pitfalls
1. **JSON Output is Large**: The `get_tree` output can be several MB for many windows - filter early
2. **Recursive Structure**: The tree is deeply nested - use `jq`'s recursive descent operator `..` carefully
3. **Don't Parse with Shell**: Never use `grep`/`sed`/`awk` on JSON - always use `jq`
4. **Undocumented Properties**: Only use documented properties as others may change
5. **Quoting Issues**: Always quote variables when passing to i3-msg: `i3-msg "workspace '$ws'"`

---

## 2. i3-msg vs i3ipc Libraries

### Decision
**Use `i3-msg` for bash scripts; consider i3ipc-python for complex event-driven logic**

### Rationale

**i3-msg strengths:**
- Simple command-line invocation from bash
- No additional language runtime required
- Straightforward for one-off queries and commands
- Perfect for shell scripts and keybindings
- Minimal dependencies (just `jq` for parsing)

**i3ipc library strengths:**
- Event subscription and monitoring
- Complex state management
- Structured data handling
- Better for long-running processes
- Available in Python, Perl, Ruby, C, JavaScript

### Implementation Notes

#### When to Use i3-msg (Bash)
```bash
#!/bin/bash
# Simple workspace switching
current=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused==true).num')
if [[ $current -eq 2 ]]; then
    i3-msg workspace 10
else
    i3-msg workspace 2
fi
```

#### When to Use i3ipc (Python)
```python
#!/usr/bin/env python3
import i3ipc

# Event-driven monitoring
i3 = i3ipc.Connection()

def on_workspace_focus(i3, e):
    # React to workspace changes
    print(f"Switched to workspace: {e.current.name}")

i3.on('workspace::focus', on_workspace_focus)
i3.main()  # Start event loop
```

#### Hybrid Approach (Recommended)
- Use i3ipc-python for monitoring and event handling
- Use bash + i3-msg for executing actions
- Example: Python daemon monitors workspaces, writes state to file; bash scripts read state and execute commands

### Pitfalls
1. **Event Ordering**: i3-py had issues with command execution order - use i3ipc instead
2. **Shell Parsing**: Don't parse i3-msg JSON output with shell tools - use jq or switch to Python
3. **Blocking Operations**: i3ipc event loops block - run in background or separate process
4. **Socket Permissions**: Ensure scripts have access to the IPC socket

---

## 3. Layout Saving: i3-save-tree and JSON Layouts

### Decision
**Use i3-save-tree for initial capture, manually edit swallows criteria, append_layout for restoration**

### Rationale
- i3-save-tree captures exact window tree structure
- JSON layouts provide declarative project definitions
- Placeholder windows enable reliable application placement
- Swallows criteria allow flexible window matching
- Native i3 feature, no external tools required

### Implementation Notes

#### Workflow

**1. Save Layout:**
```bash
# Save current workspace layout
i3-save-tree --workspace 1 > ~/.config/i3/layouts/workspace-1.json

# Save specific window tree
i3-save-tree --workspace "dev" > ~/.config/i3/layouts/dev-workspace.json
```

**2. Edit Swallows Criteria:**

Raw output from i3-save-tree:
```json
{
    "border": "pixel",
    "floating": "auto_off",
    "layout": "splith",
    "percent": 0.5,
    "type": "con",
    "nodes": [
        {
            "swallows": [
                {
                    // "class": "^Firefox$",
                    // "instance": "^Navigator$",
                    // "title": "^Mozilla Firefox$",
                    // "window_role": "^browser$"
                }
            ]
        }
    ]
}
```

**Edited for specific matching:**
```json
{
    "border": "pixel",
    "floating": "auto_off",
    "layout": "splith",
    "percent": 0.5,
    "type": "con",
    "nodes": [
        {
            "swallows": [
                {
                    "class": "^Firefox$",
                    "instance": "^Navigator$"
                }
            ]
        }
    ]
}
```

**3. Restore Layout:**
```bash
# Switch to workspace and load layout
i3-msg 'workspace 1; append_layout ~/.config/i3/layouts/workspace-1.json'

# Then launch applications (they'll be swallowed into placeholders)
firefox &
code &
```

#### Swallows Criteria Properties

Available matching properties (all are PCRE regex, case-sensitive):
- `class`: WM_CLASS class (second part)
- `instance`: WM_CLASS instance (first part)
- `title`: Window title (_NET_WM_NAME)
- `window_role`: WM_WINDOW_ROLE
- `machine`: WM_CLIENT_MACHINE

#### Getting Window Properties
```bash
# Interactive - click on window
xprop | grep -E "(WM_CLASS|WM_NAME|WM_WINDOW_ROLE)"

# Programmatic - active window
xdotool getactivewindow getwindowclassname
xprop -id $(xdotool getactivewindow) | grep WM_CLASS
```

#### Multiple Criteria Options
```json
// Match ANY of these windows
"swallows": [
    {"class": "^Emacs$"},
    {"class": "^Gvim$"}
]

// Match window with ALL of these properties
"swallows": [
    {
        "class": "^Code$",
        "title": ".*project-name.*"
    }
]
```

### Pitfalls

#### Critical Issues

1. **Manual Editing Required**:
   - i3-save-tree output is NOT usable as-is
   - Must uncomment and refine swallows criteria
   - Comments in JSON are i3-specific extension

2. **Timing and Synchronization**:
   - Applications must be launched AFTER append_layout
   - Placeholder windows created immediately
   - Windows swallowed on first match
   - No automatic application launching

3. **Title Matching Timing**:
   - Some apps (Firefox, Chrome) set title after window creation
   - Prefer matching on `class` and `instance` (set at creation)
   - Older i3 versions had title matching bugs (fixed in recent versions)

4. **Placeholder Persistence**:
   - Unmatched placeholders remain as empty containers
   - Can clutter workspace if apps fail to launch
   - Need cleanup mechanism for stale placeholders

5. **Layout Structure Limitations**:
   - Only captures container geometry and splits
   - Does NOT save application state or content
   - Cannot restore application-specific layouts (e.g., browser tabs)

#### Workarounds

**For existing windows (i3-resurrect approach):**
```bash
# Unmap and remap windows to trigger swallowing
for win_id in $(wmctrl -l | awk '{print $1}'); do
    xdotool windowunmap "$win_id"
    xdotool windowmap "$win_id"
done
```

**Wait for placeholder creation:**
```bash
i3-msg 'workspace 1; append_layout layout.json'
sleep 0.5  # Wait for placeholders
firefox &  # Now launch apps
```

**Cleanup stale placeholders:**
```bash
# Kill empty placeholder containers
i3-msg '[title="^$"] kill'
```

---

## 4. Window Matching: WM_CLASS Reliability and Edge Cases

### Decision
**Prefer `class` + `instance` matching; use `title` only when necessary; implement fallback strategies**

### Rationale
- WM_CLASS (class + instance) is set at window creation
- Title may change dynamically or be set late
- Multiple criteria increase matching reliability
- Some applications have quirks requiring special handling

### Implementation Notes

#### Matching Priority (Most to Least Reliable)

1. **class + instance** (Best - set at creation)
   ```json
   {"class": "^Firefox$", "instance": "^Navigator$"}
   ```

2. **class + window_role**
   ```json
   {"class": "^Gnome-terminal$", "window_role": "^gnome-terminal-window"}
   ```

3. **class only** (Good for most apps)
   ```json
   {"class": "^Code$"}
   ```

4. **title** (Avoid - may change)
   ```json
   {"class": "^Firefox$", "title": ".*GitHub.*"}
   ```

#### Getting Window Properties
```bash
# Interactive method
xprop | grep -E "(WM_CLASS|WM_WINDOW_ROLE|_NET_WM_NAME)"

# Output example:
# WM_CLASS(STRING) = "Navigator", "Firefox"
#                     ^instance    ^class
# WM_WINDOW_ROLE(STRING) = "browser"
# _NET_WM_NAME(UTF8_STRING) = "Mozilla Firefox"
```

### Pitfalls

#### Known Problematic Applications

1. **Spotify**
   - Does NOT set class hints when mapping window
   - Must use `for_window` instead of `assign`
   ```i3config
   for_window [class="Spotify"] move to workspace 10
   ```

2. **Firefox/Chrome with Extensions**
   - Title changes after window creation (Vimperator, etc.)
   - Match on class only, not title
   ```json
   {"class": "^Firefox$", "instance": "^Navigator$"}
   ```

3. **Terminal Programs**
   - Cannot match on programs running INSIDE terminal
   - Can only match terminal emulator itself
   - Use window_role to distinguish terminal windows

4. **Electron Apps (VS Code, Slack, Discord)**
   - Usually reliable with class matching
   - May have different class for different windows (e.g., "code-url-handler")
   ```json
   {"class": "^Code$"}
   {"class": "^code"}  // Partial match for all Code windows
   ```

5. **Games**
   - May not set WM_CLASS at all
   - Use `window_type` if available (requires i3 FAQ workaround)

6. **Java Applications**
   - May require setting `AWT_TOOLKIT=XToolkit`
   - Class names often generic or wrong

#### Edge Cases

1. **Windows Without WM_CLASS**
   - Some applications don't set WM_CLASS
   - Cannot match these windows
   - Alternative: match on window_type or title (unreliable)

2. **Multiple Windows Same Class**
   - Applications like GIMP have many windows with same class
   - Cannot reliably distinguish without window_role
   - Example: Cannot tell Shutter main window from dialogs

3. **Dynamic Title Applications**
   - Browsers add " - Private Browsing" after creation
   - `assign` only checks properties at creation time
   - Use `for_window` for post-creation matching

#### Recommended Strategies

**Strategy 1: Progressive Fallback**
```json
// Try specific match first
"swallows": [{"class": "^Code$", "instance": "^code$"}]

// Fallback to class only
"swallows": [{"class": "^Code$"}]
```

**Strategy 2: Multiple Alternatives**
```json
// Match any of these
"swallows": [
    {"class": "^Emacs$", "instance": "^emacs$"},
    {"class": "^Emacs$"}  // Fallback
]
```

**Strategy 3: Partial Regex Matching**
```json
// Match all VS Code windows
{"class": "^[Cc]ode"}

// Match terminals with project name
{"class": "^Alacritty$", "title": ".*nixos-config.*"}
```

#### Testing Window Matching
```bash
# Test if window matches criteria
i3-msg '[class="Firefox" instance="Navigator"] focus'

# List all windows with class
i3-msg -t get_tree | jq '.. | select(.window_properties?) | .window_properties | select(.class=="Firefox")'

# Monitor window creation in real-time
i3-msg -t subscribe -m '[ "window" ]' | jq -r 'select(.change=="new") | .container.window_properties'
```

---

## 5. Monitor/Output Assignment

### Decision
**Use workspace output assignment + xrandr for detection; support multi-output fallback**

### Rationale
- i3 v4.16+ supports multiple output assignment
- xrandr provides reliable monitor detection
- Declarative workspace-to-output mapping
- Graceful fallback for disconnected monitors

### Implementation Notes

#### Detect Connected Monitors
```bash
# List monitor names
xrandr --listmonitors

# Example output:
# Monitors: 2
#  0: +*DP-1 2560/597x1440/336+0+0  DP-1
#  1: +HDMI-1 1920/531x1080/299+2560+0  HDMI-1

# Get connected outputs
xrandr --query | grep " connected" | awk '{print $1}'

# Check specific output
if xrandr | grep "HDMI-1 connected" > /dev/null; then
    echo "HDMI-1 is connected"
fi

# Get EDID for unique monitor identification
xrandr --verbose | grep -A 10 "^DP-1"
```

#### Workspace Output Assignment

**i3 config (v4.16+):**
```i3config
# Assign workspace to specific output(s)
workspace 1 output DP-1
workspace 2 output DP-1
workspace 3 output HDMI-1

# Multiple outputs (fallback)
workspace 4 output HDMI-1 DP-1  # Prefers HDMI-1, falls back to DP-1

# Use primary output
workspace 10 output primary
```

**Set primary output with xrandr:**
```bash
xrandr --output DP-1 --primary
```

#### Dynamic Monitor Configuration

**Script to setup monitors:**
```bash
#!/bin/bash
# Detect and configure monitors

# Check if external monitor connected
if xrandr | grep "HDMI-1 connected" > /dev/null; then
    # Dual monitor setup
    xrandr --output eDP-1 --primary --mode 1920x1080 \
           --output HDMI-1 --mode 2560x1440 --right-of eDP-1

    # Assign workspaces
    i3-msg 'workspace 1 output eDP-1'
    i3-msg 'workspace 2 output HDMI-1'
else
    # Single monitor setup
    xrandr --output eDP-1 --primary --mode 1920x1080 --output HDMI-1 --off
fi

# Restart i3 to apply
i3-msg restart
```

#### Using arandr (GUI)
```bash
# Launch arandr to configure visually
arandr

# Save configuration
# Layout -> Save As -> ~/.screenlayout/dual-monitor.sh

# Apply from script
~/.screenlayout/dual-monitor.sh
```

#### Monitor-Specific Workspace Naming
```bash
# Name workspaces with output prefix
workspace "1:main" output DP-1
workspace "2:web" output DP-1
workspace "11:code" output HDMI-1
workspace "12:term" output HDMI-1
```

### Pitfalls

1. **Output Assignment vs Display Configuration**
   - `workspace output` only assigns workspaces
   - Does NOT configure physical display properties
   - Must use xrandr for resolution, position, rotation

2. **Disconnected Monitors**
   - Workspaces on disconnected output become "lost"
   - Workaround: workspaces move to available output
   - Issue #2326: i3 doesn't auto-adjust on monitor unplug

3. **Monitor Reconnection**
   - May need to manually reassign workspaces
   - Workspace may not return to original output
   - Solution: Script to detect changes and reassign

4. **Primary Output Changes**
   - Setting new primary may not move existing workspaces
   - Need to explicitly move workspaces after primary change

5. **Output Names**
   - Output names depend on driver (Intel, NVIDIA, AMD)
   - May change between boots or kernel versions
   - Use EDID for reliable identification

#### Recommended Approach

**Startup Script Pattern:**
```bash
#!/bin/bash
# ~/.config/i3/scripts/setup-monitors.sh

# Configure physical displays
xrandr --output eDP-1 --mode 1920x1080 --pos 0x0 --primary \
       --output HDMI-1 --mode 2560x1440 --pos 1920x0

# Wait for xrandr to apply
sleep 1

# Assign workspaces
i3-msg 'workspace 1 output eDP-1'
i3-msg 'workspace 2 output eDP-1'
i3-msg 'workspace 3 output HDMI-1'
i3-msg 'workspace 4 output HDMI-1'

# Restart i3 to apply changes
i3-msg restart
```

**Call from i3 config:**
```i3config
exec_always --no-startup-id ~/.config/i3/scripts/setup-monitors.sh
```

**Monitor change detection:**
```bash
#!/bin/bash
# Monitor udev events for monitor changes
# /etc/udev/rules.d/95-monitor-hotplug.rules
# ACTION=="change", SUBSYSTEM=="drm", RUN+="/home/user/.config/i3/scripts/setup-monitors.sh"
```

---

## 6. Workspace Switching: Programmatic Best Practices

### Decision
**Use `i3-msg` with `workspace number` for numeric workspaces; implement focus+move chains for window operations**

### Rationale
- `workspace number` works with different naming schemes
- Chained commands execute atomically
- Focus management prevents wrong window operations
- Direction-based switching (next/prev) built into i3

### Implementation Notes

#### Basic Workspace Switching
```bash
# Switch to workspace by name
i3-msg 'workspace 1'
i3-msg 'workspace "dev"'

# Switch to workspace by number (works with names like "1:web")
i3-msg 'workspace number 1'

# Switch to next/previous workspace
i3-msg 'workspace next'
i3-msg 'workspace prev'

# Restrict to current output
i3-msg 'workspace next_on_output'
i3-msg 'workspace prev_on_output'

# Create and switch to new workspace
i3-msg 'workspace 99'  # Creates if doesn't exist
```

#### Moving Windows
```bash
# Move focused window to workspace
i3-msg 'move container to workspace 1'
i3-msg 'move container to workspace number 1'

# Move and follow
i3-msg 'move container to workspace 1; workspace 1'

# Move to next/prev workspace
i3-msg 'move container to workspace next'
i3-msg 'move container to workspace prev'
```

#### Advanced Scripting Patterns

**Toggle between workspaces:**
```bash
#!/bin/bash
current=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused==true).num')
if [[ $current -eq 1 ]]; then
    i3-msg 'workspace 2'
else
    i3-msg 'workspace 1'
fi
```

**Move to numerically adjacent workspace:**
```bash
#!/bin/bash
current=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused==true).num')
next=$((current + 1))

# Move and switch
i3-msg "move container to workspace number $next; workspace number $next"
```

**Dynamic workspace creation:**
```bash
#!/bin/bash
# Find first unused workspace number
used=$(i3-msg -t get_workspaces | jq -r '.[].num' | sort -n)
for i in {1..10}; do
    if ! echo "$used" | grep -q "^$i$"; then
        i3-msg "workspace number $i"
        break
    fi
done
```

**Swap workspaces between monitors:**
```bash
#!/bin/bash
# Get workspace on each output
ws1=$(i3-msg -t get_workspaces | jq -r '.[] | select(.output=="DP-1") | select(.focused==false) | .name' | head -1)
ws2=$(i3-msg -t get_workspaces | jq -r '.[] | select(.output=="HDMI-1") | select(.focused==false) | .name' | head -1)

# Rename with temporary names to avoid conflicts
i3-msg "rename workspace \"$ws1\" to tmp1"
i3-msg "rename workspace \"$ws2\" to tmp2"
i3-msg "rename workspace tmp1 to \"$ws2\""
i3-msg "rename workspace tmp2 to \"$ws1\""

# Move to correct outputs
i3-msg "[workspace=\"$ws2\"] move workspace to output DP-1"
i3-msg "[workspace=\"$ws1\"] move workspace to output HDMI-1"
```

**Launch and arrange windows:**
```bash
#!/bin/bash
# Switch to workspace
i3-msg 'workspace 1'

# Split and launch apps
i3-msg 'split h'
firefox &
sleep 0.5  # Wait for window

i3-msg 'split v'
code &
sleep 0.5

i3-msg 'split h'
alacritty &
```

#### Focus Management

**Ensure correct window is moved:**
```bash
# Focus specific window before moving
i3-msg '[class="Firefox"] focus; move container to workspace 2'

# Focus by title
i3-msg '[title=".*Important.*"] focus; move container to workspace 1'

# Focus by window ID
window_id=$(xdotool getactivewindow)
i3-msg "[id=\"$window_id\"] focus; move container to workspace 3"
```

**Mark and recall windows:**
```bash
# Mark window
i3-msg 'mark important'

# Move marked window
i3-msg '[con_mark="important"] focus; move container to workspace 5'

# Unmark
i3-msg '[con_mark="important"] unmark'
```

#### Workspace Back-and-Forth
```bash
# Jump to previous workspace
i3-msg 'workspace back_and_forth'

# Move window to previous workspace
i3-msg 'move container to workspace back_and_forth'
```

### Pitfalls

#### Critical Issues

1. **Timing Issues**
   - Applications take time to start
   - Wrong window may be focused when move command executes
   - Solution: Explicit focus before move, or use marks

   ```bash
   # WRONG - may move wrong window
   firefox &
   i3-msg 'move container to workspace 2'

   # RIGHT - wait and focus specific window
   firefox &
   sleep 1
   i3-msg '[class="Firefox"] focus; move container to workspace 2'
   ```

2. **Workspace Naming**
   - Mix of numbered and named workspaces
   - `workspace 1` vs `workspace "1:main"`
   - Solution: Always use `workspace number X`

   ```bash
   # Works with "1", "1:main", "1:web", etc.
   i3-msg 'workspace number 1'
   ```

3. **No Direct Window Selection**
   - Cannot specify "move THIS window" directly in bash
   - Must use focus or criteria
   - Timing-sensitive if multiple windows opening

4. **Empty Workspace Creation**
   - Switching to non-existent workspace creates it
   - May create unintended workspaces
   - Solution: Check existence first

   ```bash
   # Check if workspace exists
   if i3-msg -t get_workspaces | jq -e ".[] | select(.num==$ws)" > /dev/null; then
       i3-msg "workspace number $ws"
   else
       echo "Workspace $ws does not exist"
   fi
   ```

5. **Focus Follows Mouse**
   - Mouse movement can change focus during script execution
   - Breaks assumptions about focused window
   - Solution: Use criteria-based commands

#### Best Practices

**Atomic Operations:**
```bash
# Chain commands with semicolons (executes atomically)
i3-msg 'workspace 1; split h; exec firefox; split v; exec code'
```

**Error Handling:**
```bash
#!/bin/bash
if ! i3-msg 'workspace 1' > /dev/null 2>&1; then
    echo "Failed to switch workspace" >&2
    exit 1
fi
```

**Wait for Window Creation:**
```bash
#!/bin/bash
# Launch app
firefox &
pid=$!

# Wait for window with timeout
timeout=10
while [ $timeout -gt 0 ]; do
    if i3-msg -t get_tree | jq -e ".. | select(.window_properties?) | select(.window_properties.class==\"Firefox\")" > /dev/null; then
        break
    fi
    sleep 0.5
    ((timeout--))
done
```

**dmenu Integration:**
```bash
# Select workspace interactively
bindsym $mod+t exec --no-startup-id bash -c 'ws="$(i3-msg -t get_workspaces | jq -r ".[].name" | dmenu)" && i3-msg "workspace \"$ws\""'

# Move window to selected workspace
bindsym $mod+Shift+t exec --no-startup-id bash -c 'ws="$(i3-msg -t get_workspaces | jq -r ".[].name" | dmenu)" && i3-msg "move container to workspace \"$ws\""'
```

---

## Implementation Recommendations for Project Workspace System

### Architecture

**Three-Tier Approach:**

1. **Definition Layer (JSON)**
   - Project workspace definitions
   - Layout templates
   - Application specifications
   - Monitor assignments

2. **Management Layer (Bash Scripts)**
   - Load/save project state
   - Launch applications
   - Restore layouts
   - Monitor management

3. **Integration Layer (i3 Config)**
   - Keybindings
   - Workspace assignments
   - Startup hooks

### Project Definition Schema

```json
{
    "name": "nixos-config",
    "workspaces": [
        {
            "number": 1,
            "name": "editor",
            "output": ["HDMI-1", "primary"],
            "layout": "~/.config/i3/layouts/editor-layout.json",
            "applications": [
                {
                    "command": "code ~/nixos-config",
                    "swallow": {"class": "^Code$", "title": ".*nixos-config.*"}
                }
            ]
        },
        {
            "number": 2,
            "name": "terminal",
            "output": ["HDMI-1", "primary"],
            "applications": [
                {
                    "command": "alacritty --working-directory ~/nixos-config",
                    "swallow": {"class": "^Alacritty$"}
                }
            ]
        }
    ]
}
```

### Key Scripts

**project-workspace-load.sh:**
```bash
#!/bin/bash
# Load project workspace from definition

project_file="$1"

# Parse JSON
workspaces=$(jq -r '.workspaces[]' "$project_file")

# For each workspace
for ws in $workspaces; do
    ws_num=$(echo "$ws" | jq -r '.number')
    ws_name=$(echo "$ws" | jq -r '.name')
    layout=$(echo "$ws" | jq -r '.layout')

    # Switch to workspace
    i3-msg "workspace number $ws_num"

    # Load layout if specified
    if [ -n "$layout" ] && [ "$layout" != "null" ]; then
        i3-msg "append_layout $layout"
    fi

    # Launch applications
    apps=$(echo "$ws" | jq -r '.applications[].command')
    for app in $apps; do
        eval "$app &"
        sleep 0.5
    done
done
```

**project-workspace-save.sh:**
```bash
#!/bin/bash
# Save current workspace state to project definition

project_name="$1"
output_file="~/.config/i3/projects/${project_name}.json"

# Get all workspaces
workspaces=$(i3-msg -t get_workspaces | jq -r '.[] | select(.num >= 1 and .num <= 10)')

# For each workspace
for ws in $workspaces; do
    ws_num=$(echo "$ws" | jq -r '.num')

    # Save layout
    i3-save-tree --workspace "$ws_num" > "~/.config/i3/layouts/${project_name}-ws${ws_num}.json"

    # Get running applications
    # Extract from tree...
done

# Generate project JSON
# ...
```

### Integration Points

**i3 config bindings:**
```i3config
# Quick project switching
bindsym $mod+p exec --no-startup-id ~/.config/i3/scripts/project-menu.sh

# Save current project
bindsym $mod+Shift+p exec --no-startup-id ~/.config/i3/scripts/project-save.sh

# Load project by name
bindsym $mod+Ctrl+p exec --no-startup-id ~/.config/i3/scripts/project-load.sh
```

---

## References

### Official Documentation
- i3 User's Guide: https://i3wm.org/docs/userguide.html
- i3 IPC Documentation: https://i3wm.org/docs/ipc.html
- Layout Saving: https://i3wm.org/docs/layout-saving.html
- i3-msg Manual: https://build.i3wm.org/docs/i3-msg.html

### Tools
- jq: Command-line JSON processor
- xrandr: X RandR extension for monitor management
- xprop: X window property viewer
- xdotool: X automation tool
- i3ipc-python: Python IPC library

### Related Projects
- i3-layout-manager: https://github.com/klaxalk/i3-layout-manager
- i3-resurrect: https://pypi.org/project/i3-resurrect/

---

**Document Version:** 1.0
**Last Updated:** 2025-10-17
**Research Scope:** i3wm IPC, Layout Saving, Window Management
