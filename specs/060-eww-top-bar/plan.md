# Implementation Plan: Eww-Based Top Bar with Catppuccin Mocha Theme

**Branch**: `060-eww-top-bar` | **Date**: 2025-11-14 | **Spec**: [spec.md](./spec.md)

## Summary

Transform the Sway top bar from Swaybar to Eww framework with Catppuccin Mocha theming matching the existing bottom workspace bar. The implementation will use Eww's `defpoll` for periodic system metrics updates (load, memory, disk, network) and `deflisten` for event-driven updates (volume, battery, bluetooth, i3pm project). The top bar will appear on all configured outputs (HEADLESS-1/2/3 for Hetzner, eDP-1/HDMI-A-1 for M1) with click handlers launching configuration applications. System metrics will be collected via Python scripts reading `/proc` and `/sys` filesystems, reusing patterns from the existing swaybar-enhanced implementation.

## Technical Context

**Language/Version**: Python 3.11+ (data collection scripts), Eww 0.4+ (widget system), Nix (declarative configuration)
**Primary Dependencies**: Eww (GTK3-based widgets), Python with psutil/pydbus/pygobject3 (shared environment), Nerd Fonts (icon rendering)
**Storage**: In-memory state only (no persistence), JSON output from polling scripts
**Testing**: Manual validation on M1 MacBook and Hetzner Cloud, Eww config syntax validation, systemd service health checks
**Target Platform**: NixOS with Sway window manager (M1 MacBook Pro ARM64, Hetzner Cloud x86_64)
**Project Type**: Single project (NixOS module configuration)
**Performance Goals**: <50MB RAM overhead, <2% CPU usage, <2s metric update latency, <3s bar startup time
**Constraints**: Must match bottom bar visual theme exactly (Catppuccin Mocha), must not conflict with existing Swaybar configuration during transition, must auto-detect hardware capabilities
**Scale/Scope**: ~600 lines of Nix configuration, ~300 lines of Python scripts, ~200 lines of Eww config (Yuck), ~150 lines of Eww styles (SCSS)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition ✅ PASS
- **Compliance**: Feature will be implemented as a reusable NixOS module (`eww-top-bar.nix`) following the existing pattern from `eww-workspace-bar.nix`
- **Structure**: Common Eww patterns will be extracted, platform-specific logic will use conditional enablement (`lib.mkIf`), no code duplication from swaybar-enhanced (reuse Python scripts with output format adaptation)
- **Module responsibility**: Single clear purpose - top bar system metrics display with Eww widgets

### Principle II: Reference Implementation Flexibility ✅ PASS
- **Current reference**: Hetzner Sway configuration with full Wayland compositor features
- **Validation approach**: Feature will be tested on reference (Hetzner) first, then validated on M1 MacBook
- **Breaking changes**: Replaces existing Swaybar top bar, but does not affect core Sway or bottom workspace bar functionality
- **Documentation**: Will update CLAUDE.md with new top bar commands and configuration options

### Principle III: Test-Before-Apply ✅ PASS
- **Dry-build requirement**: Will use `nixos-rebuild dry-build --flake .#hetzner-sway` and `--flake .#m1 --impure` before applying
- **Rollback plan**: NixOS generations provide automatic rollback, systemd service can be stopped independently without affecting Sway session
- **Critical service**: Top bar is non-critical (can be disabled without breaking desktop), no boot-time dependency

### Principle IV: Override Priority Discipline ✅ PASS
- **Priority usage**: Will use `lib.mkDefault` for color defaults (allow user theme overrides), normal assignment for widget structure, `lib.mkForce` NOT needed (no conflicting options)
- **Module composition**: New module will compose with existing unified-bar-theme.nix without conflicts
- **Documentation**: Comments will explain why specific priority levels used

### Principle V: Platform Flexibility Through Conditional Features ✅ PASS
- **Hardware detection**: Auto-detect battery via `/sys/class/power_supply/`, bluetooth via `bluetoothctl`, thermal sensors via `/sys/class/thermal/`
- **Conditional enablement**: Battery/bluetooth/temperature blocks will use `lib.optionals` based on hardware presence
- **Multi-platform support**: Headless Hetzner (3 virtual displays, no battery/bluetooth) vs M1 MacBook (built-in display + HDMI, battery + bluetooth)
- **Pattern**: `hasHardware = builtins.pathExists "/sys/class/power_supply/BAT0";`

