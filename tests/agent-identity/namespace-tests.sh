#!/usr/bin/env bash
# Scratch-namespace tests for services.agentIdentity. Run as the OWNER, no
# root, no host change: everything happens inside a user+net+mount namespace
# mapped onto the owner's subordinate uids (needs newuidmap and an
# /etc/subuid range for the caller). Inside, uid 2001 plays the agent and
# uid 1000 / uid 0 play other users.
#
#   tests/agent-identity/namespace-tests.sh [rules.nft]
#
# Without an argument the ruleset is built from this checkout, with the
# module enabled on ryzen (it is off by default on every host).
#
# Covers: the nftables table affects ONLY uid 2001 (other uids get immediate
# refusals, ping replies, no sockets stuck after close); uid 2001 is refused on
# loopback, tailnet, container bridges and DNAT'd ports; a 0666 socket in a
# directory with an ACL entry `u:2001:---` refuses uid 2001 and the entry is
# gone when the directory is recreated (why tailscaled re-applies it in
# ExecStartPre); abstract sockets are scoped by network namespace; a /tmp
# mounted by a more privileged namespace is locked for the agent.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
rules="${1:-}"
if [ -z "$rules" ]; then
  rules="$(nix build --no-link --print-out-paths --impure --expr "
    let f = builtins.getFlake (toString $here/../..);
        c = f.nixosConfigurations.ryzen.extendModules {
          modules = [ { services.agentIdentity.enable = f.inputs.nixpkgs.lib.mkForce true; } ];
        };
    in c.config.system.build.agentIdentityNftRules")"
fi
nft="$(nix build --no-link --print-out-paths nixpkgs#nftables)/bin/nft"
setfacl="$(nix build --no-link --print-out-paths nixpkgs#acl.bin)/bin/setfacl"
py="$(command -v python3)"

