# Implementation Plan: Waybar Integration

**Branch**: `052-waybar-integration` | **Date**: 2025-10-31 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/052-waybar-integration/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Replace swaybar with Waybar as the status bar for Sway/Wayland configurations, providing GTK-based visual enhancements (icons, hover effects, tooltips, click handlers) while preserving the existing i3pm daemon's event-driven architecture via signal-based custom module updates. Configuration will be added to home-manager modules with Catppuccin Mocha theme styling, dual-bar layout (top: system monitoring, bottom: project context + workspaces), and multi-monitor support matching the current swaybar setup.

## Technical Context

**Language/Version**: Nix expressions for home-manager configuration, JSON for Waybar config, CSS for styling
**Primary Dependencies**: Waybar (latest in nixpkgs), i3pm daemon (existing event-driven system), Font Awesome fonts (for icons), GTK3 runtime
**Storage**: File-based configuration in `~/.config/waybar/` (config.json, style.css, scripts/)
**Testing**: Manual acceptance testing per spec scenarios, `home-manager switch` validation, multi-monitor visual verification
**Target Platform**: NixOS with Sway/Wayland (hetzner-sway reference configuration, M1 MacBook Pro)
**Project Type**: Home-manager module modification with new configuration files
**Performance Goals**: <50ms hover effect latency, <100ms click action execution, <100ms signal update latency (matching existing i3bar baseline)
**Constraints**: Must maintain existing i3pm daemon signal broadcast mechanism without modification, must support multi-monitor with independent Waybar instances, must preserve existing status script compatibility
**Scale/Scope**: 2 Waybar configurations (top/bottom bars), 6-8 custom modules (project, workspace mode, battery, WiFi, volume, etc.), CSS stylesheet, signal mappings for event-driven updates

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I - Modular Composition ✅
**Status**: PASS
**Rationale**: This feature modifies the existing home-manager Sway module (`home-modules/desktop/sway.nix`) and adds a new Waybar configuration module. No duplication - existing swaybar configuration will be removed after successful migration. Waybar configuration follows the established pattern of `xdg.configFile` for declarative config file generation.

### Principle II - Reference Implementation Flexibility ✅
**Status**: PASS
**Rationale**: This feature targets the reference implementation (hetzner-sway) and the M1 MacBook Pro. Both use Sway/Wayland compositor. Waybar is validated against the reference platform first before applying to M1 configuration.

### Principle III - Test-Before-Apply ✅
**Status**: PASS (with process)
**Process**: All configuration changes will be tested with `home-manager switch --flake .#hetzner-sway` before committing. Multi-monitor layout will be validated via VNC connections to all three HEADLESS-* displays. M1 single-display configuration will be tested separately with `home-manager switch --flake .#m1`.

### Principle VI - Declarative Configuration Over Imperative ✅
**Status**: PASS
**Rationale**: All Waybar configuration will be declaratively generated via home-manager's `xdg.configFile` mechanism. Custom module scripts will be generated as executable files in `~/.config/waybar/scripts/` with proper shebangs and permissions. No post-install steps or imperative configuration required.

### Principle VII - Documentation as Code ✅
**Status**: PASS (with deliverable)
**Deliverable**: quickstart.md will document Waybar usage, module interactions, click handlers, hover behavior, and CSS customization. CLAUDE.md will be updated with Waybar section replacing swaybar documentation, including multi-monitor VNC access patterns with the new status bars.

### Principle IX - Tiling Window Manager & Productivity Standards ✅
**Status**: PASS
**Rationale**: Waybar enhances the existing Sway tiling window manager with visual status information. Keyboard shortcuts remain primary interaction method. Click handlers provide optional mouse interaction without replacing keyboard-driven workflows. Project switcher click action opens Walker launcher (keyboard-driven).

### Principle XII - Forward-Only Development & Legacy Elimination ✅
**Status**: PASS
**Rationale**: swaybar configuration will be completely removed after successful Waybar migration. No dual support, no feature flags, no backwards compatibility preservation. Migration is immediate and complete following the 4-phase rollout strategy (dual config only during testing, not long-term).

### No Violations - No Complexity Justification Required

## Project Structure

### Documentation (this feature)

```
specs/052-waybar-integration/
├── spec.md              # Feature specification (already exists)
├── checklists/
│   └── requirements.md  # Specification quality checklist (already exists)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - Waybar module documentation research
├── quickstart.md        # Phase 1 output - User-facing Waybar usage guide
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

Note: No data-model.md or contracts/ needed - this is a configuration-only feature with no new data models or APIs. Waybar's JSON config and custom module signal protocol are well-documented external interfaces.

### Source Code (repository root)

```
home-modules/desktop/
├── sway.nix             # EXISTING FILE - will be modified to launch Waybar instead of swaybar
└── waybar.nix           # NEW FILE - Waybar configuration module

