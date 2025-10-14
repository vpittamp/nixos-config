# Feature Specification: Replace KDE Plasma with Hyprland

**Feature Branch**: `001-replace-kde-plasma`
**Created**: 2025-10-14
**Status**: Draft
**Input**: User description: "Replace KDE Plasma with Hyprland for fully declarative desktop environment. Migrate all applications and functionality from KDE Plasma to Hyprland while maintaining feature parity and ensuring full NixOS declarative configuration."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Core Desktop Environment (Priority: P1)

As a system administrator, I need a fully declarative desktop environment that boots to a functional Wayland session without requiring any manual configuration or imperative scripts, so that system rebuilds are reproducible and predictable.

**Why this priority**: This is the foundation requirement. Without a working desktop environment, no other features can be used or tested. This delivers immediate value by proving Hyprland can replace KDE Plasma as the primary desktop environment.

**Independent Test**: Can be fully tested by rebuilding the system with Hyprland configuration and logging in. Success means reaching a functional desktop with a compositor running, wallpaper displayed, and basic window management working.

**Acceptance Scenarios**:

1. **Given** system is configured with Hyprland, **When** system boots and user logs in, **Then** Hyprland compositor starts automatically with no errors
2. **Given** Hyprland is running, **When** user presses configured window management keybindings, **Then** windows tile, resize, and move as expected
3. **Given** Hyprland session is active, **When** user opens an application, **Then** application windows display correctly with proper decorations
4. **Given** system rebuild is performed, **When** comparing two builds, **Then** desktop environment configuration is identical (reproducible)

---

### User Story 2 - Application Compatibility (Priority: P2)

As a developer, I need all my existing applications (VS Code, terminals, browsers, file managers) to work seamlessly in Hyprland without loss of functionality, so that I can continue my daily workflow without disruption.

**Why this priority**: Applications are the core of productivity. Users need their tools working immediately after the migration. This story ensures that the 30+ applications currently in KDE Plasma continue to function.

**Independent Test**: Launch each critical application and verify it displays, accepts input, and performs core functions. Test list: Chromium, Firefox, VS Code, Konsole, Dolphin, Kate, Spectacle, Okular, Gwenview.

**Acceptance Scenarios**:

1. **Given** Hyprland is running, **When** user launches Chromium with 1Password extension, **Then** browser opens and 1Password integration works
2. **Given** Hyprland is running, **When** user launches VS Code, **Then** editor displays with correct fonts and theming
3. **Given** user is in VS Code, **When** user opens integrated terminal, **Then** terminal functions normally
4. **Given** Hyprland is running, **When** user launches Dolphin file manager, **Then** file browser displays and allows file operations
5. **Given** user launches multiple applications, **When** user switches between them, **Then** focus changes correctly and windows remain stable

---

### User Story 3 - Window Management Keybindings (Priority: P2)

As a keyboard-focused user, I need all my existing window management shortcuts (tiling, workspace switching, window movement) mapped to Hyprland equivalents, so that muscle memory and productivity are preserved.

**Why this priority**: Keyboard shortcuts are critical for power user productivity. Mapping KDE shortcuts to Hyprland ensures users don't need to relearn their workflow.

**Independent Test**: Test each keyboard shortcut from KDE Plasma configuration and verify equivalent behavior in Hyprland. Document shortcuts in a reference table showing KDE → Hyprland mapping.

**Acceptance Scenarios**:

1. **Given** Hyprland is running with multiple workspaces, **When** user presses Meta+1 through Meta+4, **Then** system switches to the corresponding workspace
2. **Given** window is focused, **When** user presses Meta+Shift+[1-4], **Then** window moves to the specified workspace
3. **Given** window is focused, **When** user presses Meta+Arrow keys, **Then** window tiles to the corresponding screen edge
4. **Given** multiple windows are open, **When** user presses Meta+Tab, **Then** workspace overview displays showing all windows
5. **Given** window is focused, **When** user presses Meta+PgUp/PgDn, **Then** window maximizes or minimizes

---

### User Story 4 - System Bar and Launcher (Priority: P3)

As a desktop user, I need a system status bar showing time, system tray, and resource usage, plus a quick launcher for applications, so that I have visual feedback and easy access to applications.

**Why this priority**: System bar provides important context (time, network status, battery) and launcher provides convenient application access. While not strictly required for core functionality, these significantly improve usability.

**Independent Test**: Verify system bar displays after login and shows accurate information. Test launcher by pressing configured key and typing application names.

**Acceptance Scenarios**:

1. **Given** Hyprland starts, **When** desktop loads, **Then** system bar appears showing time, workspace indicators, and system tray
2. **Given** system bar is visible, **When** system resources change (CPU, memory), **Then** indicators update to reflect current state
3. **Given** user presses configured launcher key (Meta+Space), **When** launcher appears, **Then** user can type to search applications
4. **Given** user types application name in launcher, **When** user presses Enter, **Then** matching application launches
5. **Given** system tray icon is present, **When** user clicks icon, **Then** corresponding application menu or action appears

