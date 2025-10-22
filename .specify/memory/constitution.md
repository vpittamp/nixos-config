<!--
Sync Impact Report:
- Version: 1.3.0 → 1.4.0 (MINOR - New principle added for forward-only development)
- Modified principles:
  * None - existing principles remain unchanged
- New principles created:
  * Principle XII: "Forward-Only Development & Legacy Elimination" (NEW)
    - Prohibits backwards compatibility considerations based on legacy code
    - Mandates optimal solution design without legacy constraints
    - Requires complete replacement of suboptimal code, not preservation
    - Eliminates technical debt accumulation through legacy support
- New sections added:
  * None - principle added to existing Core Principles section
- Updated sections:
  * None - existing sections remain compatible
- Templates requiring updates:
  ✅ .specify/templates/spec-template.md - Already compatible, no backwards compatibility sections
  ✅ .specify/templates/plan-template.md - Already focuses on optimal solutions
  ✅ .specify/templates/tasks-template.md - Already encourages replacement over preservation
  ⚠️ .specify/templates/commands/ - May benefit from guidance on replacing vs migrating
- Follow-up TODOs:
  * Review existing codebase for legacy code that should be replaced rather than maintained
  * Consider adding migration guide template that focuses on complete replacement workflows
  * Update CLAUDE.md to emphasize replacement over backwards compatibility
  * Add examples of complete replacements (e.g., Polybar → i3bar+i3blocks, polling → event-driven)
-->

# NixOS Modular Configuration Constitution

## Core Principles

### I. Modular Composition

Every configuration MUST be built from composable modules rather than monolithic files.

**Rules**:
- Common functionality MUST be extracted into reusable modules in `modules/`
- Platform-specific configurations MUST compose modules, not duplicate code
- Each module MUST have a single, clear responsibility (services, hardware, desktop)
- Configuration inheritance MUST follow: Base → Hardware → Services → Desktop → Target
- Modules MUST use proper NixOS option patterns: `mkEnableOption` for boolean enables, `mkOption` with explicit types for configuration values

**Rationale**: This project reduced from 46 files with 3,486 lines of duplication to ~25 modular files. Modular composition is the foundation that enables maintainability, consistency, and platform flexibility without code duplication.

### II. Reference Implementation Flexibility

A reference configuration serves as the canonical example for full-featured NixOS installations. The reference implementation MAY change when architectural requirements demand it.

**Rules**:
- Base configuration (`configurations/base.nix`) MUST be extracted from the current reference implementation's common functionality
- New features MUST be validated against the reference configuration first
- When evaluating a new reference configuration:
  * Document the specific technical limitations of the current reference
  * Research and validate the proposed alternative meets all core requirements
  * Test the migration path on at least one platform before full adoption
  * Update documentation to reflect the new reference architecture
- Breaking changes MUST be tested on the reference configuration before other platforms
- Documentation MUST clearly identify the current reference configuration

**Current Reference**: Hetzner configuration (`configurations/hetzner-i3.nix`) - full-featured NixOS with i3 tiling window manager on standard x86_64 hardware, optimized for remote desktop access via xrdp

**Rationale**: Originally, Hetzner provided a stable reference for KDE Plasma desktop deployments. The migration to i3wm + xrdp + X11 reflects the evolution toward keyboard-driven productivity workflows with superior multi-session RDP compatibility. This principle allows flexibility while maintaining the discipline of having a canonical reference.

### III. Test-Before-Apply (NON-NEGOTIABLE)

Every configuration change MUST be tested with `dry-build` before applying.

**Rules**:
- ALWAYS run `nixos-rebuild dry-build --flake .#<target>` before `switch`
- Build failures MUST be resolved before committing
- Breaking changes MUST be documented in commit messages
- Rollback procedures MUST be verified for critical changes
- Use `--show-trace` flag when debugging build errors for detailed stack traces

**Rationale**: NixOS is a production system configuration. Untested changes can break system boot, desktop environments, or critical services. The dry-build requirement ensures changes are evaluated before deployment, enabling safe rollbacks via NixOS generations.

### IV. Override Priority Discipline

Module options MUST use appropriate priority levels: `lib.mkDefault` for overrideable defaults, normal assignment for standard configuration, `lib.mkForce` only when override is mandatory.

