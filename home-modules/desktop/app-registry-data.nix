{ lib, ... }:

# Feature 034/035: Application Registry Data
# Feature 057: Environment Variable-Based Window Matching
#
# This file contains the validated application definitions that can be imported
# by multiple modules (app-registry.nix for generating files, i3-window-rules.nix
# for generating window rules, etc.)
#
# IMPORTANT - Feature 057 Changes:
#
# 1. `expected_class` field:
#    - Used for VALIDATION ONLY (not for window matching)
#    - Window matching uses I3PM_APP_NAME from environment variables
#    - expected_class helps debug mismatches between env vars and actual window class
#    - Example: expected_class="FFPWA-01JCYF8Z2M" validates PWA window class
#
# 2. `aliases` field (if present):
#    - Used for LAUNCHER SEARCH ONLY (not for window matching)
#    - Allows users to find apps by alternative names in rofi/walker
#    - Window identification never uses aliases (uses I3PM_APP_NAME directly)
#    - Example: aliases=["code", "vsc"] allows launching VS Code via "code" or "vsc"
#
# 3. Window Matching Flow (Feature 057):
#    - Application launched → wrapper injects I3PM_APP_NAME, I3PM_APP_ID, etc.
#    - Window appears → daemon reads /proc/<pid>/environ
#    - Match uses I3PM_APP_NAME (not window class or aliases)
#    - Result: 15-27x faster, 100% deterministic, zero race conditions

