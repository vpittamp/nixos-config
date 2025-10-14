# Implementation Plan: KDE Plasma Performance Optimization for KubeVirt VMs

**Feature ID**: 002
**Status**: Planning
**Created**: 2025-10-14
**Target Timeline**: 7 days

## Summary

Optimize KDE Plasma desktop performance in KubeVirt virtual machines accessed via RustDesk by:
1. Switching compositor to XRender backend and disabling expensive visual effects
2. Optimizing KubeVirt VM resource allocation (dedicated CPUs, increased vCPUs/RAM, IOThreads)
3. Disabling unnecessary desktop services (Baloo indexer, Akonadi PIM)
4. Tuning RustDesk codec and compression settings

Expected outcome: 2-3x improvement in perceived responsiveness without hardware changes.

## Technical Context

- **Language**: Nix expression language
- **Framework**: NixOS 24.11+ with home-manager
- **Platform**: KubeVirt VMs on Kubernetes cluster (Hetzner host)
- **Desktop**: KDE Plasma 6 with X11 session
- **Remote Access**: RustDesk over Tailscale/LAN
- **Storage**: Kubernetes PVC for VM disks
- **Graphics**: Software rendering via llvmpipe (no GPU passthrough)
- **Testing**: `nixos-rebuild dry-build --flake .#<target>` before applying

## Constitution Check

Validating against `.specify/memory/constitution.md`:

### ✅ I. Modular Composition
- Creating separate modules: `modules/desktop/kde-plasma-vm.nix` for VM-specific compositor settings
- Reusing existing: `modules/desktop/kde-plasma.nix` as base
- KubeVirt config separate in `configurations/vm-hetzner.nix`

### ✅ II. Hetzner as Reference Implementation
- Base Hetzner configuration remains unchanged
- VM-specific optimizations in separate KubeVirt configuration
- Hetzner base continues to serve as reference for other targets

### ✅ III. Test-Before-Apply (NON-NEGOTIABLE)
- All phases include `nixos-rebuild dry-build` step before applying
- Baseline measurements before optimization
- Validation testing after each phase

### ✅ IV. Override Priority Discipline
- Using `lib.mkDefault` for compositor settings in base module
- Using `lib.mkForce` in VM module to override for performance
- Clear documentation of override rationale

### ✅ V. Platform Flexibility Through Conditional Features
- VM optimizations conditionally applied based on virtualization detection
- Desktop effects enabled by default, disabled only in VM context
- Service disabling (Baloo, Akonadi) configurable via options

### ✅ VI. Declarative Configuration Over Imperative
- All compositor settings in Nix modules
- KubeVirt VM spec declaratively defined (YAML/Nix)
- RustDesk config declarative where possible
- **Allowable exception**: Plasma user settings may require capture script (per constitution)

### ✅ VII. Documentation as Code
- This plan.md documents implementation approach
- Code comments explain performance trade-offs
- README.md provides feature overview
- research.md consolidates technical findings

## Phase 0: Research Documentation

**Goal**: Consolidate research findings from 3 research agents into unified documentation.

**Duration**: 0.5 days

**Tasks**:
1. Review research agent outputs:
   - KubeVirt GPU passthrough and graphics acceleration research
   - Remote desktop protocol optimization for VMs research
   - KDE Plasma compositor settings for VM performance research

2. Create `research.md` with sections:
   - KDE Compositor Backend Analysis (XRender vs OpenGL in VMs)
   - Visual Effects Performance Impact
   - KubeVirt Resource Allocation Best Practices
   - Remote Desktop Protocol Comparison (RustDesk, xrdp, VNC)
   - Service Overhead Analysis (Baloo, Akonadi, systemd)

3. Document key findings with sources and measurements

**Deliverables**:
- `/etc/nixos/specs/002-kde-plasma-performance/research.md`

**Success Criteria**:
- All research findings consolidated
- Performance claims backed by measurements or credible sources
- Clear rationale for each optimization decision

## Phase 1: Design & Architecture

**Goal**: Design NixOS modules and configuration structure for performance optimizations.

**Duration**: 1 day

**Tasks**:

### 1.1 Design Compositor Module
- Create `modules/desktop/kde-plasma-vm.nix` for VM-specific settings
- Define options for disabling effects, backend selection, FPS limits
- Document override strategy vs base `kde-plasma.nix`

### 1.2 Design Service Management Module
- Create `modules/services/kde-optimization.nix` for service disabling
- Options to control Baloo, Akonadi, unnecessary autostart services
- Conditional enabling based on use case

