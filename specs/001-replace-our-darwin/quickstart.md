# Quickstart: Nix-Darwin Configuration

**Feature**: Migrate Darwin Home-Manager to Nix-Darwin
**Date**: 2025-10-13
**Audience**: Developers migrating from standalone home-manager to nix-darwin

## Prerequisites

Before starting, ensure you have:

- ✅ macOS 12.0 (Monterey) or newer
- ✅ Nix package manager 2.18+ with flakes enabled
- ✅ XCode Command Line Tools: `xcode-select --install`
- ✅ Admin/sudo privileges on your Mac
- ✅ Current home-manager Darwin configuration working (if migrating)
- ✅ Git repository access (for nixos-config)

**Check Your Setup**:
```bash
# Check macOS version
sw_vers -productVersion  # Should be >= 12.0

# Check Nix version
nix --version  # Should be >= 2.18

# Check if flakes are enabled
nix flake metadata  # Should not error

# Check XCode CLI tools
xcode-select -p  # Should show /Library/Developer/CommandLineTools
```

## Quick Start (New Installation)

### Step 1: Install nix-darwin

```bash
# Navigate to your nixos-config repository
cd ~/nixos-config  # or wherever your config is

# The configuration is already prepared in this branch
# Just need to build and switch
```

### Step 2: Initial Build

```bash
# Build the configuration (doesn't activate yet)
nix build .#darwinConfigurations.darwin.system --extra-experimental-features "nix-command flakes"

# This creates a 'result' symlink to the built system
ls -l result
```

### Step 3: Activate nix-darwin

```bash
# Run the activation script
./result/sw/bin/darwin-rebuild switch --flake .#darwin

# This will:
# - Install nix-darwin command
# - Switch system profile
# - Activate home-manager
# - Apply macOS defaults
```

### Step 4: Verify Installation

```bash
# Check system profile
ls -l /run/current-system

# Check system packages
which git vim curl  # Should be in /run/current-system/sw/bin

# Check darwin-rebuild is available
which darwin-rebuild  # Should be in PATH

# Check home-manager activation
ls -l ~/.nix-profile

# Test your shell configuration
bash -l  # Should load your custom config
```

### Step 5: Future Rebuilds

```bash
# After initial setup, use darwin-rebuild directly
darwin-rebuild switch --flake .#darwin

# Optional: dry-run to see what would change
darwin-rebuild --dry-run switch --flake .#darwin
```

## Quick Start (Migration from Home-Manager Only)

### Before Migration

**Backup Your Current Setup**:
```bash
# List current home-manager generation
home-manager generations | head -5

# Note current profile path
ls -l ~/.nix-profile

# Backup home-manager config (optional)
cp -r ~/.config/home-manager ~/.config/home-manager.backup
```

### Migration Steps

#### Step 1: Verify Current State

```bash
# Ensure current home-manager works
home-manager switch --flake .#darwin

# List installed packages
nix-store -q --requisites ~/.nix-profile | wc -l
```

#### Step 2: Build New Configuration

```bash
# Build nix-darwin configuration
nix build .#darwinConfigurations.darwin.system
```

#### Step 3: Switch to nix-darwin

```bash
# Activate nix-darwin (this integrates home-manager)
./result/sw/bin/darwin-rebuild switch --flake .#darwin

# Note: This replaces standalone home-manager
```

#### Step 4: Verify Migration

```bash
# Check system packages (NEW)
which git  # Should be in /run/current-system/sw/bin

# Check user packages (UNCHANGED)
ls ~/.nix-profile/bin

# Check shell config (UNCHANGED)
echo $PS1  # Should show starship prompt

# Check tmux config (UNCHANGED)
tmux new-session -d && tmux kill-session

# Check neovim config (UNCHANGED)
nvim --version
```

#### Step 5: Clean Up (Optional)

```bash
# Old home-manager generations can remain
# They won't interfere with nix-darwin

# To clean up old generations:
nix-collect-garbage -d

# To remove old home-manager profile (CAREFUL):
# rm ~/.local/state/nix/profiles/home-manager*
# Only do this if everything works!
```

## Common Tasks

### Add a System Package

```nix
# Edit: configurations/darwin.nix

environment.systemPackages = with pkgs; [
  # ... existing packages ...
  htop  # Add your package here
];
```

```bash
# Rebuild and activate
darwin-rebuild switch --flake .#darwin
```

### Add a User Package

```nix
# Edit: home-darwin.nix or home-modules/profiles/darwin-home.nix

home.packages = with pkgs; [
  # ... existing packages ...
  ripgrep  # Add your package here
];
```

```bash
# Rebuild (nix-darwin now manages home-manager)
darwin-rebuild switch --flake .#darwin
```

### Modify macOS System Preferences

```nix
# Edit: configurations/darwin.nix

system.defaults = {
  dock.autohide = true;  # Auto-hide dock
  finder.ShowPathbar = true;  # Show path bar in Finder
  NSGlobalDomain.InitialKeyRepeat = 15;  # Faster key repeat
};
```

```bash
# Rebuild and log out/in for changes to take full effect
darwin-rebuild switch --flake .#darwin
```

### Configure SSH for 1Password

Already configured! Just verify:

```bash
# Check SSH config
cat ~/.ssh/config | grep IdentityAgent

# Should show:
# IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

# Test SSH agent
ssh-add -l  # Should list keys from 1Password
```

### Update Packages

```bash
# Update flake inputs (nixpkgs, home-manager, nix-darwin)
nix flake update

# Rebuild with updated packages
darwin-rebuild switch --flake .#darwin
```

### Rollback Configuration

