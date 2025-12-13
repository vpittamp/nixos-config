# Tasks: Enable Advanced Hardware Features

**Input**: Design documents from `/specs/115-enable-advanced-hardware-features/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: Hardware testing requires manual verification; dry-build covers configuration validation. No automated tests generated.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

NixOS configuration files:
- `configurations/` - Target system configurations
- `hardware/` - Hardware-specific modules
- `modules/` - Reusable NixOS modules
- `home-modules/` - Home-manager user modules

---

## Phase 1: Setup (Build Verification)

**Purpose**: Verify existing configurations build successfully before modifications

- [x] T001 Run dry-build for ThinkPad configuration: `sudo nixos-rebuild dry-build --flake .#thinkpad`
- [x] T002 [P] Run dry-build for Ryzen configuration: `sudo nixos-rebuild dry-build --flake .#ryzen`
- [x] T003 [P] Run dry-build for Hetzner configuration to ensure no regression: `sudo nixos-rebuild dry-build --flake .#hetzner-sway`

**Checkpoint**: All three configurations build successfully before any modifications

---

## Phase 2: Foundational (Environment Variables & Packages)

**Purpose**: Add environment variables and base packages needed by multiple user stories

**⚠️ CRITICAL**: These changes enable hardware acceleration across multiple features

- [x] T004 Add LIBVA_DRIVER_NAME="iHD" to environment.sessionVariables in configurations/thinkpad.nix
- [x] T005 [P] Verify LIBVA_DRIVER_NAME="nvidia" exists in environment.sessionVariables in configurations/ryzen.nix
- [x] T006 [P] Add wf-recorder, grim, slurp to environment.systemPackages in configurations/thinkpad.nix
- [x] T007 [P] Add wf-recorder, grim, slurp to environment.systemPackages in configurations/ryzen.nix
- [x] T008 Verify intel-gpu-tools (intel_gpu_top) is in environment.systemPackages in configurations/thinkpad.nix
- [x] T009 [P] Verify nvtopPackages.nvidia (nvtop) is in environment.systemPackages in configurations/ryzen.nix
- [x] T010 Run dry-build for both targets to verify foundational changes: `sudo nixos-rebuild dry-build --flake .#thinkpad && sudo nixos-rebuild dry-build --flake .#ryzen`

**Checkpoint**: Foundation ready - hardware-specific user story implementation can begin

---

## Phase 3: User Story 1 - Hardware-Accelerated Video Playback (Priority: P1) 🎯 MVP

**Goal**: Enable GPU hardware video decoding in Firefox on both ThinkPad (VA-API/Intel) and Ryzen (NVDEC/NVIDIA)

**Independent Test**: Play YouTube 4K video, verify GPU decoder active via `intel_gpu_top` or `nvtop`, CPU usage <20%

### Implementation for User Story 1

- [x] T011 [US1] Verify intel-media-driver is in hardware.graphics.extraPackages in hardware/thinkpad.nix
- [x] T012 [P] [US1] Verify vpl-gpu-rt (Intel VPL/QuickSync) is in hardware.graphics.extraPackages in hardware/thinkpad.nix
- [x] T013 [P] [US1] Verify libva-utils package is in environment.systemPackages in configurations/thinkpad.nix
- [x] T014 [P] [US1] Verify libva-utils package is in environment.systemPackages in configurations/ryzen.nix
- [x] T015 [US1] Add Firefox hardware video decoding settings to home-modules/tools/firefox.nix: media.ffmpeg.vaapi.enabled=true, media.hardware-video-decoding.force-enabled=true, gfx.webrender.all=true
- [x] T016 [US1] Run dry-build for ThinkPad: `sudo nixos-rebuild dry-build --flake .#thinkpad`
- [x] T017 [US1] Run dry-build for Ryzen: `sudo nixos-rebuild dry-build --flake .#ryzen`

**Checkpoint**: User Story 1 configuration complete - ready for hardware verification after apply

---

