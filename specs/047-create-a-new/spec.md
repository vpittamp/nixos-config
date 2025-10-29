# Feature Specification: Dynamic Sway Configuration Management Architecture

**Feature Branch**: `047-create-a-new`
**Created**: 2025-10-29
**Status**: Draft
**Input**: User description: "create a new feature that enhances/improves our sway configuration (hetzner-sway); we want to have the sway configuration to be as dynamic as possible but maintain stability and reliability. currently we maintain much of our logic in our python module, which contains logic for projects, window matching, workspaces to appliction mapping, etc. we should explore whether we should still use sway's config that we could configure via nix module that would output sway config, regular sway config, to customize other options such as keybindings, certain window rules (such as which windows should floating), etc. or whether we should maintain all logic in our python modules instead. we would prefer a strategy that doesn't require a full rebuild, but we also want a system that integrates well with our nixos / home-manager setup."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hot-Reloadable Configuration Changes (Priority: P1)

As a power user who frequently experiments with keybindings and window rules, I need to modify Sway configuration settings without rebuilding the entire NixOS system so I can iterate quickly on workflow improvements and test changes in real-time without downtime.

**Why this priority**: Core value proposition - eliminates rebuild friction which currently blocks rapid configuration iteration. This is the primary pain point preventing dynamic configuration management. Delivers immediate value by reducing configuration change cycle from minutes (rebuild) to seconds (reload).

**Independent Test**: Can be fully tested by modifying a keybinding in the configuration system, running a reload command, and verifying the new keybinding works immediately without running `nixos-rebuild switch` or restarting Sway session. Delivers standalone value of instant configuration updates.

**Acceptance Scenarios**:

1. **Given** user modifies a keybinding configuration, **When** user runs reload command, **Then** new keybinding becomes active within 2 seconds without Sway restart
2. **Given** user changes floating window rule, **When** user triggers configuration reload, **Then** newly launched windows follow new rule immediately
3. **Given** user updates workspace-to-output assignment, **When** reload completes, **Then** workspaces redistribute to new monitor assignments within 500ms
4. **Given** configuration has syntax error, **When** user attempts reload, **Then** system displays error message and retains previous valid configuration
5. **Given** user modifies multiple settings simultaneously, **When** reload is triggered, **Then** all changes take effect atomically (no partial state)

---

### User Story 2 - Clear Configuration Responsibility Boundaries (Priority: P1)

As a system administrator managing both static system configuration and dynamic runtime behavior, I need a clear separation between what belongs in Nix modules (static, declarative settings) versus what belongs in Python modules (dynamic, runtime logic) so I can understand where to make changes and maintain consistency across configurations.

**Why this priority**: Architectural foundation - prevents configuration drift and maintains system reliability. Without clear boundaries, settings become duplicated or contradictory across Nix and Python, leading to debugging nightmares. Essential for long-term maintainability.

**Independent Test**: Can be tested by reviewing configuration files and documentation to verify each configuration category (keybindings, window rules, project management, workspace assignments) has a clearly documented owner (Nix or Python) with no overlap or ambiguity. Validates architectural clarity without runtime testing.

**Acceptance Scenarios**:

1. **Given** user wants to change a keybinding, **When** user checks configuration documentation, **Then** documentation clearly specifies whether to edit Nix module or Python config
2. **Given** user wants to add window floating rule, **When** user reviews architecture documentation, **Then** documentation explains rationale for why this belongs in Nix vs Python
3. **Given** system has both Nix and Python configurations active, **When** conflicting settings exist (e.g., same keybinding in both), **Then** system uses documented precedence rule and logs warning
4. **Given** user adds new project via Python module, **When** project-specific window rules are needed, **Then** documentation clarifies which module handles project-scoped rules vs global rules
5. **Given** both configurations are present, **When** user inspects runtime state, **Then** system provides diagnostic command showing which settings came from Nix vs Python

---

### User Story 3 - Project-Aware Dynamic Window Rules (Priority: P1)

As a developer who switches between multiple projects with different window management needs, I need window rules (floating, workspace assignments, sizing) that adapt based on active project context so that application windows behave appropriately for each project without manual reconfiguration.

