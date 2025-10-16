# Research: Productivity-Focused i3wm Configuration

## Research Date: 2025-10-16

## Executive Summary

Based on research of popular i3wm configurations and NixOS implementations, we've identified key patterns and features that make i3wm highly productive for developers, especially when integrated with tmux and focused on workspace-based workflows.

## Key Findings

### 1. Popular i3wm Configuration Patterns

#### Status Bars
- **Polybar**: Most popular modern status bar replacement
  - Highly customizable with modules
  - Better aesthetics than default i3bar
  - Large community with scripts collection
- **i3status-rust**: Async, performant alternative written in Rust
  - Native performance
  - Rich module ecosystem
  - Better for resource-constrained environments

#### Terminal Integration
- **Dropdown/Scratchpad Terminal**: Universal pattern across all reviewed configs
  - Terminal with tmux pre-loaded in scratchpad
  - Quick toggle with keybinding (commonly `Win+grave`)
  - Serves as command palette alternative
- **Default Terminal**: Alacritty or Kitty most common
  - GPU-accelerated
  - Fast startup
  - Good tmux compatibility

### 2. tmux + i3 Integration Best Practices

#### Seamless Workflows
- **tmux-tilish**: Plugin making tmux feel like i3wm
  - Consistent keybindings between tmux and i3
  - Reduces context switching
  - Ideal for remote sessions
- **i3tmux**: Manages tmux panes as i3 windows
  - Unified workflow
  - Single mental model

#### Configuration Patterns
```
i3 Workspaces (10 virtual desktops)
  ↓
Each workspace contains applications
  ↓
Terminal applications run tmux sessions
  ↓
tmux provides terminal multiplexing within i3 windows
```

**Key Insight**: i3 manages GUI layout, tmux manages terminal layout. Don't fight this - embrace it.

### 3. Workspace Management Strategies

#### Common Patterns (from reviewed configs)
1. **Role-Based Workspaces** (Most Common)
   ```
   1: Main/Terminal
   2: Code (IDE/Editors)
   3: Web (Browsers)
   4: Communication (Slack/Email)
   5: Music/Media
   6-10: Dynamic/Project-specific
   ```

2. **Project-Based Workspaces**
   - Each project gets dedicated workspace(s)
   - Use workspace naming: `1:ProjectA`, `2:ProjectB`
   - Better for context isolation

3. **Activity-Based Workspaces**
   - Design/Mockups
   - Development
   - Testing/QA
   - Documentation
   - Meetings/Collaboration

#### Productivity Features
- **Workspace Auto-Back-And-Forth**: Toggle between current and previous workspace
- **Workspace Assignments**: Auto-assign applications to workspaces
- **Workspace Persistence**: Named workspaces survive reboots
- **Workspace Renaming**: Dynamic workspace naming based on content

### 4. Scratchpad Workflows

#### What is Scratchpad?
Hidden floating workspace for quick-access applications. Press keybinding → window appears centered and floating. Press again → window disappears back to scratchpad.

#### Common Scratchpad Uses
1. **Dropdown Terminal** (Most Popular)
   - Terminal with tmux session
   - Quick command execution
   - System monitoring (htop, btop)

2. **Calculator** (xcalc, gnome-calculator)
   - Quick math without disrupting workflow

3. **Notes/Scratch Pad** (gVim, nvim in floating terminal)
   - Quick note taking
   - Code snippets
   - TODO lists

4. **Music Player** (ncmpcpp, cmus)
   - Control music without switching workspace

5. **Password Manager** (1Password mini, keepassxc)
   - Quick password lookup

#### Implementation Pattern
```nix
# Startup commands
for_window [instance="dropdown_terminal"] move scratchpad
exec --no-startup-id alacritty --class dropdown_terminal -e tmux

# Keybinding
bindsym $mod+grave [instance="dropdown_terminal"] scratchpad show
```

### 5. Keybinding Philosophy

