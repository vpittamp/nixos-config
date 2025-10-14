# Quick Start: KDE Plasma Performance Optimization

**Feature ID**: 002
**Status**: Implementation Pending
**Estimated Time**: 30 minutes to apply optimizations

This guide provides quick instructions for applying KDE Plasma performance optimizations to KubeVirt VMs.

---

## Prerequisites

- NixOS 24.11+ system with KDE Plasma 6
- KubeVirt VM running (for VM resource optimizations)
- `kubectl` access to KubeVirt cluster (for VM resource changes)
- Git access to this repository

---

## Quick Apply (When Implementation Complete)

Once implementation is complete (Phases 2-5), apply optimizations with:

```bash
# 1. Pull latest configuration
cd /etc/nixos
git pull origin 002-kde-plasma-performance

# 2. Test configuration (REQUIRED)
sudo nixos-rebuild dry-build --flake .#<your-target>

# 3. Apply if dry-build succeeds
sudo nixos-rebuild switch --flake .#<your-target>

# 4. Logout and login (or restart KWin)
# Press Ctrl+Alt+Backspace or:
kwin_x11 --replace &

# 5. Verify optimizations applied
bash /etc/nixos/specs/002-kde-plasma-performance/scripts/verify-optimizations.sh
```

**Expected Result**: 2-3x improvement in desktop responsiveness, <20% compositor CPU usage.

---

## Manual Configuration (Current State)

Since implementation is not yet complete, here's how to apply optimizations manually:

### Step 1: Optimize Compositor (Highest Impact)

Edit `~/.config/kwinrc` and add/modify:

```ini
[Compositing]
Backend=XRender
GLCore=false
GLPreferBufferSwap=n
MaxFPS=30
MaxFPSInterval=33333333
OpenGLIsUnsafe=false
VSync=false
WindowsBlockCompositing=true
HiddenPreviews=5
```

**Restart KWin**:
```bash
kwin_x11 --replace &
```

### Step 2: Disable Expensive Effects

Edit `~/.config/kwinrc` and add/modify:

```ini
[Plugins]
blurEnabled=false
contrastEnabled=false
kwin4_effect_translucencyEnabled=false
wobblywindowsEnabled=false
magiclampEnabled=false
cubeslideEnabled=false
```

### Step 3: Set Animations to Instant

Edit `~/.config/kwinrc`:

```ini
[Effect-Slide]
Duration=0

[Effect-PresentWindows]
Duration=0

[Effect-Fade]
Duration=0
```

Edit `~/.config/kdeglobals`:

```ini
[KDE]
AnimationDurationFactor=0
```

### Step 4: Disable Baloo File Indexer

Edit `~/.config/baloofilerc`:

```ini
[Basic Settings]
Indexing-Enabled=false
```

Stop Baloo services:
```bash
systemctl --user stop baloo_file
systemctl --user stop baloo_file_extractor
systemctl --user mask baloo_file
systemctl --user mask baloo_file_extractor
```

### Step 5: Disable Akonadi (If Not Using KDE PIM)

Edit `~/.config/akonadi/akonadiserverrc`:

```ini
[%General]
StartServer=false
```

Stop Akonadi:
```bash
akonadictl stop
systemctl --user stop akonadi_control
systemctl --user mask akonadi_control
```

### Step 6: Optimize KubeVirt VM Resources

Edit your KubeVirt VirtualMachine YAML:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
spec:
  template:
    spec:
      domain:
        cpu:
          cores: 8  # Increased from 4
          sockets: 1
          threads: 1
          dedicatedCpuPlacement: true  # KEY CHANGE
          model: host-passthrough
        memory:
          guest: 16Gi  # Increased from 8Gi
        resources:
          requests:
            memory: 16Gi
            cpu: 8000m
          limits:
            memory: 16Gi
            cpu: 8000m
      ioThreadsPolicy: auto  # KEY CHANGE
```

Apply changes:
```bash
# Delete and recreate VM (resource changes require recreation)
kubectl delete vm <vm-name>
kubectl apply -f <vm-spec.yaml>
```

### Step 7: Optimize RustDesk Settings

In RustDesk client:
1. Connect to your VM
2. Open connection settings
3. Set:
   - **Codec**: VP8 (for LAN) or VP9 (for VPN)
   - **Quality**: 80-90%
   - **FPS**: 30
   - **Connection**: Direct (not relay)

---

## Verification

### Check Compositor Backend

```bash
kreadconfig5 --file kwinrc --group Compositing --key Backend
# Expected: XRender
```

### Check CPU Usage

```bash
htop -p $(pgrep kwin_x11)
# Expected: <20% during normal operations
```

### Check Services Disabled

```bash
ps aux | grep -E "baloo|akonadi"
# Expected: No results (or only grep itself)
```

### Check RAM Usage

```bash
free -h
# Note the "available" memory - should be 1-2GB more than before
```

### Check VM Resources

```bash
kubectl describe vmi <vm-name> | grep -A 10 "CPU"
# Expected: dedicatedCpuPlacement: true, cores: 8

