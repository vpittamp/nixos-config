{ config, pkgs, lib, ... }:
{
  # Cross-platform terminal color configuration
  # Works on both Linux and macOS
  
  programs.dircolors = {
    enable = true;
    enableBashIntegration = true;
    
    # Custom color settings for ls/eza
    # These work consistently across platforms
    settings = {
      # Directories
      DIR = "01;34";  # Bold blue
      LINK = "01;36"; # Bold cyan
      
      # Files by type
      EXEC = "01;32"; # Bold green for executables
      
      # Archives
      ".tar" = "01;31";
      ".tgz" = "01;31";
      ".zip" = "01;31";
      ".gz" = "01;31";
      ".bz2" = "01;31";
      ".xz" = "01;31";
      ".7z" = "01;31";
      
      # Images
      ".jpg" = "01;35";
      ".jpeg" = "01;35";
      ".png" = "01;35";
      ".gif" = "01;35";
      ".bmp" = "01;35";
      ".svg" = "01;35";
      
      # Documents
      ".pdf" = "00;33";
      ".doc" = "00;33";
      ".docx" = "00;33";
      ".txt" = "00;37";
      ".md" = "00;37";
      
      # Source code
      ".c" = "00;36";
      ".cpp" = "00;36";
      ".h" = "00;36";
      ".hpp" = "00;36";
      ".rs" = "00;36";
      ".go" = "00;36";
      ".py" = "00;36";
      ".js" = "00;36";
      ".ts" = "00;36";
      ".jsx" = "00;36";
      ".tsx" = "00;36";
      ".nix" = "00;36";
      ".sh" = "00;36";
      ".bash" = "00;36";
      
      # Config files
      ".conf" = "00;33";
      ".config" = "00;33";
      ".yml" = "00;33";
      ".yaml" = "00;33";
      ".toml" = "00;33";
      ".json" = "00;33";
      ".xml" = "00;33";
    };
  };
}