{ config, pkgs, lib, ... }:

{
  # Konsole workaround: ensure bash initialization works properly
  # Konsole by default doesn't start a login shell, which can cause issues
  # with home-manager's bash configuration not loading properly
  
  # Create a wrapper script that ensures proper initialization
  home.file.".local/share/konsole/Shell.profile" = {
    text = ''
      [Appearance]
      ColorScheme=Catppuccin-Mocha
      Font=FiraCode Nerd Font,11,-1,5,50,0,0,0,0,0
      
      [General]
      Name=Shell
      Parent=FALLBACK/
      # Force bash to act as a login shell to load .bash_profile
      # which then sources .bashrc with all our configurations
      Command=/run/current-system/sw/bin/bash -l
      
      [Scrolling]
      HistoryMode=2
      ScrollBarPosition=2
    '';
  };
  
  # Alternative: Add an alias to force reload in new terminals
  programs.bash.shellAliases = lib.mkIf config.programs.bash.enable {
    konsole-init = "source ~/.bashrc && eval \"$(starship init bash)\"";
  };
  
  # Ensure STARSHIP_SHELL is set early
  home.sessionVariables = {
    STARSHIP_SHELL = "bash";
  };
}