### Principle VI: Declarative Configuration Over Imperative ✅ PASS
- **Full declarative approach**: All configuration via Nix expressions (eww.yuck, eww.scss generated from Nix), systemd service managed by home-manager, Python scripts installed via `xdg.configFile`
- **No imperative scripts**: Zero post-install scripts required
- **Configuration generation**: Eww config generated via Nix string interpolation with `builtins.toJSON` and `lib.concatStringsSep`

### Principle VII: Documentation as Code ✅ PASS
- **Module documentation**: Header comments will explain purpose, dependencies (unified-bar-theme.nix, python-environment.nix), usage patterns
- **User guide**: Will create `specs/060-eww-top-bar/quickstart.md` with configuration examples, troubleshooting, customization options
- **CLAUDE.md update**: Will add top bar commands to "Unified Bar System (Feature 057)" section with reload/restart procedures

### Principle X: Python Development & Testing Standards ✅ PASS
- **Python version**: 3.11+ (matches existing i3-project daemon)
- **Shared environment**: Uses python-environment.nix shared module (psutil, pydbus, pygobject3 available)
- **Module structure**: Single-responsibility scripts (get-system-metrics.py for aggregated JSON output OR separate scripts per metric)
- **Error handling**: Explicit try/except with fallback values, logging via standard `logging` module
- **Type hints**: Function signatures with return types (`Optional[float]`, `dict`, etc.)

### Principle XI: i3 IPC Alignment & State Authority ✅ PASS
- **i3pm daemon health**: Will query i3pm daemon via Unix socket (existing pattern), use i3 IPC GET_TREE to validate daemon responsiveness
- **Active project display**: Will use `deflisten` streaming from i3pm daemon or polling `i3pm project current` command
- **State source**: i3 IPC as authoritative source for workspace/window state, daemon state queried via JSON-RPC

### Principle XII: Forward-Only Development & Legacy Elimination ✅ PASS
- **Complete replacement**: Will fully replace Swaybar top bar configuration, no dual support or compatibility layers
- **Migration approach**: Disable `wayland.windowManager.sway.config.bars` (top bars only) when enabling eww-top-bar module
- **No feature flags**: Single optimal implementation, no "legacy mode" or "swaybar fallback"
- **Documentation**: Migration notes will guide users to disable old configuration, not run both systems simultaneously

### Principle XIII: Deno CLI Development Standards ⚠️ N/A
- **Not applicable**: This feature uses Python scripts (not CLI tools), Nix configuration (not TypeScript), Eww widgets (not terminal UI)
- **Python justification**: System metrics collection requires `/proc` and `/sys` filesystem access, Python standard library ideal for this, no CLI tool needed

### Principle XIV: Test-Driven Development & Autonomous Testing ⚠️ PARTIAL
- **Manual testing required**: Eww widget rendering and visual appearance cannot be autonomously tested without screenshot comparison
- **State verification available**: Python script outputs (JSON), systemd service status, Eww window presence via Sway IPC can be tested
- **Test approach**: Unit tests for Python metric collection functions (pytest), integration tests for systemd service startup, manual visual validation for theming/layout
- **Test pyramid**: 70% unit (Python functions), 20% integration (service lifecycle), 10% manual (visual appearance)

### Principle XV: Sway Test Framework Standards ⚠️ PARTIAL
- **Partial applicability**: Sway window state (Eww dock window present, positioned correctly) can be validated via sway-test
- **Visual rendering limitation**: Widget appearance (colors, icons, text) cannot be validated via Sway IPC (requires screenshot comparison or manual inspection)
- **Test coverage**: Window geometry, struts reservation, multi-monitor positioning testable via sway-test; color accuracy and icon rendering require manual validation

### Constitution Violations Requiring Justification

