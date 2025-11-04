#!/usr/bin/env bash
# i3bar Event-Driven Status Script
# Subscribes to i3pm daemon events for instant status updates
# Follows i3bar protocol: https://i3wm.org/docs/i3bar-protocol.html

set -euo pipefail

# Output name passed as parameter (e.g., "rdp0" or "rdp1")
OUTPUT_NAME="${1:-unknown}"

# Configuration paths (will be substituted by Nix)
I3PM_BIN="@i3pm@"
JQ_BIN="@jq@"
SED_BIN="@sed@"
DATE_BIN="@date@"
GREP_BIN="@grep@"
AWK_BIN="@awk@"
XTERM_BIN="@xterm@"
WALKER_BIN="@walker@"
WALKER_PROJECT_LIST_BIN="@walker_project_list@"
WALKER_PROJECT_SWITCH_BIN="@walker_project_switch@"

# Colors (Catppuccin Mocha)
COLOR_LAVENDER="#b4befe"
COLOR_GREEN="#a6e3a1"
COLOR_BLUE="#89b4fa"
COLOR_YELLOW="#f9e2af"
COLOR_TEAL="#94e2d5"
COLOR_TEXT="#cdd6f4"
COLOR_SUBTEXT="#bac2de"
COLOR_SURFACE0="#313244"

# Build project block
build_project_block() {
    local current project_info icon display_name

    # Get current project name (extract from "Name: <project>" line)
    current=$("$I3PM_BIN" project current 2>/dev/null | \
        "$GREP_BIN" "^  Name:" | \
        "$AWK_BIN" '{print $2}' || echo "")

    if [ -z "$current" ]; then
        # No active project - global mode
        "$JQ_BIN" -n --arg text "∅ Global" \
            '{
                full_text: $text,
                color: "'"$COLOR_SUBTEXT"'",
                name: "project",
                instance: "global",
                separator: false,
                separator_block_width: 20,
                min_width: 150,
                align: "center"
            }'
    else
        # Get project info (icon + display name) from project list
        project_info=$("$I3PM_BIN" project list --json 2>/dev/null | \
            "$JQ_BIN" -r ".projects[] | select(.name == \"$current\") | \"\(.icon // \"📁\") \(.display_name // .name)\"" || echo "📁 $current")

        "$JQ_BIN" -n --arg text "$project_info" --arg instance "$current" \
            '{
                full_text: $text,
                color: "'"$COLOR_LAVENDER"'",
                name: "project",
                instance: $instance,
                separator: false,
                separator_block_width: 20,
                min_width: 150,
                align: "center"
            }'
    fi
}

# Build CPU block
build_cpu_block() {
    local cpu_usage

    # Get CPU usage from /proc/stat
    cpu_usage=$(grep 'cpu ' /proc/stat | "$AWK_BIN" '{
        usage=($2+$4)*100/($2+$4+$5)
    } END {
        printf "%.0f", usage
    }')

    "$JQ_BIN" -n --arg usage "$cpu_usage" \
        '{
            full_text: (" CPU " + $usage + "%"),
            color: "'"$COLOR_GREEN"'",
            name: "cpu",
            instance: "cpu0"
        }'
}

# Build memory block
build_memory_block() {
    local mem_usage

    # Get memory usage from /proc/meminfo
    mem_usage=$(grep -E '^(MemTotal|MemAvailable):' /proc/meminfo | "$AWK_BIN" '
        /MemTotal/ { total=$2 }
        /MemAvailable/ { available=$2 }
        END {
            used = total - available
            percentage = (used / total) * 100
            printf "%.0f", percentage
        }
    ')

    "$JQ_BIN" -n --arg usage "$mem_usage" \
        '{
            full_text: (" MEM " + $usage + "%"),
            color: "'"$COLOR_BLUE"'",
            name: "memory",
            instance: "mem0"
        }'
}

# Build network block
build_network_block() {
    local ip_addr interface

    # Find first active network interface with IP
    interface=$(ip -o -4 addr show | grep -v "127.0.0.1" | head -1 | "$AWK_BIN" '{print $2}' || echo "")

    if [ -n "$interface" ]; then
        ip_addr=$(ip -o -4 addr show "$interface" | "$AWK_BIN" '{print $4}' | cut -d'/' -f1)
        "$JQ_BIN" -n --arg ip "$ip_addr" --arg iface "$interface" \
            '{
                full_text: (" " + $ip),
                color: "'"$COLOR_TEAL"'",
                name: "network",
                instance: $iface
            }'
    else
        "$JQ_BIN" -n \
            '{
                full_text: "󰌙 Disconnected",
                color: "'"$COLOR_SUBTEXT"'",
                name: "network",
                instance: "none"
            }'
    fi
}

# Build date block
build_date_block() {
    local datetime
    datetime=$("$DATE_BIN" '+%a %b %d %H:%M')

    "$JQ_BIN" -n --arg datetime "$datetime" \
        '{
            full_text: (" " + $datetime),
            color: "'"$COLOR_YELLOW"'",
            name: "date",
            instance: "datetime"
        }'
}

