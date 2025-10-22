#!/run/current-system/sw/bin/bash
# Clipcat timestamp tracker
# Monitors clipboard and logs timestamps for new entries

TIMESTAMP_LOG="$HOME/.cache/clipcat/timestamps.log"

# Ensure log file exists
mkdir -p "$(dirname "$TIMESTAMP_LOG")"
touch "$TIMESTAMP_LOG"

# Watch for clipboard changes and log timestamps
# This runs continuously as a background service
while true; do
  # Get current top clipboard ID
  current_id=$(clipcatctl list | head -1 | cut -d':' -f1)
  
  # Check if this is a new entry (not already logged)
  if ! grep -q "^$current_id " "$TIMESTAMP_LOG" 2>/dev/null; then
    # Log: ID TIMESTAMP
    echo "$current_id $(date '+%Y-%m-%d %H:%M:%S')" >> "$TIMESTAMP_LOG"
  fi
  
  # Check every 2 seconds
  sleep 2
done
