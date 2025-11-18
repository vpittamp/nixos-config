# Sway Wayland Compositor Home Manager Configuration
# Parallel to i3.nix - adapted for Wayland on M1 MacBook Pro
# Works with Sway native Wayland session (no XRDP)
#
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                  CONFIGURATION MANAGEMENT ARCHITECTURE                       ║
# ║                    (Feature 047 - User Story 2)                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This module provides NIX-MANAGED (static) Sway configuration.
# For runtime-managed (hot-reloadable) settings, use the dynamic config system.
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ CONFIGURATION PRECEDENCE (from lowest to highest priority):                 │
# │                                                                              │
# │  1. Nix Config (this file)         → System defaults, stable settings       │
# │  2. Runtime Config                  → ~/.config/sway/*.{toml,json}          │
# │  3. Project Overrides               → ~/.config/sway/projects/<name>.json   │
# │                                                                              │
# │ Higher precedence levels override lower ones. Runtime changes take effect   │
# │ via `i3pm config reload` without NixOS rebuild.                             │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ DECISION TREE: Where should I put my configuration?                         │
# │                                                                              │
# │ ┌─ Is this setting system-wide and STABLE (rarely changes)?                 │
# │ │                                                                            │
# │ ├─ YES → Use this Nix file                                                  │
# │ │  Examples:                                                                │
# │ │    • Package installation (pkgs.sway, pkgs.terminal)                      │
# │ │    • Service configuration (systemd units, startup commands)              │
# │ │    • Display/output configuration (resolution, scaling)                   │
# │ │    • Base keybindings that never change (Mod+Return for terminal)         │
# │ │                                                                            │
# │ └─ NO → Does it CHANGE FREQUENTLY during development/testing?               │
# │    │                                                                         │
# │    ├─ YES → Use runtime config (hot-reloadable)                             │
# │    │  Location: ~/.config/sway/keybindings.toml or window-rules.json        │
# │    │  Command: i3pm config reload (no rebuild needed!)                      │
# │    │  Examples:                                                             │
# │    │    • Custom keybindings you're experimenting with                      │
# │    │    • Window rules for floating/sizing/positioning                      │
# │    │    • Workspace-to-output assignments (if you have multiple monitors)   │
# │    │                                                                         │
# │    └─ NO → Does it apply ONLY to specific projects?                         │
# │       │                                                                      │
# │       └─ YES → Use project overrides                                        │
# │          Location: ~/.config/sway/projects/<project-name>.json              │
# │          Command: pswitch <project> (auto-applies overrides)                │
# │          Examples:                                                          │
# │            • Project-specific keybindings (Mod+n → edit project file)       │
# │            • Project-aware window rules (calculator bigger in data-science) │
# │            • Workspace layouts for specific workflows                       │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ WHAT'S IN THIS FILE (Nix-managed):                                          │
# │                                                                              │
# │  ✓ Package installation (sway, terminal emulator, compositor packages)      │
# │  ✓ System services (daemon startup, systemd units)                          │
# │  ✓ Display configuration (resolution, scaling, output setup)                │
# │  ✓ Input devices (touchpad, keyboard base settings)                         │
# │  ✓ Base keybindings (stable shortcuts that never change)                    │
# │  ✓ Essential window rules (for system UI like walker, fzf)                  │
# │  ✓ Startup commands (service initialization)                                │
# │  ✓ Bar configuration (swaybar via separate module)                          │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ WHAT'S NOT IN THIS FILE (Runtime-managed via Feature 047):                  │
# │                                                                              │
# │  ✗ Custom user keybindings         → ~/.config/sway/keybindings.toml        │
# │  ✗ User window rules                → ~/.config/sway/window-rules.json      │
# │  ✗ Workspace assignments            → ~/.config/sway/workspace-assignments. │
# │  ✗ Project-specific overrides       → ~/.config/sway/projects/*.json        │
# │  ✗ Color schemes (user preference)  → Runtime config                        │
# │  ✗ Font size tweaks                 → Runtime config                        │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ HOW TO MODIFY SETTINGS:                                                      │
# │                                                                              │
# │ For Nix-managed settings (this file):                                       │
# │   1. Edit this file: nvim /etc/nixos/home-modules/desktop/sway.nix          │
# │   2. Test: sudo nixos-rebuild dry-build --flake .#m1                         │
# │   3. Apply: sudo nixos-rebuild switch --flake .#m1 --impure                  │
# │   4. Restart Sway (Mod+Shift+r) to apply changes                             │
# │                                                                              │
# │ For runtime-managed settings (Feature 047):                                 │
# │   1. Edit config: i3pm config edit keybindings  (or manual)                 │
# │   2. Validate: i3pm config validate                                          │
# │   3. Apply: i3pm config reload  (changes take effect immediately!)           │
# │   4. Rollback if needed: i3pm config rollback <commit-hash>                  │
# │                                                                              │
# │ See documentation: /etc/nixos/specs/047-create-a-new/quickstart.md          │
# └─────────────────────────────────────────────────────────────────────────────┘
#
{ config, lib, pkgs, osConfig ? null, ... }:

