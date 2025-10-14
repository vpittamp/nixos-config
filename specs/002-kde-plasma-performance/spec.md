# Feature Specification: KDE Plasma Performance Optimization for KubeVirt VMs

**Feature Branch**: `002-kde-plasma-performance`
**Created**: 2025-10-14
**Status**: Draft
**Priority**: High
**Context**: KubeVirt VM accessed via RustDesk experiences poor graphical performance

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Responsive Window Operations (Priority: P1)

As a remote desktop user, I need window operations (moving, resizing, switching) to feel instant and responsive when accessing my KubeVirt VM via RustDesk, so that I can work efficiently without frustrating lag.

**Why this priority**: This is the foundation of desktop usability. Laggy window operations make every task feel slow and frustrating. This delivers immediate, noticeable value.

**Independent Test**: Open 5-10 windows, drag them around the screen, resize them, switch between them with Alt+Tab. Measure response time from input to visual update. Success means operations feel instantaneous (< 100ms perceived latency).

**Acceptance Scenarios**:

1. **Given** KDE Plasma compositor is optimized, **When** user drags a window across the screen, **Then** window follows cursor smoothly without lag or tearing
2. **Given** multiple windows are open, **When** user presses Alt+Tab, **Then** window switcher appears instantly (< 50ms) with smooth transitions
3. **Given** user resizes a window, **When** user drags window edge, **Then** window resizes in real-time without stuttering
4. **Given** RustDesk connection is active, **When** user clicks window to focus, **Then** window gains focus and responds to input immediately

---

### User Story 2 - Low CPU Compositor Usage (Priority: P1)

As a system administrator, I need the KDE compositor to use minimal CPU resources (< 20% during normal operations), so that VM resources are available for actual applications rather than being consumed by desktop effects.

**Why this priority**: High compositor CPU usage directly impacts application performance and VM scalability. Every CPU cycle wasted on visual effects is unavailable for productive work.

**Independent Test**: Monitor compositor CPU usage with `htop` while performing normal desktop operations (browsing, editing documents, switching windows). Success means kwin_x11 process stays below 20% CPU usage.

**Acceptance Scenarios**:

1. **Given** compositor is optimized, **When** system is idle, **Then** kwin_x11 process uses < 5% CPU
2. **Given** user is working normally, **When** opening/closing/switching windows, **Then** kwin_x11 CPU usage peaks at < 20%
3. **Given** expensive visual effects are disabled, **When** measuring CPU usage over 1 hour, **Then** average compositor CPU usage is < 10%
4. **Given** VM has 4-6 vCPUs allocated, **When** compositor is running, **Then** at least 3 vCPUs remain available for applications

---

### User Story 3 - Smooth Cursor Movement (Priority: P2)

As a remote desktop user, I need the mouse cursor to move smoothly without jumpiness or lag, so that precise clicking and dragging operations are possible.

**Why this priority**: Cursor lag makes the entire desktop feel unresponsive and makes precise operations (clicking small buttons, selecting text) frustrating. This is critical for user experience but depends on P1 optimizations.

**Independent Test**: Move cursor rapidly across screen, draw circles, click rapidly on various UI elements. Measure cursor lag between local movement and remote display. Success means cursor feels smooth and responsive.

**Acceptance Scenarios**:

1. **Given** optimized configuration, **When** user moves cursor rapidly, **Then** cursor tracks smoothly without jumping or stuttering
2. **Given** RustDesk connection, **When** user hovers over UI elements, **Then** hover effects appear immediately (< 100ms)
3. **Given** user performs drag-and-drop, **When** dragging item across screen, **Then** dragged item follows cursor without lag
4. **Given** cursor is moving, **When** system is under moderate load, **Then** cursor remains responsive and smooth

---

### User Story 4 - Fast Screen Updates (Priority: P2)

As a remote desktop user, I need screen content to update quickly when scrolling or changing views, so that reading documents and browsing web pages feels natural.

**Why this priority**: Slow screen updates make reading and navigation frustrating. This significantly impacts productivity for document-heavy workflows.

**Independent Test**: Scroll through long documents, browse web pages, watch video content. Measure frame rate and lag between action and screen update. Success means smooth 25-30 FPS with minimal tearing.

**Acceptance Scenarios**:

1. **Given** browser is open, **When** user scrolls web page, **Then** page scrolls smoothly at 25-30 FPS without tearing
2. **Given** document editor is open, **When** user types rapidly, **Then** text appears on screen immediately (< 50ms latency)
3. **Given** file manager displays many files, **When** user scrolls through list, **Then** scrolling is smooth without frame drops
4. **Given** RustDesk compression is enabled, **When** screen content changes, **Then** updates appear within 100ms

---

### User Story 5 - Minimal Resource Overhead (Priority: P3)

As a system administrator, I need unnecessary KDE services (Baloo indexing, Akonadi PIM) to be disabled in VM environment, so that RAM and CPU are available for productive work.

