# Minimal neovim configuration for containers
# Completely bypasses Nix plugin system to avoid build permission issues
{ config, pkgs, lib, ... }:

{
  # Install only the neovim binary, no wrappers or plugins
  home.packages = with pkgs; [
    neovim-unwrapped  # Pure neovim without any Nix wrapping
    git              # Required for lazy.nvim to clone plugins
  ];
  
  # Create neovim config that uses lazy.nvim for all plugin management
  xdg.configFile."nvim/init.lua".text = ''
    -- Bootstrap lazy.nvim
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
    
    -- Basic settings first
    vim.g.mapleader = " "
    vim.opt.number = true
    vim.opt.relativenumber = true
    vim.opt.expandtab = true
    vim.opt.shiftwidth = 2
    vim.opt.tabstop = 2
    vim.opt.ignorecase = true
    vim.opt.smartcase = true
    vim.opt.mouse = "a"
    
    -- Setup lazy.nvim with minimal plugins
    local ok, lazy = pcall(require, "lazy")
    if ok then
      lazy.setup({
        -- Only essential plugins that download at runtime
        { "nvim-lua/plenary.nvim" },  -- Common dependency
        
        -- Theme
        { 
          "catppuccin/nvim",
          name = "catppuccin",
          priority = 1000,
          config = function()
            vim.cmd.colorscheme("catppuccin-mocha")
          end,
        },
        
        -- Core editing plugins
        { "tpope/vim-surround", event = "VeryLazy" },
        { "tpope/vim-commentary", event = "VeryLazy" },
        
        -- File explorer
        {
          "nvim-tree/nvim-tree.lua",
          cmd = { "NvimTreeToggle", "NvimTreeFocus" },
          config = function()
            require("nvim-tree").setup({})
          end,
        },
        
        -- Statusline
        {
          "nvim-lualine/lualine.nvim",
          event = "VeryLazy",
          config = function()
            require("lualine").setup({
              options = {
                theme = "catppuccin"
              }
            })
          end,
        },
      }, {
        -- Lazy.nvim configuration
        root = vim.fn.stdpath("data") .. "/lazy",
        lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
        performance = {
          rtp = {
            disabled_plugins = {
              "gzip",
              "matchit",
              "matchparen",
              "netrwPlugin",
              "tarPlugin",
              "tohtml",
              "tutor",
              "zipPlugin",
            },
          },
        },
        install = {
          -- Don't show installation UI in containers
          missing = true,
          colorscheme = { "catppuccin", "default" },
        },
        checker = {
          enabled = false,  -- Don't auto-check for updates
        },
        change_detection = {
          enabled = false,  -- Don't auto-reload on config changes
        },
      })
    else
      print("Failed to load lazy.nvim")
    end
    
    -- Keymaps
    vim.keymap.set("n", "<leader>w", ":w<CR>", { desc = "Save file" })
    vim.keymap.set("n", "<leader>q", ":q<CR>", { desc = "Quit" })
    vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { desc = "File explorer" })
  '';
}