## Phase 4: User Story 2 - Webcam Video Conferencing (Priority: P1)

**Goal**: Enable V4L2 webcam access for video conferencing in Firefox and Electron apps

**Independent Test**: Run `v4l2-ctl --list-devices`, verify webcam appears; test in browser at meet.google.com

### Implementation for User Story 2

- [x] T018 [US2] Verify v4l-utils is in environment.systemPackages in configurations/thinkpad.nix
- [x] T019 [P] [US2] Verify cameractrls is in environment.systemPackages in configurations/thinkpad.nix
- [x] T020 [P] [US2] Add v4l-utils to environment.systemPackages in configurations/ryzen.nix (for USB webcams)
- [x] T021 [US2] Verify user vpittamp is in "video" group in configurations/thinkpad.nix
- [x] T022 [P] [US2] Verify user vpittamp is in "video" group in configurations/ryzen.nix
- [x] T023 [US2] Run dry-build for both targets: `sudo nixos-rebuild dry-build --flake .#thinkpad && sudo nixos-rebuild dry-build --flake .#ryzen`

**Checkpoint**: User Story 2 configuration complete - ready for hardware verification

---

## Phase 5: User Story 3 - Bluetooth High-Quality Audio Codecs (Priority: P2)

**Goal**: Enable LDAC, aptX HD, aptX, AAC codecs for Bluetooth audio on ThinkPad

**Independent Test**: Pair Bluetooth headphones, check `pactl list sinks | grep codec`, verify LDAC/aptX active

### Implementation for User Story 3

- [x] T024 [US3] Verify WirePlumber bluez5.codecs configuration in services.pipewire.wireplumber.extraConfig in configurations/thinkpad.nix includes ["sbc", "sbc_xq", "aac", "ldac", "aptx", "aptx_hd"]
- [x] T025 [US3] Verify bluez5.enable-sbc-xq=true in WirePlumber config in configurations/thinkpad.nix
- [x] T026 [P] [US3] Verify bluez5.enable-msbc=true for telephony in WirePlumber config in configurations/thinkpad.nix
- [x] T027 [P] [US3] Verify bluez5.enable-hw-volume=true in WirePlumber config in configurations/thinkpad.nix
- [x] T028 [US3] Verify hardware.bluetooth.settings.General.Experimental=true in configurations/thinkpad.nix
- [x] T029 [US3] Run dry-build for ThinkPad: `sudo nixos-rebuild dry-build --flake .#thinkpad`

**Checkpoint**: User Story 3 configuration complete - ready for Bluetooth hardware verification

---

## Phase 6: User Story 4 - GPU-Accelerated Screen Recording (Priority: P2)

**Goal**: Enable hardware-encoded screen recording via wf-recorder with VAAPI/NVENC

**Independent Test**: Run `wf-recorder -c h264_vaapi -f test.mp4` (Intel) or `wf-recorder -c h264_nvenc -f test.mp4` (NVIDIA), verify CPU <30%

### Implementation for User Story 4

- [x] T030 [US4] Verify wf-recorder is in environment.systemPackages (added in T006/T007)
- [x] T031 [P] [US4] Verify grim (screenshot tool) is in environment.systemPackages
- [x] T032 [P] [US4] Verify slurp (region selection) is in environment.systemPackages
- [x] T033 [US4] Verify VA-API environment is configured (LIBVA_DRIVER_NAME set in foundational phase)
- [x] T034 [US4] Run dry-build for both targets: `sudo nixos-rebuild dry-build --flake .#thinkpad && sudo nixos-rebuild dry-build --flake .#ryzen`

**Checkpoint**: User Story 4 configuration complete - ready for screen recording verification

---

## Phase 7: User Story 5 - NVIDIA GPU Computing (Priority: P2)

**Goal**: Enable CUDA toolkit and OpenCL for GPU compute workloads on Ryzen desktop

**Independent Test**: Run `nvcc --version` for CUDA compiler, `clinfo` for OpenCL platforms

### Implementation for User Story 5

