#!/usr/bin/env bash
# A rule change must not restart agent-netns (it would cut running sessions
# off the network), and the iptables-host table must be replaced in one
# atomic nft transaction (never absent). Run as the owner; no root.
#
# 1. Unit graph (evaluation): build each host twice with the module on, the
#    second time with a different ruleset, and check that
#    - agent-netns.service is byte-identical (switch-to-configuration leaves
#      it alone) and carries X-RestartIfChanged=false;
#    - it has no Requires=/BindsTo=/PartOf= on the table's unit (a restart of
#      that unit would propagate);
#    - on iptables hosts the table unit changed and is reloaded, not
#      restarted (X-ReloadIfChanged=true, ExecReload = the transaction).
# 2. Atomicity: in a scratch user+net namespace, apply the transaction file
#    300 times while another process lists the table in a tight loop; count
#    the lookups that found no table. Also measures the old two-step form
#    (delete, then create) for comparison.
#
#   tests/agent-identity/unit-graph-test.sh
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
ok() { printf 'PASS  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

build() { # build <host> <blockTailscaleInterface> <attr path under config>
  nix build --no-link --print-out-paths --impure --expr "
    let f = builtins.getFlake (toString $repo);
        lib = f.inputs.nixpkgs.lib;
        c = f.nixosConfigurations.$1.extendModules { modules = [ {
          services.agentIdentity.enable = lib.mkForce true;
          services.agentIdentity.network.blockTailscaleInterface = $2;
        } ]; };
    in c.config.$3" 2>/dev/null
}

for host in ryzen thinkpad; do
  a="$(build "$host" true 'systemd.units."agent-netns.service".unit')"
  b="$(build "$host" false 'systemd.units."agent-netns.service".unit')"
  unit="$a/agent-netns.service"
  if [ "$a" = "$b" ]; then ok "$host: agent-netns.service is unchanged by a rule change ($a)"; else bad "$host: agent-netns.service changes with the rules ($a vs $b)"; fi
  if grep -qx 'X-RestartIfChanged=false' "$unit"; then ok "$host: agent-netns has X-RestartIfChanged=false"; else bad "$host: agent-netns lacks X-RestartIfChanged=false"; fi
  hard="$(grep -E '^(Requires|BindsTo|PartOf|Requisite)=' "$unit" | grep -E 'agent-identity-netfilter|nftables' || true)"
  if [ -z "$hard" ]; then ok "$host: no Requires/BindsTo/PartOf on the table's unit ($(grep -E '^(Wants|After)=' "$unit" | tr '\n' ' '))"; else bad "$host: hard dependency: $hard"; fi
  if grep -q '^ExecStartPre=+.*nft list table inet agent-identity' "$unit"; then ok "$host: agent-netns refuses to start without the table"; else bad "$host: agent-netns does not check for the table"; fi
done

na="$(build thinkpad true 'systemd.units."agent-identity-netfilter.service".unit')"
nb="$(build thinkpad false 'systemd.units."agent-identity-netfilter.service".unit')"
if [ "$na" != "$nb" ]; then ok "thinkpad: the table unit changes with the rules (so the comparison above is meaningful)"; else bad "thinkpad: the table unit did not change; the rule change was not exercised"; fi
nu="$na/agent-identity-netfilter.service"
if grep -qx 'X-ReloadIfChanged=true' "$nu"; then ok "thinkpad: the table unit is reloaded on change, not restarted"; else bad "thinkpad: the table unit lacks X-ReloadIfChanged=true"; fi
tx="$(build thinkpad true 'system.build.agentIdentityNftTransaction')"
if grep -q "^ExecReload=.*nft -f $tx" "$nu" && grep -q "^ExecStart=.*nft -f $tx" "$nu"; then ok "thinkpad: start and reload apply the single transaction file"; else bad "thinkpad: start/reload do not apply $tx"; fi
if grep -q '^ExecStartPre=' "$nu"; then bad "thinkpad: the table unit still has an ExecStartPre (delete-then-create)"; else ok "thinkpad: no separate delete step"; fi

table="$(build thinkpad true 'system.build.agentIdentityNftRules')"
nft="$(nix build --no-link --print-out-paths nixpkgs#nftables)/bin/nft"

inner="$(cat <<'INNER'
set -u
"$NFT" -f "$TX" || { echo "FAIL  transaction did not apply on an empty ruleset"; exit 1; }
measure() { # measure <apply command...>; prints the number of lookups with no table
  local stop=/tmp/.aid-stop.$$ miss
  rm -f "$stop"
  ( m=0; while [ ! -e "$stop" ]; do "$NFT" list table inet agent-identity >/dev/null 2>&1 || m=$((m + 1)); done; echo "$m" >"$stop.count" ) &
  sleep 0.2
  for _ in $(seq 1 300); do "$@"; done
  touch "$stop"; wait
  miss="$(cat "$stop.count")"; rm -f "$stop" "$stop.count"
  echo "$miss"
}
two_step() { "$NFT" delete table inet agent-identity; "$NFT" -f "$TABLE"; }
m_tx="$(measure "$NFT" -f "$TX")"
m_old="$(measure two_step)"
if [ "$m_tx" = 0 ]; then echo "PASS  transaction applied 300 times: 0 lookups found no table"; else echo "FAIL  transaction: $m_tx lookups found no table"; fi
echo "INFO  old delete-then-create, 300 times: $m_old lookups found no table"
"$NFT" list table inet agent-identity >/dev/null && echo "PASS  table present after the runs" || echo "FAIL  table missing after the runs"
INNER
)"
mkdir -p "${TMPDIR:-/tmp}"
res="$(unshare --map-root-user --net --mount env NFT="$nft" TX="$tx" TABLE="$table" bash -c "mount -t tmpfs none /tmp; $inner" 2>&1)"
printf '%s\n' "$res"
fails=$((fails + $(printf '%s\n' "$res" | grep -c '^FAIL' || true)))

echo "unit-graph-test: $fails failure(s)"
exit "$fails"
