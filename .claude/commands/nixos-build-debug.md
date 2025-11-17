---
description: Analyze NixOS build failures with AI-assisted error interpretation and fix suggestions
---

# NixOS Build Failure Debugger

You are analyzing a NixOS build failure to identify root causes and provide specific fixes.

## Task

Extract error information from build logs, classify the error type, and provide targeted remediation steps with exact code changes.

## Step 1: Check for Recent Build Failure

```bash
# Check if we have build logs
if [ -f /var/log/nixos-builds/last-build.json ]; then
  echo "=== Last Build Summary ==="
  cat /var/log/nixos-builds/last-build.json | jq -r '
    "Success: \(.success)",
    "Exit Code: \(.exitCode)",
    "Duration: \(.buildDuration)s",
    "Target: \(.target) \(.action)",
    "Command: \(.command)",
    "",
    "Errors:",
    .errors
  '
else
  echo "No structured build logs found"
  echo "Checking for alternative error sources..."
fi
```

## Step 2: Extract Error Details

```bash
# Get full error log if available
if [ -f /var/log/nixos-builds/last-build.log ]; then
  echo "=== Build Error Extract (last 100 lines) ==="
  tail -100 /var/log/nixos-builds/last-build.log | grep -A 5 -B 2 "error\|Error\|ERROR\|failed\|Failed" | head -50
else
  # Fallback: try to trigger evaluation and capture errors
  echo "=== Current Flake Evaluation ==="
  cd /etc/nixos
  nix flake check --no-build 2>&1 | head -50
fi
```

```bash
# Extract specific Nix error patterns
if [ -f /var/log/nixos-builds/last-build.log ]; then
  echo "=== Nix-Specific Errors ==="
  grep -E "error:|attribute .* missing|infinite recursion|syntax error|undefined variable" /var/log/nixos-builds/last-build.log 2>/dev/null | head -20
fi
```

## Step 3: Get Context Around Errors

```bash
# If build log exists, find the specific failing file/module
if [ -f /var/log/nixos-builds/last-build.log ]; then
  echo "=== File References in Errors ==="
  grep -oE "/etc/nixos/[^ :]+\.(nix|json)" /var/log/nixos-builds/last-build.log 2>/dev/null | sort | uniq -c | sort -rn | head -10
fi
```

```bash
# Check recent git changes that might have caused the error
cd /etc/nixos
echo "=== Recent Changes (potential culprits) ==="
git diff HEAD~3 --name-only 2>/dev/null | head -20
git log --oneline -5 2>/dev/null
```

## Step 4: Analyze Error Type

Classify the error into one of these categories:

### A. **Syntax Errors**
```
error: syntax error, unexpected ')', expecting ';'
```
- Missing semicolons, brackets, quotes
- Malformed attribute sets
- Invalid string interpolation

**Analysis approach:**
1. Identify exact file and line number
2. Read the file around that location
3. Check for matching brackets/braces
4. Verify string escaping

### B. **Attribute Errors**
```
error: attribute 'foo' missing
error: attribute 'bar' already defined
```
- Misspelled attribute names
- Removed/renamed options
- Conflicts between modules

**Analysis approach:**
1. Check if attribute was recently renamed in nixpkgs
2. Verify option paths against NixOS options
3. Look for similar named attributes

### C. **Type Errors**
```
error: expected a string but got a set
error: cannot coerce a set to a string
```
- Wrong type passed to option
- Missing lib.mkForce/lib.mkDefault
- Incorrect function arguments

**Analysis approach:**
1. Check option type in NixOS search
2. Verify value structure matches expected type
3. Look for type coercion needs

### D. **Infinite Recursion**
```
error: infinite recursion encountered
```
- Circular imports
- Self-referencing config
- Module evaluation loops

**Analysis approach:**
1. Find cycle in import chain
2. Check for accidental self-references
3. Use lib.mkMerge/lib.mkOverride properly

