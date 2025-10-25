# Research: Registry-Centric Project & Workspace Management

**Branch**: `035-now-that-we` | **Date**: 2025-10-25 | **Phase**: 0 (Research)

## Research Questions & Findings

### Deno i3 IPC Integration

**Question**: Can Deno directly communicate with i3 IPC socket (Unix domain socket at `$I3SOCK` or via `i3 --get-socketpath`), or does it need to shell out to Python/i3-msg?

**Decision**: **Shell out to Python daemon for complex queries, use i3-msg for simple commands**

**Rationale**:

1. **Protocol Complexity vs CLI Use Case**:
   - i3 IPC protocol requires binary message framing: magic string "i3-ipc" + 32-bit message length + 32-bit message type + JSON payload (see `/etc/nixos/docs/i3-ipc.txt` lines 64-68)
   - Responses use identical format: magic string + length + type + JSON payload
   - Implementing full protocol in Deno requires:
     - Binary protocol handling (Uint8Array, DataView for framing)
     - Message type constants (GET_TREE=4, GET_WORKSPACES=1, RUN_COMMAND=0, etc.)
     - Error handling for malformed messages
     - Connection lifecycle management
   - **Verdict**: Protocol is well-documented but adds ~200-300 lines of low-level code for a CLI tool

2. **Existing Patterns in Codebase**:
   - **Current approach**: Deno CLI (`i3pm-deno`) communicates with Python daemon via JSON-RPC 2.0 over Unix socket (see `/etc/nixos/home-modules/tools/i3pm-deno/src/client.ts`)
   - Python daemon (`i3_project_manager`) uses `i3ipc.aio` library (async i3 IPC) for querying i3 state (see `/etc/nixos/home-modules/tools/i3_project_manager/core/i3_client.py`)
   - For simple commands (workspace switches, ticks), codebase uses `i3-msg` shell-out (see test files like `live_updates_test.ts` line 13: `new Deno.Command("i3-msg", ...)`)
   - **Verdict**: Established pattern already exists - don't reinvent

3. **Deno Native Socket Support**:
   - Deno supports Unix sockets: `Deno.connect({ path: socketPath, transport: "unix" })` returns `Deno.UnixConn` (confirmed in `/etc/nixos/home-modules/tools/i3pm-deno/src/utils/socket.ts`)
   - Can read/write binary data via `Uint8Array` buffers
   - **Verdict**: Technically feasible, but requires maintaining protocol implementation

4. **No Existing Deno i3 Library**:
   - Web search found no existing Deno i3 IPC library
   - Libraries exist for Go, Python (i3ipc-python), C++, C (i3ipc-glib), but not Deno/TypeScript
   - Generic Deno IPC tools exist (deno.land/x/ipc) but not i3-specific
   - **Verdict**: Would need to implement from scratch

5. **Performance Considerations**:
   - Shell-out overhead: ~5-20ms for `i3-msg` command execution
   - JSON-RPC to daemon: ~1-5ms (local Unix socket, no network)
   - Native IPC: ~0.5-2ms (direct socket communication)
   - **Verdict**: For CLI use case (not real-time daemon), shell-out latency is acceptable
   - Layout capture/restore operations are infrequent (user-initiated), not performance-critical

6. **Maintainability**:
   - Python daemon already provides abstractions over i3 IPC (GET_TREE, GET_WORKSPACES, GET_OUTPUTS)
   - Daemon handles event subscriptions, window state caching, complex queries
   - Adding native Deno i3 IPC client duplicates daemon functionality
   - **Verdict**: Leverage existing daemon investment, don't maintain two IPC implementations

**Implementation Pattern**:

```typescript
// For layout capture: Query daemon for window state (already supports GET_TREE)
const client = new DaemonClient();
await client.connect();
const windows = await client.request<WindowState>("get_window_state", {
  include_geometry: true,
  workspace_filter: [1, 2, 3]
});

// For simple i3 commands: Shell out to i3-msg
async function moveWindow(windowId: number, workspace: number): Promise<void> {
  const cmd = new Deno.Command("i3-msg", {
    args: [`[id=${windowId}]`, "move", "container", "to", "workspace", `${workspace}`],
    stdout: "piped",
    stderr: "piped",
  });
  const { success, stderr } = await cmd.output();
  if (!success) {
    const error = new TextDecoder().decode(stderr);
    throw new Error(`Failed to move window: ${error}`);
  }
}

// For layout restoration: Use registry to launch apps (Feature 034 protocol)
import { launchApp } from "@app-launcher/registry";
for (const window of layout.windows) {
  await launchApp(window.app_name, { projectDir: project.directory });
}
```

**Alternatives Considered**:

1. **Full native Deno i3 IPC client**:
   - Pros: No external dependencies, faster for bulk queries
   - Cons: ~200-300 LOC to maintain, duplicates daemon functionality, no benefit for infrequent CLI operations
   - **Rejected**: Complexity outweighs benefits for this use case

2. **Shell out to i3-msg for all queries**:
   - Pros: Simplest implementation, zero protocol handling
   - Cons: Poor performance for bulk queries (GET_TREE returns full window hierarchy), no structured types
   - **Rejected**: GET_TREE output parsing from JSON string less elegant than typed daemon responses

3. **Hybrid approach** (SELECTED):
   - Use daemon JSON-RPC for complex queries (window state, workspace assignments, output config)
   - Use i3-msg shell-out for simple commands (move window, send tick, switch workspace)
   - Use registry launch protocol for application spawning (Feature 034)
   - **Accepted**: Leverages existing infrastructure, clear separation of concerns

**Limitations**:

- **Daemon dependency**: CLI requires Python daemon running for complex queries
  - Mitigation: Daemon already required for event-driven window marking (Feature 015)
  - Fallback: If daemon unavailable, CLI can shell out to i3-msg for degraded functionality
- **No direct event subscriptions in CLI**: Cannot subscribe to i3 window events from Deno
  - Mitigation: Not needed - daemon handles event subscriptions, CLI is stateless request-response
- **JSON-RPC overhead**: Extra serialization layer compared to native IPC
  - Impact: Negligible for CLI use case (<5ms per request on local socket)

**Layout Capture Requirements**:

Feature 035 layout capture needs the following i3 state:
1. **Window positions & sizes**: GET_TREE → container `rect` property (absolute coordinates)
2. **Workspace assignments**: GET_TREE → container `workspace` property + GET_WORKSPACES for validation
3. **Window metadata**: GET_TREE → `window_properties.class`, `window_properties.instance`, `marks` array
4. **Application identification**: Match window class to registry `expected_class` field

**Implementation approach**:
```typescript
interface LayoutWindow {
  app_name: string;          // Registry application name (not command)
  workspace: number;         // Workspace number (1-9)
  rect: {                    // Absolute coordinates from GET_TREE
    x: number;
    y: number;
    width: number;
    height: number;
  };
  floating: boolean;         // From GET_TREE container.floating
  marks: string[];           // Window marks for project scoping
}

// Capture layout via daemon
const tree = await client.request("get_tree");  // Python daemon wraps GET_TREE
const windows = extractWindows(tree);           // Parse tree, filter project windows
const layout = {
  name: layoutName,
  project: currentProject,
  windows: windows.map(w => ({
    app_name: matchRegistryApp(w.window_properties.class),  // Reverse lookup
    workspace: w.workspace,
    rect: w.rect,
    floating: w.floating !== "auto_off",
    marks: w.marks,
  })),
};
```

**Validation against registry**:
- On save: Verify all window classes match registry `expected_class` entries
- On restore: Confirm all `app_name` references exist in current registry
- On mismatch: Warn user but continue with available apps (FR-013: graceful degradation)

**Conclusion**:

Deno CLI will **not** implement native i3 IPC protocol. Instead:
- Complex queries (GET_TREE, GET_WORKSPACES) → JSON-RPC to Python daemon
- Simple commands (move window, send tick) → Shell out to i3-msg
- Application launching → Registry protocol (Feature 034)