**Rules**:
- Use `lib.mkDefault` in base modules for options that platforms should override
- Use normal assignment for typical module configuration
- Use `lib.mkForce` ONLY when the value must override all other definitions
- Document every `lib.mkForce` usage with a comment explaining why it's required
- Avoid option conflicts by choosing the appropriate priority level
- Test module composition with `nix eval` to verify override behavior

**Rationale**: Proper priority usage enables the modular composition hierarchy. Incorrect priority levels lead to hard-to-debug option conflicts and prevent platform-specific customization. The 45% file reduction achieved in this project relied on proper override mechanisms.

### V. Platform Flexibility Through Conditional Features

Modules MUST adapt to system capabilities through conditional logic rather than creating separate module variants.

**Rules**:
- Detect system capabilities with `config.services.xserver.enable or false` pattern
- Use `lib.mkIf` for conditional service configuration
- Use `lib.optionals` for conditional package lists
- Distinguish GUI vs headless deployments automatically
- Service modules MUST function correctly with or without desktop environments
- Desktop modules MUST detect window manager type and adapt accordingly

**Example**:
```nix
let
  hasGui = config.services.xserver.enable or false;
  hasI3 = config.services.i3wm.enable or false;
in {
  environment.systemPackages = with pkgs; [
    package-cli  # Always installed
  ] ++ lib.optionals hasGui [
    package-gui  # Only with GUI
  ] ++ lib.optionals hasI3 [
    rofi         # Only with i3wm
    i3wsr        # i3 workspace renamer
  ];
}
```

**Rationale**: A single module (e.g., `onepassword.nix`) can adapt to WSL (CLI-only), Hetzner (full GUI with i3), and containers (minimal) without duplication. Conditional features maintain consistency while supporting diverse deployment targets.

### VI. Declarative Configuration Over Imperative

All system configuration MUST be declared in Nix expressions; imperative post-install scripts are forbidden except for desktop environment settings capture during migration.

**Rules**:
- System packages MUST be declared in `environment.systemPackages` or module configurations
- Services MUST be configured via NixOS options, not manual systemd files
- User environments MUST use home-manager, not manual dotfile management
- Secrets MUST use 1Password integration or declarative secret management (sops-nix/agenix)
- Desktop environment configurations MUST be declared in home-manager or NixOS modules
- Configuration files MUST be generated via `environment.etc` or home-manager `home.file`
- i3 window manager configuration MUST be declared in `environment.etc."i3/config".text`
- Limited exception: Temporary capture scripts (e.g., `scripts/*-rc2nix.sh`) MAY be used to extract live desktop environment settings during migration, with the intent to refactor captured settings into declarative modules

**Rationale**: Declarative configuration is NixOS's core value proposition. It enables reproducible builds, atomic upgrades, and automatic rollbacks. Imperative changes create configuration drift and break the reproducibility guarantee. Configuration file generation via environment.etc ensures consistency and version control integration.

### VII. Documentation as Code

Every module, configuration change, and architectural decision MUST be documented alongside the code.

**Rules**:
- Complex modules MUST include header comments explaining purpose, dependencies, and options
- `docs/` MUST contain architecture documentation, setup guides, and troubleshooting
- `CLAUDE.md` MUST be the primary LLM navigation guide with quick start commands
- Breaking changes MUST update relevant documentation in the same commit
- Migration guides MUST be created for major structural changes (e.g., KDE Plasma → i3wm)
- Module options MUST include `description` fields for documentation generation

**Rationale**: This project's complexity demands clear documentation. LLM assistants, new contributors, and future maintainers rely on comprehensive guides to navigate the modular architecture effectively. Inline documentation via description fields enables automatic documentation generation.

### VIII. Remote Desktop & Multi-Session Standards

Remote desktop access MUST support multiple concurrent sessions with proper isolation, authentication, and resource management.

