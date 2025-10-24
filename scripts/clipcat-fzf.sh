#!/usr/bin/env bash
# FZF-based clipboard history selector for clipcat
# Provides terminal-based clipboard history with immediate paste, previews, and trimming

# Don't exit on error - we want to handle cancellation gracefully
set -uo pipefail

TIMESTAMP_LOG="${TIMESTAMP_LOG:-$HOME/.cache/clipcat/timestamps.log}"
MAX_ITEMS=${CLIPCAT_FZF_MAX_ITEMS:-500}

human_age() {
  local delta="$1"

  if (( delta < 0 )); then
    delta=0
  fi

  if (( delta < 60 )); then
    printf '%ds ago' "$delta"
  elif (( delta < 3600 )); then
    printf '%dm ago' $((delta / 60))
  elif (( delta < 86400 )); then
    printf '%dh ago' $((delta / 3600))
  elif (( delta < 604800 )); then
    printf '%dd ago' $((delta / 86400))
  elif (( delta < 2629746 )); then
    printf '%dw ago' $((delta / 604800))
  else
    printf '%dmo ago' $((delta / 2629746))
  fi
}

relative_timestamp() {
  local raw="$1"

  if [[ -z "$raw" || "$raw" == "--:--:--" ]]; then
    printf 'unknown'
    return
  fi

  if ! epoch=$(date -d "$raw" +%s 2>/dev/null); then
    printf '%s' "$raw"
    return
  fi

  local now
  now=$(date +%s)
  local rel
  rel=$(human_age $((now - epoch)))
  printf '%s (%s)' "$(date -d "@$epoch" '+%a %b %d %Y %H:%M:%S')" "$rel"
}

generate_entries() {
  local tslog="$1"

  if [[ ! -f "$tslog" ]]; then
    tslog=""
  fi

  clipcatctl list | awk -F': ' -v tslog="$tslog" '
    function format_age(delta) {
      if (delta < 0) delta = 0;
      if (delta < 60) {
        return sprintf("%ds ago", delta);
      } else if (delta < 3600) {
        return sprintf("%dm ago", int(delta / 60));
      } else if (delta < 86400) {
        return sprintf("%dh ago", int(delta / 3600));
      } else if (delta < 604800) {
        return sprintf("%dd ago", int(delta / 86400));
      } else if (delta < 2629746) {
        return sprintf("%dw ago", int(delta / 604800));
      }
      return sprintf("%dmo ago", int(delta / 2629746));
    }

    function load_timestamp(line, parts, clip_id) {
      split(line, parts, " ");
      clip_id = parts[1];
      if (length(parts) >= 3) {
        timestamps[clip_id] = parts[2] " " parts[3];
        split(timestamps[clip_id], v, "[- :]");
        if (length(v) >= 6) {
          epoch[clip_id] = mktime(v[1] " " v[2] " " v[3] " " v[4] " " v[5] " " v[6]);
          if (epoch[clip_id] > now) {
            epoch[clip_id] = now;
          }
          if (min_epoch == 0 || epoch[clip_id] < min_epoch) {
            min_epoch = epoch[clip_id];
          }
        }
      }
    }

    BEGIN {
      now = systime();
      min_epoch = 0;
      if (tslog != "") {
        while ((getline line < tslog) > 0) {
          load_timestamp(line);
        }
        close(tslog);
      }
      if (min_epoch == 0) {
        min_epoch = now;
      }
      missing_order = 0;
    }

    {
      id = $1;
      $1 = "";
      text = substr($0, 2);

      gsub(/\t/, " ", text);
      gsub(/\r/, "", text);
      gsub(/\\n.*/, " ⋯", text);

      if (text == "") {
        display = "<empty clip>";
      } else if (length(text) > 120) {
        display = substr(text, 1, 120) "...";
      } else {
        display = text;
      }

      if (id in epoch) {
        order = epoch[id];
        display_ts = strftime("%b %d %H:%M", epoch[id]) " • " format_age(now - epoch[id]);
      } else {
        missing_order++;
        order = min_epoch - missing_order;
        display_ts = "unknown";
      }

      printf "%013d\t%s\t%s\t%s\n", order, id, display_ts, display;
    }
  '
}

render_list() {
  local tslog="$1"

  generate_entries "$tslog" | sort -t$'\t' -k1,1nr | awk -F'\t' '{printf "%s\t[%s] %s\n", $2, $3, $4}'
}

