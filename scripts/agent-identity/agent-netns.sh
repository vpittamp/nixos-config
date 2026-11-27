# agent-netns: main process of agent-netns.service (User=@agentUser@).
#
# Holds one user+network+mount namespace for every agent session and gives it
# internet through pasta, WITHOUT any path to the host's loopback:
#   --no-map-gw          the gateway address is not mapped to host loopback
#   -T none / -U none    no namespace->host loopback port forwarding
#   -t none / -u none    no host->namespace port forwarding
# Inside, the agent has its own 127.0.0.1 (its dev servers work); host
# loopback listeners and host abstract unix sockets are not reachable. pasta's
# own host sockets belong to the agent uid, so the host nftables table
# `agent-identity` still applies to everything that leaves the namespace.
#
# The mount namespace is created from the unit's (PrivateTmp, private
# /dev/shm), so sessions that join it see the private /tmp, locked.
#
# The uid inside the namespace is the agent's own (--map-current-user), so
# CLIs that refuse to run as root behave normally.
#
# The holder's pid is published by agent-netns-publish (ExecStartPost, root),
# not by this script: the runtime directory is root-owned.
#
# Substituted at build time: @agentUser@

set -euo pipefail

[ "$(id -un)" = "@agentUser@" ] || { echo "agent-netns: must run as @agentUser@" >&2; exit 1; }

unshare --user --map-current-user --net --mount -- sleep infinity &
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

exec pasta --foreground --quiet --config-net --no-map-gw \
  --tcp-ports none --udp-ports none --tcp-ns none --udp-ns none \
  "$holder"
