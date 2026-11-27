# agent-identity-verify: the OWNER runs this after applying the configuration
# and `agent-identity-provision dev` (and `hub`, once available).
#
#   agent-identity-verify [--no-push]
#
# Every check prints one of
#   PASS   the specific expected outcome was observed (a named refusal:
#          EACCES / connection refused / HTTP 403 / `no`), with its value
#   FAIL   the opposite was observed, with the value
#   NORUN  the check could not run or saw an outcome that proves nothing
#          (e.g. a timeout, an absent target, no positive control)
# A refusal is never inferred from "the command failed".
#
# Nothing the agent can write is executed or loaded by this script: commands
# run as the agent are only the fixed probe tool (Python -I) and, inside the
# namespace, store-path binaries under `env -i` with HOME=/var/empty; the
# agent's profile, rc files, PATH, site-packages and config files are never
# used. GitHub checks use the token with curl as the owner. The run aborts
# before any check if the agent cannot run as uid @agentUid@ inside a network
# namespace different from the host's. Exit status = FAIL + NORUN count.
#
# --no-push skips the two GitHub push probes (they create and delete a
# scratch branch on PittampalliOrg/stacks).
#
# Environment: AGENT_IDENTITY_TAILNET_PROBE=<host:port> a tailnet TCP endpoint
# the owner can reach (default: the first *.ts.net server in the owner's
# kubeconfig, port 443).
#
# Substituted at build time: @agentUser@ @agentUid@ @ownerUser@ @stateDir@ @allowedRepos@ @botLogin@ @botEmail@
#   @agentIdentityProbe@ @agentEnter@ @agentAuthorToken@ @agentGitConfig@ @agentGh@

set -uo pipefail

agent="@agentUser@"
agent_uid="@agentUid@"
owner="@ownerUser@"
state_dir="@stateDir@"
allowed_repos="@allowedRepos@"
bot_login="@botLogin@"
bot_email="@botEmail@"
push=1
[ "${1:-}" = "--no-push" ] && push=0

fails=0
noruns=0
pass() { printf 'PASS   %s\n' "$*"; }
fail() { printf 'FAIL   %s\n' "$*"; fails=$((fails + 1)); }
norun() { printf 'NORUN  %s\n' "$*"; noruns=$((noruns + 1)); }

[ "$(id -un)" = "$owner" ] || { echo "run as $owner (it uses sudo to act as $agent)" >&2; exit 2; }
owner_home="$(getent passwd "$owner" | cut -d: -f6)"
owner_uid="$(id -u "$owner")"
probe_bin="@agentIdentityProbe@"
enter="@agentEnter@"
token_bin="@agentAuthorToken@"
git_config="@agentGitConfig@"
agent_gh="@agentGh@"
# Store paths of every tool run as the agent (resolved from this script's own
# runtime inputs, never from the agent's PATH).
kubectl_bin="$(command -v kubectl)"; git_bin="$(command -v git)"; bash_bin="$(command -v bash)"
curl_bin="$(command -v curl)"; ls_bin="$(command -v ls)"; unshare_bin="$(command -v unshare)"
py_bin="$(command -v python3)"
clean_env=(/run/current-system/sw/bin/env -i HOME=/var/empty PATH=/run/current-system/sw/bin LANG=C.UTF-8)

# Inside the agent namespace (agent-enter), in an empty environment.
as_agent() { sudo --user="$agent" -- "$enter" "${clean_env[@]}" "$@" </dev/null; }
# The fixed probe tool: outside the namespace (host side) and inside it.
probe_host() { sudo --user="$agent" -- "$probe_bin" "$@" </dev/null 2>&1; }
probe_in() { as_agent "$probe_bin" "$@" 2>&1; }
probe_owner() { "$probe_bin" "$@" 2>&1; }

echo "== preconditions"
uid_host="$(probe_host id)"
uid_in="$(probe_in id)"
ns_host="$(probe_host netns)"
ns_in="$(probe_in netns)"
if [ "$uid_host" != "$agent_uid" ] || [ "$uid_in" != "$agent_uid" ] || [ -z "$ns_in" ] || [ "$ns_in" = "$ns_host" ] || [ "${ns_in#net:}" = "$ns_in" ]; then
  echo "ABORT  the agent does not run as uid $agent_uid inside its own namespace: uid outside '$uid_host', uid inside '$uid_in', net ns outside '$ns_host', inside '$ns_in'"
  echo "       (is the configuration applied, and is agent-netns.service running?) No check was run."
  exit 2
