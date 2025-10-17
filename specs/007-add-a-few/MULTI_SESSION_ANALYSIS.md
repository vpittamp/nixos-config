# Multi-Session RDP Analysis & Solution

**Date**: 2025-10-16
**Issue**: Same user connecting from different devices (Surface laptop, MacBook) reconnects to existing session instead of creating separate sessions
**Expected**: Option to reconnect to existing session OR create new session per device

---

## Problem Statement

When the same user (vpittamp) connects via RDP from two different devices:
- **Observed behavior**: Connection redirects to existing session, disconnecting the previous device
- **Expected behavior**: Each device should get its own independent session (or provide option to choose)
- **Current evidence**: Two X11 displays (:11 and :12) ARE running, indicating multi-session capability exists

---

## Root Cause Analysis

### 1. Configuration Mismatch

**NixOS Configuration** (`/etc/nixos/modules/desktop/xrdp.nix`):
```ini
[SessionAllocations]
Policy=UBC                         # Configured to create new session per connection
```

**Actual Running Configuration** (`/etc/xrdp/sesman.ini`):
```ini
Policy=Separate                    # System default (deprecated policy)
```

**Finding**: The NixOS configuration is NOT being applied. The system is using the default `Policy=Separate` policy.

### 2. Why `mkAfter` Isn't Working

The current configuration uses:
```nix
environment.etc."xrdp/sesman.ini".text = mkAfter ''
  [SessionAllocations]
  Policy=UBC
'';
```

**Issue**: `mkAfter` appends text, but the NixOS xrdp module already generates a complete sesman.ini with `Policy=Separate`. Appending creates a duplicate `[SessionAllocations]` section, and xrdp reads the FIRST occurrence.

---

## Session Allocation Policy Research

### Available Policies

| Policy | Session Key | Behavior | Use Case |
|--------|-------------|----------|----------|
| **Default** | User + BitPerPixel | Reconnect to same session | Single device, resume work |
| **UBI** | User + BitPerPixel + IP | Separate session per IP | Multi-device from different networks |
| **UBD** | User + BitPerPixel + DisplaySize | Separate session per resolution | Different screen sizes |
| **UBDI** | User + BitPerPixel + DisplaySize + IP | Separate session per IP + display | Best for multi-device |
| **UBC** | User + BitPerPixel + Connection | New session per connection | BROKEN - see below |
| **UBDC** | User + BitPerPixel + DisplaySize + Connection | Same as UBC + display | BROKEN |
| **Separate** | (deprecated) | Always new session | Legacy option |

### Critical Finding: UBC Is Broken

From xrdp GitHub Issue #2239:

> **Problem**: The "Connection" parameter in UBC is constructed as:
> ```
> "<ip_addr>:<port> - socket: <sck>"
> ```
> where `<port>` and `<sck>` change on EVERY reconnection attempt.
>
> **Result**: UBC cannot find existing sessions to reconnect because the connection string never matches. This makes the 'C' parameter "effectively useless" for its intended purpose.

**Conclusion**: `Policy=UBC` is NOT recommended by xrdp maintainers for production use.

---

## Architecture Responsibility Analysis

### Session Management Hierarchy

```
User Connects
    ↓
[xrdp] - Handles RDP protocol, forwards to sesman
    ↓
[xrdp-sesman] - Authenticates user, decides session allocation
    ↓
[X11 Server] - Creates display :10, :11, :12, etc.
    ↓
[Window Manager] - i3wm runs within X11 display
    ↓
[Applications] - Run within window manager
```

### Responsibility Matrix

| Component | Responsible For | Multi-Session Role |
|-----------|-----------------|-------------------|
| **xrdp** | RDP protocol, connection handling | Routes connections to sesman |
| **xrdp-sesman** | Authentication, session allocation | **DECIDES** which session to use |
| **X11 Server** | Graphics display, input handling | Provides isolated display per session |
| **Window Manager (i3)** | Window layout, keybindings | Manages windows WITHIN a session |
| **Display Manager** | Login screen (optional) | NOT USED with xrdp |

**Key Insight**: Multi-session management is **NOT** the responsibility of i3 or any window manager. It's entirely controlled by **xrdp-sesman** via the Policy setting.

### Why i3 Is Perfect for Multi-Session

- **Lightweight**: Low memory footprint per session
- **No desktop environment conflicts**: GNOME/KDE have systemd/dbus conflicts for multi-session
- **Fast startup**: Quick session creation
- **No inter-session interference**: Each i3 instance is completely independent

**Verdict**: i3 is an EXCELLENT choice for multi-session RDP. The session management is correctly handled by xrdp-sesman, not the window manager.

---

## Hetzner Cloud VM Limitations

### Research Findings

**Hetzner Cloud Specifications**:
- **Virtualization**: KVM-based
- **Dedicated vCPU Plans (CCX)**: Exclusive CPU threads, no resource sharing
- **CPU Performance**: Continuous and predictable performance
- **Limitation**: Nested virtualization NOT supported (CPU features not passed through)

### X11 Multi-Session Compatibility

**Assessment**: ✅ **NO LIMITATIONS**

- Multiple X11 displays are standard Linux functionality
- KVM fully supports X11 (no special GPU requirements)
- Evidence: X11 displays :11 and :12 are ALREADY RUNNING on the system
- CPU/Memory: Adequate for multiple sessions (i3 is lightweight)

