{ config, lib, pkgs, ... }:

with lib;

let
  zoxideToolsPath = makeBinPath [ pkgs.fzf ];
in
{
  options = {
    modules.tools.yazi.enable = mkEnableOption "yazi file manager configuration";
  };

  config = mkIf config.modules.tools.yazi.enable {
    # Desktop entries now managed by app-registry.nix (Feature 034)
    # xdg.dataFile."applications/yazi.desktop".text = ''
    #   [Desktop Entry]
    #   Type=Application
    #   Name=Yazi
    #   Comment=Blazing fast terminal file manager
    #   Exec=ghostty -e yazi
    #   Icon=folder
    #   Terminal=false
    #   Categories=System;FileTools;FileManager;
    #   Keywords=file;manager;explorer;terminal;
    # '';

    # Yazi file manager configuration
    programs.yazi = {
      enable = true;
      enableBashIntegration = true;
      
      # Zoxide integration keybindings
      keymap = {
        mgr = {
          prepend_keymap = [
            # Zoxide integration
            { on = ["z"]; run = "shell 'PATH=${zoxideToolsPath}:$PATH; ya=$YAZI_ID; zoxide_dir=$(${pkgs.zoxide}/bin/zoxide query -l | ${pkgs.fzf}/bin/fzf --prompt \"Zoxide > \" --height=40% --reverse --preview \"${pkgs.eza}/bin/eza -la --color=always {}\" --preview-window=right:60%); if [ -n \"$zoxide_dir\" ]; then printf \"cd \\\"%s\\\"\\n\" \"$zoxide_dir\" | ${pkgs.yazi}/bin/yazi-msg --id=$ya; fi' --block"; desc = "Jump to frecent directory with zoxide"; }
            { on = ["Z"]; run = "shell 'PATH=${zoxideToolsPath}:$PATH; ya=$YAZI_ID; zoxide_dir=$(${pkgs.zoxide}/bin/zoxide query -i); if [ -n \"$zoxide_dir\" ]; then printf \"cd \\\"%s\\\"\\n\" \"$zoxide_dir\" | ${pkgs.yazi}/bin/yazi-msg --id=$ya; fi' --block"; desc = "Jump with zoxide query"; }
            
            # Smart find
            { on = ["/"]; run = "find --smart"; desc = "Smart find with highlighting"; }
            
            # Quick editor shortcuts
            { on = ["e"]; run = "open"; desc = "Open with interactive menu"; }
            { on = ["e" "e"]; run = "open --hovered"; desc = "Open hovered file with menu"; }
            { on = ["e" "n"]; run = "open --hovered --opener nvim"; desc = "Open in Neovim"; }
            { on = ["e" "v"]; run = "open --hovered --opener vscode"; desc = "Open in VSCode"; }
            { on = ["o"]; run = "open --interactive"; desc = "Open with interactive selector"; }
          ];
        };
      };
      
      settings = {
        mgr = {
          ratio = [1 1 4];
          sort_by = "mtime";
          sort_sensitive = true;
          sort_reverse = true;
          sort_dir_first = true;
          linemode = "none";
          show_hidden = true;
          show_symlink = true;
        };
        
        preview = {
          tab_size = 2;
          max_width = 2000;
          max_height = 1200;
          cache_dir = "";
          ueberzug_scale = 1;
          ueberzug_offset = [0 0 0 0];
        };
        
        opener = {
          # Multiple editor options
          edit = [
            { run = "\${EDITOR:-nvim} \"$@\""; block = true; desc = "Edit with $EDITOR (nvim)"; for = "unix"; }
          ];
          
          nvim = [
            { run = "nvim \"$@\""; block = true; desc = "Edit with Neovim"; for = "unix"; }
          ];
          
          vscode = [
            { run = "code \"$@\""; orphan = true; desc = "Open in VSCode"; for = "unix"; }
          ];
          
          vscode-wait = [
            { run = "code --wait \"$@\""; block = true; desc = "Edit in VSCode (wait)"; for = "unix"; }
          ];
          
          # Folder-specific openers
          folder-nvim = [
            { run = "nvim \"$@\""; block = true; desc = "Open folder in Neovim"; for = "unix"; }
          ];
          
          folder-vscode = [
            { run = "code \"$@\""; orphan = true; desc = "Open folder in VSCode"; for = "unix"; }
          ];
          
          # System default opener
          open = [
            { run = "xdg-open \"$@\""; desc = "Open with system default"; for = "linux"; }
          ];
          
          # File inspection tools
          reveal = [
            { run = "exiftool \"$1\"; echo \"Press enter to exit\"; read"; block = true; desc = "Show EXIF data"; for = "unix"; }
          ];
          
          hexdump = [
            { run = "hexdump -C \"$1\" | less"; block = true; desc = "View as hex"; for = "unix"; }
          ];
          
          # Archive handling
          extract = [
            { run = "unar \"$1\""; desc = "Extract here"; for = "unix"; }
          ];
          
          # Media players
          play = [
            { run = "mpv \"$@\""; orphan = true; desc = "Play with mpv"; for = "unix"; }
            { run = "mediainfo \"$1\"; echo \"Press enter to exit\"; read"; block = true; desc = "Show media info"; for = "unix"; }
          ];
        };
        
        open = {
          prepend_rules = [
            # Directories - offer both editors
            { name = "*/"; use = ["folder-vscode" "folder-nvim" "open"]; }
            
            # Configuration files - prefer nvim for quick edits
            { name = "*.toml"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.yaml"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.yml"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.json"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.nix"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.conf"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.config"; use = ["nvim" "vscode" "edit"]; }
            { name = ".env*"; use = ["nvim" "vscode" "edit"]; }
            
            # Shell scripts - nvim for quick edits
            { name = "*.sh"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.bash"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.zsh"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.fish"; use = ["nvim" "vscode" "edit"]; }
            
            # Programming files - VSCode first for better IDE features
            { name = "*.ts"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.tsx"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.js"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.jsx"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.rs"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.go"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.py"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.java"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.c"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.cpp"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.h"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.hpp"; use = ["vscode" "nvim" "edit"]; }
            
            # Web files - VSCode for better preview
            { name = "*.html"; use = ["vscode" "nvim" "open"]; }
            { name = "*.css"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.scss"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.sass"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.less"; use = ["vscode" "nvim" "edit"]; }
            
            # Documentation - VSCode for markdown preview
            { name = "*.md"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.mdx"; use = ["vscode" "nvim" "edit"]; }
            { name = "README*"; use = ["vscode" "nvim" "edit"]; }
            
            # Data files
            { name = "*.csv"; use = ["vscode" "nvim" "edit"]; }
            { name = "*.xml"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.sql"; use = ["vscode" "nvim" "edit"]; }
            
            # Text files - nvim for quick edits
            { name = "*.txt"; use = ["nvim" "vscode" "edit"]; }
            { name = "*.log"; use = ["nvim" "vscode" "less"]; }
          ];
          
          append_rules = [
            # Keep default rules for other file types
            { mime = "text/*"; use = ["nvim" "vscode" "edit"]; }
            { mime = "image/*"; use = ["open" "reveal"]; }
            { mime = "video/*"; use = ["play" "reveal"]; }
            { mime = "audio/*"; use = ["play" "reveal"]; }
            { mime = "inode/empty"; use = ["nvim" "vscode" "edit"]; }
            { mime = "application/zip"; use = ["extract" "reveal" "hexdump"]; }
            { mime = "application/gzip"; use = ["extract" "reveal" "hexdump"]; }
            { mime = "application/tar"; use = ["extract" "reveal" "hexdump"]; }
            { mime = "application/bzip"; use = ["extract" "reveal" "hexdump"]; }
            { mime = "application/bzip2"; use = ["extract" "reveal" "hexdump"]; }
            { mime = "application/7z-compressed"; use = ["extract" "reveal" "hexdump"]; }
            { mime = "application/rar"; use = ["extract" "reveal" "hexdump"]; }
            { mime = "*"; use = ["open" "reveal" "hexdump"]; }
          ];
        };
        
        tasks = {
          micro_workers = 5;
          macro_workers = 10;
          bizarre_retry = 5;
        };
        
        log = {
          enabled = false;
        };
      };
      
      # VSCode Dark Modern theme configuration
      theme = {
        mgr = {
          cwd = { fg = "#569cd6"; };
          
          # Hovered
          hovered = { fg = "#000000"; bg = "#b8d7f3"; };
          preview_hovered = { underline = true; };
          
          # Find
          find_keyword = { fg = "#f9826c"; italic = true; };
          find_position = { fg = "#cccccc"; bg = "#3a3f4b"; italic = true; };
          
          # Marker
          marker_selected = { fg = "#b8d7f3"; bg = "#3c5d80"; };
          marker_copied = { fg = "#b8d7f3"; bg = "#487844"; };
          marker_cut = { fg = "#b8d7f3"; bg = "#d47766"; };
          
          # Tab
          tab_active = { fg = "#000000"; bg = "#569cd6"; };
          tab_inactive = { fg = "#cccccc"; bg = "#3c3c3c"; };
          tab_width = 1;
          
          # Border
          border_symbol = "│";
          border_style = { fg = "#3e3e3e"; };
          
          # Highlighting
          syntect_theme = "";
        };
        
        status = {
          separator_style = { fg = "#4e4e4e"; bg = "#252526"; };
          mode_normal = { fg = "#000000"; bg = "#569cd6"; bold = true; };
          mode_select = { fg = "#000000"; bg = "#c586c0"; bold = true; };
          mode_unset = { fg = "#000000"; bg = "#d7ba7d"; bold = true; };
          
          progress_label = { fg = "#ffffff"; bold = true; };
          progress_normal = { fg = "#569cd6"; bg = "#252526"; };
          progress_error = { fg = "#f44747"; bg = "#252526"; };
          
          permissions_t = { fg = "#569cd6"; };
          permissions_r = { fg = "#d7ba7d"; };
          permissions_w = { fg = "#f44747"; };
          permissions_x = { fg = "#b5cea8"; };
          permissions_s = { fg = "#c586c0"; };
        };
        
        input = {
          border = { fg = "#569cd6"; };
          title = {};
          value = {};
          selected = { reversed = true; };
        };
        
        select = {
          border = { fg = "#569cd6"; };
          active = { fg = "#c586c0"; };
          inactive = {};
        };
        
        tasks = {
          border = { fg = "#569cd6"; };
          title = {};
          hovered = { underline = true; };
        };
        
        which = {
          mask = { bg = "#1e1e1e"; };
          cand = { fg = "#9cdcfe"; };
          rest = { fg = "#808080"; };
          desc = { fg = "#c586c0"; };
          separator = " ";
          separator_style = { fg = "#4e4e4e"; };
        };
        
        help = {
          on = { fg = "#c586c0"; };
          exec = { fg = "#9cdcfe"; };
          desc = { fg = "#808080"; };
          hovered = { bg = "#3c5d80"; bold = true; };
          footer = { fg = "#252526"; bg = "#cccccc"; };
        };
        
        filetype = {
          rules = [
            # Images
            { mime = "image/*"; fg = "#c586c0"; }
            
            # Videos
            { mime = "video/*"; fg = "#d7ba7d"; }
            
            # Audio
            { mime = "audio/*"; fg = "#d7ba7d"; }
            
            # Archives
            { mime = "application/zip"; fg = "#f14c4c"; }
            { mime = "application/gzip"; fg = "#f14c4c"; }
            { mime = "application/x-tar"; fg = "#f14c4c"; }
            { mime = "application/x-bzip"; fg = "#f14c4c"; }
            { mime = "application/x-bzip2"; fg = "#f14c4c"; }
            { mime = "application/x-7z-compressed"; fg = "#f14c4c"; }
            { mime = "application/x-rar"; fg = "#f14c4c"; }
            
            # Fallback
            { name = "*"; fg = "#cccccc"; }
            { name = "*/"; fg = "#569cd6"; }
          ];
        };
        
        icon = {
          rules = [
            # Programming
            { name = "*.c"; text = ""; }
            { name = "*.cpp"; text = ""; }
            { name = "*.h"; text = ""; }
            { name = "*.hpp"; text = ""; }
            { name = "*.rs"; text = ""; }
            { name = "*.go"; text = ""; }
            { name = "*.py"; text = ""; }
            { name = "*.js"; text = ""; }
            { name = "*.jsx"; text = "⚛"; }
            { name = "*.ts"; text = ""; }
            { name = "*.tsx"; text = "⚛"; }
            { name = "*.vue"; text = "﵂"; }
            { name = "*.json"; text = ""; }
            { name = "*.toml"; text = ""; }
            { name = "*.yaml"; text = ""; }
            { name = "*.yml"; text = ""; }
            { name = "*.nix"; text = ""; }
            
            # Text
            { name = "*.txt"; text = ""; }
            { name = "*.md"; text = ""; }
            
            # Archives
            { name = "*.zip"; text = ""; }
            { name = "*.tar"; text = ""; }
            { name = "*.gz"; text = ""; }
            { name = "*.7z"; text = ""; }
            { name = "*.bz2"; text = ""; }
            
            # Default
            { name = "*"; text = ""; }
            { name = "*/"; text = ""; }
          ];
        };
      };
    };
  };
}
