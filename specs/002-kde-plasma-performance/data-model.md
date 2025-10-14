# Data Model: KDE Plasma Performance Optimization

**Feature ID**: 002
**Created**: 2025-10-14
**Status**: Design Complete

This document defines the entities, their relationships, and state transitions for KDE Plasma performance optimization in KubeVirt VMs.

---

## 1. Core Entities

### 1.1 Compositor Configuration

**Purpose**: Defines KDE KWin compositor settings for optimal VM performance

**Entity Name**: `CompositorConfig`

**Attributes**:

| Attribute | Type | Valid Values | Default (Base) | Override (VM) | Validation |
|-----------|------|--------------|----------------|---------------|------------|
| `backend` | enum | `OpenGL`, `XRender` | `OpenGL` | `XRender` | Required |
| `glCore` | boolean | `true`, `false` | `true` | `false` | Required |
| `glPreferBufferSwap` | enum | `a` (auto), `c` (copy), `p` (paint), `e` (extend), `n` (none) | `a` | `n` | Required |
| `maxFPS` | integer | 10-144 | 60 | 30 | 10 ≤ x ≤ 144 |
| `vSync` | boolean | `true`, `false` | `true` | `false` | Required |
| `hiddenPreviews` | integer | 0-10 | 6 | 5 | 0 ≤ x ≤ 10 |
| `openGLIsUnsafe` | boolean | `true`, `false` | `false` | `false` | Required |
| `windowsBlockCompositing` | boolean | `true`, `false` | `true` | `true` | Required |

**Configuration File**: `~/.config/kwinrc` section `[Compositing]`

**NixOS Module**: `home-modules/desktop/plasma-config.nix`

**State Transitions**:
```
Initial (OpenGL)
    → Configured (XRender) [via nixos-rebuild]
    → Active (after KWin restart)
    → Validated (performance metrics checked)
```

**Validation Rules**:
- `backend = "XRender"` MUST be set for VM optimization
- `maxFPS` MUST be ≤ 60 for remote desktop scenarios
- `vSync` SHOULD be `false` for lowest latency
- Changes require KWin restart or user logout/login

---

### 1.2 Visual Effects Configuration

**Purpose**: Controls KDE desktop effects and animations

**Entity Name**: `EffectsConfig`

**Attributes** (all boolean, enabled/disabled):

| Effect Name | Config Key | Default (Desktop) | Override (VM) | Performance Impact |
|-------------|------------|-------------------|---------------|-------------------|
| Blur | `blurEnabled` | `true` | `false` | High (15-25% CPU) |
| Background Contrast | `contrastEnabled` | `true` | `false` | Medium (10-15% CPU) |
| Translucency | `kwin4_effect_translucencyEnabled` | `true` | `false` | High (10-20% CPU) |
| Wobbly Windows | `wobblywindowsEnabled` | `true` | `false` | Medium (8-12% CPU) |
| Magic Lamp | `magiclampEnabled` | `true` | `false` | Low (5-8% CPU) |
| Desktop Cube | `cubeslideEnabled` | `false` | `false` | High (15-25% CPU) |

**Configuration File**: `~/.config/kwinrc` section `[Plugins]`

**NixOS Module**: `home-modules/desktop/plasma-config.nix`

**Validation Rules**:
- For VM optimization, all effects SHOULD be disabled
- Effects MUST be individually toggleable (not all-or-nothing)
- Changes take effect immediately without restart

---

### 1.3 Animation Configuration

**Purpose**: Controls animation durations for transitions and effects

**Entity Name**: `AnimationConfig`

**Attributes**:

| Attribute | Type | Valid Values | Default | VM Override | Config Location |
|-----------|------|--------------|---------|-------------|-----------------|
| `globalAnimationDuration` | float | 0.0-1.0 | 1.0 | 0.0 | `kdeglobals` `[KDE]` |
| `slideEffectDuration` | integer | 0-1000ms | 150 | 0 | `kwinrc` `[Effect-Slide]` |
| `presentWindowsDuration` | integer | 0-1000ms | 300 | 0 | `kwinrc` `[Effect-PresentWindows]` |
| `fadeEffectDuration` | integer | 0-1000ms | 150 | 0 | `kwinrc` `[Effect-Fade]` |

