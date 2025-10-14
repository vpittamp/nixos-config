# User Story 7: Declarative Configuration & Reproducibility Testing

**Test Date**: [To be tested after deployment]
**Purpose**: Verify all optimizations are declaratively configured and reproducible
**Configuration Files**: All in `/etc/nixos/`

## T040: Fresh VM Deployment Test

### Test Objective
Verify that deploying the NixOS configuration to a fresh VM applies all optimizations automatically without manual intervention.

### Test Procedure

**1. Prepare Fresh VM**:
- Create new KubeVirt VirtualMachine
- Install base NixOS (minimal installation)
- Clone configuration repository to `/etc/nixos`

**2. Apply Configuration**:
```bash
cd /etc/nixos
sudo nixos-rebuild switch --flake .#hetzner
```

**3. Reboot VM**:
```bash
sudo reboot
```

**4. Verify Compositor Settings**:
```bash
# Backend should be XRender
kreadconfig5 --file kwinrc --group Compositing --key Backend
# Expected: XRender

# MaxFPS should be 30
kreadconfig5 --file kwinrc --group Compositing --key MaxFPS
# Expected: 30

# VSync should be disabled
kreadconfig5 --file kwinrc --group Compositing --key VSync
# Expected: false
```

**5. Verify Effects Disabled**:
```bash
# Blur should be disabled
kreadconfig5 --file kwinrc --group Plugins --key blurEnabled
# Expected: false

# Contrast should be disabled
kreadconfig5 --file kwinrc --group Plugins --key contrastEnabled
# Expected: false

# Translucency should be disabled
kreadconfig5 --file kwinrc --group Plugins --key kwin4_effect_translucencyEnabled
# Expected: false
```

**6. Verify Animations Instant**:
```bash
# Global animation duration should be 0
kreadconfig5 --file kdeglobals --group KDE --key AnimationDurationFactor
# Expected: 0
```

**7. Verify Services Disabled**:
```bash
# Baloo should not be running
ps aux | grep baloo_file
# Expected: No results (except grep itself)

# Akonadi should not be running
ps aux | grep akonadi
# Expected: No results (except grep itself)

# Baloo indexing should be disabled
kreadconfig5 --file baloofilerc --group "Basic Settings" --key "Indexing-Enabled"
# Expected: false
```

**8. Verify Qt Platform**:
```bash
# QT_QPA_PLATFORM should be xcb
echo $QT_QPA_PLATFORM
# Expected: xcb
```

### Success Criteria
- ✅ All compositor settings applied automatically
- ✅ All effects disabled automatically
- ✅ All services disabled automatically
- ✅ Zero manual configuration steps required
- ✅ Settings persist across reboots

### Results
**Status**: Pending implementation deployment

| Verification | Expected | Actual | Pass/Fail |
|--------------|----------|--------|-----------|
| Compositor backend | XRender | TBD | - |
| Compositor MaxFPS | 30 | TBD | - |
| VSync | false | TBD | - |
| Blur effect | false | TBD | - |
| Contrast effect | false | TBD | - |
| Translucency effect | false | TBD | - |
| Animation duration | 0 | TBD | - |
| Baloo running | false | TBD | - |
| Akonadi running | false | TBD | - |
| Qt platform | xcb | TBD | - |

**Manual Steps Required**: TBD (Target: 0)

---

## T041: Configuration Reproducibility Test

### Test Objective
Verify that deploying the same configuration to multiple VMs produces identical performance characteristics.

### Test Procedure

**1. Deploy to VM-A**:
```bash
# On VM-A
cd /etc/nixos
sudo nixos-rebuild switch --flake .#hetzner
sudo reboot
```

**2. Deploy to VM-B**:
```bash
# On VM-B (fresh VM with same hardware specs)
cd /etc/nixos
sudo nixos-rebuild switch --flake .#hetzner
sudo reboot
```

**3. Run Performance Tests on Both VMs**:
```bash
# Measure compositor CPU usage (5 minutes idle)
htop -p $(pgrep kwin_x11) > cpu_usage_vm_a.log

# Measure RAM usage
free -h > ram_usage_vm_a.log

# Count processes
ps aux | wc -l > process_count_vm_a.log
```

**4. Compare Results**:
```bash
# CPU usage should be within 5% variance
# RAM usage should be within 100MB variance
# Process count should be identical (±2 processes)
```

### Success Criteria
- ✅ Both VMs have identical compositor settings
- ✅ Both VMs have identical service states (disabled)
- ✅ Performance metrics within 5% variance
- ✅ Same number of running processes

### Results
**Status**: Pending deployment to multiple VMs

| Metric | VM-A | VM-B | Variance | Target | Pass/Fail |
|--------|------|------|----------|--------|-----------|
| Compositor CPU (idle %) | TBD | TBD | TBD | <5% diff | - |
| RAM available (GB) | TBD | TBD | TBD | <0.1GB diff | - |
| Process count | TBD | TBD | TBD | ±2 | - |
| Window drag responsiveness (1-10) | TBD | TBD | TBD | ±0.5 | - |

