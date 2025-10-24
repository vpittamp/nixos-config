# Secure Variable Substitution - Practical Examples & Quick Reference

**Companion to**: `research-variable-substitution.md`
**Purpose**: Quick reference guide with code snippets for implementation

---

## Quick Reference: Safe vs Unsafe Patterns

### ✅ SAFE: Argument Array Execution

```bash
#!/usr/bin/env bash
# Recommended approach

PROJECT_DIR="/home/user/My Projects/nixos"

# Build argument array
ARGS=("code" "$PROJECT_DIR")

# Execute safely (no shell interpretation)
exec "${ARGS[@]}"
```

**Why safe**:
- Variables passed as separate arguments
- Double quotes preserve spaces
- No shell metacharacter interpretation
- Direct `exec` (no subshell)

---

### ❌ UNSAFE: String Concatenation with eval

```bash
#!/usr/bin/env bash
# NEVER DO THIS

PROJECT_DIR="/tmp/normal; rm -rf ~"

# Build command string
COMMAND="code $PROJECT_DIR"

# Execute (VULNERABLE)
eval "$COMMAND"
# Result: Opens /tmp/normal, then DELETES HOME DIRECTORY
```

**Why unsafe**:
- `eval` interprets shell metacharacters
- Semicolon splits into two commands
- No validation of directory content

---

### ❌ UNSAFE: Unquoted Variable Expansion

```bash
#!/usr/bin/env bash
# NEVER DO THIS

PROJECT_DIR="/home/user/My Projects/nixos"

# Execute with unquoted variable
exec code $PROJECT_DIR
# Expands to: code /home/user/My Projects/nixos
# Shell sees 4 arguments: "code", "/home/user/My", "Projects/nixos"
```

**Why unsafe**:
- Word splitting on spaces
- Glob expansion on wildcards
- Path interpreted as multiple arguments

---

## Wrapper Script Implementation Template

### Complete Implementation

```bash
#!/usr/bin/env bash
# /etc/nixos/scripts/app-launcher-wrapper.sh
# Secure application launcher with project context variable substitution

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

APP_NAME="${1:?ERROR: Missing application name argument}"
shift  # Remaining args passed to application

REGISTRY_FILE="${HOME}/.config/i3/application-registry.json"
I3PM_BIN="${I3PM_BIN:-i3pm}"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
    logger -t app-launcher "$*"
}

error() {
    notify-send "Launcher Error" "$*"
    log "ERROR: $*"
    exit 1
}

warn() {
    notify-send "Launcher Warning" "$*"
    log "WARN: $*"
}

# Validate project directory is safe to use
validate_directory() {
    local dir="$1"

    # Must be non-empty
    [[ -n "$dir" ]] || return 1

    # Must be absolute path
    [[ "$dir" = /* ]] || {
        log "SECURITY: Rejected non-absolute path: $dir"
        return 1
    }

    # Must exist and be a directory
    [[ -d "$dir" ]] || {
        log "Validation failed: Directory not found: $dir"
        return 1
    }

    # Must not contain newlines (suspicious)
    [[ "$dir" != *$'\n'* ]] || {
        log "SECURITY: Rejected path with newline: $dir"
        return 1
    }

    # Must not contain null bytes (always invalid)
    [[ "$dir" != *$'\0'* ]] || {
        log "SECURITY: Rejected path with null byte: $dir"
        return 1
    }

    return 0
}

# Validate parameters field contains no shell metacharacters
validate_parameters() {
    local params="$1"

    # Check for command substitution
    if [[ "$params" == *'$('* ]] || [[ "$params" == *'`'* ]]; then
        error "SECURITY: Command substitution not allowed in parameters: $params"
    fi

    # Check for command separators
    if [[ "$params" =~ [;\|\&] ]]; then
        error "SECURITY: Shell operators not allowed in parameters: $params"
    fi

    # Check for suspicious patterns
    if [[ "$params" =~ \$\{.*\} ]]; then
        error "SECURITY: Parameter expansion not allowed: $params"
    fi

    return 0
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