**None** - All applicable principles satisfied. Test-driven development principles (XIV, XV) have acknowledged limitations for visual rendering validation (GTK widget appearance), which is acceptable given:
1. Visual appearance has no automated testing solution available (screenshot comparison unreliable across GTK versions)
2. Functional behavior (metrics collection, window positioning, service lifecycle) will have comprehensive automated tests
3. Manual validation will be documented with screenshots and specific acceptance criteria

## Project Structure

### Documentation (this feature)

```text
specs/060-eww-top-bar/
├── spec.md                      # Feature specification (complete)
├── plan.md                      # This file (current phase)
├── research.md                  # Phase 0 output (next step)
├── data-model.md                # Phase 1 output
├── quickstart.md                # Phase 1 output
├── contracts/                   # Phase 1 output
│   ├── system-metrics-schema.json   # JSON schema for metric output
│   └── eww-widget-api.md            # Eww widget interface documentation
├── checklists/                  # Quality validation
│   └── requirements.md          # Specification validation (complete)
└── tasks.md                     # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
home-modules/desktop/
├── eww-top-bar.nix              # Main module (NixOS option definition, systemd service)
└── eww-top-bar/                 # Configuration files
    ├── eww.yuck.nix             # Widget definitions (generated Yuck syntax)
    ├── eww.scss.nix             # Styles (generated CSS with Catppuccin colors)
    └── scripts/
        ├── system-metrics.py    # Aggregated metrics (JSON output for defpoll)
        ├── i3pm-health.sh       # i3pm daemon health check (shell script)
        ├── active-project.py    # Active i3pm project display (deflisten streaming)
        └── hardware-detect.py   # Battery/bluetooth/thermal detection

home-modules/desktop/
├── unified-bar-theme.nix        # Existing theme (dependency, no changes)
└── python-environment.nix       # Existing Python env (dependency, no changes)

tests/eww-top-bar/
├── unit/
│   ├── test_system_metrics.py   # Python metric collection tests
│   └── test_hardware_detect.py  # Hardware detection tests
├── integration/
│   ├── test_service_lifecycle.py    # systemd service tests
│   └── test_eww_window_creation.py  # Sway IPC window validation
└── sway-tests/
    ├── test_top_bar_positioning.json    # Multi-monitor window placement
    └── test_top_bar_struts.json         # Screen space reservation
```

**Structure Decision**: Single project structure (Option 1 from template) selected because this is a NixOS module feature, not a standalone application. All code lives in the existing `/etc/nixos` repository under `home-modules/` and `tests/` directories following established patterns from `eww-workspace-bar.nix` (bottom bar) and `swaybar-enhanced.nix` (current top bar).

## Complexity Tracking

> **No violations requiring justification** - This feature follows all applicable constitution principles. The implementation complexity is justified by:

| Design Aspect | Justification | Simpler Alternative Rejected |
|---------------|---------------|------------------------------|
| Eww framework over Swaybar | User explicitly requested Eww transformation for visual consistency with bottom bar. Eww provides GTK3 widgets with custom CSS styling not available in Swaybar (icon glows, transitions, gradients). | Keeping Swaybar insufficient - lacks theming flexibility and visual parity with existing bottom bar |
| Python scripts for metrics | Established pattern from swaybar-enhanced.nix. Python standard library provides robust `/proc` and `/sys` parsing without external dependencies. Shared Python environment already available. | Pure shell scripts rejected - harder to maintain, less robust error handling, no type safety, difficult JSON generation |
| Per-monitor Eww instances | Eww's multi-monitor model requires separate `defwindow` per output (established pattern from eww-workspace-bar.nix). Alternative (single window spanning monitors) not supported by Eww/GTK. | Single-window approach impossible - Eww limitation, would require fork/patch |
| Systemd service per-user | Eww daemon must run in user session for GTK/Wayland access. System-wide service insufficient for per-user desktop integration. | System-wide daemon rejected - cannot access user Wayland session, would require complex privilege dropping |

## Phase 0: Research & Decisions

**Prerequisites**: Constitution Check passed (above)

**Objective**: Resolve all "NEEDS CLARIFICATION" items from Technical Context and research best practices for Eww widget design, system metrics collection, and multi-monitor configuration.

