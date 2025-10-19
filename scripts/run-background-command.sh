#!/usr/bin/env bash
# Run a command in background with notification on completion
# Usage: run-background-command.sh <command>

COMMAND="$1"

if [ -z "$COMMAND" ]; then
    echo "Usage: run-background-command.sh <command>"
    exit 1
fi

# Create temporary files for output
TMPDIR="${TMPDIR:-/tmp}"
OUTPUT_FILE=$(mktemp "$TMPDIR/bg-command.XXXXXX")
LOG_FILE="$HOME/.cache/bg-commands.log"

# Ensure cache directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Get timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Show initial notification
notify-send -a "bg-command" -u low "Running..." "$COMMAND"

# Run command in background, capture output and exit code
(
    echo "[$TIMESTAMP] Running: $COMMAND" >> "$LOG_FILE"

    # Run the command and capture both stdout and stderr
    if eval "$COMMAND" &> "$OUTPUT_FILE"; then
        EXIT_CODE=0
    else
        EXIT_CODE=$?
    fi

    # Get output (limited to last 500 lines for sanity)
    OUTPUT=$(tail -500 "$OUTPUT_FILE")

    # Count lines
    LINE_COUNT=$(wc -l < "$OUTPUT_FILE")

    # Log completion
    echo "[$TIMESTAMP] Completed with exit code: $EXIT_CODE" >> "$LOG_FILE"
    echo "[$TIMESTAMP] Output file: $OUTPUT_FILE" >> "$LOG_FILE"

    # Send notification based on exit code
    if [ $EXIT_CODE -eq 0 ]; then
        # Success
        notify-send \
            -a "bg-command" \
            -u normal \
            "✓ Command Completed" \
            "$COMMAND\n\nClick to view output ($LINE_COUNT lines)\nLog: $OUTPUT_FILE"
    else
        # Failure - show last few lines of error
        ERROR_PREVIEW=$(tail -5 "$OUTPUT_FILE" | sed 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')
        notify-send \
            -a "bg-command" \
            -u critical \
            "✗ Command Failed (exit $EXIT_CODE)" \
            "$COMMAND\n\n$ERROR_PREVIEW\n\nLog: $OUTPUT_FILE"
    fi

    # Keep the output file for review (user can clean up manually)
    # Or auto-cleanup after 24 hours:
    # sleep 86400 && rm -f "$OUTPUT_FILE" &

) &

# Detach from terminal
disown

echo "Command started in background. Output will be saved to: $OUTPUT_FILE"
