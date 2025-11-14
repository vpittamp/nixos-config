#!/usr/bin/env bash
# Live monitor for workspace preview events
# Run this in one terminal while testing project switches

echo "Monitoring workspace-preview-daemon events..."
echo "Press Ctrl+C to stop"
echo ""
echo "Events to watch for:"
echo "  - project_mode events (char, execute, cancel)"
echo "  - Eww window close commands"
echo "  - NavigationHandler actions"
echo ""
echo "=================================="
echo ""

journalctl --user -u workspace-preview-daemon -f --no-pager 2>/dev/null | \
    grep --line-buffered -E "project_mode|Closed Eww|close workspace-preview|NavigationHandler|Execute event"