kubectl describe vmi <vm-name> | grep -A 5 "Memory"
# Expected: 16Gi
```

---

## Performance Testing

### Subjective Tests

1. **Window Drag**: Drag window across screen
   - **Expected**: Smooth movement, <100ms perceived latency

2. **Alt+Tab Switching**: Rapidly switch between windows
   - **Expected**: Instant switcher appearance (<50ms)

3. **Scrolling**: Scroll long web page or document
   - **Expected**: Smooth 25-30 FPS, no tearing

4. **Cursor Movement**: Move cursor rapidly across screen
   - **Expected**: Smooth tracking, no jumpiness

### Objective Metrics

```bash
# Compositor CPU usage
top -b -n 1 | grep kwin_x11
# Target: <20%

# RAM usage
free -h | grep "available"
# Target: 1-2GB more than before optimization

# Running services count
ps aux | wc -l
# Target: 10-20 fewer processes than before
```

---

## Troubleshooting

### Issue: KWin crashes after switching to XRender

**Symptom**: Black screen or KWin fails to start

**Solution**:
```bash
# Revert to OpenGL backend
kwriteconfig5 --file kwinrc --group Compositing --key Backend OpenGL
kwin_x11 --replace &
```

**Root Cause**: XRender might not be available on all systems. Check `/var/log/Xorg.0.log` for X11 render extension support.

### Issue: Desktop feels choppy after disabling effects

**Symptom**: Rough transitions, stuttering

**Solution**:
- Check compositor FPS: Should be 30
- Ensure animations set to instant (duration=0)
- Verify no expensive effects enabled

### Issue: Baloo or Akonadi still running

**Symptom**: `ps aux` shows baloo_file or akonadi processes

**Solution**:
```bash
# Force stop and mask
systemctl --user stop baloo_file baloo_file_extractor
systemctl --user mask baloo_file baloo_file_extractor
systemctl --user stop akonadi_control
systemctl --user mask akonadi_control

# Reboot to ensure clean state
sudo reboot
```

### Issue: VM fails to schedule with dedicated CPUs

**Symptom**: VM stuck in "Pending" state

**Solution**:
```bash
# Check host CPU capacity
kubectl describe node <node-name> | grep -A 5 "Capacity"

# Reduce vCPU count if needed
# Edit VM spec: cores: 6 (instead of 8)
```

**Root Cause**: Insufficient physical cores available for dedicated placement. Either free up cores or reduce vCPU count.

### Issue: RustDesk connection laggy despite optimizations

**Symptom**: Still experiencing high latency or stuttering

**Checklist**:
1. ✅ Compositor using XRender? (`kreadconfig5 --file kwinrc --group Compositing --key Backend`)
2. ✅ Effects disabled? (`kreadconfig5 --file kwinrc --group Plugins --key blurEnabled`)
3. ✅ VM has dedicated CPUs? (`kubectl describe vmi <name> | grep dedicatedCpuPlacement`)
4. ✅ RustDesk using direct connection? (Check RustDesk status: should not say "relay")
5. ✅ Network latency acceptable? (`ping <vm-ip>` should be <50ms)

If all checks pass but still laggy:
- Try different codec (VP8 → H.264)
- Reduce RustDesk quality to 70-80%
- Check host node CPU load (`kubectl top node`)

---

## Rollback

### Revert Compositor Settings

```bash
# Restore OpenGL backend
kwriteconfig5 --file kwinrc --group Compositing --key Backend OpenGL
kwriteconfig5 --file kwinrc --group Compositing --key GLCore true
kwriteconfig5 --file kwinrc --group Compositing --key MaxFPS 60
kwriteconfig5 --file kwinrc --group Compositing --key VSync true

# Restart KWin
kwin_x11 --replace &
```

### Re-enable Services

```bash
# Re-enable Baloo
systemctl --user unmask baloo_file baloo_file_extractor
kwriteconfig5 --file baloofilerc --group "Basic Settings" --key "Indexing-Enabled" true
systemctl --user start baloo_file

# Re-enable Akonadi (if needed)
systemctl --user unmask akonadi_control
kwriteconfig5 --file akonadiserverrc --group "%General" --key StartServer true
systemctl --user start akonadi_control
```

### Revert VM Resources

```bash
# Restore original VM spec
kubectl delete vm <vm-name>
kubectl apply -f <original-vm-spec.yaml>
```

---

## Next Steps

After applying optimizations:

1. **Measure Performance**: Run verification tests (see "Verification" section)
2. **Document Results**: Note CPU usage, RAM savings, subjective responsiveness
3. **Report Issues**: If problems occur, capture logs and create GitHub issue
4. **Tune Further**: If performance still insufficient, consider:
   - GPU passthrough (future work)
   - Further FPS reduction (15 FPS for very slow connections)
   - Alternative remote desktop protocol (X2Go, NoMachine)

---

## Related Documentation

- **Specification**: `spec.md` - Full requirements and user stories
- **Research**: `research.md` - Performance analysis and rationale
- **Implementation Plan**: `plan.md` - Development phases and timeline
- **Data Model**: `data-model.md` - Configuration entity definitions
- **Contracts**: `contracts/` - Configuration interface specifications

---

## Getting Help

**Issue Tracker**: GitHub Issues in this repository
**Documentation**: `docs/` directory in repository root
**Constitution**: `.specify/memory/constitution.md` - Project governance

---

**Version**: 1.0 (Manual)
**Last Updated**: 2025-10-14
**Status**: Pre-implementation guide (manual steps)

**Note**: This guide will be updated with automated commands once Phases 2-5 are implemented.
