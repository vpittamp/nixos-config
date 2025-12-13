# Feature Specification: Enable Advanced Hardware Features

**Feature Branch**: `115-enable-advanced-hardware-features`
**Created**: 2025-12-13
**Status**: Complete
**Input**: User description: "Given our new devices (ThinkPad with Intel Core Ultra 7 155U and AMD Ryzen 7600X3D with NVIDIA RTX 5070), enhance configurations to incorporate advanced hardware functionality that was previously limited on Hetzner VM and M1. Focus on: webcam, GPU acceleration for Firefox/PWAs, Sway compositor features, Bluetooth, audio/video playback, GTK-CSS rendering, and NixOS hardware repository capabilities."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hardware-Accelerated Video Playback in Firefox (Priority: P1)

When watching videos in Firefox or Firefox PWAs on bare metal devices, the user should experience smooth, power-efficient playback using GPU hardware decoding instead of CPU-intensive software rendering.

**Why this priority**: Video consumption is a primary use case for web browsing. Hardware acceleration reduces CPU load by 80-90%, extends battery life on ThinkPad, and provides smooth 4K/HDR playback. This was impossible on Hetzner (pixman renderer).

**Independent Test**: Open YouTube, play a 4K video, verify GPU utilization via `intel_gpu_top` (ThinkPad) or `nvtop` (Ryzen) shows decoder activity, while CPU usage remains low (<20%).

**Acceptance Scenarios**:

1. **Given** Firefox is launched on ThinkPad, **When** user plays a YouTube video, **Then** VA-API hardware decoding is used (verifiable via `about:support` showing "Hardware Video Decoding" enabled)
2. **Given** Firefox is launched on Ryzen desktop, **When** user plays a YouTube video, **Then** NVIDIA NVDEC hardware decoding is active (verifiable via `nvidia-smi dmon` showing decoder utilization)
3. **Given** a Firefox PWA (e.g., YouTube PWA) is launched, **When** user plays video content, **Then** the same hardware decoding path is used as native Firefox

---

### User Story 2 - Webcam Video Conferencing Support (Priority: P1)

The user should be able to use the built-in webcam (ThinkPad) or USB webcam (Ryzen desktop) for video conferencing applications in Firefox and Electron apps.

**Why this priority**: Video conferencing is essential for remote work. The Hetzner VM has no webcam hardware. Both new devices support real V4L2 camera access.

**Independent Test**: Open Firefox, navigate to a video conferencing site (meet.google.com), verify camera preview shows live video feed and can be selected in browser settings.

**Acceptance Scenarios**:

1. **Given** a webcam is connected/built-in, **When** user opens browser camera settings, **Then** the webcam appears as a selectable device
2. **Given** a video conference is started, **When** user enables camera, **Then** video stream transmits without errors and at native resolution
3. **Given** multiple camera applications request access, **When** user switches between apps, **Then** camera is released properly and available to the next app

---

### User Story 3 - Bluetooth Audio with High-Quality Codecs (Priority: P2)

On ThinkPad, the user should be able to pair Bluetooth headphones/speakers and use high-quality audio codecs (AAC, LDAC, aptX) for superior wireless audio quality.

**Why this priority**: Bluetooth audio is a common use case for laptops. The current configuration enables Bluetooth but codec selection may not use the highest quality available. LDAC provides 990kbps vs SBC's 328kbps.

**Independent Test**: Pair Sony WH-1000XM series headphones, verify via `pactl list sinks` that LDAC codec is active, play audio and confirm high-quality output.

**Acceptance Scenarios**:

1. **Given** Bluetooth headphones are paired, **When** audio plays, **Then** the highest quality available codec is automatically selected (LDAC > aptX HD > aptX > AAC > SBC)
2. **Given** Bluetooth headphones support microphone, **When** user switches to headset profile, **Then** mSBC codec is used for telephony with clear voice quality
3. **Given** audio is playing via Bluetooth, **When** user adjusts volume, **Then** hardware volume control is used (not software scaling)

---

### User Story 4 - GPU-Accelerated Screen Recording (Priority: P2)

The user should be able to record screen content (for demos, tutorials, etc.) using hardware video encoding for efficient, high-quality capture without significant CPU load.

**Why this priority**: Screen recording is useful for documentation, bug reports, and content creation. Hardware encoding (Intel QuickSync or NVIDIA NVENC) provides real-time encoding at minimal CPU cost - not possible on Hetzner.

**Independent Test**: Start screen recording with `wf-recorder` using hardware encoder, verify via system monitor that CPU usage stays under 30% during 1080p60 capture.

**Acceptance Scenarios**:

