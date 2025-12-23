# OpenTelemetry Traced NixOS Integration Test Template
#
# Test with full observability: traces emitted to Grafana.
# Includes OTEL pipeline verification and test result spans.
#
# Usage:
#   nix-build -A default
#   $(nix-build -A default.driverInteractive)/bin/nixos-test-driver
#
# Replace TODO_TEST_NAME with your test name.
{ pkgs ? import <nixpkgs> { } }:

let
  # Script to emit test result spans
  emitTestSpan = pkgs.writeShellScriptBin "emit_test_span" ''
    set -e
    TEST_NAME="''${1:-unknown}"
    STATUS="''${2:-passed}"
    DURATION_MS="''${3:-1000}"

    TRACE_ID=$(${pkgs.openssl}/bin/openssl rand -hex 16)
    SPAN_ID=$(${pkgs.openssl}/bin/openssl rand -hex 8)
    NOW_NS=$(date +%s%N)

    # Map status to OTEL status code
    if [ "$STATUS" = "passed" ]; then
      STATUS_CODE=1  # OK
    else
      STATUS_CODE=2  # ERROR
    fi

    ${pkgs.curl}/bin/curl -sS -X POST \
      "''${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}/v1/traces" \
      -H "Content-Type: application/json" \
      -d @- << EOF
    {
      "resourceSpans": [{
        "resource": {
          "attributes": [
            {"key": "service.name", "value": {"stringValue": "nixos-integration-tests"}}
          ]
        },
        "scopeSpans": [{
          "spans": [{
            "traceId": "$TRACE_ID",
            "spanId": "$SPAN_ID",
            "name": "test.$TEST_NAME",
            "kind": 1,
            "startTimeUnixNano": "$NOW_NS",
            "endTimeUnixNano": "$NOW_NS",
            "status": {"code": $STATUS_CODE},
            "attributes": [
              {"key": "test.name", "value": {"stringValue": "$TEST_NAME"}},
              {"key": "test.status", "value": {"stringValue": "$STATUS"}},
              {"key": "test.duration_ms", "value": {"intValue": $DURATION_MS}}
            ]
          }]
        }]
      }]
    }
    EOF

    echo "Emitted span for test: $TEST_NAME (status=$STATUS)"
  '';
in
pkgs.testers.nixosTest {
  name = "TODO_TEST_NAME";

  nodes.machine = { config, pkgs, ... }: {
    virtualisation = {
      memorySize = 2048;
      diskSize = 4096;
      cores = 2;
    };

    # Test user
    users.users.testuser = {
      isNormalUser = true;
      home = "/home/testuser";
    };

    # OTEL configuration
    environment.sessionVariables = {
      OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318";
      OTEL_SERVICE_NAME = "nixos-integration-tests";
    };

    environment.systemPackages = [
      emitTestSpan
      pkgs.curl
      pkgs.jq
      pkgs.openssl
    ];

    # If you have Grafana Alloy module available, enable it:
    # imports = [ ./path/to/grafana-alloy.nix ];
    # services.grafana-alloy.enable = true;
  };

  testScript = ''
    import time

    start_all()
    machine.wait_for_unit("multi-user.target")

    # Track test duration
    test_start = time.time()

    # --- Your test logic here ---
    machine.succeed("echo 'Running test...'")
    machine.sleep(1)

    # Example: Test a service
    # machine.wait_for_unit("my-service.service")
    # machine.wait_for_open_port(8080)

    # Calculate duration
    duration_ms = int((time.time() - test_start) * 1000)

    # Emit test result span
    # Note: This requires OTEL collector to be available
    try:
        machine.succeed(f"emit_test_span 'TODO_TEST_NAME' 'passed' {duration_ms}")
        print(f"Emitted OTEL span: passed in {duration_ms}ms")
    except Exception as e:
        print(f"Warning: Could not emit OTEL span: {e}")
        # Continue even if OTEL emission fails

    print("Test passed!")
  '';
}