This approach:
- Minimizes code duplication (daemon already has i3ipc integration)
- Leverages existing typed APIs (daemon exposes structured window state)
- Keeps CLI simple and maintainable (stateless, no protocol handling)
- Meets performance requirements (latency acceptable for user-initiated operations)
- Aligns with Principle I (modular composition - reuse daemon services)

---

## Registry Compilation and Runtime Access

### Decision: Registry Compilation Strategy

**Approach**: Use `home.file` with `builtins.toJSON` to compile registry at build time, installed as a symlink to `/nix/store` at `~/.config/i3/application-registry.json`.

**Rationale**:
1. **Declarative Configuration**: Registry remains fully declarative in Nix (Principle VI compliance)
2. **Build-Time Validation**: Nix validates schema before generating JSON (catches errors early)
3. **Automatic Updates**: Registry updates automatically on `nixos-rebuild switch` or `home-manager switch`
4. **Performance**: JSON file is pre-compiled, no runtime parsing of Nix expressions needed
5. **Runtime Access**: Deno CLI can read standard JSON file using `Deno.readTextFile()`
6. **No Manual Sync**: Symlink pattern ensures CLI always reads current Nix-generated registry

**Location**: `~/.config/i3/application-registry.json` (symlink to `/nix/store/<hash>-home-manager-files/.config/i3/application-registry.json`)

### Current Implementation (Feature 034)

**Pattern Already Established**:

```nix
# home-modules/desktop/app-registry.nix (lines 431-437)
home.file = {
  ".config/i3/application-registry.json".text = builtins.toJSON {
    version = "1.0.0";
    applications = validated;
  };
} // desktopFileEntries;
```

**Verification**:
```bash
$ ls -la ~/.config/i3/application-registry.json
lrwxrwxrwx ... -> /nix/store/6g0jg2glr657ihgy98xb47lb94d32if6-home-manager-files/.config/i3/application-registry.json

$ cat ~/.config/i3/application-registry.json | jq -r '.version, (.applications | length)'
1.0.0
21
```

**JSON Schema** (from Feature 034):
```json
{
  "version": "1.0.0",
  "applications": [
    {
      "name": "vscode",
      "display_name": "VS Code",
      "command": "code",
      "parameters": "$PROJECT_DIR",
      "scope": "scoped",
      "expected_class": "Code",
      "preferred_workspace": 1,
      "icon": "vscode",
      "nix_package": "pkgs.vscode",
      "multi_instance": true,
      "fallback_behavior": "skip",
      "description": "Visual Studio Code editor with project context"
    }
  ]
}
```

### Registry Structure Review

**Current Fields** (Feature 034):
- ✅ `name`: Kebab-case application identifier
- ✅ `display_name`: Human-readable name
- ✅ `command`: Executable name (validated for shell metacharacters)
- ✅ `parameters`: Command arguments with variable placeholders (`$PROJECT_DIR`, `$PROJECT_NAME`, etc.)
- ✅ `scope`: "scoped" (project-aware) or "global" (project-independent)
- ✅ `expected_class`: Window class for i3 matching
- ✅ `preferred_workspace`: Workspace number (1-9, validated at build time)
- ✅ `icon`: Icon name for desktop files and Walker
- ✅ `nix_package`: Package reference for error messages
- ✅ `multi_instance`: Boolean - allow multiple windows per project
- ✅ `fallback_behavior`: "skip", "use_home", or "error" when no project active
- ✅ `description`: Help text for desktop files

**Missing Fields for Feature 035**:
- ❌ `tags`: Array of strings for project-based filtering (e.g., `["development", "terminal", "git"]`)
- ❌ `expected_title_contains`: Optional title-based window matching (fallback if class unavailable)

**Recommendation**: Extend registry schema to include:

```nix
# home-modules/desktop/app-registry.nix
(mkApp {
  name = "vscode";
  display_name = "VS Code";
  command = "code";
  parameters = "$PROJECT_DIR";
  scope = "scoped";
  expected_class = "Code";
  preferred_workspace = 1;
  icon = "vscode";
  nix_package = "pkgs.vscode";
  multi_instance = true;
  fallback_behavior = "skip";
  description = "Visual Studio Code editor with project context";
  tags = ["development" "editor"];  # NEW: Flat single-level tags
})
```

### Variable Substitution Pattern

**Current Variables** (Feature 034, implemented in `app-launcher-wrapper.sh`):
- `$PROJECT_DIR` - Project root directory (absolute path, validated)
- `$PROJECT_NAME` - Project identifier (kebab-case)
- `$SESSION_NAME` - Session name for tmux/sesh (same as project name)
- `$HOME` - User home directory
- `$PROJECT_DISPLAY_NAME` - Human-readable project name
- `$PROJECT_ICON` - Project icon
- `$WORKSPACE` - Preferred workspace number

**Storage in Registry**: Literal strings (e.g., `"parameters": "$PROJECT_DIR"`)

**Substitution Timing**: Runtime, during application launch via `app-launcher-wrapper.sh`

**Substitution Location**: Bash wrapper script (lines 170-203)

**Process**:
1. Registry stores literal variable strings: `"parameters": "$PROJECT_DIR"`
2. Launcher queries daemon for project context: `i3pm project current --json`
3. Bash script performs string replacement: `${PARAM_RESOLVED//\$PROJECT_DIR/$PROJECT_DIR}`
4. Validates directory exists and is absolute path
5. Applies fallback behavior if project inactive ("skip", "use_home", "error")

**Security**: Variables validated at build time (no shell metacharacters) and runtime (absolute paths, directory existence)

**Example Flow**:
```bash
# Registry entry
{
  "name": "vscode",
  "parameters": "$PROJECT_DIR",
  "fallback_behavior": "skip"
}

# Runtime query
$ i3pm project current --json
{"name": "nixos", "directory": "/etc/nixos"}

# Substitution
$PROJECT_DIR → /etc/nixos

# Final command
exec code /etc/nixos
```

### Build-Time Validation

**Current Validation** (Feature 034, `app-registry.nix` lines 366-390):

```nix
# Duplicate name detection
duplicates = lib.filter (name:
  (lib.length (lib.filter (n: n == name) appNames)) > 1
) (lib.unique appNames);

# Workspace range validation
invalidWorkspaces = lib.filter (app:
  app ? preferred_workspace && (app.preferred_workspace < 1 || app.preferred_workspace > 9)
) applications;

# Name format validation (kebab-case)
invalidNames = lib.filter (app:
  builtins.match "[a-z0-9-]+" app.name == null
) applications;

# Parameter safety validation (lines 16-24)
validateParameters = params:
  if builtins.match ".*[;|&`].*" params != null then
    throw "Invalid parameters: contains shell metacharacters (;|&`)"
  else if builtins.match ".*\\$\\(.*" params != null then
    throw "Invalid parameters: contains command substitution $()"
  else if builtins.match ".*\\$\\{.*" params != null then
    throw "Invalid parameters: contains parameter expansion \${}"
  else
    params;
```

**What Validation Should Happen at Build Time**:
- ✅ Duplicate application names (already implemented)
- ✅ Valid workspace range 1-9 (already implemented)
- ✅ Kebab-case name format (already implemented)
- ✅ No shell metacharacters in commands/parameters (already implemented)
- ❌ **NEW**: Tag format validation (lowercase, alphanumeric, underscore, hyphen)
- ❌ **NEW**: Required fields validation (name, command, scope, expected_class OR expected_title_contains)
- ❌ **NEW**: Fallback behavior enum validation ("skip", "use_home", "error")

**Recommendation**: Add tag validation to `app-registry.nix`:

```nix
# Tag format validation (alphanumeric, underscore, hyphen)
validateTag = tag:
  if builtins.match "[a-z0-9_-]+" tag == null then
    throw "Invalid tag '${tag}': must be lowercase alphanumeric with underscores/hyphens"
  else
    tag;

