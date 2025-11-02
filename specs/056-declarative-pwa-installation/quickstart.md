# Quickstart Guide: Declarative PWA Installation

**Feature**: 056-declarative-pwa-installation
**Last Updated**: 2025-11-02
**Target Users**: NixOS system administrators, developers using PWAs

## Overview

This guide shows how to install and manage Progressive Web Apps (PWAs) declaratively using NixOS configuration. Once configured, PWAs are automatically installed across all your NixOS systems without manual Firefox GUI interaction.

**Key Benefits**:
- ✅ Zero-touch PWA deployment on fresh systems
- ✅ Cross-machine configuration portability
- ✅ Single source of truth for PWA metadata
- ✅ Automatic launcher integration (Walker/KRunner)
- ✅ Automatic 1Password extension installation

---

## Quick Start (5 Minutes)

### 1. Add PWA to Configuration

Edit `/etc/nixos/shared/pwa-sites.nix`:

```nix
pwaSites = [
  # Existing PWAs...

  # Add your new PWA
  {
    name = "YouTube";
    url = "https://www.youtube.com";
    domain = "youtube.com";
    icon = "file:///etc/nixos/assets/pwa-icons/youtube.png";
    description = "YouTube Video Platform";
    categories = "AudioVideo;Video;";
    keywords = "video;streaming;";
    scope = "https://www.youtube.com/";
    ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ013";  # Generate with: ulid
  }
];
```

### 2. Generate ULID Identifier

```bash
# Install ulid tool if not available
nix-shell -p ulid

# Generate new ULID
ulid
# Output: 01HQ1Z9J8G7X2K5MNBVWXYZ013

# Copy ULID to pwa-sites.nix
```

### 3. Add Icon (Optional)

```bash
# Download or create icon (512x512 PNG recommended)
curl -o /etc/nixos/assets/pwa-icons/youtube.png \
  https://example.com/youtube-icon.png

# Or use existing icon
```

### 4. Rebuild System

```bash
# Test configuration first
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# Apply configuration
sudo nixos-rebuild switch --flake .#hetzner-sway

# Or for M1 Mac
sudo nixos-rebuild switch --flake .#m1 --impure
```

### 5. Install PWAs

```bash
# Install all configured PWAs
pwa-install-all

# Verify installation
pwa-validate

# List installed PWAs
pwa-list
```

### 6. Launch PWA

```bash
# Via Walker launcher
Meta+D → type "YouTube" → Return

# Via command line
launch-pwa-by-name "YouTube"

# Via desktop menu
# Click Applications → YouTube
```

**Done!** Your PWA is installed and ready to use.

---

## Common Workflows

### Adding Multiple PWAs

```nix
# In pwa-sites.nix
pwaSites = [
  {
    name = "YouTube";
    url = "https://www.youtube.com";
    domain = "youtube.com";
    icon = "file:///etc/nixos/assets/pwa-icons/youtube.png";
    description = "YouTube Video Platform";
    categories = "AudioVideo;Video;";
    keywords = "video;streaming;";
    ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ013";
  }
  {
    name = "Google AI";
    url = "https://www.google.com/search?udm=50";
    domain = "google.com";
    icon = "file:///etc/nixos/assets/pwa-icons/google.png";
    description = "Google AI Search";
    categories = "Network;WebBrowser;";
    keywords = "search;web;ai;";
    ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ014";
  }
  # Add more PWAs...
];
```

Then rebuild and run `pwa-install-all`.

---

### Deploying to New Machine

```bash
# On new machine, just rebuild
cd /etc/nixos
sudo nixos-rebuild switch --flake .#<target>

# Install PWAs
pwa-install-all

# Verify
pwa-validate
```

**No configuration changes needed** - ULIDs and manifests are identical across machines.

---

### Checking Installation Status

```bash
# Validate all PWAs installed
pwa-validate
# Output:
#   ✅ YouTube - installed
#   ✅ Google AI - installed
#   ❌ Gitea - NOT INSTALLED

# List configured vs installed
pwa-list

# Get PWA IDs for reference
pwa-get-ids
```

---

### Updating PWA Metadata