### 1.3 Design Home-Manager Plasma Config Updates
- Update `home-modules/desktop/plasma-config.nix` with performance settings
- Use plasma-manager for declarative kwinrc configuration
- Ensure settings persist across reboots

### 1.4 Design KubeVirt VM Spec Updates
- Document required changes to VM YAML/Nix spec
- CPU placement strategy (dedicated cores)
- Memory allocation and QoS guarantees
- IOThreads configuration

### 1.5 Create Data Model Documentation
- Document compositor configuration entities
- Document VM resource specification entities
- Document service management states
- Create `data-model.md`

**Deliverables**:
- `/etc/nixos/modules/desktop/kde-plasma-vm.nix` (skeleton)
- `/etc/nixos/modules/services/kde-optimization.nix` (skeleton)
- `/etc/nixos/specs/002-kde-plasma-performance/data-model.md`
- Design notes in plan.md

**Success Criteria**:
- Module structure follows constitution principles
- Clear separation of concerns (base vs VM-optimized)
- Options well-documented with defaults

## Phase 2: Compositor Optimization Implementation

**Goal**: Implement and test KDE compositor performance optimizations.

**Duration**: 1.5 days

**Tasks**:

### 2.1 Implement Base Compositor Module
```nix
# modules/desktop/kde-plasma-vm.nix
{ config, lib, pkgs, ... }:
{
  # XRender backend for CPU-based rendering
  # Disable expensive effects (blur, contrast, wobbly windows)
  # Set FPS limit to 30
  # Disable vsync
  # Set animations to instant
}
```

### 2.2 Update Home-Manager Plasma Configuration
```nix
# home-modules/desktop/plasma-config.nix
"kwinrc".Compositing = {
  Backend = lib.mkForce "XRender";  # Override OpenGL default
  GLCore = false;
  MaxFPS = 30;
  # ... other settings
};

"kwinrc".Plugins = {
  blurEnabled = false;
  contrastEnabled = false;
  # ... disable other expensive effects
};
```

### 2.3 Test on Single VM
- Deploy to test KubeVirt VM
- Measure baseline vs optimized CPU usage (htop)
- Test window operations (drag, resize, switch)
- Measure subjective responsiveness

### 2.4 Document Performance Improvements
- Record CPU usage: before/after
- Record perceived latency: before/after
- Capture screenshots/videos if helpful

**Deliverables**:
- Working compositor optimization module
- Updated plasma-config.nix with performance settings
- Performance measurement data

**Success Criteria**:
- `nixos-rebuild dry-build` succeeds
- Compositor CPU usage < 20% during normal operations
- Window operations feel responsive (< 100ms perceived latency)
- No visual glitches or broken functionality

## Phase 3: Service Optimization Implementation

**Goal**: Disable unnecessary KDE services to free resources.

**Duration**: 0.5 days

**Tasks**:

### 3.1 Implement Service Disabling Module
```nix
# modules/services/kde-optimization.nix
{ config, lib, ... }:
{
  options.services.kde-optimization = {
    disableBaloo = lib.mkEnableOption "Disable Baloo file indexer";
    disableAkonadi = lib.mkEnableOption "Disable Akonadi PIM services";
  };

  config = lib.mkIf config.services.kde-optimization.enable {
    # Disable services declaratively
  };
}
```

### 3.2 Test Service Disabling
- Verify services are stopped: `ps aux | grep -E "baloo|akonadi"`
- Measure RAM usage before/after: `free -h`
- Ensure KDE functionality intact (Dolphin, Konsole, etc.)

**Deliverables**:
- Working service optimization module
- RAM usage comparison data

**Success Criteria**:
- Services successfully disabled
- 1-2GB RAM freed
- No broken KDE functionality

## Phase 4: KubeVirt VM Resource Optimization

**Goal**: Optimize KubeVirt VM resource allocation for better performance.

**Duration**: 1.5 days

**Tasks**:

### 4.1 Update VM Specification
- Increase vCPU count: 6-8 cores
- Set CPU placement: `dedicated` for exclusive core access
- Increase RAM: 8-16GB with guaranteed QoS
- Enable IOThreads for disk performance

### 4.2 Example VM Spec Updates
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
spec:
  template:
    spec:
      domain:
        cpu:
          cores: 8
          sockets: 1
          threads: 1
          dedicatedCpuPlacement: true
        memory:
          guest: 16Gi
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
      volumes:
        - name: rootdisk
          persistentVolumeClaim:
            claimName: nixos-vm-pvc
      ioThreadsPolicy: auto
