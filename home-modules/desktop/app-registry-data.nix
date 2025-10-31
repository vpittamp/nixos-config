{ lib, ... }:

# Feature 034/035: Application Registry Data
#
# This file contains the validated application definitions that can be imported
# by multiple modules (app-registry.nix for generating files, i3-window-rules.nix
# for generating window rules, etc.)

let
  # Validation helper: check for dangerous characters
  validateParameters = params:
    if builtins.match ".*[;|&`].*" params != null then
      throw "Invalid parameters '${params}': contains shell metacharacters (;|&`)"
    else if builtins.match ".*\\$\\(.*" params != null then
      throw "Invalid parameters '${params}': contains command substitution $()"
    else if builtins.match ".*\\$\\{.*" params != null then
      throw "Invalid parameters '${params}': contains parameter expansion \${}"
    else
      params;

  # Helper to split parameters string into array (for TypeScript schema)
  splitParameters = params:
    if params == "" then []
    else lib.filter (s: s != "") (lib.splitString " " params);

  # Helper to determine if app requires terminal mode
  isTerminalApp = command:
    builtins.elem command ["alacritty" "ghostty" "kitty" "wezterm"];

  # Helper to create validated application entry
  mkApp = attrs:
    let
      params = if attrs ? parameters then validateParameters attrs.parameters else "";
    in
    attrs // {
      parameters = splitParameters params;
      terminal = isTerminalApp attrs.command;
    };

  applications = [
    # WS1: Terminals (Primary: alacritty)
    (mkApp {
      name = "terminal";
      display_name = "Alacritty Terminal";
      command = "alacritty";
      # Use sesh connect to attach/create tmux session in project directory
      # sesh will use PROJECT_DIR as session directory context
      parameters = "-e sesh connect $PROJECT_DIR";
      scope = "scoped";
      expected_class = "Alacritty";
      preferred_workspace = 1;
      icon = "terminal";
      nix_package = "pkgs.alacritty";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Terminal with sesh session management for project directory";
    })

    # WS2: Editors (Primary: vscode)
    (mkApp {
      name = "vscode";
      display_name = "VS Code";
      command = "code";
      parameters = "--disable-gpu --disable-software-rasterizer --new-window $PROJECT_DIR";
      scope = "scoped";
      expected_class = "Code";
      preferred_workspace = 2;
      icon = "vscode";
      nix_package = "pkgs.vscode";
      multi_instance = true;
      fallback_behavior = "skip";
      description = "Visual Studio Code editor with project context";
    })

    (mkApp {
      name = "neovim";
      display_name = "Neovim";
      command = "alacritty";
      # parameters = "-e nvim $PROJECT_DIR";
      parameters = "-e nvim /etc/nixos/home-vpittamp.nix";
      scope = "scoped";
      expected_class = "Alacritty";
      preferred_workspace = 13;
      icon = "nvim";
      nix_package = "pkgs.neovim";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Neovim text editor in terminal";
    })

    (mkApp {
      name = "github-codespaces-pwa";
      display_name = "GitHub Codespaces";
      command = "firefoxpwa";
      parameters = "site launch 01K78K7W5MNT8TDEW2G23ZEM5S";
      scope = "global";
      expected_class = "FFPWA-01K78K7W5MNT8TDEW2G23ZEM5S";
      preferred_workspace = 2;
      icon = "FFPWA-01K78K7W5MNT8TDEW2G23ZEM5S";
      nix_package = "pkgs.firefoxpwa";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "GitHub cloud development environment";
    })

    # WS3: Browsers (Primary: firefox)
    (mkApp {
      name = "firefox";
      display_name = "Firefox";
      command = "firefox";
      parameters = "";
      scope = "global";
      expected_class = "firefox";
      preferred_workspace = 3;
      icon = "firefox";
      nix_package = "pkgs.firefox";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Mozilla Firefox web browser";
    })

    (mkApp {
      name = "chromium";
      display_name = "Chromium";
      command = "chromium";
      parameters = "";
      scope = "global";
      expected_class = "Chromium-browser";
      preferred_workspace = 3;
      icon = "chromium";
      nix_package = "pkgs.chromium";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Chromium web browser";
    })

    # WS4: YouTube PWA
    (mkApp {
      name = "youtube-pwa";
      display_name = "YouTube";
      command = "firefoxpwa";
      parameters = "site launch 01K663E3K8FMGTFVQ6Z6Q2RX7X";
      scope = "scoped";
      expected_class = "FFPWA-01K663E3K8FMGTFVQ6Z6Q2RX7X";
      preferred_workspace = 4;
      icon = "FFPWA-01K663E3K8FMGTFVQ6Z6Q2RX7X";
      nix_package = "pkgs.firefoxpwa";
      multi_instance = false;
      fallback_behavior = "use_home";
      description = "YouTube video platform";
    })

    # WS10: Google AI PWA (beyond standard 1-9)
    (mkApp {
      name = "google-ai-pwa";
      display_name = "Google AI";
      command = "firefoxpwa";
      parameters = "site launch 01K664F9E8KXZPXYF4V1Q8A93V";
      scope = "scoped";
      expected_class = "FFPWA-01K664F9E8KXZPXYF4V1Q8A93V";
      preferred_workspace = 10;
      icon = "FFPWA-01K664F9E8KXZPXYF4V1Q8A93V";
      nix_package = "pkgs.firefoxpwa";
      multi_instance = false;
      fallback_behavior = "use_home";
      description = "Google AI assistant";
    })

    # WS11: ChatGPT PWA
    (mkApp {
      name = "chatgpt-pwa";
      display_name = "ChatGPT";
      command = "firefoxpwa";
      parameters = "site launch 01K78K7ZQ1190KKGYZ6WJ0HDWX";
      scope = "scoped";
      expected_class = "FFPWA-01K78K7ZQ1190KKGYZ6WJ0HDWX";
      preferred_workspace = 11;
      icon = "FFPWA-01K78K7ZQ1190KKGYZ6WJ0HDWX";
      nix_package = "pkgs.firefoxpwa";
      multi_instance = false;
      fallback_behavior = "use_home";
      description = "ChatGPT AI assistant";
    })

    # WS5: Git Tools (Primary: lazygit)
    (mkApp {
      name = "lazygit";
      display_name = "Lazygit";
      command = "alacritty";
      parameters = "-e lazygit --work-tree=$PROJECT_DIR";
      scope = "scoped";
      expected_class = "Alacritty";
      preferred_workspace = 5;
      icon = "git";
      nix_package = "pkgs.lazygit";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Terminal UI for git commands";
    })

    # WS6: GUI File Managers (Primary: thunar)
    (mkApp {
      name = "thunar";
      display_name = "Thunar";
      command = "thunar";
      parameters = "$PROJECT_DIR";
      scope = "scoped";
      expected_class = "Thunar";
      preferred_workspace = 6;
      icon = "thunar";
      nix_package = "pkgs.xfce.thunar";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Xfce file manager";
    })

    # WS7: System Monitors (Primary: btop)
    (mkApp {
      name = "btop";
      display_name = "btop";
      command = "alacritty";
      parameters = "--class btop -e btop";
      scope = "global";
      expected_class = "btop";
      preferred_workspace = 7;
      icon = "utilities-system-monitor";
      nix_package = "pkgs.btop";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Resource monitor with better visuals";
    })

    (mkApp {
      name = "htop";
      display_name = "htop";
      command = "alacritty";
      parameters = "--class htop -e htop";
      scope = "global";
      expected_class = "htop";
      preferred_workspace = 7;
      icon = "utilities-system-monitor";
      nix_package = "pkgs.htop";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Interactive process viewer";
    })

    # WS8: Terminal File Manager (Primary: yazi)
    (mkApp {
      name = "yazi";
      display_name = "Yazi File Manager";
      command = "alacritty";
      parameters = "-e yazi $PROJECT_DIR";
      scope = "scoped";
      expected_class = "Alacritty";
      preferred_workspace = 8;
      icon = "folder";
      nix_package = "pkgs.yazi";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Terminal file manager";
    })

    # WS9: Kubernetes (Primary: k9s)
    (mkApp {
      name = "k9s";
      display_name = "K9s";
      command = "alacritty";
      parameters = "--class k9s -e k9s";
      scope = "global";
      expected_class = "k9s";
      preferred_workspace = 9;
      icon = "kubernetes";
      nix_package = "pkgs.k9s";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Kubernetes cluster management";
    })

    # WS12: Ghostty Terminal (backup terminal, less frequently used)
    (mkApp {
      name = "ghostty";
      display_name = "Ghostty Terminal";
      command = "ghostty";
      parameters = "";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 12;
      icon = "terminal";
      nix_package = "pkgs.ghostty";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Ghostty terminal (backup option)";
    })

    # WS14: TigerVNC Viewer (generic VNC client)
    (mkApp {
      name = "tigervnc";
      display_name = "TigerVNC Viewer";
      command = "vncviewer";
      parameters = "-Scale=Auto";
      scope = "global";
      expected_class = "Vncviewer";
      preferred_workspace = 14;
      icon = "preferences-desktop-remote-desktop";
      nix_package = "pkgs.tigervnc";
      multi_instance = true;
      fallback_behavior = "skip";
      description = "VNC client with auto-scaling";
    })

    # WS15-17: Hetzner Cloud VNC Displays (pre-configured connections)
    (mkApp {
      name = "hetzner-display-1";
      display_name = "Hetzner Display 1";
      command = "vncviewer";
      parameters = "-Scale=Auto 100.87.204.44:5900";
      scope = "global";
      expected_class = "Vncviewer";
      preferred_workspace = 15;
      icon = "preferences-desktop-remote-desktop";
      nix_package = "pkgs.tigervnc";
      multi_instance = true;
      fallback_behavior = "skip";
      description = "Hetzner VNC Display 1 (Workspaces 1-2)";
    })

    (mkApp {
      name = "hetzner-display-2";
      display_name = "Hetzner Display 2";
      command = "vncviewer";
      parameters = "-Scale=Auto 100.87.204.44:5901";
      scope = "global";
      expected_class = "Vncviewer";
      preferred_workspace = 16;
      icon = "preferences-desktop-remote-desktop";
      nix_package = "pkgs.tigervnc";
      multi_instance = true;
      fallback_behavior = "skip";
      description = "Hetzner VNC Display 2 (Workspaces 3-5)";
    })

    (mkApp {
      name = "hetzner-display-3";
      display_name = "Hetzner Display 3";
      command = "vncviewer";
      parameters = "-Scale=Auto 100.87.204.44:5902";
      scope = "global";
      expected_class = "Vncviewer";
      preferred_workspace = 17;
      icon = "preferences-desktop-remote-desktop";
      nix_package = "pkgs.tigervnc";
      multi_instance = true;
      fallback_behavior = "skip";
      description = "Hetzner VNC Display 3 (Workspaces 6-9)";
    })
  ];

  # Additional validation: check for duplicate names
  appNames = map (app: app.name) applications;
  duplicates = lib.filter (name:
    (lib.length (lib.filter (n: n == name) appNames)) > 1
  ) (lib.unique appNames);

  # Additional validation: check workspace range (1-20 for flexibility)
  invalidWorkspaces = lib.filter (app:
    app ? preferred_workspace && (app.preferred_workspace < 1 || app.preferred_workspace > 20)
  ) applications;

  # Additional validation: check name format (kebab-case)
  invalidNames = lib.filter (app:
    builtins.match "[a-z0-9-]+" app.name == null
  ) applications;

  # Perform all validations
  validated =
    if duplicates != [] then
      throw "Duplicate application names found: ${builtins.concatStringsSep ", " duplicates}"
    else if invalidWorkspaces != [] then
      throw "Invalid workspace numbers (must be 1-20): ${builtins.concatStringsSep ", " (map (app: app.name) invalidWorkspaces)}"
    else if invalidNames != [] then
      throw "Invalid application names (must be kebab-case): ${builtins.concatStringsSep ", " (map (app: app.name) invalidNames)}"
    else
      applications;

in
# Export just the validated applications list
validated
