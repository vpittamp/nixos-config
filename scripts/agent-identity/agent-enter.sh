# agent-enter: run a command as the agent inside the agent namespace
# (user + network + mount).
#
#   agent-enter [command [args...]]     (default: an interactive login shell)
#
# Also the core of the agent's login shell, so every login lands inside.
# Must run as @agentUser@. Fails CLOSED: nothing runs unless the target is
# the holder published by root for the running agent-netns.service and is in
# a different network namespace than the service's host-side process.
#
# Substituted at build time: @runDir@ @agentUser@ @agentUid@

set -euo pipefail

pid_file="@runDir@/netns.pid"

die() {
  printf 'agent-enter: %s\n' "$*" >&2
  exit 1
}

[ "$(id -u)" = "@agentUid@" ] \
  || die "must run as @agentUser@ (uid @agentUid@), not $(id -un); the owner uses: agent-session or agent-shell"

[ "$#" -gt 0 ] || set -- bash --login

# Trust only root-owned state.
[ "$(stat -c '%u %a' "@runDir@")" = "0 755" ] \
  || die "@runDir@ is not root-owned mode 755 ($(stat -c '%U %a' "@runDir@" 2>&1)); refusing"
[ -s "$pid_file" ] \
  || die "agent-netns.service is not running ($pid_file missing); start it: sudo systemctl start agent-netns"
[ "$(stat -c '%u' "$pid_file")" = "0" ] \
  || die "$pid_file is not owned by root; refusing"
pid="$(cat "$pid_file")"
case "$pid" in ''|*[!0-9]*) die "$pid_file does not hold a pid" ;; esac

main="$(systemctl show --property=MainPID --value agent-netns.service)"
[ -n "$main" ] && [ "$main" != "0" ] \
  || die "agent-netns.service has no main process; start it: sudo systemctl start agent-netns"
ppid="$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
[ "$ppid" = "$main" ] \
  || die "published holder $pid is not a child of agent-netns.service (main $main, parent ${ppid:-none}); restart: sudo systemctl restart agent-netns"
[ "$(stat -c '%u' "/proc/$pid")" = "@agentUid@" ] \
  || die "holder $pid does not run as @agentUser@; refusing"

[ -s "@runDir@/host-netns" ] && [ "$(stat -c '%u' "@runDir@/host-netns")" = "0" ] \
  || die "@runDir@/host-netns is missing or not root-owned; restart: sudo systemctl restart agent-netns"
host_ns="$(cat "@runDir@/host-netns")"
target_ns="$(readlink "/proc/$pid/ns/net")"
self_ns="$(readlink /proc/self/ns/net)"
[ -n "$target_ns" ] && [ "$target_ns" != "$host_ns" ] \
  || die "holder $pid is in the host network namespace ($host_ns); refusing"

export AGENT_IDENTITY_NETNS=1
if [ "$self_ns" = "$target_ns" ]; then
  exec "$@"
fi
# The namespace has its own /tmp, /var/tmp and /dev/shm: a working directory
# there does not exist inside, so start in HOME instead.
# (Callers may run with an empty environment: no PWD, no HOME.)
home="${HOME:-/}"
wd="${PWD:-$(pwd)}"
case "$wd" in /tmp|/tmp/*|/var/tmp|/var/tmp/*|/dev/shm|/dev/shm/*) wd="$home" ;; esac
exec nsenter --target "$pid" --user --net --mount --preserve-credentials --wd="$wd" -- "$@"
