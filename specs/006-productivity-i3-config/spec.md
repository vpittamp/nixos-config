# Feature Specification: Productivity-Focused i3wm Configuration

**Feature ID**: 006-productivity-i3-config
**Status**: Planned
**Created**: 2025-10-16
**Based On**: Research from 005-research-a-more (successful i3wm + XRDP implementation)

## Overview

Enhance the current working i3wm setup with productivity-focused features based on research of top i3 configurations. Focus on workspace management, tmux integration, scratchpad workflows, and better status bar.

## Current State (Baseline)

### What's Working ✅
- i3wm window manager on X11
- XRDP multi-client support (MacBook + Surface simultaneously)
- Basic keybindings (Win+C for VS Code, Win+B for Firefox)
- tmux with comprehensive configuration
- Terminal visibility fixed
- VS Code, Firefox, Alacritty available

### Current Architecture
```
NixOS System Modules:
├── modules/desktop/i3wm.nix (generates /etc/i3/config)
├── modules/desktop/xrdp.nix (multi-session XRDP)
└── configurations/hetzner-i3.nix (test config)

Home-Manager:
├── home-modules/terminal/tmux.nix (comprehensive tmux)
├── home-modules/tools/vscode.nix (full VS Code config)
└── All other user tools/configs
```

### Pain Points to Address
1. No scratchpad dropdown terminal
2. Basic status bar (default i3status)
3. No workspace organization/naming
4. Limited keybindings (missing vim-style navigation)
5. No application workspace assignments
6. Manual window management only

## Goals

### Primary Objectives
1. **Increase productivity** through better workspace management
2. **Reduce friction** in daily workflows (dropdown terminal, quick access)
3. **Improve aesthetics** without sacrificing performance
4. **Maintain reliability** - build on working foundation

### Non-Goals
- Don't break existing working setup
- Don't add unnecessary complexity
- Don't require GPU (headless QEMU/KVM server)
- Don't introduce heavy dependencies

## User Stories

### US1: Quick Terminal Access (Priority: P1)
**As a** developer
**I want** instant access to a dropdown terminal with tmux
**So that** I can run quick commands without switching workspaces

