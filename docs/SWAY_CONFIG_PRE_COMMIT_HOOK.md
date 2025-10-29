# Sway Configuration Pre-Commit Hook Example

**Feature 047 Phase 8 T064**: Pre-commit hook for automatic validation

This document provides an example pre-commit hook that validates Sway configuration files before allowing git commits. This ensures that only valid configuration changes are committed to version control.

## Quick Setup

1. Create the pre-commit hook file:
   ```bash
   mkdir -p ~/.config/sway/.git/hooks
   cat > ~/.config/sway/.git/hooks/pre-commit << 'EOF'
   #!/usr/bin/env bash
   # Sway Configuration Pre-Commit Hook
   # Feature 047 Phase 8: Automatic validation before commit

   set -e

   echo "🔍 Validating Sway configuration before commit..."

   # Run validation via daemon IPC
   if command -v i3pm &> /dev/null; then
       # Use i3pm CLI if available
       if i3pm config validate --strict; then
           echo "✅ Configuration validation passed"
           exit 0
       else
           echo "❌ Configuration validation failed"
           echo ""
           echo "Fix validation errors before committing:"
           echo "  1. Run: i3pm config validate"
           echo "  2. Fix reported errors"
           echo "  3. Try commit again"
           echo ""
           echo "To bypass validation (not recommended):"
           echo "  git commit --no-verify"
           exit 1
       fi
   else
       echo "⚠️  Warning: i3pm command not found, skipping validation"
       exit 0
   fi
   EOF

   chmod +x ~/.config/sway/.git/hooks/pre-commit
   ```

2. Test the hook:
   ```bash
   cd ~/.config/sway
   echo "# Test comment" >> keybindings.toml
   git add keybindings.toml
   git commit -m "Test commit"  # Validation will run automatically
   ```

## Full Pre-Commit Hook Script

```bash
#!/usr/bin/env bash
#
# Sway Configuration Pre-Commit Hook
# Feature 047 Phase 8 T064: Automatic validation before commit
#
# This hook validates Sway configuration files before allowing commits.
# It ensures that only syntactically correct and semantically valid
# configuration changes are committed to version control.
#
# Installation:
#   cp this-file ~/.config/sway/.git/hooks/pre-commit
#   chmod +x ~/.config/sway/.git/hooks/pre-commit
#
# Bypass (when needed):
#   git commit --no-verify

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STRICT_MODE=true        # Enable strict validation (semantic checks)
SHOW_WARNINGS=true      # Show warnings in addition to errors
TIMEOUT=10              # Validation timeout in seconds

# Banner
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Sway Configuration Pre-Commit Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if i3pm is available
if ! command -v i3pm &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: i3pm command not found${NC}"
    echo "   Skipping validation (install i3pm for validation)"
    exit 0
fi

# Check if daemon is running
if ! i3pm daemon ping &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: Sway config daemon not running${NC}"
    echo "   Skipping validation (start daemon with: systemctl --user start sway-config-daemon)"
    exit 0
fi

# Build validation command
VALIDATE_CMD="i3pm config validate"
if [ "$STRICT_MODE" = true ]; then
    VALIDATE_CMD="$VALIDATE_CMD --strict"
fi

# Get list of staged configuration files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(toml|json)$' || true)

if [ -z "$STAGED_FILES" ]; then
    echo -e "${BLUE}ℹ️  No configuration files staged, skipping validation${NC}"
    exit 0
fi

echo "Validating staged configuration files:"
for file in $STAGED_FILES; do
    echo "  - $file"
done
echo ""

# Run validation with timeout
echo "Running validation..."
if timeout "$TIMEOUT" $VALIDATE_CMD > /tmp/sway-config-validation.log 2>&1; then
    VALIDATION_EXIT_CODE=0
else
    VALIDATION_EXIT_CODE=$?
fi

# Check if validation passed
if [ $VALIDATION_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ Configuration validation passed${NC}"
    echo ""

    # Show summary if available
    if grep -q "Files validated:" /tmp/sway-config-validation.log; then
        grep "Files validated:" /tmp/sway-config-validation.log
        grep "Duration:" /tmp/sway-config-validation.log
    fi

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    rm -f /tmp/sway-config-validation.log
    exit 0

elif [ $VALIDATION_EXIT_CODE -eq 124 ]; then
    # Timeout occurred
    echo -e "${RED}❌ Validation timed out after ${TIMEOUT}s${NC}"
    echo ""
    echo "This may indicate:"
    echo "  - Daemon is unresponsive"
    echo "  - Configuration files are very large"
    echo "  - System is under heavy load"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check daemon status: systemctl --user status sway-config-daemon"
    echo "  2. Try manual validation: i3pm config validate"
    echo "  3. Restart daemon: systemctl --user restart sway-config-daemon"
    echo ""
    rm -f /tmp/sway-config-validation.log
    exit 1

else
    # Validation failed
    echo -e "${RED}❌ Configuration validation failed${NC}"
    echo ""

    # Show validation errors
    if [ -f /tmp/sway-config-validation.log ]; then
        cat /tmp/sway-config-validation.log
        echo ""
    fi

    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "How to fix:"
    echo "  1. Review validation errors above"
    echo "  2. Fix configuration issues: i3pm config edit <type>"
    echo "  3. Validate manually: i3pm config validate"
    echo "  4. Try commit again"
    echo ""
    echo "To bypass validation (NOT recommended):"
    echo "  git commit --no-verify"
    echo ""

    rm -f /tmp/sway-config-validation.log
    exit 1
fi
```

