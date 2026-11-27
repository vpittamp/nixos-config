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
- If `main` is currently failing to build in CI, no merge deploys anything
  until that is fixed; the next green push to `main` then activates `main` on
  every host, including any host the owner switched locally to something else.

## Apply (ryzen first)

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

3. Commit the one-line flip to `main` soon after. Until it is on `main`, the
   next Cachix deployment of `main` turns the module off again on ryzen.
4. Later hosts: flip their line the same way (thinkpad, surface). surface is
   switched from ryzen with `nixos-rebuild switch --flake .#surface
   --target-host vpittamp@surface --use-remote-sudo`.

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
not running, the login fails. Review agent work on GitHub; do not check out
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

`agent-identity-verify` aborts unless the agent runs as uid 2001 in a network
namespace different from the host's. Each check prints `PASS` (the specific
expected refusal or result was observed), `FAIL`, or `NORUN` (it could not
run, or saw an outcome that proves nothing). Exit status is the number of
FAIL and NORUN results. Expect all `PASS` except `NORUN hub not provisioned`
until the hub step exists, and `NORUN` for probes with no target on that host
(e.g. no running container).

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
- `tests/agent-identity/namespace-tests.sh`
- `configurations/{ryzen,thinkpad,surface}.nix`: import, `enable = false`
