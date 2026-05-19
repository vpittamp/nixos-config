# Feature Specification: Unified Bar System with Enhanced Workspace Mode

**Feature Branch**: `057-unified-bar-system`
**Created**: 2025-11-11
**Status**: Draft
**Input**: User description: "create a feature that does the following:  use the same approach/modules that we used for our bottom bar to our topbar, and consider whether we can use the same type of approach with our notification bar.  we want to try to unify teh logic that we use that allows our bars to stay in sync relative to workspace mode and relative to notifications.  here are a few things we want to accomplish.  convert the styline of the top bar and notification center to be consistent with the bottom bar.  try to centralize the appearance config as much as possible such that we can change appearance related items in one place and they are applied consistently.   if possible, keep as much as possible of the meters/guages that we have in our top bar (and that we may have removed from our bottom bar), and move them to the notification center if possible, or if not possible or more appropriate, keep in the top bar.  think of the information that the user wants to see all the time as opposed to the notification bar that will show and hide and won't always be visible.  battery and date/time are examples of something to keep on the top bar, and we want the project status in the top bar as well (or we could consider adding to teh bottom bar).  research projects online that have notification centers/top bars that we an uses as references or have config that we can use in our own.  as a part of this spec, we also want to enhance our \"workspace Mode\" indicator approach.  we want it to look better, be more consistent with our theming and perhaps show a \"preview card\" of the workspaace that is entered.  we also want to enhance the workspace mode functionality to allow for moving workspaces into different positions and different monitors.  consider the key sequence that makes sense and how to provide visual feedback to the user of what operation is happeing before they submit the action.  also revise our notifications to use the icon of the app/workspace that produces the notification including, firefow pwa's and terminal apps.  explore other items, visual and navigation type items, that will create an exceptional user experience that is keyboard focused and provides the visual feedback that the user wnts to see at that moment."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unified Bar Theming (Priority: P1)

As a user, I want all bars (top, bottom, notification center) to share consistent visual styling so that my desktop environment feels cohesive and professional, and theme changes apply everywhere at once.

**Why this priority**: Visual consistency is the foundation that makes all other enhancements meaningful. Without unified theming, users experience cognitive dissonance and the system feels unpolished. This delivers immediate value by making the entire interface feel like a unified product.

**Independent Test**: Can be fully tested by changing a single color/font/spacing value in centralized config and verifying it applies to all three bars (top, bottom, notification center). Delivers a cohesive visual experience immediately.

**Acceptance Scenarios**:

