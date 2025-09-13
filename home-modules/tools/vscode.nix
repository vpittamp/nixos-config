{ config, pkgs, lib, ... }:

{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    
    # Extensions for development and 1Password integration
    extensions = with pkgs.vscode-extensions; [
      # 1Password extension
      # Note: The 1Password extension needs to be installed manually
      # from the VSCode marketplace as "1Password"
      # Extension ID: 1Password.op-vscode
      
      # Development essentials
      ms-vscode-remote.remote-ssh
      ms-vscode-remote.remote-containers
      # ms-vscode.remote-server  # May not be available in nixpkgs
      
      # Git integration
      eamodio.gitlens
      mhutchie.git-graph
      
      # Nix support
      bbenoist.nix
      jnoortheen.nix-ide
      
      # General development
      esbenp.prettier-vscode
      dbaeumer.vscode-eslint
      ms-python.python
      golang.go
      rust-lang.rust-analyzer
      
      # Theme and UI
      pkief.material-icon-theme
      zhuangtongfa.material-theme
      
      # Productivity
      vscodevim.vim
      streetsidesoftware.code-spell-checker
    ];
    
    # User settings for VSCode
    userSettings = {
      # 1Password integration settings
      "1password.items.cacheValues" = true;
      "1password.items.useSecretReferences" = true;
      "1password.editor.suggestStorage" = true;
      "1password.items.passwordRecipe" = {
        "length" = 32;
        "includeSymbols" = true;
        "includeNumbers" = true;
        "includeUppercase" = true;
        "includeLowercase" = true;
      };
      
      # Terminal integration
      "terminal.integrated.defaultProfile.linux" = "bash";
      "terminal.integrated.profiles.linux" = {
        "bash" = {
          "path" = "${pkgs.bashInteractive}/bin/bash";
          "args" = [ "--login" ];
          "icon" = "terminal-bash";
          "env" = {
            "SSH_AUTH_SOCK" = "$HOME/.1password/agent.sock";
          };
        };
      };
      
      # SSH configuration for 1Password
      "remote.SSH.configFile" = "~/.ssh/config";
      "remote.SSH.showLoginTerminal" = true;
      "remote.SSH.useLocalServer" = false;
      
      # Git integration
      "git.enableSmartCommit" = true;
      "git.autofetch" = true;
      "git.confirmSync" = false;
      
      # Editor settings
      "editor.fontSize" = 14;
      "editor.fontFamily" = "'JetBrains Mono', 'Fira Code', monospace";
      "editor.fontLigatures" = true;
      "editor.formatOnSave" = true;
      "editor.minimap.enabled" = false;
      "editor.rulers" = [ 80 120 ];
      "editor.renderWhitespace" = "trailing";
      
      # File associations
      "files.associations" = {
        "*.nix" = "nix";
        "flake.lock" = "json";
      };
      
      # Workspace
      "workbench.colorTheme" = "Material Theme Darker";
      "workbench.iconTheme" = "material-icon-theme";
      "workbench.startupEditor" = "none";
      
      # Vim settings (if using VSCodeVim)
      "vim.useSystemClipboard" = true;
      "vim.hlsearch" = true;
      "vim.insertModeKeyBindings" = [
        {
          "before" = [ "j" "j" ];
          "after" = [ "<Esc>" ];
        }
      ];
      
      # Nix IDE settings
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "nil";
      "nix.serverSettings" = {
        "nil" = {
          "formatting" = {
            "command" = [ "nixpkgs-fmt" ];
          };
        };
      };
    };
    
    # Keybindings
    keybindings = [
      {
        key = "ctrl+shift+p";
        command = "workbench.action.showCommands";
      }
      {
        key = "ctrl+shift+o";
        command = "1password.open";
        when = "editorTextFocus";
      }
      {
        key = "ctrl+shift+l";
        command = "1password.generate";
        when = "editorTextFocus";
      }
      {
        key = "ctrl+shift+s";
        command = "1password.save";
        when = "editorTextFocus && editorHasSelection";
      }
    ];
  };
  
  # Create VSCode settings directory and SSH config for 1Password
  home.file.".vscode-server/data/Machine/settings.json" = {
    text = builtins.toJSON config.programs.vscode.userSettings;
  };
  
  # Environment variables for VSCode
  home.sessionVariables = {
    # Use 1Password SSH agent in VSCode terminal
    VSCODE_SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
  };
}