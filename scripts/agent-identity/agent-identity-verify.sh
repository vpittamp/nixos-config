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
# A refusal is never inferred from "the command failed". The run aborts
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
py="$(command -v python3)"

# Inside the agent namespace: the login shell enters it.
as_agent() { sudo --user="$agent" --login -- "$@" </dev/null; }
# Outside it, deliberately (no login shell): proves the host-side layers.
as_agent_host() { sudo --user="$agent" -- "$@" </dev/null; }

# probe <host> <port> | probe unix:<path> | probe abstract:<name>
# prints CONNECTED | REFUSED | EACCES | TIMEOUT | NOENT | OTHER:<errno name>
probe_src='
import socket, sys, errno
t = sys.argv[1]
try:
    if t.startswith("unix:") or t.startswith("abstract:"):
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(4)
        s.connect(t[5:] if t.startswith("unix:") else "\0" + t[9:])
    else:
        s = socket.create_connection((t, int(sys.argv[2])), timeout=4)
    s.close(); print("CONNECTED")
except socket.timeout: print("TIMEOUT")
except OSError as e:
    print({errno.ECONNREFUSED: "REFUSED", errno.EACCES: "EACCES", errno.EPERM: "EACCES", errno.ENOENT: "NOENT"}.get(e.errno, "OTHER:" + errno.errorcode.get(e.errno, str(e.errno))))
'
# sudo --login re-quotes the command for `shell -c` and turns newlines into
# line continuations, so multi-line programs travel base64-encoded.
probe_line="exec(__import__('base64').b64decode('$(printf '%s' "$probe_src" | base64 -w0)'))"
probe_owner() { "$py" -c "$probe_line" "$@" 2>&1; }
probe_in() { as_agent "$py" -c "$probe_line" "$@" 2>&1; }
probe_host() { as_agent_host "$py" -c "$probe_line" "$@" 2>&1; }

echo "== preconditions"
uid_host="$(as_agent_host id -u 2>&1)"
uid_in="$(as_agent id -u 2>&1)"
ns_host="$(as_agent_host readlink /proc/self/ns/net 2>&1)"
ns_in="$(as_agent readlink /proc/self/ns/net 2>&1)"
if [ "$uid_host" != "$agent_uid" ] || [ "$uid_in" != "$agent_uid" ] || [ -z "$ns_in" ] || [ "$ns_in" = "$ns_host" ] || [ "${ns_in#net:}" = "$ns_in" ]; then
  echo "ABORT  the agent does not run as uid $agent_uid inside its own namespace: uid outside '$uid_host', uid inside '$uid_in', net ns outside '$ns_host', inside '$ns_in'"
  echo "       (is the configuration applied, and is agent-netns.service running?) No check was run."
  exit 2
fi
pass "agent runs as uid $agent_uid; its sessions are in $ns_in, not the host's $ns_host"

echo "== OS identity"
groups_of_agent="$(id -nG "$agent")"
bad=""
for g in wheel docker podman onepassword onepassword-cli networkmanager input uinput tss libvirtd incus-admin "$owner" users; do
  case " $groups_of_agent " in *" $g "*) bad="$bad $g" ;; esac
done
if [ -z "$bad" ]; then pass "agent groups: $groups_of_agent"; else fail "agent is in privileged/owner groups:$bad (all: $groups_of_agent)"; fi

out="$(as_agent_host sudo -n true 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then fail "agent can run sudo without a password"
elif printf '%s' "$out" | grep -qiE 'password is required|not allowed|may not run sudo|not in the sudoers'; then pass "agent cannot sudo: $(printf '%s' "$out" | tail -n1)"
else norun "sudo as the agent failed without a sudo refusal: $out"; fi

for f in /etc/subuid /etc/subgid; do
  if [ ! -r "$f" ]; then norun "$f is not readable"
  elif grep -qE "^($agent|$agent_uid):" "$f"; then fail "$f has a range for $agent: $(grep -E "^($agent|$agent_uid):" "$f")"
  else pass "$f has no range for $agent"; fi
done