fi
pass "agent runs as uid $agent_uid; its sessions are in $ns_in, not the host's $ns_host"
# The owner's interactive path still works and lands inside. (This runs the
# agent's login profile, so it only reports; nothing below depends on it.)
ns_login="$(sudo --user="$agent" --login -- readlink /proc/self/ns/net </dev/null 2>&1)"
if [ "$ns_login" = "$ns_in" ]; then pass "sudo -u $agent -i lands in the agent namespace ($ns_login)"
else fail "sudo -u $agent -i landed in '$ns_login', not the agent namespace $ns_in"; fi

echo "== OS identity"
groups_of_agent="$(id -nG "$agent")"
bad=""
for g in wheel docker podman onepassword onepassword-cli networkmanager input uinput tss libvirtd incus-admin "$owner" users; do
  case " $groups_of_agent " in *" $g "*) bad="$bad $g" ;; esac
done
if [ -z "$bad" ]; then pass "agent groups: $groups_of_agent"; else fail "agent is in privileged/owner groups:$bad (all: $groups_of_agent)"; fi

out="$(sudo -n -l -U "$agent" 2>&1)"
if printf '%s' "$out" | grep -q "is not allowed to run sudo"; then pass "agent cannot sudo: $(printf '%s' "$out" | tail -n1)"
else fail "agent has sudo rights: $(printf '%s' "$out" | tail -n3 | tr '\n' ' ')"; fi

# sudo as the agent: only the login shell, agent-enter and the probe tool.
out_bash="$(sudo -n -l -u "$agent" /run/current-system/sw/bin/bash 2>&1)"; rc_bash=$?
out_probe="$(sudo -n -l -u "$agent" "$probe_bin" id 2>&1)"; rc_probe=$?
if [ "$rc_probe" -ne 0 ]; then norun "sudo -l for the probe tool failed (control): $out_probe"
elif [ "$rc_bash" -ne 0 ] && [ -z "$out_bash" ]; then pass "sudo refuses '-u $agent bash' (only the login shell, agent-enter and the probe tool are allowed)"
else fail "sudo allows '-u $agent bash' outside the namespace: $out_bash"; fi

um="$(systemctl is-enabled "user@$agent_uid.service" 2>&1)"
ua="$(systemctl is-active "user@$agent_uid.service" 2>&1)"
if [ "$um" = "masked" ] && [ "$ua" != "active" ]; then pass "no systemd user manager for $agent (user@$agent_uid.service masked, $ua)"
else fail "user@$agent_uid.service is '$um'/'$ua': a user manager would start agent processes outside the namespace"; fi

for f in /etc/subuid /etc/subgid; do
  if [ ! -r "$f" ]; then norun "$f is not readable"
  elif grep -qE "^($agent|$agent_uid):" "$f"; then fail "$f has a range for $agent: $(grep -E "^($agent|$agent_uid):" "$f")"
  else pass "$f has no range for $agent"; fi
done

echo "== owner credentials are unreachable from the agent"
check_denied() {
  local where="$1" path="$2" r
  r="$("probe_$where" access "$path")"
  case "$r" in
    EACCES) pass "agent ($where namespace) gets EACCES on $path" ;;
    READABLE) fail "agent ($where namespace) can read $path" ;;
    *) norun "agent ($where namespace) on $path: $r" ;;
  esac
}
for where in in host; do
  check_denied "$where" "$owner_home"
  check_denied "$where" "/run/user/$owner_uid"
done
# Every owner-owned file outside the home under /etc.
while IFS= read -r f; do
  check_denied host "$f"
done < <(find /etc -xdev -user "$owner" -type f 2>/dev/null)
for sock in /run/docker.sock /run/podman/podman.sock; do
  r="$(probe_host unix "$sock")"
  case "$r" in
    EACCES) pass "agent gets EACCES on $sock" ;;
    NOENT) norun "$sock does not exist" ;;
    CONNECTED) fail "agent can connect to $sock (root-equivalent)" ;;
    *) norun "agent on $sock: $r" ;;
  esac