**Configuration Files**:
- Global: `~/.config/kdeglobals` section `[KDE]`
- Per-effect: `~/.config/kwinrc` sections `[Effect-*]`

**NixOS Module**: `home-modules/desktop/plasma-config.nix`

**Validation Rules**:
- `globalAnimationDuration = 0.0` disables all animations system-wide
- Individual effect durations can override global setting
- Duration = 0 means instant transition (no animation)

---

### 1.4 Desktop Service Configuration

**Purpose**: Manages KDE background services (Baloo, Akonadi, etc.)

**Entity Name**: `ServiceConfig`

**Attributes**:

| Service | Systemd Unit | Enabled (Default) | Enabled (VM) | RAM Impact | CPU Impact |
|---------|--------------|-------------------|--------------|------------|------------|
| Baloo File Indexer | `baloo_file.service` | `true` | `false` | 300MB | 10-30% |
| Baloo File Extractor | `baloo_file_extractor.service` | `true` | `false` | 200MB | 5-10% |
| Akonadi Control | `akonadi_control.service` | `true` | `false` | 500MB | 5-15% |
| Akonadi Services | `akonadi_*.service` | `true` | `false` | 300MB | 5-10% |
| KDE Connect | `kdeconnect.service` | `true` | Conditional | 50MB | <5% |

**Configuration Files**:
- Baloo: `~/.config/baloofilerc` section `[Basic Settings]`
- Akonadi: `~/.config/akonadi/akonadiserverrc` section `[%General]`

**NixOS Module**: `modules/services/kde-optimization.nix` (to be created)

**State Transitions**:
```
Enabled (default)
    → Disabled (service stopped)
    → Masked (systemd mask applied)
    → Validated (ps aux confirms not running)
```

**Validation Rules**:
- Services MUST be disabled via systemd (declarative), not manual stop
- Baloo MUST have `Indexing-Enabled=false` in baloofilerc
- Akonadi MUST have `StartServer=false` in akonadiserverrc
- Changes take effect after systemctl daemon-reload or reboot

---

### 1.5 KubeVirt VM Resource Specification

**Purpose**: Defines VM compute and I/O resources for optimal performance

**Entity Name**: `VMResourceSpec`

**Attributes**:

| Attribute | Type | Valid Values | Default | Optimized | Validation |
|-----------|------|--------------|---------|-----------|------------|
| `cpu.cores` | integer | 1-32 | 4 | 8 | 1 ≤ x ≤ 32 |
| `cpu.sockets` | integer | 1-4 | 1 | 1 | x = 1 (best for desktop) |
| `cpu.threads` | integer | 1-2 | 1 | 1 | x = 1 (best for latency) |
| `cpu.dedicatedCpuPlacement` | boolean | `true`, `false` | `false` | `true` | Required |
| `cpu.model` | enum | `host-passthrough`, `host-model`, specific models | `host-model` | `host-passthrough` | Required |
| `memory.guest` | string | e.g. `8Gi`, `16Gi` | `8Gi` | `16Gi` | Must match requests/limits |
| `resources.requests.memory` | string | e.g. `8Gi`, `16Gi` | `8Gi` | `16Gi` | Must equal limits (guaranteed QoS) |
| `resources.limits.memory` | string | e.g. `8Gi`, `16Gi` | `8Gi` | `16Gi` | Must equal requests (guaranteed QoS) |
| `ioThreadsPolicy` | enum | `auto`, `shared`, manual number | `shared` | `auto` | Required |
| `devices.disks[].disk.bus` | enum | `virtio`, `sata`, `scsi` | `virtio` | `virtio` | Required for IOThreads |

**Configuration File**: KubeVirt VirtualMachine YAML spec

**NixOS Module**: N/A (KubeVirt configuration outside NixOS scope)

**State Transitions**:
```
Defined (YAML spec created)
    → Applied (kubectl apply)
    → Scheduled (Kubernetes assigns to node)
    → Running (VM booted)
    → Validated (kubectl describe vmi shows correct resources)
```

