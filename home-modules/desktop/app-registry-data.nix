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
    builtins.elem command ["ghostty" "alacritty" "kitty" "wezterm"];

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
    # Development Tools (Scoped) - Workspace 1

    (mkApp {
      name = "vscode";
      display_name = "VS Code";
      command = "code";
      parameters = "--new-window $PROJECT_DIR";
      scope = "scoped";
      expected_class = "Code";
      preferred_workspace = 1;
      icon = "vscode";
      nix_package = "pkgs.vscode";
      multi_instance = true;
      fallback_behavior = "skip";
      description = "Visual Studio Code editor with project context";
    })

    (mkApp {
      name = "neovim";
      display_name = "Neovim";
      command = "ghostty";
      # parameters = "-e nvim $PROJECT_DIR";
      parameters = "-e nvim /etc/nixos/home-vpittamp.nix";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 1;
      icon = "nvim";
      nix_package = "pkgs.neovim";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Neovim text editor in terminal";
    })

    # Browsers (Global) - Workspace 2

    (mkApp {
      name = "firefox";
      display_name = "Firefox";
      command = "firefox";
      parameters = "";
      scope = "global";
      expected_class = "firefox";
      preferred_workspace = 2;
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
      expected_class = "Chromium";
      preferred_workspace = 2;
      icon = "chromium";
      nix_package = "pkgs.chromium";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Chromium web browser";
    })

    # Terminals (Scoped) - Workspace 3

    (mkApp {
      name = "ghostty";
      display_name = "Ghostty Terminal";
      command = "ghostty";
      parameters = "-e sesh connect $PROJECT_DIR";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 3;
      icon = "terminal";
      nix_package = "pkgs.ghostty";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Terminal with automatic sesh session for project directory";
    })

    (mkApp {
      name = "terminal";
      display_name = "Terminal (Sesh Selector)";
      command = "ghostty";
      parameters = "-e sesh";
      scope = "global";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 3;
      icon = "terminal";
      nix_package = "pkgs.ghostty";
      multi_instance = true;
      fallback_behavior = "skip";
      description = "Terminal with sesh session selector";
    })

    (mkApp {
      name = "alacritty";
      display_name = "Alacritty Terminal";
      command = "alacritty";
      parameters = "--working-directory $PROJECT_DIR";
      scope = "scoped";
      expected_class = "Alacritty";
      preferred_workspace = 3;
      icon = "terminal";
      nix_package = "pkgs.alacritty";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "GPU-accelerated terminal emulator";
    })

    # Git Tools (Scoped) - Workspace 3

    (mkApp {
      name = "lazygit";
      display_name = "Lazygit";
      command = "ghostty";
      parameters = "-e lazygit --work-tree=$PROJECT_DIR";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 3;
      icon = "git";
      nix_package = "pkgs.lazygit";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Terminal UI for git commands";
    })

    (mkApp {
      name = "gitui";
      display_name = "GitUI";
      command = "ghostty";
      parameters = "-e gitui --workdir $PROJECT_DIR";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 3;
      icon = "git";
      nix_package = "pkgs.gitui";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Blazing fast terminal UI for git";
    })

    # File Managers (Scoped) - Workspace 4

    (mkApp {
      name = "yazi";
      display_name = "Yazi File Manager";
      command = "yazi";
      parameters = "$PROJECT_DIR";
      scope = "scoped";
      expected_class = "yazi";
      preferred_workspace = 4;
      icon = "folder";
      nix_package = "pkgs.yazi";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Terminal file manager";
    })

    (mkApp {
      name = "thunar";
      display_name = "Thunar";
      command = "thunar";
      parameters = "$PROJECT_DIR";
      scope = "scoped";
      expected_class = "Thunar";
      preferred_workspace = 4;
      icon = "thunar";
      nix_package = "pkgs.xfce.thunar";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Xfce file manager";
    })

    (mkApp {
      name = "pcmanfm";
      display_name = "PCManFM";
      command = "pcmanfm";
      parameters = "$PROJECT_DIR";
      scope = "scoped";
      expected_class = "Pcmanfm";
      preferred_workspace = 4;
      icon = "system-file-manager";
      nix_package = "pkgs.pcmanfm";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Lightweight file manager";
    })

    # System Tools (Global) - Workspace 5

    (mkApp {
      name = "htop";
      display_name = "htop";
      command = "ghostty";
      parameters = "-e htop";
      scope = "global";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 5;
      icon = "utilities-system-monitor";
      nix_package = "pkgs.htop";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Interactive process viewer";
    })

    (mkApp {
      name = "btop";
      display_name = "btop";
      command = "ghostty";
      parameters = "-e btop";
      scope = "global";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 5;
      icon = "utilities-system-monitor";
      nix_package = "pkgs.btop";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Resource monitor with better visuals";
    })

    (mkApp {
      name = "k9s";
      display_name = "K9s";
      command = "ghostty";
      parameters = "-e k9s";
      scope = "global";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 5;
      icon = "kubernetes";
      nix_package = "pkgs.k9s";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Kubernetes cluster management";
    })

    # Communication (Global) - Workspace 6

    (mkApp {
      name = "slack";
      display_name = "Slack";
      command = "slack";
      parameters = "";
      scope = "global";
      expected_class = "Slack";
      preferred_workspace = 6;
      icon = "slack";
      nix_package = "pkgs.slack";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Team communication platform";
    })

    (mkApp {
      name = "discord";
      display_name = "Discord";
      command = "discord";
      parameters = "";
      scope = "global";
      expected_class = "discord";
      preferred_workspace = 6;
      icon = "discord";
      nix_package = "pkgs.discord";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Voice and text chat platform";
    })

    # PWA Applications (Workspace 7)

    (mkApp {
      name = "youtube-pwa";
      display_name = "YouTube";
      command = "firefoxpwa";
      parameters = "site launch 01K666N2V6BQMDSBMX3AY74TY7";
      scope = "global";
      expected_class = "FFPWA-01K666N2V6BQMDSBMX3AY74TY7";
      preferred_workspace = 7;
      icon = "FFPWA-01K666N2V6BQMDSBMX3AY74TY7";
      nix_package = "pkgs.firefoxpwa";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "YouTube video platform";
    })

    (mkApp {
      name = "google-ai-pwa";
      display_name = "Google AI";
      command = "firefoxpwa";
      parameters = "site launch 01K665SPD8EPMP3JTW02JM1M0Z";
      scope = "global";
      expected_class = "FFPWA-01K665SPD8EPMP3JTW02JM1M0Z";
      preferred_workspace = 7;
      icon = "FFPWA-01K665SPD8EPMP3JTW02JM1M0Z";
      nix_package = "pkgs.firefoxpwa";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Google AI assistant";
    })

    (mkApp {
      name = "chatgpt-pwa";
      display_name = "ChatGPT";
      command = "firefoxpwa";
      parameters = "site launch 01K772ZBM45JD68HXYNM193CVW";
      scope = "global";
      expected_class = "FFPWA-01K772ZBM45JD68HXYNM193CVW";
      preferred_workspace = 7;
      icon = "FFPWA-01K772ZBM45JD68HXYNM193CVW";
      nix_package = "pkgs.firefoxpwa";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "ChatGPT AI assistant";
    })

    (mkApp {
      name = "github-codespaces-pwa";
      display_name = "GitHub Codespaces";
      command = "firefoxpwa";
      parameters = "site launch 01K772Z7AY5J36Q3NXHH9RYGC0";
      scope = "global";
      expected_class = "FFPWA-01K772Z7AY5J36Q3NXHH9RYGC0";
      preferred_workspace = 1;
      icon = "FFPWA-01K772Z7AY5J36Q3NXHH9RYGC0";
      nix_package = "pkgs.firefoxpwa";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "GitHub cloud development environment";
    })
  ];

  # Additional validation: check for duplicate names
  appNames = map (app: app.name) applications;
  duplicates = lib.filter (name:
    (lib.length (lib.filter (n: n == name) appNames)) > 1
  ) (lib.unique appNames);

  # Additional validation: check workspace range
  invalidWorkspaces = lib.filter (app:
    app ? preferred_workspace && (app.preferred_workspace < 1 || app.preferred_workspace > 9)
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
      throw "Invalid workspace numbers (must be 1-9): ${builtins.concatStringsSep ", " (map (app: app.name) invalidWorkspaces)}"
    else if invalidNames != [] then
      throw "Invalid application names (must be kebab-case): ${builtins.concatStringsSep ", " (map (app: app.name) invalidNames)}"
    else
      applications;

in
# Export just the validated applications list
validated