- [x] T035 [US5] Add cudaPackages.cuda_nvcc to environment.systemPackages in configurations/ryzen.nix
- [x] T036 [P] [US5] Add clinfo to environment.systemPackages in configurations/ryzen.nix
- [x] T037 [P] [US5] Verify vulkan-tools is in environment.systemPackages in configurations/ryzen.nix
- [x] T038 [US5] Run dry-build for Ryzen: `sudo nixos-rebuild dry-build --flake .#ryzen`

**Checkpoint**: User Story 5 configuration complete - ready for CUDA/OpenCL verification

---

## Phase 8: User Story 6 - Smooth GTK/Sway Compositor Performance (Priority: P3)

**Goal**: Ensure Sway uses GPU-accelerated rendering (DRM/KMS) instead of software pixman

**Independent Test**: Run `glxinfo | grep renderer`, verify shows GPU name not llvmpipe

### Implementation for User Story 6

- [x] T039 [US6] Verify services.xserver.videoDrivers = ["modesetting"] in configurations/thinkpad.nix
- [x] T040 [P] [US6] Verify services.xserver.videoDrivers = ["nvidia"] in configurations/ryzen.nix
- [x] T041 [P] [US6] Verify GBM_BACKEND="nvidia-drm" in environment.sessionVariables in configurations/ryzen.nix
- [x] T042 [P] [US6] Verify WLR_NO_HARDWARE_CURSORS="1" in environment.sessionVariables in configurations/ryzen.nix
- [x] T043 [US6] Verify hardware.nvidia.modesetting.enable=true in configurations/ryzen.nix
- [x] T044 [US6] Run dry-build for both targets: `sudo nixos-rebuild dry-build --flake .#thinkpad && sudo nixos-rebuild dry-build --flake .#ryzen`

**Checkpoint**: User Story 6 configuration complete - ready for compositor performance verification

---

## Phase 9: User Story 7 - Thunderbolt/USB4 Dock Support (Priority: P3)

**Goal**: Enable Bolt daemon for Thunderbolt device authorization on ThinkPad

**Independent Test**: Connect Thunderbolt dock, run `boltctl list`, verify device appears

### Implementation for User Story 7

- [x] T045 [US7] Add services.hardware.bolt.enable = true to configurations/thinkpad.nix
- [x] T046 [US7] Verify "thunderbolt" is in boot.initrd.availableKernelModules in hardware/thinkpad.nix
- [x] T047 [US7] Run dry-build for ThinkPad: `sudo nixos-rebuild dry-build --flake .#thinkpad`

**Checkpoint**: User Story 7 configuration complete - ready for Thunderbolt dock verification

---

## Phase 10: User Story 8 - Low-Latency Audio (Priority: P3)

**Goal**: Configure PipeWire with 256 quantum for <15ms audio latency

**Independent Test**: Run `pw-top`, verify quantum ~256 and rate 48000

### Implementation for User Story 8

- [x] T048 [US8] Verify services.pipewire.extraConfig.pipewire."92-low-latency" is configured in configurations/thinkpad.nix with quantum=256, rate=48000
- [x] T049 [P] [US8] Verify services.pipewire.extraConfig.pipewire."92-low-latency" is configured in configurations/ryzen.nix with quantum=256, rate=48000
- [x] T050 [US8] Verify security.rtkit.enable=true in configurations/thinkpad.nix
- [x] T051 [P] [US8] Verify security.rtkit.enable=true in configurations/ryzen.nix
- [x] T052 [US8] Verify services.pipewire.jack.enable=true for JACK bridge compatibility in configurations/thinkpad.nix
- [x] T053 [P] [US8] Verify services.pipewire.jack.enable=true in configurations/ryzen.nix
- [x] T054 [US8] Run dry-build for both targets: `sudo nixos-rebuild dry-build --flake .#thinkpad && sudo nixos-rebuild dry-build --flake .#ryzen`

**Checkpoint**: User Story 8 configuration complete - ready for audio latency verification

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, final verification, and apply changes

