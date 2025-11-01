# i3bar Protocol Contract

**Feature**: Enhanced Swaybar Status
**Protocol**: i3bar protocol (swaybar-compatible)
**Version**: 1.0
**Reference**: https://i3wm.org/docs/i3bar-protocol.html

## Overview

The status generator communicates with swaybar using the i3bar protocol:
- **Output** (generator → swaybar): JSON arrays of status blocks printed to stdout
- **Input** (swaybar → generator): JSON click events read from stdin

## Status Block Output Contract

### Header

First line printed to stdout must be the protocol version header:

```json
{"version": 1}
```

### Status Array

After the header, print a JSON array on each update:

```json
[
  {
    "full_text": "<span font='NerdFont'>󰕾</span> 75%",
    "short_text": "75%",
    "color": "#a6e3a1",
    "markup": "pango",
    "name": "volume",
    "instance": "default"
  },
  {
    "full_text": "<span font='NerdFont'>󰁹</span> 85%",
    "short_text": "85%",
    "color": "#a6e3a1",
    "markup": "pango",
    "name": "battery"
  }
]
```

### Status Block Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `full_text` | string | **Yes** | Full text to display (supports pango markup) |
| `short_text` | string | No | Abbreviated text for small displays |
| `color` | string | No | Foreground color (#RRGGBB format) |
| `background` | string | No | Background color (#RRGGBB format) |
| `border` | string | No | Border color (#RRGGBB format) |
| `border_top` | integer | No | Top border width in pixels (default: 0) |
| `border_right` | integer | No | Right border width in pixels (default: 0) |
| `border_bottom` | integer | No | Bottom border width in pixels (default: 0) |
| `border_left` | integer | No | Left border width in pixels (default: 0) |
| `min_width` | integer or string | No | Minimum block width (pixels or string length) |
| `align` | string | No | Text alignment: "left", "center", "right" (default: "left") |
| `name` | string | No | Block identifier for click events |
| `instance` | string | No | Instance identifier for multiple blocks of same type |
| `urgent` | boolean | No | Highlight block (default: false) |
| `separator` | boolean | No | Show separator after block (default: true) |
| `separator_block_width` | integer | No | Separator width in pixels (default: 9) |
| `markup` | string | No | Markup type: "none", "pango" (default: "none") |

### Pango Markup Support

When `markup: "pango"` is set, `full_text` can contain Pango markup:

```xml
<span font='NerdFont' foreground='#a6e3a1'>󰕾</span> <b>75%</b>
```

Supported tags:
- `<span>`: Font, foreground, background, size, weight, style
- `<b>`: Bold
- `<i>`: Italic
- `<u>`: Underline
- `<s>`: Strikethrough

### Update Frequency

Status blocks should be printed at appropriate intervals:
- **Volume**: 1 second (or on change if D-Bus signals available)
- **Battery**: 30 seconds
- **Network**: 5 seconds
- **Bluetooth**: 10 seconds

## Click Event Input Contract

### Click Event Stream

swaybar sends click events as newline-delimited JSON to stdin:

```json
{"name":"volume","instance":"default","button":1,"modifiers":[],"x":1234,"y":5,"relative_x":45,"relative_y":5,"width":100,"height":20}
```

### Click Event Schema

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Block name from status block |
| `instance` | string | Block instance from status block |
| `button` | integer | Mouse button: 1 (left), 2 (middle), 3 (right), 4 (scroll up), 5 (scroll down) |
| `modifiers` | array | Key modifiers: "Shift", "Control", "Mod1" (Alt), "Mod4" (Super) |
| `x` | integer | Absolute X coordinate of click |
| `y` | integer | Absolute Y coordinate of click |
| `relative_x` | integer | X coordinate relative to block |
| `relative_y` | integer | Y coordinate relative to block |
| `width` | integer | Block width in pixels |
| `height` | integer | Block height in pixels |

### Expected Click Handlers

| Block Name | Button | Action |
|------------|--------|--------|
| `volume` | Left (1) | Launch `pavucontrol` |
| `volume` | Scroll Up (4) | Increase volume by 5% |
| `volume` | Scroll Down (5) | Decrease volume by 5% |
| `battery` | Left (1) | Show power statistics |
| `network` | Left (1) | Launch `nm-connection-editor` or network menu |
| `bluetooth` | Left (1) | Launch `blueman-manager` or bluetooth menu |

## Protocol Flow

```
Status Generator                    swaybar
      │                                │
      ├─────> {"version": 1}          │
      │                                │
      ├─────> [StatusBlock, ...]  ────> Display blocks
      │                                │
      │  <──── ClickEvent JSON ────────┤
      │                                │
      ├─ Handle click (launch app) ──>│
      │                                │
      ├─────> [Updated blocks...]  ───> Update display
      │                                │
```

## Error Handling

### Invalid JSON
If generator outputs invalid JSON, swaybar may display error or ignore output.

**Mitigation**: Validate JSON before printing with `json.dumps()` in Python.

### Missing Required Fields
If `full_text` is missing, block will not render.

**Mitigation**: Ensure all StatusBlock instances have `full_text` set.

### Long Text Overflow
If `full_text` is too long, it may be truncated or overflow status bar.

**Mitigation**: Provide `short_text` alternative and limit `full_text` length.

### Click Event Errors
If click handler fails to launch, error should be logged but status generator must continue.

**Mitigation**: Use `subprocess.Popen()` with error handling; don't block main loop.

## Testing

### Manual Testing
```bash
# Test status generator standalone
python status-generator.py

# Pipe to jq for validation
python status-generator.py | jq .

# Test click events
echo '{"name":"volume","button":1,"x":0,"y":0}' | python status-generator.py
```

### Integration Testing
```bash
# Test with swaybar
swaymsg bar mode invisible  # Hide current bar
swaymsg bar status_command python /path/to/status-generator.py
```

## Reference Implementation

See `home-modules/desktop/swaybar/status-generator.py` for full implementation.
