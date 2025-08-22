{ config, pkgs, lib, ... }:
let
  colors = config.colorScheme;
in
{
  # Modern shell prompt with Starship - Pure ASCII configuration
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      format = "$username$hostname $directory$git_branch$git_status $kubernetes\n$character ";
      
      palette = "catppuccin_mocha";
      
      palettes.catppuccin_mocha = {
        rosewater = "${colors.rosewater}";
        flamingo = "${colors.flamingo}";
        pink = "${colors.pink}";
        mauve = "${colors.mauve}";
        red = "${colors.red}";
        maroon = "${colors.maroon}";
        peach = "${colors.peach}";
        yellow = "${colors.yellow}";
        green = "${colors.green}";
        teal = "${colors.teal}";
        sky = "${colors.sky}";
        sapphire = "${colors.sapphire}";
        blue = "${colors.blue}";
        lavender = "${colors.lavender}";
        text = "${colors.text}";
        subtext1 = "${colors.subtext1}";
        subtext0 = "${colors.subtext0}";
        overlay2 = "${colors.surface2}";
        overlay1 = "${colors.surface1}";
        overlay0 = "${colors.surface0}";
        surface2 = "${colors.surface2}";
        surface1 = "${colors.surface1}";
        surface0 = "${colors.surface0}";
        base = "${colors.base}";
        mantle = "${colors.mantle}";
        crust = "${colors.crust}";
      };
      
      os = {
        disabled = true;  # Disable OS to avoid encoding issues
        style = "fg:${colors.blue}";
        format = "[$symbol ]($style)";
      };
      
      os.symbols = {
        Ubuntu = "U";
        Debian = "D";
        Linux = "L";
        Arch = "A";
        Fedora = "F";
        Alpine = "Al";
        Amazon = "Am";
        Android = "An";
        Macos = "M";
        Windows = "W";
      };
      
      username = {
        show_always = true;
        style_user = "bold fg:${colors.mauve}";
        style_root = "bold fg:${colors.red}";
        format = "[$user]($style)";
      };
      
      hostname = {
        ssh_only = false;
        style = "fg:${colors.blue}";
        format = "@[$hostname]($style)";
        trim_at = "-";
      };
      
      directory = {
        style = "bold fg:${colors.green}";
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
        style = "fg:${colors.yellow}";
        format = " [$symbol $branch]($style)";
      };
      
      git_status = {
        style = "fg:${colors.yellow}";
        format = "[$all_status$ahead_behind]($style)";
        conflicted = "=";
        ahead = "⇡";
        behind = "⇣";
        diverged = "⇕";
        untracked = "?";
        modified = "!";
        renamed = "»";
        deleted = "✘";
        stashed = "\\$";
        staged = "+";
        typechanged = "±";
      };
      
      nodejs = {
        symbol = "⬢";
        style = "fg:${colors.green}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["js" "mjs" "cjs" "ts" "tsx"];
        detect_files = ["package.json" ".node-version"];
        detect_folders = ["node_modules"];
      };
      
      c = {
        symbol = "C";
        style = "fg:${colors.green}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["c" "h"];
      };
      
      rust = {
        symbol = "R";
        style = "fg:${colors.peach}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["rs"];
        detect_files = ["Cargo.toml" "Cargo.lock"];
      };
      
      golang = {
        symbol = "GO";
        style = "fg:${colors.sapphire}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["go"];
        detect_files = ["go.mod" "go.sum" "glide.yaml" "Gopkg.yml" "Gopkg.lock"];
      };
      
      php = {
        symbol = "PHP";
        style = "fg:${colors.lavender}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["php"];
        detect_files = ["composer.json" ".php-version"];
      };
      
      java = {
        symbol = "J";
        style = "fg:${colors.peach}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["java" "class" "jar"];
        detect_files = ["pom.xml" "build.gradle.kts" "build.sbt"];
      };
      
      kotlin = {
        symbol = "K";
        style = "fg:${colors.lavender}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["kt" "kts"];
      };
      
      haskell = {
        symbol = "λ";
        style = "fg:${colors.mauve}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["hs" "lhs"];
        detect_files = ["stack.yaml" "cabal.project"];
      };
      
      python = {
        symbol = "PY";
        style = "fg:${colors.yellow}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["py"];
        detect_files = ["requirements.txt" "pyproject.toml" "Pipfile" "setup.py"];
        detect_folders = ["__pycache__" ".venv" "venv"];
      };
      
      docker_context = {
        symbol = "D";
        style = "fg:${colors.blue}";
        format = " [$symbol]($style)";
        only_with_files = true;
        detect_files = ["docker-compose.yml" "docker-compose.yaml" "Dockerfile"];
        disabled = false;
      };
      
      kubernetes = {
        symbol = "☸";
        style = "fg:${colors.sapphire}";
        format = " [$symbol $context]($style)";
        disabled = false;
        # Define shorter aliases for long context names
        contexts = [
          { context_pattern = "vcluster_.*_kind-localdev"; context_alias = "vcluster"; }
          { context_pattern = "arn:aws:eks:.*:cluster/(.*)"; context_alias = "$1"; }
          { context_pattern = "gke_.*_(?P<cluster>[\\w-]+)"; context_alias = "gke-$cluster"; }
          { context_pattern = "(.{15}).*"; context_alias = "$1..."; }  # Truncate to 15 chars
        ];
      };
      
      fill = {
        symbol = " ";
      };
      
      time = {
        disabled = true;
        time_format = "%H:%M";
        style = "fg:${colors.subtext0}";
        format = "[$time]($style)";
      };
      
      cmd_duration = {
        min_time = 2000;
        style = "fg:${colors.yellow}";
        format = "[took $duration]($style)";
      };
      
      character = {
        success_symbol = "[➜](bold fg:${colors.green})";
        error_symbol = "[➜](bold fg:${colors.red})";
        vimcmd_symbol = "[❮](bold fg:${colors.green})";
      };
    };
  };
}