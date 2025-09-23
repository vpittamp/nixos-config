# PWA Icons Directory

This directory contains local icon files for Progressive Web Apps (PWAs).

## File Format
- Use PNG format for best compatibility
- Recommended size: at least 512x512px for best quality at all sizes
- Icons will be automatically resized to multiple sizes (16, 32, 48, 64, 96, 128, 192, 256, 512)

## Naming Convention
- Use descriptive names: `app-name.png`
- Examples: `google-ai.png`, `github.png`, `claude.png`

## Usage
Reference these icons in `/etc/nixos/modules/desktop/pwa-icons-v2.nix`:

```nix
"PWA_ID_HERE" = {
  name = "App Name";
  iconFile = "${iconAssetsDir}/app-name.png";
};
```

## Current Icons
- `google-ai.png` - Google AI/Search icon

## Adding New Icons
1. Copy your PNG file to this directory
2. Add the mapping in the pwa-icons module
3. Run `sudo nixos-rebuild switch` to apply

## Finding PWA IDs
Run `firefoxpwa profile list` to see installed PWAs and their IDs.