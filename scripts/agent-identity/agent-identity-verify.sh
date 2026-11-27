# agent-identity-verify: the OWNER runs this after applying the configuration
# and `agent-identity-provision dev` (and `hub`, once available). Every check
# prints PASS, FAIL or SKIP with the observed value; SKIP is never counted as
# PASS. Exit status = number of FAILs.
#
#   agent-identity-verify [--no-push]
#
# --no-push skips the two GitHub push probes (they create and delete a
# scratch branch `agent-identity-verify/<ts>-plain` on PittampalliOrg/stacks).
#
# Environment: AGENT_IDENTITY_TAILNET_PROBE (default
# k8s-api-hub.tail286401.ts.net), a tailnet HTTPS host the OWNER can reach.
#
# Substituted at build time: @agentUser@ @ownerUser@ @stateDir@ @allowedRepos@ @botLogin@ @botEmail@

set -uo pipefail

agent="@agentUser@"
owner="@ownerUser@"
state_dir="@stateDir@"
allowed_repos="@allowedRepos@"
bot_login="@botLogin@"
bot_email="@botEmail@"
tailnet_probe="${AGENT_IDENTITY_TAILNET_PROBE:-k8s-api-hub.tail286401.ts.net}"
push=1
[ "${1:-}" = "--no-push" ] && push=0

fails=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
skip() { printf 'SKIP  %s\n' "$*"; }

[ "$(id -un)" = "$owner" ] || { echo "run as $owner (it uses sudo to act as $agent)" >&2; exit 1; }
owner_home="$(getent passwd "$owner" | cut -d: -f6)"
owner_uid="$(id -u "$owner")"

# As the agent, inside its network namespace (the normal session path).
as_agent() { sudo --user="$agent" --login -- agent-enter "$@"; }
# As the agent, OUTSIDE the namespace (proves the host nftables layer alone).
as_agent_host() { sudo --user="$agent" --login -- "$@"; }

echo "== OS identity"
groups_of_agent="$(id -nG "$agent")"
bad=""
for g in wheel docker podman onepassword onepassword-cli networkmanager input uinput tss libvirtd incus-admin "$owner" users; do
  case " $groups_of_agent " in *" $g "*) bad="$bad $g" ;; esac
done
[ -z "$bad" ] && pass "agent groups: $groups_of_agent" || fail "agent is in privileged/owner groups:$bad (all: $groups_of_agent)"

if as_agent_host sudo -n true >/dev/null 2>&1; then
  fail "agent can run sudo without a password"
else
  pass "agent cannot sudo"
fi

echo "== owner credentials are unreachable from the agent"
for path in \
  "$owner_home" \
  "$owner_home/.config/gh/hosts.yml" \
  "$owner_home/.kube/config" \
  "$owner_home/.1password/agent.sock" \
  "$owner_home/.ssh" \
  "$owner_home/.config/pittampalli-pr-reviewer" \
  "$owner_home/.config/google-chrome" \
  "/run/user/$owner_uid" \
  "/etc/onepassword/service-token.env"; do
  # Reachable = a readable file/listable directory, or a writable socket.
  if as_agent_host sh -c 'test -r "$1" || test -w "$1"' _ "$path" </dev/null 2>/dev/null; then
    fail "agent can reach $path"
  else
    pass "agent cannot read $path"
  fi
done
for sock in /run/docker.sock /run/podman/podman.sock; do
  if [ -e "$sock" ] && as_agent_host test -w "$sock"; then
    fail "agent can write $sock (root-equivalent)"
  else
    pass "agent cannot use $sock"
  fi
done

echo "== GitHub identity"
if out="$(as_agent agent-author-token status 2>&1)"; then
  pass "agent-author-token status:"; printf '        %s\n' "${out//$'\n'/$'\n'        }"
else
  fail "agent-author-token status: $out"
fi
# shellcheck disable=SC2086 # word splitting of the repository list is intended
expected_repos="$(printf '%s\n' $allowed_repos | sort | paste -sd, -)"
repos="$(as_agent gh api /installation/repositories --jq '[.repositories[].full_name] | sort | join(",")' 2>&1)"
[ "$repos" = "$expected_repos" ] && pass "token reaches exactly: $repos" || fail "token reaches '$repos', expected '$expected_repos'"
viewer="$(as_agent gh api graphql -f query='{viewer{login}}' --jq .data.viewer.login 2>&1)"
[ "$viewer" = "$bot_login" ] && pass "GitHub viewer is $viewer" || fail "GitHub viewer is '$viewer', expected '$bot_login'"
if out="$(as_agent gh api orgs/PittampalliOrg/actions/permissions 2>&1)"; then
  fail "admin read orgs/PittampalliOrg/actions/permissions succeeded: $out"
else
  pass "admin read refused: $(printf '%s' "$out" | tail -n1)"
fi
if out="$(as_agent gh api repos/PittampalliOrg/stacks/hooks 2>&1)"; then
  fail "repo admin read repos/PittampalliOrg/stacks/hooks succeeded"
else
  pass "repo hooks read refused: $(printf '%s' "$out" | tail -n1)"
