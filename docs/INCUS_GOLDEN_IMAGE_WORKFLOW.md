# Incus Golden Image Workflow (Sway Lite)

This repository provides a lightweight Incus VM image with:

- headless Sway (Wayland)
- i3pm project/worktree management
- tmux/terminal home-manager stack
- local OTEL AI monitoring (`otel-ai-monitor` on `4318`)

## Build Artifacts

- `.#incus-sway-lite-qcow2`: QCOW2 disk image
- `.#incus-sway-lite-incus-metadata`: Incus metadata tarball bundle source
- `.#incus-sway-lite-incus-bundle`: convenience directory with:
  - `disk.qcow2`
  - `incus.tar.xz`
  - `metadata.yaml`

## One-Command Publish

```bash
./scripts/incus-publish-image.sh
```

This command:

1. builds `.#incus-sway-lite-incus-bundle`
2. imports it into local Incus
3. creates a versioned alias: `nixos-incus-sway-lite-<version>`
4. updates the stable alias: `nixos-incus-sway-lite`

### Useful Flags

```bash
./scripts/incus-publish-image.sh --dry-run
./scripts/incus-publish-image.sh --version 20260225-r1
./scripts/incus-publish-image.sh --stable-alias nixos-incus-sway-lite
```

## Launch a VM

```bash
incus launch nixos-incus-sway-lite vm-sway-01 --vm
```

Optional resource limits:

```bash
incus launch nixos-incus-sway-lite vm-sway-01 --vm \
  -c limits.cpu=4 \
  -c limits.memory=8GiB
```

## Validate Inside VM

```bash
incus exec vm-sway-01 -- uname -a
incus exec vm-sway-01 -- systemctl --user status i3-project-daemon --no-pager
incus exec vm-sway-01 -- systemctl --user status otel-ai-monitor --no-pager
```

## Remote Desktop

The image boots headless Sway. WayVNC services are managed from home-manager Sway config.
Use Tailscale (recommended) or Incus networking + port forwarding to access VNC outputs.

## Notes

- Home profile uses `programs.sway-profile.mode = "headless"` to avoid hostname coupling.
- AI monitoring is local-only in this flavor (no Alloy/Beyla/remote push).
- This flavor intentionally avoids full heavy desktop/dev parity from `base-home`.
