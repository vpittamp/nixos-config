# Starship Prompt Configuration
#
# Color Strategy:
# - Darwin (macOS): Uses simple ANSI color names (blue, cyan, green, yellow, red)
#   due to Terminal.app + tmux compatibility issues with RGB colors
# - Linux: Can use Catppuccin Mocha RGB palette (currently disabled for consistency)
#
# Palette Status:
# - Catppuccin palette defined below but not activated (line ~37 commented)
# - All prompt elements use ANSI colors for cross-platform compatibility
# - To enable Catppuccin on Linux: uncomment palette line or add platform conditional
#
# Related Configuration:
# - bash.nix: Sets color environment variables on Darwin+tmux (lines 269-279)
# - tmux.nix: Sets escape-time to prevent OSC color query sequences on Darwin (line 46)
#
# Troubleshooting:
# - If colors missing: Check COLORTERM environment variable (should be "truecolor")
# - If OSC sequences visible: Check VTE_VERSION and STARSHIP_NO_COLOR_QUERY
# - If git status shows $!: Ensure format uses $modified not $all_status
#
# See: specs/003-incorporate-this-into/ for full documentation

{ config, pkgs, lib, ... }:
let
  colors = {
    rosewater = "#f5e0dc";
    flamingo = "#f2cdcd";
    pink = "#f5c2e7";
    mauve = "#cba6f7";
    red = "#f38ba8";
    maroon = "#eba0ac";
    peach = "#fab387";
    yellow = "#f9e2af";
    green = "#a6e3a1";
    teal = "#94e2d5";
    sky = "#89dceb";
    sapphire = "#74c7ec";
    blue = "#89b4fa";
    lavender = "#b4befe";
    text = "#cdd6f4";
    subtext1 = "#bac2de";
    subtext0 = "#a6adc8";
    surface2 = "#585b70";
    surface1 = "#45475a";
    surface0 = "#313244";
    base = "#1e1e2e";
    mantle = "#181825";
    crust = "#11111b";
  };
in
{
  programs.starship = {
    enable = true;
    enableBashIntegration = true;

    settings = {
      add_newline = true;
      # Palette disabled - using simple ANSI colors for compatibility
      # palette = "catppuccin_mocha";
      right_format = "$time";
      continuation_prompt = "⋯ ";

      palettes.catppuccin_mocha = {
        rosewater = colors.rosewater;
        flamingo = colors.flamingo;
        pink = colors.pink;
        mauve = colors.mauve;
        red = colors.red;
        maroon = colors.maroon;
        peach = colors.peach;
        yellow = colors.yellow;
        green = colors.green;
        teal = colors.teal;
        sky = colors.sky;
        sapphire = colors.sapphire;
        blue = colors.blue;
        lavender = colors.lavender;
        text = colors.text;
        subtext1 = colors.subtext1;
        subtext0 = colors.subtext0;
        overlay2 = colors.surface2;
        overlay1 = colors.surface1;
        overlay0 = colors.surface0;
        surface2 = colors.surface2;
        surface1 = colors.surface1;
        surface0 = colors.surface0;
        base = colors.base;
        mantle = colors.mantle;
        crust = colors.crust;
      };

      # Simplified format for debugging - hostname already includes @
      format = "$username$hostname $directory$git_branch$git_status$character";

      os = {
        disabled = false;
        style = "bold blue";  # Was: fg:${colors.lavender}
        format = "[$symbol]($style)";
        symbols = {
          Macos = " ";  # Apple logo Nerd Font icon
          NixOS = "❄ ";  # Snowflake (works without Nerd Fonts)
          Debian = " ";  # Debian Nerd Font icon
          Ubuntu = " ";  # Ubuntu Nerd Font icon
          Arch = " ";  # Arch Nerd Font icon
          Fedora = " ";  # Fedora Nerd Font icon
          Alpine = " ";  # Alpine Nerd Font icon
          Linux = " ";  # Tux penguin Nerd Font icon
        };
      };

      username = {
        show_always = true;
        # Test with direct color codes instead of palette
        style_user = "bold blue";
        style_root = "bold red";
        format = "[$user]($style)";
      };

      hostname = {
        ssh_only = false;
        # Test with direct color
        style = "cyan";
        format = "@[$hostname]($style) ";
      };

      custom.tmux = {
        when = "test -n \"$TMUX\"";
        command = "echo \"$TMUX_PANE\"";
        style = "bold cyan";  # Was: bold fg:${colors.sky}
        format = "[$output]($style) ";
      };

      directory = {
        # Test with simple color
        style = "bold green";
        format = "[$path]($style) ";
        truncation_length = 3;
        truncation_symbol = "…/";
        home_symbol = "~";
        truncate_to_repo = false;
      };

      git_branch = {
        symbol = "⎇ ";
        # Test with simple color
        style = "yellow";
        format = "[$symbol$branch]($style)";
      };

      git_status = {
        # Test with simple color
        style = "red";
        # Simplified format - explicitly list status indicators
        format = "([$modified$untracked]($style) )";
        modified = "!";
        untracked = "?";
      };

      git_state = {
        style = "red";  # Was: fg:${colors.maroon}
        format = " [$state( $progress_current/$progress_total)]($style)";
      };

      nix_shell = {
        symbol = "❄ ";
        style = "cyan bold";  # Was: fg:${colors.sky} bold
        format = "[$symbol$state( $name)]($style) ";
      };

      kubernetes = {
        symbol = "☸";
        style = "cyan";  # Was: fg:${colors.teal}
        format = " [$symbol $context]($style)";
        disabled = false;
        contexts = [
          { context_pattern = "vcluster_.*_kind-localdev"; context_alias = "vcluster"; }
          { context_pattern = "arn:aws:eks:.*:cluster/(.*)"; context_alias = "$1"; }
          { context_pattern = "gke_.*_(?P<cluster>[\\w-]+)"; context_alias = "gke-$cluster"; }
          { context_pattern = "(.{20}).*"; context_alias = "$1…"; }
        ];
      };

      cmd_duration = {
        min_time = 2000;
        style = "yellow";  # Was: fg:${colors.yellow}
        format = " [⏱ $duration]($style)";
      };

      fill = {
        symbol = " ";
      };

      time = {
        disabled = false;
        time_format = "%H:%M";
        style = "bright-black";  # Was: fg:${colors.subtext0}
        format = "[$time]($style)";
      };

      character = {
        # Test with simple colors
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
        vimcmd_symbol = "[❮](bold green)";
      };
    };
  };
}
