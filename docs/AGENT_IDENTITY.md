# Agent identity: AI coding agents as their own OS user

`services.agentIdentity` (`modules/services/agent-identity.nix`) runs lead
coding agents (Claude Code, Codex, agy) as the OS user `agent` (uid 2001)
instead of the owner. The agent authors on GitHub as the App
`pittampalli-agent-author` (two repositories, no admin), reads the dev
cluster through a `view` ServiceAccount, and every agent login runs inside its
own user, network and mount namespace. It is **off on every host** until the
owner turns it on.

## How this repository deploys (read before applying)

- `.github/workflows/deploy.yml` builds `ryzen`, `thinkpad`, `surface` and
  `surface-pro3` on every push to `main` and, if all builds pass, activates
  the result on **every** host through Cachix Deploy (`packages/default.nix`,
  `deploy`). A merge is therefore not a per-host step.
- The module is merged with `services.agentIdentity.enable = false;` in
  `configurations/{ryzen,thinkpad,surface}.nix`, so merging changes nothing
  on any host. Each host is turned on by flipping that one line.
- **Squash-merge this pull request**, so its first commit (module enabled on
  all three hosts) never lands on `main` on its own.
- `main` has not built green since 2026-09-13 (a flake input no longer
  downloads), so no merge deploys anything today. When that input is fixed,
  the first green push activates about two and a half months of `main` on
  all **four** hosts at once, including any host switched locally to
  something else. Decide that deliberately: for example, disable the `deploy`
  job before fixing the input, and re-enable it when ready.

## Apply (ryzen first)

Switch at ryzen's **local console**, not over Tailscale SSH: tailscaled
restarts during activation (its unit changes) and takes the session with it.

1. Turn it on for ryzen only, on a branch:

   ```bash
   # configurations/ryzen.nix
   services.agentIdentity.enable = true;
   ```

2. Switch ryzen locally from that checkout and check the units:

   ```bash
   sudo nixos-rebuild dry-build --flake .#ryzen
   sudo nixos-rebuild switch --flake .#ryzen
   systemctl status agent-netns --no-pager
   sudo nft list table inet agent-identity
   getfacl -p /run/tailscale
   ```

3. Run the first-host checklist below, then `agent-identity-verify`, before
   the first agent session.
4. Commit the one-line flip to `main` soon after. Until it is on `main`, the
   next Cachix deployment of `main` turns the module off again on ryzen.
5. Later hosts: flip their line the same way (thinkpad, surface). surface is
   switched from ryzen with `nixos-rebuild switch --flake .#surface
   --target-host vpittamp@surface --use-remote-sudo`.

## First-host checklist (ryzen, after the switch)

1. `systemctl is-active agent-netns` is `active`; `systemctl is-active
   tailscaled` is `active` and `tailscale status` works for the owner.
2. `sudo nft list chain inet agent-identity output` shows exactly one rule,
   `meta skuid 2001 jump agent_out`.
3. The owner's own traffic is unaffected: `ping -c1 127.0.0.1` replies and
   `curl -sS http://127.0.0.1:1` fails at once with "Connection refused".
4. `getfacl -p /run/tailscale` lists `user:agent:---`; run
   `sudo systemctl restart tailscaled` once and check it again.
5. `grep -c '^agent:' /etc/subuid /etc/subgid` prints 0 for both;
   `systemctl is-enabled user@2001.service` prints `masked`.
6. `sudo sshd -T -C user=agent,host=localhost,addr=127.0.0.1 | grep -i denyusers`
   prints `denyusers agent`.
7. `sudo -u agent -i -- readlink /proc/self/ns/net` differs from
   `readlink /proc/self/ns/net`, and
   `sudo -n -l -u agent /run/current-system/sw/bin/bash` prints nothing and
   exits 1 (refused), while `sudo -n -l -u agent agent-enter` prints its path.
8. `agent-shell` opens a shell; inside, `ls /tmp` does not show the owner's
   files and `curl -sS https://api.github.com/zen` answers.
9. `tests/agent-identity/namespace-tests.sh`,
   `tests/agent-identity/unit-graph-test.sh` and `agent-identity-verify`
   (after `agent-identity-provision dev`) report no FAIL.

## Emergency

```bash
sudo nft delete table inet agent-identity   # drop the agent uid rules (affects only uid 2001)
sudo systemctl stop agent-netns             # cut every agent session off the network
sudo nixos-rebuild switch --rollback        # back to the previous generation (at the console)
```

## Provision the cluster token (owner, daily)

