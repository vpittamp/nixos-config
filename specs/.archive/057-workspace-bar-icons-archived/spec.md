# Feature Specification: Unified Workspace Bar Icon System

**Feature Branch**: `057-workspace-bar-icons`
**Created**: 2025-11-10
**Status**: Draft
**Input**: User description: "create new feature for our sway bar. currently each workspace is not reliably rendering the desired icon. currently, we use walker launcher that uses configured directories in @home-modules/desktop/walker.nix and follows a order of precedence that results in the icon that shows in walker launcher. we want the icons that we see in walker launcher and the icons rendered in our sway bar to be the same. we also want high quality icon display and for it to look really good when rendered. research how wakler uses the directories and precedence to determine what icons to display. also, be mindful of system icons that are used such as for btop, lazygit, etc. we need to make sure our solution addresses our firefox pwa apps, regular apps, and terminal apps which we use ghostty to launch such as lazygit, yazi. also consider reviewing this example repo which appears to have well rendered apps using eww. consider revising our existing solution to get the desired result, but use a different solution if needed. also make the bar look better such that it all goes together in a unified way, and each button has an icon and the workspace number, and it renders in a wawy that looks great;"

## User Scenarios & Testing

### User Story 1 - Icon Consistency Between Walker and Workspace Bar (Priority: P1)

As a user, when I launch an application from Walker, I want to see the exact same icon displayed in the workspace bar, so that I can quickly identify which workspace contains which application without visual confusion.

**Why this priority**: This is the core issue - inconsistent icons between launcher and bar cause cognitive friction and reduce the effectiveness of the visual workspace navigation system. Users currently see one icon in Walker and a different (or missing) icon in the bar, making workspace identification unreliable.

**Independent Test**: Can be fully tested by launching any application via Walker and immediately verifying the workspace bar shows the identical icon. Success delivers immediate value by making workspace visual identification reliable.

**Acceptance Scenarios**:

1. **Given** Firefox is not running, **When** user launches Firefox via Walker (which shows a specific Firefox icon), **Then** the workspace bar displays that same Firefox icon on the workspace containing Firefox
2. **Given** multiple apps are running across different workspaces, **When** user views the workspace bar, **Then** each workspace shows the same icon that Walker showed when the app was launched
3. **Given** a PWA application (e.g., YouTube) is launched, **When** user checks the workspace bar, **Then** the PWA's custom icon from the PWA registry appears in the workspace bar (same as Walker)

---

### User Story 2 - Terminal Application Icon Support (Priority: P2)

As a user launching terminal applications like lazygit or yazi through Ghostty, I want to see distinct, recognizable icons for each terminal application in the workspace bar, so that I can differentiate between multiple terminal sessions running different tools.

**Why this priority**: Terminal applications are frequently used but share the same base terminal emulator (Ghostty). Without distinct icons, users cannot distinguish between a workspace running lazygit vs yazi vs btop, reducing the value of the icon-based navigation system.

**Independent Test**: Can be tested by launching 3 different terminal apps (e.g., lazygit, yazi, btop) in separate workspaces and verifying each workspace shows a unique icon matching the app-specific icon defined in the application registry.

**Acceptance Scenarios**:

1. **Given** lazygit is launched via Ghostty in workspace 7, **When** user views the workspace bar, **Then** workspace 7 shows the lazygit icon (not the generic Ghostty icon)
2. **Given** yazi is launched via Ghostty in workspace 8, **When** user views the workspace bar, **Then** workspace 8 shows the yazi icon
3. **Given** btop is launched in workspace 9, **When** user views the workspace bar, **Then** workspace 9 shows the btop icon with high quality rendering

---

### User Story 3 - High Quality Icon Rendering (Priority: P3)

As a user, I want all workspace bar icons to be crisp, properly sized, and visually appealing at the bar's display size, so that the workspace bar looks polished and professional.

**Why this priority**: After achieving icon consistency (P1) and terminal app support (P2), visual polish ensures the feature feels complete and refined. Poor quality icons (pixelated, wrong size, misaligned) detract from the overall user experience even if they're technically correct.

**Independent Test**: Can be tested visually by inspecting each icon in the workspace bar at runtime, verifying crisp rendering without pixelation, proper sizing (20×20px target), and consistent visual styling across all icons.

**Acceptance Scenarios**:

1. **Given** icons are displayed in the workspace bar at 20×20 pixels, **When** user views the bar on a high DPI display, **Then** icons appear sharp and crisp without pixelation or blur
2. **Given** mixed icon sources (SVG, PNG, system icons), **When** all are displayed in the workspace bar, **Then** all icons have consistent visual weight and styling (no icons appearing too large/small/bold/thin relative to others)
3. **Given** icons are loaded from the theme system, **When** icons are missing or unavailable, **Then** the system falls back gracefully to a single-letter symbol that is clearly readable
4. **Given** icons with transparent backgrounds (like Firefox, VS Code), **When** displayed in the workspace bar, **Then** icons integrate seamlessly with the Catppuccin Mocha background colors without visible rectangular backgrounds or color conflicts

---

### User Story 4 - Unified Visual Design with Workspace Numbers (Priority: P3)

As a user, I want each workspace button to display both the icon and workspace number in a cohesive, aesthetically pleasing design, so that the workspace bar functions as both a beautiful and functional navigation tool.

**Why this priority**: Once icons are consistent and high quality, the overall visual design ensures the bar integrates well with the desktop environment and provides both visual (icon) and numeric (workspace number) navigation cues.

**Independent Test**: Can be tested by viewing the workspace bar with various combinations of populated/empty workspaces and verifying the layout, spacing, colors, and typography create a unified, polished appearance.

**Acceptance Scenarios**:

1. **Given** workspace bar is visible, **When** user views any workspace button, **Then** each button displays the workspace number and icon in a visually balanced layout (icon and number both clearly visible)
2. **Given** focused, visible, and empty workspaces exist, **When** user views the bar, **Then** visual states (colors, borders, opacity) clearly distinguish between focused/visible/empty workspaces
3. **Given** multiple workspaces are populated, **When** user views the entire bar, **Then** the design feels cohesive with consistent spacing, rounded corners, smooth transitions, and proper use of the Catppuccin Mocha color palette

---

### Edge Cases

- What happens when an icon cannot be found via the icon theme lookup, desktop file search, or app/PWA registry? (System should fall back to first letter of app name as a styled symbol)
- What happens when multiple windows from different apps are on the same workspace? (System should show icon for the focused/topmost window, falling back to first visible window)
- What happens when a terminal app is launched with custom parameters that don't match the registry? (System should fall back to Ghostty icon or first letter of window title)
- What happens when the icon theme is changed or icons are missing after a system update? (System should gracefully degrade to fallback symbols without breaking the bar)
- What happens when a PWA icon file is deleted or moved? (System should fall back to first letter of PWA name)
- What happens when a PWA icon has a solid white/colored background that clashes with the workspace bar theme? (User should replace the icon with a transparent background version in `/etc/nixos/assets/pwa-icons/` and rebuild NixOS)

## Requirements

### Functional Requirements

