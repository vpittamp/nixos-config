# agent-session / agent-shell: the owner's launchers for agent work.
#
#   agent-session [name] [herdr args...]   attach (or start) the agent's herdr
#                                          session <name> (default: lead)
#   agent-shell [command...]               a login shell (or one command) as
#                                          the agent, inside its namespace
#
# Both sudo to @agentUser@ with a login environment (its own HOME, PATH, gh,
# git and kubeconfig) and then enter the agent network namespace. sudo is
# configured with use_pty, so agent processes never hold the owner's terminal.
# Detaching from herdr leaves the agent's herdr server running in the
# namespace; run agent-session again to re-attach.
#
# Substituted at build time: @agentUser@ @mode@

set -euo pipefail

if [ "$(id -un)" = "@agentUser@" ]; then
  echo "agent-session: already the @agentUser@ user; use agent-enter" >&2
  exit 1
fi

mode="@mode@"
case "$mode" in
  session)
    name="${1:-lead}"
    if [ "$#" -gt 0 ]; then shift; fi
    exec sudo --user=@agentUser@ --login -- agent-enter herdr --session "$name" "$@"
    ;;
  shell)
    exec sudo --user=@agentUser@ --login -- agent-enter "$@"
    ;;
esac
