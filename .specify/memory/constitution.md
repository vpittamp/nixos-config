<!--
Sync Impact Report:
- Version: 1.7.0 → 1.8.0 (MINOR - New principle added for Observability Standards)
- Modified principles:
  * Principle VIII: "Remote Desktop & Multi-Session Standards" - Added VNC as primary for Sway/Wayland
  * Principle IX: "Tiling Window Manager & Productivity Standards" - Updated to reflect Sway as primary with i3wm references preserved for legacy systems
  * Principle XI: "Sway/i3 IPC Alignment & State Authority" - Renamed to include Sway, updated examples to prefer swaymsg
  * Principle XIV: "Test-Driven Development & Autonomous Testing" - Added Grafana/observability testing patterns
- New principles created:
  * Principle XVI: "Observability & Telemetry Standards" (NEW)
    - Mandates Grafana Alloy for unified telemetry collection
    - Defines multi-CLI AI tracing patterns (Claude Code, Codex, Gemini)
    - Establishes trace synthesis standards for non-native OTEL sources
    - Specifies Kubernetes LGTM stack integration
    - Documents graceful degradation for local-first monitoring
- Updated sections:
  * Platform Support Standards - Added Sway/Wayland notes for remote desktop
  * Compliance Verification - Added observability standards check
- Templates requiring updates:
  ✅ .specify/templates/spec-template.md - Generic, no changes needed
  ✅ .specify/templates/plan-template.md - Generic, no changes needed
  ✅ .specify/templates/tasks-template.md - Generic, no changes needed
  ✅ .specify/templates/checklist-template.md - Generic, no changes needed
- Follow-up TODOs:
  * None - all updates complete
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

**Current Reference**: ThinkPad configuration (`configurations/thinkpad.nix`) - full-featured NixOS with Sway Wayland compositor on x86_64 hardware, with dynamic configuration management (Feature 047)

**Rationale**: The ThinkPad serves as the primary development machine and canonical reference configuration. The Sway/Wayland stack provides modern compositor features, better performance, and native Wayland protocol support. Feature 047 adds hot-reloadable configuration with validation, version control, and template-based management to avoid home-manager conflicts. This principle allows flexibility while maintaining the discipline of having a canonical reference.

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
  hasSway = config.wayland.windowManager.sway.enable or false;
  hasI3 = config.services.i3wm.enable or false;