done

echo "== tailscaled LocalAPI"
ts_sock=/run/tailscale/tailscaled.sock
r_owner="$(probe_owner unix "$ts_sock")"
if [ "$r_owner" != "CONNECTED" ]; then
  norun "the owner cannot connect to $ts_sock either ($r_owner): no positive control"
else
  for where in in host; do
    r="$("probe_$where" unix "$ts_sock")"
    case "$r" in
      EACCES) pass "agent ($where namespace) gets EACCES on $ts_sock (owner: CONNECTED)" ;;
      CONNECTED) fail "agent ($where namespace) can connect to $ts_sock: tailscaled would dial the tailnet for it" ;;
      *) norun "agent ($where namespace) on $ts_sock: $r" ;;
    esac
  done
  acl="$(getfacl -p /run/tailscale 2>/dev/null | grep -E "^user:($agent|$agent_uid):")"
  if [ "$acl" = "user:$agent:---" ] || [ "$acl" = "user:$agent_uid:---" ]; then pass "/run/tailscale ACL: $acl"; else fail "/run/tailscale has no '---' ACL entry for $agent (found: '${acl:-none}')"; fi
fi

echo "== sshd"
sshd_cfg="$(sudo sshd -T -C "user=$agent,host=localhost,addr=127.0.0.1" -f /etc/ssh/sshd_config 2>&1)"
if [ -z "$sshd_cfg" ] || ! printf '%s' "$sshd_cfg" | grep -q '^port '; then
  norun "sshd -T could not evaluate the effective config: $(printf '%s' "$sshd_cfg" | tail -n1)"
elif printf '%s' "$sshd_cfg" | grep -qiE "^denyusers( .*)? $agent( |$)"; then
  pass "sshd denies $agent (DenyUsers)"
elif printf '%s' "$sshd_cfg" | grep -qx 'authorizedkeysfile /etc/ssh/authorized_keys.d/%u' \
  && printf '%s' "$sshd_cfg" | grep -qx 'allowtcpforwarding no' \
  && printf '%s' "$sshd_cfg" | grep -qx 'allowstreamlocalforwarding no'; then
  pass "sshd allows $agent only with root-owned keys and no forwarding"
else
  fail "sshd lets $agent log in with: $(printf '%s' "$sshd_cfg" | grep -E '^(denyusers|authorizedkeysfile|allowtcpforwarding|allowstreamlocalforwarding) ' | tr '\n' ';')"
fi
unit="$(systemctl cat 'sshd-unix-local@.service' 2>/dev/null | grep -m1 '^ExecStart=')"
if [ -z "$unit" ]; then pass "no AF_UNIX sshd instance on this host"
elif printf '%s' "$unit" | grep -q -- '-f /etc/ssh/sshd_config'; then pass "AF_UNIX sshd instance uses /etc/ssh/sshd_config (same rules)"
else fail "AF_UNIX sshd instance uses another config: $unit"; fi

echo "== nftables"
table="$(sudo nft list table inet agent-identity 2>&1)"
if ! printf '%s' "$table" | grep -q 'chain agent_out'; then
  fail "table inet agent-identity is not loaded: $(printf '%s' "$table" | tail -n1)"
else
  hook_rules="$(printf '%s\n' "$table" | sed -n '/chain output {/,/}/p' | grep -vE 'chain output|type filter|^\s*}|^\s*$')"
  if [ "$(printf '%s\n' "$hook_rules" | sed 's/^\s*//')" = "meta skuid $agent_uid jump agent_out" ] \
    || [ "$(printf '%s\n' "$hook_rules" | sed 's/^\s*//')" = "meta skuid $agent jump agent_out" ]; then
    pass "table inet agent-identity loaded; its hook matches only uid $agent_uid"
  else
    fail "the hooked chain of inet agent-identity is not exactly 'meta skuid $agent_uid jump agent_out': $hook_rules"
  fi
fi

