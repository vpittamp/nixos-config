# GitKraken Configuration Module
{ config, pkgs, lib, ... }:

{
  # GitKraken configuration files
  # Note: GitKraken has limited configuration options via files
  # Most settings are stored in binary format, but we can configure some preferences
  
  # Create GitKraken config directory
  home.file.".gitkraken/.gitconfig" = {
    text = ''
      # GitKraken global git config
      # This is separate from the system git config
      [user]
        name = Vinod Pittampalli
        email = vinod@pittampalli.com
        signingkey = ""  # Disable signing here since we handle it via 1Password
      
      [commit]
        gpgsign = false  # We disabled commit signing per user preference
      
      [core]
        sshCommand = ssh -o IdentityAgent=~/.1password/agent.sock
        editor = ${pkgs.neovim}/bin/nvim
        
      [credential]
        helper = !${pkgs._1password-gui}/bin/op-ssh-sign
    '';
  };
  
  # GitKraken preferences file
  # This configures terminal and other settings
  home.file.".gitkraken/preferences.json" = {
    text = builtins.toJSON {
      terminal = {
        command = "${pkgs.kdePackages.konsole}/bin/konsole";
        args = [ "--workdir" "%d" ];
      };
      
      ssh = {
        useLocalAgent = true;
        agentPath = "/home/vpittamp/.1password/agent.sock";
      };
      
      externalEditor = {
        command = "${pkgs.vscode}/bin/code";
        args = [ "%file" ];
      };
      
      diffTool = {
        command = "${pkgs.vscode}/bin/code";
        args = [ "--diff" "%file1" "%file2" ];
      };
      
      mergeTool = {
        command = "${pkgs.vscode}/bin/code";
        args = [ "--merge" "%file1" "%file2" "%base" "%output" ];
      };
      
      general = {
        autoFetchInterval = 10;
        showRemoteBranches = true;
        useTabs = false;
        tabSize = 2;
      };
      
      authentication = {
        useSystemGitConfig = true;
      };
    };
  };
  
  # Environment variables for GitKraken
  home.sessionVariables = {
    # Ensure GitKraken can find the 1Password SSH agent
    GITKRAKEN_SSH_AUTH_SOCK = "/home/vpittamp/.1password/agent.sock";
    # Use system git for operations (which is configured with 1Password)
    GITKRAKEN_USE_SYSTEM_GIT = "1";
  };
  
  # Create a wrapper script to launch GitKraken with proper environment
  home.file.".local/bin/gitkraken-wrapper" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      
      # Set up 1Password SSH agent
      export SSH_AUTH_SOCK=~/.1password/agent.sock
      
      # Launch GitKraken with proper environment
      exec ${pkgs.gitkraken}/bin/gitkraken "$@"
    '';
  };
  
  # Desktop entry to use our wrapper
  xdg.desktopEntries.gitkraken = {
    name = "GitKraken";
    comment = "Git GUI client with 1Password integration";
    exec = "%h/.local/bin/gitkraken-wrapper %U";
    icon = "gitkraken";
    terminal = false;
    type = "Application";
    categories = [ "Development" "RevisionControl" ];
    mimeType = [ 
      "x-scheme-handler/gitkraken"
      "x-scheme-handler/git"
    ];
  };
}