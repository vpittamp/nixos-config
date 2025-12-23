# OpenTelemetry Integration for NixOS Tests

Emit telemetry from tests to Grafana for observability of test runs.

## Contents

- [Architecture](#architecture)
- [Setup](#setup)
- [Emitting Test Spans](#emitting-test-spans)
- [Verifying Telemetry Pipeline](#verifying-telemetry-pipeline)
- [Grafana Queries](#grafana-queries)
- [Best Practices](#best-practices)

## Architecture

```
Test VM                          Host/Collector              Remote
┌─────────────────┐             ┌──────────────┐           ┌─────────────────┐
│ testScript      │             │ Grafana      │           │ K8s LGTM Stack  │
│ emit_test_span  │────OTLP────▶│ Alloy :4318  │───OTLP───▶│ Tempo (traces)  │
│                 │             │              │           │ Mimir (metrics) │
└─────────────────┘             └──────────────┘           │ Loki (logs)     │
                                                           └─────────────────┘
```

**Data Flow:**
1. Test emits spans via `emit_test_span.sh` using OTLP HTTP
2. Grafana Alloy receives on port 4318
3. Alloy forwards to local monitoring (EWW widgets) and remote K8s stack
4. Query results in Grafana dashboards

## Setup

### Include Alloy in Test VM

```nix
nodes.machine = { config, pkgs, ... }: {
  # Import your Alloy module
  imports = [ ./modules/services/grafana-alloy.nix ];

  services.grafana-alloy = {
    enable = true;
    otlpPort = 4318;
  };

  # Set OTLP endpoint for test scripts
  environment.sessionVariables = {
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318";
    OTEL_SERVICE_NAME = "nixos-integration-tests";
  };

  environment.systemPackages = with pkgs; [
    curl
    jq
    openssl  # For trace ID generation
  ];
};
```

### Minimal Setup (Without Full Alloy)

For tests that just need to emit spans without full collection:

```nix
environment.systemPackages = with pkgs; [
  curl
  jq
];

environment.sessionVariables = {
  # Point to host collector
  OTEL_EXPORTER_OTLP_ENDPOINT = "http://10.0.2.2:4318";  # VM host
};
```

## Emitting Test Spans

### Using emit_test_span.sh

The provided script emits test result traces:

```bash
# Basic usage
scripts/emit_test_span.sh "test-name" "passed" [duration_ms]

# Examples
scripts/emit_test_span.sh "nginx-startup" "passed" 1500
scripts/emit_test_span.sh "database-migration" "failed" 5000
scripts/emit_test_span.sh "network-connectivity" "passed"
```

### From testScript

```python
import time

# Track test duration
start_time = time.time()

# ... run test steps ...
machine.wait_for_unit("nginx.service")
machine.wait_for_open_port(80)

# Emit result span
duration_ms = int((time.time() - start_time) * 1000)
machine.succeed(f"emit_test_span.sh 'nginx-test' 'passed' {duration_ms}")
```

### Manual OTLP Emission

For custom span attributes:

```python
import json

span_data = {
    "resourceSpans": [{
        "resource": {
            "attributes": [
                {"key": "service.name", "value": {"stringValue": "nixos-tests"}},
                {"key": "test.suite", "value": {"stringValue": "sway-integration"}}
            ]
        },
        "scopeSpans": [{
            "spans": [{
                "traceId": "$(openssl rand -hex 16)",
                "spanId": "$(openssl rand -hex 8)",
                "name": "test.my_custom_test",
                "kind": 1,
                "startTimeUnixNano": "$(date +%s%N)",
                "endTimeUnixNano": "$(date +%s%N)",
                "status": {"code": 1},  # 1=OK, 2=ERROR
                "attributes": [
                    {"key": "test.name", "value": {"stringValue": "my_custom_test"}},
                    {"key": "test.result", "value": {"stringValue": "passed"}},
                    {"key": "vm.memory_mb", "value": {"intValue": 2048}}
                ]
            }]
        }]
    }]
}

machine.succeed(f"""
  curl -X POST http://localhost:4318/v1/traces \\
    -H 'Content-Type: application/json' \\
    -d '{json.dumps(span_data)}'
""")
```

## Verifying Telemetry Pipeline

### Test OTLP Endpoint Health

```python
# In testScript
machine.wait_for_open_port(4318)
machine.succeed("curl -f http://localhost:4318/v1/traces -X POST -H 'Content-Type: application/json' -d '{}'")
```

### Verify Span Reception

```python
# Emit test span
machine.succeed("emit_test_span.sh 'pipeline-test' 'passed' 100")

# Check Alloy received it (if logging enabled)
machine.succeed("journalctl -u grafana-alloy --no-pager | grep -q 'pipeline-test'")
```

### Full Pipeline Verification Test

```nix
# templates/otel_traced.nix includes this pattern
testScript = ''
    start_all()

    # Wait for collector
    machine.wait_for_unit("grafana-alloy.service")
    machine.wait_for_open_port(4318)

    # Emit test span
    machine.succeed("emit_test_span.sh 'otel-pipeline-test' 'passed' 100")

    # Verify local reception
    machine.succeed("curl -s http://localhost:12345/metrics | grep -q otlp")

    print("OTEL pipeline verified!")
'';
```

## Grafana Queries

### Tempo (Traces)

```
# Find test traces
{service.name="nixos-integration-tests"}

# Filter by test name
{service.name="nixos-integration-tests" && name=~"test.*nginx.*"}

# Failed tests only
{service.name="nixos-integration-tests" && status.code=2}
```

### Metrics (Mimir)

If you emit span metrics:

```promql
# Test duration histogram
histogram_quantile(0.95, sum(rate(test_duration_seconds_bucket[5m])) by (le, test_name))

# Test success rate
sum(rate(test_result_total{status="passed"}[1h])) / sum(rate(test_result_total[1h]))
```

### Loki (Logs)

```logql
{job="nixos-tests"} |= "FAIL"
{service_name="nixos-integration-tests"} | json | status="failed"
```

## Best Practices

### 1. Span Naming Convention

```
test.<suite>.<test_name>
```

Examples:
- `test.sway.window_launch`
- `test.daemon.i3pm_startup`
- `test.network.client_server`

### 2. Include Useful Attributes

```python
attributes = {
    "test.name": "nginx-startup",
    "test.suite": "web-services",
    "vm.memory_mb": 2048,
    "vm.cores": 2,
    "nixos.version": "24.11",
    "git.commit": "abc123"
}
```

### 3. Parent/Child Span Hierarchy

Create a parent span for the entire test, child spans for each step:

```python
import os

# Generate parent trace ID
trace_id = os.popen("openssl rand -hex 16").read().strip()
os.environ["TEST_TRACE_ID"] = trace_id

# Parent span for entire test
machine.succeed(f"TEST_TRACE_ID={trace_id} emit_test_span.sh 'full-test' 'passed' 5000")

# Child spans for each step (would need script modification for parent_span_id)
```

### 4. Emit on Both Success and Failure

```python
try:
    machine.succeed("risky-command")
    machine.succeed("emit_test_span.sh 'risky-test' 'passed' 1000")
except Exception:
    machine.succeed("emit_test_span.sh 'risky-test' 'failed' 1000")
    raise
```

### 5. Correlation with AI Telemetry

If testing AI CLI behavior, correlate with otel-ai-monitor:

```python
# Start AI CLI session
machine.succeed("claude --help")  # Triggers telemetry

# Wait for session span
machine.sleep(5)

# Query local monitor
output = machine.succeed("curl -s http://localhost:4320/status")
assert "working" in output or "idle" in output
```

## Troubleshooting

### Spans Not Appearing

1. Check Alloy is running:
   ```python
   machine.succeed("systemctl status grafana-alloy")
   ```

2. Check OTLP endpoint:
   ```python
   machine.succeed("curl -v http://localhost:4318/v1/traces")
   ```

3. Check Alloy logs:
   ```python
   machine.succeed("journalctl -u grafana-alloy -n 50 --no-pager")
   ```

### Network Issues

If VM can't reach host collector:

```python
# Use QEMU user-mode networking gateway
OTEL_EXPORTER_OTLP_ENDPOINT = "http://10.0.2.2:4318"
```

### Timestamp Issues

Ensure NTP is synced or use relative timestamps:

```nix
services.timesyncd.enable = true;
```