1. **Given** I update the Catppuccin Mocha background color from #1e1e2e to #2e2e3e in central config, **When** I reload all bars, **Then** all three bars (top, bottom, notification center) display the new background color
2. **Given** I change the accent color from blue (#89b4fa) to mauve (#cba6f7), **When** I reload the configuration, **Then** focused workspaces, active indicators, and notification highlights all use mauve
3. **Given** I adjust the font size from 11pt to 12pt, **When** I reload, **Then** all text in all bars scales consistently
4. **Given** I modify border radius from 4px to 8px, **When** I reload, **Then** all buttons, pills, and containers in all bars use 8px rounded corners

---

### User Story 2 - Enhanced Workspace Mode Visual Feedback (Priority: P2)

As a user navigating to workspace 23 via workspace mode, I want to see a preview card showing what's on that workspace (apps, windows, icons) before I press Enter, so I can confirm I'm going to the right place and understand what's there.

**Why this priority**: Workspace mode is already functional but lacks visual confirmation. This enhancement dramatically improves user confidence and navigation speed by showing "what's there" before committing to the switch.

**Independent Test**: Can be tested by entering workspace mode, typing "23", and verifying a preview card appears showing workspace 23's contents (app icons, window count, focused app). Delivers tangible navigation improvement immediately.

**Acceptance Scenarios**:

1. **Given** I press CapsLock to enter workspace mode and type "23", **When** the preview card appears, **Then** I see workspace 23's app icons, window count (e.g., "3 windows"), and the currently focused app name
2. **Given** workspace 50 has YouTube PWA open, **When** I type "50" in workspace mode, **Then** the preview card shows the YouTube icon, "YouTube" label, and workspace status
3. **Given** workspace 5 is empty, **When** I type "5", **Then** the preview card shows "Empty workspace" with a dimmed background
4. **Given** I type "99" (invalid workspace), **When** preview should appear, **Then** preview card shows "Invalid workspace" or remains hidden
5. **Given** the preview card is showing for workspace 23, **When** I press Escape, **Then** the card dismisses and I stay on current workspace

---

### User Story 3 - Workspace Move Operations with Visual Feedback (Priority: P3)

As a user, I want to move workspaces between monitors or reorder them using keyboard shortcuts with clear visual feedback, so I can organize my workspace layout without using a mouse.

**Why this priority**: Builds on enhanced workspace mode by adding power-user functionality. Less critical than P1/P2 but delivers significant productivity gains for advanced users managing multi-monitor setups.

**Independent Test**: Can be tested by pressing workspace mode + modifier key (e.g., Alt) to enter "move mode", seeing visual indicators change (yellow border, arrow icons), then executing a workspace move. Delivers workspace management power without needing P1/P2.

**Acceptance Scenarios**:

1. **Given** I'm on workspace 5, **When** I press CapsLock+Alt and type "2", **Then** I see visual feedback showing "Move workspace 5 → position 2" and arrows indicating the swap direction
2. **Given** I'm viewing the move operation preview "WS 5 → WS 2", **When** I press Enter, **Then** workspace 5 content swaps with workspace 2 content and I land on the new position
3. **Given** I'm on workspace 10 on monitor 1, **When** I press CapsLock+Shift and type "3" (monitor 3's range), **Then** I see preview "Move WS 10 → Monitor 3" with monitor labels highlighted
4. **Given** I see the move preview, **When** I press Escape, **Then** the move is cancelled, visual feedback clears, and workspace stays in original position

---

### User Story 4 - App-Aware Notification Icons (Priority: P4)

As a user receiving notifications, I want each notification to display the icon of the app or workspace that generated it (Firefox PWA, terminal apps, etc.) so I can quickly identify the source at a glance.

**Why this priority**: Enhances notification usability significantly but depends on notification center UI overhaul (P1). Lower priority because notifications are already functional, this is a polish enhancement.

**Independent Test**: Can be tested by triggering notifications from different sources (YouTube PWA, VS Code, terminal) and verifying each shows the correct app icon. Delivers improved notification clarity immediately.

**Acceptance Scenarios**:

1. **Given** YouTube PWA on workspace 50 sends a notification, **When** notification appears, **Then** it displays the YouTube icon from the PWA's icon path
2. **Given** a terminal app (Ghostty) running htop sends a notification, **When** notification appears, **Then** it displays the Ghostty terminal icon
3. **Given** VS Code on workspace 2 sends a build error notification, **When** notification appears, **Then** it displays the VS Code icon
4. **Given** notification is from an app without a known icon, **When** notification appears, **Then** it displays a generic workspace icon or fallback placeholder

---

### User Story 5 - Persistent vs. Transient Information Layout (Priority: P2)

As a user, I want persistent information (battery, date/time, current project) always visible in the top bar, and less critical information (CPU/memory meters, network stats) available in the notification center, so my top bar stays uncluttered while important info is always visible.

**Why this priority**: Directly impacts daily usability by keeping critical info visible while reducing clutter. Higher priority than advanced features because it affects every user interaction.

**Independent Test**: Can be tested by verifying battery, time, and project status are always visible in top bar, while opening notification center reveals CPU/memory/network gauges. Delivers better information hierarchy immediately.

**Acceptance Scenarios**:

1. **Given** I'm looking at the top bar, **When** I observe what's visible, **Then** I see battery percentage, current time, and active project name (e.g., "nixos") always displayed
2. **Given** I toggle the notification center open, **When** I view the control panel, **Then** I see CPU usage gauge, memory usage gauge, network upload/download rates, and disk usage
3. **Given** the notification center is closed, **When** I look at the top bar, **Then** CPU/memory/network info is NOT visible (decluttered)
4. **Given** battery drops below 20%, **When** I look at the top bar, **Then** battery indicator changes to warning color (e.g., red) without needing to open notification center

