{ config, pkgs, lib, ... }:

{
  # Starship prompt configuration for containers (without colorScheme dependency)
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      format = "$username$hostname $directory$git_branch$git_status$nix_shell$kubernetes\n$character ";
      
      # Catppuccin Mocha colors directly embedded
      palette = "catppuccin_mocha";
      
      palettes.catppuccin_mocha = {
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
        overlay2 = "#585b70";
        overlay1 = "#45475a";
        overlay0 = "#313244";
        surface2 = "#585b70";
        surface1 = "#45475a";
        surface0 = "#313244";
        base = "#1e1e2e";
        mantle = "#181825";
        crust = "#11111b";
      };
      
      username = {
        show_always = true;
        style_user = "bold fg:mauve";
        style_root = "bold fg:red";
        format = "[$user]($style)";
      };
      
      hostname = {
        ssh_only = false;
        style = "fg:blue";
        format = "@[$hostname]($style)";
        trim_at = "-";
      };
      
      directory = {
        style = "bold fg:green";
        format = "[$path]($style)";
        truncation_length = 3;
        truncation_symbol = "…/";
        home_symbol = "~";
      };
      
      directory.substitutions = {
        "Documents" = "D";
        "Downloads" = "DL";
        "Music" = "M";
        "Pictures" = "P";
        "Developer" = "DEV";
      };
      
      git_branch = {
        symbol = "⎇";
        style = "fg:yellow";
        format = " [$symbol $branch]($style)";
      };
      
      git_status = {
        style = "fg:yellow";
        format = "[$all_status$ahead_behind]($style)";
        conflicted = "=";
        ahead = "⇡";
        behind = "⇣";
        diverged = "⇕";
        untracked = "?";
        modified = "!";
        renamed = "»";
        deleted = "✘";
        stashed = "$";
        staged = "+";
      };
      
      nodejs = {
        symbol = "⬢";
        style = "fg:green";
        format = " [$symbol($version)]($style)";
        detect_extensions = ["js" "mjs" "cjs" "ts" "tsx"];
        detect_files = ["package.json" ".node-version"];
        detect_folders = ["node_modules"];
      };
      
      python = {
        symbol = "🐍";
        style = "fg:yellow";
        format = " [$symbol($version)]($style)";
        detect_extensions = ["py"];
        detect_files = ["requirements.txt" "pyproject.toml" "Pipfile" "setup.py"];
        detect_folders = ["__pycache__" ".venv" "venv"];
      };
      
      rust = {
        symbol = "🦀";
        style = "fg:peach";
        format = " [$symbol($version)]($style)";
        detect_extensions = ["rs"];
        detect_files = ["Cargo.toml" "Cargo.lock"];
      };
      
      golang = {
        symbol = "🐹";
        style = "fg:sapphire";
        format = " [$symbol($version)]($style)";
        detect_extensions = ["go"];
        detect_files = ["go.mod" "go.sum" "glide.yaml" "Gopkg.yml" "Gopkg.lock"];
      };
      
      nix_shell = {
        disabled = false;
        impure_msg = "[nix]";
        pure_msg = "[nix-pure]";
        unknown_msg = "[nix?]";
        format = "[$state( $name)]($style) ";
        style = "fg:blue bold";
      };
      
      kubernetes = {
        symbol = "☸";
        style = "fg:sapphire";
        format = " [$symbol $context]($style)";
        disabled = false;
        contexts = [
          { context_pattern = "arn:aws:eks:.*:cluster/(.*)"; context_alias = "$1"; }
          { context_pattern = "(.{15}).*"; context_alias = "$1..."; }
        ];
      };
      
      docker_context = {
        symbol = "🐋";
        style = "fg:blue";
        format = " [$symbol $context]($style)";
        only_with_files = true;
        detect_files = ["docker-compose.yml" "docker-compose.yaml" "Dockerfile"];
      };
      
      cmd_duration = {
        min_time = 2000;
        style = "fg:yellow";
        format = " took [$duration]($style)";
      };
      
      character = {
        success_symbol = "[➜](bold fg:green)";
        error_symbol = "[➜](bold fg:red)";
        vimcmd_symbol = "[❮](bold fg:green)";
      };
    };
  };
}