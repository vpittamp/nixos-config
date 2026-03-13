# NixOS PWA System Documentation

Last updated: 2026-03-13

## Overview

This repository uses a declarative Google Chrome PWA system integrated with:
- the i3pm application registry
- daemon-owned launch planning
- Sway workspace assignment
- Walker launcher discovery
- Quickshell runtime UI icon and window rendering

The active system no longer uses Firefox PWA or KDE panel integration.

## Architecture

### Source of truth

The canonical PWA definitions live in:
- `shared/pwa-sites.nix`

Each entry defines the declarative PWA identity and routing metadata:
- `name`
- `url`
- `domain`
- `icon`
- `description`
- `categories`
- `keywords`
- `scope`
- `ulid`
- `app_scope`
- `preferred_workspace`
- optional `preferred_monitor_role`
- `routing_domains`
- optional `routing_paths`
- optional `auth_domains`

`ulid` is declarative and stable. It is not generated at install time.

### Registry generation

PWAs are converted into i3pm application entries in:
- `home-modules/desktop/app-registry-data.nix`

That file now exports three explicit partitions:
- `workspaceOwningApplications`
- `nonOwningLaunchables`
- `applications`

Runtime consequences:
- `workspace-assignments.json` is generated only from `workspaceOwningApplications`
- `application-registry.json` is generated from the combined `applications` list
- PWAs are normal registry entries and participate in workspace ownership through the same path as native apps
- scratchpad and floating utilities remain launchable without owning a workspace

The generated runtime files are:
- `~/.config/i3/application-registry.json`
- `~/.config/i3/pwa-registry.json`
- `~/.local/share/i3pm-applications/applications/*.desktop`

Generation happens during Home Manager activation as part of a rebuild.

### Launch path

PWA launch flows are:
- `i3pm launch open <slug>-pwa`
- `launch-pwa-by-name "<Display Name>"`
- Walker launching the generated desktop entry

The browser runtime is Google Chrome, launched with:
- `--user-data-dir="$HOME/.local/share/webapps/webapp-$ULID"`
- `--class="WebApp-$ULID"`
- `--app="$URL"`

This gives deterministic Wayland/XWayland window identity that the daemon can match to the declarative registry entry.

### UI integration

PWAs appear in:
- Walker search results through generated desktop entries
- Quickshell bottom bar workspace icon summaries
- Quickshell window and session panel rows
- daemon window identification and icon resolution

The icon source is the curated path from the declarative entry, not a theme guess.

## File Map

- `shared/pwa-sites.nix`
  - canonical PWA metadata
- `home-modules/desktop/app-registry-data.nix`
  - converts PWA definitions into app-registry entries
- `home-modules/desktop/app-registry.nix`
  - writes `application-registry.json`, `pwa-registry.json`, and generated desktop entries
- `home-modules/tools/pwa-launcher.nix`
  - `launch-pwa-by-name` helper
- `assets/icons/`
  - curated PWA and app icons
- `home-modules/desktop/sway.nix`
  - generates `workspace-assignments.json` from `workspaceOwningApplications`

## Standard Workflow

### Add a new PWA

1. Add or reuse a curated icon in `assets/icons/`.
2. Add the PWA entry in `shared/pwa-sites.nix`.
3. Rebuild the target host:

```bash
sudo nixos-rebuild switch --flake .#thinkpad
```

4. Verify generated outputs:

```bash
jq -r '.pwas[] | select(.ulid == "YOUR_ULID")' ~/.config/i3/pwa-registry.json
jq -r '.applications[] | select(.name == "your-slug-pwa")' ~/.config/i3/application-registry.json
ls ~/.local/share/i3pm-applications/applications/your-slug-pwa.desktop
```

5. Test launch:

```bash
launch-pwa-by-name "Your PWA Name"
# or
i3pm launch open your-slug-pwa
```

### Remove a PWA

1. Remove the entry from `shared/pwa-sites.nix`.
2. Rebuild the target host.
3. Verify the generated registry and desktop entry no longer contain the app.

### Update a PWA icon

1. Replace the asset in `assets/icons/`.
2. Rebuild the target host.
3. Verify the generated registry still points to the correct icon path.

No extra browser-specific reinstall step is required.

## Naming and identity

### Registry app name

The runtime application name is derived from the display name:
- lowercase
- spaces replaced with `-`
- suffixed with `-pwa`

Example:
- `Google Calendar` -> `google-calendar-pwa`

### Window class

The expected window class for a declarative PWA is:
- `WebApp-<ULID>`

Example:
- `WebApp-01K666N2V6BQMDSBMX3AY74TY7`

### Profile path

Each PWA gets its own Chrome profile directory:
- `~/.local/share/webapps/webapp-<ULID>`

## Verification commands

### Check the declarative PWA registry

```bash
jq -r '.pwas[] | "\(.name) [\(.ulid)] -> \(.url)"' ~/.config/i3/pwa-registry.json
```

### Check the runtime app registry

```bash
jq -r '.applications[] | select(.name | endswith("-pwa")) | "\(.name) -> \(.expected_class)"' ~/.config/i3/application-registry.json
```

### Check generated desktop entry

```bash
sed -n '1,160p' ~/.local/share/i3pm-applications/applications/your-slug-pwa.desktop
```

### Check live window identity

```bash
swaymsg -t get_tree | grep -F "WebApp-YOUR_ULID"
```

## Troubleshooting

### PWA does not appear in Walker

Check:
- the rebuild completed successfully
- the desktop file exists under `~/.local/share/i3pm-applications/applications/`
- Walker is reading `~/.local/share/i3pm-applications` through `XDG_DATA_DIRS`

Useful check:

```bash
ls ~/.local/share/i3pm-applications/applications/*-pwa.desktop
```

### PWA missing from the registries

Check the source-of-truth entry first:

```bash
rg -n 'name = "Your PWA Name"' shared/pwa-sites.nix
```

Then verify the generated outputs:

```bash
jq -r '.pwas[] | select(.ulid == "YOUR_ULID")' ~/.config/i3/pwa-registry.json
jq -r '.applications[] | select(.name == "your-slug-pwa")' ~/.config/i3/application-registry.json
```

### Window launches but is not matched correctly

Check:
- `ulid` is correct in `shared/pwa-sites.nix`
- generated app entry has `expected_class = "WebApp-<ULID>"`
- Chrome launched with the matching `--class`

Useful checks:

```bash
jq -r '.applications[] | select(.name == "your-slug-pwa") | .expected_class' ~/.config/i3/application-registry.json
swaymsg -t get_tree | grep -F "WebApp-YOUR_ULID"
```

### Icon does not appear

Check:
- the icon file exists in `assets/icons/`
- the PWA entry points to that icon
- the generated registry entry includes the same path

Useful checks:

```bash
ls -lh assets/icons/your-icon.svg
jq -r '.pwas[] | select(.ulid == "YOUR_ULID") | .icon' ~/.config/i3/pwa-registry.json
jq -r '.applications[] | select(.name == "your-slug-pwa") | .icon' ~/.config/i3/application-registry.json
```

## Notes

- PWAs are normal app-registry entries now; there is no separate browser-install step.
- Workspace ownership is explicit through the app-registry partitions, not inferred from launcher metadata.
- Quickshell and the daemon consume the generated registries directly; do not edit `application-registry.json` or `pwa-registry.json` by hand.
