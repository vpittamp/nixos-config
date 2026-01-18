# GitKraken Configuration Module
# Configures GitKraken with GitHub OAuth, 1Password SSH, and proper terminal integration
{ config, pkgs, lib, ... }:

# Only configure GitKraken on x86_64 systems where it's available
lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
  # Install GitKraken and git-credential-oauth for GitHub authentication
  home.packages = [
    pkgs.gitkraken
    pkgs.git-credential-oauth  # OAuth-based credential helper for GitHub/GitLab/etc
  ];

  # GitKraken configuration files
  # Note: GitKraken stores most settings in binary format, but we can configure some preferences

  # Create GitKraken config directory with git config
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

      # Git credential helpers for OAuth-based authentication
      # This enables seamless GitHub/GitLab authentication in GitKraken
      [credential "https://github.com"]
        helper = oauth

      [credential "https://gitlab.com"]
        helper = oauth

      [credential "https://bitbucket.org"]
        helper = oauth

      # Fallback to 1Password for other hosts
      [credential]
        helper = cache --timeout=7200
    '';
  };

  # GitKraken preferences file
  # This configures terminal and other settings
  home.file.".gitkraken/preferences.json" = {
    text = builtins.toJSON {
      terminal = {
        command = "${pkgs.ghostty}/bin/ghostty";
        args = [ "-e" "bash" "--login" "-c" "cd %d && exec bash" ];
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

      # Use system git config for authentication
      authentication = {
        useSystemGitConfig = true;
      };

      # GitHub integration preferences
      github = {
        useSSH = true;  # Prefer SSH URLs (works with 1Password agent)
      };
    };
  };

  # Environment variables for GitKraken
  home.sessionVariables = {
    # Ensure GitKraken can find the 1Password SSH agent
    GITKRAKEN_SSH_AUTH_SOCK = "/home/vpittamp/.1password/agent.sock";
    # Use system git for operations (which is configured with 1Password and OAuth)
    GITKRAKEN_USE_SYSTEM_GIT = "1";
  };

  # Create a wrapper script to launch GitKraken with proper environment
  home.file.".local/bin/gitkraken-wrapper" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash

      # Set up 1Password SSH agent
      export SSH_AUTH_SOCK=~/.1password/agent.sock

      # Ensure git-credential-oauth is in PATH for GitHub authentication
      export PATH="${pkgs.git-credential-oauth}/bin:$PATH"

      # Launch GitKraken with proper environment
      exec ${pkgs.gitkraken}/bin/gitkraken "$@"
    '';
  };

  # Desktop entry to use our wrapper
  xdg.desktopEntries.gitkraken = {
    name = "GitKraken";
    comment = "Git GUI client with GitHub OAuth and 1Password SSH integration";
    exec = "${config.home.homeDirectory}/.local/bin/gitkraken-wrapper %U";
    icon = "gitkraken";
    terminal = false;
    type = "Application";
    categories = [ "Development" "RevisionControl" ];
    mimeType = [
      "x-scheme-handler/gitkraken"
      "x-scheme-handler/git"
    ];
  };

  # Configure git-credential-oauth for the main git config as well
  # This ensures GitHub OAuth works both in GitKraken and CLI git
  programs.git.extraConfig = {
    credential = {
      "https://github.com" = {
        helper = "oauth";
      };
      "https://gitlab.com" = {
        helper = "oauth";
      };
    };
  };
}
