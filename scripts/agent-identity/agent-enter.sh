# agent-enter: run a command as the agent inside the agent network namespace.
#
#   agent-enter [command [args...]]     (default: an interactive login shell)
#
# Must run as @agentUser@ (the owner uses agent-session / agent-shell, which
# sudo to the agent first). Fails closed: if agent-netns.service is not
# running, nothing runs.
#
# Substituted at build time: @runDir@ @agentUser@

set -euo pipefail

pid_file="@runDir@/netns.pid"

die() {
  printf 'agent-enter: %s\n' "$*" >&2
  exit 1
}

[ "$(id -un)" = "@agentUser@" ] \
  || die "must run as @agentUser@, not $(id -un); the owner uses: agent-session or agent-shell"

[ "$#" -gt 0 ] || set -- bash --login

[ -s "$pid_file" ] \
  || die "agent-netns.service is not running ($pid_file missing); start it: sudo systemctl start agent-netns"
pid="$(cat "$pid_file")"
[ -d "/proc/$pid" ] \
  || die "namespace holder pid $pid from $pid_file is gone; restart: sudo systemctl restart agent-netns"
[ "$(stat -c '%U' "/proc/$pid")" = "@agentUser@" ] \
  || die "pid $pid is not owned by @agentUser@; refusing to enter it"

target_ns="$(readlink "/proc/$pid/ns/net")"
self_ns="$(readlink /proc/self/ns/net)"

export AGENT_IDENTITY_NETNS=1
if [ "$target_ns" = "$self_ns" ]; then
  exec "$@"
fi
exec nsenter --target "$pid" --user --net --preserve-credentials -- "$@"