---

### User Story 6 - Bottom Bar Workspace Mode Integration (Priority: P2)

As a user, I want the bottom bar workspace buttons to stay synchronized with workspace mode operations (showing pending workspace, move operations, preview state) so both bars provide consistent visual feedback during navigation.

**Why this priority**: Essential for unified experience - if workspace mode shows one thing and bottom bar shows another, users get confused. Must work alongside P2 (enhanced workspace mode).

**Independent Test**: Can be tested by entering workspace mode, typing a workspace number, and verifying both the workspace mode indicator (top bar) and bottom bar workspace buttons highlight the pending target. Delivers consistency immediately.

**Acceptance Scenarios**:

1. **Given** I enter workspace mode and type "23", **When** I look at both bars, **Then** the top bar shows "→ WS 23" indicator AND the bottom bar workspace 23 button highlights in yellow (pending state)
2. **Given** I'm in move mode moving WS 5 → WS 2, **When** I look at the bottom bar, **Then** workspace 5 button shows "source" indicator and workspace 2 button shows "target" indicator
3. **Given** workspace mode is active, **When** I press Escape, **Then** both top bar indicator and bottom bar pending highlights clear simultaneously
4. **Given** I complete a workspace switch via workspace mode, **When** I land on the new workspace, **Then** bottom bar focused indicator updates to match the new workspace within 50ms

---

### Edge Cases

- **What happens when workspace preview card would overflow screen boundaries?** Card should reposition to stay on-screen (e.g., if typing "70", card appears anchored to left instead of center)
- **How does system handle workspace move when target position is occupied?** Visual preview shows "swap" operation with bidirectional arrows, making it clear workspaces will exchange positions
- **What happens if notification icon path is invalid or missing?** Fall back to generic workspace icon or app category icon (browser, terminal, editor)
- **How does centralized theming handle monitor-specific overrides?** Monitor-specific settings (if needed) should override centralized values with clear precedence documented
- **What happens when user rapidly types in workspace mode (>10 digits/second)?** System debounces input (50ms) and updates preview smoothly without lag or race conditions
- **How does bottom bar handle workspace buttons when 70 workspaces exist?** Only show workspaces with windows + current workspace, hide empty workspaces to avoid clutter (existing Feature 058 behavior)
- **What happens when workspace move targets invalid destination?** Preview shows "Invalid target" and Enter key is disabled, must press Escape to cancel
- **How does notification center handle SwayNC widget state when center is open?** Widget shows "control center open" state (distinct from has-notifications state), click closes instead of opens

## Requirements *(mandatory)*

### Functional Requirements

#### Unified Theming & Appearance

- **FR-001**: System MUST provide a centralized appearance configuration file that defines colors, fonts, spacing, border radius, and opacity values
- **FR-002**: Top bar, bottom bar, and notification center MUST read appearance values from the same centralized configuration
- **FR-003**: Centralized config MUST support Catppuccin Mocha color palette variables ($base, $blue, $mauve, $teal, $red, $yellow, etc.)
- **FR-004**: Changes to centralized appearance config MUST propagate to all bars on reload without requiring separate edits

#### Top Bar Layout & Content

- **FR-005**: Top bar MUST always display battery status (percentage + charging indicator)
- **FR-006**: Top bar MUST always display current date and time (format: "Mon Nov 11 1:23 PM")
- **FR-007**: Top bar MUST always display current i3pm project name (e.g., "nixos", "global")
- **FR-008**: Top bar MUST display workspace mode indicator when active (e.g., "→ WS 23", "⇒ WS 5→2")
- **FR-009**: Top bar MUST use consistent styling with bottom bar (matching colors, fonts, button shapes)

#### Bottom Bar Enhancements

- **FR-010**: Bottom bar workspace buttons MUST highlight pending workspace when workspace mode is active (yellow pending state from Feature 058)
- **FR-011**: Bottom bar MUST show workspace move operation indicators (source/target highlights) when move mode is active
- **FR-012**: Bottom bar MUST synchronize urgent/focused/visible/pending states with workspace mode operations within 50ms
- **FR-013**: Bottom bar MUST support showing/hiding SwayNC notification count widget (already implemented in Feature 058)

