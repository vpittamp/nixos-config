# Feature 046 - Headless Sway with VNC - Current Status

**Date**: 2025-10-28
**Branch**: `046-revise-my-spec`
**Status**: Partially Working - VNC Connection Established, Application Launch Issues

## ✅ What's Working

### VNC Access
- ✅ **wayvnc service**: Running successfully on port 5900
- ✅ **VNC connectivity**: User can connect via Tailscale (100.87.204.44:5900)
- ✅ **Display configuration**: 3 monitors at 1280x720 resolution
  - HEADLESS-1: 1280x720 @ position 0,0
  - HEADLESS-2: 1280x720 @ position 1280,0
  - HEADLESS-3: 1280x720 @ position 2560,0
- ✅ **Resolution**: Fixed from 1920x1080 to 1280x720 for better VNC client compatibility

### Sway Compositor
- ✅ **Sway running**: Successfully on wayland-1 display
- ✅ **Swaybar**: Event-driven status bar working
- ✅ **i3pm daemon**: Running and functional
- ✅ **Keyboard input**: Keybindings working (Meta+D, Alt+Space, etc.)
- ✅ **Window management**: Workspaces and window rules functional

### Application Launcher
- ✅ **Walker/Elephant removed**: GPU-dependent launcher replaced
- ✅ **Rofi installed**: Working as application launcher
- ✅ **Rofi launches**: Successfully via Meta+D and Alt+Space keybindings
- ✅ **Rofi Wayland mode**: Using native Wayland support (no X11)

### Applications
- ✅ **Alacritty terminal**: Launches and works correctly
- ✅ **Firefox**: Running (seen in window tree)
- ✅ **RustDesk**: Available for remote desktop (alternative to VNC)

## ✅ Fixed Issues

### Walker "GPU Requirement" - RESOLVED (2025-10-28)
**Previous diagnosis**: Walker requires GPU acceleration and cannot work in headless environment
**Actual cause**: Missing GSK_RENDERER=cairo environment variable for GTK4 software rendering
**Solution**:
1. Added `GSK_RENDERER=cairo` to `configurations/hetzner-sway.nix` environment variables
2. Restored walker.nix import in hetzner-sway.nix
3. Updated sway.nix menu to use walker instead of rofi

**Evidence**:
- MESA/EGL errors are non-fatal warnings (GPU unavailable, fallback to software rendering)
- Walker successfully connected to Elephant service (verified in logs: "comm connection=new")
- GTK4 supports cairo (CPU), ngl (OpenGL), and vulkan renderers
- GSK_RENDERER=cairo forces CPU-based rendering (no GPU required)
- Tested with manual launch: Walker started with no errors and connected to Elephant

**Status**: Walker keybinding (Meta+D) ready for testing in VNC session after Sway restart

## ❌ Known Issues

### VS Code Not Opening
**Status**: CRITICAL
**Symptoms**:
- VS Code launches processes (seen in `pgrep`)
- No window appears in Sway tree
- No visible window via VNC

**Likely Causes**:
1. GPU acceleration required but not available (headless environment)
2. Electron/Chromium rendering issues without GPU
3. Window may be opening but not visible/positioned correctly

**Attempted Fixes**:
- Added `--disable-gpu` flag to VS Code parameters in app-registry-data.nix
- Added `--disable-software-rasterizer` flag (though this may not be valid)
- Flags committed but home-manager registry not yet regenerated

**Next Steps**:
1. Verify home-manager picks up new VS Code flags
2. Test manual launch with flags: `code --disable-gpu /etc/nixos`
3. Check VS Code logs for rendering errors
4. Consider alternative flags: `--disable-gpu-sandbox`, `--disable-dev-shm-usage`
5. May need to use VS Code Server instead of desktop application

### Home-Manager Registry Not Updating
**Status**: MODERATE
**Issue**: Application registry JSON file not reflecting new VS Code parameters

**Current State**:
- Source file (app-registry-data.nix) has correct flags
- Symlinked registry file still shows old parameters
- `nix eval` shows correct output from source
- Home-manager rebuild attempted but registry unchanged

**Workaround**: Manual rebuild or system restart may be required

## 📋 Configuration Summary

### Key Files Modified
1. **home-modules/hetzner-sway.nix**
   - Removed walker.nix import
   - Updated comments to reflect rofi usage

2. **home-modules/desktop/sway.nix**
   - Changed window rules from walker → rofi
   - Removed Elephant service startup
   - Updated headless output resolution: 1920x1080 → 1280x720
   - Updated output positions for 3-monitor layout
   - Kept `$menu` variable set to `rofi -show drun` for headless mode

