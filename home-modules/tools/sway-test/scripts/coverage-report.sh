#!/usr/bin/env bash
#
# Coverage Report Script (User Story 4)
#
# Automates coverage collection and HTML generation for sway-test framework.
#
# Usage:
#   ./scripts/coverage-report.sh [--html] [--threshold PERCENT]
#
# Options:
#   --html          Generate HTML coverage report
#   --threshold N   Fail if coverage < N percent (default: 85)
#
# Examples:
#   ./scripts/coverage-report.sh                # Text report, 85% threshold
#   ./scripts/coverage-report.sh --html         # HTML report
#   ./scripts/coverage-report.sh --threshold 90 # Require 90% coverage
#

set -euo pipefail

# Default configuration
GENERATE_HTML=false
THRESHOLD=85
COVERAGE_DIR="coverage"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --html)
      GENERATE_HTML=true
      shift
      ;;
    --threshold)
      THRESHOLD="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,23p' "$0" | sed 's/^# //'
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run with --help for usage information"
      exit 1
      ;;
  esac
done

echo "📊 Sway Test Framework - Coverage Report"
echo "========================================="
echo ""

# Step 1: Clean previous coverage data
echo "🧹 Cleaning previous coverage data..."
rm -rf "$COVERAGE_DIR"
echo "   ✓ Removed $COVERAGE_DIR/"
echo ""

# Step 2: Run tests with coverage
echo "🧪 Running tests with coverage collection..."
echo "   Command: deno task test:coverage"
echo ""
if ! deno task test:coverage; then
  echo "❌ Tests failed. Cannot generate coverage report."
  exit 1
fi
echo ""

# Step 3: Generate text coverage report
echo "📈 Generating coverage report..."
echo "   Excluding: tests/, main.ts"
echo ""
COVERAGE_OUTPUT=$(deno task coverage)
echo "$COVERAGE_OUTPUT"
echo ""

# Step 4: Extract coverage percentage
# Format: "cover /path/to/file.ts ... 87.50%"
OVERALL_COVERAGE=$(echo "$COVERAGE_OUTPUT" | grep -oP 'All files\s+\|\s+\K[\d.]+' || echo "0")

if [[ -z "$OVERALL_COVERAGE" || "$OVERALL_COVERAGE" == "0" ]]; then
  echo "⚠️  Warning: Could not extract coverage percentage from output"
  OVERALL_COVERAGE="unknown"
else
  echo "📊 Overall Coverage: $OVERALL_COVERAGE%"
fi

# Step 5: Check threshold
if [[ "$OVERALL_COVERAGE" != "unknown" ]]; then
  # Use bc for floating point comparison
  if command -v bc &> /dev/null; then
    MEETS_THRESHOLD=$(echo "$OVERALL_COVERAGE >= $THRESHOLD" | bc -l)
    if [[ "$MEETS_THRESHOLD" -eq 1 ]]; then
      echo "✅ Coverage meets threshold ($OVERALL_COVERAGE% >= $THRESHOLD%)"
    else
      echo "❌ Coverage below threshold ($OVERALL_COVERAGE% < $THRESHOLD%)"
      exit 1
    fi
  else
    # Fallback to integer comparison if bc is not available
    OVERALL_INT=${OVERALL_COVERAGE%.*}
    if [[ "$OVERALL_INT" -ge "$THRESHOLD" ]]; then
      echo "✅ Coverage meets threshold ($OVERALL_INT% >= $THRESHOLD%)"
    else
      echo "❌ Coverage below threshold ($OVERALL_INT% < $THRESHOLD%)"
      exit 1
    fi
  fi
fi
echo ""

# Step 6: Generate HTML report (optional)
if [[ "$GENERATE_HTML" == true ]]; then
  echo "🌐 Generating HTML coverage report..."
  deno task coverage:html
  HTML_PATH="$COVERAGE_DIR/html/index.html"

  if [[ -f "$HTML_PATH" ]]; then
    echo "   ✓ HTML report generated: $HTML_PATH"
    echo ""
    echo "📖 To view HTML report:"
    echo "   Open file://$(pwd)/$HTML_PATH in your browser"
  else
    echo "   ⚠️  HTML report not found at $HTML_PATH"
  fi
  echo ""
fi

echo "✅ Coverage report complete!"
echo ""
echo "📚 Next Steps:"
echo "   - Review uncovered lines to identify missing tests"
echo "   - Aim for >85% coverage on sync-manager.ts and sync-marker.ts"
echo "   - Use HTML report for detailed line-by-line coverage"