## Configuration Options

You can customize the hook behavior by editing these variables at the top of the script:

- **STRICT_MODE**: Enable semantic validation (checks against actual Sway state)
  - `true`: Full validation including Sway IPC queries (recommended)
  - `false`: Only structural validation (syntax checking)

- **SHOW_WARNINGS**: Display warnings in addition to errors
  - `true`: Show all validation messages (recommended)
  - `false`: Only show errors

- **TIMEOUT**: Maximum validation time in seconds
  - Default: 10 seconds
  - Increase if you have large configuration files

## Validation Workflow

1. **Pre-commit trigger**: Git calls the hook when you run `git commit`

2. **Environment check**: Hook verifies i3pm CLI and daemon are available

3. **File detection**: Hook identifies staged configuration files (*.toml, *.json)

4. **Validation execution**: Hook runs `i3pm config validate` via daemon IPC

5. **Result handling**:
   - **Success**: Commit proceeds normally
   - **Failure**: Commit is blocked with error messages
   - **Timeout**: Commit is blocked with troubleshooting steps

6. **Bypass option**: Use `git commit --no-verify` to skip validation if needed

## Validation Checks

The pre-commit hook performs these validations:

### Structural Validation
- JSON/TOML syntax correctness
- Required fields presence
- Field type correctness
- Schema compliance

### Semantic Validation (with --strict)
- Workspace number existence (query Sway IPC)
- Output name validity (query Sway IPC)
- Keybinding syntax correctness
- Regex pattern validity
- Project override references

## Error Handling

### Common Errors

**"i3pm command not found"**
- Solution: Install i3pm CLI or skip validation
- Bypass: Hook automatically skips if i3pm unavailable

**"Daemon not running"**
- Solution: Start daemon with `systemctl --user start sway-config-daemon`
- Bypass: Hook automatically skips if daemon unavailable

**"Validation timeout"**
- Solution: Check daemon health with `i3pm daemon status`
- Increase timeout in hook configuration

**"Invalid keybinding syntax"**
- Solution: Fix keybinding format (e.g., `Mod+Return` not `Mod++Return`)
- Use `i3pm config validate` to see detailed error

**"Output does not exist"**
- Solution: Update workspace assignment output names
- Check valid outputs: `swaymsg -t get_outputs`

### Bypass Validation

If you need to commit without validation (emergency situations):

```bash
git commit --no-verify -m "Emergency commit"
```

**Warning**: Bypassing validation can break your Sway configuration. Only use in emergencies.

## Advanced Configuration

### Selective File Validation

Validate only specific file types:

```bash
# In pre-commit hook, replace STAGED_FILES detection:
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E 'keybindings\.toml|window-rules\.json' || true)
```

### Custom Validation Command

Use a different validation approach:

```bash
# Replace VALIDATE_CMD with custom command:
VALIDATE_CMD="python ~/.config/sway/validate-custom.py"
```

### Notification on Failure

Send desktop notification when validation fails:

```bash
# Add after validation failure:
notify-send -u critical "Sway Config" "Commit blocked - validation failed"
```

## Integration with CI/CD

For automated testing in CI/CD pipelines:

```yaml
# .github/workflows/validate-config.yml
name: Validate Sway Configuration

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install dependencies
        run: |
          # Install Sway and i3pm
          sudo apt-get update
          sudo apt-get install -y sway
          # Install i3pm (adjust for your setup)
      - name: Validate configuration
        run: |
          cd .config/sway
          i3pm config validate --strict
```

## Troubleshooting

### Hook not running

```bash
# Check hook file exists
ls -la ~/.config/sway/.git/hooks/pre-commit

# Check permissions
chmod +x ~/.config/sway/.git/hooks/pre-commit

# Test hook manually
cd ~/.config/sway
.git/hooks/pre-commit
```

### Validation always passes/fails

```bash
# Test validation manually
i3pm config validate

# Check daemon status
i3pm daemon status

# View validation logs
journalctl --user -u sway-config-daemon -n 50
```

### Performance issues

```bash
# Profile validation time
time i3pm config validate

# If >5s, check:
# - Daemon responsiveness
# - Configuration file size
# - System load
```

## Best Practices

1. **Always test before committing**: Run `i3pm config validate` manually first

2. **Keep commits small**: Validate incremental changes rather than large batches

3. **Use descriptive commit messages**: Include what configuration was changed

4. **Don't bypass validation**: Only use `--no-verify` in emergencies

5. **Monitor validation time**: If validation is slow, investigate daemon performance

6. **Regular daemon health checks**: Run `i3pm daemon status` periodically

## Related Documentation

- Configuration validation: `/etc/nixos/specs/047-create-a-new/quickstart.md` (Section 6)
- Version control: `/etc/nixos/specs/047-create-a-new/quickstart.md` (Section 7)
- CLI commands: `/etc/nixos/specs/047-create-a-new/contracts/cli-commands.md`
- Error handling: `/etc/nixos/docs/SWAY_CONFIG_ARCHITECTURE.md`

## Example Session

```bash
$ cd ~/.config/sway

$ # Make invalid change
$ echo "invalid syntax here" >> keybindings.toml

$ # Try to commit
$ git add keybindings.toml
$ git commit -m "Add new keybinding"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Sway Configuration Pre-Commit Validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Validating staged configuration files:
  - keybindings.toml

Running validation...
❌ Configuration validation failed

┌─ Validation Results ────────────────────────────────────────────────┐
│
│  ❌ Found 1 error(s):
│
│  [SYNTAX] keybindings.toml:45
│  Invalid TOML syntax: expected key-value pair
│  💡 Suggestion: Check TOML syntax using a validator
│
│  Files validated: 1
│  Duration: 234ms
│  Status: ❌ FAIL
│
└──────────────────────────────────────────────────────────────────────┘

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

How to fix:
  1. Review validation errors above
  2. Fix configuration issues: i3pm config edit keybindings
  3. Validate manually: i3pm config validate
  4. Try commit again

To bypass validation (NOT recommended):
  git commit --no-verify

$ # Fix the issue
$ vi keybindings.toml  # Remove invalid line

$ # Try again
$ git add keybindings.toml
$ git commit -m "Add new keybinding"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Sway Configuration Pre-Commit Validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Validating staged configuration files:
  - keybindings.toml

Running validation...
✅ Configuration validation passed

Files validated: 1
Duration: 189ms
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[main f9e8d7c] Add new keybinding
 1 file changed, 3 insertions(+)
```

## Summary

The pre-commit hook provides an automated safety net for Sway configuration changes:

- **Automatic validation** before every commit
- **Fast feedback** on syntax and semantic errors
- **Prevents invalid configuration** from being committed
- **Configurable strictness** and timeout settings
- **Graceful degradation** if daemon unavailable
- **Clear error messages** with fix suggestions
- **Bypass option** for emergency situations

Install the hook and never commit invalid Sway configuration again!