# Validate all tags in application list
validatedTags = lib.flatten (map (app:
  map validateTag (app.tags or [])
) applications);
```

### Runtime Validation

**What Validation Happens at Runtime** (Deno CLI):
- ✅ **Registry file exists** (`RegistryError` if missing, `/etc/nixos/home-modules/tools/app-launcher/src/registry.ts` lines 81-86)
- ✅ **Valid JSON syntax** (`RegistryError` if parse fails, lines 45-52)
- ✅ **Schema structure** (type guards via `isApplicationRegistry`, lines 54-60)
- ✅ **Duplicate application names** (lines 63-77)
- ✅ **Version format** (`x.y.z` pattern, lines 169-173 in `validateRegistry`)
- ✅ **Parameter safety** (no shell metacharacters, lines 186-193)
- ✅ **Workspace range** (1-9, lines 205-214)
- ❌ **NEW**: Project tag validation (check tags exist in registry when loading project config)
- ❌ **NEW**: Missing application references in layouts

**Project Tag Validation** (NEW for Feature 035):

```typescript
// When loading project config: ~/.config/i3/projects/<name>.json
interface ProjectConfig {
  name: string;
  directory: string;
  tags?: string[];  // NEW: Filter applications by these tags
  layout?: string;  // Path to saved layout
}

// Validate project tags against registry
function validateProjectTags(project: ProjectConfig, registry: ApplicationRegistry): string[] {
  const errors: string[] = [];
  const registryTags = new Set(
    registry.applications.flatMap(app => app.tags ?? [])
  );

  for (const tag of project.tags ?? []) {
    if (!registryTags.has(tag)) {
      errors.push(`Unknown tag "${tag}" in project "${project.name}" - not found in registry`);
    }
  }

  return errors;
}
```

### Recompilation Triggers

**When Registry Updates**:
1. User edits `home-modules/desktop/app-registry.nix`
2. User runs `sudo nixos-rebuild switch --flake .#<target>` OR `home-manager switch --flake .#<user>@<target>`
3. Nix validates schema and compiles to JSON
4. Home-manager creates new `/nix/store/<hash>` entry
5. Symlink at `~/.config/i3/application-registry.json` updated atomically
6. Next CLI command reads new registry automatically (no daemon restart needed)

**No Separate Derivation Needed**: The `home.file` mechanism already handles compilation as part of home-manager activation.

**No Activation Script Needed**: Symlink pattern provides atomic updates without custom activation logic.

### Best Practices Summary

**Nix → JSON Compilation**:
- ✅ Use `builtins.toJSON` to serialize Nix data structures
- ✅ Use `home.file.<path>.text` for small configs (< 100KB)
- ✅ Use `pkgs.writeText` for larger configs or when derivation needed
- ✅ Validate data structure before serialization (catch errors at build time)
- ✅ Use symlinks (default for `home.file`) for atomic updates

**Variable Substitution**:
- ✅ Store literal variable strings in registry (`$PROJECT_DIR`)
- ✅ Perform substitution at launch time (runtime context needed)
- ✅ Validate substituted values (absolute paths, directory existence)
- ✅ Provide fallback behaviors (skip, use_home, error)
- ✅ Log all substitutions for debugging

**Registry Access**:
- ✅ Single source of truth: `~/.config/i3/application-registry.json`
- ✅ No caching needed (OS filesystem cache is sufficient)
- ✅ Validate at both build time (Nix) and runtime (Deno CLI)
- ✅ Use type guards for runtime schema validation
- ✅ Provide clear error messages with remediation steps

**Tag System**:
- ✅ Flat single-level tags (no hierarchy)
- ✅ Tags stored as array of strings in registry
- ✅ Projects reference tags, not application names
- ✅ Validate tag format at build time (lowercase alphanumeric + underscore/hyphen)
- ✅ Validate project tags at runtime (check against registry)

### Open Questions & Answers