# Build monitor block (shows which output this bar is on)
build_monitor_block() {
    local display_name

    # Show friendly name for the output
    case "$OUTPUT_NAME" in
        rdp0)
            display_name="Monitor 1"
            ;;
        rdp1)
            display_name="Monitor 2"
            ;;
        rdp2)
            display_name="Monitor 3"
            ;;
        *)
            display_name="$OUTPUT_NAME"
            ;;
    esac

    "$JQ_BIN" -n --arg name "$display_name" --arg output "$OUTPUT_NAME" \
        '{
            full_text: ("󰍹 " + $name),
            color: "'"$COLOR_LAVENDER"'",
            name: "monitor",
            instance: $output,
            separator: false,
            separator_block_width: 20
        }'
}

# Build spacer block (for centering project)
build_spacer_block() {
    "$JQ_BIN" -n \
        '{
            full_text: "",
            separator: false,
            separator_block_width: 0,
            min_width: 200,
            align: "center"
        }'
}

# Build complete status line
build_status_line() {
    local monitor spacer1 project spacer2 cpu memory network date

    monitor=$(build_monitor_block)
    spacer1=$(build_spacer_block)
    project=$(build_project_block)
    spacer2=$(build_spacer_block)
    cpu=$(build_cpu_block)
    memory=$(build_memory_block)
    network=$(build_network_block)
    date=$(build_date_block)

    # Layout: [monitor] [spacer] [project] [spacer] [cpu] [memory] [network] [date]
    # The spacers push project toward the center
    # Workspace mode indicator is shown via Sway's native binding_mode_indicator (Feature 042)
    "$JQ_BIN" -n \
        --argjson monitor "$monitor" \
        --argjson spacer1 "$spacer1" \
        --argjson project "$project" \
        --argjson spacer2 "$spacer2" \
        --argjson cpu "$cpu" \
        --argjson memory "$memory" \
        --argjson network "$network" \
        --argjson date "$date" \
        '[$monitor, $spacer1, $project, $spacer2, $cpu, $memory, $network, $date]'
}

# Handle click events from i3bar
handle_click_event() {
    local click_data="$1"
    local name button

    # Parse click event JSON
    name=$(echo "$click_data" | "$JQ_BIN" -r '.name // ""')
    button=$(echo "$click_data" | "$JQ_BIN" -r '.button // 0')

    case "$name" in
        project)
            if [ "$button" = "1" ]; then
                # Left click: Launch Walker in dmenu mode with project list
                # Use walker-project-list to populate the menu and walker-project-switch to handle selection
                # Placeholder text guides the user and improves UX
                (
                    SELECTED=$("$WALKER_PROJECT_LIST_BIN" | GDK_BACKEND=x11 "$WALKER_BIN" --dmenu -p "Select project or clear to return to global mode..." 2>/dev/null)
                    if [ -n "$SELECTED" ]; then
                        "$WALKER_PROJECT_SWITCH_BIN" "$SELECTED"
                    fi
                ) &
            elif [ "$button" = "3" ]; then
                # Right click: Clear project (global mode)
                "$I3PM_BIN" project clear >/dev/null 2>&1 &
            fi
            ;;
    esac
}

# Main: Output i3bar protocol
main() {
    # Output header
    echo '{"version":1,"click_events":true}'
    echo '['

    # Output initial status line with current state
    initial_status=$(build_status_line)
    echo "$initial_status,"

    # Start event-driven status updates in background
    # Listen to daemon tick events for instant project updates (<100ms latency)
    (
        # Initial update
        status_line=$(build_status_line)
        printf '%s,\n' "$status_line"

        # Subscribe to daemon events (blocks until events occur)
        # Updates: instant on tick events, every 2s for system stats
        "$I3PM_BIN" daemon events --follow 2>/dev/null | while read -r event; do
            # Rebuild status on any daemon event (tick, window, etc.)
            status_line=$(build_status_line)
            printf '%s,\n' "$status_line"
        done &

        # Fallback: periodic refresh for system stats (CPU, memory, network, time)
        # This runs even if daemon events stop flowing
        while true; do
            sleep 2
            status_line=$(build_status_line)
            printf '%s,\n' "$status_line"
        done
    ) &
    STATUS_PID=$!

    # Main process: Listen for click events on stdin (blocking)
    while read -r click_event; do
        # Debug: Log click events to file
        echo "[$(date '+%H:%M:%S')] Received: $click_event" >> /tmp/i3bar-click-debug.log

        # Strip leading comma if present (i3bar sends events as JSON array elements)
        click_event="${click_event#,}"

        # Handle click event if it looks like JSON
        if [[ "$click_event" =~ ^\{ ]]; then
            echo "[$(date '+%H:%M:%S')] Handling JSON click event" >> /tmp/i3bar-click-debug.log
            handle_click_event "$click_event" &
        fi
    done

    # Cleanup on exit
    kill $STATUS_PID 2>/dev/null || true
}

# Trap to ensure cleanup
trap 'kill $STATUS_PID 2>/dev/null' EXIT

# Run main
main