**Rules**:
- Multi-session support MUST allow 3-5 concurrent connections per user without disconnecting existing sessions
- Session isolation MUST ensure independent desktop environments (separate window managers, application states)
- Session persistence MUST maintain state across disconnections with automatic cleanup after 24 hours of idle time
- Authentication MUST support password-based access with optional SSH key authentication
- Display server MUST be X11 for mature RDP/xrdp compatibility (Wayland lacks stable multi-session RDP support)
- Window manager MUST support multi-session isolation (i3wm preferred for lightweight resource usage)
- Remote desktop configuration MUST preserve existing tool integrations (1Password, terminal customizations, browser extensions)
- Clipboard integration MUST work across RDP sessions using clipcat or equivalent X11-compatible clipboard manager
- Resource limits MUST be documented and enforced to prevent system exhaustion
- DISPLAY environment variable MUST be properly propagated to user services and applications

**Configuration**:
- Remote desktop service: xrdp with multi-session support enabled
- Display server: X11 (via `services.xserver.enable = true`)
- Window manager: i3wm (via custom `services.i3wm` module)
- Session management: Automatic cleanup policies, reconnection handling
- Clipboard manager: clipcat (started from i3 config to inherit DISPLAY variable)

**Rationale**: Remote development workstations require seamless multi-device access without workflow interruption. Microsoft Remote Desktop (RDP) is the standard cross-platform protocol. Multi-session support enables users to maintain separate contexts on different devices while sharing a single powerful remote system. X11 provides mature, stable RDP compatibility via xrdp, while Wayland's RDP support remains experimental. Session cleanup prevents resource exhaustion while maintaining reasonable persistence expectations.

### IX. Tiling Window Manager & Productivity Standards

Desktop environments MUST prioritize keyboard-driven workflows with efficient window management for developer productivity.

**Rules**:
- Window manager MUST be i3wm or compatible tiling window manager (sway for Wayland, bspwm/awesome as alternatives)
- Keyboard shortcuts MUST be declaratively configured and documented
- Workspace management MUST support dynamic naming with application-aware labels (via i3wsr)
- Application launcher MUST be keyboard-driven (rofi preferred for consistency and extensibility)
- Terminal emulator MUST support transparency, true color, and tmux integration (alacritty preferred)
- Clipboard manager MUST provide history access across all applications with keyboard shortcuts (clipcat via Win+V)
- Workspace naming MUST reflect running applications for context awareness (i3wsr with custom aliases)
- Window management MUST support floating windows for specific applications (e.g., dialogs, popups)
- Multi-monitor support MUST be configurable with declarative xrandr settings
- Session startup MUST be minimal and fast (<5 seconds to usable desktop)

**i3wm Integration Requirements**:
- `rofi`: Application launcher, window switcher, clipboard menu
- `i3wsr`: Dynamic workspace renaming based on window classes
- `clipcat`: Clipboard history manager with rofi integration
- `alacritty`: Primary terminal emulator
- `i3status`: Status bar with system information
- `i3lock`: Screen locking (optional, for physical access scenarios)

**Configuration Structure**:
```nix
# System module: modules/desktop/i3wm.nix
services.i3wm = {
  enable = true;
  package = pkgs.i3;
  extraPackages = [ pkgs.rofi pkgs.i3status ];
};

# Home-manager module: home-modules/desktop/i3.nix
# User-specific keybindings, workspace configuration, theme

# Home-manager module: home-modules/desktop/i3wsr.nix
# Application-aware workspace naming with custom aliases
```

**Keyboard Shortcuts (Standard Bindings)**:
- `Win+Return`: Open terminal
- `Win+D`: Application launcher (rofi)
- `Win+V`: Clipboard history (clipcat)
- `Win+F`: Fullscreen toggle
- `Ctrl+1-9`: Workspace switching (for RDP compatibility, avoids Win key issues)
- `Win+Shift+1-9`: Move window to workspace
- `Win+Shift+Q`: Close window
- `Win+H/V`: Split horizontal/vertical

**Rationale**: Tiling window managers maximize screen real estate and minimize mouse usage, critical for remote desktop scenarios where mouse precision is degraded. i3wm's minimal resource usage enables multiple concurrent sessions on a single server. Keyboard-first workflows improve productivity and reduce dependency on RDP's pointer handling. Dynamic workspace naming via i3wsr provides immediate context awareness across workspaces. Clipboard history via clipcat ensures seamless copy/paste workflow across applications and RDP sessions.

### X. Python Development & Testing Standards

Python-based system tooling MUST follow consistent patterns for async programming, testing, type safety, and dependency management.