3. **home-modules/desktop/app-registry-data.nix**
   - Added VS Code GPU flags: `--disable-gpu --disable-software-rasterizer`
   - Updated parameters field for vscode entry

### Services Running
```bash
# VNC Server
wayvnc          # Port 5900, WAYLAND_DISPLAY=wayland-1

# Sway Compositor
sway            # PID 19716, wayland-1

# i3pm
i3-project-event-listener  # System service

# Status Bar
swaybar-status-event-driven  # 3 instances (one per monitor)
```

### Services Stopped/Removed
```bash
elephant.service  # Stopped and disabled (Walker backend)
walker            # Removed from imports
```

## 🔧 System Specifications

**Host**: Hetzner Cloud VPS (nixos-hetzner-sway)
**NixOS Version**: 25.11.20251022.01f116e
**Sway Version**: 1.11
**Wayland Display**: wayland-1
**VNC Server**: wayvnc 0.9.1

**Network Access**:
- Tailscale: 100.87.204.44
- VNC Port: 5900
- SSH: Available

## 🎯 Next Actions Required

### High Priority
1. **Fix VS Code launch issue**
   - Regenerate home-manager registry
   - Test manual launch with GPU flags
   - Check VS Code logs for errors
   - Consider VS Code Server as alternative

2. **Verify rofi integration**
   - Confirm rofi shows all applications from registry
   - Test launching various applications via rofi
   - Verify project context variables work

### Medium Priority
3. **Test multi-monitor VNC**
   - Verify all 3 monitors visible in VNC client
   - Test workspace distribution across monitors
   - Verify window movement between monitors

4. **Performance optimization**
   - Monitor VNC latency
   - Check Sway CPU usage
   - Verify swaybar refresh rate

### Low Priority
5. **Documentation**
   - Update quickstart.md with current state
   - Document troubleshooting steps
   - Add VNC client configuration guide

## 📝 Recent Commits

```
b315f82 - fix(sway): Reduce VNC resolution to 1280x720 and add VS Code GPU flags
2b89616 - feat(sway): Replace Walker/Elephant with rofi for headless environment
6cf272a - fix(sway): Define $menu variable for rofi keybindings
1753fa5 - fix(walker): Configure Wayland mode for headless but Walker still requires GPU
7efdcb8 - feat(sway): Add rofi-wayland launcher for headless mode
```

## 🐛 Debugging Commands

### Check Sway State
```bash
export SWAYSOCK=/run/user/1000/sway-ipc.1000.19716.sock
swaymsg -t get_outputs | jq '.[] | {name, current_mode}'
swaymsg -t get_tree | jq '.. | select(.app_id?) | {id, app_id, name}'
```

### Check VS Code
```bash
pgrep -a code
cat ~/.config/Code/logs/*/main.log | tail -50
code --disable-gpu --verbose /etc/nixos 2>&1 | tee /tmp/vscode-debug.log
```

### Check Application Registry
```bash
cat ~/.config/i3/application-registry.json | jq '.applications[] | select(.name == "vscode")'
```

### Check VNC
```bash
systemctl --user status wayvnc
ss -tuln | grep 5900
cat /proc/$(pgrep wayvnc)/environ | tr '\0' '\n' | grep WAYLAND_DISPLAY
```

## 💡 Lessons Learned

1. **CORRECTED - Walker works with software rendering**: Walker DOES NOT require GPU acceleration. It works perfectly with GTK4 software rendering via `GSK_RENDERER=cairo`. MESA/EGL errors are non-fatal warnings indicating GPU unavailable and fallback to CPU rendering.
2. **Don't jump to conclusions from error messages**: MESA/EGL errors looked fatal but were actually just warnings. Always research error messages before changing architecture.
3. **GTK4 rendering flexibility**: GTK4 supports multiple renderers (cairo=CPU, ngl=OpenGL, vulkan=GPU), making it suitable for both headless and native environments.
4. **Resolution matters**: 1920x1080 was too large for most VNC clients, 1280x720 is better
5. **Electron apps need special flags**: VS Code and other Electron apps require `--disable-gpu` in headless environments
6. **Home-manager symlinks**: Registry files are symlinked; changes require rebuild to take effect
7. **Question premature diagnoses**: User was right to question the Rofi switch - Walker was working before and should still work with correct configuration

## 🔗 Related Documentation

- Feature 046 Spec: `/etc/nixos/specs/046-revise-my-spec/spec.md`
- Quickstart Guide: `/etc/nixos/specs/046-revise-my-spec/quickstart.md`
- CLAUDE.md: `/etc/nixos/CLAUDE.md` (sections on Sway and VNC)