**Acceptance Criteria:**
- Press Win+grave → dropdown terminal appears
- Terminal is pre-loaded with tmux session
- Press Win+grave again → terminal hides
- Terminal persists in scratchpad (doesn't close)
- Works across all workspaces

### US2: Organized Workspace Management (Priority: P1)
**As a** user managing multiple tasks
**I want** named workspaces with assigned applications
**So that** I can organize my work by context

**Acceptance Criteria:**
- Workspaces have names (1:Term, 2:Code, 3:Web, etc.)
- Applications auto-assign to workspaces (VS Code → 2, Firefox → 3)
- Workspace switching is fast (<100ms)
- Names visible in status bar
- Can override auto-assignments

### US3: Vim-style Navigation (Priority: P2)
**As a** vim/tmux user
**I want** consistent hjkl navigation
**So that** I use muscle memory across all tools

**Acceptance Criteria:**
- Win+h/j/k/l moves focus between windows
- Win+Shift+h/j/k/l moves windows
- Works exactly like vim motion keys
- Doesn't conflict with application shortcuts

### US4: Better Status Bar (Priority: P2)
**As a** user
**I want** a informative, attractive status bar
**So that** I can see system info at a glance

**Acceptance Criteria:**
- Shows workspace names
- Shows system stats (CPU, memory, disk)
- Shows network status
- Shows date/time
- Lightweight (<10MB RAM)
- Configurable modules

### US5: Application Quick Launch (Priority: P3)
**As a** user
**I want** improved application launcher
**So that** I can find and launch apps quickly

**Acceptance Criteria:**
- Win+d opens launcher with search
- Shows icons and descriptions
- Fast fuzzy search
- Keyboard-driven
- Can launch any installed app

### US6: Smart Window Behavior (Priority: P3)
**As a** user
**I want** smart borders and gaps
**So that** my desktop looks clean

**Acceptance Criteria:**
- No borders when only one window
- Small borders (1-2px) with multiple windows
- Optional gaps between windows
- Gaps disabled when single window (smart_gaps)
- Can toggle gaps per workspace

## Technical Design

### Architecture Decision: Stay with NixOS Module

**Why not home-manager for now:**
- Current NixOS module works and is simple
- Faster iteration for testing
- Single-user system (no need for per-user configs yet)
- Can migrate to home-manager in Phase 2-3

**Migration path exists:**
```
Phase 1-2: Extend modules/desktop/i3wm.nix
Phase 3-4: Migrate to home-modules/desktop/i3.nix (home-manager)
```

### Key Technologies

**Status Bar**: i3status-rust
- Why: Native i3bar protocol, performant, good NixOS support
- Alternative: Polybar (more features, more complex)
- Fallback: Current i3status (minimal)

**Launcher**: Rofi
- Why: Universal in reviewed configs, better than dmenu
- Features: Apps, windows, ssh modes
- NixOS: Good package support

**Terminal**: Keep Alacritty
- Why: Already working well with XRDP
- Integration: Already configured in home-manager

**Compositor**: Skip for now
- Why: Adds complexity, not essential
- Consideration: Can add in Phase 3 if needed

### Configuration Structure

```nix
modules/desktop/i3wm.nix
├── Basic i3 configuration ✅
├── Keybindings
│   ├── Application launches ✅
│   ├── Window management (vim-style) 🎯
│   └── Scratchpad toggle 🎯
├── Workspaces
│   ├── Named workspaces 🎯
│   └── Application assignments 🎯
├── Appearance
│   ├── Colors 🎯
│   ├── Borders 🎯
│   └── Gaps 🎯
├── Status bar configuration 🎯
└── Startup commands 🎯

modules/desktop/i3status-rust.nix (NEW) 🎯
└── Status bar modules configuration
```

## Implementation Phases

### Phase 1: Essential Productivity (MVP)
**Goal**: Core productivity features that provide immediate value

**Features:**
1. Scratchpad dropdown terminal
2. Named workspaces (1:Term, 2:Code, 3:Web, 4:Comm)
3. Vim-style navigation (Win+hjkl)
4. Basic application assignments
5. i3status-rust status bar

**Estimated Effort**: 4-6 hours
**Success Metric**: Daily workflow 50% faster

### Phase 2: Enhanced Workflow
**Goal**: Polish and advanced features

**Features:**
1. Rofi launcher integration
2. Smart borders + gaps configuration
3. Workspace auto-back-and-forth
4. Custom modes (resize, system)
5. Additional scratchpad apps (calculator, notes)

**Estimated Effort**: 3-4 hours
**Success Metric**: Zero window manager friction

### Phase 3: Aesthetics & Polish
**Goal**: Make it beautiful and fully customized

**Features:**
1. Color scheme (Catppuccin or similar)
2. i3status-rust theming
3. Dunst notifications
4. Startup applications management
5. Dynamic workspace naming

**Estimated Effort**: 2-3 hours
**Success Metric**: Desktop looks professional

### Phase 4: Advanced Workflows (Optional)
**Goal**: Power-user features

**Features:**
1. Project-based workspace templates
2. tmux-tilish integration
3. Custom workflow scripts
4. Multi-monitor support (future hardware)

**Estimated Effort**: 4-5 hours
**Success Metric**: Fully automated workflows

## Detailed Feature Specifications

### Feature 1: Scratchpad Dropdown Terminal

**Implementation:**
```nix
# In modules/desktop/i3wm.nix

# Startup command
exec --no-startup-id alacritty --class dropdown_terminal -e tmux new-session -A -s dropdown

# Window rule
for_window [instance="dropdown_terminal"] move scratchpad, resize set 80ppt 60ppt, move position center

# Keybinding
bindsym $mod+grave [instance="dropdown_terminal"] scratchpad show
```

**Behavior:**
- Launches Alacritty with tmux session named "dropdown"
- Always centered, 80% width, 60% height
- Toggle with Win+grave
- Session persists between shows/hides

### Feature 2: Named Workspaces

**Implementation:**
```nix
# Define workspace names
set $ws1 "1:Term"
set $ws2 "2:Code"
set $ws3 "3:Web"
set $ws4 "4:Comm"
set $ws5 "5:Media"

# Workspace switching
bindsym $mod+1 workspace $ws1
bindsym $mod+2 workspace $ws2
# ... etc

# Move containers
bindsym $mod+Shift+1 move container to workspace $ws1
# ... etc
```

**Application Assignments:**
```nix
assign [class="Code"] $ws2
assign [class="firefox"] $ws3
assign [class="Slack"] $ws4
```

### Feature 3: Vim-style Navigation

**Implementation:**
```nix
# Focus windows
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

# Move windows
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right

# Keep arrow keys as alternative
bindsym $mod+Left focus left
# ... etc
```

### Feature 4: i3status-rust Status Bar

**New Module:** `modules/desktop/i3status-rust.nix`

```nix
{ config, lib, pkgs, ... }:

{
  config = {
    # Install i3status-rust
    environment.systemPackages = [ pkgs.i3status-rust ];

    # Generate config
    environment.etc."i3status-rust/config.toml".text = ''
      [theme]
      theme = "solarized-dark"

      [icons]
      icons = "awesome5"

      [[block]]
      block = "disk_space"
      path = "/"
      format = " $icon $available "

      [[block]]
      block = "memory"
      format = " $icon $mem_used_percents "

      [[block]]
      block = "cpu"
      format = " $icon $utilization "

      [[block]]
      block = "load"
      format = " $icon $1m "

      [[block]]
      block = "net"
      format = " $icon {$signal_strength $ssid|Wired} "

      [[block]]
      block = "time"
      format = " $icon $timestamp.datetime(f:'%a %m/%d %R') "
    '';
  };
}
```

**Integration in i3wm.nix:**
```nix
bar {
  status_command i3status-rs /etc/i3status-rust/config.toml
  position bottom
  # ... colors, etc
}
```

### Feature 5: Smart Borders & Gaps

**Implementation:**
```nix
# Borders
default_border pixel 2
default_floating_border pixel 2
hide_edge_borders smart

# Gaps (requires i3-gaps or i3 >=4.22)
gaps inner 5
gaps outer 5
smart_gaps on
smart_borders on

# Toggle gaps
bindsym $mod+g gaps inner current toggle 5
```

## Success Criteria

### Phase 1 Success Metrics
- [ ] Dropdown terminal responds in <100ms
- [ ] All 5 named workspaces configured
- [ ] Vim navigation works in all directions
- [ ] VS Code auto-assigns to workspace 2
- [ ] Firefox auto-assigns to workspace 3
- [ ] Status bar shows all configured modules
- [ ] No regressions (XRDP, tmux still work)

### Overall Success Criteria
- [ ] Daily workflow is measurably faster (subjective improvement)
- [ ] Zero window manager-related interruptions
- [ ] Configuration is maintainable (declarative, documented)
- [ ] Can reproduce on fresh system (all in NixOS config)
- [ ] Works reliably across RDP reconnections

## Risks & Mitigations

### Risk 1: Breaking Current Setup
**Mitigation**:
- Test in separate branch first
- Keep hetzner-i3 as test config
- Deploy to production (hetzner.nix) only after validation

### Risk 2: Performance Degradation
**Mitigation**:
- Use lightweight tools (i3status-rust vs Polybar)
- Skip compositor in Phase 1
- Monitor resource usage

### Risk 3: XRDP Compatibility Issues
**Mitigation**:
- Test all features via RDP
- Ensure scratchpad works with XRDP
- Validate multi-client still works

### Risk 4: Configuration Complexity
**Mitigation**:
- Keep it simple in Phase 1
- Document all changes
- Use lib.mkDefault for overrideable options

## Testing Strategy

### Manual Testing Checklist (Phase 1)
- [ ] Scratchpad terminal toggles with Win+grave
- [ ] Tmux session persists in dropdown
- [ ] Workspace names show in status bar
- [ ] Win+1-5 switches to named workspaces
- [ ] Win+hjkl moves focus correctly
- [ ] VS Code launches in workspace 2
- [ ] Firefox launches in workspace 3
- [ ] Status bar shows all modules
- [ ] Multi-client RDP still works
- [ ] Can disconnect/reconnect without issues

### Regression Testing
- [ ] Basic i3 functionality (before this feature)
- [ ] XRDP multi-client (before this feature)
- [ ] tmux integration (before this feature)
- [ ] VS Code keybinding (Win+C)
- [ ] Firefox keybinding (Win+B)

## Documentation Updates

### Files to Update
- [ ] `/etc/nixos/CLAUDE.md` - Add new keybindings and features
- [ ] `/etc/nixos/specs/006-productivity-i3-config/quickstart.md` - User guide
- [ ] Module comments in i3wm.nix - Inline documentation

### Quickstart Content
- Keyboard shortcuts cheatsheet
- Workspace workflow examples
- Scratchpad usage tips
- Troubleshooting common issues

## Dependencies

### Required Packages (already available)
- i3 (current)
- alacritty (current)
- tmux (current)

### New Packages (Phase 1)
- i3status-rust
- rofi (optional, recommended)

### New Packages (Phase 2+)
- dunst (notifications)
- picom (compositor, optional)

## Migration Path

### From Current State (005) → Phase 1 (006)
1. Create new branch: `006-productivity-i3-config`
2. Extend `modules/desktop/i3wm.nix` with new features
3. Test on hetzner-i3 configuration
4. Validate all features work
5. Document changes
6. Deploy to main hetzner configuration

### Future: NixOS Module → home-manager
```
Phase 1-2: Extend NixOS module
           └─ Fast iteration, proven working

Phase 3: Migrate to home-manager
         └─ home-modules/desktop/i3.nix
         └─ More flexibility, per-user config
         └─ Better dotfiles management
```

## References

- Research document: `specs/006-productivity-i3-config/research.md`
- Base implementation: `specs/005-research-a-more/` (completed)
- i3 User Guide: https://i3wm.org/docs/userguide.html
- i3status-rust: https://github.com/greshake/i3status-rust
- home-manager i3 options: https://nix-community.github.io/home-manager/options.html

## Approval & Sign-off

**Specification Status**: ✅ Complete, Ready for Implementation
**Next Step**: Create implementation plan (`plan.md`)
**Estimated Total Effort**: 13-18 hours across 4 phases
**Priority**: Phase 1 (MVP) - High Priority

---

*Specification prepared: 2025-10-16*
*Based on successful 005-research-a-more implementation*
*Ready for `/speckit.plan` to generate implementation plan*
