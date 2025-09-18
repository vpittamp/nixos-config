# Plasma Manager Integration

Generated via `plasma-manager` on 2025-09-18 to capture the live KDE Plasma configuration for `vpittamp`.

## Current State
- Declarative snapshot lives at `home-modules/desktop/generated/plasma-rc2nix.nix`.
- The module is imported by `home-modules/profiles/plasma-home.nix` alongside hand-authored overrides.
- The curated overrides in `home-modules/desktop/plasma-config.nix` now only set high-level workspace defaults; all low-level details come from the generated module.

## Refresh Workflow
1. **Take a snapshot**
   ```bash
   plasma-sync snapshot
   ```
   This command wraps `plasma-manager rc2nix`, rewrites `home-modules/desktop/generated/plasma-rc2nix.nix` in place, and shows a diff against the previous revision.
2. **Activate (optional)**
   ```bash
   plasma-sync activate
   ```
   Runs `home-manager switch --flake /etc/nixos#vpittamp` so Plasma picks up the declarative changes after logout/login.
3. **Interactive workflow**
   ```bash
   plasma-sync
   ```
   Provides a `gum`-based menu that can run the individual steps or the full pipeline, useful when iterating by hand.

- For `plasma-sync full`, pass additional Home Manager options after `--hm`, e.g. `plasma-sync full --hm --show-trace`.

## Notes
- `overrideConfig = true` will rewrite Plasma rc files on each activation; rely on git history to revert unwanted changes.
- If rc2nix reports parse failures, prefer fixing them upstream or add minimal overrides in separate modules instead of editing the generated snapshot directly.
- Retain previous snapshots when making large changes so you can diff between versions.
