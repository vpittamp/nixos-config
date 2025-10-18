# Clipcat Clipboard History Manager Configuration
# Implements FR-028 through FR-034c
{ config, lib, pkgs, ... }:

{
  # Install clipcat and clipboard tools
  home.packages = with pkgs; [
    clipcat
    xclip  # For tmux integration (FR-092, FR-093)
    xsel   # Alternative clipboard tool
  ];

  services.clipcat = {
    enable = true;
    package = pkgs.clipcat;

    # Daemon settings (FR-079 through FR-089)
    daemonSettings = {
      daemonize = true;
      max_history = 100;  # FR-080: Store 100 entries (meets SC-017: minimum 50)
      history_file_path = "${config.xdg.cacheHome}/clipcat/clipcatd-history";  # FR-081

      watcher = {
        # Monitor both X11 clipboard selections (FR-034, FR-082, FR-083)
        enable_clipboard = true;   # CLIPBOARD selection (Ctrl+C/V)
        enable_primary = true;     # PRIMARY selection (mouse select/middle-click)
        primary_threshold_ms = 5000;  # FR-084: Only update PRIMARY every 5 seconds

        # Sensitive content filtering (FR-034b, FR-085)
        denied_text_regex_patterns = [
          # Password patterns (16-128 chars with complexity)
          "^[A-Za-z0-9!@#$%^&*()_+\\-=\\[\\]{}|;:,.<>?]{16,128}$"

          # Credit card numbers
          "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b"

          # SSH private keys
          "-----BEGIN.*PRIVATE KEY-----"
          "-----BEGIN RSA PRIVATE KEY-----"
          "-----BEGIN OPENSSH PRIVATE KEY-----"

          # API tokens and secrets
          "(?i)(api[_-]?key|api[_-]?secret|token|bearer)[\\s:=]+[A-Za-z0-9_\\-]+"

          # JWT tokens
          "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"

          # AWS keys
          "AKIA[0-9A-Z]{16}"

          # GitHub tokens
          "gh[ps]_[A-Za-z0-9]{36,}"

          # Generic password indicators
          "(?i)(password|passwd|pwd)[\\s:=]+.+"
        ];

        # Content size limits (FR-086, FR-087)
        filter_text_min_length = 1;
        filter_text_max_length = 20000000;  # 20MB
        filter_image_max_size = 5242880;    # 5MB

        # MIME type filtering (optional)
        sensitive_mime_types = [];
      };

      # Enable image capture (FR-088)
      capture_image = true;
    };

    # Menu settings for rofi integration (FR-089)
    menuSettings = {
      finder = "rofi";
      rofi_config_path = "${config.xdg.configHome}/rofi/config.rasi";
    };
  };

  # The clipcat service automatically gets DISPLAY from the graphical-session.target
  # No additional systemd configuration needed - home-manager handles it
}