**Conclusion**: Hetzner Cloud VMs have ZERO limitations for running multiple xrdp sessions with X11 and i3wm.

---

## Recommended Solution

### Option 1: UBDI Policy (Recommended)

**Best for**: Different devices from different networks

```ini
[SessionAllocations]
Policy=UBDI
```

**Behavior**:
- ✅ Surface laptop (IP 73.186.170.124) → Session :11
- ✅ MacBook (different IP) → Session :12
- ⚠️ Same device reconnecting → Rejoins existing session
- ⚠️ VPN changes IP → Creates new session

**Pros**:
- Stable and well-tested policy
- Automatic per-device isolation
- Predictable reconnection behavior

**Cons**:
- Devices behind same NAT may share session
- IP changes create new sessions (may accumulate orphaned sessions)

### Option 2: UBI Policy (Alternative)

**Best for**: Simpler IP-based separation

```ini
[SessionAllocations]
Policy=UBI
```

**Behavior**:
- Same as UBDI but ignores display size
- Slightly more tolerant to resolution changes

**Pros**:
- Less strict than UBDI (resolution doesn't matter)
- Still separates by IP address

**Cons**:
- Same NAT IP limitations as UBDI

### Option 3: Manual Session Selection (Future Enhancement)

**Ideal Solution**: Allow user to choose at connection time:
- "Reconnect to existing session"
- "Create new session"

**Implementation**: Requires custom RDP client or xrdp session picker UI
**Status**: Out of scope for current implementation (requires xrdp modification)

---

## Implementation Plan

### Fix 1: Correct NixOS Configuration

**Problem**: `mkAfter` creates duplicate `[SessionAllocations]` section

**Solution**: Use `mkForce` or `lib.mkOptionDefault` to REPLACE the default configuration:

```nix
# Option A: Override entire sesman.ini (mkForce)
environment.etc."xrdp/sesman.ini".text = mkForce ''
  # Full sesman.ini content with Policy=UBDI
'';

# Option B: Use NixOS xrdp module options (if available)
services.xrdp = {
  enable = true;
  extraConfig = ''
    [SessionAllocations]
    Policy=UBDI
  '';
};
```

### Fix 2: Verify Configuration Applied

```bash
# Check running policy
sudo grep "^Policy=" /etc/xrdp/sesman.ini

# Should show: Policy=UBDI

# Restart xrdp services
sudo systemctl restart xrdp-sesman
sudo systemctl restart xrdp
```

### Fix 3: Test Multi-Device Connection

1. Connect from Surface laptop → Should create/rejoin session :11
2. Connect from MacBook (different IP) → Should create new session :12
3. Verify both sessions running: `loginctl list-sessions`
4. Verify separate X11 displays: `ps aux | grep Xorg`

---

## Frequently Asked Questions

### Q1: Why do I have 2 X displays running if it's reconnecting to the same session?

**Answer**: You likely connected twice, creating 2 sessions (displays :11 and :12). When you reconnect, xrdp tries to reconnect to ONE of them (based on Policy), which disconnects the other device from that specific display. The second display remains running but unused.

**Evidence**:
```
vpittamp  536195  Xorg :11    # Created 13:13
vpittamp  699664  Xorg :12    # Created 14:29
```

### Q2: Is this a Hetzner limitation?

**Answer**: NO. This is a pure xrdp configuration issue. Hetzner Cloud VMs have no restrictions on multiple X11 sessions.

### Q3: Is i3wm the problem?

**Answer**: NO. Session allocation is controlled by xrdp-sesman, not the window manager. i3 is actually ideal for multi-session because it's lightweight and doesn't have the systemd/dbus conflicts that plague GNOME/KDE multi-session setups.

### Q4: Can I connect from the same device twice?

**Answer**: With `Policy=UBDI`, no - same device (same IP) will reconnect to existing session. To force new sessions from same device, you would need `Policy=Separate` (deprecated) or implement manual session selection (requires xrdp modifications).

### Q5: What happens to disconnected sessions?

**Answer**: They remain running for 24 hours (`DisconnectedTimeLimit=86400`) then are automatically cleaned up. You can reconnect within 24 hours.

### Q6: Will this work with 3+ devices?

**Answer**: YES. MaxSessions=5 allows up to 5 concurrent sessions. Each device from a different IP gets its own session.

---

## Next Steps

1. ✅ **Research Complete** - Multi-session issue identified and understood
2. ⏸️ **Decide Policy** - Choose UBDI (recommended) or UBI
3. ⏸️ **Fix NixOS Config** - Update `/etc/nixos/modules/desktop/xrdp.nix` with correct policy override
4. ⏸️ **Rebuild System** - Apply configuration with `nixos-rebuild switch`
5. ⏸️ **Test Multi-Device** - Verify Surface and MacBook get separate sessions
6. ⏸️ **Document** - Update user documentation with session behavior

---

## References

- [xrdp sesman.ini manpage](https://manpages.ubuntu.com/manpages/jammy/man5/sesman.ini.5.html)
- [xrdp GitHub Issue #2239 - UBC Policy Problems](https://github.com/neutrinolabs/xrdp/issues/2239)
- [Griffon's IT Library - Multiple Sessions](https://c-nergy.be/blog/?p=17371)
- [RHEL 7.x - XRDP Multi-Session Guide](https://netsarang.atlassian.net/wiki/spaces/ENSUP/pages/1988001793/)

---

*Analysis completed by Claude Code - 2025-10-16*
