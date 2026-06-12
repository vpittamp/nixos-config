{ config, pkgs, lib, ... }:

let
  gitSigningPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7";
in
{
  # GitHub/GitLab transport should not depend on an unlocked 1Password SSH
  # agent. Commit signing can still use 1Password explicitly with `git commit -S`.
  programs.git-credential-oauth = {
    enable = false;
  };

  home.packages = [
    pkgs.gh
    pkgs.git-credential-oauth
  ];

  # Git configuration
  # Note: Using new `settings` option format (home-manager 24.11+)
  programs.git = {
    enable = true;

    # 1Password-backed SSH signing is intentionally opt-in. Requiring it for
    # every commit makes non-interactive repo maintenance fail when 1Password is
    # locked or unable to display an authorization prompt.
    signing = {
      key = gitSigningPublicKey;
      signByDefault = false;
    };

    # New settings format (replaces userName, userEmail, aliases, extraConfig)
    settings = {
      user = {
        name = "Vinod Pittampalli";
        email = "vinod@pittampalli.com";
      };

      alias = {
        co = "checkout";
        ci = "commit";
        st = "status";
        br = "branch";
        hist = "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short";
        type = "cat-file -t";
        dump = "cat-file -p";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        last = "log -1 HEAD";
        unstage = "reset HEAD --";
        cs = "commit -S";
      };

      init.defaultBranch = "main";
      core = {
        editor = "nvim";
        autocrlf = "input";
      };
      pager = {
        diff = "diffnav";
        show = "diffnav";
      };
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = false;
      commit.gpgsign = false;
      tag.gpgsign = false;

      credential = {
        "https://github.com" = {
          helper = "!gh auth git-credential";
        };
        "https://gitlab.com" = {
          helper = "oauth";
        };
      };

      url = {
        "https://github.com/" = {
          insteadOf = [
            "git@github.com:"
            "ssh://git@github.com/"
          ];
        };
      };

      # SSH signing configuration
      gpg = {
        format = "ssh";
        ssh = {
          program = "${pkgs._1password-gui or pkgs._1password-cli}/bin/op-ssh-sign";
          allowedSignersFile = "~/.config/git/allowed_signers";
        };
      };

      # SSH signing configuration. This is only used when a commit/tag is
      # explicitly signed with -S.
    };
  };
  
  # Create the allowed signers file for SSH signing verification
  home.file.".config/git/allowed_signers".text = ''
    vinod@pittampalli.com ${gitSigningPublicKey}
  '';

  # OpenSSH needs a real public key file when IdentitiesOnly is enabled.
  # Point github/gitlab auth at the same 1Password-managed SSH key used for signing.
  home.file.".ssh/git_signing_key.pub".text = "${gitSigningPublicKey} Git Signing Key\n";
}