**Rules**:
- Python version MUST be 3.11+ for all new development (matches existing i3-project daemon)
- Async/await patterns MUST be used for i3 IPC communication and daemon interaction (via i3ipc.aio, asyncio)
- Testing framework MUST be pytest with support for async tests (pytest-asyncio)
- Type hints MUST be used for function signatures and public APIs
- Data validation MUST use Pydantic models or dataclasses with validation
- Terminal UI applications MUST use Rich library for tables, live displays, and formatting
- Module structure MUST follow single-responsibility principle with clear separation (models, services, displays, validators)
- Python packages MUST be installed via home-manager user packages (development profile)
- CLI tools MUST provide --help output and follow standard argument patterns
- Error handling MUST be explicit with clear error messages and exit codes
- Logging MUST use standard library `logging` module with appropriate log levels

**Testing Requirements**:
- Unit tests MUST validate data models, formatters, and business logic
- Integration tests MUST validate IPC communication and daemon interaction
- Test scenarios MUST be independently executable and validate expected vs actual state
- Tests MUST support headless operation for CI/CD environments
- Mock patterns MUST be used to isolate tests from external dependencies (daemon, i3 IPC)
- Test reports MUST be output in both human-readable (terminal) and machine-readable (JSON) formats
- Automated tests MUST execute in under 10 seconds for full workflow validation
- Test frameworks MUST support tmux integration for multi-pane monitoring during manual testing

**Python Project Structure Pattern**:
```
home-modules/tools/<tool-name>/
├── __init__.py              # Package initialization
├── __main__.py              # CLI entry point
├── models.py                # Pydantic models / dataclasses
├── <service>.py             # Business logic modules
├── displays/                # Terminal UI components (if applicable)
│   ├── __init__.py
│   └── <mode>.py           # Display mode implementations
└── README.md                # Module documentation

tests/<tool-name>/
├── test_models.py           # Data model tests
├── test_<service>.py        # Service logic tests
└── fixtures/
    └── mock_<dependency>.py # Mock implementations
```

**Best Practices**:
- Prefer async/await over callbacks for better readability and error handling
- Use context managers for resource cleanup (connections, files, etc.)
- Validate input early and fail fast with clear error messages
- Keep display logic separate from business logic for testability
- Use circular buffers for event storage to prevent memory growth
- Implement auto-reconnection with exponential backoff for daemon connections
- Include diagnostic modes in monitoring tools for troubleshooting

**Rationale**: Features 017 and 018 established Python as the standard for i3-project system tooling. Consistent patterns across monitoring tools, test frameworks, and daemon extensions reduce cognitive load and improve maintainability. Async patterns are essential for event-driven i3 IPC integration. Rich library provides consistent terminal UI across all tools. pytest enables comprehensive test coverage including CI/CD integration. Type hints and validation prevent runtime errors and improve code quality.

### XI. i3 IPC Alignment & State Authority

All i3-related state queries and window management operations MUST use i3's native IPC API as the authoritative source of truth.

**Rules**:
- State queries MUST use i3's native IPC message types: GET_WORKSPACES, GET_OUTPUTS, GET_TREE, GET_MARKS
- Workspace-to-output assignments MUST be validated against i3's GET_WORKSPACES response
- Monitor/output configuration MUST be queried via GET_OUTPUTS, not xrandr or other tools
- Window marking and visibility MUST be verified via GET_TREE and GET_MARKS
- Event subscriptions MUST use i3's SUBSCRIBE IPC message type (window, workspace, output, binding)
- Custom state tracking (daemon, database) MUST be validated against i3 IPC data, not vice versa
- When discrepancies occur between custom state and i3 IPC, i3 IPC data MUST be considered authoritative
- i3ipc-python library (i3ipc.aio for async) MUST be used for all i3 IPC communication
- State synchronization MUST be event-driven via i3 IPC subscriptions, not polling
- Diagnostic tools MUST include i3 IPC state in all reports for validation

**Event-Driven Architecture Requirements**:
- Use i3 IPC subscriptions for real-time state updates (window events, workspace changes, output changes)
- Process events asynchronously via asyncio event loops
- Maintain minimal daemon state - query i3 IPC when authoritative state needed
- Implement event handlers with <100ms latency for window marking and state updates
- Use event buffers (circular, max 500 events) for diagnostic history, not authoritative state
- Fail gracefully when i3 IPC connection is lost with auto-reconnection (exponential backoff)