# Configuration structure within waybar.nix:
xdg.configFile."waybar/config-top.json"      # Top bar configuration (system monitoring)
xdg.configFile."waybar/config-bottom.json"   # Bottom bar configuration (project context + workspaces)
xdg.configFile."waybar/style.css"            # Catppuccin Mocha CSS styling
xdg.configFile."waybar/scripts/project-status.sh"      # EXISTING SCRIPT - adapted for Waybar custom module
xdg.configFile."waybar/scripts/workspace-mode.sh"      # EXISTING SCRIPT - adapted for Waybar custom module
xdg.configFile."waybar/scripts/battery-tooltip.sh"     # NEW - detailed battery info for tooltip
xdg.configFile."waybar/scripts/wifi-tooltip.sh"        # NEW - detailed WiFi info for tooltip

# Sway configuration changes:
home-modules/desktop/sway.nix
  # Remove: bar { } block referencing swaybar
  # Add: exec-once waybar -c ~/.config/waybar/config-top.json -s ~/.config/waybar/style.css
  # Add: exec-once waybar -c ~/.config/waybar/config-bottom.json -s ~/.config/waybar/style.css

# No new test files - testing via manual acceptance scenarios from spec.md
```

**Structure Decision**: This is primarily a configuration replacement feature. A new `waybar.nix` home-manager module will be created following the established pattern in `home-modules/desktop/` (similar to existing `walker.nix`, `i3bar.nix`). The module uses `xdg.configFile` for declarative generation of Waybar's JSON configuration files, CSS stylesheet, and custom module scripts. Existing status scripts from the i3bar configuration will be adapted to Waybar's custom module format (primarily changing output format from i3bar JSON protocol to plain text/JSON for Waybar). The Sway module will be updated to launch two Waybar instances (top and bottom bars) instead of swaybar, with appropriate signal mappings configured for i3pm daemon integration.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

No violations detected - Complexity Tracking table not needed.

## Phase 0: Research

**Objective**: Understand Waybar configuration structure, custom module protocol, signal-based updates, and CSS styling capabilities to ensure compatibility with existing i3pm daemon architecture.

**Key Research Questions**:

1. **Waybar Custom Module Protocol**:
   - How do custom modules receive POSIX signals for event-driven updates?
   - What signal numbers are available (RTMIN through RTMAX)?
   - How does signal mapping work in Waybar configuration (`"signal": N` syntax)?
   - Can existing i3pm daemon broadcast signals to Waybar custom modules without modification?

2. **Multi-Monitor Configuration**:
   - How does Waybar detect and bind to specific Sway outputs (HEADLESS-1, HEADLESS-2, HEADLESS-3)?
   - What is the syntax for output-specific bar configuration?
   - Can multiple Waybar instances run simultaneously with different configs?
   - How does workspace module filtering work (showing only workspaces for specific outputs)?

3. **Event-Driven Integration**:
   - Can custom modules execute shell scripts that read i3pm daemon state?
   - What is the performance overhead of signal-based updates vs polling?
   - How does Waybar handle signal storms (rapid successive signals)?
   - What debouncing mechanisms exist for custom module updates?

4. **Click Handler Syntax**:
   - How are `on-click`, `on-click-middle`, `on-click-right`, `on-scroll-up`, `on-scroll-down` configured?
   - Can click handlers execute arbitrary shell commands?
   - How do click handlers integrate with existing tools (pactl, Walker launcher, brightness controls)?

5. **CSS Styling Capabilities**:
   - What CSS selectors are available for module targeting (`.battery`, `.network`, `.custom-project`)?
   - How are hover effects implemented (`:hover` pseudo-class support)?
   - How does GTK CSS differ from standard web CSS?
   - What Catppuccin Mocha theme variables should be defined for consistency?

6. **Tooltip Configuration**:
   - How are tooltips configured for built-in modules (battery, network)?
   - Can custom modules have dynamic tooltips via script output?
   - What is the tooltip update mechanism (polling vs event-driven)?

7. **Icon Rendering**:
   - How does Waybar load Font Awesome icons?
   - What icon syntax is used (Unicode codepoints, CSS classes, or glyph references)?
   - How are icon colors controlled (CSS vs module config)?

**Research Deliverable**: `research.md` document covering:
- Waybar configuration JSON schema and options reference
- Custom module signal protocol with working examples
- Multi-monitor Waybar instance management patterns
- CSS styling guide with Catppuccin Mocha theme integration
- Migration checklist from swaybar to Waybar (config mapping, script adaptation)

## Phase 1: Design

**Objective**: Design Waybar configuration architecture that preserves i3pm daemon integration while providing visual enhancements and multi-monitor support.

**Design Tasks**:

1. **Module Mapping** (swaybar → Waybar):
   - Map existing swaybar modules to Waybar equivalents
   - Identify which modules need custom scripts (project status, workspace mode)
   - Plan signal number assignments for i3pm daemon broadcasts

2. **Dual-Bar Layout Design**:
   - **Top Bar** (system monitoring):
     - Left: Sway mode indicator, workspace mode indicator (→ WS, ⇒ WS, ✖ WS)
     - Center: Clock/date
     - Right: Battery, WiFi, Bluetooth, volume, CPU load, memory
   - **Bottom Bar** (project context):
     - Left: Workspaces (filtered per output)
     - Center: Window title
     - Right: Project status (from i3pm daemon)

3. **Custom Module Design**:
   - `custom/project`: Reads i3pm daemon state, receives SIGRTMIN+10 from daemon on project switch
   - `custom/workspace-mode`: Shows workspace mode state (→ WS, ⇒ WS, ✖ WS), receives SIGRTMIN+11 from daemon
   - Script output format: Plain text with optional icon prefix, newline-separated tooltip data

4. **Signal Integration Architecture**:
   - i3pm daemon already broadcasts signals on project switch (verify existing code)
   - Waybar custom modules register signal numbers in config (`"signal": 10` for RTMIN+10)
   - Scripts query daemon state via `i3pm project current` or daemon IPC
   - Performance target: <100ms from signal to Waybar display update

5. **CSS Theme Design**:
   - Define Catppuccin Mocha color variables
   - Create module-specific styles (`.battery`, `.network`, `.custom-project`)
   - Design hover effects (color transitions, subtle glow, border highlights)
   - Ensure contrast for readability on dark backgrounds

6. **Multi-Monitor Strategy**:
   - **Hetzner Cloud**: 3 Waybar instances (one per HEADLESS-* output), each with filtered workspaces
   - **M1 MacBook Pro**: 1 Waybar instance for eDP-1 output, all workspaces visible
   - Output binding via `"output": "HEADLESS-1"` syntax in Waybar config
   - Workspace filtering via Sway IPC queries in custom scripts

**Design Deliverables**:
- **quickstart.md**: User-facing guide with module reference, click handler documentation, CSS customization examples
- **waybar-config-draft.json**: Initial JSON configuration for top/bottom bars with module definitions
- **waybar-style-draft.css**: Initial CSS with Catppuccin Mocha theme and hover effects
- **signal-mapping.md**: Documentation of signal assignments and i3pm daemon integration

## Phase 2: Implementation (via `/speckit.tasks`)

**Note**: Detailed task breakdown will be generated by the `/speckit.tasks` command after Phase 1 design completion. This creates the `tasks.md` file with granular implementation tasks.

**High-Level Implementation Phases** (for planning context):

### Phase 2.1: Basic Waybar Configuration
- Create `home-modules/desktop/waybar.nix` with dual-bar configuration
- Generate JSON configs for top/bottom bars with standard modules
- Generate CSS stylesheet with Catppuccin Mocha theme
- Update `sway.nix` to launch Waybar instances on startup
- Test with `home-manager switch --flake .#hetzner-sway`

