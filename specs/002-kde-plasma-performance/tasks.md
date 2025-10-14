# Implementation Tasks: KDE Plasma Performance Optimization for KubeVirt VMs

**Feature ID**: 002
**Branch**: `002-kde-plasma-performance`
**Status**: Ready for Implementation
**Total Tasks**: 45
**Estimated Timeline**: 7 days

This document defines all implementation tasks organized by user story priority. Each user story represents an independently testable increment of functionality.

---

## Task Organization Strategy

Tasks are organized into phases:
1. **Phase 1: Setup** - Project initialization and scaffolding
2. **Phase 2: Foundational** - Blocking prerequisites required by all user stories
3. **Phase 3-9: User Stories** - One phase per user story (P1 → P2 → P3 → P4)
4. **Phase 10: Polish** - Cross-cutting concerns and final integration

**Parallel Execution**: Tasks marked `[P]` can be executed in parallel with other `[P]` tasks in the same phase.

**Story Labels**: Tasks labeled `[US#]` map to specific user stories for traceability.

---

## Phase 1: Setup (Project Initialization)

**Goal**: Initialize project structure and tooling required for all user stories.

**Duration**: 0.5 days

### T001 [P] - Create Module Directory Structure
**File**: `/etc/nixos/modules/desktop/kde-plasma-vm.nix` (create directory if needed)
**Description**: Create NixOS module directory structure for VM-specific optimizations
```bash
mkdir -p /etc/nixos/modules/desktop
mkdir -p /etc/nixos/modules/services
```
**Validation**: Directories exist and are writable
**Dependencies**: None

### T002 [P] - Create Benchmarking Documentation Structure
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/`
**Description**: Create directory for performance benchmarking documentation
```bash
mkdir -p /etc/nixos/specs/002-kde-plasma-performance/benchmarks
```
**Validation**: Directory exists
**Dependencies**: None

### T003 [P] - Create Verification Script Stub
**File**: `/etc/nixos/specs/002-kde-plasma-performance/scripts/verify-optimizations.sh`
**Description**: Create placeholder verification script for post-deployment validation
```bash
#!/usr/bin/env bash
# Verification script for KDE Plasma optimizations
echo "Verification script - to be implemented in Phase 10"
```
**Validation**: Script exists and is executable
**Dependencies**: None

**Checkpoint**: ✅ Project structure initialized

---

## Phase 2: Foundational (Blocking Prerequisites)

**Goal**: Establish baseline measurements and configuration foundations that all user stories depend on.

**Duration**: 0.5 days

### T004 - Capture Baseline Performance Metrics
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/baseline.md`
**Description**: Measure and document current (unoptimized) performance
- Run `htop` and record kwin_x11 CPU usage (idle and active)
- Run `free -h` and record RAM usage
- Run `ps aux | wc -l` and record process count
- Subjectively test window drag latency (1-10 scale)
- Test Alt+Tab responsiveness (1-10 scale)
- Measure cursor smoothness (1-10 scale)
**Validation**: baseline.md contains all measurements with timestamps
**Dependencies**: None

### T005 - Read Existing KDE Configuration
**File**: `/etc/nixos/home-modules/desktop/plasma-config.nix` (read only)
**Description**: Read and document current KDE Plasma configuration settings
- Note current compositor backend (likely OpenGL)
- Note currently enabled effects
- Note current animation settings
- Document in baseline.md for comparison
**Validation**: Current settings documented
**Dependencies**: T004

### T006 - Create NixOS Module Template for VM Optimizations
**File**: `/etc/nixos/modules/desktop/kde-plasma-vm.nix`
**Description**: Create skeleton module structure with options definition
```nix
{ config, lib, pkgs, ... }:

{
  options.desktop.kde-vm-optimization = {
    enable = lib.mkEnableOption "KDE Plasma VM performance optimizations";
    # Additional options will be added in US1 and US2
  };

  config = lib.mkIf config.desktop.kde-vm-optimization.enable {
    # Implementation will be added in user story phases
  };
}
```
**Validation**: Module compiles with `nixos-rebuild dry-build`
**Dependencies**: T001

**Checkpoint**: ✅ Baseline established, foundational structure ready

---

## Phase 3: User Story 1 - Responsive Window Operations (P1)

**Goal**: Optimize compositor for instant, responsive window operations (< 100ms latency).

**User Story**: As a remote desktop user, I need window operations (moving, resizing, switching) to feel instant and responsive when accessing my KubeVirt VM via RustDesk.

**Independent Test Criteria**:
- Open 5-10 windows, drag them around the screen
- Resize windows by dragging edges
- Switch between windows with Alt+Tab
- Click windows to change focus
- SUCCESS: All operations feel instantaneous (< 100ms perceived latency)

**Duration**: 1.5 days

