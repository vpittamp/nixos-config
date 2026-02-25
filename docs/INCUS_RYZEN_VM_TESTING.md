# Incus on Ryzen for NixOS VM Testing

This repository configures Incus on the `ryzen` host with:

- `virtualisation.incus.enable = true`
- declarative `virtualisation.incus.preseed`
- NAT bridge network `incusbr0`
- directory storage pool `default` at `/var/lib/incus/storage-pools/default`
- `vpittamp` in `incus-admin`
- default Incus profile sets `security.secureboot=false` (required for current `images:nixos/*` VM images)
- Incus Web UI enabled (`virtualisation.incus.ui.enable = true`)

## Apply Configuration

From repo root:

```bash
sudo nixos-rebuild dry-build --flake .#ryzen
sudo nixos-rebuild switch --flake .#ryzen
```

## Verify Host Setup

If you see a socket permission error, refresh group membership first:

```bash
newgrp incus-admin
```

```bash
systemctl status incus.service incus-preseed.service --no-pager
incus info
incus network list
incus storage list
incus profile show default
```

Expected defaults:

- network: `incusbr0` (IPv4 NAT, private subnet)
- storage pool: `default` (`dir` driver)
- profile: `default` with `eth0` on `incusbr0` and `root` disk on pool `default`

## Launch a NixOS Test VM

```bash
incus launch images:nixos/unstable nixos-test-01 --vm -c limits.cpu=4 -c limits.memory=8GiB
```

Check state and execute commands:

```bash
incus list
for i in $(seq 1 60); do incus exec nixos-test-01 -- true >/dev/null 2>&1 && break; sleep 2; done
incus exec nixos-test-01 -- uname -a
incus exec nixos-test-01 -- nix --version
```

## Open the Incus GUI

```bash
incus webui
```

This opens the Incus Web UI for your local daemon session.

## Snapshot and Cleanup

```bash
incus snapshot create nixos-test-01 baseline
incus restart nixos-test-01
incus stop nixos-test-01
incus delete nixos-test-01
```

## Useful Variants

Launch a stable release image instead of unstable:

```bash
incus launch images:nixos/25.11 nixos-test-stable --vm
```

Launch with larger resources:

```bash
incus launch images:nixos/unstable nixos-test-big --vm \
  -c limits.cpu=8 \
  -c limits.memory=16GiB
```

## Troubleshooting

Show Incus daemon logs:

```bash
journalctl -u incus.service -b --no-pager
journalctl -u incus-preseed.service -b --no-pager
```

Re-check bridge and firewall state:

```bash
incus network show incusbr0
sudo nft list ruleset | rg incus -n
```