### Phase 2.2: Custom Module Integration
- Adapt existing project status script for Waybar custom module format
- Adapt existing workspace mode script for Waybar custom module format
- Configure signal mappings (RTMIN+10 for project, RTMIN+11 for workspace mode)
- Verify i3pm daemon signal broadcasts reach Waybar modules
- Test project switching and workspace mode with real-time updates

### Phase 2.3: Visual Enhancements
- Implement hover effects in CSS (`:hover` styles for all modules)
- Add tooltip scripts for battery (time remaining) and WiFi (IP address)
- Configure Font Awesome icon rendering
- Test visual feedback latency (<50ms hover, <100ms click)

### Phase 2.4: Click Handler Implementation
- Configure volume click handler (mute/unmute with pactl)
- Configure volume scroll handler (adjust volume with pactl)
- Configure project click handler (launch Walker with project switcher)
- Test click actions for expected behavior

### Phase 2.5: Multi-Monitor Configuration
- Configure output bindings for Hetzner (3 instances: HEADLESS-1/2/3)
- Configure workspace filtering per output
- Test via VNC connections to all displays
- Configure M1 single-display variant (eDP-1 output)

### Phase 2.6: Migration and Cleanup
- Verify all features working on hetzner-sway reference platform
- Test on M1 MacBook Pro with Wayland session
- Document rollback procedure in CLAUDE.md
- Remove swaybar configuration from `sway.nix`
- Update CLAUDE.md with Waybar section (replace swaybar content)

## Migration Strategy

Following the 4-phase migration strategy from the spec:

### Phase 1: Dual Configuration (Safe Rollback) - Week 1
- Keep existing swaybar configuration commented out in `sway.nix`
- Add Waybar module with basic modules (no custom scripts yet)
- Test multi-monitor layout matches current swaybar setup
- Verify visual rendering and icon display
- Rollback: Uncomment swaybar, disable Waybar, reload Sway

### Phase 2: Custom Module Integration - Week 1-2
- Port project status script to Waybar custom module format
- Port workspace mode script to Waybar custom module format
- Configure signal-based updates from i3pm daemon
- Validate <100ms update latency with timing tests
- Test project switching workflow end-to-end
- Rollback: Remove custom modules, revert to basic Waybar or swaybar

### Phase 3: Visual Enhancements - Week 2
- Apply CSS styling with Catppuccin Mocha theme
- Implement hover effects and test latency
- Add click handlers for volume, project switcher
- Implement tooltips with dynamic content
- Visual verification on all displays via VNC
- Rollback: Disable click handlers, revert CSS to minimal styles

### Phase 4: Cleanup and Documentation - Week 3
- Operate with full Waybar configuration for 1 week stable period
- Monitor for any issues via VNC sessions and M1 testing
- Document Waybar usage in CLAUDE.md (module reference, click handlers, CSS customization)
- Remove swaybar configuration entirely from `sway.nix`
- Final rollback checkpoint: Git tag before swaybar removal

### Rollback Procedure (Emergency)
If critical issues arise at any phase:
1. Edit `home-modules/desktop/sway.nix` - comment Waybar exec lines
2. Uncomment swaybar `bar { }` block
3. Run `home-manager switch --flake .#hetzner-sway`
4. Reload Sway: `swaymsg reload`
5. Reconnect VNC to verify swaybar restored
6. Debug Waybar issues in isolated test branch

## Success Validation

Post-implementation validation checklist (from spec Success Criteria):

- [ ] **SC-001**: System status (battery, network, volume) identifiable at a glance via icons and colors (visual test on all displays)
- [ ] **SC-002**: Hover effects appear within 50ms (measure with manual stopwatch or screen recording analysis)
- [ ] **SC-003**: Click actions execute within 100ms (test volume mute, project switcher launch)
- [ ] **SC-004**: Status bar updates reflect daemon events within 100ms (measure with daemon event timestamps and Waybar update logs)
- [ ] **SC-005**: Custom module scripts execute without modification from current implementation (verify project-status.sh, workspace-mode.sh)
- [ ] **SC-006**: Visual appearance matches Catppuccin Mocha theme (color comparison with existing i3 theme)
- [ ] **SC-007**: Multi-monitor setup displays independent status bars on each output (verify via VNC to HEADLESS-1/2/3)
- [ ] **SC-008**: Configuration reload completes in under 500ms (measure `swaymsg reload` duration)
- [ ] **SC-009**: System resource usage within 10% of swaybar baseline (monitor CPU/memory with `htop` before/after)
- [ ] **SC-010**: Tooltip information displays within 200ms of hover (test battery, WiFi tooltips)

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Waybar incompatible with existing signal broadcast mechanism | High | Low | Research phase validates signal protocol compatibility, fallback to polling if needed |
| CSS styling unable to replicate Catppuccin Mocha theme | Medium | Low | GTK CSS supports full color customization, reference existing GTK themes for patterns |
| Multi-monitor workspace filtering complex to configure | Medium | Medium | Research Waybar output binding and workspace filtering, leverage Sway IPC for dynamic queries |
| Performance degradation with GTK rendering overhead | Medium | Low | Baseline resource usage measurement, monitor with htop, GTK3 is mature and performant |
| Custom module scripts require significant refactoring | Medium | Low | Existing scripts already modular, output format change is minor (i3bar JSON → plain text) |
| i3pm daemon signal numbering conflicts with Waybar | Low | Low | Waybar allows custom RTMIN+ offsets, flexible signal number assignment |
| VNC rendering issues with GTK applications | Low | Low | VNC already supports GTK applications (Firefox, VS Code), Waybar should work similarly |
| Rollback difficulty if migration fails | Low | Low | Dual configuration phase allows safe testing, swaybar config preserved as commented code |

## Notes

- Waybar is a mature project with active development and comprehensive documentation
- GTK3 dependency is acceptable for desktop configurations (already present for Firefox, VS Code)
- Signal-based updates maintain the event-driven architecture from i3pm daemon (no polling overhead)
- CSS customization provides future flexibility for theme changes and visual tweaks
- Multi-monitor configuration is well-supported in Waybar with per-output instance binding
- This feature aligns with the Reference Implementation (hetzner-sway) as the canonical Sway/Wayland deployment
- M1 MacBook Pro will benefit from native Wayland GTK rendering with HiDPI support
