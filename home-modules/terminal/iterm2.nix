{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.iterm2;

  # Catppuccin Mocha color palette
  # Colors are in RGB format (0.0 to 1.0 decimal values)
  catppuccinMocha = {
    # ANSI Colors (0-15)
    ansi = {
      black = { r = 0.270588; g = 0.278431; b = 0.352941; }; # #454559 (surface1)
      red = { r = 0.952941; g = 0.545098; b = 0.658824; }; # #f38ba8
      green = { r = 0.650980; g = 0.890196; b = 0.631373; }; # #a6e3a1
      yellow = { r = 0.976471; g = 0.886275; b = 0.686275; }; # #f9e2af
      blue = { r = 0.537255; g = 0.705882; b = 0.980392; }; # #89b4fa
      magenta = { r = 0.960784; g = 0.760784; b = 0.905882; }; # #f5bfe7
      cyan = { r = 0.580392; g = 0.886275; b = 0.835294; }; # #94e2d5
      white = { r = 0.650980; g = 0.678431; b = 0.784314; }; # #a6adc8 (subtext0)

      brightBlack = { r = 0.345098; g = 0.356863; b = 0.439216; }; # #585b70 (surface2)
      brightRed = { r = 0.952941; g = 0.466667; b = 0.600000; }; # #f38ba8
      brightGreen = { r = 0.537255; g = 0.847059; b = 0.545098; }; # #89d88b
      brightYellow = { r = 0.921569; g = 0.827451; b = 0.568627; }; # #ead391
      brightBlue = { r = 0.454902; g = 0.658824; b = 0.988235; }; # #74a8fc
      brightMagenta = { r = 0.949020; g = 0.682353; b = 0.870588; }; # #f2aede
      brightCyan = { r = 0.419608; g = 0.843137; b = 0.792157; }; # #6bd7ca
      brightWhite = { r = 0.729412; g = 0.760784; b = 0.870588; }; # #bac2de (subtext1)
    };

    # Special colors
    foreground = { r = 0.803922; g = 0.839216; b = 0.956863; }; # #cdd6f4 (text)
    background = { r = 0.117647; g = 0.117647; b = 0.180392; }; # #1e1e2e (base)
    cursor = { r = 0.960784; g = 0.878431; b = 0.862745; }; # #f5e0dc (rosewater)
    cursorText = { r = 0.117647; g = 0.117647; b = 0.180392; }; # #1e1e2e (base)
    selection = { r = 0.345098; g = 0.356863; b = 0.439216; }; # #585b70 (surface2)
    selectedText = { r = 0.803922; g = 0.839216; b = 0.956863; }; # #cdd6f4 (text)
    link = { r = 0.537255; g = 0.862745; b = 0.921569; }; # #89dceb (sky)
    bold = { r = 0.803922; g = 0.839216; b = 0.956863; }; # #cdd6f4 (text)
  };

  # Helper function to format color for iTerm2 JSON
  formatColor = color: {
    "Red Component" = color.r;
    "Green Component" = color.g;
    "Blue Component" = color.b;
    "Alpha Component" = 1;
    "Color Space" = "sRGB";
  };

  # Generate iTerm2 dynamic profile JSON
  profileJson = builtins.toJSON {
    Profiles = [
      {
        Name = cfg.profileName;
        Guid = cfg.profileGuid;
        # No parent specified - iTerm2 will use default profile automatically

        # Terminal settings
        "Terminal Type" = "xterm-256color";
        "Use Custom Command" = "No";
        "Use Modern Parser" = true;

        # Color settings
        "Ansi 0 Color" = formatColor catppuccinMocha.ansi.black;
        "Ansi 1 Color" = formatColor catppuccinMocha.ansi.red;
        "Ansi 2 Color" = formatColor catppuccinMocha.ansi.green;
        "Ansi 3 Color" = formatColor catppuccinMocha.ansi.yellow;
        "Ansi 4 Color" = formatColor catppuccinMocha.ansi.blue;
        "Ansi 5 Color" = formatColor catppuccinMocha.ansi.magenta;
        "Ansi 6 Color" = formatColor catppuccinMocha.ansi.cyan;
        "Ansi 7 Color" = formatColor catppuccinMocha.ansi.white;
        "Ansi 8 Color" = formatColor catppuccinMocha.ansi.brightBlack;
        "Ansi 9 Color" = formatColor catppuccinMocha.ansi.brightRed;
        "Ansi 10 Color" = formatColor catppuccinMocha.ansi.brightGreen;
        "Ansi 11 Color" = formatColor catppuccinMocha.ansi.brightYellow;
        "Ansi 12 Color" = formatColor catppuccinMocha.ansi.brightBlue;
        "Ansi 13 Color" = formatColor catppuccinMocha.ansi.brightMagenta;
        "Ansi 14 Color" = formatColor catppuccinMocha.ansi.brightCyan;
        "Ansi 15 Color" = formatColor catppuccinMocha.ansi.brightWhite;

        "Background Color" = formatColor catppuccinMocha.background;
        "Foreground Color" = formatColor catppuccinMocha.foreground;
        "Cursor Color" = formatColor catppuccinMocha.cursor;
        "Cursor Text Color" = formatColor catppuccinMocha.cursorText;
        "Selection Color" = formatColor catppuccinMocha.selection;
        "Selected Text Color" = formatColor catppuccinMocha.selectedText;
        "Link Color" = formatColor catppuccinMocha.link;
        "Bold Color" = formatColor catppuccinMocha.bold;

        # Cursor guide color (semi-transparent text color)
        "Cursor Guide Color" = {
          "Red Component" = catppuccinMocha.foreground.r;
          "Green Component" = catppuccinMocha.foreground.g;
          "Blue Component" = catppuccinMocha.foreground.b;
          "Alpha Component" = 0.07;
          "Color Space" = "sRGB";
        };

        # Font settings (if specified)
        "Normal Font" = cfg.font.name + " " + toString cfg.font.size;
        "Use Non-ASCII Font" = false;

        # Visual settings
        "Minimum Contrast" = 0;
        "Use Bold Font" = true;
        "Use Bright Bold" = true;
        "Use Italic Font" = true;
        "Use Underline Color" = false;

        # Scrollback
        "Unlimited Scrollback" = cfg.unlimitedScrollback;
        "Scrollback Lines" = if cfg.unlimitedScrollback then 0 else cfg.scrollbackLines;

        # Window settings
        "Window Type" = 0; # Normal
        "Transparency" = cfg.transparency;
        "Blur" = cfg.blur;
        "Blur Radius" = cfg.blurRadius;

        # Key mappings
        "Left Option Key Sends" = 2; # Esc+
        "Right Option Key Sends" = 0; # Normal
      }
    ];
  };
in
{
  options.programs.iterm2 = {
    enable = mkEnableOption "iTerm2 declarative configuration";

    profileName = mkOption {
      type = types.str;
      default = "NixOS Catppuccin";
      description = "Name of the iTerm2 profile";
    };

    profileGuid = mkOption {
      type = types.str;
      default = "nixos-catppuccin-mocha";
      description = "Unique identifier for the profile";
    };

    font = {
      name = mkOption {
        type = types.str;
        default = "MesloLGS-NF-Regular";
        description = "Font name for iTerm2";
      };

      size = mkOption {
        type = types.int;
        default = 14;
        description = "Font size";
      };
    };

    unlimitedScrollback = mkOption {
      type = types.bool;
      default = true;
      description = "Enable unlimited scrollback";
    };

    scrollbackLines = mkOption {
      type = types.int;
      default = 10000;
      description = "Number of scrollback lines (when not unlimited)";
    };

    transparency = mkOption {
      type = types.float;
      default = 0.0;
      description = "Background transparency (0.0 to 1.0)";
    };

    blur = mkOption {
      type = types.bool;
      default = false;
      description = "Enable background blur";
    };

    blurRadius = mkOption {
      type = types.float;
      default = 2.0;
      description = "Blur radius when blur is enabled";
    };
  };

  config = mkIf cfg.enable {
    # Create dynamic profile directory and file
    home.file."Library/Application Support/iTerm2/DynamicProfiles/nixos-catppuccin.json" = {
      text = profileJson;
    };

    # Optional: Install recommended fonts
    # Note: nerdfonts has been restructured - use nerd-fonts namespace
    home.packages = with pkgs; [
      nerd-fonts.meslo-lg
    ];
  };
}