# Load application registry
[[ -f "$REGISTRY_FILE" ]] || error "Registry not found: $REGISTRY_FILE"

# Get application definition
APP_DEF=$(jq -r --arg name "$APP_NAME" \
    '.[] | select(.name == $name)' "$REGISTRY_FILE" 2>/dev/null)

[[ -n "$APP_DEF" ]] || error "Application not found in registry: $APP_NAME"

# Extract application properties
COMMAND=$(echo "$APP_DEF" | jq -r '.command')
PARAMETERS=$(echo "$APP_DEF" | jq -r '.parameters // ""')
SCOPE=$(echo "$APP_DEF" | jq -r '.scope // "global"')

# Validate extracted values
[[ -n "$COMMAND" ]] || error "Invalid registry entry: missing command for $APP_NAME"

# Validate parameters field if present
[[ -n "$PARAMETERS" ]] && validate_parameters "$PARAMETERS"

# ============================================================================
# PROJECT CONTEXT RESOLUTION
# ============================================================================

PROJECT_DIR=""
PROJECT_NAME=""
SESSION_NAME=""

if [[ "$SCOPE" == "scoped" ]]; then
    # Query daemon for active project context
    if command -v "$I3PM_BIN" &>/dev/null; then
        PROJECT_JSON=$("$I3PM_BIN" project current 2>/dev/null || echo "{}")

        PROJECT_DIR=$(echo "$PROJECT_JSON" | jq -r '.directory // ""')
        PROJECT_NAME=$(echo "$PROJECT_JSON" | jq -r '.name // ""')
        SESSION_NAME="$PROJECT_NAME"  # Session name matches project name

        # Validate project directory if provided
        if [[ -n "$PROJECT_DIR" ]]; then
            if ! validate_directory "$PROJECT_DIR"; then
                warn "Project directory validation failed: $PROJECT_DIR\nLaunching in global mode"
                PROJECT_DIR=""
                PROJECT_NAME=""
                SESSION_NAME=""
            fi
        fi
    else
        warn "i3pm not found - cannot query project context\nLaunching in global mode"
    fi

    # If scoped app but no project context, log warning
    if [[ -z "$PROJECT_NAME" ]]; then
        log "Launching scoped app '$APP_NAME' in global mode (no active project)"
    fi
fi

# ============================================================================
# VARIABLE SUBSTITUTION
# ============================================================================

PARAM_RESOLVED=""

if [[ -n "$PARAMETERS" ]]; then
    # Start with original parameters
    PARAM_RESOLVED="$PARAMETERS"

    # Replace $PROJECT_DIR (if available)
    if [[ -n "$PROJECT_DIR" ]]; then
        PARAM_RESOLVED="${PARAM_RESOLVED//\$PROJECT_DIR/$PROJECT_DIR}"
    fi

    # Replace $PROJECT_NAME (if available)
    if [[ -n "$PROJECT_NAME" ]]; then
        PARAM_RESOLVED="${PARAM_RESOLVED//\$PROJECT_NAME/$PROJECT_NAME}"
    fi

    # Replace $SESSION_NAME (if available)
    if [[ -n "$SESSION_NAME" ]]; then
        PARAM_RESOLVED="${PARAM_RESOLVED//\$SESSION_NAME/$SESSION_NAME}"
    fi

    # Check if substitution occurred
    # If parameters still contain $ variables, they weren't resolved
    if [[ "$PARAM_RESOLVED" == *'$'* ]]; then
        # Check if unresolved variables remain
        if [[ "$PARAM_RESOLVED" =~ \$PROJECT_DIR|\$PROJECT_NAME|\$SESSION_NAME ]]; then
            warn "Some variables could not be resolved in: $PARAMETERS\nProceeding with: $PARAM_RESOLVED"
        fi
    fi

    # If no substitution occurred and variables were expected, skip parameter
    if [[ "$PARAM_RESOLVED" == "$PARAMETERS" ]] && [[ "$PARAMETERS" == *'$'* ]]; then
        log "No variable substitution occurred - skipping parameters: $PARAMETERS"
        PARAM_RESOLVED=""
    fi
