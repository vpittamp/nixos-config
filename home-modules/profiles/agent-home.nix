# Home of the `agent` OS user (services.agentIdentity, modules/services/agent-identity.nix).
#
# Deliberately NOT base-home.nix: nothing here knows the owner's identity,
# 1Password, SSH agent, browser profiles, Docker or desktop session. The agent
# gets the CLIs it works with, the GitHub App identity, and a read-only
# kubeconfig. MCP servers, Claude/Codex logins and memory are the agent's own
# (set up by the owner once, see docs/AGENT_IDENTITY.md).
{ config, lib, pkgs, inputs, agentIdentity, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  tokenBin = "${agentIdentity.agentAuthorToken}/bin/agent-author-token";

  userPackages = import ../../user/packages.nix { inherit pkgs lib inputs; };

  # Same herdr build as the owner's (user/packages.nix).
  herdr = inputs.herdr.packages.${system}.default.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../../patches/herdr-codex-raw-agent-detection.patch ];
  });
  claudeCode = inputs.claude-code-nix.packages.${system}.claude-code or pkgs.claude-code;
  codex = pkgs.callPackage ../../packages/codex.nix { };
  antigravityCli = pkgs.callPackage ../../packages/antigravity-cli.nix { };

  # gh as the App: every invocation gets the current installation token.
  # Commands that would store or broaden a credential are refused.
  ghAsApp = pkgs.writeShellApplication {
    name = "gh";
    runtimeInputs = [ ];
    text = ''
      case "''${1:-} ''${2:-}" in
        "auth login"*|"auth refresh"*|"auth setup-git"*|"auth switch"*|"auth token"*)
          echo "gh (agent): 'gh $1 $2' is disabled; this user authenticates only as pittampalli-agent-author via agent-author-token" >&2
          exit 1 ;;
      esac
      unset GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
      GH_TOKEN="$(${tokenBin})"
      export GH_TOKEN
      exec ${pkgs.gh}/bin/gh "$@"
    '';
  };

  sharedSkillsDir = ../../shared-skills;
  sharedSkillDirs = lib.filterAttrs (_: t: t == "directory" || t == "symlink")
    (if builtins.pathExists sharedSkillsDir then builtins.readDir sharedSkillsDir else { });
  skillFiles = prefix: lib.mapAttrs'
    (name: _: lib.nameValuePair "${prefix}/${name}" {
      source = sharedSkillsDir + "/${name}";
      recursive = true;
      force = true;
    })
    sharedSkillDirs;
in
{
  home.username = "agent";
  home.homeDirectory = "/home/agent";
  home.stateVersion = "25.05";
  home.enableNixpkgsReleaseCheck = false;

  programs.home-manager.enable = true;
  programs.bash = {
    enable = true;
    initExtra = ''
      if [ -z "''${AGENT_IDENTITY_NETNS:-}" ]; then
        echo "agent: this shell is OUTSIDE the agent network namespace; host loopback and the tailnet are blocked here. Use agent-enter." >&2
      fi
    '';
  };

  home.packages =
    userPackages.terminal
    ++ userPackages.languageServers
    ++ userPackages.packageManagers
    ++ userPackages.nix
    ++ [
      ghAsApp
      agentIdentity.agentAuthorToken
      herdr
      claudeCode
      codex
      antigravityCli
      pkgs.kubectl
      pkgs.kubernetes-helm
      pkgs.git-lfs
      pkgs.delta
      pkgs.nodejs
      pkgs.python3
      pkgs.gnumake
      pkgs.gcc
    ];

  home.sessionVariables = {
    # Read-only kubeconfig placed by the owner (agent-identity-provision); it
    # names only ServiceAccount contexts and points at 0600 token files.
    KUBECONFIG = "${agentIdentity.stateDir}/kubeconfig";
    GIT_TERMINAL_PROMPT = "0";
    GH_PROMPT_DISABLED = "1";
    EDITOR = "nvim";
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = agentIdentity.botLogin;
        email = agentIdentity.botEmail;
      };
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = false;
      commit.gpgsign = false;
      tag.gpgsign = false;
      credential = {
        # Only this helper; it answers only for the allowed repositories and
        # tells git to stop (quit=1) for anything else.
        helper = "";
        "https://github.com" = {
          helper = "!${tokenBin} git-credential";
          useHttpPath = true;
        };
      };
      # The agent has no SSH key: route GitHub SSH remotes to HTTPS.
      url."https://github.com/".insteadOf = [ "git@github.com:" "ssh://git@github.com/" ];
    };
  };

  xdg.configFile."gh/config.yml".text = ''
    git_protocol: https
    prompt: disabled
  '';

  home.file = skillFiles ".claude/skills" // skillFiles ".codex/skills";
}
