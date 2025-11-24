# Phase 0 Research: Enhanced Projects & Applications CRUD Interface

**Feature**: 094-enhance-project-tab
**Date**: 2025-11-24
**Status**: Complete

## Overview

This document consolidates research findings for technical unknowns identified during implementation planning. Research focused on two critical areas: (1) programmatic editing of Nix expression files from Python, and (2) real-time form validation in Eww widgets with Yuck expressions.

---

## Research Area 1: Nix Expression Editing from Python

### Decision

**Text-based template/append approach with formatting preservation** using Python regex and templates to manipulate `app-registry-data.nix`.

### Rationale

1. **No mature Nix AST libraries for Python**: `rnix-parser` is Rust-only with no official Python bindings. While theoretically possible via FFI, this violates Constitution Principle X (Python 3.11+ standard) and adds unnecessary Rust dependency.

2. **Existing codebase patterns**: Repository already uses text-based generation:
   - `pkgs/speech-to-text-indicator.nix`: Uses `pkgs.writeTextFile` to embed Python in Nix
   - `home-modules/desktop/app-registry.nix`: Generates JSON from Nix with `builtins.toJSON`
   - Registry files have **well-defined structure**: `applications = [ (mkApp { ... }) ... ]`

3. **Limited edit requirements**: Feature 094 needs simple list operations (add entry, edit entry, delete entry), not complex AST transformations requiring semantic understanding.

4. **Well-structured target file**: `app-registry-data.nix` has predictable insertion points:
   - Applications list begins after `applications = [` line
   - Each app defined as `(mkApp { ... })` block
   - List ends with `] ++ (builtins.map mkPWAApp pwas)` for PWA auto-generation

### Alternatives Considered

#### 1. AST-based with rnix-parser (Rejected)
- **Pros**: Semantic understanding, preserves all formatting/comments
- **Cons**:
  - Requires Rust FFI or subprocess calls to Rust tools
  - No Python bindings documented
  - Overkill for simple list append operations
  - Violates Constitution Principle X (Python 3.11+ standard)
  - Adds Rust build dependency to Python-based system

#### 2. Full file regeneration from JSON state (Rejected)
- **Pros**: Avoids parsing, simple template approach
- **Cons**:
  - Loses all comments in `app-registry-data.nix` (unacceptable for maintainability)
  - Loses custom formatting preferences
  - Requires maintaining parallel JSON state file
  - Cannot support incremental edits

#### 3. Nix evaluation + jq manipulation (Rejected)
- **Pros**: Leverages Nix's own parser via evaluation
- **Cons**:
  - `builtins.toJSON` produces JSON, not Nix expressions (no round-trip)
  - Can only read, not write back to Nix files
  - Fundamentally incompatible with editing workflow

### Implementation Strategy

#### Adding New Applications

```python
# File: home-modules/tools/i3_project_manager/services/app_registry_editor.py

def add_application(nix_file_path: Path, app_config: dict) -> None:
    """
    Add new application entry to app-registry-data.nix

    Strategy:
    1. Find closing ] of applications list
    2. Insert new (mkApp {...}) entry before closing bracket
    3. Preserve indentation and formatting
    """
    with open(nix_file_path, 'r') as f:
        content = f.read()

    # Generate formatted entry
    new_entry = generate_mkapp_entry(app_config)

    # Find insertion point: before "  ]\n  # Auto-generate PWA entries"
    insertion_pattern = r'(\s+\])\s+# Auto-generate PWA entries'

    modified = re.sub(
        insertion_pattern,
        f'\n{new_entry}\n\\1\n  # Auto-generate PWA entries',
        content,
        count=1
    )

    write_with_backup(nix_file_path, modified)

def generate_mkapp_entry(config: dict) -> str:
    """Generate formatted (mkApp {...}) entry with proper indentation"""
    indent = "    "

    template = f'''    (mkApp {{
{indent}  name = "{config['name']}";
{indent}  display_name = "{config['display_name']}";
{indent}  command = "{config['command']}";
{indent}  parameters = "{config.get('parameters', '')}";
{indent}  scope = "{config['scope']}";
{indent}  expected_class = "{config['expected_class']}";
{indent}  preferred_workspace = {config['preferred_workspace']};
{indent}  icon = "{config['icon']}";
{indent}  nix_package = "{config.get('nix_package', 'null')}";
{indent}  multi_instance = {str(config.get('multi_instance', False)).lower()};
{indent}  fallback_behavior = "{config.get('fallback_behavior', 'skip')}";
{indent}  description = "{config.get('description', '')}";
{indent}}})'''

    return template
```

