#!/usr/bin/env bash
# Generate a PWA icon with an environment badge overlay
# Usage: generate-env-icon.sh <source-svg> <environment> <output-png>
#
# Produces a 512x512 PNG with a colored corner badge (bottom-right circle with letter)
#
# Badge colors:
#   dev     - Green  #10b981  (D)
#   staging - Amber  #f59e0b  (S)
#   prod    - Blue   #3b82f6  (P)
#   ryzen   - Purple #a855f7  (R)
#   hub     - Cyan   #06b6d4  (H)

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <source-svg> <environment> <output-png>" >&2
  exit 1
fi

SOURCE_SVG="$1"
ENV="$2"
OUTPUT_PNG="$3"

# Validate environment
case "$ENV" in
  dev)     BADGE_COLOR="#10b981"; LETTER="D" ;;
  staging) BADGE_COLOR="#f59e0b"; LETTER="S" ;;
  prod)    BADGE_COLOR="#3b82f6"; LETTER="P" ;;
  ryzen)   BADGE_COLOR="#a855f7"; LETTER="R" ;;
  hub)     BADGE_COLOR="#06b6d4"; LETTER="H" ;;
  *)
    echo "Error: Invalid environment '$ENV'. Must be one of: dev, staging, prod, ryzen, hub" >&2
    exit 1
    ;;
esac

if [[ ! -f "$SOURCE_SVG" ]]; then
  echo "Error: Source SVG not found: $SOURCE_SVG" >&2
  exit 1
fi

SIZE=512
# Badge: 40% diameter circle in bottom-right corner with 10px margin
BADGE_DIAMETER=$((SIZE * 40 / 100))  # 204
BADGE_RADIUS=$((BADGE_DIAMETER / 2))  # 102
BADGE_CX=$((SIZE - BADGE_RADIUS - 10))  # 400
BADGE_CY=$((SIZE - BADGE_RADIUS - 10))  # 400
BORDER_WIDTH=6

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Step 1: Convert SVG to 512x512 PNG (centered, preserving aspect ratio)
rsvg-convert -w "$SIZE" -h "$SIZE" --keep-aspect-ratio "$SOURCE_SVG" -o "$TMPDIR/base.png"

# Ensure exactly 512x512 with transparent background (rsvg may output smaller)
magick "$TMPDIR/base.png" -background none -gravity center -extent "${SIZE}x${SIZE}" "$TMPDIR/base_sized.png"

# Step 2: Create badge overlay as SVG for crisp rendering
cat > "$TMPDIR/badge.svg" <<SVGEOF
<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">
  <!-- White border circle -->
  <circle cx="${BADGE_CX}" cy="${BADGE_CY}" r="${BADGE_RADIUS}" fill="white"/>
  <!-- Colored inner circle -->
  <circle cx="${BADGE_CX}" cy="${BADGE_CY}" r="$((BADGE_RADIUS - BORDER_WIDTH))" fill="${BADGE_COLOR}"/>
  <!-- Letter -->
  <text x="${BADGE_CX}" y="${BADGE_CY}" text-anchor="middle" dominant-baseline="central"
        font-family="sans-serif" font-weight="bold" font-size="$((BADGE_DIAMETER * 55 / 100))"
        fill="white">${LETTER}</text>
</svg>
SVGEOF

# Step 3: Convert badge SVG to PNG
rsvg-convert -w "$SIZE" -h "$SIZE" "$TMPDIR/badge.svg" -o "$TMPDIR/badge.png"

# Step 4: Composite badge on top of base icon
magick "$TMPDIR/base_sized.png" "$TMPDIR/badge.png" -composite "$OUTPUT_PNG"

echo "Generated: $OUTPUT_PNG"
