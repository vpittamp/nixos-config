{ config, lib, pkgs, ... }:
{
  # Use unwrapped neovim to avoid Nix plugin system issues in containers
  home.packages = with pkgs; [
    neovim-unwrapped  # Pure neovim without Nix wrapping
    gh                # GitHub CLI (Octo + gh-dash)
    gh-dash           # TUI for PR triage
    # Dependencies for plugins
    ripgrep           # For telescope
    fd                # For telescope file finder
    nodejs            # For various language servers
    nodePackages_latest.typescript-language-server  # LSP: TypeScript/JavaScript
    nodePackages_latest.typescript                  # Provides tsserver runtime
    pyright                                          # LSP: Python
    nil                                              # LSP: Nix
    lua-language-server                              # LSP: Lua
    nixpkgs-fmt                                      # Formatter used by nil_ls
    (writeShellScriptBin "nvim-telescope-picker" ''
      set -euo pipefail

      # Optional working directory override (first argument)
      if [ "$#" -gt 0 ] && [ -d "$1" ]; then
        export NVIM_STARTUP_PICKER_CWD="$1"
        cd "$1"
        shift
      fi
      if [ -z "''${NVIM_STARTUP_PICKER_CWD:-}" ]; then
        export NVIM_STARTUP_PICKER_CWD="$PWD"
      fi

      SOCKET_DIR="''${XDG_RUNTIME_DIR:-/tmp}"
      SOCKET_USER="''${USER:-''${LOGNAME:-nvim}}"
      SOCKET_SAFE=$(printf '%s' "$SOCKET_USER" | tr -c '[:alnum:]_.-' '_')
      SOCKET_PATH="$SOCKET_DIR/nvim-$SOCKET_SAFE.sock"

      server_is_alive() {
        [ -S "$SOCKET_PATH" ] && ${neovim-unwrapped}/bin/nvim --server "$SOCKET_PATH" --remote-expr "1" >/dev/null 2>&1
      }

      if ! server_is_alive; then
        # Clean up stale sockets
        rm -f "$SOCKET_PATH"
        export NVIM_LISTEN_ADDRESS="$SOCKET_PATH"
        export NVIM_STARTUP_PICKER="find_files"
        exec ${neovim-unwrapped}/bin/nvim --listen "$SOCKET_PATH" "$@"
      else
        # Attach terminal UI to existing server
        exec ${neovim-unwrapped}/bin/nvim --server "$SOCKET_PATH" --remote-ui
      fi
    '')
  ];

  # Set up Neovim as default editor
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # Aliases for vim/vi
  home.shellAliases = {
    vim = "nvim";
    vi = "nvim";
  };

  # Create desktop file for Neovim (for xdg-open integration)
  xdg.desktopEntries.nvim = {
    name = "Neovim";
    genericName = "Text Editor";
    comment = "Edit text files";
    exec = "ghostty -e nvim %F";
    terminal = false;
    categories = [ "Utility" "TextEditor" ];
    mimeType = [
      "text/plain"
      "text/x-shellscript"
      "text/x-python"
      "text/x-c"
      "text/x-c++"
      "text/x-java"
      "text/x-rust"
      "text/x-go"
      "text/x-makefile"
      "text/markdown"
      "text/x-markdown"
      "application/json"
      "application/x-yaml"
      "application/x-nix"
    ];
  };

  # Configure XDG MIME types to open text files with Neovim
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/plain" = "nvim.desktop";
      "text/x-shellscript" = "nvim.desktop";
      "text/x-python" = "nvim.desktop";
      "text/x-c" = "nvim.desktop";
      "text/x-c++" = "nvim.desktop";
      "text/x-java" = "nvim.desktop";
      "text/x-rust" = "nvim.desktop";
      "text/x-go" = "nvim.desktop";
      "text/x-makefile" = "nvim.desktop";
      "text/markdown" = "nvim.desktop";
      "text/x-markdown" = "nvim.desktop";
      "application/json" = "nvim.desktop";
      "application/x-yaml" = "nvim.desktop";
      "application/x-nix" = "nvim.desktop";
    };
  };

  # LazyVim configuration - minimal init.lua that bootstraps LazyVim
  xdg.configFile."nvim/init.lua".text = ''
    -- Bootstrap lazy.nvim
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if not (vim.uv or vim.loop).fs_stat(lazypath) then
      local lazyrepo = "https://github.com/folke/lazy.nvim.git"
      local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
      if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
          { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
          { out, "WarningMsg" },
          { "\nPress any key to exit..." },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
      end
    end
    vim.opt.rtp:prepend(lazypath)

    -- Make sure to setup `mapleader` and `maplocalleader` before
    -- loading lazy.nvim so that mappings are correct.
    vim.g.mapleader = " "
    vim.g.maplocalleader = "\\"

    -- Setup lazy.nvim
    require("lazy").setup({
      spec = {
        -- Import LazyVim and all its plugins
        { "LazyVim/LazyVim", import = "lazyvim.plugins" },
        -- Import/override with your plugins
        { import = "plugins" },
      },
      defaults = {
        lazy = false,
        version = false, -- always use the latest git commit
      },
      install = { colorscheme = { "tokyonight", "habamax" } },
      checker = { enabled = false }, -- Don't automatically check for plugin updates
      performance = {
        rtp = {
          -- Disable some rtp plugins
          disabled_plugins = {
            "gzip",
            "tarPlugin",
            "tohtml",
            "tutor",
            "zipPlugin",
          },
        },
      },
    })

    -- Disable mouse to prevent escape sequence leakage
    vim.opt.mouse = ""

    -- Disable focus event tracking to prevent escape sequence leakage
    vim.cmd('set t_fe=')
    vim.cmd('set t_fd=')
  '';

  # LazyVim config: options
  xdg.configFile."nvim/lua/config/options.lua".text = ''
    -- Options are automatically loaded before lazy.nvim startup
    -- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

    -- Add any additional options here
    vim.opt.colorcolumn = "80"
  '';

  # LazyVim config: keymaps
  xdg.configFile."nvim/lua/config/keymaps.lua".text = ''
    -- Keymaps are automatically loaded on the VeryLazy event
    -- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

    -- Add any additional keymaps here
  '';

  # LazyVim config: autocmds
  xdg.configFile."nvim/lua/config/autocmds.lua".text = ''
    -- Autocmds are automatically loaded on the VeryLazy event
    -- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

    -- Add any additional autocmds here
  '';

  # LazyVim config: lazy.nvim configuration
  xdg.configFile."nvim/lua/config/lazy.lua".text = ''
    -- This file is automatically loaded by lazy.nvim
    return {}
  '';

  # Custom plugins: Copilot (LazyVim doesn't include this by default)
  xdg.configFile."nvim/lua/plugins/copilot.lua".text = ''
    return {
      -- GitHub Copilot AI Code Completion
      {
        "zbirenbaum/copilot.lua",
        cmd = "Copilot",
        event = "InsertEnter",
        opts = {
          panel = {
            enabled = true,
            auto_refresh = false,
            keymap = {
              jump_prev = "[[",
              jump_next = "]]",
              accept = "<CR>",
              refresh = "gr",
              open = "<M-CR>"
            },
            layout = {
              position = "bottom",
              ratio = 0.4
            },
          },
          suggestion = {
            enabled = true,
            auto_trigger = true,
            debounce = 75,
            keymap = {
              accept = "<Tab>",
              accept_word = false,
              accept_line = false,
              next = "<M-]>",
              prev = "<M-[>",
              dismiss = "<C-]>",
            },
          },
          filetypes = {
            yaml = false,
            markdown = false,
            help = false,
            gitcommit = false,
            gitrebase = false,
            hgcommit = false,
            svn = false,
            cvs = false,
            ["."] = false,
          },
          copilot_node_command = "node",
          server_opts_overrides = {},
        },
      },

      -- GitHub Copilot Chat
      {
        "CopilotC-Nvim/CopilotChat.nvim",
        branch = "canary",
        dependencies = {
          { "zbirenbaum/copilot.lua" },
          { "nvim-lua/plenary.nvim" },
        },
        build = "make tiktoken",
        opts = {
          model = "claude-sonnet-4.5",
          temperature = 0.1,
        },
        keys = {
          { "<leader>cc", "<cmd>CopilotChatToggle<cr>", desc = "Toggle Copilot Chat" },
          { "<leader>cr", "<cmd>CopilotChatReset<cr>", desc = "Reset Chat" },
          { "<leader>ce", "<cmd>CopilotChatExplain<cr>", mode = { "n", "v" }, desc = "Explain" },
          { "<leader>ct", "<cmd>CopilotChatTests<cr>", mode = { "n", "v" }, desc = "Generate Tests" },
          { "<leader>cf", "<cmd>CopilotChatFix<cr>", mode = { "n", "v" }, desc = "Fix Code" },
        },
      },
    }
  '';

  # Custom plugins: Claude Code integration
  xdg.configFile."nvim/lua/plugins/claude-code.lua".text = ''
    return {
      {
        "greggh/claude-code.nvim",
        version = "v0.4.3",
        dependencies = { "nvim-lua/plenary.nvim" },
        opts = {
          window = {
            split_ratio = 0.4,
            position = "botright",
            enter_insert = true,
            hide_numbers = true,
            hide_signcolumn = true,
          },
          command = "claude",
          keymaps = {
            toggle = {
              normal = "<leader>ai",
              terminal = "<leader>ai",
            },
          },
        },
        keys = {
          { "<leader>ai", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude Code" },
          { "<leader>ac", "<cmd>ClaudeCodeContinue<cr>", desc = "Continue" },
          { "<leader>ar", "<cmd>ClaudeCodeResume<cr>", desc = "Resume" },
          { "<leader>av", "<cmd>ClaudeCodeVerbose<cr>", desc = "Verbose Mode" },
        },
      },
    }
  '';

  # GitHub PR triage + review: gh-dash (triage) + octo.nvim (review)
  xdg.configFile."nvim/lua/plugins/github-prs.lua".text = ''
    return {
      {
        "pwntester/octo.nvim",
        cmd = "Octo",
        dependencies = {
          "nvim-lua/plenary.nvim",
          "nvim-telescope/telescope.nvim",
          "nvim-tree/nvim-web-devicons",
        },
        config = true,
        keys = {
          { "<leader>gO", "<cmd>Octo<cr>", desc = "Octo (dashboard)" },
          { "<leader>gpl", "<cmd>Octo pr list<cr>", desc = "PR list" },
          { "<leader>gpc", "<cmd>Octo pr checkout<cr>", desc = "PR checkout" },
          { "<leader>gpr", "<cmd>Octo review start<cr>", desc = "Start review" },
          { "<leader>gps", "<cmd>Octo review submit<cr>", desc = "Submit review" },
        },
      },
      {
        -- Helper keymap to open gh-dash for PR triage in project root
        "LazyVim/LazyVim",
        keys = function(_, keys)
          local Util = require("lazyvim.util")
          table.insert(keys, {
            "<leader>gD",
            function()
              local cwd = (Util.root and Util.root.get()) or vim.loop.cwd()
              Util.terminal.open({ "gh", "dash" }, { cwd = cwd })
            end,
            desc = "GH Dash (PR triage)",
          })
          return keys
        end,
      },
    }
  '';

  # gh-dash configuration: start with preview closed to avoid stuck/"null" pane
  xdg.configFile."gh-dash/config.yml".text = ''
    # yaml-language-server: $schema=https://gh-dash.dev/schema.json
    defaults:
      preview:
        open: false   # keep preview closed on load; toggle with "p"
        width: 50
      prsLimit: 30
      issuesLimit: 30
      view: prs

    prSections:
      - title: Needs My Review
        filters: is:open review-requested:@me
      - title: My PRs
        filters: is:open author:@me
      - title: Involved
        filters: is:open involves:@me -author:@me

    issuesSections:
      - title: Assigned
        filters: is:open assignee:@me
      - title: Created
        filters: is:open author:@me
      - title: Involved
        filters: is:open involves:@me -author:@me
  '';
}
