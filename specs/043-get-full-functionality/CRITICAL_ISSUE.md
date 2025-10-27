# CRITICAL ISSUE: Walker Stack Overflow Crash

**Date**: 2025-10-27 17:03
**Environment**: Hetzner XRDP session
**Severity**: BLOCKER

## Issue Description

Walker 2.6.4 crashes immediately with a stack overflow error when launched via command line:

```
env GDK_BACKEND=x11 walker &
```

### Error Output
```
MESA: info: could not get caps: Function not implemented
connecting to elephant...
waiting for elephant to start...
connected.

thread 'main' has overflowed its stack
fatal runtime error: stack overflow, aborting
Aborted (core dumped)
```

## Environment Details

- **Walker Version**: 2.6.4
- **Elephant Version**: 2.6.4
- **Elephant Status**: Active (running) - no errors
- **DISPLAY**: :10.0
- **Desktop Environment**: i3wm + XRDP
- **All Providers Enabled**: applications, calc, clipboard, files, menus, runner, symbols, websearch

## Validation Status

**✅ Configuration Validation**: All configuration is correct
- Elephant service running healthy (27.5M memory)
- All 8 provider prefixes configured
- Walker config.toml generated correctly
- Environment variables properly set (DISPLAY, PATH, XDG_DATA_DIRS)

**❌ Runtime Validation**: Walker UI crashes on launch
- `walker --version` works (shows 2.6.4)
- `walker` (full UI launch) → stack overflow crash
- Crash occurs after successful Elephant connection
- No error messages in Elephant logs

## Attempted Workarounds

1. ❌ Manual launch with `env GDK_BACKEND=x11 walker &` - stack overflow crash
2. ✅ **WORKAROUND FOUND**: Launch via i3 keybinding (Meta+D) - **WORKS!**
3. ✅ Launch via `xdotool key super+d` - **WORKS!**
4. ⏳ Disabling providers one-by-one - not yet tested

## Resolution

**STATUS**: ⚠️ PARTIAL WORKAROUND FOUND

Walker works correctly when launched via the i3 keybinding (`bindsym $mod+d exec env GDK_BACKEND=x11 ...`), but crashes when launched manually from command line with the same command.

**Working Process**:
```bash
# Via keybinding (works)
xdotool key super+d
ps aux | grep walker
vpittamp 2000476 18.6  0.1 11600260 211504 ?  Ssl  17:04   0:00 walker
```

**Root Cause Hypothesis**:
The stack overflow may be related to how Walker is spawned:
- ✅ When launched by i3 (via exec in keybinding) → Works fine
- ❌ When launched directly in shell with `env ... walker &` → Stack overflow

This suggests the issue is NOT with Walker itself, but with the environment or execution context when launched manually from a shell.

## Impact Assessment

**Feature 043 Status**: ⚠️ BLOCKED
- Automated configuration validation: ✅ COMPLETE (34/102 tasks)
- Interactive runtime testing: ❌ BLOCKED by Walker crash
- All provider workflows: ❌ CANNOT TEST

**Root Cause**: Likely Walker 2.6.4 bug (stack overflow in main thread)
- Not an Elephant issue (service healthy, connects successfully)
- Not a configuration issue (all settings validated correctly)
- Not an environment issue (DISPLAY available, X11 working)

## Next Steps

### Immediate (Debugging)
1. Try launching Walker via actual Meta+D keybinding (GUI interaction required)
2. Check if Walker crash is reproducible on fresh login
3. Test with minimal Walker configuration (disable some providers)
4. Check Walker GitHub issues for known stack overflow bugs

### Short-term (Workarounds)
1. Roll back to Walker 2.5.x or earlier version (if available)
2. Test with alternative launcher (rofi) temporarily
3. File bug report with Walker maintainers

### Long-term (Permanent Fix)
1. Wait for Walker 2.6.5 patch release
2. Contribute fix to Walker if root cause identified
3. Consider switching to alternative launcher if Walker remains unstable

## Additional Notes

- Elephant service remained stable throughout Walker crashes
- No system-level issues detected (i3, X11, systemd all healthy)
- Walker can print version without crashing (suggests issue in UI initialization)

## Investigation Log

```bash
# Service status - healthy
systemctl --user status elephant
● elephant.service - Elephant launcher backend (X11)
     Active: active (running) since Mon 2025-10-27 15:18:19 EDT; 1h 44min

# Walker version check - works
walker --version
2.6.4

# Walker UI launch - crashes
env GDK_BACKEND=x11 walker &
thread 'main' has overflowed its stack
fatal runtime error: stack overflow, aborting
```

## Related Documentation

- Feature Spec: `/etc/nixos/specs/043-get-full-functionality/spec.md`
- Validation Report: `/etc/nixos/specs/043-get-full-functionality/VALIDATION_REPORT.md`
- Walker Config: `~/.config/walker/config.toml`
- Walker Source: home-modules/desktop/walker.nix
