#!/usr/bin/env bash
#
# Generate Code Coverage Report for i3 Project Daemon
#
# Runs pytest with coverage plugin and generates HTML and terminal reports.
# Target: 90%+ coverage (SC-021, FR-019)
#
# Feature 039 - Task T108
#
# Usage:
#   ./scripts/generate-coverage-report.sh
#   ./scripts/generate-coverage-report.sh --html-only  # Skip terminal output
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$REPO_ROOT/tests/i3-project-daemon"
DAEMON_DIR="$REPO_ROOT/home-modules/desktop/i3-project-event-daemon"
DIAGNOSTIC_CLI_DIR="$REPO_ROOT/home-modules/tools/i3pm-diagnostic"
COVERAGE_DIR="$REPO_ROOT/.coverage-report"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "i3 Project Daemon - Code Coverage Report"
echo "=========================================="
echo ""

# Check if pytest is installed
if ! command -v pytest &> /dev/null; then
    echo -e "${RED}Error: pytest not installed${NC}"
    echo ""
    echo "Install pytest with:"
    echo "  sudo nixos-rebuild switch --flake .#<target>"
    echo ""
    echo "Or install manually:"
    echo "  pip install pytest pytest-asyncio pytest-cov"
    exit 1
fi

# Check if pytest-cov is available
if ! python3 -c "import pytest_cov" 2>/dev/null; then
    echo -e "${RED}Error: pytest-cov not installed${NC}"
    echo ""
    echo "Install with:"
    echo "  pip install pytest-cov"
    exit 1
fi

# Create coverage directory
mkdir -p "$COVERAGE_DIR"

echo "Test directory: $TEST_DIR"
echo "Daemon code:    $DAEMON_DIR"
echo "CLI code:       $DIAGNOSTIC_CLI_DIR"
echo "Coverage dir:   $COVERAGE_DIR"
echo ""

# Run pytest with coverage
echo "Running tests with coverage..."
echo ""

cd "$REPO_ROOT"

# Coverage sources
COVERAGE_SOURCES="--cov=$DAEMON_DIR --cov=$DIAGNOSTIC_CLI_DIR"

# Coverage options
COVERAGE_OPTS="--cov-report=term-missing --cov-report=html:$COVERAGE_DIR/html --cov-report=json:$COVERAGE_DIR/coverage.json"

# Run pytest
if [ "$1" == "--html-only" ]; then
    # Skip terminal output, only generate HTML
    COVERAGE_OPTS="--cov-report=html:$COVERAGE_DIR/html --cov-report=json:$COVERAGE_DIR/coverage.json"
fi

python3 -m pytest \
    "$TEST_DIR" \
    $COVERAGE_SOURCES \
    $COVERAGE_OPTS \
    --verbose \
    --tb=short \
    || true  # Continue even if some tests fail

echo ""
echo "=========================================="
echo "Coverage Report Generated"
echo "=========================================="
echo ""

# Parse JSON coverage report for overall percentage
if [ -f "$COVERAGE_DIR/coverage.json" ]; then
    COVERAGE_PCT=$(python3 -c "
import json
with open('$COVERAGE_DIR/coverage.json') as f:
    data = json.load(f)
    print(f\"{data['totals']['percent_covered']:.1f}\")
" 2>/dev/null || echo "0.0")

    TARGET=90.0

    echo "Overall Coverage: ${COVERAGE_PCT}%"
    echo "Target:           ${TARGET}%"
    echo ""

    # Compare with target
    IS_PASSING=$(python3 -c "print('yes' if float('$COVERAGE_PCT') >= $TARGET else 'no')")

    if [ "$IS_PASSING" == "yes" ]; then
        echo -e "${GREEN}✅ Coverage target met!${NC}"
        echo ""
        echo "HTML Report: file://$COVERAGE_DIR/html/index.html"
        exit 0
    else:
        DEFICIT=$(python3 -c "print(f'{$TARGET - float(\"$COVERAGE_PCT\"):.1f}')")
        echo -e "${YELLOW}⚠️  Coverage below target by ${DEFICIT}%${NC}"
        echo ""
        echo "Missing coverage details:"
        echo "  HTML Report: file://$COVERAGE_DIR/html/index.html"
        echo ""
        echo "To improve coverage:"
        echo "  1. Review HTML report for uncovered lines"
        echo "  2. Add tests for uncovered code paths"
        echo "  3. Focus on critical paths (event processing, workspace assignment)"
        echo ""
        exit 1
    fi
else
    echo -e "${RED}Error: Coverage report not generated${NC}"
    exit 1
fi
