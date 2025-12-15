#!/usr/bin/env bash
# Feature 117: Spinner opacity for fade effect (top bar)
# Returns opacity value matching the frame index

IDX=$(cat /tmp/eww-topbar-spinner-idx 2>/dev/null || echo 0)

# Opacity values matching frame index - creates breathing effect
case $IDX in
  0)  echo "0.4" ;;
  1)  echo "0.6" ;;
  2)  echo "0.8" ;;
  3)  echo "1.0" ;;
  4)  echo "1.0" ;;
  5)  echo "0.8" ;;
  6)  echo "0.6" ;;
  7)  echo "0.4" ;;
  *)  echo "1.0" ;;
esac
