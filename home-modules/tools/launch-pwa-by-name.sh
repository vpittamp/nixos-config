#!/usr/bin/env bash
# launch-pwa-by-name: Cross-machine PWA launcher (Feature 056, Phase 4, T052)
# Dynamically resolves PWA name to ULID at runtime for portability
set -euo pipefail

PWA_NAME="$1"
FFPWA="${FFPWA:-firefoxpwa}"

# Query firefoxpwa for installed PWAs
if ! command -v "$FFPWA" >/dev/null 2>&1; then
  echo "Error: firefoxpwa not found" >&2
  exit 1
fi

# Get PWA ID by name (dynamic resolution)
PWA_ID=$("$FFPWA" profile list 2>/dev/null | grep "^- $PWA_NAME:" | awk -F'[()]' '{print $2}' | head -1)

if [ -z "$PWA_ID" ]; then
  echo "Error: PWA '$PWA_NAME' not found" >&2
  echo "Available PWAs:" >&2
  "$FFPWA" profile list 2>/dev/null | grep "^- " | sed 's/^- /  /' >&2
  exit 1
fi

# Launch PWA by resolved ID
exec "$FFPWA" site launch "$PWA_ID" "$@"