```bash
# Edit pwa-sites.nix - change description, icon, etc.
vi /etc/nixos/shared/pwa-sites.nix

# Rebuild (manifests regenerated automatically)
sudo nixos-rebuild switch --flake .#<target>

# Reinstall PWA with new metadata
firefoxpwa site uninstall <ULID>
pwa-install-all

# Or just rebuild - idempotent
pwa-install-all
```

---

### Removing a PWA

**Note**: Declarative removal not implemented (design choice - manual cleanup safer).

```bash
# Option 1: Remove from configuration (but leaves installed)
# Edit pwa-sites.nix - remove entry
# Rebuild

# Option 2: Manually uninstall
firefoxpwa profile list  # Get ULID
firefoxpwa site uninstall <ULID>

# Option 3: Remove desktop entry only
rm ~/.local/share/applications/FFPWA-<ULID>.desktop
```

---

### Troubleshooting Installation Failures

```bash
# Check firefoxpwa availability
which firefoxpwa
# If not found: nix-shell -p firefoxpwa

# Try manual installation
firefoxpwa site install \
  "file:///nix/store/.../youtube-manifest.json" \
  --document-url "https://www.youtube.com" \
  --name "YouTube" \
  --description "YouTube Video Platform" \
  --icon-url "file:///etc/nixos/assets/pwa-icons/youtube.png"

# Check manifest file
cat /nix/store/.../youtube-manifest.json | jq .

# View installation logs
journalctl --user -u manage-pwas -n 50
```

---

### Verifying 1Password Integration

```bash
# Check 1Password status
pwa-1password-status

# Expected output:
# ✅ Runtime config exists: ~/.config/firefoxpwa/runtime.json

# Verify 1Password extension loaded in PWA
# Launch PWA → Check for 1Password icon in toolbar
```

---

## Advanced Usage

### Custom PWA Scope

Some PWAs need custom scope to avoid navigation outside the app window:

```nix
{
  name = "Azure Portal";
  url = "https://portal.azure.com";
  domain = "azure.com";
  scope = "https://portal.azure.com/";  # Explicit scope
  # Without scope, defaults to https://azure.com/ (too broad)
  ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ015";
}
```

---

### Local Development PWAs

For local development services (localhost):

```nix
{
  name = "Home Assistant";
  url = "http://localhost:8123";
  domain = "localhost";
  icon = "file:///etc/nixos/assets/pwa-icons/home-assistant.png";
  description = "Home Automation Platform";
  scope = "http://localhost:8123/";  # Use HTTP, not HTTPS
  ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ016";
}
```

---

### Workspace Assignment (with i3pm)

PWAs support workspace assignment via app-registry integration:

```nix
# In app-registry-data.nix
"youtube" = {
  name = "YouTube";
  class = "FFPWA-01HQ1Z9J8G7X2K5MNBVWXYZ013";  # Use ULID from pwa-sites.nix
  preferred_workspace = 4;
  launch_via_registry = false;  # Launched via launch-pwa-by-name
  # ... other fields
};
```

Then PWAs will automatically open on assigned workspace via i3pm daemon.

---

### Using Remote Icons

```nix
{
  name = "GitHub";
  url = "https://github.com";
  domain = "github.com";
  icon = "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png";
  # Remote HTTPS icon URL
  ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ017";
}
```

**Note**: Remote icons downloaded during installation, may fail if network unavailable.

---

## File Locations

### Configuration Files

| File | Purpose | Managed By |
|------|---------|------------|
| `/etc/nixos/shared/pwa-sites.nix` | PWA definitions (source of truth) | User (Git) |
| `~/.config/firefoxpwa/config.json` | firefoxpwa configuration | home-manager |
| `~/.config/firefoxpwa/runtime.json` | 1Password integration | home-manager |
| `/nix/store/.../manifest.json` | Web App Manifests | Nix (build) |
| `/etc/nixos/assets/pwa-icons/*.png` | Custom PWA icons | User (Git) |

### Runtime Files

| File | Purpose | Managed By |
|------|---------|------------|
| `~/.local/share/firefox-pwas/*.desktop` | Desktop entries | firefoxpwa |
| `~/.local/share/applications/FFPWA-*.desktop` | Launcher symlinks | home-manager |
| `~/.local/share/icons/hicolor/*/apps/FFPWA-*.png` | Icon cache | firefoxpwa |
| `~/.local/share/firefoxpwa/` | firefoxpwa database | firefoxpwa |

