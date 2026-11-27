# agent-netns-publish: ExecStartPost (as root) of agent-netns.service.
#
# Finds the namespace holder (the child of the unit's main process that runs
# as @agentUser@ in a different network namespace than the host's, i.e. PID
# 1's) and writes, root-owned in the root-owned runtime directory:
#   netns.pid    the holder's pid
#   host-netns   the host network namespace id
# agent-enter trusts only these files. (It cannot read the host namespace id
# itself: pasta makes itself non-dumpable, so its /proc/<pid>/ns is closed to
# the agent uid.) Fails the unit if no holder appears.
#
# Substituted at build time: @runDir@ @agentUid@

set -euo pipefail

main="${MAINPID:?MAINPID not set (run as ExecStartPost)}"
pid_file="@runDir@/netns.pid"
host_file="@runDir@/host-netns"
rm -f "$pid_file"
host_ns="$(readlink /proc/1/ns/net)"

for _ in $(seq 1 100); do
  for child in $(pgrep -P "$main" || true); do
    [ "$(stat -c '%u' "/proc/$child")" = "@agentUid@" ] || continue
    child_ns="$(readlink "/proc/$child/ns/net" 2>/dev/null || true)"
    if [ -n "$child_ns" ] && [ "$child_ns" != "$host_ns" ]; then
      tmp="$(mktemp "@runDir@/.host-netns.XXXXXX")"
      printf '%s\n' "$host_ns" >"$tmp"
      chmod 0644 "$tmp"
      mv -f "$tmp" "$host_file"
      tmp="$(mktemp "@runDir@/.netns.pid.XXXXXX")"
      printf '%s\n' "$child" >"$tmp"
      chmod 0644 "$tmp"
      mv -f "$tmp" "$pid_file"
      exit 0
    fi
  done
  sleep 0.1
done
echo "agent-netns-publish: no namespace holder under main pid $main after 10s" >&2
exit 1