**i3 IPC Message Types (Standard Usage)**:
- `GET_WORKSPACES`: Query workspace list with names, visible status, output assignments
- `GET_OUTPUTS`: Query monitor/output configuration with names, active status, dimensions, workspaces
- `GET_TREE`: Query complete window tree with containers, marks, focus, properties
- `GET_MARKS`: Query all window marks in current session
- `SUBSCRIBE`: Subscribe to events (window, workspace, output, binding, shutdown, tick)
- `COMMAND`: Execute i3 commands (mark windows, move containers, switch workspaces)

**State Validation Pattern**:
```python
# Query i3's authoritative state
async with i3ipc.aio.Connection() as i3:
    workspaces = await i3.get_workspaces()
    outputs = await i3.get_outputs()
    tree = await i3.get_tree()

    # Validate daemon state against i3 state
    for workspace in workspaces:
        expected_output = workspace.output
        daemon_output = get_daemon_workspace_assignment(workspace.num)
        if expected_output != daemon_output:
            # i3 state is authoritative - update daemon
            sync_daemon_state(workspace.num, expected_output)
```

**Rationale**: Feature 018 identified critical issues when custom state tracking (daemon databases, configuration files) drifts from i3's actual state. i3's IPC API is the single source of truth for window management state - workspace assignments, output configuration, window marks, and focus state all originate from i3. Event-driven architecture via i3 IPC subscriptions replaced polling-based systems in Feature 015, reducing CPU usage to <1% and eliminating race conditions. All monitoring, testing, and diagnostic tools must align with i3's state to ensure accurate debugging and validation. When building extensions to i3, query i3 IPC to validate assumptions rather than maintaining parallel state that can desync.

### XII. Forward-Only Development & Legacy Elimination

All solutions and features MUST be designed for optimal implementation without consideration for backwards compatibility with legacy code or assumptions about production versions requiring legacy support.

**Rules**:
- Feature implementations MUST pursue the optimal solution architecture without constraints from legacy code patterns
- When creating improved logic or methodology, legacy code MUST be completely replaced, not preserved alongside new code
- No compatibility layers, feature flags, or conditional logic MUST be added to support legacy implementations
- Code duplication for backwards compatibility purposes is FORBIDDEN
- Migration from legacy to new solutions MUST be complete and immediate, not gradual with dual support
- Technical debt from backwards compatibility MUST NOT be introduced or accumulated
- Legacy code that becomes obsolete through new implementations MUST be removed in the same commit/PR
- Documentation MUST focus on current optimal solutions, not legacy approaches
- "Deprecated but supported" states are NOT ALLOWED - code is either current or removed

**Examples of This Principle**:
- ✅ **Polybar → i3bar+i3blocks migration**: Completely replaced polybar with i3bar+i3blocks, removed all polybar configuration, no dual support
- ✅ **Polling → Event-driven architecture**: Replaced entire polling system with i3 IPC subscriptions, no backwards compatibility for polling mode
- ✅ **Static i3 config → Dynamic window rules**: Will completely replace static `for_window` directives with dynamic rules engine, no preservation of old patterns
- ❌ **BAD: Adding feature flags for "legacy mode"**: Would violate this principle
- ❌ **BAD: Keeping old code "just in case"**: Would violate this principle
- ❌ **BAD: Gradual migration with dual code paths**: Would violate this principle

**When Replacement is Required**:
- New feature renders existing implementation suboptimal → Replace immediately
- Better architectural pattern emerges → Replace existing pattern completely
- Performance/maintainability improvements available → Replace without preserving old approach
- Simpler solution discovered → Replace complex solution entirely

**Rationale**: This project exists for personal productivity optimization, not as a product with external users dependent on stability. Every line of code maintained for backwards compatibility is technical debt that slows development, complicates architecture, and reduces clarity. The fastest path to optimal solutions is immediate, complete replacement of suboptimal code. This principle accelerates innovation by eliminating the burden of legacy support and ensures the codebase always represents the current best practices without historical baggage. Clean breaks are faster and clearer than gradual migrations with compatibility shims.

## Platform Support Standards

### Multi-Platform Compatibility

The configuration MUST support WSL2, Hetzner Cloud, Apple Silicon Macs (via Asahi Linux), and container deployments.

