#!/usr/bin/env bash
# Validation script to verify window marks follow i3 project:NAME format
# Part of Feature 014 - i3 Project Management System Consolidation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== i3 JSON Schema Validation ==="
echo

# Check if i3 is running
if ! pgrep -x i3 > /dev/null; then
    echo -e "${YELLOW}WARNING${NC}: i3 is not running, skipping runtime validation"
    exit 0
fi

# Check if i3-msg is available
if ! command -v i3-msg > /dev/null; then
    echo -e "${RED}ERROR${NC}: i3-msg command not found"
    exit 1
fi

# Check if jq is available
if ! command -v jq > /dev/null; then
    echo -e "${RED}ERROR${NC}: jq command not found (required for JSON parsing)"
    exit 1
fi

ERRORS=0
WARNINGS=0

echo "1. Validating window marks format..."
# Get all marks from i3 tree
MARKS=$(i3-msg -t get_tree | jq -r '.. | .marks? | .[]?' | grep -E '^project:' || true)

if [ -z "$MARKS" ]; then
    echo -e "${YELLOW}INFO${NC}: No project marks found in i3 tree"
else
    echo "Found project marks:"
    while IFS= read -r mark; do
        # Validate mark format: project:NAME or project:NAME:SUFFIX
        if [[ ! "$mark" =~ ^project:[a-zA-Z0-9_-]+(:[a-zA-Z0-9_-]+)?$ ]]; then
            echo -e "  ${RED}✗${NC} Invalid format: $mark"
            ((ERRORS++))
        else
            echo -e "  ${GREEN}✓${NC} Valid: $mark"
        fi
    done <<< "$MARKS"
fi

echo
echo "2. Validating i3 tree structure..."
# Verify we can query i3 tree without errors
if ! i3-msg -t get_tree > /dev/null 2>&1; then
    echo -e "${RED}ERROR${NC}: Failed to query i3 tree via IPC"
    ((ERRORS++))
else
    echo -e "${GREEN}✓${NC} i3 tree query successful"
fi

echo
echo "3. Validating workspace state..."
# Verify we can query workspaces
if ! i3-msg -t get_workspaces > /dev/null 2>&1; then
    echo -e "${RED}ERROR${NC}: Failed to query i3 workspaces via IPC"
    ((ERRORS++))
else
    WORKSPACE_COUNT=$(i3-msg -t get_workspaces | jq '. | length')
    echo -e "${GREEN}✓${NC} Workspace query successful ($WORKSPACE_COUNT workspaces)"
fi

echo
echo "4. Checking for redundant state files..."
# Check if window-project-map.json exists (should NOT exist per FR-019)
if [ -f "$HOME/.config/i3/window-project-map.json" ]; then
    echo -e "${RED}✗${NC} Found redundant state file: ~/.config/i3/window-project-map.json"
    echo "   This violates FR-019: System MUST NOT implement custom window tracking beyond i3 marks"
    ((ERRORS++))
else
    echo -e "${GREEN}✓${NC} No redundant window-project-map.json file"
fi

echo
echo "=== Validation Summary ==="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: All validations passed"
    exit 0
else
    echo -e "${RED}✗ FAIL${NC}: $ERRORS error(s) found"
    exit 1
fi
