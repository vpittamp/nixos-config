#!/usr/bin/env bash
# Outputs JSON summary of current Sway outputs (headless + physical)
# Example:
# {"active":["HEADLESS-1"],"enabled":["HEADLESS-1"],"all":["HEADLESS-1","HEADLESS-2","HEADLESS-3"],"active_count":1}

set -euo pipefail

outputs_json="$(swaymsg -t get_outputs 2>/dev/null || echo '[]')"

active=$(echo "$outputs_json" | jq -r '.[] | select(.active==true) | .name' | paste -sd, -)
enabled=$(echo "$outputs_json" | jq -r '.[] | select(.dpms==true) | .name' | paste -sd, -)
all=$(echo "$outputs_json" | jq -r '.[].name' | paste -sd, -)

active_list=()
IFS=',' read -ra active_arr <<< "${active}"
for o in "${active_arr[@]}"; do [[ -n "$o" ]] && active_list+=("\"$o\""); done

enabled_list=()
IFS=',' read -ra enabled_arr <<< "${enabled}"
for o in "${enabled_arr[@]}"; do [[ -n "$o" ]] && enabled_list+=("\"$o\""); done

all_list=()
IFS=',' read -ra all_arr <<< "${all}"
for o in "${all_arr[@]}"; do [[ -n "$o" ]] && all_list+=("\"$o\""); done

printf '{'
printf '"active":[%s],' "$(IFS=,; echo "${active_list[*]}")"
printf '"enabled":[%s],' "$(IFS=,; echo "${enabled_list[*]}")"
printf '"all":[%s],' "$(IFS=,; echo "${all_list[*]}")"
printf '"active_count":%d' "${#active_list[@]}"
printf '}\n'