### Research Tasks

1. **Eww Widget Design Patterns** (RESOLVED via exploration)
   - **Question**: How should system metrics be displayed as Eww widgets (layout, icons, colors)?
   - **Findings**:
     - Use horizontal box layout with icon + text labels
     - Nerd Font icons for visual consistency (e.g.,  for CPU,  for memory)
     - Color-coded status (blue for CPU, sapphire for memory, sky for disk, teal for network)
     - Spacing with separator bars (`|`) between blocks
   - **Decision**: Follow bottom workspace bar patterns - horizontal box container, icon+label buttons, semi-transparent background, border radius 6px, Catppuccin Mocha colors from unified-bar-theme.nix
   - **Reference**: `/etc/nixos/home-modules/desktop/eww-workspace-bar.nix` lines 1-300 (widget structure)

2. **System Metrics Collection Strategy** (RESOLVED via exploration)
   - **Question**: Should metrics use individual scripts or single aggregated script? Polling vs streaming?
   - **Findings**:
     - Single JSON output script is most efficient (one Python process instead of 6+)
     - Polling (`defpoll`) with 2-5s intervals acceptable for system metrics (not time-critical)
     - Streaming (`deflisten`) better for event-driven data (volume changes, battery events)
   - **Decision**:
     - Use single `system-metrics.py` script with JSON output for periodic metrics (load, memory, disk, network, temperature)
     - Use `deflisten` for event-driven updates (volume via PulseAudio events, battery via UPower D-Bus, active project via i3pm daemon)
     - Update intervals: 2s (CPU/memory), 5s (disk/network), 1s (time), event-driven (volume/battery/project)
   - **Reference**: `/etc/nixos/home-modules/desktop/swaybar/blocks/system.py` (existing metric collection logic)

3. **Multi-Monitor Configuration Approach** (RESOLVED via exploration)
   - **Question**: How to create per-monitor Eww windows dynamically based on system configuration?
   - **Findings**:
     - Detect monitors at build time via NixOS config (static) or runtime via Sway IPC (dynamic)
     - Generate separate `defwindow` blocks for each output in Nix
     - Use `eww open-many` to launch all windows simultaneously
   - **Decision**: Static configuration via NixOS with per-monitor window generation (matching eww-workspace-bar pattern). Detect headless vs laptop via `osConfig.networking.hostName`, generate window list at build time, open all windows via systemd `ExecStartPost`.
   - **Reference**: `/etc/nixos/home-modules/desktop/eww-workspace-bar.nix` lines 180-250 (workspaceOutputs, windowBlocks pattern)

4. **Hardware Auto-Detection Strategy** (RESOLVED via exploration)
   - **Question**: How to detect battery/bluetooth/thermal hardware and conditionally show blocks?
   - **Findings**:
     - Battery: Check `/sys/class/power_supply/BAT*` existence
     - Bluetooth: Query `bluetoothctl list` or D-Bus `org.bluez` interface
     - Thermal: Glob `/sys/class/thermal/thermal_zone*/temp` paths
   - **Decision**: Python script at build time generates JSON with hardware capabilities, Nix reads JSON and conditionally includes widget blocks. Pattern: `hasHardware = builtins.fromJSON (builtins.readFile ./hardware-detect.json);`
   - **Alternative**: Runtime detection in Python scripts (preferred for simplicity) - scripts return `null` if hardware unavailable, Eww hides empty blocks via CSS `display: none` on empty content
   - **Reference**: `/etc/nixos/home-modules/desktop/swaybar-enhanced.nix` lines 79-89 (detectBattery/detectBluetooth options)

5. **Click Handler Implementation** (RESOLVED via exploration)
   - **Question**: How to launch applications when clicking status blocks?
   - **Findings**:
     - Eww `eventbox` widget with `:onclick` property executes shell commands
     - Commands spawn asynchronously (non-blocking)
     - Common pattern: `(eventbox :onclick "pavucontrol &" (label :text volume_text))`
   - **Decision**: Wrap each status block in `eventbox` with appropriate click handler. Use absolute paths to executables (e.g., `${pkgs.pavucontrol}/bin/pavucontrol`) for reproducibility.
   - **Handlers**: Volume → pavucontrol, Network → nm-connection-editor, Bluetooth → blueman-manager, DateTime → gnome-calendar, Project → `walker --modules=applications --filter="i3pm;p"`
   - **Reference**: `/etc/nixos/home-modules/desktop/eww-quick-panel.nix` lines 50-80 (eventbox click handlers)