#### Editing Existing Applications

```python
def edit_application(nix_file_path: Path, app_name: str, updates: dict) -> None:
    """
    Edit existing application entry by name

    Strategy:
    1. Find (mkApp { name = "target"; ... }) block via regex
    2. Parse fields from block text
    3. Apply updates to parsed fields
    4. Regenerate block with updated values
    5. Replace old block with new block in file content
    """
    with open(nix_file_path, 'r') as f:
        content = f.read()

    # Pattern: (mkApp {\n      name = "target";\n ... \n    })
    pattern = rf'\(mkApp \{{\s+name = "{app_name}";[^}]+\}}[^)]*\)'

    match = re.search(pattern, content, re.MULTILINE | re.DOTALL)
    if not match:
        raise ValueError(f"Application '{app_name}' not found in registry")

    # Parse existing fields
    old_block = match.group(0)
    fields = parse_mkapp_fields(old_block)

    # Apply updates
    fields.update(updates)

    # Regenerate block
    new_block = generate_mkapp_entry(fields)

    # Replace in content
    modified = content.replace(old_block, new_block)

    write_with_backup(nix_file_path, modified)

def parse_mkapp_fields(block: str) -> dict:
    """Parse fields from mkApp block using regex"""
    fields = {}

    # Extract: name = "value"; or name = 123; or name = true;
    field_pattern = r'(\w+)\s*=\s*([^;]+);'

    for match in re.finditer(field_pattern, block):
        key = match.group(1)
        value_raw = match.group(2).strip()

        # Type inference
        if value_raw.startswith('"') and value_raw.endswith('"'):
            fields[key] = value_raw[1:-1]  # String
        elif value_raw in ['true', 'false']:
            fields[key] = value_raw == 'true'  # Boolean
        elif value_raw.isdigit():
            fields[key] = int(value_raw)  # Number
        else:
            fields[key] = value_raw  # Other (null, expressions)

    return fields
```

#### Deleting Applications

```python
def delete_application(nix_file_path: Path, app_name: str) -> None:
    """Delete application entry by removing entire (mkApp {...}) block"""
    with open(nix_file_path, 'r') as f:
        content = f.read()

    # Find and remove mkApp block (including surrounding whitespace)
    pattern = rf'\s*\(mkApp \{{\s+name = "{app_name}";[^}]+\}}[^)]*\)\s*'

    modified = re.sub(pattern, '', content, count=1, flags=re.MULTILINE | re.DOTALL)

    if modified == content:
        raise ValueError(f"Application '{app_name}' not found in registry")

    write_with_backup(nix_file_path, modified)
```

#### Conflict Detection and Backup

```python
def write_with_backup(file_path: Path, new_content: str) -> None:
    """
    Write file with conflict detection, backup, and Nix syntax validation

    Per spec.md clarification Q2: Detect conflicts via file modification timestamp
    """
    # Create backup before modification
    if file_path.exists():
        original_mtime = file_path.stat().st_mtime
        backup_path = file_path.with_suffix('.nix.bak')
        shutil.copy2(file_path, backup_path)

    # Write new content
    with open(file_path, 'w') as f:
        f.write(new_content)

    # Validate Nix syntax
    result = subprocess.run(
        ['nix-instantiate', '--parse', str(file_path)],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        # Syntax error - restore backup
        if backup_path.exists():
            shutil.copy2(backup_path, file_path)
        raise ValueError(f"Generated invalid Nix syntax: {result.stderr}")
```