**Why this priority**: Many KDE services are unnecessary in a remote-only VM and consume resources. Disabling them frees up capacity but isn't critical for immediate usability.

**Independent Test**: Check running processes with `ps aux`, measure RAM usage before/after optimization. Success means 1-2GB RAM freed and several CPU-intensive background processes eliminated.

**Acceptance Scenarios**:

1. **Given** Baloo is disabled, **When** checking processes, **Then** baloo_file and baloo_file_extractor are not running
2. **Given** Akonadi is disabled, **When** checking processes, **Then** akonadi_control and related processes are not running
3. **Given** services are optimized, **When** measuring idle RAM usage, **Then** system uses 1-2GB less RAM than before
4. **Given** unnecessary services disabled, **When** monitoring CPU, **Then** background CPU usage is < 5%

---

### User Story 6 - Optimized RustDesk Configuration (Priority: P3)

As a remote desktop user, I need RustDesk configured with optimal codec and compression settings, so that video stream quality balances between visual fidelity and network bandwidth.

**Why this priority**: RustDesk has various codec options that can improve performance, but the defaults are reasonable. This is an incremental improvement rather than critical fix.

**Independent Test**: Test different codec settings (VP8, VP9, H.264) and compression levels. Measure perceived quality, latency, and bandwidth usage. Success means optimal balance for LAN/VPN scenarios.

**Acceptance Scenarios**:

1. **Given** RustDesk with optimized codec, **When** connecting over LAN, **Then** desktop appears sharp with minimal compression artifacts
2. **Given** RustDesk compression tuned, **When** monitoring network usage, **Then** bandwidth usage is 10-30 Mbps for 1080p desktop
3. **Given** codec is configured, **When** performing normal operations, **Then** no noticeable increase in latency vs current setup
4. **Given** direct IP access enabled, **When** connecting, **Then** connection establishes in < 3 seconds

---

### User Story 7 - Declarative Configuration (Priority: P4)

As a system administrator, I need all performance optimizations defined in NixOS configuration files, so that configuration is reproducible and version-controlled.

**Why this priority**: Aligns with constitution's "Declarative Configuration Over Imperative" principle, but actual performance impact is secondary to correctness of optimizations themselves.

**Independent Test**: Build fresh VM from NixOS configuration, verify all optimizations are applied automatically without manual steps. Success means zero manual configuration required post-deployment.

**Acceptance Scenarios**:

1. **Given** NixOS configuration with optimizations, **When** building fresh VM, **Then** all compositor settings are applied automatically
2. **Given** declarative service configuration, **When** VM boots, **Then** Baloo and Akonadi are disabled without manual intervention
3. **Given** KubeVirt VM spec, **When** VM is created, **Then** dedicated CPU placement and IOThreads are configured
4. **Given** configuration in Git, **When** comparing two builds, **Then** desktop performance is identical (reproducible)

---

### Edge Cases

- What happens when GPU passthrough is added later (configuration should adapt)?
- How does system behave when VM is resized (more/fewer vCPUs allocated)?
- What occurs when RustDesk connection is lost and reconnected?
- How are settings preserved when KDE Plasma is upgraded?
- What happens if user manually enables visual effects through GUI?
- How does system perform when multiple windows show video content?
- What occurs when network latency increases (LAN → WAN)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: KDE compositor MUST use XRender backend for CPU-based rendering in VM environment
- **FR-002**: System MUST disable expensive visual effects (blur, background contrast, wobbly windows, translucency)
- **FR-003**: Compositor MUST limit frame rate to 30 FPS for remote desktop optimization
- **FR-004**: System MUST disable vsync to reduce input latency
- **FR-005**: Animations MUST be set to instant (no animation delay)
- **FR-006**: Baloo file indexer MUST be disabled in VM environment
- **FR-007**: Akonadi PIM services MUST be disabled when not needed
- **FR-008**: KubeVirt VM MUST use dedicated CPU placement for predictable performance
- **FR-009**: KubeVirt VM MUST allocate 6-8 vCPUs with proper socket/core topology
- **FR-010**: KubeVirt VM MUST allocate 8-16GB RAM with guaranteed QoS
- **FR-011**: KubeVirt VM MUST enable IOThreads policy for disk performance
- **FR-012**: System MUST set Qt platform to XCB for X11 compatibility
- **FR-013**: System MUST disable Qt auto-scaling in VM environment
- **FR-014**: RustDesk MUST use direct IP access for lowest latency
- **FR-015**: RustDesk MUST configure optimal codec for LAN/VPN connections
- **FR-016**: All optimizations MUST be declared in NixOS configuration files
- **FR-017**: Configuration MUST be testable through nixos-rebuild dry-build
- **FR-018**: System MUST work on KubeVirt VMs (primary target)
- **FR-019**: Settings MUST persist across reboots and configuration rebuilds
- **FR-020**: Optimizations MUST not break existing KDE functionality

