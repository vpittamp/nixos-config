# EWW Widgets Reference

Complete reference for EWW (Elkowar's Wacky Widgets) in this NixOS configuration.

## Contents

- [Widget Types](#widget-types)
- [Variable Definitions](#variable-definitions)
- [Window Definitions](#window-definitions)
- [Common Widgets](#common-widgets)
- [Events and Handlers](#events-and-handlers)
- [Styling](#styling)
- [Existing Bar Components](#existing-bar-components)
- [Backend Scripts](#backend-scripts)

## Widget Types

### Container Widgets

#### box
Primary layout container for arranging children.

```yuck
(box
  :class "my-container"
  :orientation "vertical"      ;; "vertical"/"v" or "horizontal"/"h"
  :space-evenly false          ;; Distribute children evenly
  :spacing 4                   ;; Gap between children (px)
  :halign "center"             ;; "start", "center", "end", "fill"
  :valign "center"
  :hexpand true                ;; Expand horizontally
  :vexpand false
  (child1)
  (child2))
```

#### centerbox
Three-child layout (start, center, end).

```yuck
(centerbox
  :orientation "horizontal"
  (left-widget)
  (center-widget)
  (right-widget))
```

#### overlay
Stack children on top of each other.

```yuck
(overlay
  (background-widget)
  (foreground-widget))
```

#### scroll
Scrollable container for single child.

```yuck
(scroll
  :hscroll true
  :vscroll true
  (large-content))
```

#### stack
Display one child at a time (tab-like).

```yuck
(stack
  :selected active_tab
  :transition "slideright"
  :same-size true
  (tab1)
  (tab2)
  (tab3))
```

### Display Widgets

#### label
Text display with formatting options.

```yuck
(label
  :text "Plain text"
  :markup "<b>Bold</b> text"    ;; Pango markup
  :truncate true                ;; Truncate long text
  :limit-width 20               ;; Character limit
  :wrap true                    ;; Word wrap
  :angle 90                     ;; Rotation in degrees
  :xalign 0.5                   ;; 0.0-1.0
  :yalign 0.5
  :justify "center")            ;; "left", "center", "right", "fill"
```

#### image
Display images (PNG, SVG, etc.).

```yuck
(image
  :path "/path/to/image.png"
  :image-width 32
  :image-height 32
  :preserve-aspect-ratio true
  :icon "firefox"               ;; GTK icon name
  :icon-size "large")           ;; "small", "medium", "large"
```

### Progress Widgets

#### progress
Linear progress bar.

```yuck
(progress
  :value 75                     ;; 0-100
  :orientation "horizontal"
  :flipped false)
```

#### circular-progress
Circular progress indicator.

```yuck
(circular-progress
  :value 75
  :start-at 75                  ;; Start angle (0=top, 25=right, 50=bottom, 75=left)
  :thickness 4
  :clockwise true
  (label :text "${value}%"))    ;; Optional center content
```

#### graph
Real-time value visualization.

```yuck
(graph
  :value current_value
  :thickness 2
  :time-range 60                ;; Seconds of history
  :min 0
  :max 100
  :dynamic true                 ;; Auto-scale
  :line-style "round")
```

### Interactive Widgets

#### button
Clickable element.

```yuck
(button
  :onclick "swaymsg workspace 1"
  :onmiddleclick "notify-send 'Middle click'"
  :onrightclick "notify-send 'Right click'"
  :class "my-button"
  (label :text "Click me"))
```

#### eventbox
Event-responsive container with hover, scroll, drag.

```yuck
(eventbox
  :onclick "echo clicked"
  :onmiddleclick "echo middle"
  :onrightclick "echo right"
  :onscroll "echo {}"           ;; {} = "up" or "down"
  :onhover "eww update hover=true"
  :onhoverlost "eww update hover=false"
  :cursor "pointer"             ;; GTK cursor name
  :ondropped "echo dropped"
  :dragvalue "data"
  :dragtype "text"
  (content))
```

#### scale
Slider control.

```yuck
(scale
  :value 50
  :min 0
  :max 100
  :orientation "horizontal"
  :onchange "pactl set-sink-volume @DEFAULT_SINK@ {}%"
  :flipped false
  :marks true
  :draw-value true
  :round-digits 0)
```

#### input
Text input field.

```yuck
(input
  :value initial_text
  :onchange "echo {}"
  :onaccept "echo submitted: {}"
  :password false)
```

#### checkbox
Toggle control.

```yuck
(checkbox
  :checked is_enabled
  :onchecked "echo enabled"
  :onunchecked "echo disabled")
```

### Animation Widgets

#### revealer
Animated show/hide.

```yuck
(revealer
  :reveal show_content
  :transition "slidedown"       ;; slideup, slidedown, slideleft, slideright, crossfade, none
  :duration "200ms"
  (hidden-content))
```

#### transform
Geometric transformations.

```yuck
(transform
  :rotate 45
  :translate-x 10
  :translate-y 10
  :scale-x 1.5
  :scale-y 1.5
  :transform-origin-x 0.5
  :transform-origin-y 0.5
  (content))
```

### Special Widgets

#### literal
Render dynamically generated Yuck.

```yuck
(literal
  :content widget_markup)       ;; String containing Yuck code
```

#### tooltip
Custom tooltip.

```yuck
(tooltip
  (tooltip-content)             ;; First child = tooltip
  (trigger-widget))             ;; Second child = trigger
```

#### systray
System notification icons.

```yuck
(systray
  :spacing 8
  :orientation "horizontal"
  :icon-size 16
  :prepend-new true)
```

#### calendar
Date selector.

```yuck
(calendar
  :day 15
  :month 6
  :year 2025
  :show-details true
  :show-heading true
  :show-day-names true
  :onclick "echo {0}-{1}-{2}")  ;; day-month-year
```

## Variable Definitions

### defvar (Static)
Updated via `eww update`.

```yuck
(defvar show_popup false)
(defvar active_tab 0)
(defvar selected_workspace 1)

;; Update from shell:
;; eww update show_popup=true
;; eww update active_tab=2
```

### defpoll (Periodic)
Run script at intervals.

```yuck
(defpoll system_metrics
  :interval "2s"                ;; Poll interval
  :initial '{"cpu":0}'          ;; Initial JSON value
  :run-while panel_visible      ;; Only run when condition true
  `python3 scripts/metrics.py`)
```

### deflisten (Event-driven)
Continuous script output monitoring.

```yuck
(deflisten notifications
  :initial '{"count":0}'
  `python3 scripts/notification-monitor.py`)
```

Backend script must:
- Output one JSON line per update
- Flush stdout immediately
- Run indefinitely

```python
#!/usr/bin/env python3
import json
import sys
import time

while True:
    data = {"count": get_notification_count()}
    print(json.dumps(data), flush=True)
    time.sleep(1)
```

### Magic Variables
Built-in system access.

```yuck
;; Access JSON fields
{system_metrics.cpu_load}
{notifications.count}

;; Array access
{workspaces[0].name}

;; Conditional
{condition ? "true-value" : "false-value"}

;; String interpolation
"CPU: ${system_metrics.cpu_load}%"

;; Comparison
{value > 50 ? "high" : "low"}

;; Boolean operators
{a && b}
{a || b}
{!a}

;; Arithmetic
{value + 10}
{value * 2}
```

## Window Definitions

### Basic Window

```yuck
(defwindow my-bar
  :monitor "HEADLESS-1"         ;; Output name, index, or "<primary>"
  :geometry (geometry
    :x "0px"                    ;; Position (px or %)
    :y "0px"
    :width "100%"
    :height "30px"
    :anchor "top center")       ;; top/center/bottom + left/center/right
  :stacking "fg"                ;; fg, bg, overlay, bottom
  :exclusive true               ;; Reserve screen space
  :focusable false
  :namespace "eww-my-bar"       ;; Sway app_id
  :reserve (struts              ;; Reserve space for bar
    :distance "30px"
    :side "top")
  :windowtype "dock"            ;; dock, dialog, etc.
  (bar-content))
```

### Window with Arguments

```yuck
(defwindow workspace-bar [monitor_id]
  :monitor monitor_id
  :geometry (geometry ...)
  (workspace-content :monitor monitor_id))
```

Open with: `eww open workspace-bar --arg monitor_id=HEADLESS-1`

## Events and Handlers

### Click Events

```yuck
;; Single command
:onclick "swaymsg workspace 1"

;; Multiple commands
:onclick "command1; command2"

;; With variables
:onclick "eww update selected=${id}"

;; EWW built-in actions
:onclick "eww close my-window"
:onclick "eww open other-window"
:onclick "eww update var=value"
```

### Scroll Events

```yuck
;; {} expands to "up" or "down"
:onscroll "pactl set-sink-volume @DEFAULT_SINK@ {}5%"

;; Conditional scroll
:onscroll "[ {} = 'up' ] && cmd-up || cmd-down"
```

### Hover Events

```yuck
(eventbox
  :onhover "eww update hover_${id}=true"
  :onhoverlost "eww update hover_${id}=false"
  :cursor "pointer"
  (box :class {hover ? "hovered" : ""}
    (content)))
```

## Styling

### SCSS Structure

```scss
// Theme colors (Catppuccin Mocha)
$base: #1e1e2e;
$surface0: #313244;
$surface1: #45475a;
$text: #cdd6f4;
$subtext0: #a6adc8;
$blue: #89b4fa;
$green: #a6e3a1;
$red: #f38ba8;
$yellow: #f9e2af;
$teal: #94e2d5;

// Widget styling
.my-widget {
  background-color: rgba($base, 0.85);
  border-radius: 12px;
  padding: 4px 8px;
  margin: 2px;

  // Nested elements
  .label {
    color: $text;
    font-size: 12px;
    font-family: "JetBrainsMono Nerd Font";
  }

  // State-based styling
  &.active {
    background-color: rgba($blue, 0.3);
    border: 1px solid $blue;
  }

  &:hover {
    background-color: rgba($surface1, 0.9);
  }
}

// Progress bar styling
.progress-bar {
  background-color: $surface0;
  border-radius: 4px;

  progressbar {
    background-color: $blue;
    border-radius: 4px;
  }
}

// Scale (slider) styling
scale {
  trough {
    background-color: $surface0;
    min-height: 6px;
    border-radius: 3px;
  }

  highlight {
    background-color: $blue;
    border-radius: 3px;
  }

  slider {
    background-color: $text;
    min-height: 14px;
    min-width: 14px;
    border-radius: 50%;
  }
}
```

### Common Patterns

```scss
// Glassmorphism effect
.glass {
  background-color: rgba($base, 0.7);
  backdrop-filter: blur(10px);
  border: 1px solid rgba($text, 0.1);
}

// Pill-shaped buttons
.pill {
  border-radius: 999px;
  padding: 4px 12px;
}

// Smooth transitions
.animated {
  transition: all 150ms ease-in-out;
}

// Color-coded metrics
.metric-cpu { color: $blue; }
.metric-mem { color: $teal; }
.metric-disk { color: $yellow; }
.metric-temp { color: $red; }
```

## Existing Bar Components

### Top Bar (`eww-top-bar`)
Location: `home-modules/desktop/eww-top-bar/`

**Windows**: One per monitor (top-bar-headless1, top-bar-dp1, etc.)

**Widgets**:
- System metrics (CPU, memory, disk, network, temperature)
- WiFi status
- Volume control with popup
- Battery indicator
- Bluetooth status
- Notification badge
- AI session indicator
- Build health
- Date/time
- Powermenu overlay

**Key Data Sources**:
```yuck
(defpoll system_metrics :interval "2s" ...)
(deflisten volume ...)
(deflisten battery ...)
(deflisten bluetooth ...)
(deflisten notification_data ...)
(deflisten ai_sessions_data ...)
```

### Monitoring Panel (`eww-monitoring-panel`)
Location: `home-modules/desktop/eww-monitoring-panel/`

**Windows**:
- `monitoring-panel-overlay` - Floating mode (no space reservation)
- `monitoring-panel-docked` - Reserved space mode

**Features**:
- Windows view (active windows by workspace)
- Projects view (git worktrees)
- Tabbed interface (Alt+1-7)
- Dock mode toggle (Mod+Shift+M)

**Key Data Sources**:
```yuck
(deflisten monitoring_data ...)
(defpoll projects_data :interval "10s" ...)
```

### Workspace Bar (`eww-workspace-bar`)
Location: `home-modules/desktop/eww-workspace-bar/`

**Windows**: One per monitor (bottom of screen)

**Features**:
- Workspace indicators with app icons
- Focused/visible/urgent states
- Workspace preview overlay

**Key Data Sources**:
```yuck
(deflisten workspace_strip_headless1 ...)
(deflisten workspace_preview ...)
```

### Device Controls (`eww-device-controls`)
Location: `home-modules/desktop/eww-device-controls/`

**Components**:
- Top bar indicators (volume, brightness, bluetooth, battery)
- Monitoring panel sections (audio, display, bluetooth, power, thermal, network)

**Structure**:
```
widgets/
├── indicators/       # Top bar quick access
│   ├── volume.yuck.nix
│   ├── brightness.yuck.nix
│   ├── bluetooth.yuck.nix
│   └── battery.yuck.nix
└── sections/         # Full device controls
    ├── audio.yuck.nix
    ├── display.yuck.nix
    └── ...
```

## Backend Scripts

### Python Script Pattern

```python
#!/usr/bin/env python3
"""EWW backend script template."""

import json
import sys
import time

def get_data():
    """Collect current state."""
    return {
        "metric1": 50,
        "metric2": "active",
        "items": ["a", "b", "c"]
    }

def main():
    """Main loop - output JSON on each update."""
    while True:
        try:
            data = get_data()
            print(json.dumps(data), flush=True)
        except Exception as e:
            error = {"error": str(e)}
            print(json.dumps(error), flush=True)
        time.sleep(1)

if __name__ == "__main__":
    main()
```

### Bash Script Pattern

```bash
#!/usr/bin/env bash
# EWW backend script template

get_data() {
    local metric1=$(command-to-get-metric)
    local metric2=$(another-command)

    jq -nc \
        --arg m1 "$metric1" \
        --arg m2 "$metric2" \
        '{"metric1": ($m1 | tonumber), "metric2": $m2}'
}

# Single query mode
if [[ -z "${LISTEN:-}" ]]; then
    get_data
    exit 0
fi

# Continuous mode (for deflisten)
while true; do
    get_data
    sleep 1
done
```

### Script Locations

| Bar | Script Directory |
|-----|------------------|
| Top Bar | `~/.config/eww/eww-top-bar/scripts/` |
| Monitoring Panel | `~/.config/eww-monitoring-panel/scripts/` |
| Workspace Bar | `~/.config/eww-workspace-bar/scripts/` |
| Device Controls | `~/.config/eww/eww-device-controls/scripts/` |

## Debugging

```bash
# Check EWW logs
eww logs

# List active windows
eww active-windows

# Get variable state
eww state

# Reload config
eww reload

# Close all windows
eww close-all

# Debug mode
eww daemon --debug
```
