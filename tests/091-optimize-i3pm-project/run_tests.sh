#!/usr/bin/env bash
# Test runner for Feature 091: Optimize i3pm Project Switching Performance
# Run unit and integration tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Feature 091 Test Suite ===${NC}"
echo "Project root: $PROJECT_ROOT"
echo "Test directory: $SCRIPT_DIR"
echo ""

# Check if pytest is available
if ! command -v pytest &> /dev/null; then
    echo -e "${RED}✗ pytest not found${NC}"
    echo "Install with: pip install pytest pytest-asyncio"
    exit 1
fi

# Check if we're in the right directory
if [[ ! -f "$PROJECT_ROOT/flake.nix" ]]; then
    echo -e "${RED}✗ Not in NixOS config directory${NC}"
    exit 1
fi

# Add project root to PYTHONPATH
export PYTHONPATH="$PROJECT_ROOT:${PYTHONPATH:-}"
echo -e "${BLUE}PYTHONPATH set to: $PYTHONPATH${NC}"
echo ""

# Run unit tests
echo -e "${BLUE}Running unit tests...${NC}"
if pytest "$SCRIPT_DIR/unit/" -v --tb=short; then
    echo -e "${GREEN}✓ Unit tests passed${NC}"
    unit_status=0
else
    echo -e "${RED}✗ Unit tests failed${NC}"
    unit_status=1
fi
echo ""

# Run integration tests
echo -e "${BLUE}Running integration tests...${NC}"
if pytest "$SCRIPT_DIR/integration/" -v --tb=short; then
    echo -e "${GREEN}✓ Integration tests passed${NC}"
    integration_status=0
else
    echo -e "${RED}✗ Integration tests failed${NC}"
    integration_status=1
fi
echo ""

# Summary
echo -e "${BLUE}=== Test Summary ===${NC}"
if [[ $unit_status -eq 0 ]]; then
    echo -e "${GREEN}✓ Unit tests: PASS${NC}"
else
    echo -e "${RED}✗ Unit tests: FAIL${NC}"
fi

if [[ $integration_status -eq 0 ]]; then
    echo -e "${GREEN}✓ Integration tests: PASS${NC}"
else
    echo -e "${RED}✗ Integration tests: FAIL${NC}"
fi
echo ""

# Exit with failure if any tests failed
if [[ $unit_status -ne 0 ]] || [[ $integration_status -ne 0 ]]; then
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
else
    echo -e "${GREEN}✓ All tests passed${NC}"
    exit 0
fi
