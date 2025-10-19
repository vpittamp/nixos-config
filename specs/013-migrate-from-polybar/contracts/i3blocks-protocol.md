# i3blocks Protocol Contract

**Feature**: Migrate from Polybar to i3 Native Status Bar
**Date**: 2025-10-19
**Purpose**: Define the contract between i3blocks scripts and i3bar

## Overview

This document specifies the input/output contract for i3blocks status command scripts. All scripts MUST adhere to this protocol to ensure proper integration with i3bar.

## Script Execution Contract

### Input Environment

**Environment Variables** (provided by i3blocks):
- `BLOCK_NAME`: String - Block identifier from config (e.g., "cpu", "memory")
- `BLOCK_INSTANCE`: String - Optional instance identifier
- `BLOCK_BUTTON`: Integer - Mouse button clicked (1=left, 2=middle, 3=right, 4=scroll up, 5=scroll down)
- `BLOCK_X`, `BLOCK_Y`: Integer - Click coordinates (if click events enabled)

**Standard Input**: None (scripts should not read stdin)

**Command Line Arguments**: None (use environment variables or config)

### Output Format

**Two Supported Formats**:
1. **Plain Text**: Single line output, displayed as-is
2. **JSON**: Structured output with full control over appearance

### Output Requirements

- ✅ MUST write to stdout
- ✅ MUST NOT write to stderr (unless error condition)
- ✅ MUST complete within 5 seconds (recommended <100ms)
- ✅ MUST return exit code 0 on success
- ✅ MAY return non-zero exit code on error (block shows error state)

---

## Plain Text Format

**Simple output**: Just write text to stdout.

**Example**:
```bash
#!/usr/bin/env bash
echo "CPU: 25%"
```

**Limitations**:
- No color control (uses default statusline color)
- No separator control
- No markup support
- No click event handling

**Use Case**: Simple blocks where color/formatting not needed.

---

## JSON Format (Recommended)

**Protocol Version**: i3bar JSON protocol v1

**Output Structure**:
```json
{
  "full_text": "Required display text",
  "short_text": "Optional short version",
  "color": "#hexcolor",
  "background": "#hexcolor",
  "border": "#hexcolor",
  "border_top": 1,
  "border_bottom": 1,
  "border_left": 1,
  "border_right": 1,
  "min_width": 100,
  "align": "center",
  "separator": true,
  "separator_block_width": 15,
  "markup": "pango",
  "urgent": false
}
```