---

### User Story 5 - Display and Multi-Monitor Support (Priority: P3)

As a user with multiple displays or HiDPI screens, I need display configuration to be declarative and automatic, so that displays work correctly without manual xrandr commands or configuration tools.

**Why this priority**: Display configuration is a common pain point. Declarative display settings ensure consistency across reboots and support both standard and HiDPI displays (critical for M1 Mac).

**Independent Test**: Boot system with different display configurations (single 1080p, single HiDPI, multiple monitors) and verify displays are configured correctly without manual intervention.

**Acceptance Scenarios**:

1. **Given** system boots with HiDPI display (M1 Mac), **When** Hyprland starts, **Then** display scaling is set to 1.75x automatically
2. **Given** system boots with standard 1080p display, **When** Hyprland starts, **Then** display uses 1x scaling
3. **Given** multiple monitors are connected, **When** Hyprland starts, **Then** all displays are enabled with correct positioning
4. **Given** display configuration changes (monitor added/removed), **When** change occurs, **Then** Hyprland adapts layout appropriately
5. **Given** HiDPI display is active, **When** user launches XWayland applications, **Then** applications scale correctly

---

### User Story 6 - Screenshot and Media Capture (Priority: P4)

As a content creator and documentation writer, I need screenshot functionality with the same keyboard shortcuts as KDE Plasma (Print, Meta+Shift+Print, etc.), so that I can capture screen content as part of my workflow.

**Why this priority**: Screenshots are essential for documentation and communication but not critical for basic system functionality. Can be added after core desktop is working.

**Independent Test**: Press each screenshot keybinding and verify correct capture behavior. Test: full screen (Print), region (Meta+Shift+Print), active window (Meta+Print).

**Acceptance Scenarios**:

1. **Given** Hyprland is running, **When** user presses Print key, **Then** screenshot tool launches in interactive mode
2. **Given** screenshot tool is active, **When** user selects region, **Then** region is captured and saved to Pictures directory
3. **Given** Hyprland is running, **When** user presses Meta+Shift+Print, **Then** region selection mode starts immediately
4. **Given** screenshot is captured, **When** user opens file manager, **Then** screenshot is accessible in ~/Pictures/Screenshots

---

### User Story 7 - Notification System (Priority: P4)

As a desktop user, I need system notifications to display when applications or services have important information, so that I stay informed of system events without constantly checking multiple applications.

**Why this priority**: Notifications improve user experience but aren't critical for core functionality. Applications will still work without a notification daemon.

**Independent Test**: Trigger notifications from various sources (system updates, application alerts, 1Password) and verify they display correctly with appropriate styling.

**Acceptance Scenarios**:

1. **Given** Hyprland is running, **When** application sends notification, **Then** notification appears on screen with correct content
2. **Given** notification is displayed, **When** user clicks notification, **Then** related application opens or action is performed
3. **Given** multiple notifications arrive, **When** they display, **Then** they stack or queue appropriately without overlapping
4. **Given** notification timeout expires, **When** time elapses, **Then** notification dismisses automatically

---

### Edge Cases

- What happens when XWayland applications need X11-specific features (clipboard, drag-and-drop)?
- How does system handle display configuration changes during active session (monitor hotplug)?
- What occurs when application requests features not available in Wayland (screen recording without portal)?
- How are legacy KDE configuration files handled during migration?
- What happens when user has existing KDE wallet credentials?
- How does system behave if Hyprland compositor crashes?
- What occurs when application is built for Qt5/Qt6 and expects KDE platform integration?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST start Hyprland compositor automatically on user login via display manager
- **FR-002**: System MUST configure all Hyprland settings (keybindings, workspaces, display settings) through declarative NixOS configuration
- **FR-003**: System MUST support all applications currently installed in KDE Plasma environment (30+ applications including browsers, editors, terminals, file managers)
- **FR-004**: System MUST provide workspace management with at least 4 workspaces per activity/monitor
- **FR-005**: System MUST implement window tiling with keybindings for left/right/top/bottom tiling
- **FR-006**: System MUST support HiDPI displays with configurable scaling factors (specifically 1.75x for M1 Mac Retina display)
- **FR-007**: System MUST provide XWayland support for X11-only applications
- **FR-008**: System MUST integrate with 1Password for application authentication and password management
- **FR-009**: System MUST provide system bar showing time, workspace indicators, and system tray icons
- **FR-010**: System MUST provide application launcher accessible via keyboard shortcut
- **FR-011**: System MUST support screenshot capture with keybindings matching current KDE shortcuts
- **FR-012**: System MUST provide notification daemon for system and application notifications
- **FR-013**: System MUST integrate with PipeWire for audio management (matching current audio configuration)
- **FR-014**: System MUST configure wallpaper and visual theme declaratively
- **FR-015**: System MUST support clipboard management compatible with both Wayland and XWayland applications
- **FR-016**: System MUST preserve user's home directory configuration files in backward-compatible way
- **FR-017**: System MUST be testable through dry-build before actual system rebuild
- **FR-018**: System MUST work on all target platforms: Hetzner (x86_64), M1 (aarch64), WSL2
- **FR-019**: System MUST handle multi-monitor setups with declarative positioning
- **FR-020**: System MUST provide lockscreen functionality

