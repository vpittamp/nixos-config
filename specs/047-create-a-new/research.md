# Research: Dynamic Sway Configuration Management Architecture

**Feature**: 047-create-a-new
**Date**: 2025-10-29
**Status**: Complete

## Overview

This research resolves technical unknowns for implementing hot-reloadable configuration management in Sway window manager. All decisions leverage existing i3pm daemon architecture patterns established in Features 015, 035, 037, 038, 041.

## Research Questions & Decisions

### Q1: Configuration File Format Selection

**Decision**: TOML for keybindings, JSON for window rules and workspace assignments

**Rationale**:
- TOML provides superior human readability for keybinding syntax (e.g., `Mod+Return = "exec terminal"`)
- JSON better represents structured data (window rules with nested criteria, workspace arrays)
- Both formats have robust Python parsing libraries (built-in `json`, `toml` in stdlib since 3.11)
- Existing i3pm daemon uses JSON for project config - maintains consistency for structured data
- TOML comments support inline documentation for keybindings

**Alternatives Considered**:
- **Pure JSON**: Rejected due to poor readability for keybinding definitions (no comments, verbose syntax)
- **Pure TOML**: Rejected due to complexity representing nested window rule criteria
- **YAML**: Rejected due to indentation sensitivity, parsing ambiguity, security concerns (arbitrary code execution)

**Implementation**: Use `tomllib` (Python 3.11+) for TOML, `json` module for JSON

---

### Q2: Configuration Validation Strategy

**Decision**: JSON Schema for structural validation + custom semantic validators

**Rationale**:
- JSON Schema provides standardized validation with clear error messages
- Python `jsonschema` library mature and well-documented
- Custom validators handle semantic rules (e.g., workspace numbers exist, app_id references valid applications)
- Validation can run in daemon (reload time) and CLI (pre-commit)
- Matches existing pattern in i3pm daemon for data validation (Pydantic models)

**Alternatives Considered**:
- **Pydantic models only**: Rejected because TOML/JSON files need standalone validation before Python object creation
- **Custom validator from scratch**: Rejected due to reinventing standardized schema validation
- **No validation**: Rejected - SC-006 requires 100% syntax error detection

**Implementation**:
- JSON schemas stored in `~/.config/sway/schemas/` (auto-generated from Pydantic models)
- `jsonschema.validate()` for structural validation
- Custom semantic validators check against Sway IPC state

---

### Q3: Keybinding Hot-Reload Mechanism

**Decision**: Sway IPC `reload` command for keybindings, daemon-managed for window rules

**Rationale**:
- Sway's `reload` command re-reads config file and applies keybindings atomically (<100ms)
- Daemon generates merged config file at `~/.config/sway/config` (Nix base + TOML overrides)
- Window rules applied dynamically via Sway IPC `for_window` equivalents (handled by daemon)
- Preserves Sway's native keybinding parser - no custom keybinding engine needed
- Atomic reload prevents partial state (FR-011)

**Alternatives Considered**:
- **Per-keybinding IPC commands**: Rejected - Sway lacks individual keybinding update API
- **Daemon-only keybinding handling**: Rejected - duplicates Sway's robust parsing, adds complexity
- **Full Sway restart**: Rejected - disrupts windows, fails SC-009 (no user input disruption)

**Implementation**:
- Daemon watches `~/.config/sway/keybindings.toml` for changes
- On change: merge with Nix base config, write to `~/.config/sway/config`, execute `swaymsg reload`
- Fallback on parse error: retain previous config, display error to user

---

### Q4: Project-Specific Window Rule Application

**Decision**: Extend existing daemon window event handler with rule engine

**Rationale**:
- Existing daemon already handles `window::new` events (Feature 015, 041)
- Rule engine queries active project, loads project-specific rules, applies via Sway IPC
- Leverages existing PendingLaunch correlation (Feature 041) for accurate window matching
- Rules stored in project JSON files (`~/.config/sway/projects/<name>.json`)
- Matches i3pm daemon pattern for project-scoped behavior

**Alternatives Considered**:
- **Static Sway for_window rules**: Rejected - can't adapt to project context dynamically
- **Separate rule daemon**: Rejected - duplicates existing event handling infrastructure
- **Pre-launch rule injection**: Rejected - race conditions, doesn't handle manual window creation

**Implementation**:
- Add `window_rules` field to project JSON schema
- Rule engine runs on `window::new` after project mark applied
- Rules format: `{ "criteria": { "app_id": "calculator" }, "actions": ["floating enable"] }`
- Apply rules via Sway IPC command: `swaymsg [criteria] actions`

---

### Q5: Configuration Rollback Strategy

**Decision**: Git-based versioning with symlink swapping for instant rollback

**Rationale**:
- `~/.config/sway/` already version-controlled in `/etc/nixos` repository (assumption from Constitution Principle VI)
- Rollback = `git checkout <commit>` + daemon reload trigger
- Symlink pattern enables atomic config swap (<10ms)
- Integrates with existing git workflow for NixOS config
- No custom versioning system needed - git provides timestamps, diffs, commit messages