### Key Entities

- **Compositor Configuration**: kwinrc settings for backend, effects, performance limits
- **VM Resource Spec**: KubeVirt VirtualMachine specification with CPU, memory, IO settings
- **Service Management**: systemd services to disable/enable based on use case
- **RustDesk Configuration**: Codec, compression, network settings
- **Qt Environment**: Environment variables controlling Qt behavior in VM
- **NixOS Modules**: Declarative configuration modules for each optimization area

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Window drag operations complete with < 100ms perceived latency (measured subjectively)
- **SC-002**: KDE compositor CPU usage averages < 10% during normal operations (measured with htop)
- **SC-003**: Cursor movement achieves 25-30 FPS with < 50ms lag (measured with visual tests)
- **SC-004**: Screen updates maintain 25-30 FPS during scrolling operations
- **SC-005**: Idle RAM usage decreases by 1-2GB after service optimization (measured with free -h)
- **SC-006**: Background CPU usage stays < 5% when desktop is idle (measured with top)
- **SC-007**: RustDesk connection bandwidth stays < 30 Mbps for 1080p desktop at good quality
- **SC-008**: System rebuild with optimizations completes without errors in dry-build test
- **SC-009**: Configuration contains zero imperative scripts (all declared in Nix files)
- **SC-010**: User reports 2-3x improvement in perceived desktop responsiveness (subjective survey)

## Assumptions

- **ASM-001**: KubeVirt VMs have sufficient physical CPU resources on host (4-8 physical cores available)
- **ASM-002**: Network latency between client and VM is < 50ms (LAN or VPN)
- **ASM-003**: VM storage backend provides adequate I/O performance (local SSD or fast network storage)
- **ASM-004**: RustDesk is configured with direct IP access over Tailscale or LAN
- **ASM-005**: Users access VM via X11 session, not Wayland (X11 required for RustDesk)
- **ASM-006**: GPU passthrough is not available (software rendering via llvmpipe)
- **ASM-007**: Users prioritize responsiveness over visual effects
- **ASM-008**: KDE Plasma 6 is the desktop environment (configuration targets Plasma 6 API)
- **ASM-009**: NixOS 24.11 or later is the base system (for module compatibility)
- **ASM-010**: Users accept trade-off: instant animations and minimal effects for better performance

## Out of Scope

- **OOS-001**: GPU passthrough configuration (requires dedicated GPU hardware, separate feature)
- **OOS-002**: Alternative remote desktop protocols (VNC, X2Go, NoMachine - RustDesk is chosen)
- **OOS-003**: Complete desktop environment replacement (staying with KDE Plasma)
- **OOS-004**: Custom KDE themes or extensive visual customization
- **OOS-005**: Audio optimization beyond current PulseAudio setup
- **OOS-006**: Multi-user concurrent access optimization
- **OOS-007**: Performance tuning for 4K/high-resolution displays (targeting 1080p)
- **OOS-008**: Container-based desktop environments (targeting KubeVirt VMs specifically)

## Implementation Phases

### Phase 1: Compositor Optimization (Days 1-2)
- Create NixOS module for KDE compositor optimizations
- Configure XRender backend, disable effects, set FPS limits
- Test on single VM, measure baseline vs optimized performance
- Document performance improvements

### Phase 2: Service Cleanup (Day 3)
- Disable Baloo file indexer
- Disable Akonadi PIM services
- Remove unnecessary autostart services
- Measure RAM and CPU savings

### Phase 3: VM Resource Optimization (Days 4-5)
- Update KubeVirt VM specification with dedicated CPU placement
- Increase vCPU and RAM allocation
- Enable IOThreads
- Test resource allocation with `kubectl describe vmi`

### Phase 4: RustDesk Tuning (Day 6)
- Test codec options (VP8, VP9, H.264)
- Optimize compression settings
- Verify direct IP access configuration
- Measure bandwidth and latency

### Phase 5: Integration and Testing (Day 7)
- Combine all optimizations
- Full end-to-end testing
- Performance benchmarking
- Documentation updates

## Related Documentation

- Research findings: `research.md` (compilation from 3 research agents)
- Implementation plan: `plan.md` (to be created)
- NixOS constitution: `.specify/memory/constitution.md`
- Current KDE config: `home-modules/desktop/plasma-config.nix`
- KubeVirt VM config: `configurations/vm-hetzner.nix`

## Success Validation

After implementation, validation will include:
1. **Subjective testing**: 5 users rate responsiveness improvement on scale of 1-10
2. **Objective metrics**: CPU usage, RAM usage, FPS measurements
3. **Benchmark comparison**: Before/after measurements of key operations
4. **Configuration audit**: Verify all changes are declared in Nix files
5. **Reproducibility test**: Build fresh VM, verify performance matches

Expected timeline: 7 days for full implementation and validation.