### T007 [US1] - Define Compositor Configuration Options
**File**: `/etc/nixos/modules/desktop/kde-plasma-vm.nix`
**Description**: Add compositor-specific options to module following `contracts/compositor-config.nix`
```nix
options.desktop.kde-vm-optimization.compositor = {
  backend = lib.mkOption {
    type = lib.types.enum [ "OpenGL" "XRender" ];
    default = "XRender";
    description = "Compositor rendering backend";
  };
  maxFPS = lib.mkOption {
    type = lib.types.ints.between 10 144;
    default = 30;
    description = "Maximum frames per second";
  };
  # Add all options from compositor-config.nix contract
};
```
**Validation**: Options compile, dry-build succeeds
**Dependencies**: T006
**Implements**: FR-001, FR-003, FR-004

### T008 [US1] - Implement XRender Backend Configuration
**File**: `/etc/nixos/home-modules/desktop/plasma-config.nix`
**Description**: Configure KWin to use XRender backend for CPU-based rendering
```nix
"kwinrc".Compositing = {
  Backend = lib.mkForce "XRender";
  GLCore = false;
  GLPreferBufferSwap = "n";
  OpenGLIsUnsafe = false;
  WindowsBlockCompositing = true;
};
```
**Validation**: After rebuild, `kreadconfig5 --file kwinrc --group Compositing --key Backend` returns "XRender"
**Dependencies**: T007
**Implements**: FR-001

### T009 [US1] - Configure Frame Rate Limiting
**File**: `/etc/nixos/home-modules/desktop/plasma-config.nix`
**Description**: Set MaxFPS to 30 and disable VSync for lower latency
```nix
"kwinrc".Compositing = {
  MaxFPS = 30;
  MaxFPSInterval = 33333333;  # 1/30 second in nanoseconds
  VSync = false;
  HiddenPreviews = 5;
};
```
**Validation**: After rebuild, compositor FPS capped at 30, VSync disabled
**Dependencies**: T008
**Implements**: FR-003, FR-004

### T010 [US1] - Test Window Drag Responsiveness
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us1-window-operations.md`
**Description**: Perform subjective window operation tests
- Drag multiple windows across screen
- Resize windows
- Measure perceived latency (1-10 scale, target ≥ 8)
- Record CPU usage during operations
- Document results in us1-window-operations.md
**Validation**: Window operations feel responsive (< 100ms), CPU usage < 20%
**Dependencies**: T009
**Validates**: US1 Acceptance Scenarios 1, 3

### T011 [US1] - Test Alt+Tab Switching Performance
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us1-window-operations.md` (append)
**Description**: Test window switching responsiveness
- Open 10+ windows
- Rapidly press Alt+Tab
- Measure switcher appearance delay
- Test window focus changes
- Document results
**Validation**: Switcher appears instantly (< 50ms perceived), transitions smooth
**Dependencies**: T009
**Validates**: US1 Acceptance Scenarios 2, 4

**Checkpoint**: ✅ US1 Complete - Window operations responsive, compositor uses XRender backend

---

## Phase 4: User Story 2 - Low CPU Compositor Usage (P1)

**Goal**: Reduce compositor CPU usage to < 20% during normal operations by disabling expensive visual effects.

**User Story**: As a system administrator, I need the KDE compositor to use minimal CPU resources (< 20% during normal operations).

**Independent Test Criteria**:
- Monitor `htop` filtered to `kwin_x11` process
- Perform normal desktop operations (open/close windows, browse, edit documents)
- Measure idle CPU (target < 5%) and active CPU (target < 20%)
- SUCCESS: Compositor CPU usage stays below targets

**Duration**: 1 day

### T012 [US2] - Define Effects Configuration Options
**File**: `/etc/nixos/modules/desktop/kde-plasma-vm.nix`
**Description**: Add visual effects options to module following `contracts/effects-config.nix`
```nix
options.desktop.kde-vm-optimization.effects = {
  disableExpensive = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Disable expensive effects (blur, translucency, etc.)";
  };
  # Individual effect toggles
};
```
**Validation**: Options compile
**Dependencies**: T007
**Implements**: FR-002

### T013 [US2] [P] - Disable Blur Effect
**File**: `/etc/nixos/home-modules/desktop/plasma-config.nix`
**Description**: Disable blur effect behind windows (saves 15-25% CPU)
```nix
"kwinrc".Plugins.blurEnabled = false;
```
**Validation**: Blur effect disabled, no blur visible behind windows
**Dependencies**: T012
**Implements**: FR-002

### T014 [US2] [P] - Disable Background Contrast Effect
**File**: `/etc/nixos/home-modules/desktop/plasma-config.nix`
**Description**: Disable background contrast effect (saves 10-15% CPU)
```nix
"kwinrc".Plugins.contrastEnabled = false;
```
**Validation**: Background contrast disabled
**Dependencies**: T012
**Implements**: FR-002

### T015 [US2] [P] - Disable Translucency Effect
**File**: `/etc/nixos/home-modules/desktop/plasma-config.nix`
**Description**: Disable window translucency effect (saves 10-20% CPU)
```nix
"kwinrc".Plugins.kwin4_effect_translucencyEnabled = false;
```
**Validation**: Translucency disabled, windows fully opaque
**Dependencies**: T012
**Implements**: FR-002

