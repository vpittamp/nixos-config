#!/usr/bin/env bash
# System Monitoring Status Bar (Top Bar)
# Provides real-time system metrics: CPU, memory, disk, network, temperature
# Updates every 2 seconds

# Path substitutions (will be replaced by Nix)
DATE_BIN="@date@"
GREP_BIN="@grep@"
AWK_BIN="@awk@"
SED_BIN="@sed@"

# Catppuccin Mocha colors
COLOR_LAVENDER="#b4befe"
COLOR_BLUE="#89b4fa"
COLOR_SAPPHIRE="#74c7ec"
COLOR_SKY="#89dceb"
COLOR_TEAL="#94e2d5"
COLOR_GREEN="#a6e3a1"
COLOR_YELLOW="#f9e2af"
COLOR_PEACH="#fab387"
COLOR_MAROON="#eba0ac"
COLOR_RED="#f38ba8"
COLOR_MAUVE="#cba6f7"
COLOR_PINK="#f5c2e7"
COLOR_FLAMINGO="#f2cdcd"
COLOR_ROSEWATER="#f5e0dc"
COLOR_TEXT="#cdd6f4"
COLOR_SUBTEXT1="#bac2de"
COLOR_SUBTEXT0="#a6adc8"
COLOR_OVERLAY2="#9399b2"
COLOR_SURFACE2="#585b70"
COLOR_BASE="#1e1e2e"

escape_json_string() {
    local str="$1"
    local out=""
    local char
    local i
    for (( i = 0; i < ${#str}; i++ )); do
        char=${str:i:1}
        case "$char" in
            '"') out+='\\"' ;;
            '\\') out+='\\\\' ;;
            $'\n') out+='\\n' ;;
            $'\r') out+='\\r' ;;
            $'\t') out+='\\t' ;;
            *) out+="$char" ;;
        esac
    done
    printf '%s' "$out"
}

get_generation_block() {
    if ! command -v nixos-generation-info >/dev/null 2>&1; then
        return
    fi

    local export_data
    if ! export_data=$(nixos-generation-info --export 2>/dev/null); then
        return
    fi

    local short status warning hm_short color text
    eval "$export_data"

    short=${NIXOS_GENERATION_INFO_SHORT:-}
    hm_short=${NIXOS_GENERATION_INFO_HOME_MANAGER_SHORT:-}
    status=${NIXOS_GENERATION_INFO_STATUS:-unknown}
    warning=${NIXOS_GENERATION_INFO_WARNING_PARTS:-}

    if [ -z "$short" ]; then
        short="generation unknown"
    fi

    if [ -n "$hm_short" ] && [[ "$short" != *"$hm_short"* ]]; then
        short="$short $hm_short"
    fi

    color="$COLOR_MAUVE"
    if [ "$status" = "out-of-sync" ]; then
        color="$COLOR_RED"
        if [ -n "$warning" ]; then
            short="$short ⚠ $warning"
        else
            short="$short ⚠"
        fi
    fi

    text="  $short"
    text=$(escape_json_string "$text")

    cat <<EOF
{
  "full_text": "$text",
  "color": "$color",
  "name": "nixos_generation",
  "separator": false,
  "separator_block_width": 15
}
EOF
}

# CPU usage calculation
get_cpu_usage() {
    # Read /proc/stat for CPU usage
    local cpu_line
    cpu_line=$("$GREP_BIN" '^cpu ' /proc/stat)

    # Parse idle and total times
    local idle total
    idle=$(echo "$cpu_line" | "$AWK_BIN" '{print $5}')
    total=$(echo "$cpu_line" | "$AWK_BIN" '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')

    # Calculate percentage (simple approach - doesn't track delta)
    # For more accurate tracking, we'd need to store previous values
    echo "cpu_idle=$idle cpu_total=$total"
}

