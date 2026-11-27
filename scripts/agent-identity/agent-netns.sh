# agent-netns: main process of agent-netns.service (User=@agentUser@).
#
# Holds one user+network namespace for every agent session and gives it
# internet through pasta, WITHOUT any path to the host's loopback:
#   --no-map-gw          the gateway address is not mapped to host loopback
#   -T none / -U none    no namespace->host loopback port forwarding
#   -t none / -u none    no host->namespace port forwarding
# Inside, the agent has its own 127.0.0.1 (its dev servers work); the owner's
# loopback listeners (browser DevTools port, local MCP servers, IDE bridges)
# are not reachable. pasta's own host sockets belong to the agent uid, so the
# host nftables table `agent-identity` (no tailnet, no host loopback) still
# applies to everything that leaves the namespace.
#
# The uid inside the namespace is the agent's own (--map-current-user), so
# CLIs that refuse to run as root behave normally.
#
# Substituted at build time: @runDir@ @agentUser@

set -euo pipefail

run_dir="@runDir@"
pid_file="$run_dir/netns.pid"

[ "$(id -un)" = "@agentUser@" ] || { echo "agent-netns: must run as @agentUser@" >&2; exit 1; }
mkdir -p "$run_dir"
rm -f "$pid_file"

unshare --user --map-current-user --net -- sleep infinity &
holder=$!

self_ns="$(readlink /proc/self/ns/net)"
for _ in $(seq 1 100); do
  holder_ns="$(readlink "/proc/$holder/ns/net" 2>/dev/null || true)"
  if [ -n "$holder_ns" ] && [ "$holder_ns" != "$self_ns" ]; then
    break
  fi
  sleep 0.05
done
holder_ns="$(readlink "/proc/$holder/ns/net" 2>/dev/null || true)"
if [ -z "$holder_ns" ] || [ "$holder_ns" = "$self_ns" ]; then
  echo "agent-netns: namespace holder $holder did not leave the host network namespace ($self_ns)" >&2
  exit 1
fi

printf '%s\n' "$holder" >"$pid_file.tmp"
mv -f "$pid_file.tmp" "$pid_file"

exec pasta --foreground --quiet --config-net --no-map-gw \
  --tcp-ports none --udp-ports none --tcp-ns none --udp-ns none \
  "$holder"