### T016 [US2] [P] - Disable Wobbly Windows Effect
**File**: `/etc/nixos/home-modules/desktop/plasma-config.nix`
**Description**: Disable wobbly windows animation effect (saves 8-12% CPU)
```nix
"kwinrc".Plugins.wobblywindowsEnabled = false;
```
**Validation**: Wobbly windows disabled
**Dependencies**: T012
**Implements**: FR-002

### T017 [US2] [P] - Disable Magic Lamp Effect
**File**: `/etc/nixos/home-modules/desktop/plasma-config.nix`
**Description**: Disable magic lamp minimize animation (saves 5-8% CPU)
```nix
"kwinrc".Plugins.magiclampEnabled = false;
```
**Validation**: Magic lamp effect disabled
**Dependencies**: T012
**Implements**: FR-002

### T018 [US2] [P] - Disable Desktop Cube Effect
**File**: `/etc/nixos/home-modules/desktop/plasma-config.nix`
**Description**: Ensure desktop cube remains disabled (saves 15-25% CPU if enabled)
```nix
"kwinrc".Plugins.cubeslideEnabled = false;
```
**Validation**: Desktop cube disabled
**Dependencies**: T012
**Implements**: FR-002

### T019 [US2] - Configure Instant Animations
**File**: `/etc/nixos/home-modules/desktop/plasma-config.nix`
**Description**: Set all animation durations to 0 for instant transitions
```nix
"kdeglobals".KDE.AnimationDurationFactor = 0;
"kwinrc"."Effect-Slide".Duration = 0;
"kwinrc"."Effect-PresentWindows".Duration = 0;
"kwinrc"."Effect-Fade".Duration = 0;
```
**Validation**: All transitions instant, no animation delays
**Dependencies**: T012
**Implements**: FR-005

### T020 [US2] - Measure Compositor CPU Usage
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us2-cpu-usage.md`
**Description**: Measure compositor CPU usage after optimizations
- Monitor kwin_x11 CPU usage idle (target < 5%)
- Monitor kwin_x11 CPU usage active (target < 20%)
- Monitor average CPU usage over 1 hour (target < 10%)
- Compare with baseline (T004)
- Document CPU savings percentage
**Validation**: CPU usage meets all targets, improvement documented
**Dependencies**: T013-T019
**Validates**: US2 Acceptance Scenarios 1, 2, 3, 4

**Checkpoint**: ✅ US2 Complete - Compositor CPU usage < 20%, expensive effects disabled

**Parallel Execution Example for Phase 4**:
```bash
# Tasks T013-T018 can run in parallel (different plugin settings)
nix-shell -p parallel --run "
  parallel ::: \
    'edit plasma-config.nix # T013 blur' \
    'edit plasma-config.nix # T014 contrast' \
    'edit plasma-config.nix # T015 translucency' \
    'edit plasma-config.nix # T016 wobbly' \
    'edit plasma-config.nix # T017 magic lamp' \
    'edit plasma-config.nix # T018 cube'
"
# Then T019 (sequential), then T020 (measurement)
```

---

## Phase 5: User Story 3 - Smooth Cursor Movement (P2)

**Goal**: Ensure mouse cursor moves smoothly without jumpiness or lag.

**User Story**: As a remote desktop user, I need the mouse cursor to move smoothly without jumpiness or lag.

**Independent Test Criteria**:
- Move cursor rapidly across screen in various patterns
- Draw circles with cursor
- Click rapidly on various UI elements
- Perform drag-and-drop operations
- SUCCESS: Cursor tracks smoothly without jumping, hover effects immediate (< 100ms)

**Duration**: 0.5 days

**Note**: Cursor smoothness primarily depends on compositor optimizations from US1 and US2. This phase focuses on validation and any additional tuning.

### T021 [US3] - Configure Qt Platform for X11
**File**: `/etc/nixos/modules/desktop/kde-plasma-vm.nix`
**Description**: Ensure Qt uses XCB platform for optimal X11 rendering
```nix
config = lib.mkIf config.desktop.kde-vm-optimization.enable {
  environment.sessionVariables = {
    QT_QPA_PLATFORM = "xcb";
    QT_AUTO_SCREEN_SCALE_FACTOR = "0";
    QT_SCALE_FACTOR = "1";
  };
};
```
**Validation**: Qt applications use XCB platform
**Dependencies**: T006
**Implements**: FR-012, FR-013

### T022 [US3] - Test Cursor Movement Smoothness
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us3-cursor.md`
**Description**: Perform cursor smoothness tests
- Move cursor rapidly across screen
- Draw circular patterns
- Measure perceived cursor lag (visual inspection)
- Test hover effects on UI elements (< 100ms delay)
- Perform drag-and-drop operations
- Document results and perceived smoothness (1-10 scale, target ≥ 8)
**Validation**: Cursor movement smooth, no jumpiness, hover effects immediate
**Dependencies**: T021, T009 (depends on compositor optimizations)
**Validates**: US3 Acceptance Scenarios 1, 2, 3, 4

