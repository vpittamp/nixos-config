{ config, lib, pkgs, ... }:

{
  # Project-specific workspace configuration
  # This module sets up desktop environments tailored to specific projects

  # Environment variables for quick project navigation
  home.sessionVariables = {
    # Project directories
    NIXOS_DIR = "/etc/nixos";
    STACKS_DIR = "$HOME/stacks";

    # Quick navigation aliases
    PROJECT_1 = "/etc/nixos";
    PROJECT_2 = "$HOME/stacks";
  };

  # Shell aliases for project navigation
  programs.bash.shellAliases = {
    # Project navigation
    cdnixos = "cd /etc/nixos";
    cdstacks = "cd ~/stacks";

    # Project-specific git operations
    nixos-status = "cd /etc/nixos && git status";
    nixos-diff = "cd /etc/nixos && git diff";
    nixos-log = "cd /etc/nixos && git log --oneline -10";

    stacks-status = "cd ~/stacks && git status";
    stacks-diff = "cd ~/stacks && git diff";
    stacks-log = "cd ~/stacks && git log --oneline -10";

    # Quick desktop switching
    desktop-nixos = "qdbus org.kde.KWin /KWin setCurrentDesktop 1";
    desktop-stacks = "qdbus org.kde.KWin /KWin setCurrentDesktop 2";
    desktop-research = "qdbus org.kde.KWin /KWin setCurrentDesktop 3";
    desktop-system = "qdbus org.kde.KWin /KWin setCurrentDesktop 4";

    # Open project in editor
    edit-nixos = "cd /etc/nixos && nvim";
    edit-stacks = "cd ~/stacks && nvim";

    # Rebuild NixOS from its directory
    nixos-rebuild = "cd /etc/nixos && sudo nixos-rebuild";
    nixos-test = "cd /etc/nixos && sudo nixos-rebuild dry-build --flake .#$(hostname)";
    nixos-switch = "cd /etc/nixos && sudo nixos-rebuild switch --flake .#$(hostname)";
  };

  # Konsole profiles for different projects
  programs.plasma.configFile."konsolerc"."Desktop Entry" = {
    DefaultProfile = lib.mkForce "NixOS.profile";  # Override default Shell.profile
  };

  # NixOS project profile
  home.file.".local/share/konsole/NixOS.profile".text = ''
    [Appearance]
    ColorScheme=BreezeDark
    Font=FiraCode Nerd Font Mono,11,-1,5,50,0,0,0,0,0

    [General]
    Command=/run/current-system/sw/bin/bash -c "cd /etc/nixos && exec bash"
    Directory=/etc/nixos
    Environment=TERM=xterm-256color,COLORTERM=truecolor,PROJECT=nixos
    Icon=nix-snowflake
    LocalTabTitleFormat=%d : %n
    Name=NixOS
    Parent=FALLBACK/
    ShowTerminalSizeHint=true
    StartInCurrentSessionDir=false

    [Scrolling]
    HistoryMode=2
    ScrollBarPosition=2

    [Terminal Features]
    BlinkingCursorEnabled=true
    UrlHintsModifiers=67108864
  '';

  # Stacks project profile
  home.file.".local/share/konsole/Stacks.profile".text = ''
    [Appearance]
    ColorScheme=BreezeDark
    Font=FiraCode Nerd Font Mono,11,-1,5,50,0,0,0,0,0

    [General]
    Command=/run/current-system/sw/bin/bash -c "cd ~/stacks && exec bash"
    Directory=~/stacks
    Environment=TERM=xterm-256color,COLORTERM=truecolor,PROJECT=stacks
    Icon=folder-development
    LocalTabTitleFormat=%d : %n
    Name=Stacks
    Parent=FALLBACK/
    ShowTerminalSizeHint=true
    StartInCurrentSessionDir=false

    [Scrolling]
    HistoryMode=2
    ScrollBarPosition=2

    [Terminal Features]
    BlinkingCursorEnabled=true
    UrlHintsModifiers=67108864
  '';

  # Dolphin (file manager) places for quick access
  home.file.".local/share/user-places.xbel".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE xbel>
    <xbel xmlns:kdepriv="http://www.kde.org/kdepriv" xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks">
     <info>
      <metadata owner="http://freedesktop.org">
       <bookmark:applications>
        <bookmark:application name="dolphin" exec="dolphin %u" modified="2025-01-01T00:00:00Z" count="1"/>
       </bookmark:applications>
      </metadata>
     </info>
     <bookmark href="file:///etc/nixos">
      <title>NixOS Config</title>
      <info>
       <metadata owner="http://freedesktop.org">
        <bookmark:icon name="nix-snowflake"/>
       </metadata>
      </info>
     </bookmark>
     <bookmark href="file://$HOME/stacks">
      <title>Stacks Project</title>
      <info>
       <metadata owner="http://freedesktop.org">
        <bookmark:icon name="folder-development"/>
       </metadata>
      </info>
     </bookmark>
    </xbel>
  '';

  # KRunner custom web shortcuts for documentation
  programs.plasma.configFile."kuriikwsfilterrc"."General" = {
    DefaultWebShortcut = "google";
    EnableWebShortcuts = true;
    KeywordDelimiter = 58;  # colon
    PreferredWebShortcuts = "nixos,nix,github";
    UsePreferredWebShortcutsOnly = false;
  };

  # Custom web shortcuts for NixOS and development
  programs.plasma.configFile."kuriikwsfilterrc"."nixos" = {
    Query = "https://search.nixos.org/packages?query=\\{@}";
    Name = "NixOS Package Search";
    Charset = "utf-8";
  };

  programs.plasma.configFile."kuriikwsfilterrc"."nixopt" = {
    Query = "https://search.nixos.org/options?query=\\{@}";
    Name = "NixOS Options Search";
    Charset = "utf-8";
  };

  programs.plasma.configFile."kuriikwsfilterrc"."nixpkgs" = {
    Query = "https://github.com/NixOS/nixpkgs/search?q=\\{@}";
    Name = "Nixpkgs GitHub Search";
    Charset = "utf-8";
  };

  # Yakuake configuration for project switching
  programs.plasma.configFile."yakuakerc"."Dialogs" = {
    FirstRun = false;
  };

  programs.plasma.configFile."yakuakerc"."Window" = {
    Height = 50;
    Width = 100;
    KeepOpen = true;
  };

  programs.plasma.configFile."yakuakerc"."Appearance" = {
    BackgroundColorOpacity = 85;
    Blur = true;
    Skin = "breeze-dark";
  };

  # Desktop-specific wallpapers (if you want different backgrounds per desktop)
  # Note: This would require the wallpaper files to exist
  programs.plasma.configFile."plasma-org.kde.plasma.desktop-appletsrc"."Wallpaper" = {
    # Desktop 1 - NixOS
    "Desktop1" = "/usr/share/wallpapers/NixOS/contents/images/3840x2160.png";
    # Desktop 2 - Stacks
    "Desktop2" = "/usr/share/wallpapers/Next/contents/images/3840x2160.png";
  };

  # Quick launch scripts for project-specific tasks
  home.file.".local/bin/open-nixos-workspace" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Switch to NixOS desktop and open development tools

      # Switch to desktop 1
      qdbus org.kde.KWin /KWin setCurrentDesktop 1

      # Open terminal in NixOS directory
      konsole --profile NixOS --workdir /etc/nixos &

      # Open VS Code if installed
      if command -v code &> /dev/null; then
        code /etc/nixos &
      fi

      # Open file manager
      dolphin /etc/nixos &
    '';
  };

  home.file.".local/bin/open-stacks-workspace" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Switch to Stacks desktop and open development tools

      # Switch to desktop 2
      qdbus org.kde.KWin /KWin setCurrentDesktop 2

      # Open terminal in Stacks directory
      konsole --profile Stacks --workdir ~/stacks &

      # Open VS Code if installed
      if command -v code &> /dev/null; then
        code ~/stacks &
      fi

      # Open file manager
      dolphin ~/stacks &
    '';
  };

  # Git-aware prompt additions for project identification
  programs.starship.settings = {
    directory = {
      truncation_length = lib.mkForce 8;
      truncate_to_repo = lib.mkForce true;
      format = lib.mkForce "[$path]($style)[$read_only]($read_only_style) ";

      # Special formatting for project directories
      substitutions = {
        "/etc/nixos" = "󱄅 nixos";
        "~/stacks" = "󰆧 stacks";
      };
    };

    # Custom prompt segment to show current project
    custom.project = {
      command = ''
        if [[ "$PWD" == /etc/nixos* ]]; then
          echo "󱄅 NixOS"
        elif [[ "$PWD" == ~/stacks* ]]; then
          echo "󰆧 Stacks"
        fi
      '';
      when = ''test -n "$PWD"'';
      format = "[$output]($style) ";
      style = "bold blue";
    };
  };

  # Tmux project sessions configuration
  home.file.".config/sesh/config.toml".text = ''
    [[session]]
    name = "nixos"
    path = "/etc/nixos"
    startup_command = "nvim"

    [[session]]
    name = "stacks"
    path = "~/stacks"
    startup_command = "nvim"
  '';
}