**Rules**:
- Target configurations MUST be defined in `configurations/` directory
- Hardware-specific settings MUST be isolated in `hardware/` modules
- Platform-specific packages MUST be added in target configurations with appropriate overrides
- Cross-platform features MUST be tested on at least two platforms before merging
- Containers MUST support minimal, essential, development, and full package profiles

**Testing Requirements**:
- WSL: Docker Desktop integration, VS Code Remote, 1Password CLI
- Hetzner: i3 tiling window manager, xrdp multi-session access, Tailscale VPN, development tools, clipcat clipboard manager
- M1: ARM64 optimizations, Wayland session (for native display), Retina display scaling, requires `--impure` flag
- Containers: Size constraints (<100MB minimal, <600MB development)

**Desktop Environment Transitions**:
When migrating desktop environments (e.g., KDE Plasma → i3wm, X11 → Wayland):
1. Research target environment's compatibility with existing tools and workflows
2. Evaluate display server requirements (X11 vs Wayland) based on remote desktop needs
3. For remote desktop scenarios: Prefer X11 for mature xrdp compatibility
4. For native hardware: Consider Wayland for better HiDPI and modern features
5. Test migration on reference platform first
6. Document configuration patterns and module structure
7. Validate all critical integrations (1Password, terminal tools, browser extensions, clipboard)
8. Update platform testing requirements to reflect new environment
9. Create migration documentation in `docs/MIGRATION.md`

**X11 vs Wayland Decision Criteria**:
- **Choose X11 when**:
  * Primary use case is remote desktop (RDP/xrdp)
  * Multi-session support is required
  * Mature tool compatibility is critical (screen sharing, recording, clipboard managers)
- **Choose Wayland when**:
  * Primary use case is native hardware (laptops, desktops)
  * HiDPI scaling and modern input methods are priorities
  * Security isolation between applications is required
  * Native touchpad gestures are important (e.g., M1 Mac)

## Security & Authentication Standards

### 1Password Integration

Secret management MUST use 1Password for centralized, secure credential storage.

**Rules**:
- SSH keys MUST be stored in 1Password vaults, not filesystem
- Git commit signing MUST use 1Password SSH agent
- GitHub/GitLab authentication MUST use 1Password credential helpers
- GUI installations (Hetzner, M1) MUST include 1Password desktop app
- Headless installations (WSL, containers) MUST use 1Password CLI
- Biometric authentication MUST be enabled where platform supports it
- Remote desktop sessions MUST have access to 1Password without re-authentication
- 1Password browser extension MUST be compatible with Firefox PWAs

**Configuration**:
- Module: `modules/services/onepassword.nix`
- Conditional GUI/CLI support based on `config.services.xserver.enable`
- PAM integration for system authentication
- Polkit rules for desktop authentication
- RDP session integration for persistent authentication state

### SSH Hardening

SSH access MUST use key-based authentication with rate limiting and fail2ban integration.

**Rules**:
- Password authentication MUST be disabled for SSH
- SSH keys MUST be managed via 1Password SSH agent
- Rate limiting MUST be configured on public-facing systems
- Fail2ban MUST be enabled on Hetzner and other exposed servers
- Tailscale VPN MUST be the primary access method for remote systems
- RDP authentication MAY use password-based access (separate from SSH) with optional SSH key support

## Package Management Standards

### Package Profiles

Package installations MUST be controlled by profile levels to manage system size and complexity.

**Profiles** (defined in `shared/package-lists.nix`):
- **minimal** (~100MB): Core utilities only - for containers
- **essential** (~275MB): Basic development tools - for CI/CD environments
- **development** (~600MB): Full development stack - for active development
- **full** (~1GB): Everything including Kubernetes tools - for complete workstations

**Rules**:
- Containers MUST use minimal or essential profiles
- Development systems MUST use development or full profiles
- New packages MUST be added to the appropriate profile level
- Package additions MUST justify their profile placement in commit messages

### Package Organization

Packages MUST be organized by scope: system-wide, user-specific, module-specific, or target-specific.

**Hierarchy**:
1. **System packages** (`system/packages.nix`): System-wide tools available to all users
2. **User packages** (`user/packages.nix`): User-specific tools installed via home-manager
3. **Module packages**: Packages defined within service/desktop modules for specific functionality
4. **Target packages**: Platform-specific additions in target configurations