**Checkpoint**: ✅ US3 Complete - Cursor movement smooth and responsive

---

## Phase 6: User Story 4 - Fast Screen Updates (P2)

**Goal**: Ensure screen content updates quickly (25-30 FPS) when scrolling or changing views.

**User Story**: As a remote desktop user, I need screen content to update quickly when scrolling or changing views.

**Independent Test Criteria**:
- Scroll through long documents in browser and editor
- Type rapidly in document editor
- Scroll through large file lists in file manager
- Monitor frame rate during screen updates
- SUCCESS: Smooth 25-30 FPS rendering, < 50ms typing latency

**Duration**: 0.5 days

**Note**: Screen update performance primarily depends on compositor optimizations (US1, US2) and frame rate limiting. This phase focuses on validation.

### T023 [US4] - Test Browser Scrolling Performance
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us4-screen-updates.md`
**Description**: Test screen update performance in web browser
- Open long web page
- Scroll rapidly
- Observe visual smoothness (target 25-30 FPS)
- Check for tearing or frame drops
- Document results
**Validation**: Scrolling smooth at 25-30 FPS, no visible tearing
**Dependencies**: T009 (depends on FPS limiting)
**Validates**: US4 Acceptance Scenario 1

### T024 [US4] - Test Document Editor Typing Latency
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us4-screen-updates.md` (append)
**Description**: Test typing responsiveness in document editor
- Open document editor (Kate, LibreOffice)
- Type rapidly
- Measure perceived latency between keypress and character appearance
- Target: < 50ms latency
- Document results
**Validation**: Text appears immediately, < 50ms perceived latency
**Dependencies**: T009
**Validates**: US4 Acceptance Scenario 2

### T025 [US4] - Test File Manager Scrolling
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us4-screen-updates.md` (append)
**Description**: Test scrolling performance in file manager
- Open Dolphin with directory containing many files
- Scroll through list rapidly
- Observe smoothness and frame drops
- Document results
**Validation**: Scrolling smooth, no frame drops
**Dependencies**: T009
**Validates**: US4 Acceptance Scenario 3

### T026 [US4] - Test RustDesk Screen Update Compression
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us4-screen-updates.md` (append)
**Description**: Test screen update latency over RustDesk
- Connect via RustDesk
- Perform screen updates (scroll, type, open windows)
- Measure delay between local action and remote screen update
- Target: < 100ms
- Document results
**Validation**: Screen updates appear within 100ms over RustDesk
**Dependencies**: T009
**Validates**: US4 Acceptance Scenario 4

**Checkpoint**: ✅ US4 Complete - Screen updates fast and smooth (25-30 FPS)

---

## Phase 7: User Story 5 - Minimal Resource Overhead (P3)

**Goal**: Disable unnecessary KDE services (Baloo, Akonadi) to free 1-2GB RAM and reduce background CPU usage.

**User Story**: As a system administrator, I need unnecessary KDE services (Baloo indexing, Akonadi PIM) to be disabled in VM environment.

**Independent Test Criteria**:
- Run `ps aux | grep -E "baloo|akonadi"` (should return no results)
- Measure RAM usage with `free -h` (compare with baseline)
- Monitor background CPU usage
- SUCCESS: 1-2GB RAM freed, background CPU < 5%

**Duration**: 0.5 days

### T027 [US5] - Create Service Optimization Module
**File**: `/etc/nixos/modules/services/kde-optimization.nix`
**Description**: Create new module for KDE service management following `contracts/service-config.nix`
```nix
{ config, lib, ... }:

{
  options.services.kde-optimization = {
    enable = lib.mkEnableOption "KDE service optimization for VMs";
    baloo.disable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable Baloo file indexer";
    };
    akonadi.disable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable Akonadi PIM services";
    };
  };

  config = lib.mkIf config.services.kde-optimization.enable {
    # Implementation in subsequent tasks
  };
}
```
**Validation**: Module compiles
**Dependencies**: T001
**Implements**: FR-006, FR-007

### T028 [US5] - Implement Baloo Disabling
**File**: `/etc/nixos/modules/services/kde-optimization.nix`
**Description**: Add Baloo disabling configuration
```nix
config = lib.mkMerge [
  (lib.mkIf config.services.kde-optimization.baloo.disable {
    home-manager.users.<username> = {
      xdg.configFile."baloofilerc".text = lib.generators.toINI {} {
        "Basic Settings" = {
          Indexing-Enabled = false;
        };
      };
      systemd.user.services.baloo_file.enable = false;
      systemd.user.services.baloo_file_extractor.enable = false;
    };
  })
];
```
**Validation**: After rebuild, Baloo services stopped and masked
**Dependencies**: T027
**Implements**: FR-006