**Validation Rules**:
- `dedicatedCpuPlacement = true` REQUIRES host node to have available dedicated cores
- `requests.memory` MUST equal `limits.memory` for guaranteed QoS
- `ioThreadsPolicy = auto` REQUIRES `disk.bus = virtio`
- Total vCPUs MUST NOT exceed physical cores on host node
- Changes require VM recreation (not hot-pluggable)

---

### 1.6 RustDesk Connection Configuration

**Purpose**: Optimizes RustDesk codec and connection settings

**Entity Name**: `RustDeskConfig`

**Attributes**:

| Attribute | Type | Valid Values | Default | Recommended (LAN) | Recommended (VPN) |
|-----------|------|--------------|---------|-------------------|-------------------|
| `codec` | enum | `VP8`, `VP9`, `H.264`, `H.265` | `VP8` | `VP8` or `H.264` | `VP9` |
| `quality` | integer | 10-100% | 90 | 80-90 | 70-80 |
| `fps` | integer | 10-60 | 30 | 30 | 25 |
| `connectionType` | enum | `direct`, `relay`, `auto` | `auto` | `direct` | `direct` |
| `compressionLevel` | integer | 1-10 | 6 | 5-6 | 7-8 |

**Configuration Location**: RustDesk client application settings (per-connection)

**NixOS Module**: N/A (client-side configuration, not server)

**Validation Rules**:
- `fps` SHOULD match compositor `maxFPS` setting (30)
- `connectionType = direct` REQUIRES Tailscale VPN or LAN access
- `codec = VP8` provides best latency for LAN scenarios
- `codec = VP9` provides best quality/bandwidth ratio for VPN
- Changes take effect on next connection

---

### 1.7 Qt Platform Configuration

**Purpose**: Configures Qt rendering platform and scaling

**Entity Name**: `QtPlatformConfig`

**Attributes**:

| Attribute | Type | Valid Values | Default | VM Override | Validation |
|-----------|------|--------------|---------|-------------|------------|
| `QT_QPA_PLATFORM` | string | `xcb`, `wayland`, `offscreen` | `xcb` | `xcb` | Must be `xcb` for X11 |
| `QT_AUTO_SCREEN_SCALE_FACTOR` | string | `0`, `1` | `1` | `0` | Required |
| `QT_SCALE_FACTOR` | string | `0.5`-`3.0` | `1` | `1` | 0.5 ≤ x ≤ 3.0 |
| `QT_FONT_DPI` | integer | 72-288 | `96` | `96` | 72 ≤ x ≤ 288 |

**Configuration Location**: System environment variables

**NixOS Module**: `modules/desktop/kde-plasma-vm.nix` (to be created)

**Configuration**:
```nix
environment.sessionVariables = {
  QT_QPA_PLATFORM = "xcb";
  QT_AUTO_SCREEN_SCALE_FACTOR = "0";
  QT_SCALE_FACTOR = "1";
};
```

**Validation Rules**:
- `QT_QPA_PLATFORM` MUST be `xcb` for X11 RustDesk compatibility
- `QT_AUTO_SCREEN_SCALE_FACTOR = 0` disables automatic scaling
- Manual `QT_SCALE_FACTOR` provides predictable scaling in remote scenarios
- Changes require application restart or session logout

---

## 2. Entity Relationships

### Dependency Graph

```
KubeVirt VMResourceSpec
    ↓ provides compute resources
Compositor Configuration ←→ Visual Effects Configuration
    ↓ renders desktop              ↓ applies effects
Desktop Service Configuration ←→ Animation Configuration
    ↓ background processes          ↓ transition timings
Qt Platform Configuration
    ↓ rendering backend
RustDesk Connection ← transmits → User Display
```

### Key Relationships

1. **VMResourceSpec → CompositorConfig**
   - Adequate vCPUs required for XRender rendering performance
   - 6-8 dedicated cores recommended for responsive compositor

2. **CompositorConfig ↔ EffectsConfig**
   - Compositor backend determines effect performance
   - XRender backend makes expensive effects prohibitively slow
   - Effects disabled independently but depend on compositor

3. **ServiceConfig → RAM Availability**
   - Baloo + Akonadi consume 800MB-1.5GB
   - Disabling services frees RAM for compositor and applications

4. **CompositorConfig.maxFPS ↔ RustDeskConfig.fps**
   - Should be synchronized (both 30 FPS)
   - Mismatch causes frame dropping or wasted rendering