#### ULID Generation for PWAs

Per spec.md clarification Q5: Auto-generate ULIDs programmatically using existing script.

```python
def generate_pwa_ulid() -> str:
    """Generate ULID using /etc/nixos/scripts/generate-ulid.sh"""
    result = subprocess.run(
        ['/etc/nixos/scripts/generate-ulid.sh'],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        raise RuntimeError(f"ULID generation failed: {result.stderr}")

    ulid = result.stdout.strip()

    # Validate format: 26 chars, Crockford Base32 (excludes I, L, O, U)
    if not re.match(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$', ulid):
        raise ValueError(f"Generated invalid ULID format: {ulid}")

    return ulid

def add_pwa_application(name: str, url: str, workspace: int) -> str:
    """
    Add PWA to shared/pwa-sites.nix with auto-generated ULID

    Per spec.md FR-A-029: Auto-generate ULID during save operation
    """
    ulid = generate_pwa_ulid()

    pwa_entry = f'''
    {{
      name = "{name}";
      url = "{url}";
      domain = "{extract_domain(url)}";
      icon = "/etc/nixos/assets/icons/{name.lower()}.svg";
      description = "{name} PWA";
      categories = "Network;";
      keywords = "{name.lower()};";
      scope = "{url}";
      ulid = "{ulid}";
      app_scope = "scoped";
      preferred_workspace = {workspace};
    }}
    '''

    # Insert into pwa-sites.nix before closing ]
    pwa_file = Path('/etc/nixos/shared/pwa-sites.nix')
    # (similar text manipulation as app-registry-data.nix)

    return ulid
```

### Format Preservation Strategy

- **Indentation**: Maintain 4-space indentation (detected from existing file)
- **Comments**: Preserve comments outside `applications = [...]` list
- **Field Order**: Follow existing order in `mkApp` calls
- **Blank Lines**: Preserve blank lines between app entries

### Validation Strategy

1. **Pre-save validation**: Pydantic models check field types, workspace ranges, name format (per spec.md FR-A-006, FR-A-007)
2. **Post-save validation**: Run `nix-instantiate --parse` to verify syntax
3. **On error**: Restore backup, return actionable error message to UI

### Key Files

- **New**: `home-modules/tools/i3_project_manager/services/app_registry_editor.py` (220 lines)
- **New**: `home-modules/tools/i3_project_manager/models/app_config.py` (150 lines, Pydantic models)
- **New**: `tests/094-enhance-project-tab/unit/test_app_registry_editor.py` (180 lines)

---

## Research Area 2: Real-Time Form Validation in Eww

### Decision

**Hybrid approach: Python backend validation + Yuck frontend feedback** with deflisten streaming for <100ms latency updates.

### Rationale

1. **Existing architecture already follows this pattern**:
   - Health tab validates service state in Python, displays with conditional CSS
   - Project list validates directory existence in Python, shows warning badges in UI
   - Error states display messages from backend JSON in styled widgets

2. **Backend handles business logic validation**:
   - Pydantic models with `@field_validator` decorators for type/constraint validation
   - Filesystem checks (directory exists, project name unique)
   - CLI availability checks (i3pm, Git commands)
   - Real-time streaming via deflisten for <100ms latency

3. **Frontend handles UI feedback**:
   - Conditional CSS classes based on validation state (`.input-field.error`)
   - Dynamic visibility with `:visible` property checking error fields
   - Error message labels below input fields

### Alternatives Considered