### T029 [US5] - Implement Akonadi Disabling
**File**: `/etc/nixos/modules/services/kde-optimization.nix`
**Description**: Add Akonadi disabling configuration
```nix
(lib.mkIf config.services.kde-optimization.akonadi.disable {
  home-manager.users.<username> = {
    xdg.configFile."akonadi/akonadiserverrc".text = lib.generators.toINI {} {
      "%General" = {
        StartServer = false;
      };
    };
    systemd.user.services.akonadi_control.enable = false;
  };
})
```
**Validation**: After rebuild, Akonadi services stopped
**Dependencies**: T027
**Implements**: FR-007

### T030 [US5] - Integrate Service Module into Configuration
**File**: `/etc/nixos/configurations/vm-hetzner.nix`
**Description**: Import and enable kde-optimization module
```nix
imports = [
  ../modules/services/kde-optimization.nix
];

services.kde-optimization = {
  enable = true;
  baloo.disable = true;
  akonadi.disable = true;
};
```
**Validation**: Configuration imports cleanly
**Dependencies**: T029

### T031 [US5] - Verify Services Disabled
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us5-services.md`
**Description**: Verify Baloo and Akonadi are not running
```bash
# Should return no results (or only grep itself)
ps aux | grep -E "baloo|akonadi"

# Verify systemd units masked
systemctl --user status baloo_file
systemctl --user status akonadi_control
```
**Validation**: No Baloo or Akonadi processes running
**Dependencies**: T030
**Validates**: US5 Acceptance Scenarios 1, 2

### T032 [US5] - Measure RAM Savings
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us5-services.md` (append)
**Description**: Measure RAM usage after service optimization
- Run `free -h` and note available memory
- Compare with baseline (T004)
- Calculate RAM savings (target: 1-2GB freed)
- Measure background CPU usage (target: < 5%)
- Document results
**Validation**: 1-2GB RAM freed, background CPU < 5%
**Dependencies**: T031
**Validates**: US5 Acceptance Scenarios 3, 4

**Checkpoint**: ✅ US5 Complete - Unnecessary services disabled, 1-2GB RAM freed

---

## Phase 8: User Story 6 - Optimized RustDesk Configuration (P3)

**Goal**: Document optimal RustDesk codec and compression settings for LAN/VPN scenarios.

**User Story**: As a remote desktop user, I need RustDesk configured with optimal codec and compression settings.

**Independent Test Criteria**:
- Test VP8, VP9, H.264 codecs
- Measure bandwidth usage (target < 30 Mbps for 1080p)
- Measure connection latency (target < 50ms)
- Test direct IP access over Tailscale
- SUCCESS: Optimal codec documented, connection quality acceptable

**Duration**: 1 day

**Note**: RustDesk is client-side configuration (not NixOS modules). This phase focuses on testing and documentation.

### T033 [US6] - Test VP8 Codec Performance
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us6-rustdesk.md`
**Description**: Test RustDesk with VP8 codec
- Connect to VM with RustDesk, select VP8 codec
- Set quality to 80-90%
- Monitor bandwidth usage (RustDesk stats)
- Measure perceived latency and quality (1-10 scale)
- Test over LAN
- Document results (bandwidth, latency, quality)
**Validation**: VP8 performance documented
**Dependencies**: None (can run anytime after US1-US4 complete)
**Validates**: US6 Acceptance Scenarios 1, 2

### T034 [US6] - Test VP9 Codec Performance
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us6-rustdesk.md` (append)
**Description**: Test RustDesk with VP9 codec
- Connect with VP9 codec
- Set quality to 70-80%
- Monitor bandwidth and latency
- Compare with VP8 results
- Document results
**Validation**: VP9 performance documented
**Dependencies**: T033
**Validates**: US6 Acceptance Scenarios 1, 2

### T035 [US6] - Test H.264 Codec Performance
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us6-rustdesk.md` (append)
**Description**: Test RustDesk with H.264 codec (if available)
- Connect with H.264 codec
- Monitor bandwidth and latency
- Compare with VP8 and VP9
- Document results
**Validation**: H.264 performance documented
**Dependencies**: T034
**Validates**: US6 Acceptance Scenarios 1, 2

### T036 [US6] - Verify Direct IP Access
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us6-rustdesk.md` (append)
**Description**: Test RustDesk direct connection over Tailscale
- Configure RustDesk for direct IP connection
- Verify connection not using relay server
- Measure connection establishment time (target < 3 seconds)
- Document configuration steps
**Validation**: Direct IP access confirmed, connection < 3 seconds
**Dependencies**: None
**Validates**: US6 Acceptance Scenario 4
**Implements**: FR-014

### T037 [US6] - Document Optimal RustDesk Settings
**File**: `/etc/nixos/specs/002-kde-plasma-performance/docs/rustdesk-configuration.md`
**Description**: Create user guide for optimal RustDesk configuration
- Recommend best codec for LAN (likely VP8 or H.264)
- Recommend best codec for VPN (likely VP9)
- Document quality/bandwidth trade-offs
- Provide step-by-step configuration instructions
- Include screenshots if helpful
**Validation**: Documentation complete, covers all scenarios
**Dependencies**: T033-T036
**Implements**: FR-015
**Validates**: US6 Acceptance Scenario 3