# Memory usage
get_memory_usage() {
    local mem_info
    mem_info=$(cat /proc/meminfo)

    local total available
    total=$(echo "$mem_info" | "$GREP_BIN" '^MemTotal:' | "$AWK_BIN" '{print $2}')
    available=$(echo "$mem_info" | "$GREP_BIN" '^MemAvailable:' | "$AWK_BIN" '{print $2}')

    # Convert to GB
    local used_gb total_gb usage_percent
    total_gb=$("$AWK_BIN" "BEGIN {printf \"%.1f\", $total/1024/1024}")
    used_gb=$("$AWK_BIN" "BEGIN {printf \"%.1f\", ($total-$available)/1024/1024}")
    usage_percent=$("$AWK_BIN" "BEGIN {printf \"%.0f\", (($total-$available)/$total)*100}")

    echo "${used_gb}/${total_gb}GB (${usage_percent}%)"
}

# Disk usage
get_disk_usage() {
    local disk_info
    disk_info=$(df -h / 2>/dev/null | tail -1)

    local used total percent
    used=$(echo "$disk_info" | "$AWK_BIN" '{print $3}')
    total=$(echo "$disk_info" | "$AWK_BIN" '{print $2}')
    percent=$(echo "$disk_info" | "$AWK_BIN" '{print $5}' | "$SED_BIN" 's/%//')

    echo "${used}/${total} (${percent}%)"
}

# Network traffic (simplified - shows current rx/tx bytes)
get_network_traffic() {
    # Find primary network interface (not lo)
    local iface
    iface=$(ip route | "$GREP_BIN" '^default' | "$AWK_BIN" '{print $5}' | head -1)

    if [ -z "$iface" ]; then
        echo "No network"
        return
    fi

    # Read rx/tx bytes
    local rx_bytes tx_bytes
    rx_bytes=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
    tx_bytes=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)

    # Convert to human-readable (MB/GB)
    local rx_mb tx_mb
    rx_mb=$("$AWK_BIN" "BEGIN {printf \"%.1f\", $rx_bytes/1024/1024}")
    tx_mb=$("$AWK_BIN" "BEGIN {printf \"%.1f\", $tx_bytes/1024/1024}")

    echo "↓${rx_mb}MB ↑${tx_mb}MB"
}

# CPU temperature (if available)
get_cpu_temp() {
    # Try various thermal zone files
    local temp_file
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        if [ -f "$zone" ]; then
            local temp
            temp=$(cat "$zone")
            # Convert millidegrees to degrees
            temp=$("$AWK_BIN" "BEGIN {printf \"%.0f\", $temp/1000}")
            echo "${temp}°C"
            return
        fi
    done

    echo ""
}

# System load average
get_load_average() {
    local load
    load=$(cat /proc/loadavg | "$AWK_BIN" '{print $1}')
    echo "$load"
}

# Battery status (M1 MacBook Pro)
get_battery_status() {
    local battery_path="/sys/class/power_supply/macsmc-battery"

    if [ ! -d "$battery_path" ]; then
        return  # No battery available
    fi

    local capacity status
    capacity=$(cat "$battery_path/capacity" 2>/dev/null || echo "?")
    status=$(cat "$battery_path/status" 2>/dev/null || echo "Unknown")

    # Choose icon based on charge level and status
    local icon color
    if [ "$status" = "Charging" ]; then
        icon=""  # Charging icon
        color="$COLOR_GREEN"
    elif [ "$capacity" -ge 80 ]; then
        icon=""  # Full battery
        color="$COLOR_GREEN"
    elif [ "$capacity" -ge 60 ]; then
        icon=""  # 3/4 battery
        color="$COLOR_BLUE"
    elif [ "$capacity" -ge 40 ]; then
        icon=""  # 1/2 battery
        color="$COLOR_YELLOW"
    elif [ "$capacity" -ge 20 ]; then
        icon=""  # 1/4 battery
        color="$COLOR_PEACH"
    else
        icon=""  # Low battery
        color="$COLOR_RED"
    fi

    echo "${icon} ${capacity}%|${color}"
}

