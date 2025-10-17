# UBDI Policy Implementation Status

**Date**: 2025-10-16
**Status**: ⚠️ Configuration Updated But Not Yet Active
**Issue**: NixOS xrdp module not rebuilding with extraConfDirCommands

---

## What Was Done

### 1. Research & Analysis ✅
- Comprehensive analysis of xrdp session policies documented in `MULTI_SESSION_ANALYSIS.md`
- Identified that `Policy=UBC` is broken (Connection parameter changes every reconnect)
- Determined `Policy=UBDI` is the recommended solution for multi-device scenarios
- Confirmed i3wm is not responsible for session management (xrdp-sesman handles it)
- Verified Hetzner Cloud has no limitations for multiple X11 sessions

### 2. Configuration Updates ✅
- Updated `/etc/nixos/modules/desktop/xrdp.nix` to use `services.xrdp.extraConfDirCommands`
- Added sed commands to modify generated sesman.ini:
  ```nix
  services.xrdp.extraConfDirCommands = ''
    ${pkgs.gnused}/bin/sed -i 's/^Policy=.*$/Policy=UBDI/' $out/sesman.ini
    # ... additional session settings ...
  '';
  ```
- Removed old `environment.etc."xrdp/sesman.ini"` approach (doesn't work with NixOS xrdp module)
- Successfully passed dry-build tests
- Applied configuration with `nixos-rebuild switch`

### 3. Current Status ⚠️
**Problem**: The systemd service is still using the old NixOS store path:
```
/nix/store/8r5gdzni5vahsscg97dhmifkanx85pnl-xrdp.conf/sesman.ini
Policy=Default
```

**Expected**: A new store path with `Policy=UBDI`

**Root Cause**: The `extraConfDirCommands` may not be triggering a rebuild of the xrdp.conf derivation, or there's a caching issue preventing the new configuration from being used.

---

## Current Behavior

Your system RIGHT NOW connects both devices to the same session because it's using `Policy=Default`:
- **Default Policy**: Reconnects to existing session if User + BitPerPixel match
- **Result**: Surface laptop and MacBook both connect to the same session, disconnecting each other

---

## Expected Behavior (After Fix)

Once `Policy=UBDI` is active:
- **Surface laptop** (IP 73.186.170.124) → Gets Session :11
- **MacBook** (different IP) → Gets Session :12
- **Same device reconnecting** → Rejoins its existing session
- **Different devices** → Independent sessions running simultaneously

---

## Workaround: Manual Policy Change

Until we resolve the NixOS module issue, you can manually test UBDI policy:

```bash
# 1. Find the active config
CONFIG_PATH=$(systemctl cat xrdp-sesman | grep "config" | awk '{print $NF}')

# 2. Check current policy
grep "^Policy=" $CONFIG_PATH

# 3. Temporarily copy and modify (for testing only - not persistent!)
sudo cp $CONFIG_PATH /tmp/sesman.ini
sudo sed -i 's/^Policy=Default$/Policy=UBDI/' /tmp/sesman.ini

# 4. Update systemd service to use temp config (TESTING ONLY)
sudo systemctl edit xrdp-sesman --full
# Change --config line to: --config /tmp/sesman.ini

# 5. Restart and test
sudo systemctl daemon-reload
sudo systemctl restart xrdp-sesman xrdp

# 6. Verify
grep "^Policy=" /tmp/sesman.ini
```

**⚠️ WARNING**: This workaround is NOT persistent! It will be lost on next `nixos-rebuild switch`.

---

## Next Steps to Fix Properly

### Option 1: Investigate Why extraConfDirCommands Isn't Working
1. Check if there's a syntax error in the extraConfDirCommands
2. Verify the NixOS xrdp module version supports extraConfDirCommands
3. Try using `--rebuild` flag or clearing nix store cache
4. Review NixOS xrdp module source to understand derivation building

### Option 2: Alternative Configuration Method
Use NixOS module assertions or override the entire xrdp package:

```nix
nixpkgs.overlays = [(self: super: {
  xrdp = super.xrdp.overrideAttrs (oldAttrs: {
    postInstall = (oldAttrs.postInstall or "") + ''
      sed -i 's/^Policy=Default$/Policy=UBDI/' $out/etc/xrdp/sesman.ini
    '';
  });
})];
```

### Option 3: Create Custom xrdp Package
Fork the xrdp package and modify sesman.ini template directly.

---

## Testing Instructions

Once the UBDI policy is active, test as follows:

### Test 1: Verify Policy Change
```bash
# Check active policy
sudo systemctl cat xrdp-sesman | grep "config" | awk '{print $NF}' | xargs grep "^Policy="
# Should show: Policy=UBDI
```

### Test 2: Connect from Surface Laptop
1. Open Microsoft Remote Desktop on Surface
2. Connect to Hetzner server
3. Note the session display number: `echo $DISPLAY` (should be :11 or similar)
4. Open a terminal and run: `touch /tmp/surface-session`

### Test 3: Connect from MacBook (While Surface Connected)
1. Keep Surface RDP session open
2. Open Microsoft Remote Desktop on MacBook
3. Connect to Hetzner server
4. **Expected**: New session opens (different display number, e.g., :12)
5. **Expected**: Surface session remains active (doesn't disconnect)
6. Verify: `echo $DISPLAY` (should be different from Surface)
7. Verify: `ls /tmp/surface-session` should NOT exist (different session)

### Test 4: Verify Both Sessions Running
From SSH or console:
```bash
# List all sessions
loginctl list-sessions

# Check X11 displays
ps aux | grep Xorg | grep -E ":(10|11|12|13)"

# Should see TWO Xorg processes with different display numbers
```

### Test 5: Reconnect from Surface
1. Disconnect Surface RDP
2. Wait 5 seconds
3. Reconnect from Surface
4. **Expected**: Reconnects to original session :11
5. Verify: `ls /tmp/surface-session` should still exist

### Test 6: Test 24-Hour Cleanup
1. Disconnect all RDP sessions
2. Wait 24+ hours (or set DisconnectedTimeLimit lower for testing)
3. **Expected**: Old sessions automatically terminated
4. Verify: `loginctl list-sessions` shows no disconnected sessions

---

## Files Modified

1. `/etc/nixos/modules/desktop/xrdp.nix` - Added extraConfDirCommands for UBDI policy
2. `/etc/nixos/specs/007-add-a-few/MULTI_SESSION_ANALYSIS.md` - Research and analysis
3. `/etc/nixos/specs/007-add-a-few/UBDI_IMPLEMENTATION_STATUS.md` - This file

---

## Summary

**Bottom Line**: The configuration is correct and ready, but the NixOS xrdp module hasn't regenerated the config file with the new policy. This is likely a NixOS module rebuild/caching issue that needs investigation.

**Immediate Action**: Use the manual workaround above to test UBDI policy behavior, then work on making it persistent through proper NixOS configuration.

**Root Cause**: NixOS's xrdp service uses a pre-built config in `/nix/store/`, and our `extraConfDirCommands` isn't being executed during the build process.

---

*Status document created by Claude Code - 2025-10-16*