fi

# ============================================================================
# COMMAND EXECUTION
# ============================================================================

# Build argument array (SAFE - no shell interpretation)
ARGS=()
ARGS+=("$COMMAND")

# Add resolved parameters (if any)
if [[ -n "$PARAM_RESOLVED" ]]; then
    # Split parameters on spaces (simple approach)
    # Note: This doesn't handle quoted spaces in parameters
    # For complex argument parsing, use array parsing
    read -ra PARAM_ARGS <<< "$PARAM_RESOLVED"
    ARGS+=("${PARAM_ARGS[@]}")
fi

# Add any extra arguments passed to wrapper
ARGS+=("$@")

# Log launch (for debugging and audit trail)
log "Launching application '$APP_NAME': ${ARGS[*]} (project: ${PROJECT_NAME:-global})"

# Execute command
# Use exec to replace wrapper process with application
# Maintains clean process tree
exec "${ARGS[@]}"

# If exec fails, error message
error "Failed to execute: ${ARGS[*]}"
```

---

## Desktop File Generation Pattern

### home-manager Module Example

```nix
# home-modules/desktop/app-registry.nix
{ config, pkgs, ... }:

let
  # Application registry entries
  apps = [
    {
      name = "vscode";
      displayName = "VS Code";
      command = "code";
      parameters = "$PROJECT_DIR";
      scope = "scoped";
      icon = "vscode";
    }
    {
      name = "firefox";
      displayName = "Firefox Browser";
      command = "firefox";
      parameters = "";
      scope = "global";
      icon = "firefox";
    }
    {
      name = "lazygit";
      displayName = "LazyGit";
      command = "ghostty";
      parameters = "-e lazygit --work-tree=$PROJECT_DIR";
      scope = "scoped";
      icon = "git";
    }
  ];

  # Launcher wrapper script path
  wrapperScript = "${pkgs.writeShellScript "app-launcher-wrapper" ''
    # ... (full wrapper script from above)
  ''}";

  # Generate desktop file for an application
  mkDesktopEntry = app: {
    name = app.name;
    value = {
      name = app.displayName;
      comment = "Launch ${app.displayName} with project context";

      # CRITICAL: Use wrapper script, NOT direct command
      exec = "${wrapperScript} ${app.name} %f";

      icon = app.icon;
      terminal = false;
      type = "Application";

      # Categories based on scope
      categories = if app.scope == "scoped"
        then [ "Development" "ProjectScoped" ]
        else [ "Application" ];

      # StartupWMClass for window rules integration
      startupWMClass = app.expectedClass or null;
    };
  };

in {
  # Write application registry to JSON file
  home.file.".config/i3/application-registry.json".text = builtins.toJSON apps;

  # Generate desktop files
  xdg.desktopEntries = builtins.listToAttrs (map mkDesktopEntry apps);
}
```

**Key Points**:
1. ✅ Exec line calls wrapper script (no inline variables)
2. ✅ Application name passed as argument
3. ✅ Registry written to JSON for runtime access
4. ✅ Desktop files auto-generated (no manual creation)

---

## Variable Substitution Test Cases

### Test Script

```bash
#!/usr/bin/env bash
# test-variable-substitution.sh
# Run comprehensive tests on wrapper script

set -euo pipefail

WRAPPER_SCRIPT="./app-launcher-wrapper.sh"
TEST_REGISTRY="/tmp/test-registry.json"
TEST_LOG="/tmp/launcher-test.log"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper
test_launch() {
    local test_name="$1"
    local expected_result="$2"  # "success" or "error"
    shift 2

    echo "Testing: $test_name"

    if "$WRAPPER_SCRIPT" "$@" &> "$TEST_LOG"; then
        if [[ "$expected_result" == "success" ]]; then
            echo "  ✅ PASS"
            ((TESTS_PASSED++))
        else
            echo "  ❌ FAIL (expected error, got success)"
            ((TESTS_FAILED++))
        fi
    else
        if [[ "$expected_result" == "error" ]]; then
            echo "  ✅ PASS (correctly rejected)"
            ((TESTS_PASSED++))
        else
            echo "  ❌ FAIL (expected success, got error)"
            cat "$TEST_LOG"
            ((TESTS_FAILED++))
        fi
    fi
}

