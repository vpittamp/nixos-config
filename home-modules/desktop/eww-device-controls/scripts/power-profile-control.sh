#!/usr/bin/env bash
# Power profile control wrapper for Eww onclick handlers
# Feature 116: Unified device controls
#
# Usage: power-profile-control.sh ACTION [PROFILE]
#
# Actions:
#   get           Get current profile (JSON)
#   set PROFILE   Set profile (performance|balanced|power-saver)
#   cycle         Cycle to next profile
#
# Exit codes:
#   0 - Success
#   1 - Error
#   2 - Profiles unavailable

set -euo pipefail

ACTION="${1:-get}"
PROFILE="${2:-}"

PLATFORM_PROFILE="/sys/firmware/acpi/platform_profile"
PLATFORM_CHOICES="/sys/firmware/acpi/platform_profile_choices"

error_json() {
    echo "{\"error\": true, \"message\": \"$1\", \"code\": \"$2\"}"
    exit "${3:-1}"
}

get_profile_icon() {
    local profile="$1"
    case "$profile" in
        performance) echo "󱐋" ;;
        balanced) echo "󰾅" ;;
        power-saver|low-power) echo "󰾆" ;;
        *) echo "󰾅" ;;
    esac
}

# Map platform_profile names to standard names
normalize_profile() {
    case "$1" in
        low-power) echo "power-saver" ;;
        *) echo "$1" ;;
    esac
}

# Map standard names to platform_profile names
to_platform_profile() {
    case "$1" in
        power-saver) echo "low-power" ;;
        *) echo "$1" ;;
    esac
}

# Determine which tool is available
TOOL=""
if [[ -f "$PLATFORM_PROFILE" ]]; then
    TOOL="platform_profile"
elif command -v powerprofilesctl &>/dev/null; then
    TOOL="powerprofilesctl"
else
    error_json "No power profile tool found" "PROFILES_UNAVAILABLE" 2
fi

# Check AC status
get_ac_status() {
    for ac in /sys/class/power_supply/AC* /sys/class/power_supply/ACAD*; do
        if [[ -f "$ac/online" ]] && [[ "$(cat "$ac/online")" == "1" ]]; then
            echo "true"
            return
        fi
    done
    echo "false"
}

case "$ACTION" in
    get)
        if [[ "$TOOL" == "platform_profile" ]]; then
            # Read current profile
            raw_current=$(cat "$PLATFORM_PROFILE" 2>/dev/null) || error_json "Failed to read platform profile" "PROFILE_ERROR"
            current=$(normalize_profile "$raw_current")

            # Read available profiles
            if [[ -f "$PLATFORM_CHOICES" ]]; then
                raw_choices=$(cat "$PLATFORM_CHOICES" 2>/dev/null)
                profiles=""
                for p in $raw_choices; do
                    normalized=$(normalize_profile "$p")
                    if [[ -n "$profiles" ]]; then
                        profiles+=","
                    fi
                    profiles+="\"$normalized\""
                done
                available="[$profiles]"
            else
                available="[\"power-saver\", \"balanced\", \"performance\"]"
            fi

            on_ac=$(get_ac_status)
            icon=$(get_profile_icon "$current")
            echo "{\"current\": \"$current\", \"on_ac\": $on_ac, \"available\": $available, \"icon\": \"$icon\"}"

        elif [[ "$TOOL" == "powerprofilesctl" ]]; then
            current=$(powerprofilesctl get 2>/dev/null) || error_json "Failed to get power profile" "PROFILE_ERROR"

            available="[]"
            profiles_output=$(powerprofilesctl list 2>/dev/null) || true
            if [[ -n "$profiles_output" ]]; then
                profiles=""
                while IFS= read -r line; do
                    profile=$(echo "$line" | sed 's/^[* ]*//' | sed 's/:$//' | xargs)
                    if [[ -n "$profile" ]] && [[ "$profile" != "Profile"* ]]; then
                        if [[ -n "$profiles" ]]; then
                            profiles+=","
                        fi
                        profiles+="\"$profile\""
                    fi
                done < <(echo "$profiles_output" | grep -E "^[* ]*(performance|balanced|power-saver)")
                available="[$profiles]"
            fi

            on_ac=$(get_ac_status)
            icon=$(get_profile_icon "$current")
            echo "{\"current\": \"$current\", \"on_ac\": $on_ac, \"available\": $available, \"icon\": \"$icon\"}"
        fi
        ;;

    set)
        if [[ -z "$PROFILE" ]]; then
            error_json "Profile not specified" "INVALID_VALUE"
        fi

        # Validate profile
        case "$PROFILE" in
            performance|balanced|power-saver)
                ;;
            *)
                error_json "Invalid profile: $PROFILE (use performance|balanced|power-saver)" "INVALID_VALUE"
                ;;
        esac

        if [[ "$TOOL" == "platform_profile" ]]; then
            platform_value=$(to_platform_profile "$PROFILE")
            # Use pkexec for graphical password prompt, or sudo if in terminal
            if [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
                echo "$platform_value" | pkexec tee "$PLATFORM_PROFILE" >/dev/null 2>&1 || \
                    error_json "Failed to set profile (authentication required)" "PROFILE_ERROR"
            else
                echo "$platform_value" | sudo tee "$PLATFORM_PROFILE" >/dev/null 2>&1 || \
                    error_json "Failed to set profile (requires sudo)" "PROFILE_ERROR"
            fi

        elif [[ "$TOOL" == "powerprofilesctl" ]]; then
            powerprofilesctl set "$PROFILE" 2>/dev/null || error_json "Failed to set power profile" "PROFILE_ERROR"
        fi
        ;;

    cycle)
        # Get current profile and cycle to next
        if [[ "$TOOL" == "platform_profile" ]]; then
            raw_current=$(cat "$PLATFORM_PROFILE" 2>/dev/null) || error_json "Failed to read current profile" "PROFILE_ERROR"
            current=$(normalize_profile "$raw_current")
        elif [[ "$TOOL" == "powerprofilesctl" ]]; then
            current=$(powerprofilesctl get 2>/dev/null) || error_json "Failed to get current profile" "PROFILE_ERROR"
        fi

        case "$current" in
            power-saver)
                next="balanced"
                ;;
            balanced)
                next="performance"
                ;;
            performance)
                next="power-saver"
                ;;
            *)
                next="balanced"
                ;;
        esac

        # Recursively call set
        exec "$0" set "$next"
        ;;

    *)
        error_json "Unknown action: $ACTION" "INVALID_ACTION"
        ;;
esac