```bash
# List generations
darwin-rebuild --list-generations

# Rollback to previous generation
darwin-rebuild rollback

# Or switch to specific generation
sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation <number>
./result/activate
```

## Troubleshooting

### Problem: darwin-rebuild not found

**Solution**:
```bash
# Add to PATH temporarily
export PATH="/run/current-system/sw/bin:$PATH"

# Or use full path for initial activation
./result/sw/bin/darwin-rebuild switch --flake .#darwin
```

### Problem: Build fails with "permission denied"

**Solution**:
```bash
# Ensure you have sudo privileges
sudo -v

# Run with sudo if needed
sudo darwin-rebuild switch --flake .#darwin
```

### Problem: Conflicting files during home-manager activation

**Solution**:
```bash
# Home-manager creates backups automatically
# Check for .backup files
ls -la ~ | grep backup

# If files conflict, remove or move them
mv ~/.bashrc ~/.bashrc.old

# Retry
darwin-rebuild switch --flake .#darwin
```

### Problem: macOS defaults not applying

**Solution**:
```bash
# Some defaults require logout
# Log out and log back in

# Or restart Dock and Finder
killall Dock Finder

# Check if default was written
defaults read com.apple.dock autohide
```

### Problem: 1Password SSH agent not working

**Solution**:
```bash
# Ensure 1Password is running
open -a "1Password"

# Check SSH agent socket exists
ls -la ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock

# Verify SSH config
grep IdentityAgent ~/.ssh/config

# Test with explicit socket path
SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ssh-add -l
```

### Problem: Bash version still 3.2 (macOS default)

**Solution**:
```bash
# Check if Nix bash is available
~/.nix-profile/bin/bash --version  # Should show 5.3+

# Add Nix bash to allowed shells
sudo sh -c 'echo "$HOME/.nix-profile/bin/bash" >> /etc/shells'

# Change default shell
chsh -s $HOME/.nix-profile/bin/bash

# Restart terminal
```

### Problem: Colors not working in terminal

**Solution**:
```bash
# Check TERM variable
echo $TERM  # Should be xterm-256color or similar

# Source bashrc manually
source ~/.bashrc

# Check starship is running
which starship
starship --version

# Restart terminal with new config
```

### Problem: Docker commands not working

**Solution**:
```bash
# Ensure Docker Desktop is running
open -a "Docker"

# Check Docker socket
ls -la /var/run/docker.sock

# Test Docker
docker ps

# If not in PATH, add temporarily
export PATH="/usr/local/bin:$PATH"
```

## Verification Checklist

After installation or migration, verify:

- [ ] System packages available: `which git vim curl htop tmux`
- [ ] User packages available: `which bat eza fzf`
- [ ] Bash 5.3 active: `bash --version`
- [ ] Starship prompt showing: `echo $PS1`
- [ ] Tmux configuration working: `tmux new -s test`
- [ ] Neovim configuration working: `nvim --version`
- [ ] Git signing configured: `git config --get commit.gpgsign`
- [ ] SSH agent working: `ssh-add -l`
- [ ] 1Password CLI working: `op --version`
- [ ] Docker commands working: `docker ps`
- [ ] macOS defaults applied: `defaults read com.apple.dock`
- [ ] darwin-rebuild available: `which darwin-rebuild`

## Next Steps

Once your basic configuration is working:

1. **Customize System Packages**: Add tools you need in `configurations/darwin.nix`
2. **Configure macOS Defaults**: Tune `system.defaults` to your preferences
3. **Add User Packages**: Extend `home-darwin.nix` with your tools
4. **Set Up Services**: Configure launchd services if needed
5. **Document Changes**: Update CLAUDE.md with any Darwin-specific notes

## Reference

- **Configuration File**: `configurations/darwin.nix`
- **Home Profile**: `home-darwin.nix` (imported by nix-darwin)
- **System Profile**: `/run/current-system`
- **User Profile**: `~/.nix-profile`
- **Generations**: `/nix/var/nix/profiles/system-*-link`

## Getting Help

- **nix-darwin Manual**: https://daiderd.com/nix-darwin/manual/
- **home-manager Manual**: https://nix-community.github.io/home-manager/
- **NixOS Discourse**: https://discourse.nixos.org/
- **Nix Darwin GitHub**: https://github.com/LnL7/nix-darwin
- **Project README**: `/etc/nixos/README.md`
- **Project Guide**: `/etc/nixos/CLAUDE.md`

## Tips

- **Always check before switching**: Use `--dry-run` to preview changes
- **Keep generations**: Don't delete old generations immediately - they're your rollback safety net
- **Test incrementally**: Add packages one at a time to identify issues quickly
- **Document customizations**: Add comments to .nix files explaining non-obvious choices
- **Update regularly**: Run `nix flake update` weekly to get security fixes
- **Use direnv**: Install and configure direnv for per-project Nix shells

## Performance Tips

- **Use binary cache**: Ensure `substituters` are configured in `nix.settings`
- **Enable auto-optimisation**: Set `nix.settings.auto-optimise-store = true`
- **Regular garbage collection**: Set up `nix.gc.automatic = true`
- **Use --option builders**: For parallel builds on multi-core Macs
- **Pre-download**: Run `nix build` before `switch` to avoid activation delays

## Security Best Practices

- **Never commit secrets**: Use 1Password, not .nix files
- **Review package changes**: Check `nix flake update` diff before applying
- **Keep backups**: Export 1Password vault, backup ~/.ssh/ config
- **Use trusted sources**: Only add well-known cachix caches
- **Regular updates**: Keep Nix, nix-darwin, and packages up-to-date
