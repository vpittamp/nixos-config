#!/usr/bin/env bash
# launch-pwa-by-name: Cross-machine PWA launcher (Feature 056, Phase 4, T052)
# Dynamically resolves PWA name to ULID at runtime for portability
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: launch-pwa-by-name <name-or-ulid> [extra firefoxpwa args]" >&2
  exit 1
fi

TARGET="$1"
shift
FFPWA="${FFPWA:-firefoxpwa}"

# Query firefoxpwa for installed PWAs
if ! command -v "$FFPWA" >/dev/null 2>&1; then
  echo "Error: firefoxpwa not found" >&2
  exit 1
fi

# Determine if target is already a ULID (26 chars, Crockford alphabet)
if echo "$TARGET" | grep -qE '^[0-9A-HJKMNP-TV-Z]{26}$'; then
  PWA_ID="$TARGET"
else
  # Get PWA ID by human-readable name (dynamic resolution)
  PWA_ID=$("$FFPWA" profile list 2>/dev/null | grep -F "^- $TARGET:" | awk -F'[()]' '{print $2}' | head -1)
fi

if [ -z "$PWA_ID" ]; then
  echo "Error: PWA '$TARGET' not found" >&2
  echo "Available PWAs:" >&2
  "$FFPWA" profile list 2>/dev/null | grep "^- " | sed 's/^- /  /' >&2
  exit 1
fi

# Launch PWA by resolved ID
exec "$FFPWA" site launch "$PWA_ID" "$@"
