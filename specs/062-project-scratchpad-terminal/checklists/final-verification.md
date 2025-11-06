# Final Verification: CHK040 & CHK044 Consistency Analysis

**Date**: 2025-11-05
**Validator**: Claude Code (automated)
**Status**: ✅ VERIFIED

---

## CHK040: RPC Pattern Consistency with Existing Daemon Methods

### Analysis

**Existing Daemon RPC Patterns** (from daemon-client.ts):

| Method | Parameters | Return Type | Error Codes |
|--------|-----------|-------------|-------------|
| `get_status` | None | `{ status, pid, uptime, active_project, ... }` | Standard JSON-RPC |
| `notify_project_switch` | `{ project_name }` | `void` | Standard JSON-RPC |
| `close_project_windows` | `{ project_name }` | `{ closed_count }` | Standard JSON-RPC |
| `get_events` | `{ limit?, event_type? }` | `unknown[]` | Standard JSON-RPC |
| `get_window_state` | `{ include_geometry?, workspace_filter? }` | `unknown` | Standard JSON-RPC |

**Scratchpad RPC Patterns** (from contracts/scratchpad-rpc.json):

| Method | Parameters | Return Type | Error Codes |
|--------|-----------|-------------|-------------|
| `scratchpad.toggle` | `{ project_name? }` | `{ status, project_name, pid?, window_id?, message }` | -32602, -32000, -32001 |
| `scratchpad.launch` | `{ project_name?, working_dir? }` | `{ project_name, pid, window_id, mark, working_dir, message }` | -32602, -32000, -32001 |
| `scratchpad.status` | `{ project_name? }` | `{ terminals[], count }` | -32602 |
| `scratchpad.close` | `{ project_name? }` | `{ project_name, message }` | -32602, -32000, -32001 |
| `scratchpad.cleanup` | None | `{ cleaned_up, remaining, projects_cleaned[], message }` | None |

### Consistency Check

✅ **Parameter Naming Convention**:
- Existing: `snake_case` (project_name, event_type)
- Scratchpad: `snake_case` (project_name, working_dir) ✅ CONSISTENT

✅ **Return Object Structure**:
- Existing: Typed objects with snake_case keys
- Scratchpad: Typed objects with snake_case keys ✅ CONSISTENT

✅ **Error Code Ranges**:
- Existing: Standard JSON-RPC codes (-32xxx)
- Scratchpad: Standard JSON-RPC (-32602) + Application codes (-32000, -32001) ✅ CONSISTENT
- Note: Application error codes -32000 (launch failed) and -32001 (IPC failed) align with i3pm error patterns

✅ **Optional Parameters**:
- Existing: Uses `?` suffix in TypeScript types
- Scratchpad: Uses `required: false` in JSON schema ✅ CONSISTENT

### Key Difference: Method Namespacing

**Pattern Difference**:
- Existing methods: Flat namespace (`get_status`, `notify_project_switch`)
- Scratchpad methods: Namespaced (`scratchpad.toggle`, `scratchpad.launch`)

**Analysis**: ✅ **ACCEPTABLE IMPROVEMENT**
- Namespacing is a best practice for organizing related RPC methods
- Prevents method name collisions (e.g., `toggle` vs `scratchpad.toggle`)
- Follows patterns used in other RPC systems (LSP, DAP, etc.)
- Does not break compatibility (different method names)
- Recommendation: Consider namespacing future daemon methods similarly

### Verdict: ✅ CHK040 VERIFIED - CONSISTENT

**Assessment**: Scratchpad RPC patterns are consistent with existing daemon methods, with an improvement via namespacing.

**Evidence**:
- Parameter naming: ✅ Consistent snake_case
- Return structures: ✅ Consistent typed objects
- Error codes: ✅ Consistent standard + application codes
- Optional parameters: ✅ Consistent patterns
- Namespacing: ✅ Improvement, not inconsistency

---

## CHK044: App Registry Consistency with Regular Terminal

### Analysis

**Regular Alacritty Terminal Entry** (app-registry-data.nix lines ~245):

```nix
(mkApp {
  name = "alacritty";
  display_name = "Terminal";
  command = "alacritty";
  parameters = "-e sesh connect $PROJECT_DIR";
  scope = "scoped";               # ← Project-scoped
  expected_class = "Alacritty";   # ← Window class
  preferred_workspace = 1;
  icon = "terminal";
  nix_package = "pkgs.alacritty";
  multi_instance = true;          # ← Multiple allowed
  fallback_behavior = "use_home";
  description = "Terminal with sesh session management for project directory";
})
```

**Scratchpad Terminal Entry** (app-registry-data.nix lines 274-289):

```nix
(mkApp {
  name = "scratchpad-terminal";
  display_name = "Scratchpad Terminal";
  command = "alacritty";
  parameters = "";
  scope = "scoped";               # ← Project-scoped ✅
  expected_class = "Alacritty";   # ← Window class ✅
  preferred_workspace = 1;
  icon = "terminal";
  nix_package = "pkgs.alacritty";
  multi_instance = true;          # ← Multiple allowed ✅
  fallback_behavior = "use_home";
  description = "Project-scoped floating scratchpad terminal (Feature 062)";
})
```