fi
if out="$(as_agent gh auth login --with-token </dev/null 2>&1)"; then
  fail "gh auth login was allowed for the agent"
else
  pass "gh auth login is refused: $(printf '%s' "$out" | tail -n1)"
fi
name_email="$(as_agent git config --get user.name) <$(as_agent git config --get user.email)>"
[ "$name_email" = "$bot_login <$bot_email>" ] && pass "git identity: $name_email" || fail "git identity is '$name_email', expected '$bot_login <$bot_email>'"

echo "== GitHub pushes"
if [ "$push" -eq 0 ]; then
  skip "push probes (--no-push)"
else
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  probe="$(cat <<EOF
set -u
d="\$(mktemp -d "\$HOME/.cache/agent-identity-verify.XXXXXX")"
trap 'rm -rf "\$d"' EXIT
cd "\$d"
git init -q
git remote add origin https://github.com/PittampalliOrg/stacks.git
git fetch -q --depth=1 --filter=blob:none origin main || { echo "RESULT fetch-failed"; exit 0; }
git checkout -q -b probe FETCH_HEAD
git commit -q --allow-empty -m "chore: agent-identity verification probe (deleted immediately)"
if git push -q origin HEAD:refs/heads/agent-identity-verify/$ts-plain 2>push-plain.err; then
  echo "RESULT plain-pushed"
  git push -q origin --delete agent-identity-verify/$ts-plain 2>/dev/null && echo "RESULT plain-deleted" || echo "RESULT plain-NOT-deleted"
else
  echo "RESULT plain-refused \$(tail -n2 push-plain.err | tr '\n' ' ')"
fi
mkdir -p .github/workflows
printf 'name: probe\non: workflow_dispatch\njobs: {}\n' >.github/workflows/agent-identity-verify.yml
git add .github/workflows/agent-identity-verify.yml
git commit -q -m "chore: agent-identity workflow probe (must be refused)"
if git push -q origin HEAD:refs/heads/agent-identity-verify/$ts-workflow 2>push-wf.err; then
  echo "RESULT workflow-pushed"
  git push -q origin --delete agent-identity-verify/$ts-workflow 2>/dev/null || true
else
  echo "RESULT workflow-refused \$(grep -i -m1 workflow push-wf.err)"
fi
if git push --dry-run https://github.com/$owner/nixos-config.git HEAD:refs/heads/agent-identity-verify 2>other.err; then
  echo "RESULT other-repo-allowed"
else
  echo "RESULT other-repo-refused \$(grep -m1 'agent-author-token' other.err)"
fi
EOF
)"
  results="$(as_agent bash -c "$probe" 2>&1)"
  case "$results" in *"RESULT plain-pushed"*) pass "push to a scratch branch on PittampalliOrg/stacks works" ;; *) fail "push to a scratch branch failed: $(grep 'RESULT plain' <<<"$results")" ;; esac
  case "$results" in *"RESULT plain-NOT-deleted"*) fail "scratch branch agent-identity-verify/$ts-plain was NOT deleted; delete it by hand" ;; esac
  case "$results" in *"RESULT workflow-refused"*) pass "push touching .github/workflows/ refused: $(grep 'RESULT workflow' <<<"$results" | cut -d' ' -f3-)" ;; *) fail "push touching .github/workflows/ was NOT refused: $(grep 'RESULT workflow' <<<"$results")" ;; esac
  case "$results" in *"RESULT other-repo-refused"*) pass "push to a repository outside the two is refused locally: $(grep 'RESULT other' <<<"$results" | cut -d' ' -f3-)" ;; *) fail "push to $owner/nixos-config was not refused: $(grep 'RESULT other' <<<"$results")" ;; esac
fi

echo "== Kubernetes (read-only)"
contexts="$(as_agent kubectl config get-contexts -o name 2>&1 | sort | paste -sd, -)"
case ",$contexts," in
  *,dev,*) ;;
  *) fail "agent kubeconfig has no dev context (contexts: $contexts); run: agent-identity-provision dev" ;;