# WiFi status
get_wifi_status() {
    if ! command -v nmcli >/dev/null 2>&1; then
        return  # nmcli not available
    fi

    local wifi_info
    wifi_info=$(nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -1)

    if [ -z "$wifi_info" ]; then
        echo " Disconnected|$COLOR_RED"
        return
    fi

    local ssid signal color
    ssid=$(echo "$wifi_info" | cut -d: -f2)
    signal=$(echo "$wifi_info" | cut -d: -f3)

    # Truncate SSID if too long
    if [ ${#ssid} -gt 12 ]; then
        ssid="${ssid:0:12}…"
    fi

    # Color based on signal strength
    if [ "$signal" -ge 70 ]; then
        color="$COLOR_GREEN"
    elif [ "$signal" -ge 50 ]; then
        color="$COLOR_YELLOW"
    else
        color="$COLOR_PEACH"
    fi

    echo " ${ssid} ${signal}%|${color}"
}

# Volume status
get_volume_status() {
    if ! command -v pactl >/dev/null 2>&1; then
        return  # pactl not available
    fi

    local volume muted
    volume=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '\d+%' | head -1 || echo "?")
    muted=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -oP '(yes|no)' || echo "no")

    local icon color
    if [ "$muted" = "yes" ]; then
        icon=""  # Muted
        color="$COLOR_RED"
        volume="MUTE"
    else
        icon=""  # Volume icon
        color="$COLOR_BLUE"
    fi

    echo "${icon} ${volume}|${color}"
}

# Bluetooth status
get_bluetooth_status() {
    if ! command -v bluetoothctl >/dev/null 2>&1; then
        return  # bluetoothctl not available
    fi

    local powered
    powered=$(bluetoothctl show 2>/dev/null | grep -oP 'Powered: \K(yes|no)')

    if [ "$powered" != "yes" ]; then
        return  # Bluetooth off, don't show
    fi

    # Check if any devices are connected
    local connected
    connected=$(bluetoothctl devices Connected 2>/dev/null | wc -l)

    local icon color
    if [ "$connected" -gt 0 ]; then
        icon=" ${connected}"  # Connected devices count
        color="$COLOR_BLUE"
    else
        icon=""  # On but not connected
        color="$COLOR_SUBTEXT0"
    fi

    echo "${icon}|${color}"
}

# Get current Sway binding mode
get_mode_indicator() {
    local mode
    mode=$(swaymsg -t get_binding_state 2>/dev/null | jq -r '.name' 2>/dev/null)

    # Only show indicator if not in default mode
    if [ -z "$mode" ] || [ "$mode" = "default" ]; then
        return
    fi

    # Convert mode to uppercase for visibility
    local mode_upper
    mode_upper=$(echo "$mode" | tr '[:lower:]' '[:upper:]')

    # Special handling for workspace modes - show typed digits only
    local display_text=" ⚡ ${mode_upper} ⚡ "
    if [ "$mode" = "goto_workspace" ] || [ "$mode" = "move_workspace" ] || [ "$mode" = "→ WS" ] || [ "$mode" = "⇒ WS" ]; then
        local typed_digits=""
        if [ -f "/tmp/sway-workspace-mode-state" ]; then
            typed_digits=$(cat /tmp/sway-workspace-mode-state 2>/dev/null || echo "")
            if [ -n "$typed_digits" ] && [ "$typed_digits" != "0" ]; then
                # Show: ⚡ 42_
                display_text=" ⚡ ${typed_digits}_ "
            else
                # Show: ⚡ _
                display_text=" ⚡ _ "
            fi
        fi
    fi

    # Return JSON block with bright red background for visibility
    cat <<EOF
{
  "full_text": "$display_text",
  "color": "#1e1e2e",
  "background": "$COLOR_RED",
  "border": "$COLOR_RED",
  "border_top": 2,
  "border_bottom": 2,
  "border_left": 2,
  "border_right": 2,
  "name": "sway_mode",
  "separator": false,
  "separator_block_width": 20,
  "markup": "pango"
}
EOF
}