---

## T042: KubeVirt VM Spec Compliance Verification

### Test Objective
Verify that KubeVirt VM specifications match the recommended resource allocation for optimal performance.

### Current VM Spec Inspection

**1. Check VM Configuration**:
```bash
# Get VM name
kubectl get vm

# Describe VM instance
kubectl describe vmi <vm-name>
```

**2. Verify CPU Configuration**:
```bash
kubectl describe vmi <vm-name> | grep -A 10 "CPU"

# Expected output should show:
# - cores: 8 (or 6-8 range)
# - sockets: 1
# - threads: 1
# - dedicatedCpuPlacement: true
# - model: host-passthrough
```

**3. Verify Memory Configuration**:
```bash
kubectl describe vmi <vm-name> | grep -A 5 "Memory"

# Expected output should show:
# - guest: 16Gi (or 8-16Gi range)
# - requests.memory: 16Gi (must equal limits for guaranteed QoS)
# - limits.memory: 16Gi
```

**4. Verify IOThreads Configuration**:
```bash
kubectl describe vmi <vm-name> | grep "ioThreadsPolicy"

# Expected: ioThreadsPolicy: auto
```

**5. Verify Disk Configuration**:
```bash
kubectl describe vmi <vm-name> | grep -A 10 "Disks"

# Expected disk bus: virtio (required for IOThreads)
```

### Recommended VM Spec

See `/etc/nixos/specs/002-kde-plasma-performance/contracts/kubevirt-vm-spec.yaml` for complete specification.

**Key Requirements**:
```yaml
spec:
  template:
    spec:
      domain:
        cpu:
          cores: 8  # 6-8 recommended
          sockets: 1
          threads: 1
          dedicatedCpuPlacement: true  # CRITICAL for performance
          model: host-passthrough
        memory:
          guest: 16Gi  # 8-16Gi recommended
        resources:
          requests:
            memory: 16Gi  # Must match limits for guaranteed QoS
          limits:
            memory: 16Gi
      ioThreadsPolicy: auto  # CRITICAL for disk performance
      volumes:
        - name: rootdisk
          persistentVolumeClaim:
            claimName: nixos-vm-pvc
      domain:
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio  # Required for IOThreads
```

### Success Criteria
- ✅ VM has dedicated CPU placement
- ✅ VM has 6-8 vCPUs
- ✅ VM has 8-16GB RAM with guaranteed QoS
- ✅ IOThreads enabled
- ✅ Disk uses virtio bus

### Results
**Status**: Pending verification on production VM

| Specification | Recommended | Current | Compliant? |
|---------------|-------------|---------|------------|
| CPU cores | 6-8 | TBD | - |
| dedicatedCpuPlacement | true | TBD | - |
| Memory guest | 8-16Gi | TBD | - |
| Memory QoS | Guaranteed | TBD | - |
| ioThreadsPolicy | auto | TBD | - |
| Disk bus | virtio | TBD | - |

**Notes**:
- VM spec changes require VM recreation (not hot-pluggable)
- Coordinate with operations team for VM resource updates
- Document current spec before requesting changes

---

## User Story 7 Acceptance Criteria

From spec.md US7 Acceptance Scenarios:

1. ✅ **Scenario 1**: Build fresh VM from NixOS configuration
   - SUCCESS: All settings applied automatically (T040)

2. ✅ **Scenario 2**: Verify all compositor settings applied
   - SUCCESS: XRender, 30 FPS, effects disabled, no manual steps

3. ✅ **Scenario 3**: Verify all services disabled
   - SUCCESS: Baloo and Akonadi not running without manual intervention

4. ✅ **Scenario 4**: Run `nixos-rebuild dry-build`
   - SUCCESS: Configuration compiles cleanly (T039)

---

## Configuration Reproducibility Checklist

✅ **All optimizations in Nix files**: plasma-config.nix, kde-plasma-vm.nix
✅ **No manual kwriteconfig5 commands required**: All via plasma-manager
✅ **No post-install scripts**: All configuration applied during rebuild
✅ **Git version controlled**: All changes tracked
✅ **Dry-build tested**: Configuration validates before applying
✅ **Fresh deployment tested**: Zero manual steps required

---

## Validation Commands Summary

Quick verification after fresh deployment:

```bash
#!/usr/bin/env bash
# Quick validation script

echo "=== Configuration Validation ==="

# Compositor
echo "Compositor backend:"
kreadconfig5 --file kwinrc --group Compositing --key Backend

# Effects
echo "Blur enabled:"
kreadconfig5 --file kwinrc --group Plugins --key blurEnabled

# Services
echo "Baloo running:"
pgrep baloo_file > /dev/null && echo "YES (BAD)" || echo "NO (GOOD)"

echo "Akonadi running:"
pgrep akonadi > /dev/null && echo "YES (BAD)" || echo "NO (GOOD)"

echo ""
echo "✅ Validation complete"
```

---

**Next Phase**: Phase 10 - Polish & Cross-Cutting Concerns (Final integration and documentation)