#### Notification Center Integration

- **FR-014**: Notification center MUST display CPU usage gauge with percentage and visual bar
- **FR-015**: Notification center MUST display memory usage gauge with used/total and visual bar
- **FR-016**: Notification center MUST display network upload/download rates (KB/s or MB/s)
- **FR-017**: Notification center MUST display disk usage for root filesystem
- **FR-018**: Notification center MUST use consistent Catppuccin Mocha styling matching top/bottom bars
- **FR-019**: Notification center MUST support Do Not Disturb toggle with visual state indicator
- **FR-020**: System MUST integrate SwayNC's existing customizable widgets (Title, DND, Notifications, Label, MPRIS, Volume, Backlight)

#### Enhanced Workspace Mode

- **FR-021**: System MUST display workspace preview card when user types workspace number in workspace mode
- **FR-022**: Preview card MUST show workspace app icons, window count, and focused app name
- **FR-023**: Preview card MUST indicate empty workspaces with dimmed "Empty workspace" message
- **FR-024**: Preview card MUST use Catppuccin Mocha styling consistent with bars
- **FR-025**: Preview card MUST appear within 50ms of typing final digit
- **FR-026**: Preview card MUST dismiss on Escape keypress or workspace switch completion

#### Workspace Move Operations

- **FR-027**: System MUST support workspace reordering via keyboard shortcut (workspace mode + modifier key, e.g., CapsLock+Alt)
- **FR-028**: System MUST support moving workspace to different monitor via keyboard shortcut (workspace mode + Shift)
- **FR-029**: System MUST display visual feedback for move operations showing source and target positions
- **FR-030**: Move operation preview MUST show directional arrows indicating swap or monitor transfer
- **FR-031**: Move operations MUST execute on Enter keypress and cancel on Escape keypress
- **FR-032**: System MUST update workspace-to-monitor assignments after move operations (Feature 001 integration)

#### App-Aware Notifications

- **FR-033**: Notifications MUST display app icon from Firefox PWA icon path when notification originates from PWA
- **FR-034**: Notifications MUST display terminal app icon when notification originates from terminal (Ghostty, Alacritty)
- **FR-035**: Notifications MUST display VS Code icon when notification originates from editor
- **FR-036**: Notifications MUST fall back to generic workspace icon when app icon path is invalid or missing
- **FR-037**: System MUST read app icon paths from i3pm app registry (application-registry.json)

#### Synchronization & State Management

- **FR-038**: Workspace mode state MUST be shared between top bar indicator and bottom bar workspace buttons via IPC
- **FR-039**: Bottom bar MUST subscribe to workspace mode events from i3pm daemon (workspace_mode_digit, workspace_mode_execute, workspace_mode_cancel)
- **FR-040**: Notification center MUST update CPU/memory/network gauges every 2 seconds via polling or D-Bus subscriptions
- **FR-041**: All bars MUST use the same Python-based event-driven architecture as workspace_panel.py (Feature 058)

### Key Entities

- **CentralizedTheme**: Represents unified appearance configuration with color palette (Catppuccin Mocha), font definitions, spacing constants, border radius, opacity values. Consumed by top bar, bottom bar, notification center.

- **WorkspacePreviewCard**: Represents preview overlay showing workspace contents with app icons list, window count, focused app name, empty/invalid state indicator, Catppuccin styling.

- **WorkspaceMoveOperation**: Represents pending workspace move with source workspace ID, target workspace/monitor ID, operation type (swap, transfer), visual feedback state (arrows, highlights).

- **NotificationMetadata**: Represents notification with app icon path, app name, workspace origin, urgency level, timestamp. Links to i3pm app registry for icon resolution.

- **TopBarLayout**: Represents persistent information layout with battery widget, date/time widget, project status widget, workspace mode indicator widget.

