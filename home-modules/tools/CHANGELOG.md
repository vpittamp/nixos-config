# Changelog

All notable changes to i3 Project Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2025-10-21

### Added

**Phase 6: Real-Time Window Inspection TUI**
- Window inspector TUI with real-time property display
- Three inspection modes: click selection, focused window, by ID
- Live mode with i3 event subscriptions for property updates
- Classification actions via keyboard shortcuts (s/g/u/p)
- Pattern match display and creation
- Copy WM_CLASS to clipboard functionality
- PropertyDisplay widget with change highlighting (200ms yellow flash)
- WindowProperties data model with classification reasoning

**Phase 7: Polish & Documentation**
- JSON output format for all CLI commands (--json flag)
- Dry-run mode for mutation commands (--dry-run flag)
- Consistent error messages with remediation steps (SC-036 format)
- OutputFormatter for unified JSON/rich text output
- ProjectJSONEncoder for custom type serialization
- DryRunResult/DryRunChange for preview-before-apply

**New CLI Commands**:
- `i3pm app-classes inspect` - Launch window inspector TUI
  - `--click`: Select window by clicking (default)
  - `--focused`: Inspect currently focused window
  - `--live`: Enable auto-updates on i3 events
  - `window_id`: Inspect by i3 container ID

**New Dependencies**:
- `xdotool` - Window selection for inspector
- `xorg.xprop` - Window property extraction
- `xvfb-run` - Virtual framebuffer for app detection
- `pytest-textual` - TUI testing framework

### Changed
- Version bumped from 0.2.0 to 0.3.0
- Development status: Alpha → Beta
- All commands now support `--json` flag for machine-readable output
- Mutation commands now support `--dry-run` flag for safe exploration
- Error messages now include remediation steps

### Fixed
- i3ipc async connection management (no context manager protocol)
- Inspector TUI layout and reactive property updates
- JSON encoder handling of datetime and Path objects

## [0.2.0] - 2025-10-15

### Added

**Phase 5: Classification Wizard TUI**
- Interactive TUI for bulk application classification
- Multi-select with keyboard shortcuts (s/g/u)
- Real-time filtering (all/unclassified/scoped/global)
- Sorting by name, class, status, confidence
- Auto-accept high-confidence suggestions
- Batch operations with undo support
- Live statistics and progress tracking

**App Discovery & Classification**:
- Automatic app discovery from .desktop files
- ML-based classification suggestions with confidence scores
- Pattern-based classification rules (glob/regex)
- Xvfb-based window class detection for apps without WM_CLASS

**CLI Commands**:
- `i3pm app-classes wizard` - Interactive classification wizard
- `i3pm app-classes discover` - Scan system for apps
- `i3pm app-classes detect` - Xvfb window class detection
- `i3pm app-classes suggest` - ML classification suggestions
- `i3pm app-classes auto-classify` - Auto-apply suggestions
- `i3pm app-classes add-pattern` - Pattern rule creation
- `i3pm app-classes list-patterns` - View pattern rules
- `i3pm app-classes remove-pattern` - Delete pattern rules
- `i3pm app-classes test-pattern` - Test pattern matching

### Changed
- Event-driven daemon replaced polling system
- App classification now supports pattern rules
- Improved project switching performance (<100ms)

## [0.1.0] - 2025-10-01

### Added

**Initial Release**

**Core Features**:
- Event-driven i3 project management daemon
- Real-time window marking with project context
- Automatic window show/hide based on active project
- Multi-monitor workspace distribution

**CLI Commands**:
- `i3pm switch <project>` - Switch to project
- `i3pm current` - Show active project
- `i3pm clear` - Return to global mode
- `i3pm list` - List all projects
- `i3pm create` - Create new project
- `i3pm show` - Display project details
- `i3pm edit` - Update project configuration
- `i3pm delete` - Remove project
- `i3pm validate` - Validate configuration
- `i3pm status` - Daemon health and statistics
- `i3pm events` - View daemon events
- `i3pm windows` - List tracked windows

**Daemon Features**:
- i3 IPC event subscriptions (window, workspace, tick)
- JSON-RPC IPC server for CLI communication
- Systemd user service with socket activation
- <100ms window marking latency
- <1% CPU usage, <15MB memory footprint

**Application Classification**:
- Scoped classes (project-specific windows)
- Global classes (visible in all projects)
- Manual classification via CLI
- Configuration stored in ~/.config/i3/app-classes.json

**Project Management**:
- JSON-based project configuration
- Workspace preferences per project
- Auto-launch applications on switch
- Saved layout support
- Project directory association

[0.3.0]: https://github.com/vpittamp/nixos/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/vpittamp/nixos/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/vpittamp/nixos/releases/tag/v0.1.0