# Build status line
build_status_line() {
    local cpu_usage mem_usage disk_usage net_traffic cpu_temp load_avg current_time
    local battery_status wifi_status volume_status bluetooth_status
    local blocks=()
    local block

    # Gather metrics
    mem_usage=$(get_memory_usage)
    disk_usage=$(get_disk_usage)
    net_traffic=$(get_network_traffic)
    cpu_temp=$(get_cpu_temp)
    load_avg=$(get_load_average)
    current_time=$("$DATE_BIN" '+%a %b %d  %H:%M')  # Shortened time format (removed seconds)
    battery_status=$(get_battery_status)
    wifi_status=$(get_wifi_status)
    volume_status=$(get_volume_status)
    bluetooth_status=$(get_bluetooth_status)

    # Mode indicator (first block - leftmost position, only shown when not in default mode)
    if block=$(get_mode_indicator); then
        if [ -n "$block" ]; then
            blocks+=("$block")
        fi
    fi

    if block=$(get_generation_block); then
        if [ -n "$block" ]; then
            blocks+=("$block")
        fi
    fi

    # Battery (if available)
    if [ -n "$battery_status" ]; then
        local text color
        text="${battery_status%|*}"
        color="${battery_status#*|}"
        block=$(cat <<EOF
{
  "full_text": "${text}",
  "color": "${color}",
  "name": "battery",
  "separator": false,
  "separator_block_width": 12
}
EOF
)
        blocks+=("$block")
    fi

    # WiFi (if available)
    if [ -n "$wifi_status" ]; then
        local text color
        text="${wifi_status%|*}"
        color="${wifi_status#*|}"
        block=$(cat <<EOF
{
  "full_text": "${text}",
  "color": "${color}",
  "name": "wifi",
  "separator": false,
  "separator_block_width": 12
}
EOF
)
        blocks+=("$block")
    fi

    # Volume (if available)
    if [ -n "$volume_status" ]; then
        local text color
        text="${volume_status%|*}"
        color="${volume_status#*|}"
        block=$(cat <<EOF
{
  "full_text": "${text}",
  "color": "${color}",
  "name": "volume",
  "separator": false,
  "separator_block_width": 12
}
EOF
)
        blocks+=("$block")
    fi

    # Bluetooth (if available and powered on)
    if [ -n "$bluetooth_status" ]; then
        local text color
        text="${bluetooth_status%|*}"
        color="${bluetooth_status#*|}"
        block=$(cat <<EOF
{
  "full_text": "${text}",
  "color": "${color}",
  "name": "bluetooth",
  "separator": false,
  "separator_block_width": 12
}
EOF
)
        blocks+=("$block")
    fi

    block=$(cat <<EOF
{
  "full_text": " ${load_avg}",
  "color": "$COLOR_BLUE",
  "name": "load",
  "separator": false,
  "separator_block_width": 12
}
EOF
)
    blocks+=("$block")

    block=$(cat <<EOF
{
  "full_text": " ${mem_usage}",
  "color": "$COLOR_SAPPHIRE",
  "name": "memory",
  "separator": false,
  "separator_block_width": 12
}
EOF
)
    blocks+=("$block")

    block=$(cat <<EOF
{
  "full_text": " ${current_time}",
  "color": "$COLOR_TEXT",
  "name": "datetime",
  "separator": false,
  "separator_block_width": 10
}
EOF
)
    blocks+=("$block")

    printf '[\n'
    local idx=0
    local total=${#blocks[@]}
    for block in "${blocks[@]}"; do
        if [ $idx -ne 0 ]; then
            printf ',\n'
        fi
        printf '%s' "$block"
        idx=$((idx + 1))
    done
    printf '\n]\n'
}

# Main loop
main() {
    # i3bar protocol header
    echo '{"version":1,"click_events":false}'
    echo '['

    # Initial status
    build_status_line

    # Update every 2 seconds
    while true; do
        sleep 2
        echo ","
        build_status_line
    done
}

main
