#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 0 ]]; then
    echo "launch-code no longer accepts a directory override." >&2
    echo "Use the managed launcher instead: app-launcher-wrapper.sh code" >&2
    exit 2
fi

exec "${HOME}/.local/bin/app-launcher-wrapper.sh" code
