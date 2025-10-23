# Window Class Identification Tasks

**Generated**: 2025-10-23 14:15:14
**Feature**: 030-review-our-i3pm
**Phase**: Phase 2 - Foundational Infrastructure (Deferred)

## Overview

These 44 applications require WM class identification before they can be properly managed by i3pm.

## Process

For each application:
1. Launch the application
2. Run `i3pm windows` or `xprop` to identify the WM_CLASS
3. Update the pattern in window-rules.json
4. Add to app-classes.json scoped/global list
5. Test with `i3pm rules classify --class <WM_CLASS>`

## Applications Needing Identification

Total: 44 apps

- [ ] **WS17**: Identify WM class for `ARandR` (exec: `arandr`)
- [ ] **WS18**: Identify WM class for `Bulk Rename` (exec: `thunar`)
- [ ] **WS19**: Identify WM class for `GVim` (exec: `gvim`)
- [ ] **WS20**: Identify WM class for `GitKraken` (exec: `gitkraken-wrapper`)
- [ ] **WS21**: Identify WM class for `GitKraken Desktop` (exec: `gitkraken`)
- [ ] **WS23**: Identify WM class for `Hetzner Cloud` (exec: `firefox`)
- [ ] **WS24**: Identify WM class for `Htop` (exec: `htop`)
- [ ] **WS25**: Identify WM class for `K9s` (exec: `konsole`)
- [ ] **WS27**: Identify WM class for `Launch without taking a screenshot` (exec: `spectacle`)
- [ ] **WS28**: Identify WM class for `Lazydocker` (exec: `ghostty`)
- [ ] **WS30**: Identify WM class for `Neovim` (exec: `nvim`)
- [ ] **WS34**: Identify WM class for `NixOS Manual` (exec: `nixos-help`)
- [ ] **WS35**: Identify WM class for `Open a New Window` (exec: `rustdesk`)
- [ ] **WS38**: Identify WM class for `Removable Drives and Media` (exec: `thunar-volman-settings`)
- [ ] **WS39**: Identify WM class for `Rofi` (exec: `rofi`)
- [ ] **WS40**: Identify WM class for `Rofi Theme Selector` (exec: `rofi-theme-selector`)
- [ ] **WS41**: Identify WM class for `Thunar Preferences` (exec: `thunar-settings`)
- [ ] **WS42**: Identify WM class for `Trash` (exec: `thunar`)
- [ ] **WS43**: Identify WM class for `Vim` (exec: `vim`)
- [ ] **WS44**: Identify WM class for `Volume Control` (exec: `pavucontrol`)
- [ ] **WS46**: Identify WM class for `Yazi` (exec: `ghostty`)
- [ ] **WS47**: Identify WM class for `Yazi` (exec: `yazi`)
- [ ] **WS48**: Identify WM class for `Yazi (Select Directory)` (exec: `ghostty`)
- [ ] **WS50**: Identify WM class for `btop++` (exec: `btop`)
- [ ] **WS51**: Identify WM class for `lf` (exec: `lf`)
- [ ] **WS52**: Identify WM class for `ranger` (exec: `ranger`)
- [ ] **WS53**: Identify WM class for `Btop` (exec: `btop`)
- [ ] **WS54**: Identify WM class for `Cargo` (exec: `cargo`)
- [ ] **WS55**: Identify WM class for `Deno` (exec: `deno`)
- [ ] **WS56**: Identify WM class for `Docker` (exec: `docker`)
- [ ] **WS57**: Identify WM class for `Gh` (exec: `gh`)
- [ ] **WS58**: Identify WM class for `Git` (exec: `git`)
- [ ] **WS59**: Identify WM class for `K9s` (exec: `k9s`)
- [ ] **WS60**: Identify WM class for `Kubectl` (exec: `kubectl`)
- [ ] **WS61**: Identify WM class for `Lazygit` (exec: `lazygit`)
- [ ] **WS62**: Identify WM class for `Nano` (exec: `nano`)
- [ ] **WS63**: Identify WM class for `Ncdu` (exec: `ncdu`)
- [ ] **WS64**: Identify WM class for `Node` (exec: `node`)
- [ ] **WS65**: Identify WM class for `Npm` (exec: `npm`)
- [ ] **WS66**: Identify WM class for `Nvim` (exec: `nvim`)
- [ ] **WS67**: Identify WM class for `Python` (exec: `python`)
- [ ] **WS68**: Identify WM class for `Ranger` (exec: `ranger`)
- [ ] **WS69**: Identify WM class for `Tmux` (exec: `tmux`)
- [ ] **WS70**: Identify WM class for `Yarn` (exec: `yarn`)

## Quick Identification Commands

```bash
# Method 1: Use i3pm windows (when app is running)
i3pm windows | grep -i "app-name"

# Method 2: Use xprop (click on window)
xprop | grep WM_CLASS

# Method 3: Use i3-msg (get all windows)
i3-msg -t get_tree | jq '.. | select(.window_properties?) | {name: .name, class: .window_properties.class}'
```

## Priority Groups

### High Priority (Development Tools)
- GitKraken, GVim, Neovim, Lazydocker, RustDesk

### Medium Priority (System Tools)  
- ARandR, Htop, pavucontrol (Volume Control), spectacle

### Low Priority (Utilities)
- Rofi, Thunar utilities, Bulk Rename

## Notes

- PWAs already have WM classes (FFPWA-* pattern)
- Terminal apps (ghostty/alacritty wrappers) may need title-based patterns
- Some apps may need `title:` patterns instead of class-based patterns
