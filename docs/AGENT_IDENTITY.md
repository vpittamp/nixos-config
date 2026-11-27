# Agent identity: AI coding agents as their own OS user

Step I2 of separating AI-agent identity from the owner's (option-b design v2,
section 5). Step I1 is PittampalliOrg/stacks#18519 (dev namespace
`agent-identity`, which mints the App token).

## Why

Until now, lead agent sessions (Claude Code, Codex, agy and their subagents)
ran as `vpittamp`: `gh` logged in as the owner (`admin:org`, `repo`,
`workflow`), git pushing with the owner's credential, kube contexts `hub` and
`dev` as cluster-admin, the 1Password and SSH agents, the browser profile and
the reviewer App key all in reach. A GitHub approval gate between "agent" and
"owner" was therefore not a gate.

## Shape: a separate OS user, sessions in their own network namespace

`services.agentIdentity` (`modules/services/agent-identity.nix`) creates the
user `agent` (uid 2001) and is enabled on `ryzen`, `thinkpad` and `surface`.

| Layer | What it does | Where |
| --- | --- | --- |
| OS user `agent` | Own home `/home/agent` (0700), locked password, no groups (not wheel, docker, podman, onepassword, networkmanager, input, libvirtd, users), no sudo rule. The owner's home is asserted 0700, so nothing under it (gh `hosts.yml`, `~/.kube`, `~/.1password/agent.sock`, `~/.ssh`, browser profiles, `~/.config/pittampalli-pr-reviewer/`) is reachable. `/run/user/1000` (Wayland, D-Bus, 1Password browser socket) is 0700. | `modules/services/agent-identity.nix` |
| Home | Minimal home-manager profile, not `base-home.nix`: CLIs (claude, codex, agy, herdr, kubectl, helm, node, python, language servers), `gh` wrapper, git identity, kubeconfig. Shared skills linked into `~/.claude/skills` and `~/.codex/skills`. | `home-modules/profiles/agent-home.nix` |
| GitHub | `gh` wrapper sets `GH_TOKEN` from `agent-author-token` on every call and refuses `gh auth login/refresh/setup-git/switch/token`. git's only credential helper is `agent-author-token git-credential`, which answers only for `https://github.com/PittampalliOrg/{stacks,workflow-builder}` (with `credential.useHttpPath`) and tells git to stop (`quit=1`) for anything else. SSH remotes are rewritten to HTTPS; the agent has no SSH key. Identity: `pittampalli-agent-author[bot] <362024332+pittampalli-agent-author[bot]@users.noreply.github.com>` (362024332 is the bot user's id, not the App id). | `scripts/agent-identity/agent-author-token.sh` |
| Token path | `agent-author-token` reads the owner-placed bound token of `agent-identity/local-minter` (`/var/lib/agent-identity/dev-local-minter.token`, 0600 `agent`), GETs Secret `agent-identity/agent-author-token` from the dev API server (CA pinned, bearer header from a pipe, never in argv), checks with GitHub that the token reaches exactly the two repositories and reads its expiry (`GitHub-Authentication-Token-Expiration`; fallback: the Secret's last write + 1 h). Cached only on tmpfs `/run/agent-identity/github/` (0700 `agent`), refetched with under 10 min left, never used past expiry. | same |
| Kubernetes | `KUBECONFIG=/var/lib/agent-identity/kubeconfig`, written by the owner: contexts `dev` (SA `local-minter`, `view` + get that one Secret) and, later, `hub` (SA `local-viewer`, `view`). Each user stanza is a `tokenFile`; no admin context and no client certificate exists for this user. | `scripts/agent-identity/agent-identity-provision.sh` |
| Network (host) | nftables table `inet agent-identity`, keyed on uid 2001: reject everything via `tailscale0` and to `100.64.0.0/10` / `fd7a:115c:a1e0::/48` (MagicDNS port 53 excepted), and everything to `lo` (host loopback and the host's own addresses). | module, `nftRules` |
| Network (sessions) | `agent-netns.service` (User=agent) holds one user+network namespace with internet through `pasta` and no path to host loopback (`--no-map-gw`, all port forwarding off). The uid inside is the agent's own. Sessions join it with `agent-enter`; the agent's own dev servers work on its private 127.0.0.1. | `scripts/agent-identity/agent-netns.sh`, `agent-enter.sh` |
| Terminal | `sudo` runs with `use_pty`, and `dev.tty.legacy_tiocsti=0`, so an agent process cannot inject keystrokes into the owner's shell. | module |

### Why (a) a separate user and not (b) a wrapper or sandbox

- A wrapper inside `vpittamp` (`GH_TOKEN`, `GH_CONFIG_DIR`) changes who agents
  *author* as and nothing else: the agent can still read `~/.config/gh`, the
  kubeconfig, the reviewer key, talk to the 1Password and SSH agents, and run
  `sudo` (wheel is passwordless here).
- A bubblewrap or systemd-scope sandbox around an owner-uid process can hide
  paths, but every hole is a hole in the owner's full authority: `sudo`, the
  owner's D-Bus and polkit rules (the 1Password polkit rules here grant by
  user name), any socket or path the profile forgets. It also has to be
  maintained per CLI.
- A different uid gets the kernel's DAC, the per-user polkit rules, the 0700
  homes and `/run/user/1000`, and sudo's wheel rule for free, and it is
  reversible (`enable = false`).
- Two things a different uid does **not** separate on this machine, found while
  mapping it, are why the module adds the network layers:
  1. **The tailnet authenticates by device, not by uid.** The operator
     apiserver proxies (`k8s-api-hub`, `dev-api-v2`, ...) grant
     `system:masters` to the device owner's Tailscale identity, and Headlamp and
     Argo CD sit on the tailnet too. Any local process, of any user, reaching
     them is the owner. Hence the uid-keyed reject on `tailscale0` and the
     tailnet ranges.
  2. **Loopback has no owner.** The owner's Chrome exposes its DevTools port on
     127.0.0.1 (a logged-in GitHub browser session), and local MCP servers and
     IDE bridges listen there. Hence the uid-keyed reject on `lo`, and the
     session namespace so agents keep a usable loopback of their own.

## What an agent process can and cannot reach afterwards

| Reach | Agent |
| --- | --- |
| GitHub as `pittampalli-agent-author`: contents, issues, pull requests write on `stacks` and `workflow-builder` | yes |
| Push touching `.github/workflows/`, any org/repo admin API, rulesets, statuses/checks, approving as code owner | no (the App has none of those permissions) |
| git credentials for any other repository or host | no (helper refuses; the token would be refused by GitHub anyway) |
| The owner's `gh` token, kubeconfig and admin client certificates, SSH keys, 1Password (desktop app, SSH agent, CLI service token in `/etc/onepassword/service-token.env`), browser profiles, reviewer App key | no (DAC: 0700 home, 0600 file, 0700 `/run/user/1000`) |
| dev API as `local-minter`: read (`view`, no Secrets) + get `agent-identity/agent-author-token` | yes |
| hub API | no, until the stacks follow-up below; then `view` only |
| Tailnet (apiserver proxies, Headlamp, Argo CD, other devices) | no (nftables, uid 2001) |
| Host loopback listeners (Chrome DevTools, MCP servers, IDE ports, local databases) | no (namespace has its own loopback; nftables rejects uid 2001 to `lo`) |
| Docker / Podman sockets (root-equivalent) | no (not in the groups) |
| sudo | no |
| The public internet | yes |

### Residual paths (not closed by this change)

1. **World-readable files outside the owner's home.** Anything the owner
   leaves world-readable in `/tmp`, `/var/tmp`, `/dev/shm` or `/nix/store` is
   readable by the agent (owner-created `/tmp/<dir>` with mode 0755 exists
   today, e.g. checkouts and venvs). Never put a secret in the Nix store; keep
   temporary credentials under a 0700 directory.
2. **Process listing.** `/proc` is not mounted with `hidepid`, so the agent can
   see the owner's process command lines (not environments). Never pass a
   secret in argv.
3. **tailscaled's LocalAPI socket is 0666.** Read-only status is available to
   every user. Dialing through tailscaled (`tailscale nc`) needs LocalAPI write
   access, which only root and the operator (`vpittamp`) have; the
   verification script proves the refusal on each host and fails if it is not
   clearly refused.
4. **Shared kernel and machine** (design section 18, item 3): a local privilege
   escalation, or a sudo rule later granted to `agent`, undoes all of this.
5. **dev `view` includes `pods/log` and ConfigMaps.** A secret printed into a
   log or a ConfigMap on dev is readable by the agent (and already by every
   `view` holder).
6. **Exit node.** With a Tailscale exit node set, the agent has no internet
   (fail-closed); set `services.agentIdentity.network.blockTailscaleInterface
   = false` only if that is needed, which keeps the tailnet-range rejects.
7. **Agent-owned credentials the owner hands over** (Claude/Codex
   subscription logins, any MCP API key) are the agent's to use; give it only
   workspace-scoped keys.
8. **Terminal escape sequences.** Agent output reaches the owner's terminal
   (e.g. OSC 52 clipboard writes); `use_pty` stops input injection, not
   output.

## Reviewer designation stays owner-only

`scripts/pr-reviewer/` in stacks and workflow-builder signs with the reviewer
App key in `~vpittamp/.config/pittampalli-pr-reviewer/`. The agent cannot
traverse `/home/vpittamp` (0700, asserted at build time), has no sudo, and its
own clones contain the scripts but no key. Until I3 moves designation to the
hub, the owner runs `designate.sh` from his own shell, never inside
`agent-shell`/`agent-session`, and never on a script an agent prepared without
reading it first. Do not copy the key, or anything under that directory, into
`/var/lib/agent-identity`, `/home/agent` or `/tmp`.

## Owner apply steps

Order: **ryzen first** (lead sessions run there today; it uses the
declarative nftables backend). thinkpad and surface next (iptables hosts: the
same table comes from `agent-identity-netfilter.service`).

1. Build, then switch:

   ```bash
   cd ~/repos/vpittamp/nixos-config/<checkout of this branch>
   sudo nixos-rebuild dry-build --flake .#ryzen
   sudo nixos-rebuild switch --flake .#ryzen
   systemctl status agent-netns --no-pager
   sudo nft list table inet agent-identity
   ```

2. When stacks#18519 is synced on dev (`kubectl --context dev -n
   agent-identity get secret agent-author-token -o name` answers), place the
   bound token. This is the one manual credential step:

   ```bash
   agent-identity-provision dev            # default --duration 24h
   ```

   It runs, with the owner's kubeconfig,
   `kubectl --context dev -n agent-identity create token local-minter --duration=24h`
   and pipes the result straight into
   `sudo install -m 0600 -o agent -g agent /dev/stdin /var/lib/agent-identity/dev-local-minter.token`.
   It also copies the dev server URL and CA (public) to
   `/var/lib/agent-identity/dev-server` and `dev-ca.crt`, writes
   `/var/lib/agent-identity/kubeconfig`, and prints the agent's `auth whoami`.
   The `dev` context must point at the public API endpoint, not a tailnet
   proxy (the agent cannot reach the tailnet; the script refuses one). Re-run
   it daily (or with a longer `--duration` if the API server allows); when it
   expires, `agent-author-token` says so and names this command.

3. One-time agent setup (owner-driven, as the agent):

   ```bash
   agent-shell claude            # then /login with the subscription
   agent-shell codex login
   agent-shell herdr integration install claude
   agent-shell herdr integration install codex
   agent-shell git clone https://github.com/PittampalliOrg/workflow-builder ~/repos/PittampalliOrg/workflow-builder
   agent-shell git clone https://github.com/PittampalliOrg/stacks ~/repos/PittampalliOrg/stacks
   ```

   Memory and project notes under `~/.claude/projects/` are not copied
   automatically. Review them first (they describe the owner's systems), then
   e.g. `sudo cp -r ~/.claude/projects/<p>/memory /home/agent/.claude/projects/<p>/ && sudo chown -R agent:agent /home/agent/.claude`.

4. Verify (expected output below):

   ```bash
   agent-identity-verify          # --no-push skips the two push probes
   ```

5. Work: `agent-session` (herdr session `lead`, inside the namespace) or
   `agent-session <name>`. Detach leaves the agent's herdr server running;
   `agent-session` again re-attaches. `agent-shell` gives a plain shell or runs
   one command.

### Fallback

- Agent network broken: `sudo systemctl restart agent-netns`, then restart the
  agent's herdr server (`agent-shell herdr server stop`) so panes rejoin the
  new namespace.
- Token path broken (dev unreachable, minter stale): `agent-shell
  agent-author-token status` names the cause. The owner can push an agent's
  branch himself from his own clone after review.
- Undo: set `services.agentIdentity.enable = false;` in the host file and
  switch. The user's home stays on disk (`/home/agent`); delete it by hand if
  wanted. Running agents as `vpittamp` again re-opens everything this change
  closed.

### Expected `agent-identity-verify` output (dev provisioned, hub not yet)

```
== OS identity
PASS  agent groups: agent
PASS  agent cannot sudo
== owner credentials are unreachable from the agent
PASS  agent cannot read /home/vpittamp
PASS  agent cannot read /home/vpittamp/.config/gh/hosts.yml
PASS  agent cannot read /home/vpittamp/.kube/config
PASS  agent cannot read /home/vpittamp/.1password/agent.sock
PASS  agent cannot read /home/vpittamp/.ssh
PASS  agent cannot read /home/vpittamp/.config/pittampalli-pr-reviewer
PASS  agent cannot read /home/vpittamp/.config/google-chrome
PASS  agent cannot read /run/user/1000
PASS  agent cannot read /etc/onepassword/service-token.env
PASS  agent cannot use /run/docker.sock
PASS  agent cannot use /run/podman/podman.sock
== GitHub identity
PASS  agent-author-token status: ...
PASS  token reaches exactly: PittampalliOrg/stacks,PittampalliOrg/workflow-builder
PASS  GitHub viewer is pittampalli-agent-author[bot]
PASS  admin read refused: gh: Resource not accessible by integration (HTTP 403)
PASS  repo hooks read refused: gh: Resource not accessible by integration (HTTP 403)
PASS  gh auth login is refused: gh (agent): 'gh auth login' is disabled; ...
PASS  git identity: pittampalli-agent-author[bot] <362024332+pittampalli-agent-author[bot]@users.noreply.github.com>
== GitHub pushes
PASS  push to a scratch branch on PittampalliOrg/stacks works
PASS  push touching .github/workflows/ refused: ... without `workflows` permission ...
PASS  push to a repository outside the two is refused locally: agent-author-token: refusing credentials for github.com/vpittamp/nixos-config.git ...
== Kubernetes (read-only)
PASS  agent kube contexts: dev
PASS  dev: whoami system:serviceaccount:agent-identity:local-minter
PASS  dev: can-i create pods -A -> no
PASS  dev: can-i list secrets -A -> no
PASS  dev: can-i '*' '*' -A -> no
PASS  dev: can-i get pods -A -> yes
PASS  dev: get pods -A works
SKIP  hub not provisioned (needs the stacks hub ServiceAccount; then: agent-identity-provision hub)
PASS  bound token file mode: 600 agent
== network boundary
PASS  agent namespace reaches the internet (api.github.com 200)
PASS  agent namespace has its own working loopback
PASS  none of the host's <n> loopback listeners is reachable from the agent namespace
PASS  host nftables layer: the agent uid cannot reach 127.0.0.1:22 (the owner can)
PASS  agent cannot reach tailnet host k8s-api-hub.tail286401.ts.net (the owner can)
PASS  tailscale nc as the agent is refused by tailscaled: ...
agent-identity-verify: all checks passed
```

The exact GitHub error strings are not verified yet (they need the live
token). Exit status is the number of FAILs; a SKIP is never a PASS.

## Hub read access (stacks follow-up)

A dev ServiceAccount token is not valid on the hub, and there is no
cross-cluster credential path, so the hub needs its own identity. Exact change
for a PittampalliOrg/stacks pull request, in the hub-management component:

- `packages/components/hub-management/manifests/agent-identity/Namespace-agent-identity.yaml`:
  Namespace `agent-identity`, Pod Security `restricted` labels.
- `.../agent-identity/ResourceQuota-no-pods.yaml`: `pods: "0"`.
- `.../agent-identity/ServiceAccount-local-viewer.yaml`: ServiceAccount
  `agent-identity/local-viewer`, `automountServiceAccountToken: false`, no
  token Secret.
- `.../agent-identity/ClusterRoleBinding-agent-identity-local-viewer-view.yaml`:
  ClusterRoleBinding `agent-identity-local-viewer-view` -> ClusterRole `view`,
  subject the ServiceAccount above. Nothing else: no Role on any Secret, no
  `edit`, no impersonation.
- `packages/components/hub-management/kustomization.yaml`: list the four files.
- A test next to `scripts/gitops/test_agent_identity_dev.py` asserting the
  binding is exactly `view`, the ServiceAccount has no token Secret, and no
  other binding names `agent-identity:local-viewer`.
- Optional, only if agents need Argo CD objects on the hub: `view` does not
  include `argoproj.io` unless the chart aggregates it; add a ClusterRole with
  `get/list/watch` on `applications`, `applicationsets`, `appprojects` and bind
  it the same way.

Owner check after sync, then the workstation step:

```bash
kubectl --context hub auth can-i list secrets -A --as=system:serviceaccount:agent-identity:local-viewer   # no
kubectl --context hub auth can-i get pods -A --as=system:serviceaccount:agent-identity:local-viewer       # yes
agent-identity-provision hub    # kubectl --context hub -n agent-identity create token local-viewer --duration=24h
```

The owner's `hub` context must point at the hub's public API endpoint.

## Still unverified until stacks#18519 is live on dev

- `agent-author-token` end to end: Secret read with the bound token, the
  GitHub expiry header on installation tokens (else the write-time fallback is
  used), the exact-repositories check.
- GitHub's behaviour for the App: `/installation/repositories` contents,
  GraphQL `viewer` login, the refusal text for a `.github/workflows/` push and
  for org admin reads, and whether a stacks ruleset restricts branch creation
  or deletion for the App.
- Every check of `agent-identity-verify` that runs as the agent (the user does
  not exist until the switch).

## Files

- `modules/services/agent-identity.nix`: user, sudo/tty hardening, state and
  runtime directories, nftables table (both backends), `agent-netns.service`,
  owner commands, the agent's home-manager wiring.
- `home-modules/profiles/agent-home.nix`: the agent's environment.
- `scripts/agent-identity/`: `agent-author-token.sh`, `agent-netns.sh`,
  `agent-enter.sh`, `agent-session.sh` (`agent-session`, `agent-shell`),
  `agent-identity-provision.sh`, `agent-identity-verify.sh`. All are built
  with `writeShellApplication`, so shellcheck gates them at build time.
- `configurations/{ryzen,thinkpad,surface}.nix`: import + enable.
- `shared-skills/cluster-desired-state/SKILL.md`: the App as state not in Git.