let
  # Detect headless Sway configuration (Feature 046)
  isHeadless = osConfig != null && (osConfig.networking.hostName or "") == "nixos-hetzner-sway";
  tailscaleAudioCfg = if osConfig != null then lib.attrByPath [ "services" "tailscaleAudio" ] { } osConfig else { };
  tailscaleAudioEnabled = tailscaleAudioCfg.enable or false;
  tailscaleSinkName = tailscaleAudioCfg.sinkName or "tailscale-rtp";
  mkWayvncWrapper = output: port: socket:
    pkgs.writeShellScript ("wayvnc-" + lib.strings.toLower output + "-wrapper") ''
      set -euo pipefail

      has_transient=0
      wayland_display="$(${pkgs.coreutils}/bin/printenv WAYLAND_DISPLAY 2>/dev/null || true)"
      if [ -n "$wayland_display" ]; then
        if ${pkgs.coreutils}/bin/timeout 2 \
             ${pkgs.wayland-utils}/bin/wayland-info --display "$wayland_display" 2>/dev/null \
             | ${pkgs.gnugrep}/bin/grep -q 'ext_transient_seat_v1'; then
          has_transient=1
        fi
      fi

      if [ "$has_transient" -eq 1 ]; then
        exec ${pkgs.wayvnc}/bin/wayvnc \
          -o ${output} \
          -S ${socket} \
          -R \
          -Ldebug \
          -r \
          --transient-seat \
          0.0.0.0 ${toString port}
      fi

      echo "wayvnc ${output}: ext_transient_seat_v1 not detected; continuing without dedicated seat" >&2
      exec ${pkgs.wayvnc}/bin/wayvnc \
        -o ${output} \
        -S ${socket} \
        -R \
        -Ldebug \
        -r \
        0.0.0.0 ${toString port}
    '';

  # Feature 001: Import validated application definitions with monitor role preferences
  appRegistryData = import ./app-registry-data.nix { inherit lib; };

  # Feature 001 US3: Import PWA site definitions with monitor role preferences
  pwaSitesData = import ../../shared/pwa-sites.nix { inherit lib; };

  # Feature 001: Generate workspace-to-monitor assignments from app registry
  # This creates the declarative workspace-assignments.json that the daemon reads
  # to determine which monitor role (primary/secondary/tertiary) each workspace should use
  workspaceAssignments = let
    clampWorkspace = ws:
      if ws < 1 then 1
      else if ws > 70 then 70
      else ws;

    # Map monitor roles → concrete outputs and include schema-required fields
    monitorRoleToOutput = role:
      if isHeadless then
        if role == "primary" then "HEADLESS-1"
        else if role == "secondary" then "HEADLESS-2"
        else if role == "tertiary" then "HEADLESS-3"
        else "HEADLESS-1"
      else
        # Laptop default mapping: keep everything on eDP-1; allow HDMI for secondary
        if role == "secondary" then "HDMI-A-1" else "eDP-1";

    # Fallback outputs (avoid including primary in the list)
    fallbackOutputs = primary:
      if isHeadless then
        builtins.filter (o: o != primary) [ "HEADLESS-1" "HEADLESS-2" "HEADLESS-3" ]
      else
        builtins.filter (o: o != primary) [ "eDP-1" "HDMI-A-1" ];
  in {
    version = "1.0";
    assignments =
      # App registry assignments
      (map (app: {
        workspace_number = clampWorkspace app.preferred_workspace;
        app_name = app.name;
        monitor_role = if app ? preferred_monitor_role && app.preferred_monitor_role != null
                       then app.preferred_monitor_role
                       else (
                         # Infer monitor role from workspace number (Feature 001 US1)
                         # WS 1-2: primary, WS 3-5: secondary, WS 6+: tertiary
                         if app.preferred_workspace <= 2 then "primary"
                         else if app.preferred_workspace <= 5 then "secondary"
                         else "tertiary"
                       );
        primary_output = monitorRoleToOutput (
          if app ? preferred_monitor_role && app.preferred_monitor_role != null
          then app.preferred_monitor_role
          else (
            if app.preferred_workspace <= 2 then "primary"
            else if app.preferred_workspace <= 5 then "secondary"
            else "tertiary"
          )
        );
        fallback_outputs = fallbackOutputs (
          monitorRoleToOutput (
            if app ? preferred_monitor_role && app.preferred_monitor_role != null
            then app.preferred_monitor_role
            else (
              if app.preferred_workspace <= 2 then "primary"
              else if app.preferred_workspace <= 5 then "secondary"
              else "tertiary"
            )
          )
        );
        auto_reassign = true;
        source = "nix";
      }) appRegistryData)
      ++
      # PWA site assignments (Feature 001 US3: PWA-specific monitor preferences)
      (map (pwa: {
        workspace_number = clampWorkspace pwa.preferred_workspace;
        app_name = "${pwa.name}-pwa";  # Append -pwa for identification
        monitor_role = if pwa ? preferred_monitor_role && pwa.preferred_monitor_role != null
                       then pwa.preferred_monitor_role
                       else (
                         # Infer monitor role from workspace number
                         if pwa.preferred_workspace <= 2 then "primary"
                         else if pwa.preferred_workspace <= 5 then "secondary"
                         else "tertiary"
                       );
        primary_output = monitorRoleToOutput (
          if pwa ? preferred_monitor_role && pwa.preferred_monitor_role != null
          then pwa.preferred_monitor_role
          else (
            if pwa.preferred_workspace <= 2 then "primary"
            else if pwa.preferred_workspace <= 5 then "secondary"
            else "tertiary"
          )
        );
        fallback_outputs = fallbackOutputs (
          monitorRoleToOutput (
            if pwa ? preferred_monitor_role && pwa.preferred_monitor_role != null
            then pwa.preferred_monitor_role
            else (
              if pwa.preferred_workspace <= 2 then "primary"
              else if pwa.preferred_workspace <= 5 then "secondary"
              else "tertiary"
            )
          )
        );
        auto_reassign = true;
        source = "nix";
      }) pwaSitesData.pwaSites);
  };