5. **QtPlatformConfig.QT_QPA_PLATFORM → RustDesk Compatibility**
   - Must be `xcb` (X11) for RustDesk to capture screen
   - Wayland incompatible with current RustDesk version

---

## 3. State Machines

### Compositor Backend State Machine

```
┌─────────────┐
│  Initial    │ (OpenGL, default)
└──────┬──────┘
       │ nixos-rebuild switch
       ↓
┌─────────────┐
│ Configured  │ (XRender in kwinrc)
└──────┬──────┘
       │ KWin restart / logout
       ↓
┌─────────────┐
│   Active    │ (XRender rendering)
└──────┬──────┘
       │ Performance testing
       ↓
┌─────────────┐
│  Validated  │ (CPU < 20%, latency < 100ms)
└─────────────┘
```

### Service Lifecycle State Machine

```
┌─────────────┐
│   Enabled   │ (default state)
└──────┬──────┘
       │ systemd.user.services.*.enable = false
       ↓
┌─────────────┐
│  Disabled   │ (service stopped)
└──────┬──────┘
       │ systemctl mask (optional)
       ↓
┌─────────────┐
│   Masked    │ (prevented from starting)
└──────┬──────┘
       │ ps aux validation
       ↓
┌─────────────┐
│  Validated  │ (not running)
└─────────────┘
```

### VM Resource Provisioning State Machine

```
┌─────────────┐
│   Defined   │ (YAML spec created)
└──────┬──────┘
       │ kubectl apply
       ↓
┌─────────────┐
│   Applied   │ (K8s resource created)
└──────┬──────┘
       │ KubeVirt schedules
       ↓
┌─────────────┐
│ Scheduled   │ (Node assigned)
└──────┬──────┘
       │ VM boots
       ↓
┌─────────────┐
│   Running   │ (VM operational)
└──────┬──────┘
       │ Resource verification
       ↓
┌─────────────┐
│  Validated  │ (Resources confirmed)
└─────────────┘
```

---

## 4. Validation Rules Summary

### Compositor Configuration

```python
assert config.backend == "XRender", "VM optimization requires XRender"
assert config.maxFPS <= 60, "MaxFPS too high for remote desktop"
assert config.vSync == False, "VSync adds latency"
assert config.glCore == False, "GLCore requires GPU"
```

### Effects Configuration

```python
expensive_effects = ["blur", "contrast", "translucency", "wobbly"]
for effect in expensive_effects:
    assert effects[effect] == False, f"{effect} disabled for VM performance"
```

### Service Configuration

```python
# After configuration applied
assert "baloo_file" not in ps_output, "Baloo must be disabled"
assert "akonadi" not in ps_output, "Akonadi must be disabled"
```

### VM Resource Configuration

```python
assert vm_spec.cpu.dedicatedCpuPlacement == True, "Dedicated CPUs required"
assert vm_spec.memory.requests == vm_spec.memory.limits, "Guaranteed QoS required"
assert vm_spec.ioThreadsPolicy == "auto", "IOThreads required for disk performance"
assert vm_spec.cpu.cores >= 6, "Minimum 6 vCPUs recommended"
```

### Cross-Entity Validation

```python
# Compositor FPS should match RustDesk FPS
assert compositor.maxFPS == rustdesk.fps, "FPS mismatch causes frame drops"

# Qt platform must be X11 for RustDesk
assert qt.QT_QPA_PLATFORM == "xcb", "RustDesk requires X11"

# VM memory must support KDE + apps
assert vm_spec.memory.guest >= "8Gi", "Insufficient memory for KDE"
```

---

## 5. Configuration File Mapping

### Home-Manager (User-Level)

**File**: `home-modules/desktop/plasma-config.nix`

**Entities Configured**:
- CompositorConfig
- EffectsConfig
- AnimationConfig
- ServiceConfig (Baloo, Akonadi)

**Access Pattern**: Declarative via `programs.plasma.configFile`

### System Module (System-Level)

**File**: `modules/desktop/kde-plasma-vm.nix` (to be created)

**Entities Configured**:
- QtPlatformConfig

**Access Pattern**: Declarative via `environment.sessionVariables`

