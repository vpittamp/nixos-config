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
    vim.opt.mouse = "a"
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