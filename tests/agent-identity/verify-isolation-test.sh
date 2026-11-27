#!/usr/bin/env bash
# The owner's verify script must not run anything the agent can write.
#
# Reproduces the review's demonstration: a `.pth` file planted in the agent's
# user site-packages runs (as the agent, in the HOST network namespace) when
# the owner's verify script probes "as the agent outside the namespace" with
# `sudo --user=agent -- python3 -c ...`, because sudo sets HOME to the agent's
# home. Run as the OWNER, no root: a scratch user+mount namespace on the
# owner's subordinate uids, uid 2001 as the agent, and a `sudo` shim that
# does what sudo does for `--user=agent -- cmd` (switch uid, HOME=target home,
# PATH kept).
#
#   tests/agent-identity/verify-isolation-test.sh <old verify script> <new verify script>
#
# Expects the OLD script's host probe to run the planted code (the test
# reports FAIL for it) and the NEW script's host probe not to (PASS). Exit
# status: 0 only if the new script is clean.
set -euo pipefail

old="${1:?old agent-identity-verify script}"
new="${2:?new agent-identity-verify script}"

# The probe definitions of each script, up to and including probe_host.
defs() { sed -n '/^\(py\|probe_bin\)=/,/^probe_host()/p' "$1"; }
OLD_DEFS="$(defs "$old")"
NEW_DEFS="$(defs "$new")"
[ -n "$OLD_DEFS" ] && [ -n "$NEW_DEFS" ] || { echo "could not extract probe definitions" >&2; exit 2; }
# The interpreter the verify script resolves: writeShellApplication puts its
# runtimeInputs (plain pkgs.python3, user site enabled) first on PATH.
pydir="$(nix build --no-link --print-out-paths --impure --expr "
  (builtins.getFlake (toString $(cd "$(dirname "$0")/../.." && pwd))).inputs.nixpkgs.legacyPackages.x86_64-linux.python3")/bin"
py="$pydir/python3"

inner="$(cat <<'INNER'
set -u
fails=0
mount -t tmpfs -o mode=755 none /home
mount -t tmpfs -o mode=1777 none /tmp
mkdir -p /home/agent /tmp/shim
chown 2001:2001 /home/agent
site="$(setpriv --reuid 2001 --regid 2001 --clear-groups env HOME=/home/agent "$PY" -c 'import site; print(site.getusersitepackages())')"
setpriv --reuid 2001 --regid 2001 --clear-groups mkdir -p "$site"
# The planted payload: record that it ran, as whom, in which network namespace.
printf '%s\n' 'import os; open("/tmp/pth-ran", "a").write("uid=%d ns=%s\n" % (os.getuid(), os.readlink("/proc/self/ns/net")))' \
  | setpriv --reuid 2001 --regid 2001 --clear-groups tee "$site/zz-planted.pth" >/dev/null
cat >/tmp/shim/sudo <<'SHIM'
#!/bin/sh
# sudo --user=<u> [--login] -- cmd...  (only the non-login form is emulated)
user=""; login=0
while [ $# -gt 0 ]; do
  case "$1" in --user=*) user="${1#--user=}" ;; --login) login=1 ;; --) shift; break ;; *) break ;; esac
  shift
done
[ "$login" = 0 ] || { echo "shim: --login not emulated" >&2; exit 97; }
[ "$user" = agent ] || { echo "shim: only --user=agent" >&2; exit 98; }
exec setpriv --reuid 2001 --regid 2001 --clear-groups env HOME=/home/agent PATH="$PATH" "$@"
SHIM
chmod 755 /tmp/shim/sudo
export PATH="/tmp/shim:$PYDIR:$PATH"

run_case() { # run_case <label> <defs> <probe args...>
  local label="$1" defs="$2"; shift 2
  rm -f /tmp/pth-ran
  out="$(agent=agent; py="$PY"; eval "$defs"; probe_host "$@" 2>&1)"
  if [ -e /tmp/pth-ran ]; then
    printf 'FAIL  %s: the planted .pth ran (%s); probe said: %s\n' "$label" "$(tr '\n' ' ' </tmp/pth-ran)" "$out"
    fails=$((fails + 1))
  else
    printf 'PASS  %s: the planted .pth did not run; probe said: %s\n' "$label" "$out"
  fi
}
run_case "old verify host probe" "$OLD_DEFS" 127.0.0.1 9
old_fails=$fails; fails=0
run_case "new verify host probe" "$NEW_DEFS" tcp 127.0.0.1 9
run_case "new verify host probe (unix)" "$NEW_DEFS" unix /run/does-not-exist
echo "verify-isolation-test: old script planted-code runs: $old_fails; new script planted-code runs: $fails"
exit "$fails"
INNER
)"

exec unshare --map-auto --map-root-user --mount \
  env PY="$py" PYDIR="$pydir" OLD_DEFS="$OLD_DEFS" NEW_DEFS="$NEW_DEFS" bash -c "$inner"
