{ lib, assetsPackage ? null, hostName ? "", ... }:

# Feature 034/035: Application Registry Data
# Feature 106: Portable icon paths via assetsPackage
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
  # Feature 106: Helper to get icon path from Nix store or fallback to legacy path
  # When assetsPackage is provided, use store paths; otherwise fall back to /etc/nixos
  iconPath = name:
    if assetsPackage != null
    then "${assetsPackage}/icons/${name}"
    else "/etc/nixos/assets/icons/${name}";

  # Import centralized PWA site definitions (Feature 056)
  # Pass assetsPackage for portable icon paths
  # Feature 125: Pass hostName for host-specific parameterization
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib assetsPackage hostName; };
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

  # Feature 001: Validate monitor role enum (primary/secondary/tertiary)
  validateMonitorRole = role:
    let
      normalizedRole = lib.toLower role;
      validRoles = ["primary" "secondary" "tertiary"];
    in
    if !builtins.elem normalizedRole validRoles then
      throw "Invalid monitor role '${role}': must be one of ${lib.concatStringsSep ", " validRoles}"
    else
      normalizedRole;

  # Feature 001 US4: Validate floating size preset (scratchpad/small/medium/large)
  validateFloatingSize = size:
    let
      normalizedSize = lib.toLower size;
      validSizes = ["scratchpad" "small" "medium" "large"];
    in
    if !builtins.elem normalizedSize validSizes then
      throw "Invalid floating size '${size}': must be one of ${lib.concatStringsSep ", " validSizes}"
    else
      normalizedSize;

  # Helper to create validated application entry
  mkApp = attrs:
    let
      params = if attrs ? parameters then validateParameters attrs.parameters else "";
      # Feature 001: Validate and normalize monitor role if present
      monitorRole =
        if attrs ? preferred_monitor_role && attrs.preferred_monitor_role != null
        then validateMonitorRole attrs.preferred_monitor_role
        else null;
      # Feature 001 US4: Validate and normalize floating size if present
      floatingSize =
        if attrs ? floating_size && attrs.floating_size != null
        then validateFloatingSize attrs.floating_size
        else null;
    in
    attrs // {
      parameters = splitParameters params;
      terminal = isTerminalApp attrs.command;
      # Feature 001: Add normalized monitor role
      preferred_monitor_role = monitorRole;
      # Feature 001 US4: Add normalized floating size (T049, T050)
      floating = if attrs ? floating then attrs.floating else false;
      floating_size = floatingSize;
      # Feature 101: Scratchpad flag - apps with scratchpad=true use workspace 0
      # and are managed by the scratchpad system (one per worktree)
      scratchpad = if attrs ? scratchpad then attrs.scratchpad else false;
    };

  # Helper to convert PWA site definition → app registry entry (Feature 056)
  mkPWAApp = pwa: mkApp ({
    name = "${lib.toLower (lib.replaceStrings [" "] ["-"] pwa.name)}-pwa";
    display_name = pwa.name;
    command = "launch-pwa-by-name";
    parameters = pwa.ulid;  # Use ULID for reliable PWA launch
    scope = pwa.app_scope;
    expected_class = "FFPWA-${pwa.ulid}";  # NOW CORRECT with declarative ULIDs!
    preferred_workspace = pwa.preferred_workspace;
    icon = pwa.icon;  # Use icon from PWA definition (absolute path)
    nix_package = "pkgs.firefoxpwa";
    multi_instance = false;
    fallback_behavior = "use_home";
    description = pwa.description;
  } // lib.optionalAttrs (pwa ? preferred_monitor_role) {
    # Feature 001: Pass through PWA monitor role preference
    preferred_monitor_role = pwa.preferred_monitor_role;
  });

  applications = [
    # TERMINAL APPLICATIONS OVERVIEW:
    # 1. Regular terminals (name="terminal", "ghostty"): Use sesh for smart tmux session management
    # 2. Scratchpad terminal (name="scratchpad-terminal"): Uses tmux directly with scratchpad-{project} naming
    #    - Scratchpad is launched by daemon, not via app registry wrapper
    #    - Provides quick floating terminal access per project

    # WS1: Terminals (Primary: ghostty with sesh)
    (mkApp {
      name = "terminal";
      display_name = "Terminal";
      command = "ghostty";
      # Use sesh connect to attach/create tmux session in project directory
      # sesh will use PROJECT_DIR as session directory context
      parameters = "-e sesh connect $PROJECT_DIR";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 1;
      preferred_monitor_role = "primary";
      icon = iconPath "tmux-original.svg";
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
      preferred_monitor_role = "secondary";
      icon = "vscode";
      nix_package = "pkgs.vscode";
      multi_instance = true;
      fallback_behavior = "skip";
      description = "Visual Studio Code editor with project context";
    })

    # NOTE: Antigravity disabled - x86_64 only (no ARM64/aarch64 build available)
    # Package defined in home-modules/hetzner-sway.nix for Hetzner Cloud only
    # (mkApp {
    #   name = "antigravity";
    #   display_name = "Antigravity";
    #   command = "antigravity";
    #   parameters = "";
    #   scope = "global";
    #   expected_class = "Antigravity";
    #   preferred_workspace = 2;
    #   preferred_monitor_role = "secondary";
    #   icon = "antigravity"; # installed by custom package
    #   nix_package = "antigravity";
    #   multi_instance = true;
    #   fallback_behavior = "skip";
    #   description = "Google Antigravity IDE with embedded agent tools";
    # })

    (mkApp {
      name = "nvim";
      display_name = "Neovim";
      command = "ghostty";
      # Launch Neovim directly in the active project directory
      parameters = "-e nvim $PROJECT_DIR";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 4;
      preferred_monitor_role = "secondary";
      icon = iconPath "neovim.svg";
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
      preferred_monitor_role = "tertiary";
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

    # WS15: Google Chrome - Required for Claude in Chrome extension
    (mkApp {
      name = "google-chrome";
      display_name = "Google Chrome";
      command = "google-chrome-stable";
      parameters = "";
      scope = "global";
      expected_class = "Google-chrome";
      preferred_workspace = 15;
      icon = "google-chrome";
      nix_package = "pkgs.google-chrome";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Google Chrome browser with Claude in Chrome support";
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
      preferred_monitor_role = "tertiary";
      icon = iconPath "lazygit.svg";
      nix_package = "pkgs.lazygit";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Terminal UI for git commands";
    })

    # WS13: Docker Tools (lazydocker)
    (mkApp {
      name = "lazydocker";
      display_name = "Lazydocker";
      command = "ghostty";
      parameters = "-e lazydocker";
      scope = "global";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 13;
      preferred_monitor_role = "tertiary";
      icon = iconPath "lazydocker.svg";
      nix_package = "pkgs.lazydocker";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Terminal UI for Docker container management";
    })

    # WS5: GUI Git Client (gittyup)
    (mkApp {
      name = "gittyup";
      display_name = "Gittyup";
      command = "gittyup";
      parameters = "$PROJECT_DIR";
      scope = "scoped";
      expected_class = "Gittyup";
      preferred_workspace = 5;
      preferred_monitor_role = "tertiary";
      icon = iconPath "git.svg";
      nix_package = "pkgs.gittyup";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Qt-based GUI git client";
    })

    # WS14: GitKraken (Feature-rich Git GUI)
    (mkApp {
      name = "gitkraken";
      display_name = "GitKraken";
      command = "gitkraken";
      parameters = "--path $PROJECT_DIR";
      scope = "scoped";
      expected_class = "GitKraken";
      preferred_workspace = 14;
      preferred_monitor_role = "secondary";
      icon = "gitkraken";
      nix_package = "pkgs.gitkraken";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Feature-rich Git GUI client with GitHub integration";
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
      icon = iconPath "thunar.svg";
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
      icon = iconPath "yazi.png";
      nix_package = "pkgs.yazi";
      multi_instance = true;
      fallback_behavior = "use_home";
      description = "Terminal file manager";
    })

    # WS9: Kubernetes (Primary: k9s)
    # Uses sesh for tmux session persistence - can detach/reattach
    (mkApp {
      name = "k9s";
      display_name = "K9s";
      command = "ghostty";
      parameters = "-e sesh connect k9s";
      scope = "global";
      expected_class = "com.mitchellh.ghostty";
      preferred_workspace = 9;
      icon = iconPath "k9s.png";
      nix_package = "pkgs.k9s";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Kubernetes cluster management via Tailscale";
    })

    # WS10: Kubernetes UI (Primary: headlamp)
    (mkApp {
      name = "headlamp";
      display_name = "Headlamp";
      command = "headlamp";
      parameters = "--disable-gpu";
      scope = "global";
      expected_class = "Headlamp";
      preferred_workspace = 10;
      icon = iconPath "headlamp.svg";
      nix_package = "pkgs.headlamp";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Kubernetes web UI for cluster management via Tailscale";
    })

    # WS11: AI Agents (Primary: goose-desktop) - HEADLESS-1
    (mkApp {
      name = "goose-desktop";
      display_name = "Goose AI Agent";
      command = "goose-desktop";
      parameters = "";
      scope = "global";
      expected_class = "goose";  # Electron app class
      preferred_workspace = 11;
      preferred_monitor_role = "primary";  # Always on HEADLESS-1
      icon = iconPath "goose.svg";
      nix_package = "pkgs.goose-desktop";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Open-source AI agent with desktop interface";
    })

    # WS12: Remote Access (Primary: remmina)
    (mkApp {
      name = "remmina";
      display_name = "Remmina";
      command = "remmina";
      parameters = "";
      scope = "global";
      expected_class = "org.remmina.Remmina";
      preferred_workspace = 12;
      icon = "org.remmina.Remmina";
      nix_package = "pkgs.remmina";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Remote desktop client for VNC, RDP, SSH connections";
    })

    (mkApp {
      name = "moonlight";
      display_name = "Moonlight";
      command = "moonlight";
      parameters = "";
      scope = "global";
      expected_class = "com.moonlight_stream.Moonlight";
      preferred_workspace = 12;
      icon = "com.moonlight_stream.Moonlight";
      nix_package = "pkgs.moonlight-qt";
      multi_instance = false;
      fallback_behavior = "skip";
      description = "Moonlight game streaming client";
    })

    # Scratchpad Terminal (Feature 062, Feature 101)
    # Special floating terminal for quick project access
    # NOTE: Launched by daemon via Sway IPC, not through wrapper
    # Parameters shown here are for documentation/reference only
    # Feature 101: Uses workspace 0 as marker for scratchpad windows
    # One scratchpad terminal per worktree - toggle focuses existing if present
    (mkApp {
      name = "scratchpad-terminal";
      display_name = "Scratchpad Terminal";
      command = "ghostty";
      # Actual launch command (via daemon): ghostty -e bash -c 'tmux new-session -A -s scratchpad-{project} -c {working_dir}'
      # This creates/attaches to project-specific tmux session named "scratchpad-{project}"
      parameters = "-e bash -c 'tmux new-session -A -s scratchpad-PROJECT -c PROJECT_DIR'";
      scope = "scoped";
      expected_class = "com.mitchellh.ghostty";
      # Feature 101: Workspace 0 = scratchpad home (not a real workspace)
      # Used for deterministic tracking - scratchpad windows always have workspace_number=0
      preferred_workspace = 0;
      scratchpad = true;  # Feature 101: Mark as scratchpad-managed app
      icon = "com.mitchellh.ghostty";
      nix_package = "pkgs.ghostty";
      multi_instance = false;  # Feature 101: One per worktree, toggle focuses existing
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

  # Additional validation: check workspace range
  # Scratchpad apps: 0 (special marker for scratchpad home)
  # Regular apps (non-PWA): 1-50
  # PWA apps (name ends with -pwa): 50+ (no upper bound)
  invalidWorkspaces = lib.filter (app:
    if app ? preferred_workspace then
      let
        isPWA = lib.hasSuffix "-pwa" app.name;
        isScratchpad = if app ? scratchpad then app.scratchpad else false;
        ws = app.preferred_workspace;
      in
        if isScratchpad then
          ws != 0  # Scratchpad apps must use workspace 0
        else if isPWA then
          ws < 50  # PWAs must be >= 50, no upper limit
        else
          ws < 1 || ws > 50  # Regular apps must be 1-50
    else
      false
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
      let
        invalidList = map (app:
          let
            isPWA = lib.hasSuffix "-pwa" app.name;
            isScratchpad = if app ? scratchpad then app.scratchpad else false;
            ws = if app ? preferred_workspace then app.preferred_workspace else 0;
            reason =
              if isScratchpad then "scratchpad app must be 0"
              else if isPWA then "PWA must be >=50"
              else "regular app must be 1-50";
          in
            "${app.name} (WS ${toString ws}, ${reason})"
        ) invalidWorkspaces;
      in
        throw "Invalid workspace numbers:\n  ${builtins.concatStringsSep "\n  " invalidList}"
    else if invalidNames != [] then
      throw "Invalid application names (must be kebab-case or reverse-domain): ${builtins.concatStringsSep ", " (map (app: app.name) invalidNames)}"
    else
      applications;

in
# Export just the validated applications list
validated
