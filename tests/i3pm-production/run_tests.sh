#!/usr/bin/env bash
# Test runner for i3pm production readiness tests
# Feature 030: Uses Python environment with test dependencies

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== i3pm Production Readiness Test Suite ==="
echo ""

# Check if we're in the right directory
if [ ! -d "tests/i3pm-production" ]; then
    echo -e "${RED}Error: Must run from repository root (/etc/nixos)${NC}"
    exit 1
fi

# Create Python virtual environment with test dependencies if needed
VENV_DIR="tests/i3pm-production/.venv"
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Creating test virtual environment...${NC}"
    python3 -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"

    echo -e "${YELLOW}Installing test dependencies...${NC}"
    pip install --quiet \
        pytest \
        pytest-asyncio \
        pytest-cov \
        pydantic \
        i3ipc \
        || {
            echo -e "${RED}Failed to install dependencies${NC}"
            exit 1
        }
    echo -e "${GREEN}✓ Test environment created${NC}"
else
    source "$VENV_DIR/bin/activate"
    echo -e "${GREEN}✓ Using existing test environment${NC}"
fi

# Show Python environment info
echo ""
echo "Python: $(python3 --version)"
echo "pytest: $(pytest --version 2>&1 | head -1)"
echo "Environment: $VENV_DIR"
echo ""

# Parse command line arguments
TEST_PATH="${1:-tests/i3pm-production}"
COVERAGE="${COVERAGE:-0}"

# Run tests
echo -e "${YELLOW}Running tests from: $TEST_PATH${NC}"
echo ""

if [ "$COVERAGE" = "1" ]; then
    pytest "$TEST_PATH" \
        -v \
        --cov=home-modules/desktop/i3-project-event-daemon \
        --cov-report=term-missing \
        --cov-report=html:htmlcov \
        "$@"

    echo ""
    echo -e "${GREEN}Coverage report generated: htmlcov/index.html${NC}"
else
    pytest "$TEST_PATH" -v "$@"
fi

# Test result
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All tests passed${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