### KubeVirt (External)

**File**: KubeVirt VirtualMachine YAML

**Entities Configured**:
- VMResourceSpec

**Access Pattern**: Imperative via `kubectl apply`

### RustDesk (Client-Side)

**File**: RustDesk application settings

**Entities Configured**:
- RustDeskConfig

**Access Pattern**: Interactive via RustDesk UI (not declarative)

---

## 6. Testing and Validation

### Entity-Level Tests

**CompositorConfig**:
```bash
# Verify backend
kreadconfig5 --file kwinrc --group Compositing --key Backend
# Expected: XRender

# Verify FPS limit
kreadconfig5 --file kwinrc --group Compositing --key MaxFPS
# Expected: 30
```

**EffectsConfig**:
```bash
# Verify blur disabled
kreadconfig5 --file kwinrc --group Plugins --key blurEnabled
# Expected: false
```

**ServiceConfig**:
```bash
# Verify Baloo not running
ps aux | grep baloo_file
# Expected: no results

# Verify Akonadi not running
ps aux | grep akonadi
# Expected: no results
```

**VMResourceSpec**:
```bash
# Verify dedicated CPUs
kubectl describe vmi <vm-name> | grep -i dedicated
# Expected: dedicatedCpuPlacement: true

# Verify memory allocation
kubectl describe vmi <vm-name> | grep -i memory
# Expected: 16Gi
```

### Integration Tests

**Compositor + Effects**:
```bash
# CPU usage test
htop -p $(pgrep kwin_x11)
# Expected: < 20% during normal operations
```

**Services + RAM**:
```bash
# RAM usage test
free -h
# Expected: 1-2GB more available than before
```

**VM Resources + Responsiveness**:
```bash
# Latency test (subjective)
# Drag window across screen, measure perceived delay
# Expected: < 100ms latency
```

---

## 7. Migration and Upgrade Paths

### From OpenGL to XRender

```
1. Backup current kwinrc: cp ~/.config/kwinrc ~/.config/kwinrc.backup
2. Apply NixOS configuration: nixos-rebuild switch
3. Logout and login (or restart KWin)
4. Validate backend: kreadconfig5 --file kwinrc --group Compositing --key Backend
```

### From Enabled to Disabled Services

```
1. Apply NixOS configuration with service disabling
2. Reload systemd user: systemctl --user daemon-reload
3. Verify services stopped: ps aux | grep -E "baloo|akonadi"
4. Reboot for clean state (optional but recommended)
```

### From Default to Optimized VM Resources

```
1. Export current VM state (if data needs preservation)
2. Delete VM: kubectl delete vm <vm-name>
3. Apply new VM spec with optimized resources: kubectl apply -f vm-spec.yaml
4. Verify resources: kubectl describe vmi <vm-name>
```

**Note**: VM resource changes require VM recreation (not hot-pluggable)

---

## 8. Performance Metrics Mapping

### Entity → Metric Mapping

| Entity | Primary Metric | Secondary Metric | Target |
|--------|----------------|------------------|--------|
| CompositorConfig | CPU usage (kwin_x11) | Frame drops per minute | < 20% CPU, 0 drops |
| EffectsConfig | CPU overhead | Rendering latency | < 5% total, < 50ms |
| AnimationConfig | Transition time | Perceived smoothness | 0ms (instant) |
| ServiceConfig | RAM usage | Background CPU | 1-2GB freed, < 5% CPU |
| VMResourceSpec | UI latency spikes | CPU steal time | < 5ms p95, < 1% |
| RustDeskConfig | Network bandwidth | Connection latency | < 30 Mbps, < 50ms |
| QtPlatformConfig | Font rendering | DPI accuracy | Sharp fonts, correct size |

---

## Conclusion

This data model defines the complete structure of entities involved in KDE Plasma performance optimization for KubeVirt VMs. All entities are configured declaratively via NixOS modules (where possible), with clear validation rules and state transitions.

**Implementation**: Phases 2-5 of plan.md will implement modules to manage these entities.

**Next Steps**: Create contract specifications for configuration interfaces (Phase 1 continuation).

---

**Document Version**: 1.0
**Last Updated**: 2025-10-14
**Status**: Design Complete