**Checkpoint**: ✅ US6 Complete - RustDesk optimal settings documented

---

## Phase 9: User Story 7 - Declarative Configuration (P4)

**Goal**: Ensure all optimizations are declaratively defined in NixOS configuration files (constitution compliance).

**User Story**: As a system administrator, I need all performance optimizations defined in NixOS configuration files.

**Independent Test Criteria**:
- Build fresh VM from NixOS configuration
- Verify all compositor settings applied automatically
- Verify all services disabled without manual intervention
- Run `nixos-rebuild dry-build` successfully
- SUCCESS: Zero manual configuration steps required, all settings reproducible

**Duration**: 1 day

### T038 [US7] - Audit Configuration for Imperative Steps
**File**: `/etc/nixos/specs/002-kde-plasma-performance/docs/configuration-audit.md`
**Description**: Review all implemented configurations and identify any imperative steps
- Check all modules for hardcoded paths or manual steps
- Verify no post-install scripts required (except allowed Plasma capture)
- Verify all settings in Nix expressions
- Document findings
**Validation**: Zero imperative steps identified (except allowed exceptions)
**Dependencies**: T030 (all modules implemented)
**Implements**: FR-016
**Validates**: US7 Acceptance Scenario 2

### T039 [US7] - Create Dry-Build Test Script
**File**: `/etc/nixos/specs/002-kde-plasma-performance/scripts/test-dry-build.sh`
**Description**: Create script to test configuration without applying
```bash
#!/usr/bin/env bash
set -euo pipefail
echo "Testing KDE Plasma optimization configuration..."
nixos-rebuild dry-build --flake .#vm-hetzner
echo "✅ Dry-build successful - configuration is valid"
```
**Validation**: Script runs successfully
**Dependencies**: T030
**Implements**: FR-017

### T040 [US7] - Test Fresh VM Deployment
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us7-reproducibility.md`
**Description**: Deploy configuration to fresh VM and verify automatic application
- Create new KubeVirt VM
- Apply NixOS configuration
- Boot VM
- Verify compositor settings applied (kreadconfig5 checks)
- Verify services disabled (ps aux checks)
- Verify no manual steps required
- Document deployment process and validation results
**Validation**: All settings applied automatically, zero manual steps
**Dependencies**: T030
**Validates**: US7 Acceptance Scenarios 1, 2, 3

### T041 [US7] - Test Configuration Reproducibility
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us7-reproducibility.md` (append)
**Description**: Deploy configuration twice and verify identical performance
- Deploy configuration to VM-A
- Deploy same configuration to VM-B
- Run identical performance tests on both VMs
- Compare results (should be nearly identical)
- Document reproducibility verification
**Validation**: Performance identical across deployments
**Dependencies**: T040
**Validates**: US7 Acceptance Scenario 4
**Implements**: FR-019

### T042 [US7] - Verify KubeVirt VM Spec Compliance
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us7-reproducibility.md` (append)
**Description**: Verify KubeVirt VM spec matches requirements
```bash
kubectl describe vmi <vm-name> | grep -A 10 "CPU"
kubectl describe vmi <vm-name> | grep -A 5 "Memory"
kubectl describe vmi <vm-name> | grep "dedicatedCpuPlacement"
kubectl describe vmi <vm-name> | grep "ioThreadsPolicy"
```
- Document current VM spec
- Create updated VM spec following `contracts/kubevirt-vm-spec.yaml`
- Note: Actual VM updates performed by operations team (outside NixOS scope)
**Validation**: VM spec requirements documented
**Dependencies**: None
**Validates**: US7 Acceptance Scenario 3
**Implements**: FR-008, FR-009, FR-010, FR-011, FR-018

**Checkpoint**: ✅ US7 Complete - All configurations declarative and reproducible

---

## Phase 10: Polish & Cross-Cutting Concerns

**Goal**: Final integration, documentation updates, and comprehensive testing.

**Duration**: 1 day

### T043 - Implement Verification Script
**File**: `/etc/nixos/specs/002-kde-plasma-performance/scripts/verify-optimizations.sh`
**Description**: Complete verification script started in T003
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== KDE Plasma Optimization Verification ==="

# Check compositor backend
BACKEND=$(kreadconfig5 --file kwinrc --group Compositing --key Backend)
echo "✓ Compositor backend: $BACKEND (expected: XRender)"

# Check services disabled
echo "✓ Checking services..."
! pgrep -f baloo_file && echo "  ✓ Baloo disabled" || echo "  ✗ Baloo running"
! pgrep -f akonadi && echo "  ✓ Akonadi disabled" || echo "  ✗ Akonadi running"

# Check CPU usage
KWIN_CPU=$(top -b -n 1 | grep kwin_x11 | awk '{print $9}')
echo "✓ KWin CPU usage: ${KWIN_CPU}% (target: < 20%)"

# Check RAM available
FREE_RAM=$(free -h | grep Mem | awk '{print $7}')
echo "✓ Available RAM: $FREE_RAM"

echo "=== Verification Complete ==="
```
**Validation**: Script runs and reports all metrics
**Dependencies**: T030 (all optimizations implemented)