1. **Given** ThinkPad with Intel Arc GPU, **When** user records screen with `wf-recorder`, **Then** VAAPI hardware encoder is used (QuickSync)
2. **Given** Ryzen desktop with RTX 5070, **When** user records screen, **Then** NVENC hardware encoder is available
3. **Given** a recording is in progress, **When** user performs normal desktop tasks, **Then** system remains responsive (no frame drops or lag)

---

### User Story 5 - NVIDIA GPU Computing for Development (Priority: P2)

On the Ryzen desktop, the user should be able to utilize the RTX 5070 GPU for CUDA/OpenCL compute tasks (AI/ML development, video transcoding, etc.).

**Why this priority**: The RTX 5070 is a significant compute resource. Enabling CUDA development unlocks AI/ML workflows, video processing acceleration, and GPU compute capabilities not available on other systems.

**Independent Test**: Run `clinfo` and verify NVIDIA OpenCL platform is available; compile and run a simple CUDA program.

**Acceptance Scenarios**:

1. **Given** CUDA toolkit is installed, **When** user runs `nvcc --version`, **Then** CUDA compiler is available
2. **Given** user runs `clinfo`, **When** output is displayed, **Then** NVIDIA GPU appears as an OpenCL compute device
3. **Given** user runs Vulkan compute shader, **When** executed, **Then** RTX 5070 ray tracing cores are utilized

---

### User Story 6 - Smooth GTK/Sway Compositor Performance (Priority: P3)

Desktop animations, window transitions, and GTK application rendering should be smooth and GPU-accelerated on both devices.

**Why this priority**: Smooth UI contributes to a polished user experience. The Hetzner VM uses software rendering (pixman/cairo) which can be sluggish for animations. Bare metal GPUs enable hardware-accelerated compositing.

**Independent Test**: Enable window animations in Sway, resize windows rapidly, verify smooth 60fps rendering without tearing.

**Acceptance Scenarios**:

1. **Given** Sway compositor is running on ThinkPad, **When** user switches workspaces, **Then** transition completes smoothly without visible stutter
2. **Given** GTK4 application is launched, **When** user interacts with UI, **Then** animations render via GPU (not cairo software fallback)
3. **Given** Eww widgets are updating, **When** monitoring panel refreshes, **Then** updates complete without visible lag

---

### User Story 7 - Thunderbolt/USB4 Dock Support (Priority: P3)

On ThinkPad, the user should be able to connect Thunderbolt/USB4 docks for external displays, USB peripherals, and charging via a single cable.

**Why this priority**: Thunderbolt docks enable a "dock and work" workflow with external monitors, keyboard, mouse, and power via one connection. This requires hardware support not available on VMs.

**Independent Test**: Connect Thunderbolt dock, verify external display appears in `swaymsg -t get_outputs`, USB devices enumerate, and laptop charges.

**Acceptance Scenarios**:

1. **Given** Thunderbolt dock is connected, **When** external monitor is attached to dock, **Then** display is detected and usable in Sway
2. **Given** USB devices are connected through dock, **When** user lists devices, **Then** all devices appear in `lsusb` output
3. **Given** dock provides power delivery, **When** connected, **Then** laptop battery shows "Charging" status

---

### User Story 8 - Low-Latency Audio for Real-Time Applications (Priority: P3)

The user should have access to low-latency audio for real-time audio applications (speech-to-text, audio editing, music production).

**Why this priority**: Low-latency audio is important for real-time voice applications and professional audio work. PipeWire can achieve <10ms latency with proper configuration on real hardware.

**Independent Test**: Run `pw-top`, verify audio quantum is 256 samples (~5ms at 48kHz), test speech-to-text recognition for responsive transcription.

**Acceptance Scenarios**:

1. **Given** PipeWire is running, **When** user checks `pw-top`, **Then** audio latency is under 10ms
2. **Given** speech-to-text is active, **When** user speaks, **Then** transcription appears within 500ms of speech completion
3. **Given** JACK-compatible app is launched, **When** audio is routed, **Then** PipeWire JACK bridge provides seamless integration

---

### Edge Cases

