# Quickstart: Visual Worktree Relationship Map

**Feature**: 111-visual-map-worktrees
**Status**: Complete (111 tests passing)

## Overview

The Visual Worktree Relationship Map displays git worktree relationships as an interactive graph in the monitoring panel's Projects tab. See at a glance which branches are ahead/behind, which have been merged, and how worktrees relate to each other.

## Accessing the Map

### Open the Monitoring Panel

```
Mod+M           # Toggle panel visibility
Mod+Shift+M     # Enter focus mode (keyboard navigation)
```

### Switch to Projects Tab

```
Alt+2           # Direct switch to Projects tab
2               # In focus mode, press '2'
```

### Toggle Map View

Click **Map** button in the view toggle header, or:

```
m               # In focus mode, toggle map/list view
```

## Understanding the Map

### Node Types

| Visual | Meaning |
|--------|---------|
| Purple circle (larger) | Main branch |
| Blue circle | Feature branch |
| Teal circle, dashed | Merged branch |
| Faded node | Stale branch (30+ days inactive) |
| Red dot on node | Uncommitted changes |

### Edge Labels

| Label | Meaning |
|-------|---------|
| ↑5 | 5 commits ahead of parent |
| ↓2 | 2 commits behind parent |
| ↑3 ↓2 | Diverged (ahead AND behind) |
| ✓ | Branch was merged |
| ⚠ | Potential merge conflict |

### Visual Hierarchy

```
              ┌────────┐
              │  main  │  Root (layer 0)
              └────┬───┘
       ┌──────────┼──────────┐
       │          │          │
  ┌────┴───┐ ┌────┴───┐ ┌────┴───┐
  │  108   │ │  109   │ │  110   │  Layer 1
  └────┬───┘ └────────┘ └────────┘
       │
  ┌────┴───┐
  │  111   │  Layer 2 (branched from 108)
  └────────┘
```

## Interacting with the Map

### Click Actions

- **Left-click node**: Switch to that worktree
- **Right-click node**: Open context menu
- **Hover node**: Show detailed tooltip

### Context Menu Options

| Action | Description |
|--------|-------------|
| Open Terminal | Launch terminal in worktree directory |
| Open VS Code | Open VS Code in worktree |
| Open Lazygit | Launch lazygit for git operations |
| Copy Path | Copy worktree path to clipboard |
| Delete | Delete worktree (with confirmation) |

### Keyboard Shortcuts (Focus Mode)

| Key | Action |
|-----|--------|
| `e` | Toggle expanded map view |
| `Escape` | Close expanded view / Exit focus mode |

**Note**: Full keyboard navigation (j/k/h/l) within the map is planned for a future release. Use click interaction for now.

## Map Refresh Behavior

The map automatically refreshes when:

- Panel is opened
- Worktree is created or deleted
- Git operations complete (commit, push, pull)
- Manual refresh (`r` key or Refresh button)

**Cache**: Branch relationships are cached for 5 minutes to improve performance. Click Refresh to force recalculation.

## Compact vs Expanded View

### Compact View (Default)

- Fits within the monitoring panel
- Optimized for 5-10 worktrees
- Abbreviated labels

### Expanded View

```
e               # In focus mode, toggle expanded view
```

Or click the **Expand button (󰁌)** in the map header.

- Full-screen overlay with larger SVG (600x700px)
- All labels visible
- Better for 10+ worktrees
- Press `Escape` to close
- Click a node to switch and auto-close expanded view

## Status Indicators

### Node Status

| Indicator | Meaning | Action |
|-----------|---------|--------|
| Red dot (●) | Dirty (uncommitted changes) | Commit or stash |
| Faded appearance | Stale (30+ days) | Consider cleanup |
| Teal, dashed | Merged to main | Safe to delete |
| ⚠ badge | Merge conflicts | Resolve conflicts |

### Edge Status

| Style | Meaning |
|-------|---------|
| Solid line | Direct parent-child |
| Dashed line | Merged relationship |
| Red dashed | Potential conflict |

## Troubleshooting

### Map Not Displaying

```bash
# Check monitoring panel service
systemctl --user status eww-monitoring-panel

# Restart if needed
systemctl --user restart eww-monitoring-panel
```

### Relationships Incorrect

```bash
# Force cache refresh
# In panel focus mode, press 'r'

# Or check git state directly
git log --oneline --graph --all | head -30
```

### Performance Issues

If map takes >2 seconds to render with many worktrees:

1. Use list view for navigation
2. Delete stale/merged worktrees
3. Check git repository health: `git gc`

### SVG Not Rendering

```bash
# Check if SVG was generated
ls -la /tmp/worktree-map-*.svg

# Check backend logs
journalctl --user -u eww-monitoring-panel --since "5 minutes ago"
```

## CLI Integration

### Query Map Data

```bash
# Get relationship data as JSON
i3pm worktree relationships nixos

# Get specific branch parent
i3pm worktree parent 111-visual-map
```

### Generate Map Manually

```bash
# Generate SVG without panel
i3pm worktree map nixos --output /tmp/worktree-map.svg
```

## Related Features

- **Feature 108**: Worktree card status display
- **Feature 109**: Enhanced worktree user experience
- **Feature 099**: Projects tab CRUD operations

## Configuration

Map appearance follows Catppuccin Mocha theme defined in:
`~/.config/sway/appearance.json`

No additional configuration required.
