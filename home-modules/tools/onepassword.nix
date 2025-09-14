# 1Password home-manager configuration
# Manages user-specific 1Password settings
{ config, lib, pkgs, ... }:

{
  # Create 1Password settings directory and default settings
  # This only creates settings if they don't exist, preserving user changes
  home.activation.onePasswordSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Create 1Password config directory
    mkdir -p $HOME/.config/1Password/settings
    
    # Create default settings only if file doesn't exist
    if [ ! -f $HOME/.config/1Password/settings/settings.json ]; then
      cat > $HOME/.config/1Password/settings/settings.json << 'EOF'
{
  "security.authenticatedUnlock.enabled": true,
  "security.authenticatedUnlock.method": "systemAuthentication"
}
EOF
      echo "Created default 1Password settings with system authentication enabled"
    fi
  '';
  
  # Environment variables for 1Password
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
  };
}