echo "== owner credentials are unreachable from the agent"
check_denied() {
  local where="$1" path="$2" out rc
  if [ -d "$path" ]; then
    out="$("as_agent$where" ls -- "$path" 2>&1 >/dev/null)"; rc=$?
  else
    out="$("as_agent$where" head -c 0 -- "$path" 2>&1)"; rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then fail "agent${where:+ (outside the namespace)} can read $path"
  elif printf '%s' "$out" | grep -q 'Permission denied'; then pass "agent${where:+ (outside)} gets Permission denied on $path"
  else norun "agent${where:+ (outside)} on $path: not a permission refusal: $out"; fi
}
for where in "" "_host"; do
  check_denied "$where" "$owner_home"
  check_denied "$where" "/run/user/$owner_uid"
done
# Every owner-owned file outside the home under /etc.
while IFS= read -r f; do
  check_denied "_host" "$f"
done < <(find /etc -xdev -user "$owner" -type f 2>/dev/null)
for sock in /run/docker.sock /run/podman/podman.sock; do
  r="$(probe_host "unix:$sock")"
  case "$r" in
    EACCES) pass "agent gets EACCES on $sock" ;;
    NOENT) norun "$sock does not exist" ;;
    CONNECTED) fail "agent can connect to $sock (root-equivalent)" ;;
    *) norun "agent on $sock: $r" ;;
  esac
done

echo "== tailscaled LocalAPI"
ts_sock=/run/tailscale/tailscaled.sock
r_owner="$(probe_owner "unix:$ts_sock")"
if [ "$r_owner" != "CONNECTED" ]; then
  norun "the owner cannot connect to $ts_sock either ($r_owner): no positive control"
else
  for where in in host; do
    r="$("probe_$where" "unix:$ts_sock")"
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
if out="$(as_agent agent-author-token status 2>&1)"; then
  pass "agent-author-token status:"; printf '         %s\n' "${out//$'\n'/$'\n'         }"
else
  norun "agent-author-token cannot obtain a token, GitHub checks not run: $out"; gh_ok=0
fi
if [ "$gh_ok" -eq 1 ]; then
  # shellcheck disable=SC2086 # word splitting of the repository list is intended
  expected_repos="$(printf '%s\n' $allowed_repos | sort | paste -sd, -)"
  repos="$(as_agent gh api /installation/repositories --jq '[.repositories[].full_name] | sort | join(",")' 2>&1)"
  if [ "$repos" = "$expected_repos" ]; then pass "token reaches exactly: $repos"; else fail "token reaches '$repos', expected '$expected_repos'"; fi
  viewer="$(as_agent gh api graphql -f query='{viewer{login}}' --jq .data.viewer.login 2>&1)"
  if [ "$viewer" = "$bot_login" ]; then pass "GitHub viewer is $viewer"; else fail "GitHub viewer is '$viewer', expected '$bot_login'"; fi
  for ep in orgs/PittampalliOrg/actions/permissions repos/PittampalliOrg/stacks/hooks; do
    out="$(as_agent gh api "$ep" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then fail "admin read $ep succeeded"
    elif printf '%s' "$out" | grep -qE 'HTTP 403'; then pass "admin read $ep refused: $(printf '%s' "$out" | tail -n1)"
    else norun "admin read $ep failed without HTTP 403: $(printf '%s' "$out" | tail -n1)"; fi
  done
  out="$(as_agent gh auth login --with-token 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then fail "gh auth login was allowed for the agent"
  elif printf '%s' "$out" | grep -q 'is disabled'; then pass "gh auth login is refused by the wrapper"
  else norun "gh auth login failed for another reason: $out"; fi
fi
name_email="$(as_agent git config --get user.name) <$(as_agent git config --get user.email)>"
if [ "$name_email" = "$bot_login <$bot_email>" ]; then pass "git identity: $name_email"; else fail "git identity is '$name_email', expected '$bot_login <$bot_email>'"; fi

echo "== GitHub pushes"
if [ "$push" -eq 0 ]; then
  norun "push probes skipped (--no-push)"
elif [ "$gh_ok" -eq 0 ]; then
  norun "push probes: no token"
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
  echo "RESULT other-repo-refused \$(grep -m1 'refusing credentials' other.err)"