echo "== GitHub identity"
gh_ok=1
token="$(as_agent "$token_bin" token 2>"${TMPDIR:-/tmp}/.aiv-token.err")"; rc=$?
token_err="$(cat "${TMPDIR:-/tmp}/.aiv-token.err" 2>/dev/null)"; rm -f "${TMPDIR:-/tmp}/.aiv-token.err"
if [ "$rc" -ne 0 ] || [ -z "$token" ]; then
  norun "agent-author-token cannot obtain a token, GitHub checks not run: $token_err"; gh_ok=0; token=""
else
  pass "agent-author-token returned an installation token"
fi
# GitHub calls are made by THIS script (the owner) with the agent's token:
# nothing of the agent's is executed for them.
gh_call() { # gh_call <method> <path> [json body] -> prints "<http code> <body>"
  local body code
  body="$(mktemp)"
  if [ "$1" = POST ]; then
    code="$("$curl_bin" -q -sS -o "$body" -w '%{http_code}' -X POST --data "$3" \
      -H @<(printf 'Authorization: Bearer %s\nAccept: application/vnd.github+json\n' "$token") "https://api.github.com/$2")"
  else
    code="$("$curl_bin" -q -sS -o "$body" -w '%{http_code}' \
      -H @<(printf 'Authorization: Bearer %s\nAccept: application/vnd.github+json\n' "$token") "https://api.github.com/$2")"
  fi
  printf '%s %s' "$code" "$(cat "$body")"; rm -f "$body"
}
if [ "$gh_ok" -eq 1 ]; then
  # shellcheck disable=SC2086 # word splitting of the repository list is intended
  expected_repos="$(printf '%s\n' $allowed_repos | sort | paste -sd, -)"
  r="$(gh_call GET 'installation/repositories?per_page=100')"
  repos="$(printf '%s' "${r#* }" | jq -r '[.repositories[].full_name] | sort | join(",")' 2>/dev/null)"
  if [ "${r%% *}" = 200 ] && [ "$repos" = "$expected_repos" ]; then pass "token reaches exactly: $repos"
  elif [ "${r%% *}" = 200 ]; then fail "token reaches '$repos', expected '$expected_repos'"
  else norun "installation/repositories: HTTP ${r%% *}"; fi
  r="$(gh_call POST graphql '{"query":"{viewer{login}}"}')"
  viewer="$(printf '%s' "${r#* }" | jq -r '.data.viewer.login // empty' 2>/dev/null)"
  if [ "$viewer" = "$bot_login" ]; then pass "GitHub viewer is $viewer"; else fail "GitHub viewer is '$viewer' (HTTP ${r%% *}), expected '$bot_login'"; fi
  for ep in orgs/PittampalliOrg/actions/permissions repos/PittampalliOrg/stacks/hooks; do
    r="$(gh_call GET "$ep")"
    case "${r%% *}" in
      403) pass "admin read $ep refused: HTTP 403 $(printf '%s' "${r#* }" | jq -r '.message // empty' 2>/dev/null)" ;;
      2*) fail "admin read $ep succeeded (HTTP ${r%% *})" ;;
      *) norun "admin read $ep: HTTP ${r%% *}, not 403" ;;
    esac
  done
fi
token=""
out="$(as_agent "$agent_gh" auth login --with-token 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then fail "gh auth login was allowed for the agent"
elif printf '%s' "$out" | grep -q 'is disabled'; then pass "the agent's gh wrapper refuses gh auth login"
else norun "gh auth login failed for another reason: $out"; fi
name_email="$(git config --file "$git_config" --get user.name) <$(git config --file "$git_config" --get user.email)>"
if [ "$name_email" = "$bot_login <$bot_email>" ]; then pass "declared git identity: $name_email"; else fail "declared git identity is '$name_email', expected '$bot_login <$bot_email>'"; fi
live="$(as_agent /run/current-system/sw/bin/readlink -f /home/"$agent"/.config/git/config 2>&1)"
if [ "$live" = "$(readlink -f "$git_config")" ]; then pass "the agent's ~/.config/git/config is the declared one"
else fail "the agent's ~/.config/git/config is '$live', not the declared $git_config (changed by the agent?)"; fi

echo "== GitHub pushes"
if [ "$push" -eq 0 ]; then
  norun "push probes skipped (--no-push)"
