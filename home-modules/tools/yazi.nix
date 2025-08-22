{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    modules.tools.yazi.enable = mkEnableOption "yazi file manager configuration";
  };

  config = mkIf config.modules.tools.yazi.enable {
    # Yazi file manager configuration
    programs.yazi = {
      enable = true;
      enableBashIntegration = true;
      
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
          edit = [
            { run = "\${EDITOR:-nvim} \"$@\""; block = true; for = "unix"; }
          ];
          open = [
            { run = "xdg-open \"$@\""; desc = "Open"; for = "linux"; }
          ];
          reveal = [
            { run = "exiftool \"$1\"; echo \"Press enter to exit\"; read"; block = true; desc = "Show EXIF"; for = "unix"; }
          ];
          extract = [
            { run = "unar \"$1\""; desc = "Extract here"; for = "unix"; }
          ];
          play = [
            { run = "mpv \"$@\""; orphan = true; for = "unix"; }
            { run = "mediainfo \"$1\"; echo \"Press enter to exit\"; read"; block = true; desc = "Show media info"; for = "unix"; }
          ];
        };
        
        open = {
          rules = [
            { name = "*/"; use = ["edit" "open" "reveal"]; }
            { mime = "text/*"; use = ["edit" "reveal"]; }
            { mime = "image/*"; use = ["open" "reveal"]; }
            { mime = "video/*"; use = ["play" "reveal"]; }
            { mime = "audio/*"; use = ["play" "reveal"]; }
            { mime = "inode/empty"; use = ["edit" "reveal"]; }
            { mime = "application/json"; use = ["edit" "reveal"]; }
            { mime = "*/javascript"; use = ["edit" "reveal"]; }
            { mime = "application/zip"; use = ["extract" "reveal"]; }
            { mime = "application/gzip"; use = ["extract" "reveal"]; }
            { mime = "application/tar"; use = ["extract" "reveal"]; }
            { mime = "application/bzip"; use = ["extract" "reveal"]; }
            { mime = "application/bzip2"; use = ["extract" "reveal"]; }
            { mime = "application/7z-compressed"; use = ["extract" "reveal"]; }
            { mime = "application/rar"; use = ["extract" "reveal"]; }
            { mime = "*"; use = ["open" "reveal"]; }
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
        manager = {
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