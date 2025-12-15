#!/usr/bin/env bash
# Feature 117: Spinner frame for AI working animation (top bar)
# Outputs circle character - opacity creates the pulse effect

IDX_FILE="/tmp/eww-topbar-spinner-idx"
IDX=$(cat "$IDX_FILE" 2>/dev/null || echo 0)

# 8-frame animation: large circle with opacity pulse
case $IDX in
  0)  echo "⬤" ;;
  1)  echo "⬤" ;;
  2)  echo "⬤" ;;
  3)  echo "⬤" ;;
  4)  echo "⬤" ;;
  5)  echo "⬤" ;;
  6)  echo "⬤" ;;
  7)  echo "⬤" ;;
  *)  echo "⬤" ;;
esac

# Increment index (wrap at 8)
NEXT=$(( (IDX + 1) % 8 ))
echo "$NEXT" > "$IDX_FILE"