**Alternatives Considered**:
- **Copy-based versioning**: Rejected - slower, uses more disk space, manual cleanup needed
- **Database-backed versioning**: Rejected - overkill for text files, adds dependency
- **No rollback**: Rejected - violates FR-009, SC-007 requirements

**Implementation**:
- Config files symlinked from git repo: `~/.config/sway/keybindings.toml -> /etc/nixos/user-config/sway/keybindings.toml`
- `i3pm config rollback <commit>`: checkout commit, send daemon reload IPC
- `i3pm config list-versions`: parse git log for recent config commits

---

### Q6: Configuration Precedence & Conflict Resolution

**Decision**: Documented three-tier precedence: Nix base (lowest) → Runtime config (medium) → Project overrides (highest)

**Rationale**:
- Nix base provides system defaults, minimal change for standard workflows
- Runtime config allows user customization without rebuild
- Project overrides enable context-specific behavior (highest priority)
- Clear precedence prevents ambiguity (FR-007)
- Conflicts logged with warning, higher priority wins

**Alternatives Considered**:
- **Flat precedence (Nix OR runtime, no hybrid)**: Rejected - loses NixOS integration benefits
- **User-configurable precedence**: Rejected - adds complexity, increases confusion
- **Error on conflict**: Rejected - too restrictive, prevents gradual overrides

**Implementation**:
- Config merger module loads: Nix base → apply runtime overrides → apply project overrides
- Conflict detection: log warning when same key defined at multiple levels
- `i3pm config show --sources` displays precedence for each setting

---

### Q7: Validation Performance Optimization

**Decision**: Lazy validation on file change, cached schemas, async validation

**Rationale**:
- JSON Schema validation typically <50ms for small configs (50 keybindings, 20 rules)
- Schemas cached in memory after first load
- Async validation doesn't block daemon event loop
- File watcher triggers validation only on actual changes
- Meets SC-002 constraint (<3 seconds for reload, validation is <500ms subset)

**Alternatives Considered**:
- **Validation on every config access**: Rejected - unnecessary overhead
- **No caching**: Rejected - reloading schemas adds ~10ms per validation
- **Synchronous validation**: Rejected - blocks daemon during validation

**Implementation**:
- Use `watchdog` library for file change detection
- Validation runs in asyncio task, doesn't block event loop
- Schemas loaded once at daemon startup, cached in-memory

---

### Q8: Atomic Configuration Reload

**Decision**: Two-phase commit pattern (validate → apply) with automatic rollback on failure

**Rationale**:
- Phase 1: Validate all config files, check semantic consistency, merge
- Phase 2: Apply merged config atomically (write + swaymsg reload OR daemon IPC)
- Failure in Phase 1: reject changes, keep current config, display errors
- Failure in Phase 2: automatically rollback to previous version (git revert + reload)
- Satisfies FR-011 (atomic reload), SC-003 (95% success rate)

**Alternatives Considered**:
- **Best-effort application**: Rejected - partial state violates FR-011
- **Manual rollback**: Rejected - doesn't meet SC-007 (<3 second automatic rollback)
- **Lock file for coordination**: Rejected - adds complexity, watchdog sufficient

**Implementation**:
- Transaction context manager: `with ConfigTransaction():`
- Validation errors abort before any writes
- Apply errors trigger automatic `git revert HEAD` + reload
- Success: commit changes to git with auto-generated message

---

## Technology Stack Summary

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Configuration Format | TOML (keybindings), JSON (rules) | Human-readable TOML for linear data, JSON for structured nested data |
| Validation | JSON Schema + custom validators | Standardized structural validation, semantic validation via Sway IPC queries |
| Hot-Reload | Sway IPC `reload` + daemon rules engine | Leverages native Sway parsing, daemon extends with dynamic behavior |
| Versioning | Git | Already in use for /etc/nixos, provides timestamps/diffs/rollback |
| File Watching | `watchdog` Python library | Async file change detection, widely used, stable |
| Parsing | `tomllib` (stdlib), `json` (stdlib) | No external dependencies for parsing |
| IPC Client | `i3ipc.aio` (existing) | Existing daemon dependency, Sway-compatible |

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Configuration validation misses edge case | Comprehensive test suite with 80%+ semantic error detection target (SC-006) |
| Sway reload disrupts active input | Sway's reload is input-safe, tested extensively in i3 workflows |
| Git merge conflicts in config | User training, config files are append-mostly (keybindings, rules grow over time) |
| Daemon crash during reload | Systemd watchdog restarts daemon, last-known-good config preserved |
| Performance degradation | Async validation, lazy loading, caching, <2s reload budget with margin |

## Open Questions (Resolved)

All technical unknowns resolved. Ready to proceed to Phase 1 (Data Model & Contracts).
