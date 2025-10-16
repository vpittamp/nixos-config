# Feature 006: Productivity-Focused i3wm Configuration

**Status**: ✅ Specification Complete - Ready for Implementation
**Created**: 2025-10-16
**Commit**: fd585a2

## Quick Start

After clearing context, run:
```bash
cd /etc/nixos
/speckit.plan  # Generate implementation plan
```

Then:
```bash
/speckit.implement  # Start implementation
```

## What's in This Directory

| File | Purpose |
|------|---------|
| `spec.md` | **Complete feature specification** - Read this first! |
| `research.md` | Research findings from popular i3 configs |
| `NEXT_STEPS.md` | How to continue after context clear |
| `README.md` | This file |

## Overview

Enhance the working i3wm setup with productivity features based on research:
- Scratchpad dropdown terminal (Win+grave)
- Named workspaces (1:Term, 2:Code, 3:Web, etc.)
- Vim-style navigation (Win+hjkl)
- Better status bar (i3status-rust)
- Application workspace assignments

## Current State

✅ **Working** (from feature 005):
- i3wm on X11 + XRDP
- Multi-client RDP support
- tmux fully configured
- VS Code, Firefox available
- Basic keybindings (Win+C, Win+B)

## Implementation Phases

**Phase 1 (MVP)**: 4-6 hours
- Scratchpad terminal, named workspaces, vim navigation, i3status-rust

**Phase 2**: 3-4 hours
- Rofi, smart borders, gaps, custom modes

**Phase 3**: 2-3 hours
- Color scheme, theming, notifications

**Phase 4**: 4-5 hours (optional)
- Advanced workflows, templates, automation

## Key Files to Modify

- `modules/desktop/i3wm.nix` - Extend with new features
- `modules/desktop/i3status-rust.nix` - New module (create)
- `configurations/hetzner-i3.nix` - Test configuration

## Success Criteria (Phase 1)

- [ ] Dropdown terminal <100ms response
- [ ] 5 named workspaces visible
- [ ] Vim navigation working
- [ ] Apps auto-assign to workspaces
- [ ] Status bar showing all modules
- [ ] No regressions (XRDP, tmux still work)

---

**Ready for implementation!** See `spec.md` for full details.