**Why this priority**: Extends existing project management system with context-aware window behavior. Critical for project-scoped workflow productivity. Leverages existing i3pm architecture to provide differentiated window behavior per project.

**Independent Test**: Can be tested by defining project-specific window rules (e.g., floating calculator for "nixos" project but tiled for "data-science" project), switching between projects, launching the application, and verifying window rule matches active project context.

**Acceptance Scenarios**:

1. **Given** project "nixos" has rule "float calculator", **When** user switches to nixos project and launches calculator, **Then** calculator window opens floating
2. **Given** project "data-science" has rule "tile calculator on workspace 4", **When** user switches to data-science and launches calculator, **Then** calculator opens tiled on workspace 4
3. **Given** no project is active (global mode), **When** user launches application, **Then** default window rules apply from base Sway configuration
4. **Given** project-specific rule conflicts with global rule, **When** project is active, **Then** project rule takes precedence over global rule
5. **Given** user updates project window rules, **When** user triggers reload, **Then** new rules apply to subsequently launched windows without Sway restart

---

### User Story 4 - Version-Controlled Configuration with Rollback (Priority: P2)

As a cautious administrator who values system stability, I need configuration changes to be version-controlled and easily reversible so I can experiment with new settings confidently knowing I can instantly rollback to a known-good state if changes cause problems.

**Why this priority**: Enhances reliability and encourages experimentation. Not strictly required for MVP but significantly improves user confidence. Enables safe testing of complex configuration changes.

**Independent Test**: Can be tested by making configuration changes, committing to version control, making additional breaking changes, and executing rollback command to restore previous working configuration state within seconds.

**Acceptance Scenarios**:

1. **Given** user commits configuration changes to git, **When** user runs rollback command with commit hash, **Then** configuration restores to that commit state within 3 seconds
2. **Given** user makes breaking configuration change, **When** Sway fails to reload, **Then** system automatically reverts to last known-good configuration
3. **Given** user has 5 configuration versions in history, **When** user lists available versions, **Then** system displays timestamps, commit messages, and current active indicator
4. **Given** user is experimenting with keybindings, **When** user enables "try mode", **Then** changes auto-revert after 10 seconds unless explicitly confirmed
5. **Given** configuration is rolled back, **When** rollback completes, **Then** system logs show which settings changed and their before/after values

---

### User Story 5 - Integrated Configuration Validation (Priority: P2)

As a user who occasionally makes typos or invalid configuration entries, I need automatic validation before configuration is applied so I can catch errors early and avoid deploying broken configurations that disrupt my workflow.

**Why this priority**: Quality-of-life improvement that prevents common errors. Not critical for core functionality but significantly improves user experience. Reduces debugging time for configuration mistakes.

**Independent Test**: Can be tested by intentionally creating invalid configuration (malformed keybinding syntax, non-existent workspace number, invalid window class pattern), running validation command, and verifying system detects error with helpful message before attempting reload.

**Acceptance Scenarios**:

1. **Given** user defines invalid keybinding syntax, **When** validation runs, **Then** system reports syntax error with line number and suggested fix
2. **Given** user references non-existent workspace in assignment rule, **When** validation executes, **Then** system warns about undefined workspace and lists valid workspace numbers
3. **Given** user creates circular dependency in window rules, **When** validation checks configuration, **Then** system detects cycle and identifies conflicting rules
4. **Given** configuration is valid, **When** validation runs, **Then** system confirms all checks passed and displays summary of loaded settings
5. **Given** user enables auto-validation, **When** configuration file is saved, **Then** validation runs automatically and displays results in editor or terminal

---

### Edge Cases