# Setup test registry
cat > "$TEST_REGISTRY" <<'EOF'
[
  {
    "name": "test-normal",
    "command": "echo",
    "parameters": "$PROJECT_DIR",
    "scope": "scoped"
  },
  {
    "name": "test-injection",
    "command": "echo",
    "parameters": "$PROJECT_DIR; rm -rf ~",
    "scope": "scoped"
  },
  {
    "name": "test-global",
    "command": "echo",
    "parameters": "hello world",
    "scope": "global"
  }
]
EOF

export HOME=/tmp
export REGISTRY_FILE="$TEST_REGISTRY"

# ============================================================================
# TEST CASES
# ============================================================================

echo "Starting variable substitution security tests..."
echo

# Test 1: Normal path with spaces
export PROJECT_DIR="/home/user/My Projects/nixos"
test_launch "Normal path with spaces" "success" "test-normal"

# Test 2: Path with dollar sign
export PROJECT_DIR="/home/user/\$projects/nixos"
test_launch "Path with dollar sign" "success" "test-normal"

# Test 3: Semicolon injection attempt (should be rejected)
test_launch "Semicolon injection attempt" "error" "test-injection"

# Test 4: Global application (no project context)
unset PROJECT_DIR
test_launch "Global application" "success" "test-global"

# Test 5: Empty project directory
export PROJECT_DIR=""
test_launch "Empty project directory" "success" "test-normal"

# Test 6: Non-existent directory
export PROJECT_DIR="/tmp/nonexistent-$(date +%s)"
test_launch "Non-existent directory" "error" "test-normal"

# Test 7: Relative path (should be rejected)
export PROJECT_DIR="./relative/path"
test_launch "Relative path" "error" "test-normal"

# Test 8: Path with newline (should be rejected)
export PROJECT_DIR=$'/tmp/test\nmalicious'
test_launch "Path with newline" "error" "test-normal"

# ============================================================================
# RESULTS
# ============================================================================

echo
echo "========================================="
echo "Test Results:"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "========================================="

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
```

---

## CLI Validation Command

### i3pm apps validate Implementation

```typescript
// home-modules/tools/app-launcher/src/commands/validate.ts

import { readApplicationRegistry } from "../registry.ts";

interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
}

/**
 * Validate application registry for security and correctness
 */
export async function validateRegistry(): Promise<ValidationResult> {
  const result: ValidationResult = {
    valid: true,
    errors: [],
    warnings: [],
  };

  try {
    const registry = await readApplicationRegistry();

    for (const app of registry) {
      // Validate required fields
      if (!app.name) {
        result.errors.push(`Application missing 'name' field`);
        result.valid = false;
      }

      if (!app.command) {
        result.errors.push(`Application '${app.name}': missing 'command' field`);
        result.valid = false;
      }

      // Validate parameters field (if present)
      if (app.parameters) {
        const paramErrors = validateParameters(app.parameters);
        if (paramErrors.length > 0) {
          result.errors.push(
            `Application '${app.name}': ${paramErrors.join(", ")}`
          );
          result.valid = false;
        }
      }

      // Validate command exists
      const commandExists = await checkCommandExists(app.command);
      if (!commandExists) {
        result.warnings.push(
          `Application '${app.name}': command '${app.command}' not found in PATH`
        );
      }

      // Validate scope value
      if (app.scope && !["scoped", "global"].includes(app.scope)) {
        result.errors.push(
          `Application '${app.name}': invalid scope '${app.scope}' (must be 'scoped' or 'global')`
        );
        result.valid = false;
      }
    }
  } catch (error) {
    result.errors.push(`Failed to read registry: ${error.message}`);
    result.valid = false;
  }

  return result;
}

