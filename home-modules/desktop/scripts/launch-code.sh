#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 0 ]]; then
    echo "launch-code no longer accepts a directory override." >&2
    echo "Use the daemon-owned launcher instead: i3pm launch open code" >&2
    exit 2
fi

exec i3pm launch open code