### Technology Decisions

All decisions resolved above. Summary:

| Technology Choice | Decision | Rationale |
|-------------------|----------|-----------|
| Widget Framework | Eww 0.4+ with GTK3 | User requirement, visual consistency with bottom bar |
| Data Collection | Python 3.11+ with standard library | Established pattern, robust error handling, shared environment available |
| Update Mechanism | `defpoll` for periodic, `deflisten` for events | Balance between simplicity (polling) and responsiveness (streaming) |
| Monitor Detection | Static NixOS config with per-monitor windows | Matches bottom bar pattern, avoids runtime complexity |
| Hardware Detection | Runtime Python checks returning null | Simpler than build-time detection, graceful degradation |
| Theme Integration | Unified-bar-theme.nix color imports | Reuses Feature 057 infrastructure, single source of truth |
| Service Management | systemd user service with auto-restart | Standard pattern, reliability, session integration |

### Best Practices Research

**Eww Widget Performance**:
- Minimize `defpoll` frequency (2s minimum for non-critical metrics)
- Use JSON output for structured data (faster than parsing text)
- Avoid expensive commands in polling (cache results where possible)
- Use `deflisten` for high-frequency updates only when necessary

**GTK3 Widget Optimization**:
- Limit nested boxes (flat hierarchy preferred)
- Use CSS transitions sparingly (0.2s max)
- Avoid complex shadows/glows on high-frequency updates
- Test on low-powered hardware (M1 is fast, but headless Hetzner VMs may be slower)

**Sway Integration**:
- Always use `:exclusive true` + `:reserve (struts ...)` together
- Anchor position must match struts side (top anchor + top struts)
- Test with multiple monitors (focus issues common)

**Python Script Reliability**:
- Always handle missing `/proc` or `/sys` paths gracefully
- Use timeouts for subprocess calls (2s max)
- Log errors but don't crash (return null/default values)
- Test on headless systems (no battery/bluetooth/thermal)

## Phase 1: Design & Contracts

**Prerequisites**: Phase 0 research complete (above), all NEEDS CLARIFICATION resolved

**Objective**: Define data models, system metrics output schema, Eww widget interfaces, and create quickstart documentation.

### Deliverables

1. **data-model.md**: Entity definitions for status blocks, system metrics, hardware capabilities, Eww windows
2. **contracts/system-metrics-schema.json**: JSON schema for Python script outputs
3. **contracts/eww-widget-api.md**: Eww widget interface documentation (variables, events, click handlers)
4. **quickstart.md**: User-facing documentation with configuration examples, troubleshooting, customization

### Agent Context Update

After Phase 1 completion:
- Run `.specify/scripts/bash/update-agent-context.sh claude`
- Add new technology: Eww 0.4+ GTK3 widgets, system-metrics.py Python script, eww-top-bar.nix module
- Preserve existing manual additions in agent context

## Phase 2: Task Breakdown

**Prerequisites**: Phase 1 design complete, agent context updated

**Objective**: Generate actionable, dependency-ordered tasks in `tasks.md` via `/speckit.tasks` command

**Note**: Phase 2 tasks are generated by the `/speckit.tasks` command, not by `/speckit.plan`. This plan document ends after Phase 1 design artifacts are created.

## Next Steps

1. ✅ **Phase 0 Complete**: Research resolved, all technology decisions made (see Research Tasks section above)
2. **Phase 1 Next**: Create `research.md` documenting findings, then generate `data-model.md`, `contracts/`, and `quickstart.md`
3. **Phase 2 Later**: Run `/speckit.tasks` to generate implementation tasks from completed design artifacts

**Status**: Ready to proceed to Phase 1 design artifact generation. Research phase complete with all "NEEDS CLARIFICATION" items resolved via codebase exploration.
