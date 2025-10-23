# Workspace Mapping Summary

**Generated**: 2025-10-23
**Feature**: 030-review-our-i3pm
**Status**: Configuration Installed

## Overview

Created comprehensive 1:1 workspace mapping for all applications on the system, organized by type and functionality.

## Statistics

- **Total Applications**: 70 unique applications
- **Workspace Range**: WS1 - WS70
- **Configuration Files Updated**:
  - `~/.config/i3/window-rules.json`: 26 rules (with WM classes)
  - `~/.config/i3/app-classes.json`: 3 scoped, 21 global classes
- **Deferred WM Class Identification**: 44 applications

## Application Categories

### GUI Applications (52 apps)
- **Terminals**: Alacritty, Ghostty, XTerm
- **Editors/IDEs**: VS Code, Vim, GVim, Neovim
- **Browsers**: Firefox, Chromium
- **Dev Tools**: Postman, GitKraken, 1Password, Headlamp
- **File Managers**: Thunar, Yazi, Ranger, lf
- **System Tools**: btop++, Htop, ARandR, pavucontrol, spectacle
- **Remote**: RustDesk

### PWA Applications (14 apps)
- **Cloud Platforms**: Azure Portal, Hetzner Cloud (x2)
- **Development**: GitHub Codespaces, ArgoCD, Kargo, Backstage, Gitea
- **Kubernetes**: Headlamp
- **AI Tools**: Google AI, ChatGPT Codex
- **Misc**: Home Assistant, YouTube, Uber Eats, Tailscale

### Terminal-Based Applications (21 apps)
- **DevOps**: K9s, Kubectl, Docker, Lazydocker
- **Version Control**: Git, Gh, Lazygit
- **Editors**: Vim, Nvim, Nano
- **File Managers**: Yazi, Ranger
- **Monitors**: Btop, Htop
- **Languages**: Python, Node, Deno, Cargo, Npm, Yarn
- **Utilities**: Tmux, Ncdu

## Scope Distribution

### Scoped Applications (Project-Specific)
Applications that are hidden when switching projects:
- Terminal emulators
- Code editors
- File managers
- Git tools
- DevOps tools
- Language/build tools

### Global Applications (Always Visible)
Applications that remain visible across all projects:
- Web browsers
- PWAs (all)
- System utilities
- Productivity tools
- Cloud platforms

## Workspace Organization

```
Workspaces 1-1: Core Terminals
Workspaces 2-15: PWA Applications
Workspaces 16-52: GUI Applications
Workspaces 53-70: Terminal Applications
```

## Files Changed

### ~/.config/i3/window-rules.json
- **Before**: 9 rules
- **After**: 26 rules (+17 new applications)
- **Backup**: `window-rules.json.backup-20251023-141542`

### ~/.config/i3/app-classes.json
- **Before**: 7 scoped, 4 global
- **After**: 3 scoped, 21 global
- **Backup**: `app-classes.json.backup-20251023-141542`

## Next Steps

### Phase 2 Tasks (Deferred)
See `deferred-wm-class-identification.md` for 44 applications that need WM class identification.

**Quick Identification Process**:
```bash
# Launch the application
<command>

# Identify WM class
i3pm windows | grep -i "app-name"
# OR
xprop | grep WM_CLASS  # (then click window)

# Update configuration
vi ~/.config/i3/window-rules.json
vi ~/.config/i3/app-classes.json

# Reload daemon
systemctl --user restart i3-project-event-listener

# Test
i3pm rules classify --class <WM_CLASS>
```

### Priority Applications for WM Class ID
1. **High**: GitKraken, GVim, Neovim, Lazydocker, RustDesk
2. **Medium**: ARandR, Htop, pavucontrol, spectacle
3. **Low**: Rofi utilities, Thunar utilities

## Testing

After reloading the daemon, test the configuration:

```bash
# Reload daemon
systemctl --user restart i3-project-event-listener

# View current rules
i3pm rules list

# Test window classification
i3pm rules classify --class <WM_CLASS>

# Validate all rules
i3pm rules validate

# Check workspace assignments
i3pm windows
```

## Notes

- Terminal apps (like lazygit, k9s) launched via ghostty need title-based patterns
- Some applications may need `title:^pattern` instead of class-based patterns
- PWA apps use WM class pattern `FFPWA-<ID>`
- Duplicate apps (e.g., multiple "Yazi") were consolidated based on exec command