/**
 * Validate parameters field for security issues
 */
function validateParameters(params: string): string[] {
  const errors: string[] = [];

  // Check for command substitution
  if (params.includes("$(") || params.includes("`")) {
    errors.push("Command substitution not allowed: $() or `");
  }

  // Check for command separators
  if (/[;|&]/.test(params)) {
    errors.push("Shell operators not allowed: ; | &");
  }

  // Check for parameter expansion
  if (/\$\{.*\}/.test(params)) {
    errors.push("Parameter expansion not allowed: ${}");
  }

  // Check for allowed variables only
  const vars = params.match(/\$[A-Z_]+/g) || [];
  const allowed = ["$PROJECT_DIR", "$PROJECT_NAME", "$SESSION_NAME", "$WORKSPACE"];
  const invalid = vars.filter((v) => !allowed.includes(v));

  if (invalid.length > 0) {
    errors.push(
      `Invalid variables: ${invalid.join(", ")}. Allowed: ${allowed.join(", ")}`
    );
  }

  return errors;
}

/**
 * Check if command exists in PATH
 */
async function checkCommandExists(command: string): Promise<boolean> {
  try {
    const process = new Deno.Command("which", {
      args: [command],
      stdout: "null",
      stderr: "null",
    });
    const { success } = await process.output();
    return success;
  } catch {
    return false;
  }
}

/**
 * Main entry point for validate command
 */
export async function validateCommand(): Promise<void> {
  console.log("Validating application registry...\n");

  const result = await validateRegistry();

  // Print errors
  if (result.errors.length > 0) {
    console.error("❌ Errors:");
    for (const error of result.errors) {
      console.error(`  - ${error}`);
    }
    console.error("");
  }

  // Print warnings
  if (result.warnings.length > 0) {
    console.warn("⚠️  Warnings:");
    for (const warning of result.warnings) {
      console.warn(`  - ${warning}`);
    }
    console.warn("");
  }

  // Print result
  if (result.valid) {
    console.log("✅ Registry validation passed");
    Deno.exit(0);
  } else {
    console.error("❌ Registry validation failed");
    Deno.exit(1);
  }
}
```

---

## Quick Decision Matrix

### When to Use Each Approach

| Scenario | Recommended Approach | Rationale |
|----------|---------------------|-----------|
| Application takes directory as first argument | **Tier 1**: No variables, pass `$PROJECT_DIR` directly | Simplest, safest |
| Application needs `--flag=$VALUE` format | **Tier 2**: Restricted substitution | Necessary for flexibility |
| Application needs complex shell syntax | ❌ **Reconsider registry approach** | Too risky, use dedicated script |
| User types arbitrary command (fzf launcher) | **No substitution** | Trust user input, execute directly |
| Registry-defined command (auto-launch) | **Tier 2** with validation | Balance security and flexibility |

---

## Checklist for Implementation

### Pre-Implementation
- [ ] Review `research-variable-substitution.md` in full
- [ ] Understand attack vectors (Section 2)
- [ ] Review test cases (Section 7)

### Implementation Phase
- [ ] Implement wrapper script with argument array execution
- [ ] Add `validate_directory()` function with all checks
- [ ] Add `validate_parameters()` function with regex checks
- [ ] Implement variable substitution with `${VAR//pattern/replacement}`
- [ ] Log all launches with `logger -t app-launcher`
- [ ] Add error messages with `notify-send`

### Validation Phase
- [ ] Run test script with all edge cases
- [ ] Test with project containing spaces in path
- [ ] Test with project containing `$` in path
- [ ] Test injection attempts (semicolon, pipe, backtick)
- [ ] Test global mode (no active project)
- [ ] Test scoped mode with missing directory

### Documentation Phase
- [ ] Update CLAUDE.md with launcher commands
- [ ] Create quickstart guide with examples
- [ ] Document allowed variables
- [ ] Document security model (trusted registry)

---

**END OF QUICK REFERENCE**