in {
  environment.systemPackages = with pkgs; [
    package-cli  # Always installed
  ] ++ lib.optionals hasGui [
    package-gui  # Only with GUI
  ] ++ lib.optionals hasSway [
    wl-clipboard # Only with Sway
    wofi         # Sway launcher
  ] ++ lib.optionals hasI3 [
    rofi         # Only with i3wm
    i3wsr        # i3 workspace renamer
  ];
}
```

**Rationale**: A single module (e.g., `onepassword.nix`) can adapt to WSL (CLI-only), Hetzner (full GUI with Sway), and containers (minimal) without duplication. Conditional features maintain consistency while supporting diverse deployment targets.

### VI. Declarative Configuration Over Imperative

All system configuration MUST be declared in Nix expressions; imperative post-install scripts are forbidden except for desktop environment settings capture during migration.

**Rules**:
- System packages MUST be declared in `environment.systemPackages` or module configurations
- Services MUST be configured via NixOS options, not manual systemd files
- User environments MUST use home-manager, not manual dotfile management
- Secrets MUST use 1Password integration or declarative secret management (sops-nix/agenix)
- Desktop environment configurations MUST be declared in home-manager or NixOS modules
- Configuration files MUST be generated via `environment.etc` or home-manager `home.file`
- Sway/i3 window manager configuration MUST be declared in home-manager or `environment.etc`
- Limited exception: Temporary capture scripts (e.g., `scripts/*-rc2nix.sh`) MAY be used to extract live desktop environment settings during migration, with the intent to refactor captured settings into declarative modules

**Rationale**: Declarative configuration is NixOS's core value proposition. It enables reproducible builds, atomic upgrades, and automatic rollbacks. Imperative changes create configuration drift and break the reproducibility guarantee. Configuration file generation via environment.etc ensures consistency and version control integration.

### VII. Documentation as Code

Every module, configuration change, and architectural decision MUST be documented alongside the code.

**Rules**:
- Complex modules MUST include header comments explaining purpose, dependencies, and options
- `docs/` MUST contain architecture documentation, setup guides, and troubleshooting
- `CLAUDE.md` MUST be the primary LLM navigation guide with quick start commands
- Breaking changes MUST update relevant documentation in the same commit
- Migration guides MUST be created for major structural changes (e.g., KDE Plasma → i3wm → Sway)
- Module options MUST include `description` fields for documentation generation

**Rationale**: This project's complexity demands clear documentation. LLM assistants, new contributors, and future maintainers rely on comprehensive guides to navigate the modular architecture effectively. Inline documentation via description fields enables automatic documentation generation.

### VIII. Remote Desktop & Multi-Session Standards

Remote desktop access MUST support multiple concurrent sessions with proper isolation, authentication, and resource management.

**Rules**:
- Multi-session support MUST allow 3-5 concurrent connections per user without disconnecting existing sessions
- Session isolation MUST ensure independent desktop environments (separate window managers, application states)
- Session persistence MUST maintain state across disconnections with automatic cleanup after 24 hours of idle time
- Authentication MUST support password-based access with optional SSH key authentication
- Display server selection depends on remote access method:
  * VNC: Use Wayland/Sway with wayvnc for modern compositor features
  * RDP: Use X11 for mature xrdp multi-session compatibility
- Window manager MUST support multi-session isolation (Sway preferred for Wayland, i3wm for X11)
- Remote desktop configuration MUST preserve existing tool integrations (1Password, terminal customizations, browser extensions)
- Clipboard integration MUST work across sessions using wl-clipboard (Wayland) or clipcat (X11)
- Resource limits MUST be documented and enforced to prevent system exhaustion
- DISPLAY/WAYLAND_DISPLAY environment variable MUST be properly propagated to user services and applications

**Configuration**:
- Remote desktop service: wayvnc for Sway/Wayland, xrdp for X11 multi-session
- Display server: Wayland (via headless compositor) or X11 (via `services.xserver.enable = true`)
- Window manager: Sway for Wayland, i3wm for X11
- Session management: Automatic cleanup policies, reconnection handling
- Clipboard manager: wl-clipboard (Wayland) or clipcat (X11)

**Rationale**: Remote development workstations require seamless multi-device access without workflow interruption. VNC provides efficient Wayland-native remote access via wayvnc. RDP via xrdp remains supported for X11 deployments. Multi-session support enables users to maintain separate contexts on different devices while sharing a single powerful remote system. Session cleanup prevents resource exhaustion while maintaining reasonable persistence expectations.

### IX. Tiling Window Manager & Productivity Standards

Desktop environments MUST prioritize keyboard-driven workflows with efficient window management for developer productivity.

**Rules**:
- Window manager MUST be Sway (Wayland) or i3wm (X11) or compatible tiling window manager
- Keyboard shortcuts MUST be declaratively configured and documented
- Workspace management MUST support dynamic naming with application-aware labels
- Application launcher MUST be keyboard-driven (rofi/wofi preferred for consistency and extensibility)
- Terminal emulator MUST support transparency, true color, and tmux integration (ghostty/alacritty preferred)
- Clipboard manager MUST provide history access across all applications with keyboard shortcuts
- Workspace naming MUST reflect running applications for context awareness
- Window management MUST support floating windows for specific applications (e.g., dialogs, popups)
- Multi-monitor support MUST be configurable with declarative output settings (swaymsg or xrandr)
- Session startup MUST be minimal and fast (<5 seconds to usable desktop)

**Sway/Wayland Integration Requirements**:
- `wofi` or `rofi`: Application launcher, window switcher, clipboard menu
- `wl-clipboard`: Clipboard operations (wl-copy, wl-paste)
- `ghostty` or `alacritty`: Primary terminal emulator
- `waybar` or `eww`: Status bar with system information
- `swaylock`: Screen locking

**i3wm/X11 Integration Requirements** (legacy):
- `rofi`: Application launcher, window switcher, clipboard menu
- `i3wsr`: Dynamic workspace renaming based on window classes
- `clipcat`: Clipboard history manager with rofi integration
- `alacritty`: Primary terminal emulator
- `i3status` or `i3bar+i3blocks`: Status bar with system information

**Configuration Structure**:
```nix
# Home-manager Sway module: home-modules/desktop/sway.nix
wayland.windowManager.sway = {
  enable = true;
  config = {
    modifier = "Mod4";
    terminal = "ghostty";
    menu = "wofi --show drun";
    # User-specific keybindings, workspace configuration, theme
  };
};
```

**Keyboard Shortcuts (Standard Bindings)**:
- `Win+Return`: Open terminal
- `Win+D` or `Alt+Space`: Application launcher
- `Win+V`: Clipboard history
- `Win+F`: Fullscreen toggle
- `Win+1-9`: Workspace switching
- `Win+Shift+1-9`: Move window to workspace
- `Win+Shift+Q`: Close window
- `Win+H/V`: Split horizontal/vertical

**Rationale**: Tiling window managers maximize screen real estate and minimize mouse usage, critical for remote desktop scenarios where mouse precision is degraded. Sway's modern Wayland protocol provides better security isolation and HiDPI support. i3wm remains supported for X11 deployments requiring xrdp. Keyboard-first workflows improve productivity and reduce dependency on pointer handling. Dynamic workspace naming provides immediate context awareness across workspaces.

### X. Python Development & Testing Standards

Python-based system tooling MUST follow consistent patterns for async programming, testing, type safety, and dependency management.

**Rules**:
- Python version MUST be 3.11+ for all new development (matches existing i3-project daemon)
- Async/await patterns MUST be used for IPC communication and daemon interaction (via i3ipc.aio, asyncio)
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
- Mock patterns MUST be used to isolate tests from external dependencies (daemon, Sway IPC)
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

**Rationale**: Features 017 and 018 established Python as the standard for i3-project system tooling. Consistent patterns across monitoring tools, test frameworks, and daemon extensions reduce cognitive load and improve maintainability. Async patterns are essential for event-driven Sway/i3 IPC integration. Rich library provides consistent terminal UI across all tools. pytest enables comprehensive test coverage including CI/CD integration. Type hints and validation prevent runtime errors and improve code quality.

### XI. Sway/i3 IPC Alignment & State Authority

All Sway/i3-related state queries and window management operations MUST use the native IPC API as the authoritative source of truth.

**Rules**:
- State queries MUST use native IPC message types: GET_WORKSPACES, GET_OUTPUTS, GET_TREE, GET_MARKS
- Workspace-to-output assignments MUST be validated against GET_WORKSPACES response
- Monitor/output configuration MUST be queried via GET_OUTPUTS, not external tools
- Window marking and visibility MUST be verified via GET_TREE and GET_MARKS
- Event subscriptions MUST use SUBSCRIBE IPC message type (window, workspace, output, binding)
- Custom state tracking (daemon, database) MUST be validated against IPC data, not vice versa
- When discrepancies occur between custom state and IPC, IPC data MUST be considered authoritative
- For Sway: use i3ipc-python library (i3ipc.aio for async) or swaymsg for shell scripting
- For i3wm: use i3ipc-python library (i3ipc.aio for async)
- State synchronization MUST be event-driven via IPC subscriptions, not polling
- Diagnostic tools MUST include IPC state in all reports for validation

**Event-Driven Architecture Requirements**:
- Use IPC subscriptions for real-time state updates (window events, workspace changes, output changes)
- Process events asynchronously via asyncio event loops
- Maintain minimal daemon state - query IPC when authoritative state needed
- Implement event handlers with <100ms latency for window marking and state updates
- Use event buffers (circular, max 500 events) for diagnostic history, not authoritative state
- Fail gracefully when IPC connection is lost with auto-reconnection (exponential backoff)

**IPC Message Types (Standard Usage)**:
- `GET_WORKSPACES`: Query workspace list with names, visible status, output assignments
- `GET_OUTPUTS`: Query monitor/output configuration with names, active status, dimensions, workspaces
- `GET_TREE`: Query complete window tree with containers, marks, focus, properties
- `GET_MARKS`: Query all window marks in current session
- `SUBSCRIBE`: Subscribe to events (window, workspace, output, binding, shutdown, tick)
- `COMMAND`: Execute commands (mark windows, move containers, switch workspaces)

**State Validation Pattern**:
```python
# Query Sway's authoritative state
async with i3ipc.aio.Connection() as sway:
    workspaces = await sway.get_workspaces()
    outputs = await sway.get_outputs()
    tree = await sway.get_tree()

    # Validate daemon state against Sway state
    for workspace in workspaces:
        expected_output = workspace.output
        daemon_output = get_daemon_workspace_assignment(workspace.num)
        if expected_output != daemon_output:
            # Sway state is authoritative - update daemon
            sync_daemon_state(workspace.num, expected_output)
```

**Rationale**: Feature 018 identified critical issues when custom state tracking (daemon databases, configuration files) drifts from Sway/i3's actual state. The IPC API is the single source of truth for window management state - workspace assignments, output configuration, window marks, and focus state all originate from the compositor. Event-driven architecture via IPC subscriptions replaced polling-based systems in Feature 015, reducing CPU usage to <1% and eliminating race conditions. All monitoring, testing, and diagnostic tools must align with IPC state to ensure accurate debugging and validation. When building extensions, query IPC to validate assumptions rather than maintaining parallel state that can desync.

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
- ✅ **Polling → Event-driven architecture**: Replaced entire polling system with IPC subscriptions, no backwards compatibility for polling mode
- ✅ **i3wm → Sway migration**: Sway is primary, i3wm remains for specific X11 use cases (not backwards compatibility)
- ❌ **BAD: Adding feature flags for "legacy mode"**: Would violate this principle
- ❌ **BAD: Keeping old code "just in case"**: Would violate this principle
- ❌ **BAD: Gradual migration with dual code paths**: Would violate this principle

**When Replacement is Required**:
- New feature renders existing implementation suboptimal → Replace immediately
- Better architectural pattern emerges → Replace existing pattern completely
- Performance/maintainability improvements available → Replace without preserving old approach
- Simpler solution discovered → Replace complex solution entirely

**Rationale**: This project exists for personal productivity optimization, not as a product with external users dependent on stability. Every line of code maintained for backwards compatibility is technical debt that slows development, complicates architecture, and reduces clarity. The fastest path to optimal solutions is immediate, complete replacement of suboptimal code. This principle accelerates innovation by eliminating the burden of legacy support and ensures the codebase always represents the current best practices without historical baggage. Clean breaks are faster and clearer than gradual migrations with compatibility shims.

### XIII. Deno CLI Development Standards

All new CLI tool development MUST use Deno runtime with TypeScript and heavy reliance on Deno standard library modules.

**Rules**:
- CLI tools MUST be implemented using Deno runtime version 1.40+ for modern standard library features
- Command-line argument parsing MUST use `parseArgs()` from `@std/cli/parse-args` (minimist-style API)
- Interactive prompts MUST use utilities from `@std/cli` (promptSecret for passwords, prompt for input)
- Terminal formatting MUST use ANSI utilities from `@std/cli/unstable-ansi` for colors and escape codes
- String width calculations for terminal display MUST use `unicodeWidth()` from `@std/cli/unicode-width`
- File I/O MUST use Deno standard library modules (`@std/fs`, `@std/path`) where available
- JSON operations MUST use Deno standard library `@std/json` or built-in JSON APIs
- HTTP/networking MUST use Deno standard library `@std/http` or native Deno.serve/fetch APIs
- TypeScript MUST be used with strict type checking enabled (strict mode in deno.json)
- Distribution MUST be via compiled standalone executables (`deno compile`) - no runtime installation required
- Third-party npm packages MAY be used only when Deno std library lacks required functionality
- CLI tools MUST provide `--help` and `--version` flags following standard conventions
- Error messages MUST be user-friendly with actionable guidance (daemon not running, connection failed, etc.)

**Deno Standard Library CLI Module Usage** (from `@std/cli`):
- `parseArgs(args, options)`: Command-line argument parser with support for flags, options, boolean values, defaults, aliases
- `promptSecret(message, options)`: Secure password input with hidden characters
- `prompt(message, options)`: Interactive text input prompting
- `unicodeWidth(str)`: Calculate display width of strings containing Unicode characters (critical for table formatting)
- ANSI escape code utilities: Colors, cursor movement, screen clearing, text styling

**TypeScript Type Safety Requirements**:
- All function signatures MUST include explicit parameter and return types
- Public APIs MUST use interfaces or type definitions for contracts
- Data validation MUST use type guards or runtime validation (Zod recommended for complex schemas)
- Avoid `any` type - use `unknown` with type guards when type is truly dynamic

**Project Structure Pattern**:
```
home-modules/tools/<tool-name>/
├── deno.json                # Deno configuration (tasks, imports, compiler options)
├── main.ts                  # Entry point with parseArgs() CLI handling
├── mod.ts                   # Public API exports
├── src/
│   ├── commands/           # Command implementations
│   ├── models.ts           # Type definitions and interfaces
│   ├── client.ts           # IPC/daemon client logic
│   └── ui/                 # Terminal UI components (if applicable)
├── tests/
│   └── <feature>_test.ts   # Deno.test() test suites
└── README.md               # Module documentation
```

**Example - parseArgs() Usage**:
```typescript
import { parseArgs } from "@std/cli/parse-args";

const args = parseArgs(Deno.args, {
  boolean: ["live", "tree", "table", "json", "version", "help"],
  string: ["project", "format"],
  default: { format: "tree" },
  alias: { h: "help", v: "version" },
});

if (args.help) {
  console.log("Usage: i3pm windows [options]");
  Deno.exit(0);
}
```

**Compilation and Distribution**:
```bash
# Compile to standalone executable
deno compile --allow-net --allow-read --output=i3pm main.ts

# NixOS packaging - use buildDenoApplication or custom derivation
```

**When to Use Deno vs Python**:
- **Use Deno for**: CLI tools, terminal UIs, JSON-RPC clients, standalone utilities, fast startup requirements
- **Use Python for**: Sway/i3 event daemons with i3ipc-python, complex async workflows with asyncio, Rich terminal UIs, pytest-based testing frameworks
- **Migration path**: Replace Python CLI tools with Deno equivalents when performance, distribution, or startup time is critical (e.g., Feature 026 TypeScript/Deno CLI rewrite)

**Rationale**: Feature 026 (TypeScript/Deno CLI Rewrite) establishes Deno as the modern standard for CLI tool development. Deno's built-in TypeScript support eliminates build complexity, the extensive standard library reduces third-party dependencies, and compiled executables remove runtime installation requirements. The `parseArgs()` function from `@std/cli/parse-args` provides a mature, well-documented API for command-line parsing that rivals popular Node.js libraries. Deno's security model (explicit permissions) and fast startup time make it ideal for CLI tools that need to execute quickly and reliably. This principle positions Deno as the replacement for Python in CLI contexts while preserving Python's strengths in daemon/event-driven architectures.

### XIV. Test-Driven Development & Autonomous Testing

All feature development MUST follow test-driven development principles with comprehensive automated testing across the test pyramid, including autonomous user flow testing via UI automation and system state verification.

**Rules**:
- Feature development MUST follow test-first approach: write tests before implementation
- Test pyramid MUST be comprehensive: unit tests (70%), integration tests (20%), end-to-end tests (10%)
- User flow tests MUST simulate real user interactions whenever technically feasible
- Browser-based features MUST use MCP server tools (Playwright, Chrome DevTools) for automated UI testing
- Wayland/Sway UI interactions MUST be tested programmatically via input simulation tools (ydotool, wtype, wl-clipboard)
- When UI simulation is not feasible, state verification MUST be performed via Sway IPC tree queries and daemon state inspection
- For window manager testing, sway-test framework MUST be used (see Principle XV)
- Test execution MUST be autonomous - no manual user intervention except when technically impossible
- Test failures MUST trigger iterative refinement: spec → plan → tasks → implementation → tests → fix → repeat until all tests pass
- Test suites MUST be executable in headless CI/CD environments without human interaction
- Test results MUST provide actionable failure messages with expected vs actual state diffs
- Observability tests MUST verify telemetry emission and trace structure (see Principle XVI)

**Test Pyramid Layers**:

1. **Unit Tests (70% of test suite)**:
   - Test individual functions, classes, and modules in isolation
   - Use mocks/stubs for external dependencies
   - Fast execution (<1ms per test)
   - Examples: Data model validation, utility functions, parsers

2. **Integration Tests (20% of test suite)**:
   - Test component interactions (daemon ↔ IPC, API ↔ database, OTEL ↔ collector)
   - Use real dependencies where feasible, mocks for external services
   - Medium execution speed (<100ms per test)
   - Examples: Daemon IPC communication, file system operations, subprocess interactions, telemetry pipeline

3. **End-to-End Tests (10% of test suite)**:
   - Test complete user workflows from start to finish
   - Use production-like environment (real Sway session, real applications)
   - Slower execution (<5s per test)
   - Examples: Project switch workflow, window management lifecycle, PWA launch and workspace assignment

**User Flow Testing Strategies**:

**Browser Automation (MCP Playwright/Chrome DevTools)**:
```python
# Example: Test PWA launch and workspace assignment
async def test_pwa_launch_workspace_assignment():
    """Test that Claude PWA launches on correct workspace."""
    # Via MCP Playwright server
    page = await browser.new_page()
    await page.goto("https://claude.ai")

    # Verify workspace via Sway IPC
    async with i3ipc.aio.Connection() as sway:
        tree = await sway.get_tree()
        claude_window = find_window_by_class(tree, "FFPWA-01JCYF8Z2")

        assert claude_window.workspace().num == 52, \
            f"Claude PWA on workspace {claude_window.workspace().num}, expected 52"
```

**Wayland Input Simulation (ydotool/wtype)**:
```python
# Example: Test workspace mode navigation via keyboard
async def test_workspace_mode_navigation():
    """Test keyboard-driven workspace navigation."""
    # Simulate CapsLock + digits + Enter
    subprocess.run(["ydotool", "key", "58:1", "58:0"])  # CapsLock press+release
    subprocess.run(["ydotool", "key", "3:1", "3:0"])    # Digit 2
    subprocess.run(["ydotool", "key", "4:1", "4:0"])    # Digit 3
    subprocess.run(["ydotool", "key", "28:1", "28:0"])  # Enter

    # Verify focused workspace via Sway IPC
    await asyncio.sleep(0.2)  # Allow navigation to complete
    async with i3ipc.aio.Connection() as sway:
        workspaces = await sway.get_workspaces()
        focused = next(ws for ws in workspaces if ws.focused)

        assert focused.num == 23, \
            f"Focused workspace is {focused.num}, expected 23"
```

**Sway IPC State Verification** (when UI simulation not possible):
```python
# Example: Verify window environment variable injection (using sway-test framework for structured testing)
async def test_environment_variable_injection():
    """Test that launched applications have I3PM_* environment variables."""
    # Launch application programmatically (not via UI)
    proc = await asyncio.create_subprocess_exec(
        "i3pm", "app", "launch", "vscode",
        env={**os.environ, "I3PM_PROJECT_NAME": "nixos"}
    )
    await proc.wait()

    # Query Sway for new window
    await asyncio.sleep(0.5)  # Allow window creation
    async with i3ipc.aio.Connection() as sway:
        tree = await sway.get_tree()
        vscode_windows = find_windows_by_class(tree, "Code")

        assert len(vscode_windows) > 0, "VS Code window not found"
        window = vscode_windows[-1]  # Get most recent

        # Read environment variables from /proc
        env_vars = read_process_environ(window.pid)

        assert "I3PM_APP_ID" in env_vars, "Missing I3PM_APP_ID"
        assert env_vars["I3PM_APP_NAME"] == "vscode"
        assert env_vars["I3PM_PROJECT_NAME"] == "nixos"
```

**Autonomous Test Execution Requirements**:
- Test suites MUST run without prompting for user input
- Test setup MUST automatically prepare test environment (launch Sway session, start daemon, seed data)
- Test teardown MUST clean up resources (close windows, stop processes, remove temp files)
- Test failures MUST provide reproducible steps and diagnostic data
- Tests MUST be idempotent - safe to run multiple times without side effects
- Tests MUST handle timing issues with explicit waits/retries, not arbitrary sleep()

**Test-Driven Iteration Workflow**:
1. **Write specification** (spec.md) - Define user stories with acceptance criteria
2. **Write tests** (before implementation) - Convert acceptance criteria to executable tests
3. **Run tests** (expect failures) - All tests should fail initially
4. **Implement feature** - Write minimal code to make tests pass
5. **Run tests** (iterate until passing) - Fix code until all tests pass
6. **Refactor** (with test safety net) - Improve code quality while maintaining passing tests
7. **Commit** (only when tests pass) - Never commit failing tests to main branch

**Test Framework Requirements**:

**Python (pytest)**:
```python
# tests/test_window_environment.py
import pytest
from i3pm.services.window_environment import WindowEnvironment

@pytest.mark.asyncio
async def test_window_environment_parsing():
    """Unit test: Parse I3PM_* environment variables."""
    env_dict = {
        "I3PM_APP_ID": "test-app-project-123-456",
        "I3PM_APP_NAME": "test-app",
        "I3PM_SCOPE": "scoped",
        "I3PM_PROJECT_NAME": "project",
    }

    window_env = WindowEnvironment.from_env_dict(env_dict)

    assert window_env.app_id == "test-app-project-123-456"
    assert window_env.app_name == "test-app"
    assert window_env.is_scoped is True
```

**Deno (Deno.test)** - See Principle XV for sway-test framework examples:
```typescript
// tests/window_matcher_test.ts
import { assertEquals } from "@std/assert";
import { matchWindow } from "../src/window_matcher.ts";

Deno.test("matchWindow: matches by I3PM_APP_NAME", async () => {
  const window = {
    pid: 12345,
    environment: {
      I3PM_APP_NAME: "vscode",
      I3PM_APP_ID: "vscode-nixos-123-456",
    },
  };

  const result = await matchWindow(window, "vscode");

  assertEquals(result.matched, true);
  assertEquals(result.matchType, "environment");
});
```

**Wayland Input Simulation Tools**:
- **ydotool**: Low-level input injection (keyboard, mouse) - works on Wayland
- **wtype**: Wayland-native text input tool (simpler alternative to ydotool for text)
- **wl-clipboard**: Clipboard operations (wl-copy, wl-paste) for clipboard testing
- **swaymsg**: Sway IPC commands for window/workspace manipulation

**MCP Server Integration**:
- **Playwright MCP**: Browser automation via MCP server (if available)
- **Chrome DevTools MCP**: Chrome/Chromium browser control (if available)
- Fallback: Direct Playwright/Puppeteer library usage if MCP servers not available

**Test Execution Patterns**:
- Tests MUST be executable via `pytest tests/` or `deno test` with zero configuration
- CI/CD integration MUST run full test suite on every commit
- Test duration MUST be reasonable (<2 minutes for full suite)
- Flaky tests MUST be fixed or disabled (never tolerate intermittent failures)

**Rationale**: Test-driven development ensures features work correctly before deployment, reduces debugging time, and provides confidence during refactoring. Autonomous testing via UI automation (Playwright, ydotool) and state verification (Sway IPC) enables comprehensive validation without manual intervention. This approach scales to CI/CD environments and ensures consistent quality. The test-driven iteration loop (spec → plan → test → implement → fix → repeat) produces robust, well-tested code that meets requirements. MCP server integration (when available) provides standardized browser automation, while Wayland input simulation tools enable desktop UI testing. The sway-test framework (Principle XV) provides structured window manager testing with declarative test definitions.

### XV. Sway Test Framework Standards

All Sway/Wayland window manager testing MUST use the declarative TypeScript/Deno-based sway-test framework for structured, autonomous state verification.

**Rules**:
- Window manager tests MUST be defined in JSON test files using the sway-test schema
- Test definitions MUST be declarative - specifying expected state, not implementation details
- Test execution MUST be autonomous via `sway-test run <test.json>` with no manual intervention
- Multi-mode state comparison MUST be supported: exact (full tree), partial (field-based), assertions (JSONPath), empty (action-only)
- Partial mode MUST be the default for most tests - checking specific properties like focusedWorkspace, windowCount, workspace structure
- Undefined semantics MUST apply: `undefined` in expected state = "don't check" (field ignored), `null` in expected = must match null exactly
- Test results MUST provide detailed diffs with mode indicators, compared/ignored field lists, and contextual "Expected X, got Y" messages
- Sway IPC MUST be the authoritative source of truth for window manager state (GET_TREE, GET_WORKSPACES, GET_OUTPUTS)
- Test framework MUST be implemented in TypeScript with Deno runtime (matching Principle XIII standards)
- Test failures MUST block commits - all window manager tests must pass before merging

**Multi-Mode State Comparison**:

1. **Partial Mode (Recommended - 90% of tests)**:
   - Check specific properties: `focusedWorkspace`, `windowCount`, `workspaces`
   - Ignore unchecked fields automatically (undefined = "don't check")
   - Fast, focused assertions on relevant state
   - Example: `{ "focusedWorkspace": 3, "windowCount": 1 }`

2. **Exact Mode (Full tree validation)**:
   - Compare complete Sway tree structure
   - Triggered by `tree` field in expectedState
   - Use for comprehensive state validation
   - Example: `{ "tree": { "type": "root", "nodes": [...] } }`

3. **Assertions Mode (Advanced JSONPath queries)**:
   - Query-based assertions on nested properties
   - Triggered by `assertions` field in expectedState
   - Use for complex state queries
   - Example: `{ "assertions": [{ "path": "$.nodes[0].focused", "expected": true }] }`

4. **Empty Mode (Action-only validation)**:
   - Validate actions execute without errors
   - No state comparison performed
   - Triggered by empty expectedState object `{}`
   - Use for testing action execution only

**Test Definition Schema**:
```typescript
interface TestCase {
  name: string;                    // Test description
  description?: string;            // Detailed explanation
  tags?: string[];                 // Test categorization
  timeout?: number;                // Max execution time (ms)
  actions: Action[];               // Test actions to execute
  expectedState: ExpectedState;    // State assertions
}

interface ExpectedState {
  // Partial mode (recommended)
  focusedWorkspace?: number;       // Which workspace is focused
  windowCount?: number;            // Total window count
  workspaces?: Array<{             // Workspace-specific assertions
    num?: number;                  // Workspace number
    focused?: boolean;             // Focus state
    visible?: boolean;             // Visibility state
    windows?: Array<{              // Window assertions
      app_id?: string;             // Application ID
      class?: string;              // Window class
      title?: string;              // Window title
      focused?: boolean;           // Focus state
      floating?: boolean;          // Floating state
    }>;
  }>;

  // Exact mode
  tree?: SwayTreeStructure;        // Full tree comparison

  // Assertions mode
  assertions?: PartialMatch[];     // JSONPath queries
}
```

**Example Test - Partial Mode** (Feature 068):
```json
{
  "name": "Firefox launches on workspace 3",
  "description": "Validate PWA workspace assignment",
  "tags": ["workspace-assignment", "firefox", "pwa"],
  "timeout": 5000,
  "actions": [
    {
      "type": "launch_app",
      "params": {
        "app_name": "firefox",
        "workspace": 3,
        "sync": true
      }
    }
  ],
  "expectedState": {
    "focusedWorkspace": 3,
    "windowCount": 1,
    "workspaces": [
      {
        "num": 3,
        "focused": true,
        "windows": [
          {
            "app_id": "firefox",
            "focused": true
          }
        ]
      }
    ]
  }
}
```

**Test Execution**:
```bash
# Run single test
sway-test run tests/test_firefox_workspace.json

# Run test directory
sway-test run tests/workspace-assignment/

# Run with verbose output
sway-test run --verbose tests/test_firefox_workspace.json

# Validate test syntax without execution
sway-test validate tests/*.json
```

**Enhanced Error Messages** (Feature 068):
```
✗ States differ: [PARTIAL mode]

Summary: ~2 modified

Comparing 4 field(s), ignoring 15 field(s)
  Compared: focusedWorkspace, windowCount, workspaces[0].num, workspaces[0].focused

Differences:
  ~ $.focusedWorkspace
    Expected 3, got 1
  ~ $.workspaces[0].focused
    Expected true, got false
```

**State Extraction & Comparison Architecture** (Feature 068):

**StateExtractor Service**:
- Pure functional design - no side effects
- Extracts only requested fields from Sway tree
- Supports nested structures (workspaces → windows)
- Uses Sway IPC GET_TREE as authoritative source

**StateComparator Service**:
- Multi-mode dispatch based on expectedState fields
- Undefined semantics: `undefined` = skip comparison (field ignored)
- Null semantics: `null` = must match null exactly (field compared)
- Tracks compared vs ignored fields for enhanced error messages

**Test Framework File Structure**:
```
home-modules/tools/sway-test/
├── deno.json                          # Deno configuration
├── main.ts                            # CLI entry point
├── src/
│   ├── commands/
│   │   ├── run.ts                     # Test runner (multi-mode dispatch)
│   │   └── validate.ts                # Test validation
│   ├── services/
│   │   ├── state-extractor.ts         # Feature 068: Partial state extraction
│   │   ├── state-comparator.ts        # Multi-mode comparison
│   │   ├── sway-client.ts             # Sway IPC client
│   │   └── action-executor.ts         # Test action execution
│   ├── models/
│   │   ├── test-case.ts               # Test definition schema
│   │   ├── test-result.ts             # Test result types
│   │   └── state-snapshot.ts          # Sway state types
│   └── ui/
│       ├── diff-renderer.ts           # Feature 068: Enhanced error messages
│       └── reporter.ts                # Test result reporting
└── tests/
    └── sway-tests/                    # Example test cases
```

**Integration with Test-Driven Development**:
- Write sway-test JSON definitions BEFORE implementing window manager features
- Run tests during development to validate behavior
- Tests serve as executable documentation of expected window manager behavior
- Automated CI/CD execution via `sway-test run tests/**/*.json`

**Undefined Semantics - Critical Design Principle** (Feature 068):
```json
// This test checks ONLY focusedWorkspace and workspaces[0].num
// All other fields (windowCount, workspace.visible, workspace.name, etc.) are IGNORED
{
  "expectedState": {
    "focusedWorkspace": 1,
    "workspaces": [
      { "num": 1 }
    ]
  }
}
```

**Field Tracking for Debugging** (Feature 068):
```
Comparing 2 field(s), ignoring 0 field(s)
  Compared: focusedWorkspace, workspaces[0].num
  Ignored: (no fields ignored)
