{ pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Vinod Pittampalli";
    userEmail = "vinod@pittampalli.com";

    # Basic git configuration without 1Password signing
    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "nvim";

      # Basic pull/push settings
      pull.rebase = false;
      push.autoSetupRemote = true;

      # URL shortcuts
      url."git@github.com:".insteadOf = "gh:";
      url."git@gitlab.com:".insteadOf = "gl:";

      # Basic commit signing (disabled for container)
      commit.gpgsign = false;

      # Performance settings
      core.preloadindex = true;
      core.fscache = true;
      gc.auto = 256;

      # Color settings
      color.ui = "auto";
      color.diff = {
        meta = "yellow bold";
        frag = "magenta bold";
        old = "red bold";
        new = "green bold";
      };

      # Aliases
      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
        df = "diff";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        last = "log -1 HEAD";
        unstage = "reset HEAD --";
        amend = "commit --amend";
        contributors = "shortlog --summary --numbered";
        undo = "reset --soft HEAD^";
        prune-branches = "!git branch --merged | grep -v '\\*\\|main\\|master\\|develop' | xargs -n 1 git branch -d";
        sync = "!git fetch --all --prune && git rebase origin/$(git branch --show-current)";
        quickfix = "commit -am 'Quick fix'";
        wip = "commit -am 'WIP: Work in progress'";
        fixup = "commit --fixup";
        squash = "rebase -i --autosquash";
      };
    };

    # Delta diff tool configuration
    delta = {
      enable = true;
      options = {
        navigate = true;
        light = false;
        side-by-side = true;
        line-numbers = true;
        syntax-theme = "Dracula";
        plus-style = "syntax #003800";
        minus-style = "syntax #3f0001";
        features = "decorations";
        decorations = {
          commit-decoration-style = "bold yellow box ul";
          file-style = "bold yellow ul";
          file-decoration-style = "none";
          hunk-header-decoration-style = "cyan box ul";
        };
      };
    };

    # Ignore files
    ignores = [
      ".DS_Store"
      "*.swp"
      "*~"
      ".idea"
      ".vscode"
      "*.iml"
      ".env.local"
      "node_modules"
      ".direnv"
    ];
  };
}