**Q1**: Should tags be validated for uniqueness, or can multiple apps share the same tag?
**A1**: Tags SHOULD be shared across applications (e.g., multiple apps can have "terminal" tag). No uniqueness constraint needed.

**Q2**: Should the registry JSON include a "tags" top-level field listing all unique tags?
**A2**: Optional but useful for CLI queries. Recommendation: Add `"tags": [...]` to registry JSON for fast tag enumeration without parsing all applications.

**Q3**: Should layout restore validate that all referenced applications still exist in registry?
**A3**: Yes. Runtime validation should check layout references against current registry and skip missing apps with warnings (FR-013).

**Q4**: Should the registry support application dependencies (e.g., "launch app B before app A")?
**A4**: Out of scope for Feature 035 (spec line 182). Users handle dependencies manually.

### Recommendation for Feature 035

**Phase 0 Actions**:
1. ✅ **No new compilation strategy needed** - use existing `home.file` pattern from Feature 034
2. ✅ **Extend registry schema** to include `tags` field (flat array of strings)
3. ✅ **Add build-time tag validation** to `app-registry.nix`
4. ✅ **Add runtime project tag validation** to Deno CLI when loading projects
5. ✅ **Maintain existing variable substitution** pattern (runtime, in bash wrapper)
6. ✅ **Document tag naming conventions** (lowercase, alphanumeric, underscore, hyphen)

**No Breaking Changes**:
- Existing registry access patterns remain unchanged
- Variable substitution continues to work as-is
- Build-time and runtime validation extend current patterns
- Tags are additive (optional field with empty array default)

**Next Steps** (Phase 1):
- Define project configuration schema with tag filtering
- Design Deno CLI commands for tag-based application queries
- Implement layout save/restore with registry application references
- Update i3pm CLI to expose registry metadata and project management

---

*Research completed: 2025-10-25*
*Next phase: Design (data models, contracts, quickstart)*

### Window Matching and Auto-Assignment Strategy

**Question**: Should window workspace assignment use static i3 `for_window` rules generated from app-registry.nix, or event-driven daemon with i3ipc subscriptions? What are edge cases for PWAs, multi-instance apps, and window class matching?

**Decision**: **Hybrid approach - Static rules for global apps + Event-driven daemon for scoped apps**

**Rationale**:

i3 native `for_window` rules have critical limitations for this use case:
- ✅ Can handle **static** workspace assignments (e.g., Firefox always → WS2)
- ✅ Supports pattern matching with PCRE regex on class, title, instance
- ❌ **Cannot** access external state (active project, daemon state)
- ❌ **Cannot** conditionally show/hide windows based on project context
- ❌ **Cannot** execute external scripts or variable substitution
- ❌ All rules evaluated once at window creation from static config

Evidence from existing `/etc/nixos/home-modules/desktop/i3.nix` (lines 38-79):
```nix
# NOTE: Project-scoped applications (Ghostty, Code) should NOT have static assign rules
# as they need dynamic workspace placement for layout restore to work correctly.
# The daemon handles project-aware window placement via marks.

# All scoped app for_window rules are DISABLED:
# assign [class="Code"] $ws2  # DISABLED
# assign [class="ghostty"] $ws1  # DISABLED
```

**Hybrid Approach Selected**:

1. **Static Rules** (Generated at NixOS build time):
   - Global applications with fixed workspaces (Firefox → WS2, K9s → WS5)
   - Generated from app-registry.nix as i3 `for_window` rules
   - Zero runtime overhead, native i3 performance

2. **Event-Driven Daemon** (Runtime):
   - Scoped applications with project-aware placement
   - Layout restore workspace assignment
   - Multi-instance applications
   - Window marking with project tags

**Current Daemon Architecture** (Feature 015):

Proven implementation at `/etc/nixos/home-modules/desktop/i3-project-event-daemon/`:
- ✅ Systemd user service with socket activation + watchdog
- ✅ Subscribes to i3 IPC: `window::new`, `window::mark`, `window::close`, `window::focus`, `window::title`, `tick`, `output`, `shutdown`
- ✅ 4-level precedence classification (project scoped_classes → window rules → patterns → lists)
- ✅ JSON-RPC IPC server for CLI queries
- ✅ 500-event buffer for debugging