- What happens when GPU driver crashes during hardware decoding? System should fall back to software decoding without crashing the browser.
- How does system handle Bluetooth audio codec negotiation failure? Should fall back to mandatory SBC codec.
- What happens when Thunderbolt device authorization fails? User should see clear error via bolt daemon notification.
- How does system handle webcam being in use by another application? Browser should show "camera in use" error, not crash.
- What happens when NVIDIA driver version mismatch occurs? System should fail with clear error message during boot/login.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST enable VA-API hardware video decoding on Intel Arc GPU (ThinkPad) with `intel-media-driver` and appropriate environment variables
- **FR-002**: System MUST enable NVIDIA NVDEC/NVENC on RTX 5070 (Ryzen) with NVIDIA proprietary drivers and VA-API/NVDEC bridges
- **FR-003**: Firefox MUST be configured to use hardware video decoding on both platforms via `media.ffmpeg.vaapi.enabled` and related settings
- **FR-004**: System MUST load Video4Linux (V4L2) modules and include `v4l-utils` for webcam support
- **FR-005**: System MUST configure PipeWire with WirePlumber to enable high-quality Bluetooth audio codecs (SBC-XQ, AAC, LDAC, aptX, aptX HD) on ThinkPad
- **FR-006**: System MUST include hardware-accelerated screen recording tools (`wf-recorder`, `grim`, `slurp`) configured to use available GPU encoders
- **FR-007**: System MUST enable Thunderbolt/USB4 support via `bolt` daemon and appropriate kernel modules on ThinkPad
- **FR-008**: System MUST configure PipeWire with low-latency settings (256 quantum, 48kHz sample rate) on both platforms
- **FR-009**: Sway compositor MUST use hardware-accelerated rendering (DRM/KMS modesetting) instead of software renderer
- **FR-010**: System MUST enable CUDA toolkit and OpenCL support on Ryzen desktop for GPU compute workloads
- **FR-011**: GTK applications MUST use hardware-accelerated rendering where available (not forced to cairo software fallback)
- **FR-012**: System MUST include GPU monitoring tools appropriate to each platform (`intel_gpu_top` for Intel, `nvtop` for NVIDIA)

### Key Entities

- **Hardware Profile**: Platform-specific configuration (ThinkPad Intel, Ryzen NVIDIA) with GPU drivers, kernel modules, and environment variables
- **Video Acceleration Stack**: VA-API/VDPAU backends, browser configurations, and verification tools for hardware video decoding
- **Audio Pipeline**: PipeWire configuration with codec support, latency settings, and device routing
- **Peripheral Support**: Webcam (V4L2), Bluetooth (BlueZ), Thunderbolt (bolt), USB subsystems

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Video playback in Firefox uses less than 20% CPU for 1080p60 content (vs 60%+ with software decoding)
- **SC-002**: Webcam video stream achieves native sensor resolution with less than 100ms capture-to-display latency
- **SC-003**: Bluetooth audio connects within 5 seconds and uses high-quality codec (LDAC/aptX when supported by device)
- **SC-004**: Screen recording at 1080p60 uses less than 30% CPU via hardware encoder
- **SC-005**: Audio round-trip latency is under 15ms as measured by PipeWire diagnostics
- **SC-006**: Sway workspace switching completes within 50ms (smooth 60fps animation)
- **SC-007**: Thunderbolt dock connection establishes within 10 seconds of physical connection
- **SC-008**: GPU compute workloads (CUDA/OpenCL) execute on dedicated GPU hardware, not CPU fallback
- **SC-009**: Configuration builds successfully on both ThinkPad and Ryzen targets without hardware-specific errors on opposite platform

## Assumptions

The following reasonable defaults and assumptions are made:

1. **Firefox as primary browser**: The specification focuses on Firefox hardware acceleration. Chromium/Electron apps will inherit system-wide VA-API settings via `NIXOS_OZONE_WL=1`.

2. **No HDR requirement**: HDR/color management is deferred as Sway support is immature. Standard dynamic range is assumed sufficient.

3. **Intel NPU not enabled**: Intel NPU driver is not packaged in NixOS yet (issue #348739). This is excluded from current scope.

4. **NVIDIA open-source kernel modules**: RTX 5070 (Blackwell) is new enough to use NVIDIA's open-source kernel modules (`hardware.nvidia.open = true`).

5. **Single GPU per system**: No multi-GPU or GPU passthrough configuration is in scope. Ryzen uses only the RTX 5070, not any integrated graphics.

6. **Hetzner VM unchanged**: The Hetzner configuration will remain with software rendering (pixman). No attempt to enable hardware features on VM.

7. **Bluetooth on ThinkPad only**: Ryzen desktop is assumed to not have Bluetooth hardware. If present, configuration is already in place via `hardware.bluetooth`.

8. **Standard Bluetooth codecs**: No need to configure exotic codecs (LC3, LE Audio). Focus on widely-supported AAC/LDAC/aptX.

9. **webcam resolution**: Webcam is assumed to be 1080p or lower. No specific 4K webcam support required.

10. **Gaming disabled**: Neither system has gaming enabled (`services.bare-metal.enableGaming = false`). No Steam/Proton/GameMode optimization required.