### T044 - Update CLAUDE.md with Optimization Commands
**File**: `/etc/nixos/CLAUDE.md`
**Description**: Add section for VM optimization commands
```markdown
## 🎨 KDE Plasma VM Optimization

### Quick Verification

```bash
# Verify optimizations applied
bash /etc/nixos/specs/002-kde-plasma-performance/scripts/verify-optimizations.sh

# Check compositor backend
kreadconfig5 --file kwinrc --group Compositing --key Backend

# Monitor compositor CPU
htop -p $(pgrep kwin_x11)
```

### Benchmarking

See `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/` for baseline and optimized metrics.
```
**Validation**: Documentation updated
**Dependencies**: T043

### T045 - Create Final Performance Report
**File**: `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/final-report.md`
**Description**: Consolidate all benchmark results into final report
- Compare baseline (T004) with optimized metrics
- Calculate improvement percentages for:
  - Compositor CPU usage
  - RAM usage
  - Window operation responsiveness
  - Cursor smoothness
  - Screen update performance
- Document whether success criteria met (SC-001 through SC-010)
- Create graphs/charts if helpful
- Provide executive summary
**Validation**: Report shows 2-3x responsiveness improvement, all success criteria met
**Dependencies**: T020, T022, T026, T032, T037, T041
**Validates**: All Success Criteria (SC-001 through SC-010)

**Checkpoint**: ✅ Feature Complete - All user stories implemented, documented, and validated

---

## Task Summary

### Total Tasks: 45

**By Phase**:
- Phase 1 (Setup): 3 tasks
- Phase 2 (Foundational): 3 tasks
- Phase 3 (US1 - P1): 5 tasks
- Phase 4 (US2 - P1): 9 tasks
- Phase 5 (US3 - P2): 2 tasks
- Phase 6 (US4 - P2): 4 tasks
- Phase 7 (US5 - P3): 6 tasks
- Phase 8 (US6 - P3): 5 tasks
- Phase 9 (US7 - P4): 5 tasks
- Phase 10 (Polish): 3 tasks

**By User Story**:
- US1 (Responsive Window Operations): 5 tasks
- US2 (Low CPU Compositor Usage): 9 tasks
- US3 (Smooth Cursor Movement): 2 tasks
- US4 (Fast Screen Updates): 4 tasks
- US5 (Minimal Resource Overhead): 6 tasks
- US6 (Optimized RustDesk Configuration): 5 tasks
- US7 (Declarative Configuration): 5 tasks
- Setup/Polish: 9 tasks

**Parallelization Opportunities**:
- Phase 1: T001, T002, T003 (all parallel)
- Phase 4: T013-T018 (6 parallel effect disabling tasks)
- Total parallel tasks: 9

---

## Dependency Graph

```
Setup Phase (T001-T003)
    ↓
Foundational Phase (T004-T006)
    ↓
┌─────────────────────────────────────────┐
│ User Story 1 (T007-T011) [P1]           │ Compositor optimization
└─────────────────┬───────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│ User Story 2 (T012-T020) [P1]           │ Effects disabling
└─────┬───────────────────────────┬───────┘
      ↓                           ↓
┌─────────────────┐   ┌─────────────────────────┐
│ US3 (T021-T022) │   │ US4 (T023-T026) [P2]    │
│ [P2] Cursor     │   │ Screen updates          │
└─────────────────┘   └─────────────────────────┘
      ↓                           ↓
      └───────────┬───────────────┘
                  ↓
┌─────────────────────────────────────────┐
│ User Story 5 (T027-T032) [P3]           │ Services optimization
└─────────────────┬───────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│ User Story 6 (T033-T037) [P3]           │ RustDesk testing
└─────────────────┬───────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│ User Story 7 (T038-T042) [P4]           │ Declarative config
└─────────────────┬───────────────────────┘
                  ↓
Polish Phase (T043-T045)
```

**Critical Path**: T001 → T004 → T006 → T007 → T008 → T009 → T012 → T019 → T027 → T030 → T038 → T043 → T045

**Independent Paths**:
- US3 and US4 can proceed in parallel after US1+US2 complete
- US6 (RustDesk testing) is largely independent and can start after US1-US4 complete

---

## Implementation Strategy

### MVP (Minimum Viable Product) - User Story 1 Only

**Scope**: T001-T011 (Setup + Foundational + US1)
**Timeline**: 2 days
**Deliverable**: Responsive window operations with XRender backend
**Value**: Immediate improvement in desktop usability (most critical pain point)