### Field Specifications

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `full_text` | String | ✅ Yes | N/A | Text to display |
| `short_text` | String | ❌ No | "" | Abbreviated text for narrow spaces |
| `color` | String | ❌ No | statusline color | Text color (#RRGGBB) |
| `background` | String | ❌ No | transparent | Background color |
| `border` | String | ❌ No | transparent | Border color (all sides) |
| `border_top` | Integer | ❌ No | 0 | Top border width (px) |
| `border_bottom` | Integer | ❌ No | 0 | Bottom border width (px) |
| `border_left` | Integer | ❌ No | 0 | Left border width (px) |
| `border_right` | Integer | ❌ No | 0 | Right border width (px) |
| `min_width` | Int/String | ❌ No | auto | Minimum block width |
| `align` | String | ❌ No | "left" | Text alignment ("left"\|"center"\|"right") |
| `separator` | Boolean | ❌ No | true | Show separator after block |
| `separator_block_width` | Integer | ❌ No | 9 | Separator width (px) |
| `markup` | String | ❌ No | "none" | Markup format ("none"\|"pango") |
| `urgent` | Boolean | ❌ No | false | Urgent state (highlight) |

### Color Specifications

**Format**: Hex color codes in format `#RRGGBB`

**Catppuccin Mocha Palette** (for consistency):
```json
{
  "normal": "#cdd6f4",    // Text (normal state)
  "dimmed": "#bac2de",    // Subtext0 (secondary info)
  "accent": "#b4befe",    // Lavender (primary accent)
  "success": "#a6e3a1",   // Green (good state)
  "warning": "#f9e2af",   // Yellow (warning state)
  "error": "#f38ba8",     // Red (error/urgent state)
  "background": "#1e1e2e" // Base (background)
}
```

### Markup Support

**Pango Markup** (when `"markup": "pango"`):
- `<b>bold</b>`
- `<i>italic</i>`
- `<u>underline</u>`
- `<s>strikethrough</s>`
- `<span foreground="#color">colored text</span>`
- `<span size="large">large text</span>`

**Example**:
```json
{
  "full_text": "<span foreground='#b4befe'></span> NixOS",
  "markup": "pango"
}
```

---

## Script Examples

### Example 1: Simple CPU Block (Plain Text)

```bash
#!/usr/bin/env bash
# Simple CPU usage display (plain text)

CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
echo "CPU: ${CPU}%"
```

**Output**: `CPU: 25%`

---

### Example 2: CPU Block with Color (JSON)

```bash
#!/usr/bin/env bash
# CPU usage with color coding

# Get CPU usage
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)

# Color based on threshold
if (( $(echo "$CPU > 95" | bc -l) )); then
  COLOR="#f38ba8"  # Red (urgent)
elif (( $(echo "$CPU > 80" | bc -l) )); then
  COLOR="#f9e2af"  # Yellow (warning)
else
  COLOR="#cdd6f4"  # Normal
fi

# Output JSON
cat <<EOF
{
  "full_text": "CPU: ${CPU}%",
  "color": "$COLOR",
  "separator": true,
  "separator_block_width": 15
}
EOF
```

---

### Example 3: Memory Block

```bash
#!/usr/bin/env bash
# Memory usage display

# Get memory info
MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))

# Color based on usage
if [ $MEM_PERCENT -gt 95 ]; then
  COLOR="#f38ba8"
elif [ $MEM_PERCENT -gt 80 ]; then
  COLOR="#f9e2af"
else
  COLOR="#cdd6f4"
fi

# Output JSON
cat <<EOF
{
  "full_text": "MEM: ${MEM_PERCENT}%",
  "color": "$COLOR"
}
EOF
```

---

### Example 4: Network Status

```bash
#!/usr/bin/env bash
# Network connection status

# Check primary network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -z "$INTERFACE" ]; then
  # No connection
  STATUS="disconnected"
  COLOR="#f38ba8"
else
  # Connected
  STATUS="$INTERFACE: up"
  COLOR="#a6e3a1"
fi

cat <<EOF
{
  "full_text": "$STATUS",
  "color": "$COLOR"
}
EOF
```

---

### Example 5: Date/Time

```bash
#!/usr/bin/env bash
# Date and time display

DATETIME=$(date '+%Y-%m-%d %H:%M')

cat <<EOF
{
  "full_text": "$DATETIME",
  "color": "#cdd6f4"
}
EOF
```

---

### Example 6: Project Indicator (Signal-Based)

```bash
#!/usr/bin/env bash
# Project context indicator (signal-driven)

PROJECT_FILE="$HOME/.config/i3/active-project"

# Check if file exists and is valid JSON
if [ -f "$PROJECT_FILE" ]; then
  # Parse JSON (requires jq)
  NAME=$(jq -r '.display_name // .name' "$PROJECT_FILE" 2>/dev/null)
  ICON=$(jq -r '.icon // ""' "$PROJECT_FILE" 2>/dev/null)
  
  if [ -n "$NAME" ] && [ "$NAME" != "null" ]; then
    # Active project
    TEXT="$ICON $NAME"
    COLOR="#b4befe"  # Lavender accent
  else
    # Invalid JSON or missing fields
    TEXT="∅"
    COLOR="#6c7086"  # Dimmed
  fi
else
  # No project active
  TEXT="∅"
  COLOR="#6c7086"
fi

cat <<EOF
{
  "full_text": "$TEXT",
  "color": "$COLOR",
  "separator": true,
  "separator_block_width": 15
}
EOF
```

**Signal Update**:
```bash
# From i3-project-switch script
pkill -RTMIN+10 i3blocks
```

**i3blocks config**:
```ini
[project]
command=/path/to/project.sh
interval=once
signal=10
```

---

## Click Event Handling (Optional)

### Enabling Click Events

**i3bar config**:
```nix
bars = [{
  # ...
  extraConfig = ''
    click_events yes
  '';
}];
```

### Processing Clicks

**Environment variables available**:
- `BLOCK_BUTTON`: 1=left, 2=middle, 3=right, 4=scroll up, 5=scroll down
- `BLOCK_X`, `BLOCK_Y`: Click coordinates

**Example**:
```bash
#!/usr/bin/env bash

case $BLOCK_BUTTON in
  1) # Left click - open system monitor
    alacritty -e htop &
    ;;
  3) # Right click - refresh
    # Just re-run to refresh
    ;;
esac

# Then output normal block data
echo '{"full_text":"CPU: 25%"}'
```

---

## Error Handling

### Script Errors

**Exit Codes**:
- `0`: Success - block displays normally
- `Non-zero`: Error - i3blocks may show error indicator

**Error Display**:
```bash
#!/usr/bin/env bash

# Try to get value
VALUE=$(command_that_might_fail 2>/dev/null)

if [ $? -ne 0 ]; then
  # Error occurred
  cat <<EOF
{
  "full_text": "ERROR",
  "color": "#f38ba8",
  "urgent": true
}
EOF
  exit 1
fi

# Normal output
echo "{\"full_text\":\"$VALUE\"}"
```

### Timeouts

**Best Practice**: Set timeout for external commands
```bash
# Use timeout command
RESULT=$(timeout 2s curl https://api.example.com/status 2>/dev/null)

if [ $? -eq 124 ]; then
  # Timeout occurred
  echo '{"full_text":"TIMEOUT","color":"#f38ba8"}'
  exit 1
fi
```

---

## Performance Guidelines

### Execution Time

- ✅ Target: <50ms per script execution
- ⚠️ Acceptable: <100ms
- ❌ Problematic: >500ms
- 🛑 Unacceptable: >5s (i3blocks timeout)

### Optimization Tips

1. **Avoid Heavy Commands**:
   - ❌ Don't: `top` (slow startup)
   - ✅ Do: Read `/proc` directly

2. **Cache Expensive Operations**:
```bash
CACHE_FILE="/tmp/i3blocks_cache_$$"
CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))

if [ $CACHE_AGE -gt 60 ]; then
  # Refresh cache
  expensive_operation > "$CACHE_FILE"
fi

cat "$CACHE_FILE"
```

3. **Minimize Subprocesses**:
   - ❌ Don't: Multiple `grep | awk | sed` pipes
   - ✅ Do: Single awk or direct file parsing

4. **Use Efficient Tools**:
   - Prefer: `grep`, `awk`, bash built-ins
   - Avoid: `python`, `ruby` (startup overhead)

---

## Testing Contract Compliance

### Validation Checklist

- [ ] Script outputs valid JSON or plain text
- [ ] JSON can be parsed by `jq` without errors
- [ ] Color codes are valid hex format (#RRGGBB)
- [ ] Script completes in <100ms (test with `time`)
- [ ] Script exits with code 0 on success
- [ ] Script handles missing dependencies gracefully
- [ ] Script doesn't write to stderr (unless error)
- [ ] Script doesn't require user input

### Test Commands

```bash
# Test script output
./cpu.sh | jq .

# Test execution time
time ./cpu.sh

# Test exit code
./cpu.sh; echo $?

# Test with signal
kill -RTMIN+10 $(pgrep i3blocks)
```

---

## Full i3blocks Configuration Example

```ini
# Global properties
separator_block_width=15
markup=pango

# CPU block
[cpu]
command=/home/user/.config/i3blocks/scripts/cpu.sh
interval=5
color=#cdd6f4

# Memory block
[memory]
command=/home/user/.config/i3blocks/scripts/memory.sh
interval=5
color=#cdd6f4

# Network block
[network]
command=/home/user/.config/i3blocks/scripts/network.sh
interval=10
color=#cdd6f4

# Project block (signal-based)
[project]
command=/home/user/.config/i3blocks/scripts/project.sh
interval=once
signal=10
color=#b4befe

# Date/time block
[datetime]
command=/home/user/.config/i3blocks/scripts/datetime.sh
interval=60
color=#cdd6f4
```

---

## Summary

**Input Contract**:
- Scripts receive environment variables (BLOCK_*)
- Scripts should not read stdin
- Scripts should not require arguments

**Output Contract**:
- Plain text: Single line to stdout
- JSON: Structured object with required `full_text` field
- Must complete within 5 seconds
- Exit 0 on success, non-zero on error

**Best Practices**:
- Use JSON for color control
- Keep execution time <100ms
- Handle errors gracefully
- Use Catppuccin colors for consistency
- Set appropriate signal numbers for event-driven blocks

**Validation**:
- Test with `jq` for JSON validity
- Test with `time` for performance
- Verify colors in #RRGGBB format
- Check exit codes