```

**When to Use Each Mode**:
- **Partial mode**: Default for most tests - validate specific properties (focusedWorkspace, window count, workspace structure)
- **Exact mode**: Comprehensive validation of complete Sway tree (use sparingly, fragile to irrelevant changes)
- **Assertions mode**: Complex queries on nested properties (advanced use cases)
- **Empty mode**: Validate action execution without state checks (setup/teardown, error testing)

**Rationale**: Feature 068 fixed critical bugs in state comparison and established the sway-test framework as the standard for declarative window manager testing. The multi-mode comparison system provides flexibility: partial mode for focused assertions (90% of tests), exact mode for comprehensive validation, assertions mode for complex queries, and empty mode for action-only testing. Undefined semantics (`undefined` = "don't check") enable precise control over which fields matter in each test. Enhanced error messages with mode indicators, field tracking, and contextual diffs dramatically improve debugging speed. The framework follows Principle XIII (Deno/TypeScript standards) and Principle XI (Sway IPC authority), ensuring consistency with project architecture. Declarative JSON test definitions enable autonomous execution, version control, and clear documentation of expected window manager behavior.

### XVI. Observability & Telemetry Standards

All system components with monitoring requirements MUST emit standardized telemetry via OpenTelemetry protocols, collected through a unified Grafana Alloy pipeline.

**Rules**:
- Telemetry collection MUST use Grafana Alloy as the unified local collector
- All AI CLI tools (Claude Code, Codex CLI, Gemini CLI) MUST emit or have synthesized OTEL traces
- Non-native OTEL sources (Codex, Gemini) MUST use interceptor scripts to synthesize coherent traces
- Session correlation MUST use `session.id` as the primary join key across traces, metrics, and logs
- Trace hierarchy MUST follow: Session → Turn → LLM Call/Tool spans
- Remote telemetry export MUST target the Kubernetes LGTM stack (Tempo/Mimir/Loki)
- Local monitoring (EWW widgets) MUST function when remote stack is offline (graceful degradation)
- Span metrics MUST be derived via `otelcol.connector.spanmetrics` for RED metrics with exemplars
- Telemetry MUST NOT introduce high-cardinality series (exclude `span.name` from metrics dimensions)
- Subagent traces MUST include span links and `claude.parent_session_id` for cross-trace correlation

**Telemetry Architecture**:
```
AI CLIs → Alloy :4318 → [batch] → otel-ai-monitor :4320 (local EWW)
                               → K8s OTEL Collector (remote)
