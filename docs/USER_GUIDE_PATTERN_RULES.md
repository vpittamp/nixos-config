# Pattern Rules - User Guide

**Part of T097: User guide documentation**

Pattern rules allow you to automatically classify applications based on their window class names using glob or regex patterns.

## Table of Contents

- [Overview](#overview)
- [Pattern Types](#pattern-types)
- [Creating Patterns](#creating-patterns)
- [Testing Patterns](#testing-patterns)
- [Managing Patterns](#managing-patterns)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

### What are Pattern Rules?

Pattern rules classify applications based on matching their WM_CLASS (window class) against patterns. They're useful for:

- **Bulk classification**: Classify many similar apps at once
- **Dynamic apps**: Handle apps with changing window classes
- **PWAs**: Classify Progressive Web Apps with prefixes like `pwa-*`
- **Consistency**: Ensure new apps follow classification rules

### How They Work

1. When a window opens, i3pm extracts its WM_CLASS
2. Pattern rules are evaluated in priority order (highest first)
3. First matching pattern determines the classification
4. If no pattern matches, explicit lists are checked
5. Unmatched windows remain unclassified

### Pattern Priority

- Higher priority patterns are evaluated first
- Default priority is 0
- Priorities can be negative or positive
- Explicit lists (scoped_classes, global_classes) take precedence

## Pattern Types

### Glob Patterns

Use glob patterns for simple wildcard matching.

**Syntax**: `glob:pattern*`

**Examples**:
```bash
# Match all PWAs
glob:pwa-*

# Match terminal variants
glob:*terminal*

# Match Google apps
glob:Google-*
```

**Wildcards**:
- `*` - Matches any characters (including none)
- `?` - Matches exactly one character
- `[abc]` - Matches any character in brackets
- `[!abc]` - Matches any character NOT in brackets

### Regex Patterns

Use regex for complex matching.

**Syntax**: `regex:^pattern$`

**Examples**:
```bash
# Match exact class
regex:^Code$

# Match terminals ending in 'term'
regex:^.*term$

# Match versioned apps
regex:^app-v\d+\.\d+$
```

**Common Regex**:
- `^` - Start of string
- `$` - End of string
- `.` - Any character
- `.*` - Zero or more of any character
- `\d` - Any digit
- `+` - One or more
- `?` - Zero or one

### Literal Patterns

Plain strings match exactly (no wildcards).

**Examples**:
```bash
# Just the class name
Code
firefox
Ghostty
```

## Creating Patterns

### Using the CLI

```bash
# Basic pattern (scoped)
i3pm app-classes add-pattern "glob:terminal-*" scoped

# With priority (higher = evaluated first)
i3pm app-classes add-pattern "glob:pwa-*" global --priority 10

# With description
i3pm app-classes add-pattern "regex:^Code.*$" scoped \
  --priority 5 \
  --description "VS Code and variants"

# Preview with dry-run
i3pm app-classes add-pattern "glob:test-*" scoped --dry-run
```

### Using the Wizard

1. Launch wizard: `i3pm app-classes wizard`
2. Select an unclassified app
3. Press `p` to create pattern
4. Enter pattern in dialog
5. Pattern is automatically created and applied

### Editing Directly

Edit `~/.config/i3/app-classes.json`:

```json
{
  "scoped_classes": [],
  "global_classes": [],
  "class_patterns": [
    {
      "pattern": "glob:pwa-*",
      "scope": "global",
      "priority": 10,
      "description": "Progressive Web Apps"
    },
    {
      "pattern": "regex:^terminal.*$",
      "scope": "scoped",
      "priority": 5,
      "description": "All terminal emulators"
    }
  ]
}
```

## Testing Patterns

### Test Pattern Matching

```bash
# Test if a pattern matches a class
i3pm app-classes test-pattern "glob:pwa-*" "pwa-youtube"
# Output: ✓ Match: pwa-youtube matches glob:pwa-*

# Test regex
i3pm app-classes test-pattern "regex:^Code.*$" "Code-Insiders"
# Output: ✓ Match: Code-Insiders matches regex:^Code.*$

# Test no match
i3pm app-classes test-pattern "glob:test-*" "production-app"
# Output: ✗ No match: production-app does not match glob:test-*
```

### Validate Pattern Syntax

```bash
# Dry-run to check syntax before creating
i3pm app-classes add-pattern "regex:^[invalid(regex$" scoped --dry-run
# Output: Error: Invalid regex pattern
```

### Check Current Classification

```bash
# See what pattern matched a window
i3pm app-classes check pwa-youtube
# Output:
# WM_CLASS: pwa-youtube
# Classification: global
# Source: pattern (glob:pwa-*)
# Priority: 10
```

## Managing Patterns

### List All Patterns

```bash
# View all patterns
i3pm app-classes list-patterns

# Output (example):
# Pattern Rules (3):
# Priority  Pattern              Scope    Description
# --------  -------------------  -------  -------------------------
#       10  glob:pwa-*           global   Progressive Web Apps
#        5  regex:^terminal.*$   scoped   All terminal emulators
#        0  glob:*-dev           scoped   Development variants
```

### Remove Patterns

```bash
# Remove a pattern
i3pm app-classes remove-pattern "glob:test-*"

# Preview removal
i3pm app-classes remove-pattern "glob:test-*" --dry-run

# Skip confirmation
i3pm app-classes remove-pattern "glob:test-*" --yes
```

### Update Patterns

To update a pattern:
1. Remove the old pattern
2. Add the new pattern
3. Reload daemon: `systemctl --user restart i3-project-event-listener`

Or edit `~/.config/i3/app-classes.json` directly and reload.

## Examples

### Example 1: Progressive Web Apps

All PWAs have class names starting with `pwa-`. Classify them as global:

```bash
i3pm app-classes add-pattern "glob:pwa-*" global \
  --priority 10 \
  --description "Progressive Web Apps are always visible"
```

**Matches**:
- `pwa-youtube`
- `pwa-gmail`
- `pwa-claude`

### Example 2: Terminal Emulators

Match all terminal emulators:

```bash
i3pm app-classes add-pattern "regex:^.*term.*$" scoped \
  --priority 5 \
  --description "All terminal applications"
```

**Matches**:
- `Ghostty`
- `Alacritty`
- `xterm`
- `gnome-terminal`

### Example 3: Development Tools

Match development variants of apps:

```bash
i3pm app-classes add-pattern "glob:*-dev" scoped \
  --description "Development versions"

i3pm app-classes add-pattern "glob:*-canary" scoped \
  --description "Canary builds"
```

**Matches**:
- `Code-Insiders` (if named `Code-dev`)
- `firefox-dev`
- `chrome-canary`

### Example 4: Version-specific Apps

Match apps with version numbers:

```bash
i3pm app-classes add-pattern "regex:^app-v\d+\.\d+$" scoped \
  --priority 3 \
  --description "Versioned app instances"
```

**Matches**:
- `app-v1.0`
- `app-v2.5`
- `app-v10.23`

### Example 5: Exclude from Classification

Use high priority to exclude certain patterns:

```bash
# First, create specific exception (high priority)
i3pm app-classes add-pattern "glob:browser-testing" global \
  --priority 20 \
  --description "Testing browser stays global"

# Then, general browser rule (lower priority)
i3pm app-classes add-pattern "glob:browser-*" scoped \
  --priority 5 \
  --description "Browser variants are scoped"
```

## Troubleshooting

### Pattern Not Matching

**Symptom**: Pattern should match but doesn't classify apps.

**Solutions**:

1. **Test the pattern**:
   ```bash
   i3pm app-classes test-pattern "your-pattern" "actual-class-name"
   ```

2. **Check priority order**:
   ```bash
   i3pm app-classes list-patterns
   # Higher priority patterns are checked first
   ```

3. **Verify window class**:
   ```bash
   # Get actual window class
   i3pm app-classes inspect --focused
   # Look at the "WM_CLASS" field
   ```

4. **Reload daemon**:
   ```bash
   systemctl --user restart i3-project-event-listener
   ```

### Pattern Matches Too Much

**Symptom**: Pattern classifies unintended apps.

**Solutions**:

1. **Make pattern more specific**:
   ```bash
   # Too broad
   glob:*term*

   # More specific
   glob:*-terminal

   # Most specific
   regex:^(alacritty|ghostty|xterm)$
   ```

2. **Add exception with higher priority**:
   ```bash
   # Exception (high priority)
   i3pm app-classes add-pattern "glob:special-terminal" global \
     --priority 10

   # General rule (lower priority)
   i3pm app-classes add-pattern "glob:*terminal" scoped \
     --priority 5
   ```

### Regex Errors

**Symptom**: Pattern fails with "Invalid regex" error.

**Solutions**:

1. **Escape special characters**:
   ```bash
   # Wrong
   regex:^app.v1$

   # Right (escape the dot)
   regex:^app\.v1$
   ```

2. **Test regex separately**:
   ```bash
   # Use test-pattern first
   i3pm app-classes test-pattern "regex:^test$" "test"
   ```

3. **Use glob instead**:
   ```bash
   # Complex regex
   regex:^[a-z]+-v\d+\.\d+$

   # Simpler glob
   glob:*-v*
   ```

### Pattern Order Issues

**Symptom**: Wrong pattern is matching first.

**Solutions**:

1. **Check priority**:
   ```bash
   i3pm app-classes list-patterns
   # Patterns are shown in priority order
   ```

2. **Adjust priorities**:
   ```bash
   # Remove old pattern
   i3pm app-classes remove-pattern "glob:old-pattern"

   # Add with new priority
   i3pm app-classes add-pattern "glob:old-pattern" scoped \
     --priority 15
   ```

3. **Remember**: Higher number = checked first

## Best Practices

### 1. Start with Specific Patterns

Begin with narrow, specific patterns and expand as needed:

```bash
# Start specific
glob:pwa-youtube

# Then expand
glob:pwa-*
```

### 2. Use Descriptive Names

Always add descriptions to remember why patterns exist:

```bash
i3pm app-classes add-pattern "glob:*-dev" scoped \
  --description "Development builds - project specific"
```

### 3. Test Before Applying

Use dry-run and test-pattern:

```bash
# Test match
i3pm app-classes test-pattern "glob:new-*" "new-app"

# Dry-run creation
i3pm app-classes add-pattern "glob:new-*" scoped --dry-run
```

### 4. Use Priority Wisely

- **20+**: Exceptions and overrides
- **10**: Important general rules
- **5**: Standard classifications
- **0**: Catch-all patterns (default)
- **Negative**: Low priority fallbacks

### 5. Document Complex Patterns

For complex regex, add explanation:

```json
{
  "pattern": "regex:^(code|codium|code-insiders)$",
  "scope": "scoped",
  "priority": 5,
  "description": "VS Code family: official, OSS, and Insiders builds"
}
```

## Related Guides

- [Classification Wizard](USER_GUIDE_WIZARD.md) - Interactive classification
- [Window Inspector](USER_GUIDE_INSPECTOR.md) - Inspect window properties
- [Xvfb Detection](USER_GUIDE_XVFB.md) - Detect window classes

---

**Last updated**: 2025-10-21 (T097 implementation)
