# Quick Start: Enhanced Projects & Applications CRUD Interface

**Feature**: 094-enhance-project-tab
**Date**: 2025-11-24

## Overview

Add comprehensive CRUD operations to the monitoring panel's Projects and Applications tabs.

## Quick Test Scenarios

### Projects Tab

**View Projects** (US1):
```bash
# Open monitoring panel
Mod+M

# Navigate to Projects tab (Alt+2)
# Hover over any project → see JSON detail with syntax highlighting
```

**Edit Project** (US2):
```bash
# Click "Edit" icon next to project
# Modify display name or icon
# Click "Save" → verify list updates immediately
# Check file: cat ~/.config/i3/projects/<name>.json
```

**Create Project** (US3):
```bash
# Click "New Project" button
# Fill form: name="test-project", dir="~/test"
# Click "Save" → verify appears in list
```

**Worktrees** (US5):
```bash
# Under main project, click "New Worktree"
# Fill form: branch="feature-095", path="~/nixos-095"
# Click "Save" → verify hierarchy shows worktree with tree lines
```

### Applications Tab

**View Apps** (US6):
```bash
# Navigate to Applications tab (Alt+3)
# Hover over apps → see type-specific JSON detail
# PWAs show ULID, start_url; Terminal apps show parameters
```

**Edit App** (US7):
```bash
# Click "Edit" on regular app
# Change workspace from 3 to 5
# Click "Save" → see rebuild notification
```

**Create PWA** (US8):
```bash
# Click "New Application" → select "PWA"
# Fill: name="notion-pwa", start_url="https://notion.so", workspace=55
# Click "Save" → ULID auto-generated, rebuild notification shown
```

## Key Files

- **Projects**: `~/.config/i3/projects/*.json`
- **Apps**: `home-modules/desktop/app-registry-data.nix`
- **Backend**: `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
- **Frontend**: `home-modules/desktop/eww-monitoring-panel.nix`

## Troubleshooting

**Panel not updating**: `systemctl --user restart eww-monitoring-panel`
**Validation errors**: Check backend logs: `journalctl --user -u eww-monitoring-panel -f`
**Nix syntax error**: Backup restored automatically, check error message

## Dependencies

- Python 3.11+ with Pydantic
- Eww 0.4+ with deflisten support
- i3pm CLI for worktree operations
- `/etc/nixos/scripts/generate-ulid.sh` for PWA creation
