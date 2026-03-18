# Disk Pressure Runbook

## What is automated

- User timer: `disk-usage-report.timer`
  - Writes a summary report to `~/.local/state/disk-guardrails/latest-report.txt`
  - Logs warning at `80%` root usage and critical at `90%`
- User timer: `disk-cleanup-low-risk.timer`
  - Removes trash entries older than `14d`
  - Removes stale test webapp directories matching `test-1pw*` and `webapp-TEST-*`
  - Removes repo-local `result*` symlinks older than `14d`
- System policy:
  - Caps persistent coredump usage so crash dumps cannot grow without bound

## Primary inspection commands

```bash
df -h /
disk-usage-report
disk-nix-roots-audit
journalctl --disk-usage
du -xsh ~/.local/share ~/.cache ~/repos /nix/store /var/lib/systemd/coredump
```

## User service operations

```bash
systemctl --user status disk-usage-report.timer
systemctl --user status disk-cleanup-low-risk.timer
systemctl --user start disk-usage-report.service
systemctl --user start disk-cleanup-low-risk.service
```

## Coredump operations

Inspect current crash dump pressure:

```bash
ls -lh /var/lib/systemd/coredump | tail -n 40
coredumpctl list
```

Clear retained coredumps after confirming they are no longer needed:

```bash
sudo rm -f /var/lib/systemd/coredump/*
```

## Nix pressure checks

Look for repo-local roots that keep store paths alive:

```bash
disk-nix-roots-audit
find ~/repos -maxdepth 5 -type l -name 'result*' -print
find ~/repos -path '*/.devenv/gc/*' -type l -print
```

After removing stale roots:

```bash
sudo nix-collect-garbage -d
```

## Manual cleanup targets

Highest-yield locations observed on this machine class:

- `~/.local/share/firefoxpwa`
- `~/.local/share/webapps`
- `~/.local/share/pnpm/store`
- `~/.local/share/containers/storage`
- `~/.cache/.bun`
- `~/.cache/google-chrome`
- `~/.cache/mozilla`
- large inactive `node_modules` trees under `~/repos`

Use caution with:

- active Firefox PWA profiles
- active `.devenv/gc/*` roots
- current project `node_modules`

## Disk-full triage sequence

1. Run `df -h /` to confirm whether the filesystem is truly full.
2. Run `lsof +L1` to detect deleted-but-open files.
3. Run `disk-usage-report` to inspect the known hot spots.
4. Check `/var/lib/systemd/coredump` and clear crash dumps if safe.
5. Audit repo-local Nix roots with `disk-nix-roots-audit`.
6. Remove stale roots, then run `sudo nix-collect-garbage -d`.
