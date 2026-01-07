{ config, pkgs, lib, ... }:
let
  # Feature 106: Portable script wrappers for worktree support
  scriptWrappers = import ../../shared/script-wrappers.nix { inherit pkgs lib; };

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
      right_format = "$custom.i3pm_project $time";
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

      format = lib.concatStrings [
        "$os$username$hostname"
        "\${custom.tmux}"
        "$directory"
        # Git info: branch, commit, worktree context, status, state, metrics
        "$git_branch"
        "$git_commit"
        "\${custom.git_worktree}"
        "$git_status"
        "$git_state"
        "$git_metrics"
        "$fill"
        "$nix_shell"
        "$kubernetes"
        "$cmd_duration"
        "$line_break"
        "$character"
      ];

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

      # Feature 106: portable wrapper for worktree support
      custom.i3pm_project = {
        when = "[ -x ${scriptWrappers.i3pm-project-badge}/bin/i3pm-project-badge ] && test -n \"$I3PM_PROJECT_NAME$I3PM_PROJECT_DISPLAY_NAME\"";
        command = "${scriptWrappers.i3pm-project-badge}/bin/i3pm-project-badge --plain";
        style = "fg:${colors.peach} bold";
        format = "[$output]($style)";
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

      # Show short commit hash (helpful for referencing specific commits)
      git_commit = {
        commit_hash_length = 7;
        style = "fg:${colors.subtext0}";
        format = "[@$hash]($style)";
        tag_disabled = false;
        tag_symbol = " 🏷 ";
        tag_max_candidates = 1;
        only_detached = false;
      };

      # Show lines added/deleted in current changes
      git_metrics = {
        disabled = false;
        added_style = "fg:${colors.green}";
        deleted_style = "fg:${colors.red}";
        # Only show when there are actual changes
        only_nonzero_diffs = true;
        format = " [+$added]($added_style)/[-$deleted]($deleted_style)";
      };

      # Custom worktree indicator - shows when in a git worktree with context
      custom.git_worktree = {
        when = "test \"$I3PM_IS_WORKTREE\" = \"true\" || git rev-parse --is-inside-work-tree >/dev/null 2>&1 && test -n \"$(git rev-parse --git-common-dir 2>/dev/null)\" && [ \"$(git rev-parse --git-common-dir 2>/dev/null)\" != \"$(git rev-parse --git-dir 2>/dev/null)\" ]";
        command = ''
          if [ "$I3PM_IS_WORKTREE" = "true" ]; then
            # Use I3PM environment for rich context
            type="''${I3PM_BRANCH_TYPE:-wt}"
            num="''${I3PM_BRANCH_NUMBER:-}"
            if [ -n "$num" ]; then
              echo "⌥$type#$num"
            else
              echo "⌥$type"
            fi
          else
            # Fallback: detect git worktree without I3PM
            echo "⌥wt"
          fi
        '';
        style = "fg:${colors.pink} bold";
        format = " [$output]($style)";
      };

      git_status = {
        # Show explicit counts for each status type with clear symbols
        format = lib.concatStrings [
          "("
          "[$conflicted](bold fg:${colors.red})"
          "[$stashed](fg:${colors.mauve})"
          "[$staged](fg:${colors.green})"
          "[$modified](fg:${colors.yellow})"
          "[$renamed](fg:${colors.peach})"
          "[$deleted](fg:${colors.red})"
          "[$untracked](fg:${colors.sky})"
          "[$ahead_behind](fg:${colors.sapphire})"
          ")"
        ];
        # Staged files (ready to commit)
        staged = " +\${count}";
        # Modified files (changed but not staged)
        modified = " ~\${count}";
        # Untracked files (new, not in git)
        untracked = " ?\${count}";
        # Deleted files
        deleted = " ✗\${count}";
        # Renamed files
        renamed = " →\${count}";
        # Merge conflicts
        conflicted = " ⚠\${count}";
        # Stashed changes
        stashed = " ≡\${count}";
        # Commits ahead of remote
        ahead = " ↑\${count}";
        # Commits behind remote
        behind = " ↓\${count}";
        # Branch has diverged (show both)
        diverged = " ↑\${ahead_count}↓\${behind_count}";
        # Up to date with remote (optional indicator)
        up_to_date = "";
        # File type changed
        typechanged = " τ\${count}";
      };

      git_state = {
        style = "fg:${colors.maroon}";
        format = " [$state( $progress_current/$progress_total)]($style)";
        # Clear labels for each operation type
        rebase = "REBASING";
        merge = "MERGING";
        revert = "REVERTING";
        cherry_pick = "CHERRY-PICK";
        bisect = "BISECTING";
        am = "AM";  # applying patches
        am_or_rebase = "AM/REBASE";
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
