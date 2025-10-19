#!/usr/bin/env bash
# View the output of the last background command
# Usage: view-last-bg-command.sh [file]

if [ -n "$1" ]; then
    # View specific file provided as argument
    LOG_FILE="$1"
else
    # Find the most recent bg-command output file
    LOG_FILE=$(ls -t /tmp/bg-command.* 2>/dev/null | head -1)
fi

if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
    echo "No background command output found"
    exit 1
fi

# View the file with less
less "$LOG_FILE"