elif [ "$gh_ok" -eq 0 ]; then
  norun "push probes: no token"
else
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  probe="$(cat <<EOF
set -u
export GIT_CONFIG_GLOBAL=$git_config GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
git() { $git_bin "\$@"; }
d="\$(mktemp -d /tmp/agent-identity-verify.XXXXXX)"
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
  echo "RESULT other-repo-refused \$(grep -m1 'refusing credentials' other.err)"
fi
EOF
)"
  results="$(as_agent "$bash_bin" -c "$probe" 2>&1)"
  line() { grep -m1 "RESULT $1" <<<"$results" | cut -d' ' -f2-; }
  case "$(line plain)" in
    plain-pushed*) pass "push to a scratch branch on PittampalliOrg/stacks works" ;;
    *) fail "push to a scratch branch: $(line plain) $(line fetch)" ;;
  esac
  case "$results" in *"RESULT plain-NOT-deleted"*) fail "scratch branch agent-identity-verify/$ts-plain was NOT deleted; delete it by hand" ;; esac
  wf="$(line workflow)"
  case "$wf" in
    workflow-refused*) if printf '%s' "$wf" | grep -qiE 'permission|scope'; then pass "push touching .github/workflows/ refused: ${wf#workflow-refused }"; else norun "workflow push failed without a permission refusal: $wf"; fi ;;
    workflow-pushed*) fail "push touching .github/workflows/ was NOT refused" ;;
    *) norun "workflow push probe did not run: $wf" ;;
  esac
  other="$(line other-repo)"
  case "$other" in
    *"refusing credentials"*) pass "push to a repository outside the two is refused by the credential helper" ;;
    other-repo-allowed*) fail "push to $owner/nixos-config was allowed" ;;
    *) norun "other-repository push failed without the helper's refusal: $other" ;;
  esac
fi

echo "== Kubernetes (read-only)"
kubeconfig="$state_dir/kubeconfig"
kc() { as_agent "$kubectl_bin" --kubeconfig "$kubeconfig" --cache-dir /tmp/agent-identity-verify-kube "$@"; }
contexts="$(kubectl --kubeconfig "$kubeconfig" config get-contexts -o name 2>&1 | sort | paste -sd, -)"
extra="$(printf '%s\n' "${contexts//,/$'\n'}" | grep -vxE 'dev|hub' || true)"
if [ -z "$extra" ]; then pass "agent kube contexts: $contexts"; else fail "agent kubeconfig has other contexts: $extra"; fi
can_i() {
  local ctx="$1" want="$2" a
  shift 2
  a="$(kc --context "$ctx" auth can-i "$@" 2>&1)"
  if [ "$a" = "$want" ]; then pass "$ctx: can-i $* -> $a"
  elif [ "$a" = "yes" ] || [ "$a" = "no" ]; then fail "$ctx: can-i $* -> $a, expected $want"
  else norun "$ctx: can-i $*: $a"; fi
}
check_kube() {
  local ctx="$1" sa="$2" who
  who="$(kc --context "$ctx" auth whoami -o jsonpath='{.status.userInfo.username}' 2>&1)"
  if [ "$who" != "system:serviceaccount:agent-identity:$sa" ]; then
    case "$who" in system:*|admin*|kubernetes-admin*) fail "$ctx: whoami '$who', expected system:serviceaccount:agent-identity:$sa" ;; *) norun "$ctx: cannot authenticate: $who" ;; esac
    return
  fi
  pass "$ctx: whoami $who"
  can_i "$ctx" no create pods -A
  can_i "$ctx" no list secrets -A
  can_i "$ctx" no '*' '*' -A
  can_i "$ctx" yes get pods -A
}
if [ -s "$state_dir/dev-server" ]; then check_kube dev local-minter; else norun "dev not provisioned ($state_dir/dev-server missing): agent-identity-provision dev"; fi
if [ -s "$state_dir/hub-server" ]; then check_kube hub local-viewer; else norun "hub not provisioned (needs the stacks hub ServiceAccount; then agent-identity-provision hub)"; fi
mode="$(stat -c '%a %U' "$state_dir/dev-local-minter.token" 2>&1)"
if [ "$mode" = "600 $agent" ]; then pass "bound token file mode: $mode"; else fail "bound token file $state_dir/dev-local-minter.token is '$mode', expected '600 $agent'"; fi