in
{
  # Import keybindings from separate module (moved from dynamic config to static Nix)
  imports = [
    ./sway-keybindings.nix
    ./unified-bar-theme.nix  # Feature 057: Centralized Catppuccin Mocha theme
    ./swaync.nix  # Feature 057: SwayNC notification center with unified theming
    ../tools/sway-tree-monitor.nix
  ];
  # Sway window manager configuration via home-manager
  wayland.windowManager.sway = {
    enable = true;
    package = pkgs.sway;

    # Sway uses identical config syntax to i3 (FR-023)
    config = {
      # Modifier key (Mod4 = Super/Command key on Mac)
      modifier = "Mod4";

      # Terminal (Meta+Return) - using app-launcher-wrapper for project context (Feature 046)
      terminal = "~/.local/bin/app-launcher-wrapper.sh terminal";

      # Application menu (Meta+D) - walker works with software rendering (GSK_RENDERER=cairo)
      menu = "walker";

      # Font with Font Awesome icons - reduced size for compact status bar
      fonts = {
        names = [ "monospace" "Font Awesome 6 Free" ];
        size = 8.0;
      };

      # Border settings - keep titlebars disabled; border width handled by sway-config-manager
      window = {
        titlebar = false;
      };

      floating = {
        titlebar = false;
      };

      # Output configuration (FR-005, FR-006)
      # Conditional configuration for headless vs physical displays
      output = if isHeadless then {
        # Headless Wayland - TRIPLE output for multi-monitor VNC workflow (Feature 048)
        # Three independent VNC instances stream each output to separate ports
        # Resolution: 1920x1200 to match TigerVNC's preferred aspect ratio (16:10)
        # This prevents letterboxing/whitespace when viewing via VNC
        # Layout: Horizontal arrangement (left to right) - RESTORED DEFAULT
        # Physical arrangement (left→right): HEADLESS-2, HEADLESS-1, HEADLESS-3
        # Matches the operator's monitor order (secondary ➜ primary ➜ tertiary)
        "HEADLESS-2" = {
          resolution = "1920x1200@60Hz";
          position = "0,0";
          scale = "1.0";
        };
        "HEADLESS-1" = {
          resolution = "1920x1200@60Hz";
          position = "1920,0";  # Center display
          scale = "1.0";
        };
        "HEADLESS-3" = {
          resolution = "1920x1200@60Hz";
          position = "3840,0";  # Right-most display
          scale = "1.0";
        };
      } else {
        # M1 MacBook Pro physical displays
        "eDP-1" = {
          scale = "2.0";                    # 2x scaling for Retina
          resolution = "2560x1600@60Hz";    # Native resolution
          position = "0,0";
        };

        # External monitor (auto-detect, 1:1 scaling)
        "HDMI-A-1" = {
          scale = "1.0";
          mode = "1920x1080@60Hz";
          position = "1280,0";  # Right of built-in (1280 = 2560/2)
        };
      };

      # Input configuration (FR-006)
      input =
        {
        # Touchpad configuration for M1 MacBook Pro
        "type:touchpad" = {
          natural_scroll = "enabled";   # Natural scrolling
          scroll_method = "two_finger";  # Enable two-finger scrolling
          tap = "enabled";               # Tap-to-click
          tap_button_map = "lrm";        # Two-finger right-click
          dwt = "enabled";               # Disable while typing
          middle_emulation = "enabled";  # Three-finger middle-click
        };

        # Keyboard configuration
        "type:keyboard" = {
          xkb_layout = "us";
          # Disable CapsLock toggle behavior - makes it act like a regular key
          # This prevents the sticky LED when using CapsLock for workspace mode
          xkb_options = "caps:none";
          repeat_delay = "300";
          repeat_rate = "50";
        };
      }
      // lib.optionalAttrs isHeadless {
        # Slow down virtual pointer events injected via WayVNC for finer control
        "type:pointer" = {
          accel_profile = "adaptive";
          pointer_accel = "-0.4";
        };
      };

      # Feature 001: Declarative workspace-to-monitor assignments
      # Generate workspace assignments from app registry and PWA data
      # Replaces Feature 049's hardcoded assignments (workspaces 1-9 only)
      # with complete declarative system for all workspaces (1-70)
      workspaceOutputAssign = if isHeadless then
        let
          # Map monitor roles to physical outputs
          roleToOutput = role:
            if role == "primary" then "HEADLESS-1"
            else if role == "secondary" then "HEADLESS-2"
            else if role == "tertiary" then "HEADLESS-3"
            else "HEADLESS-1";  # Fallback to primary

          # Generate workspace assignment from app/PWA data
          assignmentToOutput = assignment: {
            workspace = toString assignment.workspace_number;
            output = roleToOutput assignment.monitor_role;
          };
        in
          # Convert all workspace assignments to Sway output assignments
          map assignmentToOutput workspaceAssignments.assignments
      else [
        # M1 MacBook Pro: Single display (eDP-1) for all workspaces
        # All workspace assignments use primary role → eDP-1
        { workspace = "1"; output = "eDP-1"; }
        { workspace = "2"; output = "eDP-1"; }
        { workspace = "3"; output = "eDP-1"; }
      ];

      # ═══════════════════════════════════════════════════════════════════════════
      # KEYBINDINGS (Static Nix Configuration)
      # ═══════════════════════════════════════════════════════════════════════════
      #
      # Keybindings are now defined in sway-keybindings.nix and managed statically.
      # This simplifies the configuration stack by removing the dynamic keybinding
      # layer while keeping window rules and projects fully dynamic.
      #
      # To edit keybindings:
      #   • Edit: /etc/nixos/home-modules/desktop/sway-keybindings.nix
      #   • Test: home-manager build
      #   • Apply: home-manager switch (or nixos-rebuild switch for system changes)
      #
      # Keybindings are imported via the imports section at the top of this file.
      # ═══════════════════════════════════════════════════════════════════════════
      # (Keybindings defined in sway-keybindings.nix)

      # ORIGINAL home-manager keybindings (commented out for Feature 047):
      # All keybindings below have been moved to ~/.local/share/sway-config-manager/templates/keybindings.toml
      # and are now managed dynamically. To restore static keybindings, remove lib.mkForce above.
      #
      # keybindings = let
      #   mod = config.wayland.windowManager.sway.config.modifier;
      # in lib.mkOptionDefault {
      #   # Terminal (uses config.terminal which calls app-launcher-wrapper)
      #   "${mod}+Return" = "exec $terminal";

      #   # Application launcher (rofi for headless, walker for M1)
      #   "${mod}+d" = "exec $menu";
      #   "Mod1+space" = "exec $menu";  # Alternative: Alt+Space

      #         # Window management
      #         "${mod}+Shift+q" = "kill";
      #         "${mod}+Escape" = "kill";  # Alternative kill binding
      # 
      #         # Focus movement (arrow keys)
      #         "${mod}+Left" = "focus left";
      #         "${mod}+Down" = "focus down";
      #         "${mod}+Up" = "focus up";
      #         "${mod}+Right" = "focus right";
      # 
      #         # Move focused window (arrow keys)
      #         "${mod}+Shift+Left" = "move left";
      #         "${mod}+Shift+Down" = "move down";
      #         "${mod}+Shift+Up" = "move up";
      #         "${mod}+Shift+Right" = "move right";
      # 
      #         # Split orientation
      #         "${mod}+h" = "split h";
      #         "${mod}+Shift+bar" = "split v";
      # 
      #         # Fullscreen
      #         "${mod}+f" = "fullscreen toggle";
      # 
      #         # Container layout
      #         "${mod}+s" = "layout stacking";
      #         "${mod}+w" = "layout tabbed";
      #         "${mod}+e" = "layout toggle split";
      # 
      #         # Toggle floating
      #         "${mod}+Shift+space" = "floating toggle";
      #         "${mod}+space" = "focus mode_toggle";
      # 
      #         # Scratchpad
      #         "${mod}+Shift+minus" = "move scratchpad";
      #         "${mod}+minus" = "scratchpad show";
      # 
      #         # Workspace switching (Ctrl+1-9) - parallel to Hetzner
      #         "Control+1" = "workspace number 1";
      #         "Control+2" = "workspace number 2";
      #         "Control+3" = "workspace number 3";
      #         "Control+4" = "workspace number 4";
      #         "Control+5" = "workspace number 5";
      #         "Control+6" = "workspace number 6";
      #         "Control+7" = "workspace number 7";
      #         "Control+8" = "workspace number 8";
      #         "Control+9" = "workspace number 9";
      # 
      #         # Move container to workspace
      #         "${mod}+Shift+1" = "move container to workspace number 1";
      #         "${mod}+Shift+2" = "move container to workspace number 2";
      #         "${mod}+Shift+3" = "move container to workspace number 3";
      #         "${mod}+Shift+4" = "move container to workspace number 4";
      #         "${mod}+Shift+5" = "move container to workspace number 5";
      #         "${mod}+Shift+6" = "move container to workspace number 6";
      #         "${mod}+Shift+7" = "move container to workspace number 7";
      #         "${mod}+Shift+8" = "move container to workspace number 8";
      #         "${mod}+Shift+9" = "move container to workspace number 9";
      # 
      #         # Project management keybindings (parallel to i3 config)
      #         "${mod}+p" = "exec ${pkgs.xterm}/bin/xterm -name fzf-launcher -geometry 80x24 -e /etc/nixos/scripts/fzf-project-switcher.sh";
      #         "${mod}+Shift+p" = "exec i3pm project clear";
      # 
      #         # Project-aware application launchers (Feature 035: Registry-based)
      #         "${mod}+c" = "exec ~/.local/bin/app-launcher-wrapper.sh vscode";
      #         "${mod}+g" = "exec ~/.local/bin/app-launcher-wrapper.sh lazygit";
      #         "${mod}+y" = "exec ~/.local/bin/app-launcher-wrapper.sh yazi";
      #         "${mod}+b" = "exec ~/.local/bin/app-launcher-wrapper.sh btop";
      #         "${mod}+k" = "exec ~/.local/bin/app-launcher-wrapper.sh k9s";
      #         "${mod}+Shift+Return" = "exec ~/.local/bin/app-launcher-wrapper.sh terminal";
      # 
      #         # Monitor detection/workspace reassignment
      #         "${mod}+Shift+m" = "exec ~/.config/i3/scripts/reassign-workspaces.sh";
      # 
      #         # Reload/restart
      #         "${mod}+Shift+c" = "reload";
      #         "${mod}+Shift+r" = "restart";
      #         "${mod}+Shift+e" = "exec swaymsg exit";
      # 
      #         # Screenshots (grim + slurp for Wayland)
      #         "Print" = "exec grim -o $(swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name') - | wl-copy";
      #         "${mod}+Print" = "exec grim -g \"$(swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '.. | select(.focused?) | .rect | \"\\(.x),\\(.y) \\(.width)x\\(.height)\"')\" - | wl-copy";
      #         "${mod}+Shift+x" = "exec grim -g \"$(slurp)\" - | wl-copy";
      #       };

      # ═══════════════════════════════════════════════════════════════════════════
      # WINDOW RULES (Nix-Managed - Essential System UI Only)
      # ═══════════════════════════════════════════════════════════════════════════
      #
      # NOTE: Only SYSTEM UI window rules belong here (launcher, system dialogs).
      # These are essential for the window manager to function correctly.
      #
      # For USER-DEFINED window rules (floating, sizing, positioning), use runtime config:
      #   • Edit: ~/.config/sway/window-rules.json
      #   • Reload: i3pm config reload
      #   • Examples: Calculator floating, Firefox on workspace 3, etc.
      #
      # ═══════════════════════════════════════════════════════════════════════════
      window.commands = [
        # Walker launcher - floating, centered, no border
        {
          criteria = { app_id = "walker"; };
          command = "floating enable, border pixel 0, move position center, mark _global_ui";
        }

        # Floating terminal
        {
          criteria = { app_id = "floating_terminal"; };
          command = "floating enable";
        }

        # FZF launcher - floating, centered, no border
        {
          criteria = { instance = "fzf-launcher"; };
          command = "floating enable, border pixel 0, move position center, mark _global_ui";
        }

        # FZF file search - floating with preview
        # Note: Ghostty app_id is always com.mitchellh.ghostty, so we match by title
        # Large size for comfortable preview pane
        {
          criteria = { app_id = "com.mitchellh.ghostty"; title = "^FZF File Search$"; };
          command = "floating enable, border pixel 2, mark _file_search, resize set width 1800 px height 1000 px, move position center";
        }

        # Blueman Bluetooth Manager - floating window
        {
          criteria = { app_id = ".blueman-manager-wrapped"; };
          command = "floating enable";
        }

        # PulseAudio Volume Control - floating window
        {
          criteria = { app_id = "pavucontrol"; };
          command = "floating enable";
        }

        # Network Manager Connection Editor - floating window
        {
          criteria = { app_id = "nm-connection-editor"; };
          command = "floating enable";
        }

        # GNOME Calendar - floating window
        {
          criteria = { app_id = "org.gnome.Calendar"; };
          command = "floating enable";
        }
      ];

      # Startup commands (FR-015)
      startup = [
        # D-Bus activation environment
        { command = "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd --all"; }

        # Import Wayland/Sway environment for systemd services and shells
        # SWAYSOCK is needed for swaymsg commands in terminals
        { command = "systemctl --user import-environment WAYLAND_DISPLAY DISPLAY SWAYSOCK"; }

        # i3pm daemon (socket-activated system service)
        # Socket activation happens automatically on first IPC request
        # The 2-second delay in reassign-workspaces allows daemon to fully initialize
        # before any IPC connections, avoiding deadlock during startup

        # Monitor workspace distribution (wait for daemon to initialize)
        { command = "sleep 2 && ~/.config/i3/scripts/reassign-workspaces.sh"; }

        # sov workspace overview daemon
        { command = "systemctl --user start sov"; }
      ];

      # Bar configuration will be provided by swaybar.nix
      bars = [];
    };

    # Extra Sway config for features not exposed by home-manager
    extraConfig = ''
      ${lib.optionalString (!isHeadless) ''
        # Disable laptop lid close action (keep running when closed)
        # Only for M1 MacBook Pro, not headless mode
        bindswitch lid:on output eDP-1 disable
        bindswitch lid:off output eDP-1 enable
      ''}

      # Application menu launcher - walker works with software rendering (GSK_RENDERER=cairo)
      set $menu walker

      # Define modifier key for dynamic keybindings (Feature 047)
      set $mod Mod4

      # Focus settings - auto-focus newly launched windows
      # Feature: Auto-focus apps launched via Walker across all displays
      # Benefit: Provides immediate feedback when launching apps from Walker
      # Behavior: Workspace automatically switches to show newly launched app
      focus_on_window_activation focus

      # Mouse focus behavior - focus on click, not hover
      # no = focus only changes on mouse click (prevents hover-based focus stealing)
      # yes = focus changes when mouse hovers over window (default Sway behavior)
      # always = focus follows mouse even for unfocused outputs
      focus_follows_mouse no

      # Mouse warping - move cursor when switching focus via keyboard
      # none = cursor stays where it is (natural keyboard navigation)
      # output = cursor moves to center of output when switching focus (BEST for multi-monitor)
      # container = cursor moves to center of container when switching focus
      mouse_warping output

      # Workspace names - numbers only for clean display
      set $ws1 "1"
      set $ws2 "2"
      set $ws3 "3"
      set $ws4 "4"
      set $ws5 "5"
      set $ws6 "6"
      set $ws7 "7"
      set $ws8 "8"
      set $ws9 "9"

      # PWA Workspace Assignments - REMOVED (Feature 053)
      #
      # ═══════════════════════════════════════════════════════════════════════════
      # FEATURE 053: Event-Driven Workspace Assignment Enhancement
      # ═══════════════════════════════════════════════════════════════════════════
      #
      # ROOT CAUSE FIX: Native Sway `assign` rules suppress window creation events,
      # preventing the i3-project-event-daemon from receiving window::new IPC events.
      # This caused PWAs to appear without triggering event handlers for project
      # assignment and window tracking.
      #
      # SOLUTION: Remove ALL native assignment rules and consolidate to single
      # event-driven mechanism in i3-project-event-daemon. Workspace assignments
      # are now managed via:
      #   - Priority 0: Launch notification (matched_launch.workspace_number)
      #   - Priority 1: App-specific handlers (VS Code title parsing)
      #   - Priority 2: I3PM_TARGET_WORKSPACE environment variable
      #   - Priority 3: I3PM_APP_NAME registry lookup
      #   - Priority 4: Window class matching (exact → instance → normalized)
      #
      # All PWA workspace assignments remain in app-registry-data.nix with
      # preferred_workspace field. The daemon reads this and assigns windows
      # via IPC commands instead of Sway's internal assignment logic.
      #
      # Benefits:
      #   • 100% event delivery (no suppressed window::new events)
      #   • Unified assignment mechanism (no conflicts or race conditions)
      #   • Dynamic project-aware workspace assignment
      #   • <100ms assignment latency with launch notification Priority 0
      #
      # Removed rules (now handled by daemon):
      #   • YouTube PWA (FFPWA-01K666N2V6BQMDSBMX3AY74TY7) → workspace 4
      #   • Google AI PWA (FFPWA-01K665SPD8EPMP3JTW02JM1M0Z) → workspace 10
      #   • ChatGPT PWA (FFPWA-01K772ZBM45JD68HXYNM193CVW) → workspace 11
      #   • GitHub Codespaces PWA (FFPWA-01K772Z7AY5J36Q3NXHH9RYGC0) → workspace 2
      #
      # See: /etc/nixos/specs/053-workspace-assignment-enhancement/
      # ═══════════════════════════════════════════════════════════════════════════

      # Feature 047: Include dynamically generated appearance from sway-config-manager
      # Note: Keybindings are now static (defined in sway-keybindings.nix)
      include ~/.config/sway/appearance-generated.conf

      # Feature 062: Project-Scoped Scratchpad Terminal
      # Essential window rule for floating, centered scratchpad terminal
      # Matches by app_id (com.mitchellh.ghostty) AND title "Scratchpad Terminal"
      # Regular Ghostty terminals have different titles (e.g., "Ghostty") and won't match
      # Size: 1100x550 pixels (optimized for 9pt font), centered on display
      # Note: Daemon handles marking with scratchpad:{project} and moving to scratchpad
      for_window [app_id="com.mitchellh.ghostty" title="^Scratchpad Terminal$"] floating enable, resize set width 1100 px height 550 px, move position center

      # Workspace modes (Feature 042: Event-Driven Workspace Mode Navigation)
      # Embedded directly instead of include due to Sway not loading included modes
      # Visual feedback: workspace-mode-visual helper shows typed keys (wshowkeys overlay on physical, notifications on headless)
      mode "→ WS" {
          # Digits for workspace navigation
          bindsym 0 exec i3pm-workspace-mode digit 0
          bindsym 1 exec i3pm-workspace-mode digit 1
          bindsym 2 exec i3pm-workspace-mode digit 2
          bindsym 3 exec i3pm-workspace-mode digit 3
          bindsym 4 exec i3pm-workspace-mode digit 4
          bindsym 5 exec i3pm-workspace-mode digit 5
          bindsym 6 exec i3pm-workspace-mode digit 6
          bindsym 7 exec i3pm-workspace-mode digit 7
          bindsym 8 exec i3pm-workspace-mode digit 8
          bindsym 9 exec i3pm-workspace-mode digit 9

          # Letters for project switching
          bindsym a exec i3pm-workspace-mode char a
          bindsym b exec i3pm-workspace-mode char b
          bindsym c exec i3pm-workspace-mode char c
          bindsym d exec i3pm-workspace-mode char d
          bindsym e exec i3pm-workspace-mode char e
          # bindsym f removed - conflicts with Feature 073 float toggle action
          bindsym g exec i3pm-workspace-mode char g
          bindsym h exec i3pm-workspace-mode char h
          bindsym i exec i3pm-workspace-mode char i
          bindsym j exec i3pm-workspace-mode char j
          bindsym k exec i3pm-workspace-mode char k
          bindsym l exec i3pm-workspace-mode char l
          # bindsym m removed - conflicts with Feature 073 move window action
          bindsym n exec i3pm-workspace-mode char n
          bindsym o exec i3pm-workspace-mode char o
          bindsym p exec i3pm-workspace-mode char p
          bindsym q exec i3pm-workspace-mode char q
          bindsym r exec i3pm-workspace-mode char r
          bindsym s exec i3pm-workspace-mode char s
          bindsym t exec i3pm-workspace-mode char t
          bindsym u exec i3pm-workspace-mode char u
          bindsym v exec i3pm-workspace-mode char v
          bindsym w exec i3pm-workspace-mode char w
          bindsym x exec i3pm-workspace-mode char x
          bindsym y exec i3pm-workspace-mode char y
          bindsym z exec i3pm-workspace-mode char z

          # Feature 072: Colon to switch to project mode
          bindsym colon exec i3pm-workspace-mode char :

          # Feature 059: Arrow key navigation for interactive workspace menu
          bindsym Down exec i3pm-workspace-mode nav down
          bindsym Up exec i3pm-workspace-mode nav up
          bindsym Home exec i3pm-workspace-mode nav home
          bindsym End exec i3pm-workspace-mode nav end
          bindsym Delete exec i3pm-workspace-mode delete
          bindsym BackSpace exec i3pm-workspace-mode backspace

          # Feature 073: Per-window actions for interactive menu (T048, T049)
          bindsym m exec i3pm-workspace-mode action m
          bindsym Shift+m exec i3pm-workspace-mode action shift-m
          bindsym f exec i3pm-workspace-mode action f

          # Execute/cancel (Feature 058: Visual feedback now via workspace bar)
          bindsym Return exec "i3pm-workspace-mode execute"
          bindsym KP_Enter exec "i3pm-workspace-mode execute"
          bindsym Escape exec "i3pm-workspace-mode cancel"
      }

      mode "⇒ WS" {
          # Digits for workspace navigation
          bindsym 0 exec i3pm-workspace-mode digit 0
          bindsym 1 exec i3pm-workspace-mode digit 1
          bindsym 2 exec i3pm-workspace-mode digit 2
          bindsym 3 exec i3pm-workspace-mode digit 3
          bindsym 4 exec i3pm-workspace-mode digit 4
          bindsym 5 exec i3pm-workspace-mode digit 5
          bindsym 6 exec i3pm-workspace-mode digit 6
          bindsym 7 exec i3pm-workspace-mode digit 7
          bindsym 8 exec i3pm-workspace-mode digit 8
          bindsym 9 exec i3pm-workspace-mode digit 9

          # Letters for project switching
          bindsym a exec i3pm-workspace-mode char a
          bindsym b exec i3pm-workspace-mode char b
          bindsym c exec i3pm-workspace-mode char c
          bindsym d exec i3pm-workspace-mode char d
          bindsym e exec i3pm-workspace-mode char e
          # bindsym f removed - conflicts with Feature 073 float toggle action
          bindsym g exec i3pm-workspace-mode char g
          bindsym h exec i3pm-workspace-mode char h
          bindsym i exec i3pm-workspace-mode char i
          bindsym j exec i3pm-workspace-mode char j
          bindsym k exec i3pm-workspace-mode char k
          bindsym l exec i3pm-workspace-mode char l
          # bindsym m removed - conflicts with Feature 073 move window action
          bindsym n exec i3pm-workspace-mode char n
          bindsym o exec i3pm-workspace-mode char o
          bindsym p exec i3pm-workspace-mode char p
          bindsym q exec i3pm-workspace-mode char q
          bindsym r exec i3pm-workspace-mode char r
          bindsym s exec i3pm-workspace-mode char s
          bindsym t exec i3pm-workspace-mode char t
          bindsym u exec i3pm-workspace-mode char u
          bindsym v exec i3pm-workspace-mode char v
          bindsym w exec i3pm-workspace-mode char w
          bindsym x exec i3pm-workspace-mode char x
          bindsym y exec i3pm-workspace-mode char y
          bindsym z exec i3pm-workspace-mode char z

          # Feature 072: Colon to switch to project mode
          bindsym colon exec i3pm-workspace-mode char :

          # Feature 059: Arrow key navigation for interactive workspace menu
          bindsym Down exec i3pm-workspace-mode nav down
          bindsym Up exec i3pm-workspace-mode nav up
          bindsym Home exec i3pm-workspace-mode nav home
          bindsym End exec i3pm-workspace-mode nav end
          bindsym Delete exec i3pm-workspace-mode delete
          bindsym BackSpace exec i3pm-workspace-mode backspace

          # Feature 073: Per-window actions for interactive menu (T048, T049)
          bindsym m exec i3pm-workspace-mode action m
          bindsym Shift+m exec i3pm-workspace-mode action shift-m
          bindsym f exec i3pm-workspace-mode action f

          # Execute/cancel (Feature 058: Visual feedback now via workspace bar)
          bindsym Return exec "i3pm-workspace-mode execute"
          bindsym KP_Enter exec "i3pm-workspace-mode execute"
          bindsym Escape exec "i3pm-workspace-mode cancel"
      }

      # Platform-conditional workspace mode keybindings
      # NOTE: Control+0/Shift+0 moved to sway-keybindings.nix (works on all platforms)
      # M1-specific CapsLock binding remains here (requires bindcode, not available in keybindings attr)
      ${if isHeadless then ''
        # Hetzner: Control+0 keybindings now in sway-keybindings.nix
      '' else ''
        # M1 (Physical): Use CapsLock for ergonomic single-key workspace mode access
        # Using bindcode 66 (CapsLock physical keycode) because xkb_options caps:none makes it emit VoidSymbol
        # This approach is more reliable than binding to VoidSymbol
        # Feature 072: Call enter command to trigger all-windows preview
        bindcode --release 66 exec i3pm-workspace-mode enter, mode "→ WS"
        bindcode --release Shift+66 mode "⇒ WS"
      ''}
    '';
  };

  # Install Wayland-specific utilities
  home.packages = with pkgs; [
    wl-clipboard     # Clipboard utilities (wl-copy, wl-paste)
    grim             # Screenshot tool
    slurp            # Screen area selection
    swaynotificationcenter  # Notification daemon with action button support
    swaylock         # Screen locker
    swayidle         # Idle management
    sov              # Workspace overview
    wshowkeys        # Visual key overlay for workspace mode
    # sway-easyfocus now managed by home-manager module (desktop/sway-easyfocus.nix)
  ] ++ lib.optionals isHeadless [
    # wayvnc for headless mode (Feature 046)
    pkgs.wayvnc
    pkgs.wireplumber  # Provides wpctl for default sink adjustments
  ];

  # Runtime helper to pick which virtual outputs are active and sync wayvnc units
  home.file.".local/bin/active-monitors" = {
    source = ./scripts/active-monitors.sh;
    executable = true;
  };


  # wayvnc configuration for headless Sway (Feature 048)
  # Shared configuration for all three WayVNC instances
  # Port specification removed - handled by individual systemd services
  xdg.configFile."wayvnc/config" = lib.mkIf isHeadless {
    text = ''
      address=0.0.0.0
      enable_auth=false
    '';
  };

  # Feature 001: Workspace-to-monitor assignments (declarative configuration)
  # This file is read by workspace_assignment_manager.py on daemon startup
  # to determine which monitor role each workspace should use based on app preferences
  # Format: workspace-assignments.schema.json (v1.0)
  xdg.configFile."sway/workspace-assignments.json".text = builtins.toJSON workspaceAssignments;

  # wayvnc systemd services for headless mode (Feature 048)
  # Three independent VNC instances for three virtual displays

  # HEADLESS-1 (Primary display, workspaces 1-2, port 5900)
  systemd.user.services."wayvnc@HEADLESS-1" = lib.mkIf isHeadless {
    Unit = {
      Description = "wayvnc VNC server for HEADLESS-1";
      Documentation = "https://github.com/any1/wayvnc";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = mkWayvncWrapper "HEADLESS-1" 5900 "/run/user/1000/wayvnc-headless-1.sock";
      Restart = "on-failure";
      RestartSec = "1";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # HEADLESS-2 (Secondary display, workspaces 3-5, port 5901)
  systemd.user.services."wayvnc@HEADLESS-2" = lib.mkIf isHeadless {
    Unit = {
      Description = "wayvnc VNC server for HEADLESS-2";
      Documentation = "https://github.com/any1/wayvnc";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = mkWayvncWrapper "HEADLESS-2" 5901 "/run/user/1000/wayvnc-headless-2.sock";
      Restart = "on-failure";
      RestartSec = "1";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # HEADLESS-3 (Tertiary display, workspaces 6-9, port 5902)
  systemd.user.services."wayvnc@HEADLESS-3" = lib.mkIf isHeadless {
    Unit = {
      Description = "wayvnc VNC server for HEADLESS-3";
      Documentation = "https://github.com/any1/wayvnc";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = mkWayvncWrapper "HEADLESS-3" 5902 "/run/user/1000/wayvnc-headless-3.sock";
      Restart = "on-failure";
      RestartSec = "1";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  systemd.user.services."tailscale-rtp-default-sink" = lib.mkIf (isHeadless && tailscaleAudioEnabled) {
    Unit = {
      Description = "Set PipeWire default sink to Tailscale RTP";
      After = [ "pipewire.service" "wireplumber.service" "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "set-tailscale-rtp-default" ''
        set -euo pipefail

        attempts=0
        until ${pkgs.wireplumber}/bin/wpctl status >/dev/null 2>&1; do
          if [ "$attempts" -ge 40 ]; then
            echo "wpctl not ready, skipping default sink assignment" >&2
            exit 0
          fi
          attempts=$((attempts + 1))
          sleep 0.5
        done

        ${pkgs.wireplumber}/bin/wpctl set-default "${tailscaleSinkName}"
      ''}";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # Sway session target (synchronization point for Sway-dependent services)
  # Contract: /etc/nixos/specs/046-revise-my-spec/contracts/systemd-dependencies.md lines 132-149
  # This target represents that Sway compositor is fully initialized with IPC socket available
  systemd.user.targets.sway-session = {
    Unit = {
      Description = "sway compositor session";
      Documentation = "man:systemd.special(7)";
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };
  };

  # SwayNC (Sway Notification Center) systemd service
  # Notification daemon for Sway (replaces Dunst which is used for i3)
  systemd.user.services.swaync = {
    Unit = {
      Description = "Sway Notification Center";
      Documentation = "https://github.com/ErikReider/SwayNotificationCenter";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      Type = "dbus";
      BusName = "org.freedesktop.Notifications";
      ExecStart = "${pkgs.swaynotificationcenter}/bin/swaync";
      ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # sov workspace overview service
  systemd.user.services.sov = {
    Unit = {
      Description = "Sway Overview - Workspace Overview";
      Documentation = "https://github.com/milgra/sov";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.writeShellScript "sov-setup-pipe" ''
        rm -f /tmp/sovpipe
        mkfifo /tmp/sovpipe
      ''}";
      ExecStart = "${pkgs.writeShellScript "sov-daemon" ''
        # sov options:
        # -c 3: 3 columns for multi-monitor layout
        # -a lc: anchor to left-center
        # -m 20: 20px margin from screen edges
        # -r 0.15: 15% of screen size for thumbnails
        # -t 200: 200ms delay before overlay appears
        tail -f /tmp/sovpipe | ${pkgs.sov}/bin/sov -c 3 -a lc -m 20 -r 0.15 -t 200
      ''}";
      Restart = "on-failure";
      RestartSec = "1";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}