- **NotificationCenterLayout**: Represents transient information layout with CPU gauge, memory gauge, network stats, disk usage, SwayNC widgets (DND, volume, backlight, MPRIS).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can change a single theme value and see it apply to all three bars (top, bottom, notification center) within 3 seconds of reload
- **SC-002**: Workspace preview card appears within 50ms of typing final workspace digit in workspace mode
- **SC-003**: Bottom bar workspace button pending highlight synchronizes with workspace mode indicator within 50ms
- **SC-004**: Workspace move operations complete within 200ms after pressing Enter
- **SC-005**: Notifications from PWAs display correct app icon in 95% of cases (5% fallback to generic icon)
- **SC-006**: CPU/memory/network gauges in notification center update every 2 seconds with less than 100ms jitter
- **SC-007**: Users can navigate to any workspace (1-70) using workspace mode with preview card confirmation in under 2 seconds total time
- **SC-008**: Users can reorganize workspaces across monitors without mouse input in under 5 seconds per move operation
- **SC-009**: Top bar remains uncluttered (max 4-5 widgets) while notification center provides access to 6+ metrics/gauges
- **SC-010**: All bar configurations use shared codebase/modules with 80% code reuse between bars (centralized theme, shared widgets, common event handlers)

## Assumptions

1. **Python-based architecture**: Assumes all bars will use Python 3.11+ with i3ipc.aio for async event handling, matching workspace_panel.py's proven architecture
2. **Eww for overlays**: Assumes workspace preview card will be implemented as Eww overlay widget (like workspace buttons), not native Sway window
3. **SwayNC preservation**: Assumes SwayNC remains the notification daemon, we're enhancing its control center UI rather than replacing it
4. **Catppuccin Mocha**: Assumes Catppuccin Mocha color palette is the canonical theme, other themes are out of scope
5. **Workspace numbering**: Assumes workspace IDs remain 1-70, workspace move operations don't change IDs, only reorder assignments
6. **Monitor roles**: Assumes Feature 001's monitor role system (primary/secondary/tertiary) is used for workspace-to-monitor moves
7. **Icon availability**: Assumes app icons are available via i3pm app registry; if registry lacks icon, fallback is acceptable
8. **Single user**: Assumes single-user Sway session, multi-user concurrent sessions are out of scope

## Research References

### AGS (Aylur's GTK Shell)
- **URL**: https://aylur.github.io/ags-docs/
- **Relevance**: Modern GTK-based shell framework with notification center widgets, bars, and control panels. Uses JavaScript for configuration, demonstrates best practices for notification + bar integration.
- **Key Features**: Dynamic GTK windows, built-in notification service, Hyprland IPC integration, widget composition patterns
- **Applicable Patterns**: Notification center layout (combining notifications + system metrics), widget reusability (shared components across bars), JavaScript-based declarative UI (could inspire Nix DSL patterns)

### SwayNC (Sway Notification Center)
- **URL**: https://github.com/ErikReider/SwayNotificationCenter
- **Relevance**: Current notification daemon in use. Provides GTK control center with customizable widgets (DND, Volume, Backlight, MPRIS). Supports CSS theming.
- **Key Features**: Grouped notifications, keyboard shortcuts, notification body markup, album art, DND mode, custom CSS, widget extensibility
- **Applicable Patterns**: Widget system (Title, DND toggle, Notifications panel, Menubar, Button grid, Volume/Backlight sliders), Catppuccin theme examples, Waybar integration patterns (notification count indicators)
- **Integration Approach**: Extend SwayNC's control center to include CPU/memory/network gauges, apply unified Catppuccin styling via shared SCSS

### n7n-AGS-Shell
- **URL**: https://github.com/nine7nine/n7n-AGS-Shell
- **Relevance**: Real-world AGS implementation with simplified notification/date menu widgets, demonstrates practical bar + notification center integration
- **Key Features**: Refactored app-bar to TopPanel using widgets, central config object pattern, AGS 1.x examples
- **Applicable Patterns**: Central config pattern (single source for theming), widget composition (building complex UIs from simple components)

### Eww Documentation & Examples
- **URL**: https://elkowar.github.io/eww/
- **Relevance**: Current bottom bar implementation uses Eww. Documentation provides widget patterns, overlay techniques, defpoll/deflisten patterns.
- **Key Features**: Yuck DSL for UI, CSS for styling, deflisten for event streams, overlay widget for layered UI
- **Applicable Patterns**: Overlay widgets for preview cards, deflisten for real-time workspace updates (already used in Feature 058), CSS variable usage for theming

