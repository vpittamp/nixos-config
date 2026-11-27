# agent-identity-provision: the OWNER's one manual step. Issues a short-lived
# bound ServiceAccount token with the owner's own kubeconfig and places it
# where only the agent user can read it; writes the agent's read-only
# kubeconfig (no secret in it: it points at the token files).
#
#   agent-identity-provision dev [--duration 24h]
#       kubectl --context dev -n agent-identity create token local-minter
#       -> @stateDir@/dev-local-minter.token   (0600 @agentUser@)
#   agent-identity-provision hub [--duration 24h]
#       kubectl --context hub -n agent-identity create token local-viewer
#       -> @stateDir@/hub-local-viewer.token   (0600 @agentUser@)
#       (needs the hub ServiceAccount from the stacks follow-up; see
#        docs/AGENT_IDENTITY.md "Hub read access")
#   agent-identity-provision kubeconfig
#       only re-render @stateDir@/kubeconfig
#
# The token goes straight from kubectl into `sudo install` through a pipe; it
# is never in a variable, an argument or an intermediate file. The server URL
# and CA (not secrets) are copied from the owner's kubeconfig context.
#
# Environment: AGENT_IDENTITY_DEV_CONTEXT (default dev),
#              AGENT_IDENTITY_HUB_CONTEXT (default hub).
#
# Substituted at build time: @stateDir@ @agentUser@

set -euo pipefail

state_dir="@stateDir@"
agent_user="@agentUser@"

die() {
  printf 'agent-identity-provision: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'usage: agent-identity-provision dev|hub [--duration <go duration, default 24h>]\n       agent-identity-provision kubeconfig\n' >&2
  exit 2
}

[ "$(id -u)" -ne 0 ] || die "run as the owner (it uses the owner's kubeconfig), not as root"
[ "$(id -un)" != "$agent_user" ] || die "run as the owner, not as $agent_user"

cluster="${1:-}"
[ -n "$cluster" ] || usage
shift
duration="24h"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --duration) duration="${2:?--duration needs a value}"; shift 2 ;;
    *) usage ;;
  esac
done

render_kubeconfig() {
  local tmp c current=""
  tmp="$(mktemp)"
  {
    printf 'apiVersion: v1\nkind: Config\npreferences: {}\nclusters:\n'
    for c in dev hub; do
      [ -s "$state_dir/$c-server" ] || continue
      printf -- '- name: %s\n  cluster:\n    server: %s\n    certificate-authority: %s\n' \
        "$c" "$(cat "$state_dir/$c-server")" "$state_dir/$c-ca.crt"
    done
    printf 'users:\n'
    [ -s "$state_dir/dev-server" ] \
      && printf -- '- name: dev-local-minter\n  user:\n    tokenFile: %s\n' "$state_dir/dev-local-minter.token"
    [ -s "$state_dir/hub-server" ] \
      && printf -- '- name: hub-local-viewer\n  user:\n    tokenFile: %s\n' "$state_dir/hub-local-viewer.token"
    printf 'contexts:\n'
    if [ -s "$state_dir/dev-server" ]; then
      printf -- '- name: dev\n  context:\n    cluster: dev\n    user: dev-local-minter\n'
      current="dev"
    fi
    if [ -s "$state_dir/hub-server" ]; then
      printf -- '- name: hub\n  context:\n    cluster: hub\n    user: hub-local-viewer\n'
      [ -n "$current" ] || current="hub"
    fi
    printf 'current-context: "%s"\n' "$current"
  } >"$tmp"
  sudo install -m 0644 -o root -g root "$tmp" "$state_dir/kubeconfig"
  rm -f "$tmp"
  echo "wrote $state_dir/kubeconfig (current-context: ${current:-none}; contexts: $(sed -n 's/^- name: \(dev\|hub\)$/\1/p' "$state_dir/kubeconfig" | sort -u | paste -sd' ' -))"
}

provision() {
  local name="$1" context="$2" sa="$3" server ca_b64
  kubectl config get-contexts "$context" >/dev/null 2>&1 \
    || die "the owner's kubeconfig has no context '$context'"
  server="$(kubectl config view --minify --context "$context" -o jsonpath='{.clusters[0].cluster.server}')"
  [ -n "$server" ] || die "context '$context' has no cluster server"
  case "$server" in
    https://*.ts.net*|https://100.*)
      die "context '$context' points at a tailnet address ($server); the agent cannot reach the tailnet by design. Use a context whose server is the cluster's public API endpoint" ;;
  esac
  ca_b64="$(kubectl config view --raw --minify --context "$context" -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
  [ -n "$ca_b64" ] || die "context '$context' has no certificate-authority-data"

  kubectl --context "$context" -n agent-identity get serviceaccount "$sa" -o name >/dev/null \
    || die "ServiceAccount agent-identity/$sa does not exist on '$context' (is the stacks change synced?)"

  printf '%s' "$ca_b64" | base64 -d | sudo install -m 0644 -o root -g root /dev/stdin "$state_dir/$name-ca.crt"
  printf '%s\n' "$server" | sudo install -m 0644 -o root -g root /dev/stdin "$state_dir/$name-server"

  # The one manual credential step. Bound token, expires after $duration.
  kubectl --context "$context" -n agent-identity create token "$sa" --duration="$duration" \
    | sudo install -m 0600 -o "$agent_user" -g "$agent_user" /dev/stdin "$state_dir/$name-$sa.token"
  echo "placed $state_dir/$name-$sa.token (0600 $agent_user); it expires after $duration (the API server may cap it): re-run before then"

  render_kubeconfig

  echo "check, as $agent_user:"
  sudo --user="$agent_user" --login -- kubectl --context "$name" auth whoami -o jsonpath='{.status.userInfo.username}{"\n"}' \
    || die "the agent could not authenticate to '$name' with the new token"
}

case "$cluster" in
  dev) provision dev "${AGENT_IDENTITY_DEV_CONTEXT:-dev}" local-minter ;;
  hub) provision hub "${AGENT_IDENTITY_HUB_CONTEXT:-hub}" local-viewer ;;
  kubeconfig) render_kubeconfig ;;
  *) usage ;;
esac