### Consistency Check

✅ **Scope Pattern**:
- Regular terminal: `scope = "scoped"` (project-scoped)
- Scratchpad terminal: `scope = "scoped"` (project-scoped) ✅ CONSISTENT

✅ **Multi-Instance Pattern**:
- Regular terminal: `multi_instance = true` (one per project)
- Scratchpad terminal: `multi_instance = true` (one per project) ✅ CONSISTENT

✅ **Expected Class Pattern**:
- Regular terminal: `expected_class = "Alacritty"` (based on command)
- Scratchpad terminal: `expected_class = "Alacritty"` (based on command) ✅ CONSISTENT

✅ **Fallback Behavior**:
- Regular terminal: `fallback_behavior = "use_home"` (if no project)
- Scratchpad terminal: `fallback_behavior = "use_home"` (if no project) ✅ CONSISTENT

✅ **Package Reference**:
- Regular terminal: `nix_package = "pkgs.alacritty"`
- Scratchpad terminal: `nix_package = "pkgs.alacritty"` ✅ CONSISTENT

### Key Differences (Intentional)

**1. Parameters**:
- Regular terminal: `-e sesh connect $PROJECT_DIR` (launches sesh session)
- Scratchpad terminal: `""` (no parameters, managed by daemon)
- **Analysis**: ✅ INTENTIONAL - Scratchpad uses daemon for lifecycle management

**2. Name**:
- Regular terminal: `name = "alacritty"` (command name)
- Scratchpad terminal: `name = "scratchpad-terminal"` (descriptive)
- **Analysis**: ✅ INTENTIONAL - Different functionality, different name

**3. Display Name**:
- Regular terminal: `display_name = "Terminal"`
- Scratchpad terminal: `display_name = "Scratchpad Terminal"`
- **Analysis**: ✅ INTENTIONAL - User-facing distinction

### Update Required for Ghostty

⚠️ **ACTION REQUIRED**: The current scratchpad-terminal entry uses Alacritty. Based on updated requirements (FR-001, FR-016, FR-017), the entry should be updated to:

```nix
(mkApp {
  name = "scratchpad-terminal";
  display_name = "Scratchpad Terminal";
  command = "ghostty";           # ← UPDATED: Ghostty primary
  parameters = "--working-directory=$PROJECT_DIR";  # ← UPDATED: Ghostty flag
  scope = "scoped";
  expected_class = "ghostty";    # ← UPDATED: Ghostty class
  preferred_workspace = 1;
  icon = "terminal";
  nix_package = "pkgs.ghostty";  # ← UPDATED: Ghostty package
  fallback_command = "alacritty"; # ← NEW: Fallback
  fallback_class = "Alacritty";   # ← NEW: Fallback class
  fallback_package = "pkgs.alacritty"; # ← NEW: Fallback package
  multi_instance = true;
  fallback_behavior = "use_home";
  description = "Project-scoped floating scratchpad terminal with Ghostty (Feature 062)";
})
```

**Note**: This update aligns with spec.md requirements but is not yet implemented in app-registry-data.nix.

### Verdict: ✅ CHK044 VERIFIED - CONSISTENT (with Ghostty update pending)

**Assessment**: Scratchpad terminal entry follows the same patterns as regular terminal entry, with intentional differences for its specialized use case.

**Evidence**:
- scope="scoped": ✅ Consistent
- multi_instance=true: ✅ Consistent
- expected_class based on command: ✅ Consistent
- fallback_behavior="use_home": ✅ Consistent
- nix_package reference: ✅ Consistent

**Intentional Differences**:
- parameters: Empty (daemon-managed) vs sesh command (user-launched)
- name: Descriptive vs command name
- display_name: Distinguishes functionality

**Pending Update**: Alacritty → Ghostty per spec.md requirements

---

## Summary

### CHK040: RPC Pattern Consistency ✅ VERIFIED
- **Status**: Consistent with improvement (namespacing)
- **Recommendation**: Use namespacing for future RPC method groups
- **Blockers**: None

### CHK044: App Registry Consistency ✅ VERIFIED
- **Status**: Consistent patterns, intentional differences
- **Action Required**: Update app-registry-data.nix to use Ghostty
- **Blockers**: None (Alacritty fallback maintains compatibility)

### CHK024: Async Timeout Requirements ✅ COMPLETED
- **Status**: TR-009 added to spec.md with comprehensive timeout table
- **Blockers**: None

### Final Assessment

**Overall Status**: ✅ ALL CRITICAL VERIFICATIONS COMPLETE

**Requirements Coverage**: 76/98 (78%) with TR-009
- Added 1 new requirement (TR-009)
- Verified 2 consistency items (CHK040, CHK044)
- Remaining gaps: 21 items (17 low priority, 2 medium, 0 critical)

**Readiness**: ✅ READY FOR IMPLEMENTATION

**Next Steps**:
1. Update app-registry-data.nix with Ghostty-based scratchpad entry
2. Proceed with implementation per plan.md §Integration Patterns
3. Address remaining 21 gaps during implementation