---

## Essential Commands Reference

| Command | Purpose | Example |
|---------|---------|---------|
| `pwa-install-all` | Install all configured PWAs | `pwa-install-all` |
| `pwa-validate` | Verify all PWAs installed | `pwa-validate` |
| `pwa-list` | List configured and installed PWAs | `pwa-list` |
| `pwa-get-ids` | Get ULIDs for installed PWAs | `pwa-get-ids` |
| `pwa-install-guide` | Show installation guide | `pwa-install-guide` |
| `pwa-1password-status` | Check 1Password integration | `pwa-1password-status` |
| `firefoxpwa profile list` | List all PWAs (official tool) | `firefoxpwa profile list` |
| `launch-pwa-by-name` | Launch PWA by name | `launch-pwa-by-name "YouTube"` |

---

## Troubleshooting

### PWA Not Appearing in Walker

**Symptoms**: PWA installed but not visible in Walker launcher

**Fixes**:
```bash
# Restart Elephant service (Walker backend)
systemctl --user restart elephant

# Rebuild icon cache
update-desktop-database ~/.local/share/applications

# Check symlinks exist
ls -la ~/.local/share/applications/FFPWA-*.desktop

# Verify desktop file valid
desktop-file-validate ~/.local/share/firefox-pwas/FFPWA-*.desktop
```

---

### Installation Fails with Manifest Error

**Symptoms**: `pwa-install-all` reports manifest invalid

**Fixes**:
```bash
# Validate manifest JSON
cat /nix/store/.../manifest.json | jq .

# Check manifest URL accessible
curl "file:///nix/store/.../manifest.json"

# Verify icon path exists
ls -la /etc/nixos/assets/pwa-icons/youtube.png

# Try manual installation with detailed errors
firefoxpwa site install "file:///nix/store/.../manifest.json" \
  --document-url "https://youtube.com" \
  --name "YouTube" \
  --description "YouTube" \
  2>&1 | tee install.log
```

---

### ULID Validation Error

**Symptoms**: Build error: "Invalid ULID for YouTube"

**Fixes**:
```bash
# Validate ULID format
echo "01HQ1Z9J8G7X2K5MNBVWXYZ013" | grep -E '^[0-9A-HJKMNP-TV-Z]{26}$'
# Should print the ULID if valid, empty if invalid

# Common mistakes:
# - Contains I, L, O, or U (invalid ULID alphabet)
# - Lowercase letters (must be uppercase)
# - Not exactly 26 characters

# Generate new ULID
ulid
```

---

### Duplicate ULID Error

**Symptoms**: Build error: "Attribute 'sites' already defined"

**Fixes**:
```bash
# Check for duplicate ULIDs in pwa-sites.nix
grep -E 'ulid = "[0-9A-Z]{26}"' /etc/nixos/shared/pwa-sites.nix | sort | uniq -d

# Generate unique ULID for each PWA
for i in {1..5}; do ulid; done
```

---

### PWA Works on One Machine But Not Another

**Symptoms**: PWA installed on machine A, but not on machine B with same config

**Causes**: ULIDs are machine-specific (if not using declarative approach)

**Fixes**:
```bash
# Verify ULIDs are identical in pwa-sites.nix (not generated at build time)
grep ulid /etc/nixos/shared/pwa-sites.nix

# ULIDs should be static strings, not function calls
# ✅ ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ013";
# ❌ ulid = builtins.hashString "sha256" name;

# If ULIDs differ, update pwa-sites.nix with static values
# Commit to Git for cross-machine consistency
```

---

### 1Password Not Working in PWA

**Symptoms**: 1Password icon not visible in PWA toolbar

**Fixes**:
```bash
# Check runtime config exists
pwa-1password-status

# Expected: ✅ Runtime config exists

# If missing, rebuild
sudo nixos-rebuild switch --flake .#<target>

# Restart PWA
# Close PWA → Relaunch via Walker

# Manually enable in existing PWA (if needed)
# Open PWA → about:addons → Check 1Password installed
```