#### 1. Yuck-only validation (Rejected)
- **Pros**: Simpler architecture, immediate visual feedback
- **Cons**:
  - **Eww has no native validation support** - No built-in validators, regex, or constraints
  - **Limited string manipulation** - Yuck can't validate patterns (alphanumeric, length)
  - **No debouncing mechanism** - `:timeout` is fixed delay, not true debouncing
  - **Cannot check uniqueness** - Yuck can't query filesystem for existing project names

#### 2. Backend-only validation (Rejected)
- **Pros**: Authoritative validation source
- **Cons**:
  - Requires form submission to see errors (no inline feedback)
  - Cannot show errors as user types (poor UX)

#### 3. Hybrid (Selected - matches existing architecture)
- **Pros**:
  - Real-time feedback via deflisten streaming
  - Authoritative validation in Python (can check filesystem, uniqueness, CLI availability)
  - Visual feedback via conditional CSS
  - Debounced updates (300ms) in backend
  - Consistent with monitoring panel, health tab, project list patterns
- **Cons**:
  - More complex than pure frontend
  - Requires maintaining backend validation service

### Eww Input Widget Capabilities

From official Eww documentation:

```yuck
(input
  :value {form_data.project_name}      ; Bound to defvar or defpoll variable
  :onchange "validate-field {}"         ; Executes on text change ({} = current value)
  :timeout "300ms"                      ; Delay before executing command (NOT true debounce)
  :onaccept "create-project {}"         ; Executes on Enter key
  :password false)                      ; Obscure text for sensitive fields
```