**Rules**:
- Prefer module-specific package definitions for better encapsulation (e.g., `modules/desktop/i3wm.nix` includes rofi, alacritty)
- Use system packages for tools required by multiple modules
- Use user packages for development tools and personal utilities
- Use target packages ONLY for platform-specific requirements (e.g., wsl.exe on WSL)
- Avoid duplicate package declarations across modules

**Best Practice - Module Package Scoping**:
```nix
# modules/desktop/i3wm.nix
config = mkIf cfg.enable {
  environment.systemPackages = with pkgs; [
    cfg.package      # i3 itself
    alacritty       # Terminal for i3
    rofi            # Application launcher
  ] ++ cfg.extraPackages;  # Allow extension
};
```

## Testing & Validation Standards

### Automated Testing Requirements

Python-based system tooling MUST include comprehensive automated tests for functionality validation and regression prevention.

**Rules**:
- All Python modules MUST have pytest-based unit tests for data models and business logic
- Integration tests MUST validate daemon communication, i3 IPC interaction, and state synchronization
- Test scenarios MUST simulate real user workflows (project lifecycle, window management, monitor configuration)
- Tests MUST support headless operation for CI/CD integration
- Mock implementations MUST be provided for external dependencies (daemon, i3 IPC socket)
- Test reports MUST be output in machine-readable format (JSON) for CI/CD parsing
- Automated test suites MUST execute in under 10 seconds for complete workflow validation
- Failed tests MUST report expected vs actual state with detailed diff information
- Test frameworks MUST use tmux for multi-pane monitoring during manual interactive testing

**Test Coverage Requirements**:
- **Unit tests**: Data models, formatters, validators, business logic (>80% coverage target)
- **Integration tests**: IPC communication, daemon interaction, state queries
- **Contract tests**: JSON-RPC API endpoints, i3 IPC message types
- **Scenario tests**: End-to-end user workflows with state validation
- **Regression tests**: Previously identified bugs with validation to prevent recurrence

**Test Organization Pattern**:
```
tests/<module-name>/
├── unit/
│   ├── test_models.py
│   ├── test_validators.py
│   └── test_formatters.py
├── integration/
│   ├── test_daemon_client.py
│   └── test_i3_ipc.py
├── scenarios/
│   ├── test_project_lifecycle.py
│   └── test_window_management.py
└── fixtures/
    ├── mock_daemon.py
    └── sample_data.py
```

**Rationale**: Feature 018 demonstrated the value of automated testing for complex event-driven systems. Manual testing is time-consuming, error-prone, and doesn't scale to CI/CD. Automated tests catch regressions early, provide confidence during refactoring, and serve as executable documentation of expected behavior. Test scenarios based on real user workflows ensure comprehensive coverage of critical paths.

### Diagnostic & Monitoring Standards

System tooling MUST provide observability and diagnostic capabilities for debugging and troubleshooting.

**Rules**:
- Monitoring tools MUST display real-time system state (active project, tracked windows, monitors, events)
- Event streams MUST be captured and displayed with timestamps, event types, and payloads
- Diagnostic capture MUST include: current state snapshot, recent event history (500 events), i3 tree structure, complete i3 IPC state (outputs, workspaces, marks)
- State validation MUST compare custom daemon state against i3 IPC authoritative state
- Monitoring tools MUST support multiple display modes (live, events, history, tree, diagnose)
- Connection status MUST be clearly indicated with auto-reconnection on failure
- Error states MUST provide actionable troubleshooting guidance
- Diagnostic reports MUST be output as structured JSON for analysis and comparison

**Monitoring Tool Requirements**:
- Real-time display updates (250ms refresh rate for live mode)
- Event streaming with <100ms latency from event occurrence to display
- Circular event buffer (500 events max) for historical review
- Terminal UI using Rich library for tables, syntax highlighting, and live displays
- Multiple concurrent instances for parallel monitoring (different modes in different terminals)
- Headless operation mode for automated diagnostic capture

**Rationale**: Feature 017 (i3 Project System Monitor) established that comprehensive observability reduces debugging time by 50% compared to manual log inspection. Real-time monitoring enables developers to see state changes as they occur, event streams reveal timing and sequencing issues, and diagnostic captures provide complete context for post-mortem analysis. These capabilities are essential for maintaining complex event-driven systems.

