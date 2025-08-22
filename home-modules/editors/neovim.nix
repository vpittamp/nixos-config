{ config, lib, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    
    extraConfig = ''
      set number relativenumber
      set expandtab
      set tabstop=2
      set shiftwidth=2
      set smartindent
      set termguicolors
      set signcolumn=yes
      set colorcolumn=80
      set scrolloff=8
      set updatetime=50
      
      " Better search
      set ignorecase
      set smartcase
      set incsearch
      set hlsearch
      
      " Key mappings
      let mapleader = " "
      nnoremap <leader>w :w<CR>
      nnoremap <leader>q :q<CR>
      nnoremap <leader>h :nohlsearch<CR>
      
      " Better navigation
      nnoremap <C-h> <C-w>h
      nnoremap <C-j> <C-w>j
      nnoremap <C-k> <C-w>k
      nnoremap <C-l> <C-w>l
    '';
    
    plugins = with pkgs.vimPlugins; [
      # Theme
      tokyonight-nvim
      
      # Essential
      plenary-nvim
      telescope-nvim
      nvim-treesitter.withAllGrammars
      
      # Telescope extensions and dependencies
      telescope-fzy-native-nvim
      telescope-live-grep-args-nvim
      telescope-undo-nvim
      nvim-neoclip-lua
      
      # File tree
      nvim-tree-lua
      
      # Status line
      lualine-nvim
      
      # Git
      gitsigns-nvim
      vim-fugitive
      
      # LSP and completion
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      luasnip
      
      # AI assistance
      claude-code-nvim
      
      # Quality of life
      comment-nvim
      nvim-autopairs
      indent-blankline-nvim
    ];
    
    extraLuaConfig = ''
      -- Set colorscheme
      vim.cmd.colorscheme "tokyonight-night"
      
      -- Use system clipboard by default
      vim.opt.clipboard = "unnamedplus"
      
      -- Lualine
      require('lualine').setup {
        options = { theme = 'tokyonight' }
      }
      
      -- Gitsigns
      require('gitsigns').setup()
      
      -- Comment
      require('Comment').setup()
      
      -- Autopairs
      require('nvim-autopairs').setup()
      
      -- Indent blankline
      require('ibl').setup()
      
      -- Claude Code AI assistant
      require('claude-code').setup({
        -- Use default settings for now
        keymaps = {
          toggle = {
            normal = "<C-,>",       -- Normal mode keymap
            terminal = "<C-,>",     -- Terminal mode keymap
          },
        },
      })
      
      -- Telescope configuration
      local telescope = require('telescope')
      local builtin = require('telescope.builtin')
      
      telescope.setup({
        defaults = {
          border = true,
          file_ignore_patterns = { '.git/', 'node_modules' },
          layout_config = {
            height = 0.9999999,
            width = 0.99999999,
            preview_cutoff = 0,
            horizontal = { preview_width = 0.60 },
            vertical = { width = 0.999, height = 0.9999, preview_cutoff = 0 },
            prompt_position = 'top',
          },
          path_display = { 'smart' },
          prompt_position = 'top',
          prompt_prefix = ' ',
          selection_caret = '👉',
          sorting_strategy = 'ascending',
          vimgrep_arguments = {
            'rg',
            '--color=never',
            '--no-heading',
            '--hidden',
            '--with-filename',
            '--line-number',
            '--column',
            '--smart-case',
            '--trim',
          },
        },
        pickers = {
          buffers = {
            prompt_prefix = '󰸩 ',
          },
          commands = {
            prompt_prefix = ' ',
            layout_config = {
              height = 0.99,
              width = 0.99,
            },
          },
          command_history = {
            prompt_prefix = ' ',
            layout_config = {
              height = 0.99,
              width = 0.99,
            },
          },
          git_files = {
            prompt_prefix = '󰊢 ',
            show_untracked = true,
          },
          find_files = {
            prompt_prefix = ' ',
            find_command = { 'fd', '-H' },
            layout_config = {
              height = 0.999,
              width = 0.999,
            },
          },
          live_grep = {
            prompt_prefix = '󰱽 ',
          },
          grep_string = {
            prompt_prefix = '󰱽 ',
          },
        },
        extensions = {
          smart_open = {
            cwd_only = true,
            filename_first = true,
          },
        },
      })
      
      -- Load Telescope extensions
      telescope.load_extension('live_grep_args')
      telescope.load_extension('neoclip')
      telescope.load_extension('undo')
      telescope.load_extension('fzy_native')
      
      -- Telescope keybindings
      vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Find files' })
      vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Live grep' })
      vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Buffers' })
      vim.keymap.set('n', '<leader>*', builtin.grep_string, { desc = 'Grep word under cursor' })
      vim.keymap.set('n', '<leader>.', builtin.resume, { desc = 'Resume Telescope' })
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Help tags' })
      vim.keymap.set('n', '<leader>fc', builtin.commands, { desc = 'Commands' })
      vim.keymap.set('n', '<leader>fu', '<cmd>Telescope undo<cr>', { desc = 'Undo tree' })
      vim.keymap.set('n', '<leader>fy', '<cmd>Telescope neoclip<cr>', { desc = 'Clipboard history' })
      vim.keymap.set('n', '<leader>fl', '<cmd>Telescope live_grep_args live_grep_args<cr>', { desc = 'Live grep with args' })
      
      -- Nvim-tree
      require('nvim-tree').setup()
      vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>', {})
    '';
  };
}