#!/usr/bin/env bash
# Emit a test result trace span to OTEL collector
#
# Usage:
#   emit_test_span.sh <test-name> <status> [duration_ms]
#
# Arguments:
#   test-name    Name of the test (e.g., "nginx-startup")
#   status       Test result: "passed" or "failed"
#   duration_ms  Optional duration in milliseconds (default: 1000)
#
# Environment:
#   OTEL_EXPORTER_OTLP_ENDPOINT  OTLP endpoint (default: http://localhost:4318)
#   OTEL_SERVICE_NAME            Service name (default: nixos-integration-tests)
#
# Examples:
#   emit_test_span.sh "nginx-test" "passed" 1500
#   emit_test_span.sh "database-migration" "failed" 5000
#   OTEL_EXPORTER_OTLP_ENDPOINT=http://10.0.2.2:4318 emit_test_span.sh "test" "passed"

set -euo pipefail

# Arguments
TEST_NAME="${1:-unknown}"
STATUS="${2:-passed}"
DURATION_MS="${3:-1000}"

# Configuration from environment
ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}"
SERVICE_NAME="${OTEL_SERVICE_NAME:-nixos-integration-tests}"

# Generate trace and span IDs
TRACE_ID=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | xxd -p)
SPAN_ID=$(openssl rand -hex 8 2>/dev/null || head -c 16 /dev/urandom | xxd -p)

# Current time in nanoseconds
NOW_NS=$(date +%s%N)

# Map status to OTEL status code (1=OK, 2=ERROR)
if [ "$STATUS" = "passed" ]; then
    STATUS_CODE=1
else
    STATUS_CODE=2
fi

# Send trace via OTLP HTTP
curl -sS -X POST "${ENDPOINT}/v1/traces" \
    -H "Content-Type: application/json" \
    -d @- << EOF
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        {"key": "service.name", "value": {"stringValue": "${SERVICE_NAME}"}},
        {"key": "service.version", "value": {"stringValue": "1.0.0"}}
      ]
    },
    "scopeSpans": [{
      "scope": {
        "name": "nixos-test-driver"
      },
      "spans": [{
        "traceId": "${TRACE_ID}",
        "spanId": "${SPAN_ID}",
        "name": "test.${TEST_NAME}",
        "kind": 1,
        "startTimeUnixNano": "${NOW_NS}",
        "endTimeUnixNano": "${NOW_NS}",
        "status": {"code": ${STATUS_CODE}},
        "attributes": [
          {"key": "test.name", "value": {"stringValue": "${TEST_NAME}"}},
          {"key": "test.status", "value": {"stringValue": "${STATUS}"}},
          {"key": "test.duration_ms", "value": {"intValue": ${DURATION_MS}}},
          {"key": "test.framework", "value": {"stringValue": "nixos-test-driver"}}
        ]
      }]
    }]
  }]
}
EOF

echo "Emitted trace for test: ${TEST_NAME} (status=${STATUS}, duration=${DURATION_MS}ms)"
