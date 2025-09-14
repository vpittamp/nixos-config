# 1Password home-manager configuration
# Manages user-specific 1Password settings
{ config, lib, pkgs, ... }:

{
  # Create 1Password settings directory structure
  # Note: 1Password uses authenticated settings with HMAC tags that cannot be set declaratively
  # These settings must be configured through the 1Password GUI and will persist across rebuilds
  # The settings are stored in ~/.config/1Password/settings/settings.json
  home.activation.onePasswordSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Create 1Password config directories
    mkdir -p $HOME/.config/1Password/settings
    mkdir -p $HOME/.config/1Password/Data
    
    # Important settings that need to be enabled manually in 1Password GUI:
    # 1. Settings → Developer → "Integrate with 1Password CLI" (enables CLI integration)
    # 2. Settings → Security → "Unlock using system authentication service" (enables biometric/system auth)
    # 3. Settings → Developer → "Use SSH agent" (enables SSH key management)
    # 
    # These settings will persist across NixOS rebuilds as they're stored in the user's home directory
    
    # Check if settings exist and provide guidance
    if [ ! -f $HOME/.config/1Password/settings/settings.json ]; then
      echo "=================================================================================="
      echo "1Password First-Time Setup Required:"
      echo ""
      echo "Please open 1Password and configure the following settings:"
      echo "1. Settings → Developer → Enable 'Integrate with 1Password CLI'"
      echo "2. Settings → Security → Enable 'Unlock using system authentication service'"
      echo "3. Settings → Developer → Enable 'Use SSH agent' (for Git authentication)"
      echo ""
      echo "These settings will persist across system rebuilds."
      echo "=================================================================================="
    elif ! grep -q '"developers.cliSharedLockState.enabled": true' $HOME/.config/1Password/settings/settings.json 2>/dev/null; then
      echo "Note: 1Password CLI integration may not be enabled. Check Settings → Developer"
    fi
  '';
  
  # Environment variables for 1Password
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
  };
}