inner="$(cat <<'INNER'
set -u
fails=0
ok() { printf 'PASS  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
expect() { # expect <label> <wanted regex> <observed>
  if printf '%s' "$3" | grep -qE "^($2)"; then ok "$1: $3"; else bad "$1: $3 (wanted $2)"; fi
}
as() { local u="$1"; shift; setpriv --reuid "$u" --regid "$u" --clear-groups "$@"; }

R_TXT="$(cat "$RULES")"
mount -t tmpfs -o mode=1777 none /tmp
cd /tmp
printf '%s\n' "$R_TXT" >rules.nft
cat >probe.py <<'PY'
import socket, sys, time, errno
t = sys.argv[1]; start = time.time()
try:
    if t.startswith("unix:") or t.startswith("abstract:"):
        s = socket.socket(socket.AF_UNIX); s.settimeout(4)
        s.connect(t[5:] if t.startswith("unix:") else "\0" + t[9:])
    else:
        s = socket.create_connection((t, int(sys.argv[2])), timeout=4)
    s.close(); r = "CONNECTED"
except socket.timeout: r = "TIMEOUT"
except OSError as e:
    r = {errno.ECONNREFUSED: "REFUSED", errno.EACCES: "EACCES"}.get(e.errno, errno.errorcode.get(e.errno, str(e.errno)))
print(f"{r} {time.time()-start:.2f}s")
PY
cat >serve.py <<'PY'
import socket, sys, os
t = sys.argv[1]
if t.startswith("tcp:"):
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", int(t[4:])))
else:
    s = socket.socket(socket.AF_UNIX)
    s.bind(t[5:] if t.startswith("unix:") else "\0" + t[9:])
    if t.startswith("unix:"): os.chmod(t[5:], 0o666)
s.listen(); s.settimeout(float(sys.argv[2]))
while True:
    try:
        c, _ = s.accept()
    except Exception:
        break
    try:
        c.sendall(b"x"); c.close()
    except Exception:
        pass
PY
chmod 0644 probe.py serve.py rules.nft
P="$PY probe.py"

ip link set lo up
echo "0 65535" >/proc/sys/net/ipv4/ping_group_range
ip link add docker0 type dummy; ip addr add 172.17.0.1/16 dev docker0; ip link set docker0 up
ip link add br-test type dummy; ip addr add 172.18.0.1/16 dev br-test; ip link set br-test up
ip link add tailscale0 type dummy; ip addr add 100.70.0.1/32 dev tailscale0; ip link set tailscale0 up
ip route add 100.64.0.0/10 dev tailscale0
ip link add eth0 type dummy; ip addr add 198.51.100.1/24 dev eth0; ip link set eth0 up
ip route add 203.0.113.0/24 dev eth0
"$NFT" -f - <<'NAT'
table ip nat {
  chain output {
    type nat hook output priority -100; policy accept;
    ip daddr 203.0.113.5 tcp dport 80 dnat to 198.51.100.7:80
  }
}
NAT
"$NFT" -f rules.nft || { echo "FAIL  ruleset did not load"; exit 1; }

echo "== other uids are untouched"
for u in 0 1000; do
  expect "uid $u closed port 127.0.0.1:9 refused at once" 'REFUSED 0\.[0-4]' "$(as "$u" $P 127.0.0.1 9)"
  if as "$u" ping -c1 -W3 127.0.0.1 >/dev/null 2>&1; then ok "uid $u ping 127.0.0.1: reply"; else bad "uid $u ping 127.0.0.1: no reply"; fi
  as "$u" $PY serve.py tcp:8090 3 & sleep 0.3
  for _ in 1 2 3; do as "$u" $PY -c 'import socket;s=socket.create_connection(("127.0.0.1",8090),timeout=3);s.recv(1);s.close()' || true; done
  sleep 1.5
  stuck="$(ss -tanH state last-ack state fin-wait-1 state closing | wc -l)"
  if [ "$stuck" = 0 ]; then ok "uid $u: no socket stuck in FIN-WAIT-1/LAST-ACK/CLOSING after close"; else bad "uid $u: $stuck sockets stuck after close"; fi
  wait
done

echo "== uid 2001 (agent) is refused"
as 1000 $PY serve.py tcp:8091 30 & sleep 0.3
expect "control: uid 1000 to its own 127.0.0.1:8091" 'CONNECTED' "$(as 1000 $P 127.0.0.1 8091)"
expect "agent to another user's 127.0.0.1:8091" 'REFUSED' "$(as 2001 $P 127.0.0.1 8091)"
expect "agent to a host address (198.51.100.1, via lo)" 'REFUSED' "$(as 2001 $P 198.51.100.1 8091)"
expect "agent to the tailnet (100.70.0.9)" 'REFUSED' "$(as 2001 $P 100.70.0.9 443)"
expect "agent to docker0 (172.17.0.2)" 'REFUSED' "$(as 2001 $P 172.17.0.2 6379)"
expect "agent to br-* (172.18.0.2)" 'REFUSED' "$(as 2001 $P 172.18.0.2 5432)"
expect "agent to a DNAT'd port (203.0.113.5:80)" 'REFUSED' "$(as 2001 $P 203.0.113.5 80)"
expect "control: agent to an unblocked address (198.51.100.7, dummy link) is not refused" 'TIMEOUT' "$(as 2001 $P 198.51.100.7 80)"
counters="$("$NFT" list chain inet agent-identity agent_out)"
for rule in 'ct status dnat' 'oifname "tailscale0"' 'oifname "lo"' 'oifname "docker0"' 'oifname "br-\*"'; do
  if printf '%s\n' "$counters" | grep -E "$rule" | grep -qE 'counter packets [1-9]'; then ok "rule hit: $rule"; else bad "rule not hit: $rule"; fi
done

echo "== tailscaled-style socket: ACL u:2001:--- on its directory"
mkdir -m 0755 /tmp/ts
$PY serve.py unix:/tmp/ts/sock 30 & sleep 0.3
expect "before the ACL, agent to the 0666 socket" 'CONNECTED' "$(as 2001 $P unix:/tmp/ts/sock)"
"$SETFACL" -m u:2001:--- /tmp/ts
expect "with the ACL, agent" 'EACCES' "$(as 2001 $P unix:/tmp/ts/sock)"
expect "with the ACL, uid 1000" 'CONNECTED' "$(as 1000 $P unix:/tmp/ts/sock)"
kill %% 2>/dev/null; wait 2>/dev/null
rm -rf /tmp/ts; mkdir -m 0755 /tmp/ts
$PY serve.py unix:/tmp/ts/sock 30 & sleep 0.3
expect "directory recreated (service restart) without re-applying: agent" 'CONNECTED' "$(as 2001 $P unix:/tmp/ts/sock)"
"$SETFACL" -m u:2001:--- /tmp/ts
expect "re-applied (ExecStartPre on every start): agent" 'EACCES' "$(as 2001 $P unix:/tmp/ts/sock)"

echo "== abstract sockets are per network namespace"
as 1000 $PY serve.py abstract:agentid-test 30 & sleep 0.3
expect "agent in the same network namespace (the residual for processes outside agent-netns)" 'CONNECTED' "$(as 2001 $P abstract:agentid-test)"
expect "agent inside its own network namespace" 'REFUSED' "$(as 2001 unshare --user --map-current-user --net $P abstract:agentid-test)"

echo "== /tmp mounted by a more privileged namespace is locked for the agent"
# umount2(2) with MNT_DETACH: a locked mount answers EINVAL (util-linux
# umount(8) prints that as "not mounted"), so call it directly.
UMOUNT='import ctypes,os;l=ctypes.CDLL(None,use_errno=True);r=l.umount2(b"/tmp",2);print("UNMOUNTED" if r==0 else os.strerror(ctypes.get_errno()))'
out="$(as 2001 unshare --user --map-root-user --mount $PY -c "$UMOUNT")"
expect "agent (own user+mount namespace) unmounting /tmp" 'Invalid argument' "$out"
out="$(unshare --mount $PY -c "$UMOUNT")"
expect "control: the namespace that mounted it can unmount" 'UNMOUNTED' "$out"

echo
echo "namespace-tests: $fails failure(s)"
exit "$fails"
INNER
)"

exec unshare --map-auto --map-root-user --net --mount \
  env RULES="$rules" NFT="$nft" SETFACL="$setfacl" PY="$py" bash -c "$inner"