```

### 4.3 Test Resource Allocation
- Deploy updated VM spec
- Verify CPU placement: `kubectl describe vmi <name>`
- Test performance with increased resources
- Monitor host resource usage

**Deliverables**:
- Updated KubeVirt VM specification
- Resource allocation verification

**Success Criteria**:
- VM successfully runs with increased resources
- Dedicated CPU placement confirmed
- IOThreads enabled and functional
- Noticeable performance improvement

## Phase 5: RustDesk Configuration Optimization

**Goal**: Optimize RustDesk codec and compression settings.

**Duration**: 1 day

**Tasks**:

### 5.1 Test Codec Options
- Test VP8, VP9, H.264 codecs
- Measure perceived quality, latency, bandwidth
- Document optimal codec for LAN/VPN scenarios

### 5.2 Optimize Compression Settings
- Test various quality levels (10-100%)
- Balance quality vs bandwidth
- Document recommended settings

### 5.3 Verify Direct IP Access
- Ensure RustDesk uses direct connection (not relay)
- Test over Tailscale VPN
- Measure connection establishment time

**Deliverables**:
- Documented RustDesk optimal settings
- Configuration guide for users

**Success Criteria**:
- Optimal codec identified for use case
- Connection quality acceptable
- Bandwidth usage < 30 Mbps for 1080p
- Direct IP connection working

## Phase 6: Integration & Testing

**Goal**: Combine all optimizations and perform comprehensive testing.

**Duration**: 1.5 days

**Tasks**:

### 6.1 Integrate All Optimizations
- Enable all modules in VM configuration
- Test combined effect
- Ensure no conflicts between optimizations

### 6.2 Comprehensive Performance Testing
- Window operations (drag, resize, switch)
- Cursor movement smoothness
- Screen update speed (scrolling, typing)
- CPU/RAM usage monitoring
- RustDesk connection quality

### 6.3 Before/After Comparison
- Document baseline measurements (from Phase 0)
- Document optimized measurements
- Calculate improvement percentage
- User subjective feedback (1-10 scale)

### 6.4 Edge Case Testing
- Test with many windows open (10+)
- Test with video playback
- Test with high network latency
- Test with VM resize (more/fewer vCPUs)

**Deliverables**:
- Complete performance benchmark report
- Before/after comparison data
- Edge case test results

**Success Criteria**:
- All user stories pass acceptance scenarios
- 2-3x subjective responsiveness improvement
- All success criteria met (spec.md)
- Zero regressions in functionality

## Phase 7: Documentation & Finalization

**Goal**: Complete documentation and prepare for production deployment.

**Duration**: 0.5 days

**Tasks**:

### 7.1 Update Documentation
- Update README.md with optimization overview
- Create user guide for RustDesk configuration
- Document troubleshooting steps
- Update CLAUDE.md with VM optimization notes

### 7.2 Code Cleanup
- Remove debug code and comments
- Ensure consistent formatting
- Add comprehensive module documentation
- Review constitution compliance

### 7.3 Create Deployment Guide
- Step-by-step VM deployment
- Configuration verification steps
- Performance validation checklist

**Deliverables**:
- Updated documentation files
- Deployment guide
- Clean, production-ready code

**Success Criteria**:
- Documentation complete and accurate
- Code follows Nix style guidelines
- Constitution principles validated
- Ready for production deployment

## Project Structure

```
/etc/nixos/
├── modules/
│   ├── desktop/
│   │   ├── kde-plasma.nix              # Base KDE config (existing)
│   │   └── kde-plasma-vm.nix           # NEW: VM-specific optimizations
│   └── services/
│       └── kde-optimization.nix        # NEW: Service management
│
├── home-modules/
│   └── desktop/
│       └── plasma-config.nix           # MODIFIED: Add performance settings
│
├── configurations/
│   └── vm-hetzner.nix                  # MODIFIED: Enable optimization modules
│
├── specs/002-kde-plasma-performance/
│   ├── README.md                       # Feature overview
│   ├── spec.md                         # Specification (complete)
│   ├── plan.md                         # This file
│   ├── research.md                     # NEW: Research consolidation
│   ├── data-model.md                   # NEW: Entity documentation
│   └── benchmarks/
│       ├── baseline.md                 # NEW: Pre-optimization metrics
│       └── optimized.md                # NEW: Post-optimization metrics
```

## Files to Modify

### High Priority (Core Functionality)
1. `/etc/nixos/modules/desktop/kde-plasma-vm.nix` (NEW) - VM compositor settings
2. `/etc/nixos/home-modules/desktop/plasma-config.nix` (MODIFY) - User settings
3. `/etc/nixos/modules/services/kde-optimization.nix` (NEW) - Service management
4. `/etc/nixos/configurations/vm-hetzner.nix` (MODIFY) - Enable optimizations
5. KubeVirt VM YAML spec (MODIFY) - Resource allocation

### Medium Priority (Documentation)
6. `/etc/nixos/specs/002-kde-plasma-performance/research.md` (NEW)
7. `/etc/nixos/specs/002-kde-plasma-performance/data-model.md` (NEW)
8. `/etc/nixos/CLAUDE.md` (MODIFY) - Add VM optimization notes

### Low Priority (Polish)
9. `/etc/nixos/README.md` (MODIFY) - Mention VM optimizations
10. Benchmark documentation files (NEW)

## Dependencies & Blockers

### External Dependencies
- KubeVirt cluster must have sufficient physical CPU/RAM resources
- Kubernetes storage class must support PVC resize (if needed)
- RustDesk client must be version 1.2.0+ for optimal codec support

### Internal Dependencies
- Phase 2 depends on Phase 1 (design complete)
- Phase 6 depends on Phases 2-5 (all optimizations implemented)
- Phase 7 depends on Phase 6 (testing complete)

### Potential Blockers
1. **KubeVirt resource constraints**: If cluster cannot allocate 8 vCPUs/16GB RAM, may need to reduce allocation
2. **Plasma-manager limitations**: Some settings may not be declaratively configurable, may need imperative script (allowed by constitution)
3. **RustDesk codec support**: Some codecs may not work well with Wayland (mitigated by using X11)

## Risk Mitigation

### Risk 1: Performance Optimization Insufficient
- **Likelihood**: Medium
- **Impact**: High
- **Mitigation**: Phase 2 includes early testing; if insufficient, escalate to GPU passthrough investigation

### Risk 2: Service Disabling Breaks Functionality
- **Likelihood**: Low
- **Impact**: Medium
- **Mitigation**: Thorough testing in Phase 3; make service disabling optional

### Risk 3: KubeVirt Resource Allocation Fails
- **Likelihood**: Low
- **Impact**: High
- **Mitigation**: Test resource allocation on non-production VM first; have fallback allocation strategy

### Risk 4: RustDesk Codec Incompatibility
- **Likelihood**: Low
- **Impact**: Medium
- **Mitigation**: Test multiple codecs in Phase 5; fallback to xrdp if needed

## Success Metrics

### Primary Metrics (Must Achieve)
- ✅ Compositor CPU usage < 20% during normal operations
- ✅ Window operations perceived latency < 100ms
- ✅ Screen updates maintain 25-30 FPS
- ✅ 2-3x subjective responsiveness improvement (user feedback)

### Secondary Metrics (Nice to Have)
- 🎯 Idle RAM usage decreased by 1-2GB
- 🎯 Background CPU usage < 5%
- 🎯 RustDesk bandwidth < 30 Mbps for 1080p

### Configuration Quality Metrics
- ✅ Zero imperative scripts (except Plasma settings capture)
- ✅ All modules pass dry-build test
- ✅ Configuration reproducible across VM rebuilds
- ✅ Constitution compliance: 7/7 principles followed

## Timeline Summary

| Phase | Duration | Days | Deliverable |
|-------|----------|------|-------------|
| Phase 0: Research | 0.5 days | Day 1 | research.md |
| Phase 1: Design | 1.0 days | Day 1-2 | Module skeletons, data-model.md |
| Phase 2: Compositor | 1.5 days | Day 2-3 | Working compositor optimization |
| Phase 3: Services | 0.5 days | Day 4 | Service disabling module |
| Phase 4: VM Resources | 1.5 days | Day 4-5 | Updated VM spec |
| Phase 5: RustDesk | 1.0 days | Day 6 | Codec optimization guide |
| Phase 6: Integration | 1.5 days | Day 6-7 | Benchmark report |
| Phase 7: Documentation | 0.5 days | Day 7 | Complete documentation |
| **TOTAL** | **7.5 days** | | Production-ready optimization |

## Next Steps

1. **Immediate**: Create research.md (Phase 0) consolidating findings from 3 research agents
2. **Day 1-2**: Design module architecture (Phase 1)
3. **Day 2-3**: Implement compositor optimizations (Phase 2)
4. **Day 4-7**: Continue through remaining phases
5. **Day 7**: Production deployment

## Open Questions

1. Should GPU passthrough be investigated as Phase 8 (future work)?
2. Should we create automated performance benchmarking scripts?
3. Should RustDesk configuration be system-wide or per-user?
4. Should we support multiple VM profiles (minimal, balanced, performance)?

---

**Plan Version**: 1.0
**Last Updated**: 2025-10-14
**Status**: Ready for Phase 0 execution