- **FR-001**: System MUST use identical icon lookup logic and precedence order for both Walker launcher and workspace bar icon display
- **FR-002**: System MUST prioritize icon sources in this order: (1) Application registry (`application-registry.json`), (2) PWA registry (`pwa-registry.json`), (3) Desktop file by ID, (4) Desktop file by StartupWMClass, (5) Icon theme lookup via `getIconPath()`
- **FR-003**: System MUST resolve terminal applications (launched via Ghostty) to their specific app icon (e.g., lazygit, yazi, btop) rather than the generic Ghostty terminal icon
- **FR-004**: System MUST support multiple icon formats (SVG, PNG, XPM) with preference for SVG when available for scalability
- **FR-005**: System MUST render icons at the configured size (20×20 pixels by default) with proper scaling to maintain aspect ratio and sharpness
- **FR-006**: System MUST fall back gracefully when icons are unavailable by displaying the first uppercase letter of the application name as a styled symbol
- **FR-007**: System MUST search for icons in these directories with this precedence: (1) `~/.local/share/icons`, (2) `~/.icons`, (3) `/usr/share/icons` (theme-based), (4) `/usr/share/pixmaps`
- **FR-008**: System MUST cache resolved icon paths to avoid redundant filesystem searches during runtime
- **FR-009**: Workspace bar buttons MUST display both the workspace number and application icon in a unified visual design
- **FR-010**: System MUST apply the Catppuccin Mocha color palette consistently across all workspace bar states (focused, visible, empty, urgent)
- **FR-011**: System MUST ensure workspace bar service has identical `XDG_DATA_DIRS` configuration as Walker/Elephant service to access the same icon themes and application directories
- **FR-012**: System MUST detect window changes and update workspace icons in real-time (<500ms latency)
- **FR-013**: Icon backgrounds SHOULD integrate well with the Catppuccin Mocha workspace bar theme. Transparent/no backgrounds (like Firefox, VS Code) are preferred, but intentional colored backgrounds that complement the theme (like adi1090x/widgets examples with GitHub dark gray #24292E, Reddit orange #E46231) are acceptable. Avoid unintentional white/default backgrounds that clash with the theme

### Key Entities

- **Icon Index**: Represents the in-memory mapping from application identifiers (app_id, window_class, window_instance) to resolved icon paths and display names. Populated from app registry, PWA registry, and desktop files.
- **Workspace Button**: Represents a single workspace UI element in the bar, containing the workspace number, icon path, icon fallback symbol, focused/visible/urgent state, and application name for tooltip.
- **Icon Resolution Cascade**: Represents the ordered lookup chain starting from application registry, progressing through PWA registry and desktop files, then falling back to icon theme lookup and finally to single-letter symbols.
- **Application Registry**: Centralized JSON mapping of application names to metadata including icon names, expected window classes, display names, and workspace preferences.
- **PWA Registry**: JSON mapping of PWA ULIDs to metadata including custom icon paths (typically PNG files in `/etc/nixos/assets/pwa-icons/`).

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% of applications visible in Walker show the same icon in the workspace bar (zero icon inconsistencies between launcher and bar)
- **SC-002**: Terminal applications launched via Ghostty display their specific application icon (lazygit, yazi, btop) rather than the generic terminal icon in at least 95% of cases
- **SC-003**: Icon rendering quality achieves crisp, non-pixelated display on both standard and high DPI displays (subjective visual inspection with zero pixelation observed)
- **SC-004**: Workspace bar updates icons within 500ms of window focus changes or new window creation (measured from IPC event to icon display)
- **SC-005**: Icon lookup latency remains under 50ms for cached icons and under 200ms for initial icon resolution (measured per icon resolution operation)
- **SC-006**: Users can identify the application running in a workspace by icon alone without needing to read the tooltip in at least 90% of cases (qualitative user testing)
- **SC-007**: Workspace bar maintains consistent visual aesthetics across all states with proper spacing, alignment, and color application (passes visual design review checklist)
- **SC-008**: Icon backgrounds integrate well with workspace bar theme (90% of displayed icons either have transparent backgrounds OR intentional colored backgrounds that complement the Catppuccin Mocha palette - no unintentional white/default backgrounds that clash)

## Assumptions

1. **Icon Theme Availability**: We assume icon themes (Papirus, Breeze, hicolor) are installed and accessible via the configured `XDG_DATA_DIRS`. If themes are missing, the system will still function using fallback symbols.

2. **Application Registry Completeness**: We assume the application registry (`application-registry.json`) contains accurate icon names for all curated applications. If icons are missing or incorrect, the system will fall back to desktop file icons or theme lookup.

3. **PWA Icon Storage**: We assume PWA icons are stored as PNG files in `/etc/nixos/assets/pwa-icons/` with filenames matching the PWA names. This is the current convention established in the PWA registry.

4. **Terminal App Detection**: We assume terminal applications launched via Ghostty can be identified by matching their window instance or title against the application registry. For apps not in the registry, Ghostty's generic icon will be used.

5. **Icon Size Target**: We assume 20×20 pixels is the optimal icon size for the current workspace bar design. This can be adjusted if visual testing suggests a different size improves readability or aesthetics.

6. **XDG Standards Compliance**: We assume icon theme lookup via `getIconPath()` (from PyXDG library) follows XDG Icon Theme Specification correctly for finding themed icons.

7. **Real-time Updates**: We assume i3ipc events (`workspace`, `window`, `binding`) fire reliably when window state changes occur, enabling real-time icon updates without polling.

8. **Eww Rendering Capabilities**: We assume Eww (the bar widget system) can render image widgets at the specified size with proper scaling for both SVG and PNG formats.

## Dependencies

- **Python 3.11+**: Required for the workspace panel script that generates icon data
- **i3ipc Python library**: Required for Sway IPC communication to detect workspace and window changes
- **PyXDG**: Required for XDG-compliant icon theme lookup via `getIconPath()`
- **Eww widget system**: Required for rendering the workspace bar with icon support
- **Application Registry**: Must be kept in sync with actual installed applications and their icon names
- **PWA Registry**: Must be kept in sync with installed PWAs and their icon file paths
- **Icon Themes**: At minimum, the `hicolor` fallback theme should be available; enhanced experience with Papirus or Breeze themes

## Out of Scope

- Changing the workspace bar widget system to a different technology (e.g., migrating from Eww to Waybar or another bar system)
- Adding animated icons or transitions between icon states
- Customizing icon colors or applying filters/effects to icons
- Supporting icon customization via user-provided theme overrides beyond standard XDG icon themes
- Adding workspace previews or thumbnails of window contents
- Implementing icon badges or notification indicators on workspace icons
- Supporting multi-line workspace buttons or alternative layout orientations (vertical bar)