Window auto-marking (`handlers.py:242-388`):
```python
async def on_window_new(conn, event, state_manager, window_rules, ...):
    # Classify window using pattern matching
    classification = classify_window(
        window_class=window_class,
        window_title=window_title,
        active_project_scoped_classes=active_project_scoped_classes,
        window_rules=window_rules,
    )

    # If scoped and active project, mark window
    if classification.scope == "scoped" and active_project:
        mark = f"project:{active_project}"
        await conn.command(f'[id={window_id}] mark --add "{mark}"')

    # Execute structured actions (Feature 024)
    if classification.matched_rule and classification.matched_rule.actions:
        await apply_rule_actions(conn, window_info, classification.matched_rule.actions)
```

**Edge Case Handling**:

| Edge Case | Solution | Implementation |
|-----------|----------|----------------|
| **PWA apps (FFPWA-*)** | Exact class matching | `expected_class = "FFPWA-01K666N2V6BQMDSBMX3AY74TY7"` in registry, static rule generated |
| **Multi-instance (terminals)** | `multi_instance = true` flag | Daemon allows multiple marked windows, no fixed workspace |
| **Multiple window classes** | Track primary class only | Registry defines main `expected_class`, helpers unmarked |
| **Window never appears** | No timeout (out of scope) | User debug via `i3pm windows --live`, `i3pm daemon events` |

**Implementation Pattern**:

NixOS build time (`home-modules/desktop/app-registry.nix`):
```nix
let
  # Filter global apps with fixed workspaces
  globalApps = filter (app:
    app.scope == "global" && app ? preferred_workspace
  ) validated;

  # Generate i3 for_window rules
  globalWindowRules = lib.concatStringsSep "\n    " (
    map (app: ''for_window [class="${app.expected_class}"] move to workspace number ${toString app.preferred_workspace}'')
    globalApps
  );
in
{
  # Auto-generated i3 window rules
  home.file.".config/i3/window-rules-generated.conf".text = ''
    # Auto-generated from app-registry.nix (Feature 035)
    # DO NOT EDIT - Rebuilt on nixos-rebuild

    ${globalWindowRules}
  '';
}
```

Runtime daemon extension (`i3-project-event-daemon/config.py`):
```python
def load_registry_window_rules(registry_path: Path) -> List[WindowRule]:
    """Generate window rules from registry for scoped applications."""
    registry = json.loads(registry_path.read_text())

    rules = []
    for app in registry["applications"]:
        if app["scope"] != "scoped":
            continue  # Global apps use static rules

        pattern = PatternRule(
            pattern=app["expected_class"],
            scope="scoped",
            priority=250,
        )

        # Multi-instance apps don't get fixed workspace
        workspace = None if app.get("multi_instance", False) else app.get("preferred_workspace")

        rules.append(WindowRule(
            pattern_rule=pattern,
            workspace=workspace,
        ))

    return rules
```

**Alternatives Considered and Rejected**:

1. **Pure static rules**: Cannot support project-scoped assignment or layout restore (violates FR-005, FR-011)
2. **Pure daemon**: Unnecessary overhead for global apps (daemon already required for scoped apps)
3. **Generate i3 config at runtime**: Would require i3 restart for every project switch (breaks UX)

**Validation**:
- Build-time: NixOS validates workspace numbers (1-9)
- Runtime: Daemon logs unmatched window classes to event buffer
- User tools: `i3pm windows --live` shows assignments, `i3pm daemon events` shows classification

**Benefits**:
- ✅ Best performance for global apps (native i3 rules, zero overhead)
- ✅ Full flexibility for scoped apps (daemon logic)
- ✅ Single source of truth (app-registry.nix)
- ✅ Proven architecture (extends Feature 015 daemon)
- ✅ Clean edge case handling (PWAs, multi-instance, partial classes)

---

*Window matching research completed: 2025-10-25*