esac
extra="$(printf '%s\n' "${contexts//,/$'\n'}" | grep -vxE 'dev|hub' || true)"
[ -z "$extra" ] && pass "agent kube contexts: $contexts" || fail "agent kubeconfig has extra contexts: $extra"
check_kube() {
  local ctx="$1" sa="$2" who
  who="$(as_agent kubectl --context "$ctx" auth whoami -o jsonpath='{.status.userInfo.username}' 2>&1)"
  [ "$who" = "system:serviceaccount:agent-identity:$sa" ] && pass "$ctx: whoami $who" || fail "$ctx: whoami '$who', expected system:serviceaccount:agent-identity:$sa"
  local a
  a="$(as_agent kubectl --context "$ctx" auth can-i create pods -A 2>&1)"; [ "$a" = "no" ] && pass "$ctx: can-i create pods -A -> no" || fail "$ctx: can-i create pods -A -> $a"
  a="$(as_agent kubectl --context "$ctx" auth can-i list secrets -A 2>&1)"; [ "$a" = "no" ] && pass "$ctx: can-i list secrets -A -> no" || fail "$ctx: can-i list secrets -A -> $a"
  a="$(as_agent kubectl --context "$ctx" auth can-i '*' '*' -A 2>&1)"; [ "$a" = "no" ] && pass "$ctx: can-i '*' '*' -A -> no" || fail "$ctx: can-i '*' '*' -A -> $a"
  a="$(as_agent kubectl --context "$ctx" auth can-i get pods -A 2>&1)"; [ "$a" = "yes" ] && pass "$ctx: can-i get pods -A -> yes" || fail "$ctx: can-i get pods -A -> $a"
  if as_agent kubectl --context "$ctx" get pods -A --request-timeout=20s -o name >/dev/null 2>&1; then pass "$ctx: get pods -A works"; else fail "$ctx: get pods -A failed"; fi
}
if [ -s "$state_dir/dev-server" ]; then check_kube dev local-minter; else fail "dev not provisioned ($state_dir/dev-server missing)"; fi
if [ -s "$state_dir/hub-server" ]; then check_kube hub local-viewer; else skip "hub not provisioned (needs the stacks hub ServiceAccount; then: agent-identity-provision hub)"; fi
mode="$(stat -c '%a %U' "$state_dir/dev-local-minter.token" 2>&1)"
[ "$mode" = "600 $agent" ] && pass "bound token file mode: $mode" || fail "bound token file $state_dir/dev-local-minter.token is '$mode', expected '600 $agent'"

echo "== network boundary"
code="$(as_agent curl -s -o /dev/null -m 10 -w '%{http_code}' https://api.github.com/zen 2>&1)"
[ "$code" = "200" ] && pass "agent namespace reaches the internet (api.github.com $code)" || fail "agent namespace cannot reach api.github.com ($code)"
if as_agent python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));s.listen();socket.create_connection(s.getsockname(),timeout=3)' 2>/dev/null; then
  pass "agent namespace has its own working loopback"
else
  fail "agent namespace loopback does not work"
fi
# Every TCP listener the owner's host has on loopback must be unreachable.
reached=""
checked=0
while read -r addr; do
  host="${addr%:*}"; port="${addr##*:}"
  host="${host#[}"; host="${host%]}"
  checked=$((checked + 1))
  if as_agent python3 -c "import socket;socket.create_connection(('$host',$port),timeout=2)" </dev/null 2>/dev/null; then
    reached="$reached $addr"
  fi
done < <(ss -ltnH | awk '{print $4}' | grep -E '^(127\.|\[::1\])' | sort -u)
[ -z "$reached" ] && pass "none of the host's $checked loopback listeners is reachable from the agent namespace" || fail "agent namespace reached host loopback listeners:$reached"
if as_agent_host python3 -c 'import socket;socket.create_connection(("127.0.0.1",22),timeout=3)' 2>/dev/null; then
  fail "outside the namespace the agent uid reaches host loopback (127.0.0.1:22): nftables table agent-identity is not loaded"
else
  if python3 -c 'import socket;socket.create_connection(("127.0.0.1",22),timeout=3)' 2>/dev/null; then
    pass "host nftables layer: the agent uid cannot reach 127.0.0.1:22 (the owner can)"
  else
    skip "host nftables layer: 127.0.0.1:22 is not open for the owner either, so the probe proves nothing"
  fi
fi
if curl -s -o /dev/null -m 10 "https://$tailnet_probe/version" 2>/dev/null; then
  if as_agent curl -s -o /dev/null -m 10 "https://$tailnet_probe/version" 2>/dev/null || as_agent_host curl -s -o /dev/null -m 10 "https://$tailnet_probe/version" 2>/dev/null; then
    fail "agent reached tailnet host $tailnet_probe (Tailscale identity = the owner's)"
  else
    pass "agent cannot reach tailnet host $tailnet_probe (the owner can)"
  fi
  # tailscaled dials on the agent's behalf only if its LocalAPI grants the
  # agent write access; a refusal names it. Anything else (a connection, a
  # hang until timeout, another error) is not proof of refusal.
  nc_err="$(as_agent_host timeout 10 tailscale nc "$tailnet_probe" 443 </dev/null 2>&1 >/dev/null)"
  nc_rc=$?
  if [ "$nc_rc" -ne 0 ] && printf '%s' "$nc_err" | grep -qiE 'denied|forbidden|permission|not allowed'; then
    pass "tailscale nc as the agent is refused by tailscaled: $(printf '%s' "$nc_err" | tail -n1)"
  else
    fail "tailscale nc as the agent was not clearly refused (exit $nc_rc: $(printf '%s' "$nc_err" | tail -n1)); tailscaled may dial the tailnet for the agent"
  fi
else
  skip "tailnet probe: the owner cannot reach $tailnet_probe either, so the probe proves nothing (set AGENT_IDENTITY_TAILNET_PROBE)"
fi

echo
if [ "$fails" -eq 0 ]; then echo "agent-identity-verify: all checks passed"; else echo "agent-identity-verify: $fails check(s) FAILED"; fi
exit "$fails"