---

### Can't Launch PWA After Installation

**Symptoms**: PWA installed but clicking desktop entry does nothing

**Fixes**:
```bash
# Check desktop entry syntax
desktop-file-validate ~/.local/share/firefox-pwas/FFPWA-*.desktop

# Try launching manually
/nix/store/.../firefoxpwa site launch <ULID>

# Check firefoxpwa database
firefoxpwa profile list

# Reinstall PWA
firefoxpwa site uninstall <ULID>
pwa-install-all
```

---

## Migration from Manual Installation

If you have existing manually-installed PWAs and want to adopt declarative approach:

```bash
# Step 1: Get current PWA IDs
pwa-get-ids > current-pwas.txt

# Step 2: Add ULIDs to pwa-sites.nix using existing IDs
# Edit pwa-sites.nix - use ULIDs from pwa-get-ids output

# Step 3: Rebuild (existing PWAs preserved)
sudo nixos-rebuild switch --flake .#<target>

# Step 4: Verify configuration matches installed PWAs
pwa-validate

# Result: Existing PWAs now managed declaratively
```

---

## Best Practices

### 1. Always Use Static ULIDs

```nix
# ✅ Good: Static ULID committed to Git
ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ013";

# ❌ Bad: Dynamic ULID generation (breaks cross-machine portability)
ulid = builtins.hashString "sha256" name;
```

### 2. Validate Before Rebuild

```bash
# Test configuration before applying
sudo nixos-rebuild dry-build --flake .#<target>

# Check for ULID duplicates
grep ulid /etc/nixos/shared/pwa-sites.nix | sort | uniq -d
```

### 3. Use Descriptive PWA Names

```nix
# ✅ Good: Clear, unique names
name = "GitHub Codespaces";
name = "Azure Portal";

# ❌ Bad: Generic names (conflict risk)
name = "Portal";
name = "App";
```

### 4. Include Icons in Git

```bash
# Store icons in version control for cross-machine deployment
git add /etc/nixos/assets/pwa-icons/youtube.png
git commit -m "Add YouTube PWA icon"
```

### 5. Test on Reference Configuration First

```bash
# Deploy to hetzner-sway first
sudo nixos-rebuild switch --flake .#hetzner-sway
pwa-validate

# Then deploy to other targets
sudo nixos-rebuild switch --flake .#m1 --impure
sudo nixos-rebuild switch --flake .#wsl
```

---

## Examples

### Example: Complete PWA Definition

```nix
{
  name = "ChatGPT Codex";
  url = "https://chatgpt.com/codex";
  domain = "chatgpt.com";
  icon = "file:///etc/nixos/assets/pwa-icons/chatgpt-codex.png";
  description = "ChatGPT Code Assistant";
  categories = "Development;";
  keywords = "ai;chatgpt;codex;coding;assistant;";
  scope = "https://chatgpt.com/codex";
  ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ018";
}
```

### Example: Complete Installation Workflow

```bash
# 1. Add PWA to pwa-sites.nix
vi /etc/nixos/shared/pwa-sites.nix

# 2. Generate ULID
ulid
# Copy to pwa-sites.nix

# 3. Add icon
curl -o /etc/nixos/assets/pwa-icons/chatgpt-codex.png \
  https://example.com/icon.png

# 4. Test configuration
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# 5. Apply configuration
sudo nixos-rebuild switch --flake .#hetzner-sway

# 6. Install PWA
pwa-install-all

# 7. Verify
pwa-validate

# 8. Launch
Meta+D → type "ChatGPT" → Return
```

---

## Next Steps

- **Implementation**: See `tasks.md` for detailed implementation tasks
- **Data Model**: See `data-model.md` for entity definitions
- **API Contracts**: See `contracts/` for function interfaces
- **Architecture**: See `plan.md` for technical context

---

## References

- [firefoxpwa Documentation](https://github.com/filips123/PWAsForFirefox)
- [Web App Manifest Spec](https://www.w3.org/TR/appmanifest/)
- [ULID Specification](https://github.com/ulid/spec)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [home-manager Manual](https://nix-community.github.io/home-manager/)
