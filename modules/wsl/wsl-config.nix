# WSL-specific configuration module
# This should only be imported in WSL configurations, not in native Linux
{ config, lib, pkgs, ... }:

{
  # WSL-specific packages
  environment.systemPackages = with pkgs; [
    wslu  # WSL utilities
  ];

  # WSL-specific environment variables
  environment.sessionVariables = {
    # Use WSL Docker Desktop if available
    DOCKER_HOST = lib.mkDefault "unix:///mnt/wsl/docker-desktop/shared-sockets/guest-services/docker.proxy.sock";
  };

  # WSL-specific shell configuration
  programs.bash.interactiveShellInit = lib.mkAfter ''
    # WSL-specific DISPLAY configuration
    if [ -n "$WSL_DISTRO_NAME" ] && [ -z "$DISPLAY" ]; then
      export DISPLAY=:0
    fi
    
    # WSL Docker Desktop integration
    if [ -n "$WSL_DISTRO_NAME" ]; then
      # Check if Docker Desktop socket exists
      if [ -S "/mnt/wsl/docker-desktop/shared-sockets/guest-services/docker.proxy.sock" ]; then
        export DOCKER_HOST="unix:///mnt/wsl/docker-desktop/shared-sockets/guest-services/docker.proxy.sock"
      fi
    fi
    
    # WSL clipboard integration
    pbcopy_wsl() {
      local input
      if [ -t 0 ]; then
        input="$*"
      else
        input="$(cat)"
      fi
      # Try wl-copy first (WSLg)
      if command -v wl-copy >/dev/null 2>&1; then
        printf "%s" "$input" | wl-copy --type text/plain 2>/dev/null
      # Fall back to Windows clipboard
      else
        printf "%s" "$input" | /mnt/c/Windows/System32/clip.exe
      fi
    }
    
    pbpaste_wsl() {
      # Try wl-paste first (WSLg)
      if command -v wl-paste >/dev/null 2>&1; then
        wl-paste --no-newline 2>/dev/null | sed 's/\r$//'
      # Fall back to Windows clipboard
      else
        /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -command 'Get-Clipboard' | sed 's/\r$//'
      fi
    }
    
    # Override clipboard functions for WSL
    alias pbcopy='pbcopy_wsl'
    alias pbpaste='pbpaste_wsl'
  '';

  # WSL-specific aliases
  programs.bash.shellAliases = {
    winhome = "cd /mnt/c/Users/$USER/";
    windesktop = "cd /mnt/c/Users/$USER/Desktop";
    windocs = "cd /mnt/c/Users/$USER/Documents";
  };
}