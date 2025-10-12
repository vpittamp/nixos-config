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
      palette = "catppuccin_mocha";
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

      format = "$os$username$hostname\${custom.tmux}$directory$git_branch$git_status$git_state$fill$nix_shell$kubernetes$cmd_duration$line_break$character";

      os = {
        disabled = false;
        style = "bold fg:${colors.lavender}";
        format = "[$symbol]($style)";
        symbols = {
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
        style_user = "bold fg:${colors.rosewater}";
        style_root = "bold fg:${colors.red}";
        format = "[$user]($style)";
      };

      hostname = {
        ssh_only = false;
        style = "fg:${colors.sapphire}";
        format = "@[$hostname]($style) ";
      };

      custom.tmux = {
        when = "test -n \"$TMUX\"";
        command = "echo \"$TMUX_PANE\"";
        style = "bold fg:${colors.sky}";
        format = "[$output]($style) ";
      };

      directory = {
        style = "bold fg:${colors.green}";
        format = "[$path]($style) ";
        truncation_length = 3;
        truncation_symbol = "…/";
        home_symbol = "~";
        truncate_to_repo = false;
      };

      git_branch = {
        symbol = "⎇ ";
        style = "fg:${colors.peach}";
        format = "[$symbol$branch]($style)";
      };

      git_status = {
        style = "fg:${colors.yellow}";
        format = " [$all_status$ahead_behind]($style)";
      };

      git_state = {
        style = "fg:${colors.maroon}";
        format = " [$state( $progress_current/$progress_total)]($style)";
      };

      nix_shell = {
        symbol = "❄ ";
        style = "fg:${colors.sky} bold";
        format = "[$symbol$state( $name)]($style) ";
      };

      kubernetes = {
        symbol = "☸";
        style = "fg:${colors.teal}";
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
        style = "fg:${colors.yellow}";
        format = " [⏱ $duration]($style)";
      };

      fill = {
        symbol = " ";
      };

      time = {
        disabled = false;
        time_format = "%H:%M";
        style = "fg:${colors.subtext0}";
        format = "[$time]($style)";
      };

      character = {
        success_symbol = "[❯](bold fg:${colors.green})";
        error_symbol = "[❯](bold fg:${colors.red})";
        vimcmd_symbol = "[❮](bold fg:${colors.green})";
      };
    };
  };
}