### E. **Package Build Failures**
```
error: builder for '/nix/store/...' failed
```
- Upstream build issue
- Missing dependencies
- Hardware-specific problems

**Analysis approach:**
1. Check if package is pinned to old version
2. Verify system architecture support
3. Look for overlay conflicts

### F. **Evaluation Errors**
```
error: undefined variable
error: called without required argument
```
- Missing imports
- Wrong function signatures
- Scope issues

**Analysis approach:**
1. Check imports at top of file
2. Verify function has all arguments
3. Ensure variables are in scope

## Step 5: Provide Specific Fix

Based on error classification, provide:

### 1. **Root Cause**
Explain exactly what went wrong in plain language.

### 2. **Location**
Exact file path and line number (if available).

### 3. **Fix Code**
Show the exact change needed:

```nix
# BEFORE (broken)
programs.foo = {
  enable = true
  option = "value";
};

# AFTER (fixed)
programs.foo = {
  enable = true;  # Added missing semicolon
  option = "value";
};
```

### 4. **Verification Command**

```bash
# Test the fix without applying
sudo nixos-rebuild dry-build --flake .#<target> --show-trace
```

### 5. **Prevention**
How to avoid this error in the future.

## Output Format

Structure your response as:

```
## NixOS Build Failure Analysis

### Error Classification
**Type:** [Syntax/Attribute/Type/Recursion/Package/Evaluation]
**Severity:** [Blocking/Critical/Moderate]

### Root Cause
[Clear explanation of what went wrong]

### Error Location
**File:** /etc/nixos/path/to/file.nix
**Line:** [if available]
**Context:** [surrounding code if helpful]

### Recommended Fix

[Code diff or exact change needed]

### Commands to Apply Fix

```bash
# 1. Read the broken file
# 2. Apply fix using Edit tool
# 3. Test: sudo nixos-rebuild dry-build --flake .#<target>
# 4. Apply: sudo nixos-rebuild switch --flake .#<target>
```

### Prevention Tips
- [How to avoid this in future]
- [Related best practices]

### Additional Resources
- NixOS Options: https://search.nixos.org/options
- Nix Manual: https://nixos.org/manual/nix/stable/
```

## Fallback: No Build Logs Available

If `/var/log/nixos-builds/` doesn't exist (wrapper not used), offer:

```bash
# Run a test build to capture errors
cd /etc/nixos
sudo nixos-rebuild dry-build --flake .#<TARGET> --show-trace 2>&1 | tee /tmp/nixos-build-debug.log

# Then analyze:
echo "=== Errors Found ==="
grep -E "error:|Error:" /tmp/nixos-build-debug.log | head -20
```

Ask user:
1. Which target (hetzner-sway, m1, wsl)?
2. Should I run a dry-build to capture errors?
3. Or analyze a specific file they suspect is broken?

## Common Quick Fixes

### Syntax Error - Missing Semicolon
```bash
# Find lines missing semicolons before }
grep -n "}" /etc/nixos/path/to/file.nix | while read line; do
  linenum=$(echo $line | cut -d: -f1)
  prev=$((linenum - 1))
  sed -n "${prev}p" /etc/nixos/path/to/file.nix | grep -v ";" | grep -v "^$" | grep -v "{" && echo "Line $prev might need semicolon"
done
```

### Attribute Missing - Check Option Exists
```bash
# Verify option path
nix-instantiate --eval -E '(import <nixpkgs/nixos> {}).options.programs.foo.enable or "NOT FOUND"'
```

### Package Not Building - Try Unstable
```nix
# Use package from unstable instead
environment.systemPackages = [
  pkgs-unstable.problematic-package  # Use newer version
];
```

## When to Use

Invoke this command when:
- `nixos-rebuild` fails with errors
- Configuration evaluation throws errors
- Package builds fail during rebuild
- Need to understand cryptic Nix error messages
- Want AI-assisted interpretation of build logs