System  → node exporter → Alloy → Mimir (K8s)
Journald → Alloy → Loki (K8s)
```

**Service Ports**:
| Service | Port | Purpose |
|---------|------|---------|
| grafana-alloy | 4318 (OTLP HTTP), 12345 (UI) | Unified telemetry collector |
| otel-ai-monitor | 4320 | Local AI session tracking for EWW (all CLIs) |
| grafana-beyla | - | eBPF auto-instrumentation (optional) |
| pyroscope-agent | - | Continuous profiling (optional) |

**AI CLI Telemetry Patterns**:

**Claude Code** (native OTEL):
- Uses Node.js interceptor (`scripts/minimal-otel-interceptor.js`) for trace synthesis
- Session ID hydrated via SessionStart hook
- Turn boundaries from UserPromptSubmit + Stop hooks
- Subagent traces linked via Task tool spans

**Codex CLI** (synthesized traces):
- OTEL logs routed through `scripts/codex-otel-interceptor.js`
- Synthesizes Session → Turn → LLM/Tool trace hierarchy
- Uses `notify` hook for accurate turn boundaries
- Normalizes `conversation.id` → `session.id` for correlation

**Gemini CLI** (synthesized traces):
- OTEL configured via `~/.gemini/settings.json`
- Routed through `scripts/gemini-otel-interceptor.js`
- Synthesizes traces from log events (`gemini_cli.user_prompt`, `gemini_cli.api_*`, `gemini_cli.tool_call`)
- No notify hook - uses log event boundaries

**Trace Hierarchy Standard**:
```
Claude Code Session (root)
├── Turn #1: [user prompt]
│   ├── LLM Call: claude-3-opus
│   ├── Tool: Read file
│   └── Tool: Edit file
├── Turn #2: [user prompt]
│   ├── LLM Call: claude-3-opus
│   └── Task (subagent)
│       └── [linked to subagent trace]
└── ...
```

**Grafana Correlation Queries**:
- By session: `{session.id="abc123"}`
- By provider: `{service.name=~"claude-code|codex|gemini"}`
- By model: `{gen_ai.request.model="gpt-4o"}`

**Interceptor Configuration Knobs**:
- `OTEL_INTERCEPTOR_TURN_BOUNDARY_MODE`: `auto|hooks|heuristic`
- `OTEL_INTERCEPTOR_TURN_IDLE_END_MS`: Debounce window for heuristic mode (default: 1500)
- `OTEL_INTERCEPTOR_SESSION_ID_POLICY`: `buffer|eager` (default: buffer)
- `OTEL_INTERCEPTOR_INJECT_TRACEPARENT`: Enable W3C trace context injection (for Beyla correlation)

**Graceful Degradation**:
- Local AI monitoring (EWW widgets) works when K8s offline
- Remote telemetry queued in 100MB memory buffer
- Automatic retry with exponential backoff
- Alloy live debugging UI at http://localhost:12345

**NixOS Configuration Pattern**:
```nix
let
  tailnet = "tail286401.ts.net";
  host = config.networking.hostName;
  cluster = if builtins.elem host [ "ryzen" "thinkpad" ] then host else "ryzen";
  tsServiceUrl = name: "https://${name}-${cluster}.${tailnet}";