echo "== network boundary"
code="$(as_agent "$curl_bin" -q -s -o /dev/null -m 10 -w '%{http_code}' https://api.github.com/zen 2>&1)"
if [ "$code" = "200" ]; then pass "agent namespace reaches the internet (api.github.com $code)"; else fail "agent namespace cannot reach api.github.com ($code)"; fi
if as_agent "$py_bin" -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));s.listen();socket.create_connection(s.getsockname(),timeout=3)' 2>/dev/null; then
  pass "agent namespace has its own working loopback"
else
  fail "agent namespace loopback does not work"
fi

# Host loopback listeners, from inside the namespace: its own lo has none.
listeners="$(ss -ltnH | awk '{print $4}' | grep -E '^(127\.|\[::1\])' | sort -u)"
n=0; bad=""; odd=""
while read -r addr; do
  [ -n "$addr" ] || continue
  host="${addr%:*}"; port="${addr##*:}"; host="${host#[}"; host="${host%]}"
  n=$((n + 1))
  r="$(probe_in tcp "$host" "$port")"
  case "$r" in REFUSED) ;; CONNECTED) bad="$bad $addr" ;; *) odd="$odd $addr=$r" ;; esac
done <<<"$listeners"
if [ "$n" -eq 0 ]; then norun "no host loopback listeners to probe"
elif [ -n "$bad" ]; then fail "agent namespace reached host loopback listeners:$bad"
elif [ -n "$odd" ]; then norun "host loopback probes without a clear refusal:$odd"
else pass "all $n host loopback listeners: connection refused inside the agent namespace"; fi

# The same, outside the namespace: the nftables table must refuse.
first="$(printf '%s\n' "$listeners" | head -n1)"
if [ -n "$first" ]; then
  host="${first%:*}"; port="${first##*:}"; host="${host#[}"; host="${host%]}"
  ro="$(probe_owner tcp "$host" "$port")"; ra="$(probe_host tcp "$host" "$port")"
  if [ "$ro" != "CONNECTED" ]; then norun "host loopback control: the owner gets $ro on $first"
  elif [ "$ra" = "REFUSED" ]; then pass "outside the namespace the agent uid is refused on host loopback $first (owner: CONNECTED)"
  elif [ "$ra" = "CONNECTED" ]; then fail "outside the namespace the agent uid reaches host loopback $first"
  else norun "outside the namespace, host loopback $first: $ra"; fi
fi

# Tailnet.
tprobe="${AGENT_IDENTITY_TAILNET_PROBE:-}"
if [ -z "$tprobe" ]; then
  thost="$(kubectl config view -o jsonpath='{range .clusters[*]}{.cluster.server}{"\n"}{end}' 2>/dev/null | sed -n 's#^https://\([^/:]*\.ts\.net\).*#\1#p' | head -n1)"
  [ -n "$thost" ] && tprobe="$thost:443"
fi
if [ -z "$tprobe" ]; then
  norun "no tailnet probe target (set AGENT_IDENTITY_TAILNET_PROBE=host:port)"
else
  th="${tprobe%:*}"; tp="${tprobe##*:}"
  ro="$(probe_owner tcp "$th" "$tp")"
  if [ "$ro" != "CONNECTED" ]; then norun "tailnet control: the owner gets $ro on the probe target"
  else
    for where in in host; do
      r="$("probe_$where" tcp "$th" "$tp")"
      case "$r" in
        REFUSED|EHOSTUNREACH|ENETUNREACH) pass "agent ($where namespace) refused on the tailnet probe target ($r; owner: CONNECTED)" ;;
        CONNECTED) fail "agent ($where namespace) reached the tailnet probe target" ;;
        *) norun "agent ($where namespace) on the tailnet probe target: $r" ;;
      esac
    done
  fi
fi

