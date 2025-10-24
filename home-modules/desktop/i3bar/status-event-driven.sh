#!/usr/bin/env bash
# i3bar Event-Driven Status Script
# Subscribes to i3pm daemon events for instant status updates
# Follows i3bar protocol: https://i3wm.org/docs/i3bar-protocol.html

set -euo pipefail

# Configuration paths (will be substituted by Nix)
I3PM_BIN="@i3pm@"
JQ_BIN="@jq@"
SED_BIN="@sed@"
DATE_BIN="@date@"
GREP_BIN="@grep@"
AWK_BIN="@awk@"

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

    # Get current project (strip ANSI codes)
    current=$("$I3PM_BIN" project current 2>/dev/null | "$SED_BIN" 's/\x1b\[[0-9;]*m//g' || echo "")

    if [ -z "$current" ]; then
        # No active project - global mode
        "$JQ_BIN" -n --arg text "∅ Global" \
            '{
                full_text: $text,
                color: "'"$COLOR_SUBTEXT"'",
                name: "project",
                instance: "global"
            }'
    else
        # Get project info from daemon
        project_info=$("$I3PM_BIN" project list --json 2>/dev/null | \
            "$JQ_BIN" -r ".[] | select(.name == \"$current\") | \"\(.icon // \"📁\") \(.display_name // .name)\"" || echo "📁 $current")

        "$JQ_BIN" -n --arg text "$project_info" --arg instance "$current" \
            '{
                full_text: $text,
                color: "'"$COLOR_LAVENDER"'",
                name: "project",
                instance: $instance
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

# Build complete status line
build_status_line() {
    local project cpu memory network date

    project=$(build_project_block)
    cpu=$(build_cpu_block)
    memory=$(build_memory_block)
    network=$(build_network_block)
    date=$(build_date_block)

    # Combine all blocks into status line array
    "$JQ_BIN" -n \
        --argjson project "$project" \
        --argjson cpu "$cpu" \
        --argjson memory "$memory" \
        --argjson network "$network" \
        --argjson date "$date" \
        '[$project, $cpu, $memory, $network, $date]'
}

# Main: Output i3bar protocol
main() {
    # Output header
    echo '{"version":1,"click_events":true}'
    echo '['

    # Output initial empty status line
    echo '[],'

    # Subscribe to daemon events and rebuild status on each event
    "$I3PM_BIN" daemon events --follow --type=project,window 2>/dev/null | while read -r event; do
        # Build and output new status line
        status_line=$(build_status_line)
        echo "$status_line,"
    done
}

# Run main
main
