# Ghost Container Quick Reference

**For**: Feature 051 - i3run-Scratchpad Enhancement
**Platform**: Sway (Wayland)
**Use Case**: Project-wide metadata persistence via Sway window marks

---

## Quick Answer: Does It Persist?

| Scenario | Persists? | Notes |
|----------|-----------|-------|
| **Daemon restarts** | YES | Window unchanged in Sway, marks readable |
| **Sway restart** | YES | Process must still be running (e.g., sleep 100) |
| **Process dies** | NO | Ghost window disappears with its marks |
| **Manual cleanup** | User choice | Daemon never auto-removes ghost container |

---

## Creation: One Command

```bash
# Sway command
swaymsg 'exec --no-startup-id "sleep 100 &" && sleep 0.2 && swaymsg "[class=.*] floating enable, resize set 1 1, opacity 0, move scratchpad, mark i3pm_ghost"'
```

## Python Implementation (Recommended)

```python
class GhostContainerManager:
    async def ensure_ghost_container_exists(self) -> int:
        """Returns existing or creates new ghost container."""
        # 1. Query tree for mark i3pm_ghost
        # 2. If found: return existing window ID
        # 3. If not found: create new ghost
        pass
```

---

## Persistence Strategy

```
On Daemon Start:
  1. Query Sway tree for mark "i3pm_ghost"
  2. If found: use existing ghost window
  3. If not: create new ghost window
  4. Read marks from ghost: scratchpad_state:*
  5. Restore terminal states from marks

Result: Ghost container is "create once, never destroy"
```

---

## Mark Format

| Mark | Purpose | Example |
|------|---------|---------|
| `i3pm_ghost` | Ghost container ID | Primary mark on invisible window |
| `scratchpad:project` | Terminal window | `scratchpad:nixos` (Feature 062) |
| `scratchpad_state:project=...` | Persistent state | `scratchpad_state:nixos=floating:true,x:100,y:200` |

---

## State Storage Example

```
Ghost window marks:
[
  "i3pm_ghost",
  "scratchpad_state:nixos=floating:true,x:100,y:200,w:1000,h:600,ts:1730819417",
  "scratchpad_state:work=floating:false,x:50,y:100,w:800,h:400,ts:1730819418"
]
```

Parse example:
```python
project, state = decode_state("scratchpad_state:nixos=floating:true,x:100,y:200")
# project = "nixos"
# state = {"floating": True, "x": 100, "y": 200}
```

---

## Lifecycle: Birth to Death

```
1. Daemon starts
   → Queries Sway for i3pm_ghost mark
   → Not found, so creates new ghost window

2. Ghost window created
   → 1x1 pixel, opacity 0, in scratchpad
   → Marked: i3pm_ghost
   → Process: sleep 100 (lightweight, long-lived)

3. Terminal launches
   → Marked: scratchpad:project_name
   → State recorded in ghost: scratchpad_state:project_name=...

4. Daemon restarts
   → Ghost window still exists (same content, new window ID)
   → Marks still readable
   → State restored from ghost marks

5. Manual cleanup (optional)
   → swaymsg '[con_mark=i3pm_ghost] kill'
   → Removes ghost and all marks
```

---

## Key Commands

```bash
# Find ghost
swaymsg -t get_tree | jq '.. | select(.marks[]? == "i3pm_ghost")'

# Get window ID
GHOST_ID=$(swaymsg -t get_tree | jq '.. | select(.marks[]? == "i3pm_ghost") | .id' | head -1)

# Add mark to ghost
swaymsg "[con_id=$GHOST_ID] mark \"scratchpad_state:project=state:value\""

# Read marks from ghost
swaymsg "[con_mark=i3pm_ghost] mark --list"

# Remove ghost
swaymsg '[con_mark=i3pm_ghost] kill'

# Verify 1x1 and opacity 0
swaymsg -t get_tree | jq ".. | select(.marks[]? == \"i3pm_ghost\") | {geometry: {width, height}, opacity}"
```

---

## Python Usage Pattern

```python
# Initialize
ghost_mgr = GhostContainerManager(sway_connection)
await ghost_mgr.initialize()  # Creates ghost if needed

# Store state
state = {"floating": True, "x": 100, "y": 200}
await ghost_mgr.add_state_mark("nixos", state)

# Retrieve state
state = await ghost_mgr.retrieve_metadata("nixos")
print(state)  # {"floating": True, "x": 100, "y": 200}

# On daemon restart
state = await ghost_mgr.retrieve_metadata("nixos")  # Works immediately
```

---

## Why Ghost Containers?

| Feature | Benefit |
|---------|---------|
| **Persistent** | Survives daemon/Sway restarts (if process alive) |
| **Attached to windows** | Marks tied to Sway window lifecycle |
| **Lightweight** | 1x1 pixel, negligible CPU/memory |
| **Single per system** | One ghost stores state for all projects |
| **Marks support multiple projects** | Ghost can hold marks for 5+ projects |
| **No file I/O** | No JSON files to sync or lock |

---

## Gotchas

1. **Process must stay alive**: If `sleep 100` expires, ghost dies
   - Solution: Daemon monitors and recreates if needed

2. **Window ID changes on Sway restart**: But marks persist
   - Solution: Always query by mark, never cache window ID

3. **Marks have ~200 char limit**: Per-mark (not total)
   - Solution: Keep state entries under 80 chars (plenty)

4. **No persistence across process death**: If process dies, marks lost
   - Solution: Monitor ghost health, recreate if missing

---

## Testing

```bash
# Create ghost manually
swaymsg 'exec --no-startup-id "sleep 100"'
GHOST_ID=$(swaymsg -t get_tree | jq '.. | objects | select(.type=="floating_con") | .id' | tail -1)
swaymsg "[con_id=$GHOST_ID] floating enable, resize set 1 1, opacity 0, move scratchpad, mark i3pm_ghost"

# Add test mark
swaymsg "[con_mark=i3pm_ghost] mark \"scratchpad_state:test=value:123\""

# Verify
swaymsg "[con_mark=i3pm_ghost] mark --list"
# Should see: i3pm_ghost, scratchpad_state:test=value:123

# Kill Sway (or restart)
# Verify mark still there
swaymsg "[con_mark=i3pm_ghost] mark --list"
```

---

## File Location

Full research: `/etc/nixos/docs/051-GHOST_CONTAINER_RESEARCH.md` (1400+ lines)

---

## Next Steps

1. Implement `GhostContainerManager` class
2. Integrate with `ScratchpadManager` for state persistence
3. Implement state restoration on daemon startup
4. Add unit tests for mark encoding/decoding
5. Full Feature 051 implementation

---

**Created**: 2025-11-06
**Status**: Ready for implementation