- What happens when Sway configuration is reloaded while user is actively typing in a window? (Should not interrupt input, apply changes on next focus change)
- How does system handle Python daemon crash during configuration reload? (Graceful degradation: static Nix config remains active, daemon restarts with watchdog)
- What occurs when user modifies both Nix and Python configs simultaneously and triggers rebuild? (Documented precedence: Nix settings load first, Python overrides at runtime where permitted)
- How does system behave when project-specific window rule references workspace that doesn't exist? (Validation error before reload, falls back to default workspace)
- What happens if configuration rollback is triggered while daemon is processing window events? (Queue rollback until event processing completes, apply atomically)
- How does system handle conflicting keybindings between Sway config and Python daemon? (Nix keybindings have precedence, daemon uses IPC commands only)
- What occurs when hot-reload changes modifier key used in dozens of keybindings? (Validation warns about scope of change, requires explicit confirmation flag)
- How does system handle workspace reassignment when windows are currently open on affected workspaces? (Windows migrate with workspace to new output, maintain focus state)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support hot-reloading of keybindings without Sway restart or NixOS rebuild
- **FR-002**: System MUST support hot-reloading of window rules (floating, workspace assignments, sizing) without Sway restart
- **FR-003**: System MUST support hot-reloading of workspace-to-output assignments and trigger automatic workspace redistribution
- **FR-004**: System MUST provide clear documentation defining which settings belong in Nix modules versus Python modules
- **FR-005**: System MUST maintain configuration state in version-controllable files (JSON/TOML/YAML) separate from Nix store
- **FR-006**: System MUST validate configuration syntax and semantics before applying changes
- **FR-007**: System MUST detect configuration conflicts between Nix-managed and Python-managed settings and apply documented precedence rules
- **FR-008**: System MUST support project-specific window rules that override global rules when project is active
- **FR-009**: System MUST provide rollback mechanism to restore previous configuration version
- **FR-010**: System MUST preserve existing i3pm daemon functionality during configuration architecture changes
- **FR-011**: System MUST reload configuration atomically (all changes succeed or all fail) to prevent partial state
- **FR-012**: System MUST log configuration reload operations with timestamp, changed settings, and success/failure status
- **FR-013**: System MUST provide CLI command to display current active configuration with source attribution (Nix vs Python)
- **FR-014**: System MUST continue using Nix modules for static system-level settings (package installation, systemd services, session setup)
- **FR-015**: System MUST use Python daemon for dynamic runtime settings (project switching, window filtering, event-driven workspace management)

### Assumptions

- Sway IPC protocol provides sufficient capabilities for dynamic window rule application (matches i3 IPC feature parity)
- Home-manager Sway module can generate base configuration that Python daemon extends at runtime
- Configuration reload latency under 2 seconds is acceptable for user experience
- Users are comfortable with JSON/TOML configuration file editing (alternative to Nix syntax)
- Version control (git) is already in use for /etc/nixos repository
- Python daemon has necessary permissions to modify Sway state via IPC (matches current i3pm daemon permissions)
- Validation can be implemented using JSON Schema or similar without external dependencies

### Key Entities

- **Keybinding Configuration**: Represents keyboard shortcut mappings to Sway/daemon commands (key combo, command, description, source=Nix|Python)
- **Window Rule**: Defines behavior for windows matching criteria (match criteria, actions like float/tile/workspace, scope=global|project, priority)
- **Project Window Rule Override**: Project-specific rule that takes precedence over global rules when project is active (project name, base rule reference, override properties)
- **Workspace Assignment**: Maps workspace numbers to output names with fallback behavior (workspace number, primary output, fallback outputs, auto-reassign policy)
- **Configuration Version**: Snapshot of configuration state for rollback (timestamp, commit hash, configuration files, metadata)
- **Configuration Source Attribution**: Tracks which system (Nix or Python) owns each setting (setting path, source system, precedence level, last modified)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can modify and reload keybindings in under 5 seconds without NixOS rebuild (measured from file save to active keybinding)
- **SC-002**: Users can modify and reload window rules in under 3 seconds without Sway restart
- **SC-003**: Configuration reload operations succeed without errors 95% of the time during normal usage (excluding intentional validation errors)
- **SC-004**: System provides clear documentation with decision tree for "where should this setting go" achieving 90% user accuracy in categorization
- **SC-005**: Project-specific window rules apply correctly with 100% accuracy when switching between projects
- **SC-006**: Configuration validation detects 100% of syntax errors and 80% of semantic errors before reload
- **SC-007**: Configuration rollback restores previous state within 3 seconds with zero data loss
- **SC-008**: Existing i3pm daemon features (project switching, window filtering, workspace management) continue working with 100% backward compatibility
- **SC-009**: Hot-reload operations complete without disrupting active user input (keyboard/mouse) in 100% of cases
- **SC-010**: System architecture reduces average time to test configuration change from 120 seconds (rebuild) to under 10 seconds (reload)
