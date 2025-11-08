{ config, lib, pkgs, ... }:
{
  # Use unwrapped neovim to avoid Nix plugin system issues in containers
  home.packages = with pkgs; [
    neovim-unwrapped  # Pure neovim without Nix wrapping
    # Dependencies for plugins
    ripgrep           # For telescope
    fd                # For telescope file finder
    nodejs            # For various language servers
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
  
  # Create Neovim configuration using lazy.nvim for plugin management
  # This works identically in both local and container environments
  xdg.configFile."nvim/init.lua".text = ''
    -- Bootstrap lazy.nvim plugin manager
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if not vim.loop.fs_stat(lazypath) then
      print("Installing lazy.nvim...")
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
    
    -- Set leader key before plugins
    vim.g.mapleader = " "
    vim.g.maplocalleader = " "
    
    -- Basic settings
    vim.opt.number = true
    vim.opt.relativenumber = true
    vim.opt.expandtab = true
    vim.opt.tabstop = 2
    vim.opt.shiftwidth = 2
    vim.opt.smartindent = true
    vim.opt.termguicolors = true
    vim.opt.signcolumn = "yes"
    vim.opt.colorcolumn = "80"
    vim.opt.scrolloff = 8
    vim.opt.updatetime = 50
    vim.opt.mouse = ""  -- Disable mouse to prevent escape sequence leakage

    -- Disable focus event tracking to prevent escape sequence leakage
    vim.cmd('set t_fe=')  -- Disable focus gained sequence
    vim.cmd('set t_fd=')  -- Disable focus lost sequence

    vim.opt.ignorecase = true
    vim.opt.smartcase = true
    vim.opt.incsearch = true
    vim.opt.hlsearch = true
    
    -- Setup lazy.nvim with all plugins
    local plugins = {
      -- Theme
      { 
        "folke/tokyonight.nvim",
        lazy = false,
        priority = 1000,
        config = function()
          vim.cmd.colorscheme("tokyonight-night")
        end,
      },
      
      -- Essential plugins
      { "nvim-lua/plenary.nvim" },
      
      -- File navigation
      {
        "nvim-telescope/telescope.nvim",
        branch = "0.1.x",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
          require("telescope").setup({
            defaults = {
              mappings = {
                i = {
                  ["<C-u>"] = false,
                  ["<C-d>"] = false,
                },
              },
            },
          })
        end,
        keys = {
          { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
          { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Grep Files" },
          { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Find Buffers" },
          { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help Tags" },
        },
      },
      
      -- Treesitter for syntax highlighting
      {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        config = function()
          require("nvim-treesitter.configs").setup({
            ensure_installed = { "lua", "vim", "vimdoc", "nix", "bash", "python", "typescript", "javascript", "yaml", "json", "markdown" },
            auto_install = true,
            highlight = { enable = true },
            indent = { enable = true },
          })
        end,
      },
      
      -- LSP Configuration
      {
        "neovim/nvim-lspconfig",
        dependencies = {
          "williamboman/mason.nvim",
          "williamboman/mason-lspconfig.nvim",
        },
        config = function()
          require("mason").setup()
          require("mason-lspconfig").setup({
            ensure_installed = { "lua_ls", "nil_ls", "pyright", "tsserver" },
          })
          
          local lspconfig = require("lspconfig")
          
          -- Lua
          lspconfig.lua_ls.setup({
            settings = {
              Lua = {
                telemetry = { enable = false },
                workspace = { checkThirdParty = false },
              },
            },
          })
          
          -- Nix
          lspconfig.nil_ls.setup({})
          
          -- Python
          lspconfig.pyright.setup({})
          
          -- TypeScript/JavaScript
          lspconfig.tsserver.setup({})
        end,
      },
      
      -- Autocompletion
      {
        "hrsh7th/nvim-cmp",
        dependencies = {
          "hrsh7th/cmp-nvim-lsp",
          "hrsh7th/cmp-buffer",
          "hrsh7th/cmp-path",
          "L3MON4D3/LuaSnip",
          "saadparwaiz1/cmp_luasnip",
        },
        config = function()
          local cmp = require("cmp")
          local luasnip = require("luasnip")
          
          cmp.setup({
            snippet = {
              expand = function(args)
                luasnip.lsp_expand(args.body)
              end,
            },
            mapping = cmp.mapping.preset.insert({
              ["<C-d>"] = cmp.mapping.scroll_docs(-4),
              ["<C-f>"] = cmp.mapping.scroll_docs(4),
              ["<C-Space>"] = cmp.mapping.complete(),
              ["<CR>"] = cmp.mapping.confirm({ select = true }),
              ["<Tab>"] = cmp.mapping(function(fallback)
                if cmp.visible() then
                  cmp.select_next_item()
                elseif luasnip.expand_or_jumpable() then
                  luasnip.expand_or_jump()
                else
                  fallback()
                end
              end, { "i", "s" }),
            }),
            sources = {
              { name = "nvim_lsp" },
              { name = "luasnip" },
              { name = "buffer" },
              { name = "path" },
            },
          })
        end,
      },
      
      -- Git integration
      {
        "lewis6991/gitsigns.nvim",
        config = function()
          require("gitsigns").setup()
        end,
      },
      
      -- File explorer
      {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
          require("nvim-tree").setup()
        end,
        keys = {
          { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "File Explorer" },
        },
      },
      
      -- Status line
      {
        "nvim-lualine/lualine.nvim",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
          require("lualine").setup({
            options = {
              theme = "tokyonight",
            },
          })
        end,
      },
      
      -- Comment plugin
      {
        "numToStr/Comment.nvim",
        config = function()
          require("Comment").setup()
        end,
      },
      
      -- Surround plugin
      {
        "kylechui/nvim-surround",
        version = "*",
        event = "VeryLazy",
        config = function()
          require("nvim-surround").setup()
        end,
      },
      
      -- Which key
      {
        "folke/which-key.nvim",
        event = "VeryLazy",
        init = function()
          vim.o.timeout = true
          vim.o.timeoutlen = 300
        end,
        config = function()
          require("which-key").setup()
        end,
      },
      
      -- Indent guides
      {
        "lukas-reineke/indent-blankline.nvim",
        main = "ibl",
        config = function()
          require("ibl").setup()
        end,
      },
      
      -- Claude Code Integration
      {
        "greggh/claude-code.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
          require('claude-code').setup({
            -- Window configuration
            window = {
              split_ratio = 0.4,  -- 40% of screen for Claude
              position = "botright",  -- bottom right split
              enter_insert = true,  -- auto enter insert mode
            },
            -- Claude Code command path (already in PATH from Nix)
            command = "claude",
            -- Keymaps configuration
            keymaps = {
              toggle = {
                normal = "<leader>ai",  -- Toggle in normal mode
                terminal = "<leader>ai",  -- Toggle in terminal mode
              },
            },
          })
        end,
        keys = {
          { "<leader>ai", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude Code" },
          { "<leader>ac", "<cmd>ClaudeCodeContinue<cr>", desc = "Claude Continue" },
          { "<leader>ar", "<cmd>ClaudeCodeResume<cr>", desc = "Claude Resume" },
          { "<leader>av", "<cmd>ClaudeCodeVerbose<cr>", desc = "Claude Verbose Mode" },
        },
      },
      
      -- GitHub Copilot AI Code Completion
      {
        "zbirenbaum/copilot.lua",
        cmd = "Copilot",
        event = "InsertEnter",
        config = function()
          require("copilot").setup({
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
                position = "bottom", -- | top | left | right
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
            copilot_node_command = "node", -- Node.js version must be > 18.x
            server_opts_overrides = {},
          })
        end,
      },
      
      -- GitHub Copilot Chat
      {
        "CopilotC-Nvim/CopilotChat.nvim",
        branch = "canary",
        dependencies = {
          { "zbirenbaum/copilot.lua" },
          { "nvim-lua/plenary.nvim" },
        },
        opts = {
          debug = true,
          model = "claude-3.5-sonnet", -- Can use gpt-4o or claude-3.5-sonnet
          temperature = 0.1,
          window = {
            layout = "vertical", -- 'vertical', 'horizontal', 'float', 'replace'
            width = 0.5, -- fractional width of parent, or absolute width in columns when > 1
            height = 0.5, -- fractional height of parent, or absolute height in rows when > 1
            relative = "editor", -- 'editor', 'win', 'cursor', 'mouse'
            border = "rounded", -- 'none', single', 'double', 'rounded', 'solid', 'shadow'
            row = nil, -- row position of the window, default is centered
            col = nil, -- column position of the window, default is centered
            title = "Copilot Chat", -- title of chat window
            footer = nil, -- footer of chat window
            zindex = 1, -- determines if window is on top or below other floating windows
          },
        },
        keys = {
          -- Chat commands
          { "<leader>cc", "<cmd>CopilotChatToggle<cr>", desc = "Toggle Copilot Chat" },
          { "<leader>cr", "<cmd>CopilotChatReset<cr>", desc = "Reset Copilot Chat" },
          { "<leader>cs", "<cmd>CopilotChatStop<cr>", desc = "Stop Copilot Chat" },
          
          -- Quick actions
          { "<leader>ce", "<cmd>CopilotChatExplain<cr>", mode = { "n", "v" }, desc = "Explain code" },
          { "<leader>ct", "<cmd>CopilotChatTests<cr>", mode = { "n", "v" }, desc = "Generate tests" },
          { "<leader>cf", "<cmd>CopilotChatFix<cr>", mode = { "n", "v" }, desc = "Fix code" },
          { "<leader>co", "<cmd>CopilotChatOptimize<cr>", mode = { "n", "v" }, desc = "Optimize code" },
          { "<leader>cd", "<cmd>CopilotChatDocs<cr>", mode = { "n", "v" }, desc = "Document code" },
          { "<leader>cx", "<cmd>CopilotChatFixDiagnostic<cr>", mode = { "n", "v" }, desc = "Fix diagnostic" },
          { "<leader>cm", "<cmd>CopilotChatCommit<cr>", desc = "Generate commit message" },
          { "<leader>cq", function()
            local input = vim.fn.input("Quick Chat: ")
            if input ~= "" then
              require("CopilotChat").ask(input, { selection = require("CopilotChat.select").buffer })
            end
          end, desc = "Quick chat" },
          
          -- Model selection
          { "<leader>cn", "<cmd>CopilotChatModels<cr>", desc = "Select AI model" },
        },
      },
    }
    
    -- Initialize lazy.nvim
    require("lazy").setup(plugins, {
      root = vim.fn.stdpath("data") .. "/lazy",
      lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
      performance = {
        rtp = {
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
    
    -- Key mappings
    vim.keymap.set("n", "<leader>w", ":w<CR>", { desc = "Save file" })
    vim.keymap.set("n", "<leader>q", ":q<CR>", { desc = "Quit" })
    vim.keymap.set("n", "<leader>h", ":nohlsearch<CR>", { desc = "Clear search" })
    
    -- Better window navigation
    vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
    vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
    vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
    vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })
  '';
}