**Limitations discovered**:
- No built-in validation attributes (`min-length`, `max-length`, `pattern`, `required`)
- No native error message display (must use separate label widget)
- `:timeout` is simple delay, NOT true debouncing (doesn't reset timer on new input)
- Parent window must have `focusable="true"` for input to work

### Validation Backend Pattern

```python
# File: home-modules/tools/i3_project_manager/services/form_validator.py

from pydantic import BaseModel, Field, field_validator

class ProjectFormData(BaseModel):
    """Real-time validation model for project creation form"""
    project_name: str = Field(..., min_length=1, max_length=64)
    directory: str = Field(..., min_length=1)
    icon: str = Field(default="📦")

    @field_validator("project_name")
    @classmethod
    def validate_name_pattern(cls, v: str) -> str:
        """Per spec.md FR-P-007: lowercase, hyphens only, no spaces"""
        if not re.match(r'^[a-z0-9-]+$', v):
            raise ValueError("Must be lowercase alphanumeric with hyphens only")
        return v

    @field_validator("project_name")
    @classmethod
    def validate_name_uniqueness(cls, v: str) -> str:
        """Check if project already exists"""
        existing = Path.home() / f".config/i3/projects/{v}.json"
        if existing.exists():
            raise ValueError(f"Project '{v}' already exists")
        return v

    @field_validator("directory")
    @classmethod
    def validate_directory_exists(cls, v: str) -> str:
        """Per spec.md FR-P-008: validate directory exists and accessible"""
        path = Path(v).expanduser()
        if not path.exists():
            raise ValueError(f"Directory does not exist: {v}")
        if not path.is_dir():
            raise ValueError(f"Path is not a directory: {v}")
        if not os.access(path, os.R_OK | os.W_OK):
            raise ValueError(f"Directory not accessible (check permissions): {v}")
        return v

class ValidationDebouncer:
    """True debouncing with 300ms delay"""
    def __init__(self, delay: float = 0.3):
        self.delay = delay
        self.pending_task: Optional[asyncio.Task] = None
        self.last_input = None

    async def debounce(self, input_value: str, callback):
        """Cancel previous validation, wait 300ms, then validate if still latest"""
        self.last_input = input_value

        if self.pending_task:
            self.pending_task.cancel()

        async def delayed_callback():
            await asyncio.sleep(self.delay)
            if self.last_input == input_value:  # Still the latest value
                await callback(input_value)

        self.pending_task = asyncio.create_task(delayed_callback())

async def stream_validation_updates():
    """Stream validation results to Eww via deflisten"""
    debouncer = ValidationDebouncer(delay=0.3)
    form_state = {}

    while True:
        # Read current form state from Eww variables (via IPC or file)
        form_data = await get_current_form_state()

        # Debounce validation
        await debouncer.debounce(form_data, validate_form)

async def validate_form(form_data: dict):
    """Validate form and output JSON to stdout (captured by deflisten)"""
    try:
        validated = ProjectFormData(**form_data)
        result = {"valid": True, "errors": {}}
    except ValidationError as e:
        result = {
            "valid": False,
            "errors": {err["loc"][0]: err["msg"] for err in e.errors()}
        }

    # Output JSON to stdout (deflisten captures this)
    print(json.dumps(result), flush=True)
```

### Frontend Conditional CSS Pattern

```yuck
;; Validation state (streamed from backend)
(deflisten validation_state
  :initial "{\"valid\": true, \"errors\": {}}"
  `form-validation-service --mode projects --listen`)

;; Form data (local state)
(defvar form_data "{\"project_name\": \"\", \"directory\": \"\"}")

;; Input field with error state
(box :class "form-field"
     :orientation "v"
  (label :class "field-label" :text "Project Name")
  (input
    :class {validation_state.errors?.project_name != ""
            ? "input-field error"
            : "input-field"}
    :value {form_data.project_name}
    :onchange "update-form-field project_name {}"
    :timeout "300ms")

  ;; Error message label (conditional visibility)
  (label
    :class "error-message"
    :visible {(validation_state.errors?.project_name ?: "") != ""}
    :text {validation_state.errors?.project_name ?: ""}))
```

### CSS Styling (Catppuccin Mocha)

```scss
/* Feature 057: Catppuccin Mocha colors from unified bar system */
$mocha-surface0: #313244;
$mocha-overlay0: #6c7086;
$mocha-text: #cdd6f4;
$mocha-red: #f38ba8;
$mocha-blue: #89b4fa;

/* Input field states */
.input-field {
  background-color: $mocha-surface0;
  border: 2px solid $mocha-overlay0;
  border-radius: 6px;
  padding: 8px 12px;
  color: $mocha-text;
  font-size: 13px;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.input-field.error {
  border-color: $mocha-red;
  box-shadow: 0 0 8px rgba(243, 139, 168, 0.4);
}

.input-field:focus {
  border-color: $mocha-blue;
  box-shadow: 0 0 12px rgba(137, 180, 250, 0.3);
}

.error-message {
  font-size: 11px;
  color: $mocha-red;
  margin-top: 4px;
  font-style: italic;
}

.field-label {
  font-size: 12px;
  color: $mocha-text;
  margin-bottom: 6px;
  font-weight: 600;
}

/* Submit button states */
.submit-btn {
  background-color: $mocha-blue;
  color: $mocha-surface0;
  padding: 10px 20px;
  border-radius: 6px;
  font-weight: 600;
  cursor: pointer;
  transition: background-color 0.2s;
}

.submit-btn:hover {
  background-color: lighten($mocha-blue, 10%);
}

.submit-btn.disabled {
  background-color: $mocha-overlay0;
  cursor: not-allowed;
  opacity: 0.5;
}
```

### Real-Time Update Patterns

**Pattern 1: deflisten (streaming, <100ms latency) - RECOMMENDED**
```yuck
;; Best for real-time validation feedback
(deflisten validation_state
  :initial "{\"valid\": true, \"errors\": {}}"
  `form-validation-service --mode projects --listen`)
```

**Pattern 2: defpoll (polling, configurable interval)**
```yuck
;; Good for less critical validation (e.g., checking directory exists)
(defpoll validation_state
  :interval "1s"
  :initial "{\"valid\": true, \"errors\": {}}"
  `form-validation-service --mode projects`)
```

### Complete Form Example

```yuck
;; Project creation form widget
(defwidget project-creation-form []
  (box :class "form-container"
       :orientation "v"
       :space-evenly false
       :spacing 16

    ;; Header
    (label :class "form-title" :text "Create New Project")

    ;; Project name field
    (box :class "form-field" :orientation "v"
      (label :class "field-label" :text "Project Name *")
      (input
        :class {validation_state.errors?.project_name
                ? "input-field error"
                : "input-field"}
        :value {form_data.project_name}
        :onchange "update-form-field project_name {}"
        :timeout "300ms")
      (label
        :class "error-message"
        :visible {(validation_state.errors?.project_name ?: "") != ""}
        :text {validation_state.errors?.project_name ?: ""}))

    ;; Directory field
    (box :class "form-field" :orientation "v"
      (label :class "field-label" :text "Working Directory *")
      (input
        :class {validation_state.errors?.directory
                ? "input-field error"
                : "input-field"}
        :value {form_data.directory}
        :onchange "update-form-field directory {}"
        :timeout "300ms")
      (label
        :class "error-message"
        :visible {(validation_state.errors?.directory ?: "") != ""}
        :text {validation_state.errors?.directory ?: ""}))

    ;; Icon field (optional)
    (box :class "form-field" :orientation "v"
      (label :class "field-label" :text "Icon (emoji or path)")
      (input
        :class "input-field"
        :value {form_data.icon}
        :onchange "update-form-field icon {}"
        :timeout "300ms"))

    ;; Action buttons
    (box :class "form-actions"
         :orientation "h"
         :halign "end"
         :spacing 12
      (button
        :class "cancel-btn"
        :onclick "cancel-form"
        "Cancel")
      (button
        :class {validation_state.valid ? "submit-btn" : "submit-btn disabled"}
        :onclick {validation_state.valid ? "submit-project-create" : ""}
        :sensitive {validation_state.valid}
        "Create Project"))))
```

### Key Files

- **New**: `home-modules/tools/i3_project_manager/services/form_validator.py` (280 lines)
- **New**: `home-modules/tools/i3_project_manager/models/project_config.py` (150 lines, Pydantic models)
- **New**: `home-modules/tools/i3_project_manager/models/app_config.py` (220 lines, Pydantic models for 3 app types)
- **Modify**: `home-modules/desktop/eww-monitoring-panel.nix` (add form widgets, CSS, validation state)

---

## Summary

### Key Decisions

1. **Nix Editing**: Text-based manipulation with regex and templates (not AST-based)
2. **Form Validation**: Hybrid approach (Python backend + Yuck frontend feedback)
3. **Real-time Updates**: deflisten streaming with 300ms debouncing in backend
4. **Error Display**: Conditional CSS classes + error message labels below inputs
5. **ULID Generation**: Programmatic via existing `/etc/nixos/scripts/generate-ulid.sh`

### Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Regex-based Nix editing breaks on formatting changes | Test suite includes formatting variation tests; backup/restore on syntax errors |
| Backend validation service crashes | Graceful error handling; fallback to offline validation in frontend |
| Deflisten stream disconnects | Automatic reconnection with exponential backoff (existing pattern) |
| ULID collisions (extremely rare) | Retry generation up to 3 times; validate uniqueness before commit |
| Form state desync between Eww and backend | Single source of truth: backend reads form state from Eww variables |

### Dependencies Confirmed

- Python 3.11+ with `pydantic`, `i3ipc.aio`, `asyncio` (existing)
- Eww 0.4+ with deflisten support (existing)
- `nix-instantiate` for syntax validation (existing)
- `/etc/nixos/scripts/generate-ulid.sh` (existing)
- `i3pm` CLI for worktree creation (existing)

### Ready for Phase 1

All technical unknowns resolved. Ready to proceed to:
- **Phase 1**: Data model design, API contracts, quickstart guide