## Home-Manager Standards

### Module Structure

Home-manager modules MUST follow consistent structure and import patterns.

**Rules**:
- Each home-manager module MUST declare its inputs: `{ config, lib, pkgs, ... }:`
- User-specific desktop configuration MUST live in `home-modules/desktop/`
- User-specific tool configuration MUST live in `home-modules/tools/`
- Modules MUST use `lib.mkIf` for conditional feature activation
- Modules MUST expose options via home-manager option system when configurable
- Configuration files MUST be generated via `home.file` or `xdg.configFile`

**Example Module Structure**:
```nix
# home-modules/tools/clipcat.nix
{ config, lib, pkgs, ... }:

{
  services.clipcat = {
    enable = true;
    package = pkgs.clipcat;

    daemonSettings = {
      max_history = 100;
      # ... configuration
    };
  };

  # Ensure dependencies available
  home.packages = with pkgs; [ xclip xsel ];
}
```

### Configuration File Generation

Configuration files MUST be generated declaratively, not copied from external sources.

**Rules**:
- i3 config MUST be generated via `environment.etc."i3/config".text` (system-level) or `xdg.configFile."i3/config".text` (user-level)
- Dotfiles MUST be generated via home-manager's `home.file` or `xdg.configFile`
- Template-based generation MUST use Nix string interpolation with `${}` for variable substitution
- Binary paths MUST use `${pkgs.package}/bin/binary` format for reproducibility
- Scripts MUST be generated with proper shebang and execute permissions

**Example**:
```nix
environment.etc."i3/config".text = ''
  # i3 configuration
  set $mod Mod4
  bindsym $mod+Return exec ${pkgs.alacritty}/bin/alacritty
  bindsym $mod+d exec ${pkgs.rofi}/bin/rofi -show drun
'';
```

## Governance

This Constitution supersedes all other development practices and conventions. Any configuration change, module addition, or architectural modification MUST comply with these principles.

### Amendment Procedure

1. **Proposal**: Document proposed change with rationale in a GitHub issue or pull request
2. **Review**: Changes affecting Core Principles require architectural review and testing on all platforms
3. **Approval**: Amendments must be tested via `dry-build` on WSL, Hetzner, M1, and containers
4. **Migration Plan**: Breaking changes require migration documentation in `docs/MIGRATION.md`
5. **Version Update**: Constitution version increments follow semantic versioning
6. **Propagation**: Update dependent templates, documentation, and command files

### Semantic Versioning

- **MAJOR**: Backward incompatible changes (principle removal, governance redefinition)
- **MINOR**: New principles added or materially expanded guidance
- **PATCH**: Clarifications, wording improvements, typo fixes, non-semantic refinements

### Compliance Verification

All pull requests and configuration rebuilds MUST verify compliance with:
- ✅ Modular composition - no code duplication
- ✅ Test-before-apply - `dry-build` executed and passed
- ✅ Override priorities - `mkDefault` and `mkForce` used appropriately
- ✅ Conditional features - modules adapt to system capabilities
- ✅ Declarative configuration - no imperative post-install scripts (except temporary desktop capture)
- ✅ Documentation updates - architectural changes reflected in docs
- ✅ Security standards - secrets via 1Password, SSH hardening maintained
- ✅ Remote desktop standards - multi-session support, session isolation, resource limits
- ✅ Tiling WM standards - i3wm configuration, keyboard-first workflows, workspace isolation
- ✅ Python standards - async patterns, pytest testing, type hints, Rich UI
- ✅ i3 IPC alignment - state queries via native IPC, event-driven architecture
- ✅ Forward-only development - optimal solutions without legacy compatibility preservation

### Complexity Justification

Any violation of simplicity principles (e.g., adding a 5th platform target, creating deep inheritance hierarchies, introducing abstraction layers) MUST be justified by documenting:
- **Current Need**: Specific problem requiring the complexity
- **Simpler Alternative Rejected**: Why simpler approaches were insufficient
- **Long-term Maintenance**: How the complexity will be managed and documented

**Version**: 1.4.0 | **Ratified**: 2025-10-14 | **Last Amended**: 2025-10-22