## Constraints

- **Technology Stack**: Must use existing stack (Eww for bars/overlays, SwayNC for notifications, Python 3.11+ for event handling, Nix for config management)
- **Backward Compatibility**: Must preserve existing workspace mode functionality from Feature 042 and Feature 058 (CapsLock trigger, digit typing, pending highlight)
- **Performance**: Workspace mode operations (preview, move) must complete within user perception threshold (50-200ms)
- **No Breaking Changes**: Must not break existing i3pm daemon, workspace-to-monitor assignments (Feature 001), or scratchpad functionality (Feature 062)
- **Monitor Support**: Must work on both M1 Mac (1 monitor: eDP-1) and Hetzner Cloud (3 monitors: HEADLESS-1/2/3)
- **Icon Resolution**: Limited to icons available in i3pm app registry, Nerd Fonts, and XDG icon themes (Papirus, Breeze)

## Out of Scope

- **Custom notification daemon**: Replacing SwayNC with custom implementation (e.g., "End" Haskell daemon)
- **Thumbnail-based previews**: Showing actual window screenshots in preview cards (only app icons + metadata)
- **Workspace renaming**: Changing workspace names or IDs, only reordering/moving
- **Multi-user sessions**: Synchronizing bars across multiple concurrent Sway sessions
- **Theme designer UI**: GUI for editing centralized theme config (manual Nix editing only)
- **Notification history database**: Persistent storage of notification history (SwayNC provides transient history)
- **Voice control**: Audio-based workspace navigation
- **Touchscreen support**: Touch gestures for workspace moves (keyboard only)

## Dependencies

- **Feature 001**: Declarative workspace-to-monitor assignment (workspace move operations must update monitor assignments)
- **Feature 042**: Event-driven workspace mode navigation (keyboard shortcuts, digit accumulation, Enter/Escape handling)
- **Feature 058**: Workspace mode visual feedback (pending highlight, bottom bar integration, workspace_panel.py architecture)
- **Feature 062**: Project-scoped scratchpad terminal (project status display in top bar)
- **SwayNC**: Notification daemon with GTK control center (notification list, DND toggle, existing widgets)
- **i3pm daemon**: Event bus for workspace mode state (workspace_mode_digit, workspace_mode_execute, workspace_mode_cancel events)
- **Catppuccin Mocha**: Color palette for unified theming ($base, $blue, $mauve, $teal, $red, $yellow, etc.)

## Related Features

- **Feature 047**: Dynamic Sway config management (window rules, appearance.json) - could extend to centralized bar theming
- **Feature 049**: Auto workspace-to-monitor redistribution (integrates with workspace move operations)
- **Feature 053**: Event-driven workspace assignment (notification icon resolution from app registry)

## Implementation Notes

1. **Centralized Theme Architecture**: Consider creating `home-modules/desktop/shared-theme.nix` exporting Catppuccin variables, then importing into eww-workspace-bar.nix, swaybar.nix, and SwayNC CSS
2. **Preview Card Widget**: Implement as Eww overlay window (like workspace buttons) anchored to center screen, triggered by workspace mode events
3. **Workspace Move IPC**: Extend i3pm daemon with `workspace_mode_move` event type, publish to workspace_panel.py for bottom bar visual feedback
4. **Notification Icon Lookup**: Query i3pm application-registry.json for app_name → icon_path mapping, pass to SwayNC via D-Bus hints
5. **Top Bar Migration**: Migrate swaybar.nix from shell script status generator to Python-based approach matching workspace_panel.py (async D-Bus, i3ipc.aio)
6. **SwayNC Widget Extension**: Add custom widgets to SwayNC config.json (CPU gauge, memory gauge, network stats) using Label + custom scripts
7. **State Synchronization**: Use i3pm daemon as single source of truth, all bars subscribe to events rather than polling workspace state
8. **Testing Strategy**: Unit tests for theme variable resolution, integration tests for workspace mode + bottom bar sync, visual tests for preview card appearance