render_preview() {
  local clip_id="$1"
  local tslog="$2"

  if [[ -z "$clip_id" ]]; then
    printf 'No clip selected\n'
    return
  fi

  if ! content=$(clipcatctl get "$clip_id" 2>/dev/null); then
    printf 'Unable to load clip %s\n' "$clip_id"
    return
  fi

  local timestamp=""
  if [[ -n "$tslog" && -f "$tslog" ]]; then
    timestamp=$(awk -v id="$clip_id" '$1 == id {print $2 " " $3}' "$tslog" | tail -n1)
  fi

  local bytes lines
  bytes=$(printf '%s' "$content" | wc -c | awk '{print $1}')
  lines=$(printf '%s' "$content" | awk 'END {print NR}')
  if [[ -z "$lines" ]]; then
    lines=0
  fi

  printf '\033[1mID:\033[0m %s\n' "$clip_id"
  printf '\033[1mTimestamp:\033[0m %s\n' "$(relative_timestamp "$timestamp")"
  printf '\033[1mSize:\033[0m %s bytes, %s lines\n\n' "$bytes" "$lines"

  if command -v bat >/dev/null 2>&1; then
    printf '%s' "$content" | bat --paging=never --style=plain --color=always --wrap=never --file-name "clip-$clip_id.txt" -
  else
    printf '%s\n' "$content"
  fi
}

prune_timestamp_log() {
  local tslog="$1"
  shift

  if [[ ! -f "$tslog" || $# -eq 0 ]]; then
    return
  fi

  local joined
  joined=$(printf '%s|' "$@")
  joined=${joined%|}

  local tmp
  tmp=$(mktemp)
  awk -v ids="$joined" '
    BEGIN {
      n = split(ids, arr, "|");
      for (i = 1; i <= n; ++i) {
        if (arr[i] != "") {
          remove[arr[i]] = 1;
        }
      }
    }
    {
      if (!($1 in remove)) {
        print $0;
      }
    }
  ' "$tslog" > "$tmp" && mv "$tmp" "$tslog"
}

enforce_limit() {
  local limit="$1"
  local tslog="$2"

  if [[ -z "$limit" || "$limit" -le 0 ]]; then
    return
  fi

  local total
  if ! total=$(clipcatctl length 2>/dev/null); then
    total=$(clipcatctl list | wc -l)
  fi

  if [[ -z "$total" || "$total" -le "$limit" ]]; then
    return
  fi

  local remove_count=$(( total - limit ))
  mapfile -t remove_ids < <(generate_entries "$tslog" | sort -t$'\t' -k1,1n | head -n "$remove_count" | cut -f2)

  if (( ${#remove_ids[@]} > 0 )); then
    clipcatctl remove "${remove_ids[@]}" >/dev/null 2>&1 || true
    prune_timestamp_log "$tslog" "${remove_ids[@]}"
  fi
}

case "${1:-}" in
  list)
    log_path="${2:-$TIMESTAMP_LOG}"
    enforce_limit "$MAX_ITEMS" "$log_path"
    render_list "$log_path"
    exit 0
    ;;
  preview)
    render_preview "${2:-}" "${3:-$TIMESTAMP_LOG}"
    exit 0
    ;;
esac

if command -v realpath >/dev/null 2>&1; then
  SCRIPT_PATH=$(realpath "$0")
elif command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH=$(readlink -f "$0")
else
  SCRIPT_PATH="$0"
fi

enforce_limit "$MAX_ITEMS" "$TIMESTAMP_LOG"

printf -v LIST_CMD '%q list %q' "$SCRIPT_PATH" "$TIMESTAMP_LOG"
printf -v PREVIEW_CMD '%q preview %s %q' "$SCRIPT_PATH" '{1}' "$TIMESTAMP_LOG"

HEADER_MESSAGE=$'Enter->paste | Ctrl-Y copy only | Ctrl-D delete | Ctrl-/ preview layout | Ctrl-P toggle preview'

selected=$(render_list "$TIMESTAMP_LOG" | fzf \
  --tmux=center,90%,80% \
  --ansi \
  --no-sort \
  --layout=reverse \
  --border=rounded \
  --border-label=' Clipcat ' \
  --info=inline \
  --delimiter='\t' \
  --with-nth=2 \
  --header="$HEADER_MESSAGE" \
  --prompt='History > ' \
  --preview="$PREVIEW_CMD" \
  --preview-label=' Clipboard entry ' \
  --preview-window=right,60%,border-top \
  --bind "ctrl-d:execute-silent(clipcatctl remove {1})+reload($LIST_CMD)" \
  --bind "ctrl-r:reload($LIST_CMD)" \
  --bind 'ctrl-p:toggle-preview' \
  --bind 'ctrl-y:execute-silent(clipcatctl promote {1})' \
  --bind 'shift-up:preview-up,shift-down:preview-down' \
  --bind 'alt-up:preview-up,alt-down:preview-down' \
  --bind 'ctrl-/:change-preview-window(right,60%,border-top|right,60%,border-top,wrap|hidden)' \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8) || exit 0

# If user selected something, promote to clipboard and paste it
if [ -n "${selected:-}" ]; then
  clip_id=${selected%%$'\t'*}

  # Promote to top of clipboard history (makes it the current clipboard item)
  clipcatctl promote "$clip_id"

  # Get the actual text content
  text=$(clipcatctl get "$clip_id")

  # Determine if we're in tmux and paste appropriately
  if [ -n "${TMUX:-}" ]; then
    tmux send-keys -l "$text" >/dev/null 2>&1
  else
    if command -v xdotool &>/dev/null; then
      sleep 0.1
      xdotool type --clearmodifiers -- "$text"
    fi
  fi
fi >/dev/null 2>&1
