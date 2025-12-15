#!/usr/bin/env bash
# Feature 117: AI Sessions status script for top bar
# Reads badge files from XDG_RUNTIME_DIR/i3pm-badges and outputs JSON
# Three states: working (active), stopped (needs attention), idle (muted)
#
# Optimized architecture: Project is stored in badge file at write time
# (via tmux session's I3PM_PROJECT_NAME env var), eliminating expensive sway tree queries

BADGE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"

# Output empty array if badge directory doesn't exist
if [[ ! -d "$BADGE_DIR" ]]; then
    echo '{"sessions":[],"has_working":false}'
    exit 0
fi

# Collect all badge files
sessions="[]"
has_working=false

for badge_file in "$BADGE_DIR"/*.json; do
    [[ -f "$badge_file" ]] || continue

    # Read badge content
    badge_content=$(cat "$badge_file" 2>/dev/null) || continue
    [[ -z "$badge_content" ]] && continue

    # Extract fields using jq - project is now stored in badge
    window_id=$(basename "$badge_file" .json)
    state=$(echo "$badge_content" | jq -r '.state // "stopped"')
    source=$(echo "$badge_content" | jq -r '.source // "unknown"')
    count=$(echo "$badge_content" | jq -r '.count // 0')
    project=$(echo "$badge_content" | jq -r '.project // ""')

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
