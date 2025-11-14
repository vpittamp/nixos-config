{ config, lib, ... }:

# Eww styles (CSS/SCSS) for top bar
# Feature 060: Catppuccin Mocha theme matching bottom workspace bar

let
  # Catppuccin Mocha colors
  mocha = {
    base = "#1e1e2e";
    surface0 = "#313244";
    text = "#cdd6f4";
    subtext0 = "#a6adc8";
    blue = "#89b4fa";
    sapphire = "#74c7ec";
    sky = "#89dceb";
    teal = "#94e2d5";
    peach = "#fab387";
    green = "#a6e3a1";
    yellow = "#f9e2af";
    red = "#f38ba8";
  };

in
''
/* Eww Top Bar Styles - Feature 060: Catppuccin Mocha Theme */

* {
  all: unset;
  font-family: "FiraCode Nerd Font", "Font Awesome 6 Free";
  font-size: 10px;
}

/* ============================================================================
   Top Bar Container
   ============================================================================ */

.top-bar {
  background-color: rgba(30, 30, 46, 0.85);  /* ${mocha.base} with transparency */
  border-radius: 6px;
  padding: 4px 12px;
  margin: 4px;
}

/* ============================================================================
   Block Layouts
   ============================================================================ */

.left-block,
.center-block,
.right-block {
  padding: 0 8px;
}

.metric-block {
  padding: 2px 6px;
  margin: 0 2px;
}

/* ============================================================================
   Separator
   ============================================================================ */

.separator {
  color: ${mocha.subtext0};
  font-size: 8px;
  opacity: 0.5;
  padding: 0 4px;
}

/* ============================================================================
   Icons (Nerd Fonts)
   ============================================================================ */

.icon {
  font-family: "FiraCode Nerd Font";
  font-size: 11px;
  margin-right: 4px;
}

/* CPU icon - blue */
.cpu-icon {
  color: ${mocha.blue};
}

/* Memory icon - sapphire */
.memory-icon {
  color: ${mocha.sapphire};
}

/* Disk icon - sky */
.disk-icon {
  color: ${mocha.sky};
}

/* Network icon - teal */
.network-icon {
  color: ${mocha.teal};
}

/* Temperature icon - peach */
.temp-icon {
  color: ${mocha.peach};
}

/* Volume icon - green (unmuted) / red (muted) */
.volume-icon {
  color: ${mocha.green};
}

/* Battery icon - color-coded by level */
.battery-icon {
  color: ${mocha.green};  /* Default: normal level */
}

.battery-icon.battery-low {
  color: ${mocha.yellow};  /* Warning: 20-50% */
}

.battery-icon.battery-critical {
  color: ${mocha.red};  /* Critical: <20% */
}

/* Bluetooth icon - color-coded by state */
.bluetooth-icon {
  color: ${mocha.blue};  /* Default */
}

.bluetooth-icon.bluetooth-connected {
  color: ${mocha.blue};  /* Connected: blue */
}

.bluetooth-icon.bluetooth-enabled {
  color: ${mocha.green};  /* Enabled but not connected: green */
}

.bluetooth-icon.bluetooth-disabled {
  color: ${mocha.subtext0};  /* Disabled: gray */
}

/* Active Project icon - subtext color */
.project-icon {
  color: ${mocha.subtext0};
}

/* Daemon Health icon - color-coded by status */
.daemon-icon {
  color: ${mocha.green};  /* Default: healthy */
}

.daemon-icon.daemon-healthy {
  color: ${mocha.green};  /* Healthy (<100ms): green */
}

.daemon-icon.daemon-slow {
  color: ${mocha.yellow};  /* Slow (100-500ms): yellow */
}

.daemon-icon.daemon-unhealthy {
  color: ${mocha.red};  /* Unhealthy (>500ms or unresponsive): red */
}

/* Date/Time icon - text color */
.datetime-icon {
  color: ${mocha.text};
}

/* ============================================================================
   Values (metric text)
   ============================================================================ */

.value {
  color: ${mocha.text};
  font-size: 9px;
}

/* Specific value colors can be added here if needed */
.cpu-value,
.memory-value,
.disk-value,
.network-value,
.temp-value,
.volume-value,
.battery-value,
.bluetooth-value,
.project-value,
.daemon-value,
.datetime-value {
  color: ${mocha.text};
}

/* ============================================================================
   Visibility and Transitions
   ============================================================================ */

/* Note: GTK CSS doesn't support attribute selectors like [visible="false"]
 * Visibility is controlled by the :visible property in eww.yuck widgets instead
 * Widgets with :visible false won't render at all */

/* Smooth transitions for value changes */
.value {
  transition: color 0.2s ease;
}
''