# Containers: a container address and port the owner can reach.
cprobe=""
if command -v docker >/dev/null 2>&1; then
  for c in $(docker ps -q 2>/dev/null); do
    ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$c" 2>/dev/null | awk '{print $1}')"
    port="$(docker inspect -f '{{range $p, $_ := .NetworkSettings.Ports}}{{$p}} {{end}}' "$c" 2>/dev/null | tr ' ' '\n' | grep '/tcp$' | head -n1 | cut -d/ -f1)"
    if [ -n "$ip" ] && [ -n "$port" ] && [ "$(probe_owner tcp "$ip" "$port")" = "CONNECTED" ]; then cprobe="$ip $port"; break; fi
  done
fi
if [ -z "$cprobe" ]; then
  norun "no running container with a reachable TCP port to probe"
else
  for where in in host; do
    # shellcheck disable=SC2086 # "ip port"
    r="$("probe_$where" tcp $cprobe)"
    case "$r" in
      REFUSED|EHOSTUNREACH|ENETUNREACH) pass "agent ($where namespace) refused on a container address ($r; owner: CONNECTED)" ;;
      CONNECTED) fail "agent ($where namespace) reached a container address" ;;
      *) norun "agent ($where namespace) on a container address: $r" ;;
    esac
  done
fi

# Host abstract unix sockets are scoped to the host network namespace.
abstract="$(ss -xlH 2>/dev/null | awk '{print $5}' | grep '^@' | sed 's/^@//' | sort -u)"
n=0; bad=""; odd=""
while read -r name; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  r="$(probe_in abstract "$name")"
  case "$r" in REFUSED) ;; CONNECTED) bad="$bad @$name" ;; *) odd="$odd @$name=$r" ;; esac
done <<<"$abstract"
if [ "$n" -eq 0 ]; then norun "no host abstract sockets to probe"
elif [ -n "$bad" ]; then fail "agent namespace reached host abstract sockets:$bad"
elif [ -n "$odd" ]; then norun "abstract socket probes without a clear refusal:$odd"
else pass "all $n host abstract sockets: connection refused inside the agent namespace"; fi

echo "== private /tmp"
marker="$(mktemp /tmp/agent-identity-verify.XXXXXX)"
chmod 0644 "$marker"
out="$(as_agent "$ls_bin" -- "$marker" 2>&1)"; rc=$?
rm -f "$marker"
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'No such file'; then pass "the agent namespace has a private /tmp (owner's marker absent)"
elif [ "$rc" -eq 0 ]; then fail "the agent namespace sees the host /tmp"
else norun "private /tmp check: $out"; fi
# umount2(2) directly: util-linux umount(8) reports a locked mount's EINVAL as "not mounted".
out="$(as_agent "$unshare_bin" --user --map-root-user --mount "$py_bin" -I -c 'import ctypes,os;l=ctypes.CDLL(None,use_errno=True);r=l.umount2(b"/tmp",2);print("UNMOUNTED" if r==0 else os.strerror(ctypes.get_errno()))' 2>&1)"
if [ "$out" = "UNMOUNTED" ]; then fail "the agent can unmount its private /tmp (it is not locked)"
elif [ "$out" = "Invalid argument" ]; then pass "the private /tmp is locked (umount2: EINVAL)"
else norun "unmount probe: $out"; fi

echo "== agent processes in the host network namespace"
# Only pasta (agent-netns.service's main process) may run as the agent in
# the host network namespace.
pasta_pid="$(systemctl show --property=MainPID --value agent-netns.service)"
procs="$(sudo /run/current-system/sw/bin/sh -c 'h=$(readlink /proc/1/ns/net); for p in $(pgrep -u '"$agent_uid"'); do n=$(readlink /proc/$p/ns/net 2>/dev/null) || continue; [ "$n" = "$h" ] && echo "$p $(cat /proc/$p/comm 2>/dev/null)"; done' 2>&1)"
others="$(printf '%s\n' "$procs" | awk -v m="$pasta_pid" 'NF && $1 != m')"
if [ -z "$pasta_pid" ] || [ "$pasta_pid" = 0 ]; then norun "agent-netns.service has no main process"
elif [ -z "$others" ]; then pass "no uid-$agent_uid process in the host network namespace except pasta ($pasta_pid)"
else fail "uid-$agent_uid processes in the host network namespace: $(printf '%s' "$others" | tr '\n' ';')"; fi

echo
echo "agent-identity-verify: $fails FAIL, $noruns NORUN"
exit $((fails + noruns))