### Key Entities

- **Desktop Module Configuration**: Defines Hyprland service, compositor settings, keybindings, display configuration, autostart applications
- **Window Rules**: Defines application-specific window behaviors (floating, tiling, workspace assignment)
- **Keybinding Mappings**: Maps KDE Plasma shortcuts to Hyprland equivalents (workspace switching, window management, application launching)
- **Display Configuration**: Defines monitor resolution, scaling, positioning for different hardware profiles
- **Application Compatibility Layer**: XWayland configuration, Qt/GTK theming, portal integrations
- **System Integration Services**: Status bar (Waybar), launcher (wofi/rofi), notification daemon (mako/dunst), screenshot tool (grim+slurp)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: System rebuild with Hyprland configuration completes without errors in dry-build test
- **SC-002**: User can log in and reach functional desktop within 30 seconds of system boot
- **SC-003**: All 30+ existing applications launch and display correctly in Hyprland
- **SC-004**: 100% of documented keyboard shortcuts from KDE Plasma have working equivalents in Hyprland
- **SC-005**: System configuration contains zero imperative scripts for desktop environment setup (excluding Plasma capture script which will be removed)
- **SC-006**: HiDPI display on M1 Mac automatically configures with 1.75x scaling on first boot
- **SC-007**: Multi-monitor setup (Hetzner via RDP) displays correctly with primary and secondary screens positioned appropriately
- **SC-008**: Screenshot functionality works with existing muscle memory keybindings (95%+ of screenshots captured successfully)
- **SC-009**: System remains stable for 8+ hour work session without compositor crashes or hangs
- **SC-010**: Window management operations (tiling, workspace switching, focus changes) complete in under 100ms (perceived as instant)

## Assumptions

- **ASM-001**: Hyprland's Wayland-native architecture will provide better stability than KDE Plasma's mixed X11/Wayland approach
- **ASM-002**: Most applications are already Wayland-compatible; those that aren't will work through XWayland
- **ASM-003**: Users are comfortable with keyboard-centric workflow (Hyprland is optimized for keyboard shortcuts)
- **ASM-004**: Current KDE Plasma configuration files in home directory can coexist with Hyprland configuration
- **ASM-005**: Waybar will provide adequate system bar functionality to replace KDE Plasma's panel
- **ASM-006**: Wofi or Rofi will provide adequate application launcher functionality to replace KDE's KRunner
- **ASM-007**: grim+slurp combination will provide screenshot functionality equivalent to Spectacle
- **ASM-008**: mako or dunst will provide notification functionality equivalent to KDE's notification system
- **ASM-009**: Migration can be performed incrementally, testing on one system before deploying to all platforms
- **ASM-010**: Existing scripts that depend on KDE-specific APIs (touchegg gestures, plasma-rc2nix) will need alternative solutions or removal

## Out of Scope

- **OOS-001**: Migration of KDE-specific application data or settings (each application will use its own configuration)
- **OOS-002**: Touchscreen or touchpad gesture support (current touchegg configuration is X11-specific)
- **OOS-003**: KDE Connect integration (would need separate Wayland-compatible alternative)
- **OOS-004**: KDE Activities (Hyprland uses workspaces instead, mapping may not be 1:1)
- **OOS-005**: KDE Wallet integration (1Password is already primary secret manager)
- **OOS-006**: Plasma browser integration (Firefox PWAs will work through different mechanism)
- **OOS-007**: SDDM display manager customization (will use minimal SDDM configuration or alternative like GREETD)
- **OOS-008**: Complex window rules for project-based activities (simplified to workspace-based organization)

## Migration Strategy

This migration will follow a phased approach:

**Phase 1**: Create Hyprland module alongside existing KDE Plasma module (no breaking changes)
**Phase 2**: Test Hyprland on single platform (M1 Mac - native Wayland recommended by Asahi Linux)
**Phase 3**: Validate application compatibility and document any issues
**Phase 4**: Migrate keybindings and create mapping documentation
**Phase 5**: Deploy to Hetzner (with RDP testing)
**Phase 6**: Remove KDE Plasma module after successful validation on all platforms
**Phase 7**: Update documentation to reflect Hyprland as primary desktop environment

This allows rollback at any phase if critical issues are discovered.