let
  # Import centralized PWA site definitions (Feature 056)
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib; };
  pwas = pwaSitesConfig.pwaSites;
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

  # Helper to convert PWA site definition → app registry entry (Feature 056)
  mkPWAApp = pwa: mkApp {
    name = "${lib.toLower (lib.replaceStrings [" "] ["-"] pwa.name)}-pwa";
    display_name = pwa.name;
    command = "launch-pwa-by-name";
    parameters = pwa.ulid;  # Use ULID for reliable PWA launch
    scope = pwa.app_scope;
    expected_class = "FFPWA-${pwa.ulid}";  # NOW CORRECT with declarative ULIDs!
    preferred_workspace = pwa.preferred_workspace;
    icon = lib.toLower (lib.replaceStrings [" "] ["-"] pwa.name);
    nix_package = "pkgs.firefoxpwa";
    multi_instance = false;
    fallback_behavior = "use_home";
    description = pwa.description;
  };

  applications = [
    # TERMINAL APPLICATIONS OVERVIEW:
    # 1. Regular terminals (name="terminal", "ghostty"): Use sesh for smart tmux session management
    # 2. Scratchpad terminal (name="scratchpad-terminal"): Uses tmux directly with scratchpad-{project} naming
    #    - Scratchpad is launched by daemon, not via app registry wrapper
    #    - Provides quick floating terminal access per project

    # WS1: Terminals (Primary: ghostty with sesh)
    (mkApp {
      name = "terminal";
      display_name = "Ghostty Terminal";
      command = "ghostty";
      # Use sesh connect to attach/create tmux session in project directory
      # sesh will use PROJECT_DIR as session directory context
      parameters = "-e sesh connect $PROJECT_DIR";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 1;
      icon = "com.mitchellh.ghostty";
      nix_package = "pkgs.ghostty";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Regular terminal with sesh session management for project directory";
    })

    # WS2: Editors (Primary: code)
    (mkApp {
      name = "code";
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
      name = "nvim";
      display_name = "Neovim";
      command = "ghostty";
      # parameters = "-e nvim $PROJECT_DIR";
      parameters = "-e nvim /etc/nixos/home-vpittamp.nix";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 13;
      icon = "nvim";
      nix_package = "pkgs.neovim";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Neovim text editor in terminal";
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
      name = "chromium-browser";
      display_name = "Chromium";
      command = "chromium";
      parameters = "";
      scope = "global";
      expected_class = "Chromium-browser";
      preferred_workspace = 3;
      icon = "chromium-browser";
      nix_package = "pkgs.chromium";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Chromium web browser";
    })

    # WS5: Git Tools (Primary: lazygit)
    (mkApp {
      name = "lazygit";
      display_name = "Lazygit";
      command = "ghostty";
      parameters = "-e lazygit --work-tree=$PROJECT_DIR";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
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
      command = "ghostty";
      parameters = "-e btop";
      scope = "global";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 7;
      icon = "btop";
      nix_package = "pkgs.btop";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Resource monitor with better visuals";
    })

    (mkApp {
      name = "htop";
      display_name = "htop";
      command = "ghostty";
      parameters = "-e htop";
      scope = "global";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 7;
      icon = "htop";
      nix_package = "pkgs.htop";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Interactive process viewer";
    })

    # WS8: Terminal File Manager (Primary: yazi)
    (mkApp {
      name = "yazi";
      display_name = "Yazi File Manager";
      command = "ghostty";
      parameters = "-e yazi $PROJECT_DIR";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 8;
      icon = "system-file-manager";
      nix_package = "pkgs.yazi";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Terminal file manager";
    })

    # WS9: Kubernetes (Primary: k9s)
    (mkApp {
      name = "k9s";
      display_name = "K9s";
      command = "ghostty";
      parameters = "-e k9s";
      scope = "global";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 9;
      icon = "/etc/nixos/assets/pwa-icons/k9s.png";
      nix_package = "pkgs.k9s";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Kubernetes cluster management";
    })


    # Scratchpad Terminal (Feature 062)
    # Special floating terminal for quick project access
    # NOTE: Launched by daemon via Sway IPC, not through wrapper
    # Parameters shown here are for documentation/reference only
    (mkApp {
      name = "scratchpad-terminal";
      display_name = "Scratchpad Terminal";
      command = "ghostty";
      # Actual launch command (via daemon): ghostty -e bash -c 'tmux new-session -A -s scratchpad-{project} -c {working_dir}'
      # This creates/attaches to project-specific tmux session named "scratchpad-{project}"
      parameters = "-e bash -c 'tmux new-session -A -s scratchpad-PROJECT -c PROJECT_DIR'";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 1;  # Default to workspace 1, but managed dynamically
      icon = "com.mitchellh.ghostty";
      nix_package = "pkgs.ghostty";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Project-scoped floating scratchpad terminal with tmux session (scratchpad-{project})";
    })

    # FZF File Search (floating)
    # Global fuzzy file finder with bat preview that opens files in nvim
    # Always launches new instance (via --force flag in keybinding)
    # Note: Runs in Ghostty with title "FZF File Search" for window rule matching
    (mkApp {
      name = "fzf-file-search";
      display_name = "FZF File Search";
      command = "fzf-file-search";
      parameters = "";
      scope = "global";
      expected_class = "com.mitchellh.ghostty";  # Ghostty's app_id, matched by title
      preferred_workspace = 1;  # Floating, doesn't matter
      icon = "system-search";
      nix_package = "pkgs.fzf";
      multi_instance = true;  # Allow multiple search windows
      fallback_behavior = "skip";
      description = "Floating fuzzy file finder with preview that opens files in nvim";
    })
  ]
  # Auto-generate PWA entries from pwa-sites.nix (Feature 056)
  # All PWAs will have correct expected_class with declarative ULIDs
  # This provides workspace assignments and window rules for i3pm
  ++ (builtins.map mkPWAApp pwas);

  # Additional validation: check for duplicate names
  appNames = map (app: app.name) applications;
  duplicates = lib.filter (name:
    (lib.length (lib.filter (n: n == name) appNames)) > 1
  ) (lib.unique appNames);

  # Additional validation: check workspace range (1-70 to accommodate PWAs on WS 50-64)
  invalidWorkspaces = lib.filter (app:
    app ? preferred_workspace && (app.preferred_workspace < 1 || app.preferred_workspace > 70)
  ) applications;

  # Additional validation: check name format (kebab-case or reverse-domain notation)
  # Allows: kebab-case (foo-bar) and reverse-domain (com.example.app)
  invalidNames = lib.filter (app:
    builtins.match "[a-z0-9.-]+" app.name == null
  ) applications;

  # Perform all validations
  validated =
    if duplicates != [] then
      throw "Duplicate application names found: ${builtins.concatStringsSep ", " duplicates}"
    else if invalidWorkspaces != [] then
      throw "Invalid workspace numbers (must be 1-20): ${builtins.concatStringsSep ", " (map (app: app.name) invalidWorkspaces)}"
    else if invalidNames != [] then
      throw "Invalid application names (must be kebab-case or reverse-domain): ${builtins.concatStringsSep ", " (map (app: app.name) invalidNames)}"
    else
      applications;

in
# Export just the validated applications list
validated
