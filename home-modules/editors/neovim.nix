{ config, lib, pkgs, ... }:

let
  # Custom plugin for claudecode.nvim (not in nixpkgs yet)
  claudecode-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "claudecode-nvim";
    version = "unstable-2024-12-01";
    src = pkgs.fetchFromGitHub {
      owner = "coder";
      repo = "claudecode.nvim";
      rev = "main";
      sha256 = "sha256-b4jCKIqowkVuWhI9jxthluZISBOnIc8eOIgkw5++HRY=";
    };
  };
in
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
      nvim-web-devicons
      
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
      cmp_luasnip
      friendly-snippets
      none-ls-nvim
      nvim-lint
      conform-nvim
      
      # AI assistance
      claudecode-nvim  # Custom plugin defined above
      avante-nvim
      
      # Avante.nvim dependencies
      nui-nvim
      render-markdown-nvim
      img-clip-nvim
      
      # Quality of life
      comment-nvim
      nvim-autopairs
      indent-blankline-nvim
      
      # Navigation
      flash-nvim
      precognition-nvim
      leap-nvim
      
      # LazyVim-like additions
      which-key-nvim
      mini-nvim
      bufferline-nvim
      noice-nvim
      nui-nvim
      nvim-notify
      dashboard-nvim
      neo-tree-nvim
      trouble-nvim
      todo-comments-nvim
      vim-illuminate
      indent-blankline-nvim-lua
      
      # UI enhancements
      dressing-nvim
      nvim-navic
      barbecue-nvim
    ];
    
    extraLuaConfig = ''
      -- Configure and set tokyonight colorscheme
      local status, tokyonight = pcall(require, "tokyonight")
      if status then
        tokyonight.setup({
          style = "night",
          transparent = false,
          terminal_colors = true,
        })
      end
      
      -- Set colorscheme with error handling
      local colorscheme_ok, _ = pcall(vim.cmd, "colorscheme tokyonight-night")
      if not colorscheme_ok then
        vim.cmd("colorscheme default")
      end
      
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
      
      -- Claudecode.nvim AI assistant
      local claudecode_ok, claudecode = pcall(require, 'claudecode')
      if claudecode_ok then
        claudecode.setup({
          -- No configuration needed, it works out of the box
          -- The plugin creates a WebSocket server that Claude Code CLI connects to
        })
      end
      
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
      
      -- Flash.nvim navigation
      require('flash').setup({
        modes = {
          search = {
            enabled = true,
          },
          char = {
            enabled = true,
            jump_labels = true,
          },
        },
      })
      
      -- Flash keybindings
      vim.keymap.set({ 'n', 'x', 'o' }, 's', function() require('flash').jump() end, { desc = 'Flash' })
      vim.keymap.set({ 'n', 'x', 'o' }, 'S', function() require('flash').treesitter() end, { desc = 'Flash Treesitter' })
      vim.keymap.set('o', 'r', function() require('flash').remote() end, { desc = 'Remote Flash' })
      vim.keymap.set({ 'o', 'x' }, 'R', function() require('flash').treesitter_search() end, { desc = 'Treesitter Search' })
      vim.keymap.set('c', '<c-s>', function() require('flash').toggle() end, { desc = 'Toggle Flash Search' })
      
      -- Precognition.nvim - Vim motion hints
      require('precognition').setup({
        -- startVisible = true, -- Show hints by default (set to false to start hidden)
        startVisible = false, -- Start with hints hidden, toggle with :Precognition
        showBlankVirtLine = true,
        highlightColor = { link = "Comment" },
        hints = {
          Caret = { text = "^", prio = 2 },
          Dollar = { text = "$", prio = 1 },
          MatchingPair = { text = "%", prio = 5 },
          Zero = { text = "0", prio = 1 },
          w = { text = "w", prio = 10 },
          b = { text = "b", prio = 9 },
          e = { text = "e", prio = 8 },
          W = { text = "W", prio = 7 },
          B = { text = "B", prio = 6 },
          E = { text = "E", prio = 5 },
        },
        gutterHints = {
          G = { text = "G", prio = 10 },
          gg = { text = "gg", prio = 9 },
          PrevParagraph = { text = "{", prio = 8 },
          NextParagraph = { text = "}", prio = 8 },
        },
      })
      
      -- Toggle precognition hints with leader+p
      vim.keymap.set('n', '<leader>p', ':Precognition toggle<CR>', { desc = 'Toggle Precognition hints' })
      
      -- Avante.nvim configuration - AI-powered code assistance
      require('avante').setup({
        provider = "claude", -- Use Claude as the AI provider
        mode = "agentic", -- Use tools for automatic code generation
        auto_suggestions_provider = "claude", -- Use Claude for auto-suggestions (be careful with costs)
        
        providers = {
          claude = {
            endpoint = "https://api.anthropic.com",
            model = "claude-3-5-sonnet-20241022",
            timeout = 30000, -- 30 seconds timeout
            api_key_name = "AVANTE_ANTHROPIC_API_KEY", -- Will use this environment variable
            extra_request_body = {
              temperature = 0.75,
              max_tokens = 4096,
            },
          },
        },
        
        behaviour = {
          auto_suggestions = false, -- Disabled by default to control costs
          auto_set_highlight_group = true,
          auto_set_keymaps = true,
          auto_apply_diff_after_generation = false,
          support_paste_from_clipboard = true,
          minimize_diff = true, -- Remove unchanged lines when applying code blocks
          enable_token_counting = true, -- Show token usage
          auto_approve_tool_permissions = false, -- Require approval for tool usage
        },
        
        mappings = {
          diff = {
            ours = "co",
            theirs = "ct",
            all_theirs = "ca",
            both = "cb",
            cursor = "cc",
            next = "]x",
            prev = "[x",
          },
          suggestion = {
            accept = "<M-l>",
            next = "<M-]>",
            prev = "<M-[>",
            dismiss = "<C-]>",
          },
          jump = {
            next = "]]",
            prev = "[[",
          },
          submit = {
            normal = "<CR>",
            insert = "<C-s>",
          },
          cancel = {
            normal = { "<C-c>", "<Esc>", "q" },
            insert = { "<C-c>" },
          },
          sidebar = {
            apply_all = "A",
            apply_cursor = "a",
            retry_user_request = "r",
            edit_user_request = "e",
            switch_windows = "<Tab>",
            reverse_switch_windows = "<S-Tab>",
            remove_file = "d",
            add_file = "@",
            close = { "<Esc>", "q" },
          },
        },
        
        hints = { enabled = true },
        windows = {
          position = "right", -- Sidebar on the right
          wrap = true,
        },
        
        prompt_logger = {
          enabled = true,
          log_dir = vim.fn.stdpath("cache") .. "/avante_prompts",
          fortune_cookie_on_success = false,
          next_prompt = {
            normal = "<C-n>",
            insert = "<C-n>",
          },
          prev_prompt = {
            normal = "<C-p>",
            insert = "<C-p>",
          },
        },
      })
      
      -- Avante keybindings for quick access
      vim.keymap.set('n', '<leader>aa', ':AvanteAsk<CR>', { desc = 'Avante: Ask AI' })
      vim.keymap.set('v', '<leader>aa', ':AvanteAsk<CR>', { desc = 'Avante: Ask AI about selection' })
      vim.keymap.set('n', '<leader>ae', ':AvanteEdit<CR>', { desc = 'Avante: Edit with AI' })
      vim.keymap.set('v', '<leader>ae', ':AvanteEdit<CR>', { desc = 'Avante: Edit selection with AI' })
      vim.keymap.set('n', '<leader>ar', ':AvanteRefresh<CR>', { desc = 'Avante: Refresh' })
      vim.keymap.set('n', '<leader>at', ':AvanteToggle<CR>', { desc = 'Avante: Toggle sidebar' })
      
      -- Render-markdown configuration for better markdown display in Avante
      require('render-markdown').setup({
        file_types = { "markdown", "Avante" },
        code = {
          enabled = true,
          sign = false,
          width = 'full',
          position = 'left',
        },
      })
      
      -- img-clip configuration for image pasting support
      require('img-clip').setup({
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          use_absolute_path = true, -- Required for Windows/WSL users
        },
      })
      
      -- MCP Hub integration (when available)
      -- To use MCP Hub with Avante, install mcp-hub separately and configure:
      -- 1. Run: mcp-hub --port 3000 --config ~/.config/mcp/servers.json
      -- 2. Configure Avante to connect to MCP servers through the hub
      -- Note: Full MCP Hub integration pending package availability in nixpkgs
      
      -- LSP configuration
      local lspconfig = require('lspconfig')
      local capabilities = require('cmp_nvim_lsp').default_capabilities()
      
      -- TypeScript/JavaScript LSP
      if vim.fn.executable('typescript-language-server') == 1 then
        lspconfig.ts_ls.setup({
          capabilities = capabilities,
          on_attach = function(client, bufnr)
            -- Enable completion triggered by <c-x><c-o>
            vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
            
            -- LSP keybindings
            local opts = { noremap=true, silent=true, buffer=bufnr }
            vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
            vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
            vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
            vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
            vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
            vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, opts)
            vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
            vim.keymap.set('n', '<leader>wl', function()
              print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
            end, opts)
            vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, opts)
            vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
            vim.keymap.set({ 'n', 'v' }, '<leader>ca', vim.lsp.buf.code_action, opts)
            vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
            vim.keymap.set('n', '<leader>f', function()
              vim.lsp.buf.format { async = true }
            end, opts)
          end,
          settings = {
            typescript = {
              inlayHints = {
                includeInlayParameterNameHints = 'all',
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = true,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
              }
            }
          }
        })
      end
      
      -- Nix LSP
      if vim.fn.executable('nil') == 1 then
        lspconfig.nil_ls.setup({
          capabilities = capabilities,
        })
      end
      
      -- Python LSP
      if vim.fn.executable('pyright') == 1 then
        lspconfig.pyright.setup({
          capabilities = capabilities,
        })
      end
      
      -- Completion setup
      local cmp = require('cmp')
      local luasnip = require('luasnip')
      
      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
          ['<Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { 'i', 's' }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
        }, {
          { name = 'buffer' },
          { name = 'path' },
        })
      })
    '';
  };
}