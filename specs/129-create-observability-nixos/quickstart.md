# Quickstart: NixOS Full Observability Stack

## Prerequisites

- NixOS with flakes enabled
- Tailscale connected to network with K8s cluster
- Kernel 5.8+ with BTF support (for Beyla)
- LGTM stack deployed in Kubernetes (assumed pre-existing)

## Quick Enable

Add to your host configuration (e.g., `configurations/thinkpad.nix`):

```nix
{
  services.grafana-alloy = {
    enable = true;
    k8sEndpoint = "http://otel-collector.tail286401.ts.net:4318";
  };

  # Optional: eBPF auto-instrumentation
  services.grafana-beyla.enable = true;
}
```

Rebuild:

```bash
sudo nixos-rebuild dry-build --flake .#thinkpad
sudo nixos-rebuild switch --flake .#thinkpad
```

## Verify Services

```bash
# Check service status
systemctl status grafana-alloy
systemctl status grafana-beyla  # if enabled
systemctl --user status otel-ai-monitor

# Check Alloy logs
journalctl -u grafana-alloy -f

# Test OTLP endpoint
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}'
# Should return 200 OK
```

## View in Grafana

1. Open Grafana: `http://grafana.tail286401.ts.net:3000`
2. **Metrics**: Explore → Mimir → Query `node_cpu_seconds_total{host="thinkpad"}`
3. **Logs**: Explore → Loki → Query `{host="thinkpad", service="otel-ai-monitor"}`
4. **Traces**: Explore → Tempo → Search by service name

## Key Ports

| Service | Port | Description |
|---------|------|-------------|
| Alloy OTLP | 4318 | Receives OTLP HTTP from apps |
| otel-ai-monitor | 4320 | Local AI session tracking |
| Beyla | (none) | eBPF, no port needed |

## Troubleshooting

### Alloy not receiving telemetry

```bash
# Check Alloy is listening
ss -tlnp | grep 4318

# Check Claude Code OTEL config
echo $OTEL_EXPORTER_OTLP_ENDPOINT
# Should be: http://localhost:4318
```

### Beyla not instrumenting processes

```bash
# Check capabilities
grep Cap /proc/$(pgrep beyla)/status

# Check kernel version
uname -r  # Needs 5.8+

# Check perf_event_paranoid
cat /proc/sys/kernel/perf_event_paranoid  # Should be ≤1
```

### Telemetry not reaching K8s

```bash
# Test Tailscale connectivity
ping otel-collector.tail286401.ts.net

# Check Alloy export queue
curl -s localhost:12345/metrics | grep otelcol_exporter
```

## AI Session Monitoring

The existing `otel-ai-monitor` service is preserved and continues to:
- Receive AI session telemetry from Alloy
- Track session state (working/completed/idle)
- Update EWW widgets in real-time
- Send desktop notifications

No changes needed to existing AI monitoring workflow.

## Disable/Enable Components

```nix
{
  services.grafana-alloy = {
    enable = true;
    enableNodeExporter = false;  # Disable system metrics
    enableJournald = false;      # Disable log collection
  };

  services.grafana-beyla.enable = false;  # Disable eBPF tracing
}
```