### Incremental Delivery

1. **Week 1, Day 1-2**: MVP (US1 - Responsive Windows)
2. **Week 1, Day 3**: US2 (Low CPU Usage) - Compounds US1 benefits
3. **Week 1, Day 4**: US3 + US4 (Cursor + Screen Updates) - Parallel implementation
4. **Week 1, Day 5**: US5 (Service Optimization) - RAM savings
5. **Week 1, Day 6**: US6 (RustDesk) - Codec testing and documentation
6. **Week 1, Day 7**: US7 + Polish - Declarative config validation, final report

### Testing Strategy

**Per-Story Testing**: Each user story has Independent Test Criteria defined in the spec. Complete story testing before moving to next story.

**No TDD**: Tests are validation-focused (performance measurements, subjective testing), not automated unit tests. Each task includes validation criteria.

**Regression Testing**: After each story, re-run previous story tests to ensure no regressions.

---

## Constitution Compliance Checklist

✅ **I. Modular Composition**: Separate modules for compositor (kde-plasma-vm.nix), services (kde-optimization.nix)
✅ **II. Hetzner as Reference**: Base Hetzner config unchanged, VM optimizations separate
✅ **III. Test-Before-Apply**: All tasks require `nixos-rebuild dry-build` before switch
✅ **IV. Override Priority Discipline**: Using `lib.mkDefault` in base, `lib.mkForce` for VM overrides
✅ **V. Platform Flexibility**: Conditional VM optimizations via module options
✅ **VI. Declarative Configuration**: All settings in Nix modules, zero imperative scripts
✅ **VII. Documentation as Code**: Comprehensive benchmarking docs, configuration audit

---

## Success Metrics

### Expected Outcomes (from spec.md success criteria)

| Metric | Baseline | Target | Measured In |
|--------|----------|--------|-------------|
| Window drag latency | ~200-500ms | < 100ms | T010 |
| Compositor CPU (idle) | 15-20% | < 5% | T020 |
| Compositor CPU (active) | 40-60% | < 20% | T020 |
| Compositor CPU (average) | ~30% | < 10% | T020 |
| RAM usage | Baseline | -1 to -2GB | T032 |
| Background CPU | 10-15% | < 5% | T032 |
| RustDesk bandwidth | Uncapped | < 30 Mbps | T037 |
| Screen FPS | Variable | 25-30 FPS | T026 |
| Cursor smoothness | Poor (subjective) | Smooth (8+/10) | T022 |
| Overall responsiveness | 1x (baseline) | 2-3x improvement | T045 |

---

## File Locations Reference

### NixOS Modules (Implementation)
- `/etc/nixos/modules/desktop/kde-plasma-vm.nix` - VM compositor optimizations (T006-T021)
- `/etc/nixos/modules/services/kde-optimization.nix` - Service management (T027-T030)
- `/etc/nixos/home-modules/desktop/plasma-config.nix` - Home-manager Plasma config (T008-T019)
- `/etc/nixos/configurations/vm-hetzner.nix` - Target configuration (T030)

### Documentation
- `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/baseline.md` - Baseline metrics (T004)
- `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us1-window-operations.md` - US1 testing (T010-T011)
- `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us2-cpu-usage.md` - US2 testing (T020)
- `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us3-cursor.md` - US3 testing (T022)
- `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us4-screen-updates.md` - US4 testing (T023-T026)
- `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us5-services.md` - US5 testing (T031-T032)
- `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us6-rustdesk.md` - US6 testing (T033-T036)
- `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/us7-reproducibility.md` - US7 testing (T040-T042)
- `/etc/nixos/specs/002-kde-plasma-performance/benchmarks/final-report.md` - Consolidated results (T045)
- `/etc/nixos/specs/002-kde-plasma-performance/docs/rustdesk-configuration.md` - RustDesk guide (T037)
- `/etc/nixos/specs/002-kde-plasma-performance/docs/configuration-audit.md` - Declarative audit (T038)

### Scripts
- `/etc/nixos/specs/002-kde-plasma-performance/scripts/verify-optimizations.sh` - Verification (T003, T043)
- `/etc/nixos/specs/002-kde-plasma-performance/scripts/test-dry-build.sh` - Dry-build test (T039)

### Contracts (Reference)
- `/etc/nixos/specs/002-kde-plasma-performance/contracts/compositor-config.nix` - Compositor options
- `/etc/nixos/specs/002-kde-plasma-performance/contracts/effects-config.nix` - Effects options
- `/etc/nixos/specs/002-kde-plasma-performance/contracts/service-config.nix` - Service options
- `/etc/nixos/specs/002-kde-plasma-performance/contracts/kubevirt-vm-spec.yaml` - VM spec reference

---

**Tasks Status**: ✅ Ready for Implementation
**Next Step**: Begin Phase 1 (Setup) with tasks T001-T003
**Estimated Completion**: 7 days for full feature, 2 days for MVP

**Generated**: 2025-10-14
**Version**: 1.0