- [x] T055 [P] Update CLAUDE.md with hardware verification commands from quickstart.md
- [x] T056 [P] Add hardware feature section to CLAUDE.md documenting new capabilities
- [x] T057 Run final dry-build for all three targets to ensure no regressions: `sudo nixos-rebuild dry-build --flake .#thinkpad && sudo nixos-rebuild dry-build --flake .#ryzen && sudo nixos-rebuild dry-build --flake .#hetzner-sway`
- [ ] T058 Apply configuration to current system: `sudo nixos-rebuild switch --flake .#<current-target>`
- [ ] T059 Run quickstart.md verification procedures for applied target
- [x] T060 Update spec.md status from Draft to Complete

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - verification only
- **Foundational (Phase 2)**: Depends on Setup - adds shared env vars and packages
- **User Stories (Phase 3-10)**: All depend on Foundational completion
  - US1 (P1) and US2 (P1) can proceed in parallel - both P1 priority
  - US3-US8 (P2-P3) can proceed in parallel after US1/US2 if desired
- **Polish (Phase 11)**: Depends on all user stories being verified via dry-build

### User Story Dependencies

| Story | Priority | Depends On | Can Parallel With |
|-------|----------|------------|-------------------|
| US1 - Video Playback | P1 | Foundational | US2 |
| US2 - Webcam | P1 | Foundational | US1 |
| US3 - Bluetooth | P2 | Foundational | US4, US5 |
| US4 - Screen Recording | P2 | Foundational | US3, US5 |
| US5 - CUDA/OpenCL | P2 | Foundational | US3, US4 |
| US6 - Compositor | P3 | Foundational | US7, US8 |
| US7 - Thunderbolt | P3 | Foundational | US6, US8 |
| US8 - Low-Latency Audio | P3 | Foundational | US6, US7 |

### Parallel Opportunities

- All [P] marked tasks within a phase can run in parallel
- US1 and US2 (both P1) can be done in parallel
- US3, US4, US5 (all P2) can be done in parallel
- US6, US7, US8 (all P3) can be done in parallel
- Many tasks are verification tasks (checking existing config) which can parallelize heavily

---

## Parallel Example: User Story 1 (Video Playback)

```bash
# Parallel verification tasks:
Task: "Verify intel-media-driver is in hardware.graphics.extraPackages in hardware/thinkpad.nix"
Task: "Verify vpl-gpu-rt is in hardware.graphics.extraPackages in hardware/thinkpad.nix"
Task: "Verify libva-utils package is in configurations/thinkpad.nix"
Task: "Verify libva-utils package is in configurations/ryzen.nix"

# Then sequential (depends on above):
Task: "Add Firefox hardware video decoding settings to home-modules/tools/firefox.nix"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup (verify builds)
2. Complete Phase 2: Foundational (env vars + base packages)
3. Complete Phase 3: User Story 1 (Video Playback)
4. Complete Phase 4: User Story 2 (Webcam)
5. **STOP and VALIDATE**: Apply config, test video playback and webcam
6. Deploy if ready - MVP delivers the two P1 features

### Incremental Delivery

1. Setup + Foundational → Base ready
2. Add US1 + US2 (P1) → Test → Apply (MVP!)
3. Add US3 + US4 + US5 (P2) → Test → Apply
4. Add US6 + US7 + US8 (P3) → Test → Apply
5. Polish → Documentation complete

### Single Developer Strategy

Execute phases sequentially in priority order:
1. Setup → Foundational → US1 → US2 → Apply → Test
2. US3 → US4 → US5 → Apply → Test
3. US6 → US7 → US8 → Apply → Test
4. Polish → Done

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Most tasks are verification (existing config) or addition (new options)
- dry-build validates configuration syntax; hardware testing requires applied config
- Hetzner configuration should NOT be modified - verify no regression only
- Many settings already exist - tasks focus on verification and gap-filling
- Apply changes only after dry-build succeeds for target