in
services.grafana-alloy = {
  enable = true;
  k8sEndpoint = tsServiceUrl "otel-collector";
  lokiEndpoint = tsServiceUrl "loki";
  mimirEndpoint = tsServiceUrl "mimir";
  enableNodeExporter = true;
  enableJournald = true;
  journaldUnits = [ "grafana-alloy.service" "otel-ai-monitor.service" ];
};
```

**Testing Observability** (integration with Principle XIV):
- Unit tests: Validate span structure, attribute population, trace context propagation
- Integration tests: Verify OTLP export to collector, session correlation across signals
- E2E tests: Confirm traces appear in Grafana with correct hierarchy

**Rationale**: Features 129, 130, 131, and 125 established a comprehensive observability stack for this project. All AI CLI tools now emit or have synthesized OTEL telemetry, enabling unified monitoring in Grafana. The `session.id` join key correlates traces, metrics, and logs for debugging AI workflows. Trace synthesis for non-native OTEL sources (Codex, Gemini) ensures consistent trace hierarchy regardless of provider. Local-first architecture via otel-ai-monitor enables EWW widget functionality even when the remote Kubernetes stack is unavailable. Span metrics with exemplars provide "click from metric to trace" functionality in Grafana. This observability foundation supports debugging, performance analysis, and cost tracking across all AI tooling.

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
- Hetzner: Sway tiling window manager, VNC multi-session access, Tailscale VPN, development tools, wl-clipboard
- M1: ARM64 optimizations, Wayland session (for native display), Retina display scaling, requires `--impure` flag
- Containers: Size constraints (<100MB minimal, <600MB development)

**Desktop Environment Transitions**:
When migrating desktop environments (e.g., KDE Plasma → i3wm → Sway):
1. Research target environment's compatibility with existing tools and workflows
2. Evaluate display server requirements (X11 vs Wayland) based on remote desktop needs
3. For remote desktop scenarios: Prefer Wayland with wayvnc or X11 with xrdp
4. For native hardware: Prefer Wayland for better HiDPI and modern features
5. Test migration on reference platform first
6. Document configuration patterns and module structure
7. Validate all critical integrations (1Password, terminal tools, browser extensions, clipboard)
8. Update platform testing requirements to reflect new environment
9. Create migration documentation in `docs/MIGRATION.md`

**X11 vs Wayland Decision Criteria**:
- **Choose Wayland when**:
  * Primary use case is native hardware or VNC remote access
  * HiDPI scaling and modern input methods are priorities
  * Security isolation between applications is required
  * Native touchpad gestures are important (e.g., M1 Mac)
- **Choose X11 when**:
  * Primary use case is RDP multi-session (xrdp)
  * Legacy application compatibility is critical
  * Mature tool compatibility is required (older screen sharing, recording)

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
- VNC/RDP session integration for persistent authentication state

### SSH Hardening

SSH access MUST use key-based authentication with rate limiting and fail2ban integration.

**Rules**:
- Password authentication MUST be disabled for SSH
- SSH keys MUST be managed via 1Password SSH agent
- Rate limiting MUST be configured on public-facing systems
- Fail2ban MUST be enabled on Hetzner and other exposed servers
- Tailscale VPN MUST be the primary access method for remote systems
- VNC/RDP authentication MAY use password-based access (separate from SSH) with optional SSH key support

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
- Prefer module-specific package definitions for better encapsulation (e.g., `modules/desktop/sway.nix` includes wofi, waybar)
- Use system packages for tools required by multiple modules
- Use user packages for development tools and personal utilities
- Use target packages ONLY for platform-specific requirements (e.g., wsl.exe on WSL)
- Avoid duplicate package declarations across modules

**Best Practice - Module Package Scoping**:
```nix
# modules/desktop/sway.nix
config = mkIf cfg.enable {
  environment.systemPackages = with pkgs; [
    cfg.package      # Sway itself
    ghostty          # Terminal for Sway
    wofi             # Application launcher
  ] ++ cfg.extraPackages;  # Allow extension
};
```

## Testing & Validation Standards

### Automated Testing Requirements

Python-based system tooling MUST include comprehensive automated tests for functionality validation and regression prevention.

**Rules**:
- All Python modules MUST have pytest-based unit tests for data models and business logic
- Integration tests MUST validate daemon communication, Sway IPC interaction, and state synchronization
- Test scenarios MUST simulate real user workflows (project lifecycle, window management, monitor configuration)
- Tests MUST support headless operation for CI/CD environments
- Mock implementations MUST be provided for external dependencies (daemon, Sway IPC socket)
- Test reports MUST be output in machine-readable format (JSON) for CI/CD parsing
- Automated test suites MUST execute in under 10 seconds for complete workflow validation
- Failed tests MUST report expected vs actual state with detailed diff information
- Test frameworks MUST use tmux for multi-pane monitoring during manual interactive testing

**Test Coverage Requirements**:
- **Unit tests**: Data models, formatters, validators, business logic (>80% coverage target)
- **Integration tests**: IPC communication, daemon interaction, state queries
- **Contract tests**: JSON-RPC API endpoints, Sway IPC message types
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
│   └── test_sway_ipc.py
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
- Diagnostic capture MUST include: current state snapshot, recent event history (500 events), Sway tree structure, complete Sway IPC state (outputs, workspaces, marks)
- State validation MUST compare custom daemon state against Sway IPC authoritative state
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
# home-modules/tools/wl-clipboard.nix
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [ wl-clipboard ];

  # Ensure wl-copy/wl-paste available in user environment
  home.sessionVariables = {
    # Wayland clipboard integration
  };
}
```