#### Common Modifier Key Choices
- **Win/Super (Mod4)**: Most popular (doesn't conflict with apps)
- **Alt (Mod1)**: Alternative, but conflicts with many applications

#### Standard Keybinding Categories
1. **Navigation**: Mod+Arrows, Mod+hjkl
2. **Window Management**: Mod+Shift+[key]
3. **Workspaces**: Mod+[1-9], Mod+Shift+[1-9]
4. **Applications**: Mod+[letter] (c=code, b=browser, etc.)
5. **System**: Mod+Shift+[e/r/q] (exit, reload, quit)
6. **Modes**: Mod+r (resize), Mod+x (system menu)

#### Reviewed Configurations Use Vim-style hjkl
- h: left
- j: down
- k: up
- l: right

**Benefits**: Same muscle memory as vim/tmux/many CLI tools

### 6. Appearance & Theming

#### Color Schemes
- **Catppuccin**: Most trending (2024-2025)
- **Dracula**: Classic, widely supported
- **Nord**: Minimal, professional
- **Gruvbox**: Retro, warm colors
- **Tokyo Night**: Modern, popular with developers

#### Window Decorations
- **No Borders** on single window (smart_borders)
- **Minimal borders** when multiple windows (1-2px)
- **No title bars** (relies on status bar for window info)

#### Gaps (i3-gaps)
- **Inner gaps**: 5-10px between windows
- **Outer gaps**: 5-10px from screen edges
- **Smart gaps**: Disabled when only one window
- **Gaps modes**: Toggle gaps on/off per workspace

### 7. NixOS Home-Manager Integration

#### Official home-manager i3 Module

**Module Path**: `xsession.windowManager.i3`

**Key Options**:
- `config.keybindings`: Declarative keybinding management
- `config.modes`: Define modes (resize, system, etc.)
- `config.startup`: Startup commands
- `config.bars`: Status bar configuration
- `config.colors`: Color scheme
- `config.gaps`: Gap configuration
- `config.window`: Window behavior
- `config.assigns`: Workspace assignments
- `extraConfig`: Escape hatch for advanced configs

#### Example NixOS Configurations Reviewed
1. **Th0rgal/horus-nix-home**
   - Full i3 + polybar + personal apps
   - All declarative in Nix
   - Good example of home-manager integration

2. **srid/nix-config**
   - Minimal, clean i3 config
   - Focus on essential features
   - Good starting point

3. **Various i3wm-config repos** (100+ stars)
   - Most use traditional config files
   - Some converted to Nix
   - Highlight common patterns

### 8. Status Bar Configuration

#### Polybar (Recommended for Aesthetics)
**Pros**:
- Highly customizable appearance
- Large module collection
- Active community
- Material icons support

**Cons**:
- More complex configuration
- Not native to i3
- Higher resource usage

#### i3status-rust (Recommended for Performance)
**Pros**:
- Native i3bar protocol
- Async, performant
- Written in Rust
- Simple configuration
- Good NixOS support

**Cons**:
- Less visually impressive than Polybar
- Smaller community

#### i3bar + i3status (Default, Minimal)
**Pros**:
- Zero config needed
- Lightweight
- Always works
- Part of i3

**Cons**:
- Basic appearance
- Limited customization
- No icons/colors by default

### 9. Application Integration

#### Rofi (Application Launcher)
- Replaces dmenu
- Better UI/UX
- Multiple modes (apps, windows, ssh, etc.)
- Themeable
- **Universal across reviewed configs**

#### Dunst (Notifications)
- Lightweight notification daemon
- Configurable appearance
- Keyboard-driven interaction
- Works well with i3

#### Picom (Compositor)
- Window transparency
- Shadows, blur effects
- Fade animations
- **Optional**: Many skip for performance

### 10. Productivity Workflows

#### Pattern 1: Developer Workflow
```
Workspace 1: tmux (multiple terminals)
  ├─ pane 0: project shell
  ├─ pane 1: logs/monitoring
  └─ pane 2: git operations

Workspace 2: VS Code (main editor)
  └─ Integrated terminal disabled (use workspace 1)

Workspace 3: Firefox (documentation/research)
  ├─ Window 1: Project docs
  └─ Window 2: Stack Overflow, etc.

Workspace 4: Communication
  ├─ Slack
  └─ Email

Scratchpad: Dropdown terminal with tmux
  └─ Quick commands, system monitoring
```

#### Pattern 2: Remote-First Workflow (Your Use Case)
```
Local Machine (Surface/MacBook)
  ↓ RDP (XRDP)
Remote Server (Hetzner i3wm)
  ├─ Workspace 1: tmux terminal
  ├─ Workspace 2: VS Code (remote)
  ├─ Workspace 3: Firefox
  └─ Scratchpad: dropdown terminal

Benefits:
- All processing on server
- Consistent environment across devices
- Can disconnect/reconnect without losing state
- tmux provides terminal persistence
- i3 provides GUI persistence
```

## Recommendations for Your Configuration

### Phase 1: Essential Features (MVP)
✅ Already Implemented:
- [x] Basic i3wm setup
- [x] XRDP integration
- [x] Multi-client support
- [x] Quick launch keys (Win+C, Win+B)
- [x] tmux integration (already configured)

🎯 Next Priority:
- [ ] Scratchpad dropdown terminal
- [ ] Improved status bar (i3status-rust)
- [ ] Workspace configuration (named workspaces)
- [ ] Better keybindings (vim-style navigation)
- [ ] Application assignments to workspaces

### Phase 2: Productivity Enhancements
- [ ] Rofi with custom modes
- [ ] Window gaps (i3-gaps features)
- [ ] Smart borders
- [ ] Workspace auto-back-and-forth
- [ ] Multiple monitors support (for future)

### Phase 3: Polish & Customization
- [ ] Color scheme (suggest Catppuccin)
- [ ] Custom modes (resize, system, etc.)
- [ ] Startup applications
- [ ] Dunst notifications
- [ ] Compositor (optional)

### Phase 4: Advanced Workflows
- [ ] Project-based workspace templates
- [ ] Dynamic workspace naming
- [ ] tmux-tilish integration
- [ ] Custom scripts for workflow automation

## Key Design Decisions

### 1. Status Bar Choice
**Recommendation**: i3status-rust
- Native i3bar protocol (no external process)
- NixOS has good support
- Lightweight and performant
- Can upgrade to Polybar later if needed

### 2. Terminal Strategy
**Recommendation**: Keep current Alacritty + tmux
- You already have comprehensive tmux config
- Alacritty works well with XRDP
- Add scratchpad dropdown for quick access

### 3. Keybinding Strategy
**Recommendation**: Vim-style with Win modifier
- Win+hjkl for navigation (consistent with vim/tmux)
- Win+C/B/Return for applications
- Win+grave for scratchpad dropdown
- Win+Shift for window movement

### 4. Workspace Strategy
**Recommendation**: Hybrid approach
```
1: Main (Terminal/tmux)
2: Code (VS Code, editors)
3: Web (Firefox, browsers)
4: Comm (Slack, email if used)
5-10: Dynamic (project-specific)
```

### 5. Configuration Management
**Recommendation**: Migrate to home-manager i3 module
- Currently using NixOS module (`modules/desktop/i3wm.nix`)
- Migrate to home-manager for per-user customization
- Allows different configs per machine
- Better integration with dotfiles

## Architecture Comparison

### Current Approach (NixOS Module)
```
/etc/nixos/modules/desktop/i3wm.nix
  └─ Generates /etc/i3/config
     └─ System-wide config
        └─ Same for all users
```

**Pros**:
- Simple
- Works for single-user
- Easy to manage with rest of system config

**Cons**:
- Can't customize per-user
- Requires rebuild for changes
- Not portable across machines

### Recommended Approach (home-manager)
```
/etc/nixos/home-modules/desktop/i3.nix
  └─ xsession.windowManager.i3
     └─ config.keybindings = { ... }
     └─ config.bars = [ ... ]
     └─ config.startup = [ ... ]
```

**Pros**:
- Per-user customization
- Can sync across machines
- Faster iteration (no system rebuild)
- Better for dotfiles management

**Cons**:
- More complex initially
- Requires home-manager setup
- Learning curve for Nix expressions

## Implementation Strategy

### Option A: Extend Current NixOS Module (Faster)
- Build on existing `modules/desktop/i3wm.nix`
- Add features incrementally
- Good for MVP/testing
- Migrate to home-manager later

### Option B: Migrate to home-manager Now (Better Long-term)
- Create `home-modules/desktop/i3.nix`
- Full declarative config
- Better architecture
- More work upfront

**Recommendation**: Start with Option A, migrate to Option B in Phase 2-3

## References

### Documentation
- [i3 User's Guide](https://i3wm.org/docs/userguide.html)
- [i3 FAQ](https://faq.i3wm.org/)
- [home-manager i3 options](https://nix-community.github.io/home-manager/options.html#opt-xsession.windowManager.i3.enable)
- [NixOS Wiki: i3](https://nixos.wiki/wiki/I3)

### Repositories Referenced
- https://github.com/nix-community/home-manager (official module)
- https://github.com/Th0rgal/horus-nix-home (full example)
- https://github.com/jabirali/tmux-tilish (tmux integration)
- https://github.com/andreatulimiero/i3tmux (seamless tmux)
- https://github.com/abdes/arch-i3-polybar-dotfiles-autosetup (reference config)

### Tools Mentioned
- **Status Bars**: Polybar, i3status-rust, i3status
- **Launchers**: Rofi, dmenu
- **Terminals**: Alacritty, Kitty, urxvt
- **Notifications**: Dunst
- **Compositor**: Picom
- **tmux Plugins**: tmux-tilish, tmux-resurrect, tmux-continuum

## Next Steps

1. ✅ **Research Complete**: Compiled comprehensive findings
2. 🎯 **Create Feature Spec**: Based on research findings
3. 📋 **Plan Implementation**: Break down into phases
4. 🔧 **Start Development**: Begin with Phase 1 MVP features

## Conclusion

The research shows clear patterns in successful i3wm configurations:

1. **Workspace-centric workflows** are universal
2. **tmux integration** is essential for terminal users
3. **Scratchpad dropdown terminal** appears in almost every config
4. **Vim-style keybindings** provide consistency
5. **Minimalist appearance** with smart borders and optional gaps
6. **home-manager** is the preferred NixOS approach

Your current setup (i3wm + XRDP + tmux) aligns perfectly with best practices. The next phase should focus on:
- Scratchpad workflows
- Better status bar
- Workspace management
- Vim-style keybindings
- Application assignments

This will transform your current working MVP into a productivity powerhouse while maintaining the simplicity and reliability you've already achieved.
