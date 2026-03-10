{ config, pkgs, lib, ... }:

let
  gitSigningPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7";
in
{
  # Git credential OAuth - disabled in favor of 1Password integration
  programs.git-credential-oauth = {
    enable = false;  # We use 1Password git-credential-op instead
  };

  # Git configuration
  # Note: Using new `settings` option format (home-manager 24.11+)
  programs.git = {
    enable = true;

    # SSH signing configuration with 1Password
    # All commits will be signed with SSH key from 1Password
    signing = {
      key = gitSigningPublicKey;
      signByDefault = true;  # Sign all commits by default for verification
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
      };

      init.defaultBranch = "main";
      core = {
        editor = "nvim";
        autocrlf = "input";
      };
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = false;

      # SSH signing configuration
      gpg = {
        format = "ssh";
        ssh = {
          program = "${pkgs._1password-gui or pkgs._1password-cli}/bin/op-ssh-sign";
          allowedSignersFile = "~/.config/git/allowed_signers";
        };
      };

      # Credential helpers - disabled for SSH-only authentication
      # We use SSH keys via 1Password SSH agent instead of HTTPS credential helpers
      # If you need HTTPS authentication, consider using git-credential-oauth
      # credential = {
      #   helper = "${pkgs.git-credential-oauth}/bin/git-credential-oauth";
      # };
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
