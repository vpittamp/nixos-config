#!/usr/bin/env bash
# Validation script to validate project configs against JSON schemas
# Part of Feature 014 - i3 Project Management System Consolidation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== JSON Schema Validation ==="
echo

# Check if jq is available
if ! command -v jq > /dev/null; then
    echo -e "${RED}ERROR${NC}: jq command not found (required for JSON parsing)"
    exit 1
fi

ERRORS=0
WARNINGS=0

PROJECTS_DIR="$HOME/.config/i3/projects"
CONTRACTS_DIR="/etc/nixos/specs/014-create-a-new/contracts"

# Check if projects directory exists
if [ ! -d "$PROJECTS_DIR" ]; then
    echo -e "${YELLOW}INFO${NC}: No projects directory at $PROJECTS_DIR"
    echo "   This is normal if no projects have been created yet"
    exit 0
fi

# Check if contracts directory exists
if [ ! -d "$CONTRACTS_DIR" ]; then
    echo -e "${YELLOW}WARNING${NC}: Contracts directory not found at $CONTRACTS_DIR"
    echo "   Skipping schema validation"
    exit 0
fi

echo "1. Validating project configuration files..."
PROJECT_COUNT=0
for config_file in "$PROJECTS_DIR"/*.json; do
    [ -e "$config_file" ] || continue
    ((PROJECT_COUNT++))

    filename=$(basename "$config_file")
    echo
    echo "Checking: $filename"

    # Validate JSON syntax
    if ! jq empty "$config_file" 2>/dev/null; then
        echo -e "  ${RED}✗${NC} Invalid JSON syntax"
        ((ERRORS++))
        continue
    fi

    # Check required fields
    REQUIRED_FIELDS=("version" "project")
    for field in "${REQUIRED_FIELDS[@]}"; do
        if ! jq -e ".$field" "$config_file" > /dev/null 2>&1; then
            echo -e "  ${RED}✗${NC} Missing required field: $field"
            ((ERRORS++))
        fi
    done

    # Check project subfields
    PROJECT_FIELDS=("name" "displayName" "icon" "directory")
    for field in "${PROJECT_FIELDS[@]}"; do
        if ! jq -e ".project.$field" "$config_file" > /dev/null 2>&1; then
            echo -e "  ${RED}✗${NC} Missing required field: project.$field"
            ((ERRORS++))
        fi
    done

    # Validate project name matches filename
    project_name=$(jq -r '.project.name' "$config_file" 2>/dev/null || echo "")
    expected_name="${filename%.json}"
    if [ "$project_name" != "$expected_name" ]; then
        echo -e "  ${RED}✗${NC} Project name mismatch: name='$project_name' but filename='$filename'"
        ((ERRORS++))
    else
        echo -e "  ${GREEN}✓${NC} Project name matches filename"
    fi

    # Check directory is absolute path
    directory=$(jq -r '.project.directory' "$config_file" 2>/dev/null || echo "")
    if [[ ! "$directory" =~ ^/ ]]; then
        echo -e "  ${RED}✗${NC} Directory is not an absolute path: $directory"
        ((ERRORS++))
    else
        echo -e "  ${GREEN}✓${NC} Directory is absolute path"

        # Warn if directory doesn't exist
        if [ ! -d "$directory" ]; then
            echo -e "  ${YELLOW}⚠${NC}  Warning: Directory does not exist: $directory"
            ((WARNINGS++))
        fi
    fi

    # Validate version is semver
    version=$(jq -r '.version' "$config_file" 2>/dev/null || echo "")
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+ ]]; then
        echo -e "  ${YELLOW}⚠${NC}  Warning: Version doesn't look like semver: $version"
        ((WARNINGS++))
    fi
done

if [ $PROJECT_COUNT -eq 0 ]; then
    echo -e "${YELLOW}INFO${NC}: No project configuration files found"
fi

echo
echo "2. Validating active-project file..."
ACTIVE_PROJECT="$HOME/.config/i3/active-project"

if [ ! -f "$ACTIVE_PROJECT" ]; then
    echo -e "${YELLOW}INFO${NC}: No active-project file (normal when no project is active)"
else
    # Validate JSON syntax
    if ! jq empty "$ACTIVE_PROJECT" 2>/dev/null; then
        echo -e "${RED}✗${NC} Invalid JSON syntax in active-project file"
        ((ERRORS++))
    else
        # Check if it's empty object (no project)
        if [ "$(jq '. | length' "$ACTIVE_PROJECT")" -eq 0 ]; then
            echo -e "${GREEN}✓${NC} Active project file is empty (no active project)"
        else
            # Check required fields
            REQUIRED=("name" "display_name" "icon")
            for field in "${REQUIRED[@]}"; do
                if ! jq -e ".$field" "$ACTIVE_PROJECT" > /dev/null 2>&1; then
                    echo -e "${RED}✗${NC} Missing field in active-project: $field"
                    ((ERRORS++))
                fi
            done

            # Verify project exists
            project_name=$(jq -r '.name' "$ACTIVE_PROJECT" 2>/dev/null || echo "")
            if [ -n "$project_name" ] && [ ! -f "$PROJECTS_DIR/$project_name.json" ]; then
                echo -e "${RED}✗${NC} Active project '$project_name' config file not found"
                ((ERRORS++))
            else
                echo -e "${GREEN}✓${NC} Active project file valid"
            fi
        fi
    fi
fi

echo
echo "3. Validating app-classes configuration..."
APP_CLASSES="$HOME/.config/i3/app-classes.json"

if [ ! -f "$APP_CLASSES" ]; then
    echo -e "${YELLOW}WARNING${NC}: No app-classes.json file found"
    ((WARNINGS++))
else
    # Validate JSON syntax
    if ! jq empty "$APP_CLASSES" 2>/dev/null; then
        echo -e "${RED}✗${NC} Invalid JSON syntax in app-classes.json"
        ((ERRORS++))
    else
        # Check structure
        if ! jq -e '.classes | type == "array"' "$APP_CLASSES" > /dev/null 2>&1; then
            echo -e "${RED}✗${NC} app-classes.json missing 'classes' array"
            ((ERRORS++))
        else
            CLASS_COUNT=$(jq '.classes | length' "$APP_CLASSES")
            echo -e "${GREEN}✓${NC} app-classes.json valid ($CLASS_COUNT application classes defined)"
        fi
    fi
fi

echo
echo "=== Validation Summary ==="
echo "Projects validated: $PROJECT_COUNT"
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
echo

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: All JSON schemas valid"
    exit 0
else
    echo -e "${RED}✗ FAIL${NC}: $ERRORS error(s) found"
    exit 1
fi
