# Next Steps: After Context Clear

## Current Status (2025-10-16)

### ✅ Completed
1. Research complete - saved to `research.md`
2. Feature specification complete - saved to `spec.md`
3. Current i3wm setup is working:
   - i3wm on X11 with XRDP
   - Multi-client RDP (MacBook + Surface)
   - Basic keybindings (Win+C=VS Code, Win+B=Firefox)
   - tmux fully configured
   - Terminal visibility fixed

### 📦 Artifacts Created
```
/etc/nixos/specs/006-productivity-i3-config/
├── research.md          # Comprehensive research findings
├── spec.md             # Complete feature specification
└── NEXT_STEPS.md       # This file
```

## How to Continue

### Step 1: Review Specification
```bash
cd /etc/nixos/specs/006-productivity-i3-config
cat spec.md | less
```

Key sections to review:
- User Stories (US1-US6)
- Implementation Phases
- Technical Design
- Detailed Feature Specifications

### Step 2: Run Planning Command

```bash
cd /etc/nixos
/speckit.plan
```

This will generate:
- `plan.md` - Detailed implementation plan
- `tasks.md` - Actionable task breakdown
- `data-model.md` - Configuration structure
- `contracts/` - Module interfaces

### Step 3: Start Implementation

Option A - Use speckit workflow:
```bash
/speckit.implement
```

Option B - Manual implementation (Phase 1 only):
```bash
# Edit the i3wm module
nvim modules/desktop/i3wm.nix

# Create i3status-rust module
nvim modules/desktop/i3status-rust.nix

# Test build
sudo nixos-rebuild dry-build --flake .#hetzner-i3

# Deploy
sudo nixos-rebuild switch --flake .#hetzner-i3
```

## Quick Reference: Phase 1 Features

### What to Implement First (MVP)
1. **Scratchpad Dropdown Terminal**
   - Win+grave toggle
   - Pre-loaded with tmux
   - 80% width, 60% height, centered

2. **Named Workspaces**
   - 1:Term, 2:Code, 3:Web, 4:Comm, 5:Media
   - Show in status bar

3. **Vim-style Navigation**
   - Win+h/j/k/l for focus
   - Win+Shift+h/j/k/l for move

4. **Application Assignments**
   - VS Code → workspace 2
   - Firefox → workspace 3

5. **i3status-rust Status Bar**
   - Replace default i3status
   - Show: disk, memory, CPU, network, time

## Key Commands Reference

### Testing
```bash
# Dry build (always run first)
sudo nixos-rebuild dry-build --flake .#hetzner-i3

# Build and switch
sudo nixos-rebuild switch --flake .#hetzner-i3

# Reload i3 config after deploy
DISPLAY=:11 i3-msg reload
DISPLAY=:12 i3-msg reload
```

### Debugging
```bash
# Check i3 config syntax
i3 -C

# View i3 log
cat ~/.i3/i3log

# Check XRDP status
systemctl status xrdp xrdp-sesman

# List active X displays
ps aux | grep "Xorg :"
```

## File Locations

### Current Configuration Files
```
/etc/nixos/
├── modules/desktop/
│   ├── i3wm.nix         # Current i3 config (extend this)
│   └── xrdp.nix         # XRDP config (working, don't touch)
├── configurations/
│   └── hetzner-i3.nix   # Test configuration
└── specs/
    ├── 005-research-a-more/  # Previous feature (completed)
    │   └── tasks.md          # Reference for completed work
    └── 006-productivity-i3-config/  # Current feature
        ├── research.md       # Research findings
        ├── spec.md          # Feature spec
        └── NEXT_STEPS.md    # This file
```

### Where to Add New Code
- `modules/desktop/i3wm.nix` - Extend existing module
- `modules/desktop/i3status-rust.nix` - New module (create this)
- `configurations/hetzner-i3.nix` - Enable new features here for testing

## Important Context

### What's Working (Don't Break)
- ✅ XRDP multi-client sessions (Policy=Separate)
- ✅ tmux with fixed terminal colors
- ✅ VS Code and Firefox available
- ✅ Basic i3 keybindings
- ✅ X11 with software rendering

### Known Constraints
- Headless server (no GPU) - use software rendering
- XRDP requires X11 (not Wayland)
- Multiple simultaneous RDP sessions must work
- Configuration must be declarative (no manual edits)

### Testing Approach
1. Test on hetzner-i3 configuration first
2. Validate via RDP from MacBook/Surface
3. Ensure multi-client still works
4. Check terminal visibility in tmux
5. Verify VS Code/Firefox still launch correctly

## Phase 1 Success Criteria

Before moving to Phase 2, ensure:
- [ ] Dropdown terminal responds in <100ms
- [ ] All 5 named workspaces configured and visible
- [ ] Vim navigation works (h/j/k/l)
- [ ] Applications auto-assign to workspaces
- [ ] Status bar shows all modules
- [ ] No regressions (XRDP, tmux, apps still work)
- [ ] Works across RDP reconnections

## Communication Context for New Session

When starting fresh session, you can say:

> "I'm continuing work on feature 006-productivity-i3-config. The research and specification are complete in /etc/nixos/specs/006-productivity-i3-config/. The current i3wm setup (from feature 005) is working with XRDP multi-client support. I need to implement Phase 1 features: scratchpad dropdown terminal, named workspaces, vim-style navigation, and i3status-rust status bar. Should I run /speckit.plan first to generate the implementation plan?"

## Estimated Timeline

- **Phase 1 (MVP)**: 4-6 hours
  - Scratchpad: 1 hour
  - Workspaces: 1 hour
  - Navigation: 30 min
  - Assignments: 30 min
  - Status bar: 1-2 hours
  - Testing: 1 hour

- **Phase 2**: 3-4 hours
- **Phase 3**: 2-3 hours
- **Phase 4**: 4-5 hours (optional)

**Total**: 13-18 hours for complete implementation

## Questions to Answer

If anything is unclear after reading spec.md:

1. Should we use i3status-rust or Polybar for status bar?
   - **Recommended**: i3status-rust (lighter, native)

2. Should we add rofi in Phase 1?
   - **Recommended**: Add in Phase 2 (not critical for MVP)

3. Should we migrate to home-manager now?
   - **Recommended**: No, extend current NixOS module first

4. What about color scheme/theming?
   - **Recommended**: Phase 3 (after functionality works)

---

**Ready to proceed!** Clear context, then run `/speckit.plan` to generate implementation plan.