### Configuration File Generation

Configuration files MUST be generated declaratively, not copied from external sources.

**Rules**:
- Sway config MUST be generated via home-manager `wayland.windowManager.sway` or `xdg.configFile`
- i3 config MUST be generated via `environment.etc."i3/config".text` (system-level) or `xdg.configFile."i3/config".text` (user-level)
- Dotfiles MUST be generated via home-manager's `home.file` or `xdg.configFile`
- Template-based generation MUST use Nix string interpolation with `${}` for variable substitution
- Binary paths MUST use `${pkgs.package}/bin/binary` format for reproducibility
- Scripts MUST be generated with proper shebang and execute permissions

**Example**:
```nix
wayland.windowManager.sway.config = {
  modifier = "Mod4";
  terminal = "${pkgs.ghostty}/bin/ghostty";
  menu = "${pkgs.wofi}/bin/wofi --show drun";
};
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
- ✅ Tiling WM standards - Sway/i3 configuration, keyboard-first workflows, workspace isolation
- ✅ Python standards - async patterns, pytest testing, type hints, Rich UI
- ✅ Sway/i3 IPC alignment - state queries via native IPC, event-driven architecture
- ✅ Forward-only development - optimal solutions without legacy compatibility preservation
- ✅ Test-driven development - tests written before implementation, autonomous test execution
- ✅ Sway test framework - declarative JSON tests for window manager validation
- ✅ Observability standards - OTEL telemetry via Grafana Alloy, AI CLI tracing

### Complexity Justification

Any violation of simplicity principles (e.g., adding a 5th platform target, creating deep inheritance hierarchies, introducing abstraction layers) MUST be justified by documenting:
- **Current Need**: Specific problem requiring the complexity
- **Simpler Alternative Rejected**: Why simpler approaches were insufficient
- **Long-term Maintenance**: How the complexity will be managed and documented

**Version**: 1.8.0 | **Ratified**: 2025-10-14 | **Last Amended**: 2025-12-22
