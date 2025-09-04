#!/usr/bin/env bash
# Quick fix for home-manager conflicts in containers

# Backup existing files
echo "Backing up existing shell configuration files..."
[ -f ~/.bashrc ] && mv ~/.bashrc ~/.bashrc.backup
[ -f ~/.profile ] && mv ~/.profile ~/.profile.backup  
[ -f ~/.bash_profile ] && mv ~/.bash_profile ~/.bash_profile.backup

# Apply home-manager configuration
echo "Applying home-manager configuration..."
home-manager switch

echo "Done! Your environment is now configured."
echo ""
echo "Run 'exec bash' to reload your shell with the new configuration."