Once the dev side (PittampalliOrg/stacks#18519) is synced:

```bash
agent-identity-provision dev            # --duration 24h by default
```

It issues a bound token for ServiceAccount `agent-identity/local-minter` with
the owner's own kubeconfig and places it at
`/var/lib/agent-identity/dev-local-minter.token` (0600, owned by `agent`).
A failed issue leaves the previous token in place. It also writes the public
server URL and CA and `/var/lib/agent-identity/kubeconfig`, then prints the
agent's `kubectl auth whoami`. The `dev` context it reads must point at the
cluster's public API endpoint. Re-run before the token expires;
`agent-author-token` names this command when it has.

`agent-identity-provision hub` does the same for the hub once the stacks
follow-up below exists.

## Use

```bash
agent-session            # herdr session "lead" as the agent, inside its namespace
agent-session <name>     # another session; run again to re-attach
agent-shell [command]    # a login shell, or one command, as the agent
```

One-time, as the agent: `agent-shell claude` (then `/login`),
`agent-shell codex login`, `agent-shell herdr integration install claude`,
and clone `PittampalliOrg/workflow-builder` and `PittampalliOrg/stacks` under
`/home/agent/repos/`. Review anything copied from the owner's `~/.claude`
before copying it.

Every login of the user lands in the namespace; if `agent-netns.service` is
not running, the login fails. The agent has no systemd user manager
(`user@2001.service` is masked). sudo runs only three things as the agent:
its login shell (`sudo -u agent -i [-- command]`), `agent-enter`, and the
fixed probe tool `agent-identity-probe`; `sudo -u agent <anything else>` is
refused, so nothing lands as the agent in the host namespaces by accident.
To debug outside the namespace, use root (`sudo -i`, then `setpriv`). Review agent work on GitHub; do not check out
agent branches in the owner's own sessions.

`agent-netns.service` is not restarted by a rebuild (it would cut running
sessions off the network). Restart it deliberately:
`sudo systemctl restart agent-netns`, then `agent-shell herdr server stop`
so panes come back in the new namespace.

## Verify

```bash
agent-identity-verify          # --no-push skips the two push probes
tests/agent-identity/namespace-tests.sh   # no root; scratch namespaces only
```

Run `agent-identity-verify` before the first agent session on each host. It
executes nothing the agent can write (only the fixed probe tool and
store-path binaries in an empty environment). It aborts unless the agent runs as uid 2001 in a network
namespace different from the host's. Each check prints `PASS` (the specific
expected refusal or result was observed), `FAIL`, or `NORUN` (it could not
run, or saw an outcome that proves nothing). Exit status is the number of
FAIL and NORUN results. Expect all `PASS` except `NORUN hub not provisioned`
until the hub step exists, and `NORUN` for probes with no target on that host
(e.g. no running container).

`unit-graph-test.sh` checks that a rule change does not restart
`agent-netns` and that the table is replaced in one transaction.
`verify-isolation-test.sh <old> <new>` checks that a `.pth` planted in the
agent's home is not run by the verify script's probes.

`namespace-tests.sh` builds the nftables table from this checkout and checks,
in throwaway namespaces mapped onto the owner's subordinate uids, that the
table affects only uid 2001 and refuses it the expected destinations, that a
directory ACL refuses uid 2001 a 0666 socket, and that the agent's private
`/tmp` is locked. It exits non-zero on any failure.

## Roll back

- One host: set `services.agentIdentity.enable = false;` for it and switch
  (and commit, for the reason above). `/home/agent` and
  `/var/lib/agent-identity` stay on disk; remove them by hand if wanted.
- Stop all agent network access at once: `sudo systemctl stop agent-netns`.

## Hub read access (stacks follow-up)

A dev ServiceAccount token is not valid on the hub. A PittampalliOrg/stacks
pull request adds, in the hub-management component
(`packages/components/hub-management/manifests/agent-identity/`, listed in its
`kustomization.yaml`):

- Namespace `agent-identity` (Pod Security `restricted`), ResourceQuota
  `pods: "0"`;
- ServiceAccount `agent-identity/local-viewer`,
  `automountServiceAccountToken: false`, no token Secret;
- ClusterRoleBinding `agent-identity-local-viewer-view` to ClusterRole
  `view`, and nothing else;
- a test asserting exactly that binding.

Then: `agent-identity-provision hub`.

## Files

- `modules/services/agent-identity.nix`, `home-modules/profiles/agent-home.nix`
- `scripts/agent-identity/`: `agent-author-token.sh`, `agent-netns.sh`,
  `agent-netns-publish.sh`, `agent-enter.sh`, `agent-session.sh`,
  `agent-identity-provision.sh`, `agent-identity-verify.sh`
- `tests/agent-identity/`: `namespace-tests.sh`, `unit-graph-test.sh`,
  `verify-isolation-test.sh`; `scripts/agent-identity/agent-identity-probe.py`
- `configurations/{ryzen,thinkpad,surface}.nix`: import, `enable = false`
