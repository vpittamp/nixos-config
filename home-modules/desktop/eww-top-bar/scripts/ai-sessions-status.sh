#!/usr/bin/env bash
# Feature 117: AI Sessions status script for top bar
# Reads badge files from XDG_RUNTIME_DIR/i3pm-badges and outputs JSON
# Three states: working (active), stopped (needs attention), idle (muted)

BADGE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"

# Output empty array if badge directory doesn't exist
if [[ ! -d "$BADGE_DIR" ]]; then
    echo '{"sessions":[],"has_working":false}'
    exit 0
fi

# Get sway tree once for all window lookups
SWAY_TREE=$(swaymsg -t get_tree 2>/dev/null)

# Function to extract project from window marks
get_window_project() {
    local win_id="$1"
    # Find window marks and extract project from scoped mark format:
    # scoped:app_type:owner/repo:branch:window_id -> owner/repo:branch
    local marks=$(echo "$SWAY_TREE" | jq -r ".. | objects | select(.id == $win_id) | .marks[]?" 2>/dev/null)
    for mark in $marks; do
        if [[ "$mark" == scoped:* ]]; then
            # Extract project: scoped:type:owner/repo:branch:id -> owner/repo:branch
            # Format: scoped:terminal:vpittamp/nixos-config:117-branch:7
            local parts
            IFS=':' read -ra parts <<< "$mark"
            if [[ ${#parts[@]} -ge 4 ]]; then
                # parts[2] = owner/repo, parts[3] = branch
                echo "${parts[2]}:${parts[3]}"
                return
            fi
        fi
    done
    echo "global"
}

# Collect all badge files
sessions="[]"
has_working=false

for badge_file in "$BADGE_DIR"/*.json; do
    [[ -f "$badge_file" ]] || continue

    # Read badge content
    badge_content=$(cat "$badge_file" 2>/dev/null) || continue
    [[ -z "$badge_content" ]] && continue

    # Extract fields using jq
    window_id=$(basename "$badge_file" .json)
    state=$(echo "$badge_content" | jq -r '.state // "stopped"')
    source=$(echo "$badge_content" | jq -r '.source // "unknown"')
    count=$(echo "$badge_content" | jq -r '.count // 0')

    # Get project from window marks (not badge file)
    project=$(get_window_project "$window_id")

    # Track if any session is working
    if [[ "$state" == "working" ]]; then
        has_working=true
    fi

    # Determine needs_attention (stopped with count > 0 = needs focus)
    needs_attention=false
    if [[ "$state" == "stopped" ]] && [[ "$count" -gt 0 ]]; then
        needs_attention=true
    fi

    # Add to sessions array
    session=$(jq -n \
        --arg id "$window_id" \
        --arg state "$state" \
        --arg source "$source" \
        --argjson count "${count:-0}" \
        --arg project "$project" \
        --argjson needs_attention "$needs_attention" \
        '{id: $id, state: $state, source: $source, count: $count, project: $project, needs_attention: $needs_attention}')

    sessions=$(echo "$sessions" | jq --argjson session "$session" '. + [$session]')
done

# Output final JSON
jq -n \
    --argjson sessions "$sessions" \
    --argjson has_working "$has_working" \
    '{sessions: $sessions, has_working: $has_working}'
