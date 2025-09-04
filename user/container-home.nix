{ config, pkgs, lib, ... }:

let
  # Import user packages
  userPackages = import ./packages.nix { inherit pkgs lib; };
  
  # Select package profile based on environment variable
  packageProfile = 
    let prof = builtins.getEnv "CONTAINER_PROFILE";
    in if prof == "minimal" then userPackages.minimal
       else if prof == "development" then userPackages.development
       else userPackages.essential;  # default to essential
in
{
  # Import the starship configuration
  imports = [ ./container-starship.nix ];

  # Basic home configuration
  home.username = builtins.getEnv "USER";
  home.homeDirectory = builtins.getEnv "HOME";
  home.stateVersion = "24.05";
  
  # Install user packages
  home.packages = packageProfile;
  
  # Enable home-manager
  programs.home-manager.enable = true;
  
  # Git configuration
  programs.git = {
    enable = true;
    userName = "Container User";
    userEmail = "user@container.local";
    
    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
      
      # Better diffs
      diff.algorithm = "histogram";
      merge.conflictStyle = "zdiff3";
      
      # Aliases
      alias = {
        st = "status -sb";
        co = "checkout";
        br = "branch";
        ci = "commit";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        visual = "!gitk";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      };
    };
  };
  
  # Bash configuration with prompt
  programs.bash = {
    enable = true;
    enableCompletion = true;
    
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      PAGER = "less";
      LESS = "-R";
    };
    
    shellAliases = {
      ll = "ls -l";
      la = "ls -la";
      ".." = "cd ..";
      "..." = "cd ../..";
      
      # Neovim aliases
      vim = "nvim";
      vi = "nvim";
      
      # Use eza if available
      ls = "eza --icons=auto";
      l = "eza -l --icons=auto";
      tree = "eza --tree --icons=auto";
      
      # Git shortcuts
      g = "git";
      gs = "git status";
      gp = "git pull";
      gc = "git commit";
      ga = "git add";
      
      # Nix shortcuts
      hm = "home-manager";
      hms = "home-manager switch --impure";
      hme = "home-manager edit";
      hmn = "home-manager news";
    };
    
    initExtra = ''
      # Better history
      export HISTCONTROL=ignoredups:erasedups
      export HISTSIZE=10000
      export HISTFILESIZE=10000
      shopt -s histappend
      
      # Better directory navigation
      shopt -s autocd
      shopt -s cdspell
      shopt -s dirspell
      
      # Enable ** for recursive globbing
      shopt -s globstar
      
      # Update window size after each command
      shopt -s checkwinsize
      
      # Colored GCC warnings and errors
      export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
      
      # Set up fzf key bindings and fuzzy completion
      if command -v fzf >/dev/null 2>&1; then
        eval "$(fzf --bash)"
      fi
      
      # Initialize zoxide for better cd
      if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init bash)"
        alias cd="z"
      fi
      
      # Create a simple function to switch profiles
      switch-profile() {
        local profile="$1"
        if [[ -z "$profile" ]]; then
          echo "Usage: switch-profile [minimal|essential|development]"
          echo "Current profile: ''${CONTAINER_PROFILE:-essential}"
          return 1
        fi
        export CONTAINER_PROFILE="$profile"
        home-manager switch --impure
      }
    '';
  };
  
  # Tmux configuration
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    historyLimit = 10000;
    keyMode = "vi";
    mouse = true;
    prefix = "C-a";
    baseIndex = 1;
    escapeTime = 0;
    
    # Tmux plugins from nixpkgs
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      mode-indicator
      {
        plugin = resurrect;
        extraConfig = "set -g @resurrect-strategy-nvim 'session'";
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '60' # minutes
        '';
      }
    ];
    
    extraConfig = ''
      # Split panes with | and -
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      
      # Vim-style pane navigation
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      
      # Resize panes with HJKL
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5
      
      # Status bar styling (Catppuccin Mocha theme)
      set -g status-style 'bg=#1e1e2e fg=#cdd6f4'
      set -g status-left '#[fg=#89b4fa,bold] #S #[fg=#cdd6f4]| '
      set -g status-right '#{tmux_mode_indicator} #[fg=#f9e2af]%H:%M '
      set -g status-left-length 30
      
      # Window status
      setw -g window-status-format '#[fg=#585b70] #I:#W '
      setw -g window-status-current-format '#[fg=#89b4fa,bold] #I:#W '
      
      # Active pane border
      set -g pane-active-border-style 'fg=#89b4fa'
      set -g pane-border-style 'fg=#313244'
      
      # Copy mode
      bind Enter copy-mode
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-selection-and-cancel
      
      # Reload config
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"
    '';
  };
  
  # Sesh - Smart session manager for tmux
  programs.sesh = {
    enable = true;
    enableAlias = true;  # Enable 's' alias
    enableTmuxIntegration = true;
    icons = true;
    
    settings = {
      default_session = {
        name = "main";
        path = "~";
        startup_command = "nvim";
      };
      
      # Configure startup windows
      startup_scripts = [
        {
          session_name = "config";
          script_path = "~/.config";
        }
      ];
    };
  };
  
  # Neovim - installed as package, not via programs.neovim to avoid plugin issues
  # The programs.neovim module tries to build vim plugins even when empty
  # So we install neovim-unwrapped directly (no wrappers, no plugins)
  home.packages = [ pkgs.neovim-unwrapped ];
  
  # Neovim aliases are already in bash.shellAliases above
  
  # Neovim configuration via init files
  home.file.".config/nvim/init.lua".text = ''
      -- Bootstrap lazy.nvim plugin manager
      local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
      if not vim.loop.fs_stat(lazypath) then
        vim.fn.system({
          "git",
          "clone",
          "--filter=blob:none",
          "https://github.com/folke/lazy.nvim.git",
          "--branch=stable",
          lazypath,
        })
      end
      vim.opt.rtp:prepend(lazypath)
      
      -- Plugin specifications
      local plugins = {
        -- Essential plugins
        { "tpope/vim-sensible" },
        { "tpope/vim-surround" },
        { "tpope/vim-commentary" },
        { "tpope/vim-fugitive" },
        
        -- Language support
        { "LnL7/vim-nix" },
        
        -- UI improvements
        {
          "itchyny/lightline.vim",
          config = function()
            vim.g.lightline = { colorscheme = "jellybeans" }
          end,
        },
      }
      
      -- Setup lazy.nvim with plugins
      require("lazy").setup(plugins, {
        -- Store plugins in user directory (writable in containers)
        root = vim.fn.stdpath("data") .. "/lazy",
        -- Don't change the RTP (let Nix handle that)
        performance = {
          rtp = {
            reset = false,
          },
        },
      })
      
      -- Basic settings
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      
      -- Enable syntax highlighting
      vim.cmd('syntax enable')
      
      -- Better search
      vim.opt.ignorecase = true
      vim.opt.smartcase = true
      vim.opt.incsearch = true
      vim.opt.hlsearch = true
      
      -- Show matching brackets
      vim.opt.showmatch = true
      
      -- Enable mouse
      vim.opt.mouse = 'a'
      
      -- Better colors for dark terminals
      vim.opt.background = 'dark'
      
      -- Status line always visible
      vim.opt.laststatus = 2
      
      -- Leader key
      vim.g.mapleader = ' '
      
      -- Quick save
      vim.keymap.set('n', '<leader>w', ':w<CR>')
      
      -- Quick quit
      vim.keymap.set('n', '<leader>q', ':q<CR>')
  '';
  
  # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableBashIntegration = true;
  };
  
  # FZF for fuzzy finding
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    tmux = {
      enableShellIntegration = true;  # Required for sesh tmux integration
    };
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--inline-info"
      "--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8"
      "--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc"
      "--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
    ];
  };
  
  # Bat (better cat)
  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
      style = "numbers,changes";
    };
  };
  
  # Zoxide (better cd)
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };
  
  # Eza (better ls)  
  programs.eza = {
    enable = true;
    enableBashIntegration = true;
    icons = "auto";
    git = true;
  };
  
  # Ripgrep configuration
  programs.ripgrep = {
    enable = true;
    arguments = [
      "--max-columns=150"
      "--max-columns-preview"
      "--smart-case"
    ];
  };
}