fi
EOF
)"
  results="$(as_agent bash -c "eval \"\$(printf %s $(printf '%s' "$probe" | base64 -w0) | base64 -d)\"" 2>&1)"
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
contexts="$(as_agent kubectl config get-contexts -o name 2>&1 | sort | paste -sd, -)"
extra="$(printf '%s\n' "${contexts//,/$'\n'}" | grep -vxE 'dev|hub' || true)"
if [ -z "$extra" ]; then pass "agent kube contexts: $contexts"; else fail "agent kubeconfig has other contexts: $extra"; fi
can_i() {
  local ctx="$1" want="$2" a
  shift 2
  a="$(as_agent kubectl --context "$ctx" auth can-i "$@" 2>&1)"
  if [ "$a" = "$want" ]; then pass "$ctx: can-i $* -> $a"
  elif [ "$a" = "yes" ] || [ "$a" = "no" ]; then fail "$ctx: can-i $* -> $a, expected $want"
  else norun "$ctx: can-i $*: $a"; fi
}
check_kube() {
  local ctx="$1" sa="$2" who
  who="$(as_agent kubectl --context "$ctx" auth whoami -o jsonpath='{.status.userInfo.username}' 2>&1)"
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
code="$(as_agent curl -s -o /dev/null -m 10 -w '%{http_code}' https://api.github.com/zen 2>&1)"
if [ "$code" = "200" ]; then pass "agent namespace reaches the internet (api.github.com $code)"; else fail "agent namespace cannot reach api.github.com ($code)"; fi
if as_agent "$py" -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));s.listen();socket.create_connection(s.getsockname(),timeout=3)' 2>/dev/null; then
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
  r="$(probe_in "$host" "$port")"
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
  ro="$(probe_owner "$host" "$port")"; ra="$(probe_host "$host" "$port")"
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
  ro="$(probe_owner "$th" "$tp")"
  if [ "$ro" != "CONNECTED" ]; then norun "tailnet control: the owner gets $ro on the probe target"
  else
    for where in in host; do
      r="$("probe_$where" "$th" "$tp")"
      case "$r" in
        REFUSED|OTHER:EHOSTUNREACH|OTHER:ENETUNREACH) pass "agent ($where namespace) refused on the tailnet probe target ($r; owner: CONNECTED)" ;;
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
    if [ -n "$ip" ] && [ -n "$port" ] && [ "$(probe_owner "$ip" "$port")" = "CONNECTED" ]; then cprobe="$ip $port"; break; fi
  done
fi
if [ -z "$cprobe" ]; then
  norun "no running container with a reachable TCP port to probe"
else
  for where in in host; do
    # shellcheck disable=SC2086 # "ip port"
    r="$("probe_$where" $cprobe)"
    case "$r" in
      REFUSED|OTHER:EHOSTUNREACH|OTHER:ENETUNREACH) pass "agent ($where namespace) refused on a container address ($r; owner: CONNECTED)" ;;
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
  r="$(probe_in "abstract:$name")"
  case "$r" in REFUSED) ;; CONNECTED) bad="$bad @$name" ;; *) odd="$odd @$name=$r" ;; esac
done <<<"$abstract"
if [ "$n" -eq 0 ]; then norun "no host abstract sockets to probe"
elif [ -n "$bad" ]; then fail "agent namespace reached host abstract sockets:$bad"
elif [ -n "$odd" ]; then norun "abstract socket probes without a clear refusal:$odd"
else pass "all $n host abstract sockets: connection refused inside the agent namespace"; fi

echo "== private /tmp"
marker="$(mktemp /tmp/agent-identity-verify.XXXXXX)"
chmod 0644 "$marker"
out="$(as_agent ls -- "$marker" 2>&1)"; rc=$?
rm -f "$marker"
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'No such file'; then pass "the agent namespace has a private /tmp (owner's marker absent)"
elif [ "$rc" -eq 0 ]; then fail "the agent namespace sees the host /tmp"
else norun "private /tmp check: $out"; fi
out="$(as_agent unshare --user --map-root-user --mount sh -c 'umount /tmp && echo UNMOUNTED' 2>&1)"
if printf '%s' "$out" | grep -q UNMOUNTED; then fail "the agent can unmount its private /tmp (it is not locked)"
elif printf '%s' "$out" | grep -qiE 'invalid argument|not permitted'; then pass "the private /tmp is locked: $(printf '%s' "$out" | tail -n1)"
else norun "unmount probe: $out"; fi

echo
echo "agent-identity-verify: $fails FAIL, $noruns NORUN"
exit $((fails + noruns))
