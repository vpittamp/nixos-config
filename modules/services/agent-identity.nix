# Agent identity separation (option-b design v2, section 5, step I2).
#
# Lead coding agents (Claude Code, Codex, agy and their subagents) run as a
# separate OS user instead of the owner. That user:
#   - authors on GitHub as the App `pittampalli-agent-author` (installation
#     token minted on dev, fetched on demand; contents/issues/pull_requests on
#     PittampalliOrg/stacks and PittampalliOrg/workflow-builder only, no
#     workflows, no admin);
#   - reads dev (and, after the stacks follow-up, hub) through ServiceAccounts
#     with the built-in `view` role; it has no admin kube context at all;
#   - cannot read the owner's home (gh token, kubeconfig, 1Password socket,
#     SSH keys, browser profile, reviewer App key), is in no privileged group,
#     has no sudo;
#   - cannot reach the tailnet (whose apiserver proxies and Headlamp
#     authenticate by DEVICE identity, i.e. as the owner) or the host's
#     loopback listeners (browser DevTools port, local MCP servers): enforced
#     by an nftables table keyed on the agent uid, and in daily use by running
#     every agent session inside its own network namespace (pasta) that has
#     internet and a private loopback.
#
# Owner runbook and verification: docs/AGENT_IDENTITY.md.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkOption mkIf mkMerge types concatStringsSep optionalString;
  cfg = config.services.agentIdentity;

  scriptsDir = ../../scripts/agent-identity;

  subst = text: builtins.replaceStrings
    [ "@agentUser@" "@ownerUser@" "@stateDir@" "@cacheDir@" "@runDir@" "@allowedRepos@" "@botLogin@" "@botEmail@" ]
    [ cfg.user cfg.ownerUser cfg.stateDir cfg.cacheDir cfg.runDir (concatStringsSep " " cfg.github.repositories) cfg.github.botLogin cfg.github.botEmail ]
    text;

  mkScript = { name, file, runtimeInputs, extraSubst ? (t: t), excludeShellChecks ? [ ], bashOptions ? [ "errexit" "nounset" "pipefail" ] }:
    pkgs.writeShellApplication {
      inherit name runtimeInputs excludeShellChecks bashOptions;
      text = extraSubst (subst (builtins.readFile (scriptsDir + "/${file}")));
    };

  agentAuthorToken = mkScript {
    name = "agent-author-token";
    file = "agent-author-token.sh";
    runtimeInputs = with pkgs; [ coreutils curl jq gawk gnugrep findutils ];
  };

  agentNetns = mkScript {
    name = "agent-netns";
    file = "agent-netns.sh";
    runtimeInputs = with pkgs; [ coreutils util-linux passt ];
  };

  agentEnter = mkScript {
    name = "agent-enter";
    file = "agent-enter.sh";
    runtimeInputs = with pkgs; [ coreutils util-linux ];
  };

  # sudo is the setuid wrapper from the inherited PATH (/run/wrappers/bin);
  # writeShellApplication prepends runtimeInputs and keeps the caller's PATH.
  agentSession = mkScript {
    name = "agent-session";
    file = "agent-session.sh";
    runtimeInputs = [ pkgs.coreutils ];
    extraSubst = builtins.replaceStrings [ "@mode@" ] [ "session" ];
  };
  agentShell = mkScript {
    name = "agent-shell";
    file = "agent-session.sh";
    runtimeInputs = [ pkgs.coreutils ];
    extraSubst = builtins.replaceStrings [ "@mode@" ] [ "shell" ];
  };

  agentIdentityProvision = mkScript {
    name = "agent-identity-provision";
    file = "agent-identity-provision.sh";
    runtimeInputs = [ pkgs.coreutils pkgs.kubectl pkgs.gnused pkgs.gnugrep ];
  };

  agentIdentityVerify = mkScript {
    name = "agent-identity-verify";
    file = "agent-identity-verify.sh";
    # A FAIL is recorded and the run continues: no errexit. pass/fail always
    # return 0, so `test && pass || fail` is a correct if/else (SC2015); the
    # probe script is single-quoted on purpose (SC2016).
    bashOptions = [ "nounset" "pipefail" ];
    excludeShellChecks = [ "SC2015" "SC2016" ];
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.gnugrep pkgs.gawk pkgs.iproute2 pkgs.python3 pkgs.getent ];
  };

  uid = toString cfg.uid;

  # One rule body for both firewall backends. Numeric uid: the ruleset is
  # checked at build time in a sandbox without the user database.
  nftRules = ''
    # Refused, not silently dropped. (Measured in a scratch user+net
    # namespace: a matching-uid loopback connect does not complete, it ends
    # in the client's connect timeout; a non-matching uid connects.)
    chain deny {
      meta l4proto tcp counter reject with tcp reset
      counter reject
    }

    chain output {
      type filter hook output priority filter; policy accept;
      meta skuid != ${uid} accept

      # Name resolution through Tailscale MagicDNS stays available.
      ip daddr 100.100.100.100 meta l4proto { tcp, udp } th dport 53 accept
      ip6 daddr fd7a:115c:a1e0::53 meta l4proto { tcp, udp } th dport 53 accept

      # The tailnet authenticates by device, i.e. as the owner (apiserver
      # proxies with system:masters, Headlamp, Argo CD): never for the agent.
      ${optionalString cfg.network.blockTailscaleInterface ''oifname "tailscale0" jump deny''}
      ip daddr 100.64.0.0/10 jump deny
      ip6 daddr fd7a:115c:a1e0::/48 jump deny

      # Host loopback (and the host's own addresses, which route via lo):
      # the owner's browser DevTools port, local MCP servers, IDE bridges.
      # Agent sessions get their own loopback inside agent-netns.
      oifname "lo" jump deny
    }
  '';

  nftRulesFile = pkgs.writeText "agent-identity.nft" ''
    table inet agent-identity {
    ${nftRules}
    }
  '';
in
{
  options.services.agentIdentity = {
    enable = mkEnableOption "a separate OS user for AI coding agents, with its own GitHub App identity and read-only cluster access";

    user = mkOption {
      type = types.str;
      default = "agent";
      description = "OS user that agent CLIs run as.";
    };

    uid = mkOption {
      type = types.int;
      default = 2001;
      description = "Fixed uid of the agent user (the nftables table matches it numerically).";
    };

    ownerUser = mkOption {
      type = types.str;
      default = "vpittamp";
      description = "The human owner. Only this user launches agent sessions and provisions tokens.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/agent-identity";
      description = ''
        Owner-placed files: <cluster>-server, <cluster>-ca.crt (public), the
        bound ServiceAccount tokens (0600, owned by the agent user) and the
        agent's kubeconfig (no secret in it).
      '';
    };

    cacheDir = mkOption {
      type = types.str;
      default = "/run/agent-identity/github";
      description = "tmpfs cache of the current App token (agent-owned, 0700).";
    };

    runDir = mkOption {
      type = types.str;
      default = "/run/agent-identity";
      description = "Runtime directory of agent-netns (holds netns.pid).";
    };

    github = {
      repositories = mkOption {
        type = types.listOf types.str;
        default = [ "PittampalliOrg/stacks" "PittampalliOrg/workflow-builder" ];
        description = "The only repositories git hands the App token to. Must equal the App installation's.";
      };
      botLogin = mkOption {
        type = types.str;
        default = "pittampalli-agent-author[bot]";
        description = "Commit author/committer name.";
      };
      botEmail = mkOption {
        type = types.str;
        # 362024332 is the bot user's id (gh api 'users/pittampalli-agent-author%5Bbot%5D' --jq .id),
        # not the App id (5954793).
        default = "362024332+pittampalli-agent-author[bot]@users.noreply.github.com";
        description = "Commit author/committer email (GitHub noreply address of the App's bot user).";
      };
    };

    network.blockTailscaleInterface = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Reject every agent packet routed via tailscale0 (subnet routes
        included), not only tailnet addresses. With a Tailscale exit node set,
        this also cuts the agent's internet: that is the fail-closed choice.
      '';
    };

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "SSH public keys that may log in as the agent (e.g. for `herdr --remote agent@<host>`). Empty: no SSH login.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.user != cfg.ownerUser;
          message = "services.agentIdentity.user must differ from ownerUser";
        }
        {
          # The whole separation rests on the owner's home being closed.
          assertion = config.users.users.${cfg.ownerUser}.homeMode == "700";
          message = "services.agentIdentity: users.users.${cfg.ownerUser}.homeMode must be \"700\"";
        }
        {
          assertion = !(builtins.elem cfg.user (config.users.groups.wheel.members or [ ]));
          message = "services.agentIdentity: the agent user must not be in wheel";
        }
      ];

      users.groups.${cfg.user} = { gid = cfg.uid; };
      users.users.${cfg.user} = {
        isNormalUser = true;
        uid = cfg.uid;
        group = cfg.user;
        description = "AI coding agents (GitHub App pittampalli-agent-author)";
        home = "/home/${cfg.user}";
        createHome = true;
        homeMode = "700";
        # No privileged or owner groups: not wheel, docker, podman, onepassword,
        # networkmanager, input, libvirtd, users.
        extraGroups = lib.mkForce [ ];
        # Locked password: reachable only through the owner's sudo (and SSH
        # keys, if any are listed).
        hashedPassword = "!";
        openssh.authorizedKeys.keys = cfg.authorizedKeys;
        shell = pkgs.bashInteractive;
      };

      # Agent processes never hold the owner's terminal (no TIOCSTI injection
      # into the owner's shell after an agent session ends).
      security.sudo.extraConfig = ''
        Defaults use_pty
      '';
      boot.kernel.sysctl."dev.tty.legacy_tiocsti" = lib.mkDefault 0;

      systemd.tmpfiles.rules = [
        # Owner-placed: public server URL/CA, agent-owned 0600 token files,
        # kubeconfig without secrets. Listing it reveals nothing.
        "d ${cfg.stateDir} 0755 root root -"
        "d ${cfg.runDir} 0700 ${cfg.user} ${cfg.user} -"
        "d ${cfg.cacheDir} 0700 ${cfg.user} ${cfg.user} -"
      ];

      environment.systemPackages = [
        agentEnter
        agentSession
        agentShell
        agentIdentityProvision
        agentIdentityVerify
      ];

      # One user+network namespace for all agent sessions, with internet via
      # pasta and no path to host loopback. Sessions join it via agent-enter.
      systemd.services.agent-netns = {
        description = "Network namespace for AI agent sessions (pasta, no host loopback)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "systemd-tmpfiles-setup.service" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          User = cfg.user;
          Group = cfg.user;
          ExecStart = "${agentNetns}/bin/agent-netns";
          Restart = "on-failure";
          RestartSec = 5;
        };
      };

      home-manager.users.${cfg.user} = {
        imports = [ ../../home-modules/profiles/agent-home.nix ];
        _module.args.agentIdentity = {
          inherit (cfg) stateDir;
          inherit (cfg.github) botLogin botEmail repositories;
          inherit agentAuthorToken;
        };
      };
    }

    # Firewall backend: nftables hosts (ryzen) get a declarative table that
    # survives the NixOS ruleset flush; iptables hosts (thinkpad, surface) get
    # the same table from a oneshot unit (iptables-nft/legacy and an nft table
    # hook side by side; any reject wins).
    (mkIf config.networking.nftables.enable {
      networking.nftables.tables.agent-identity = {
        family = "inet";
        content = nftRules;
      };
      systemd.services.agent-netns = {
        requires = [ "nftables.service" ];
        after = [ "nftables.service" ];
      };
    })
    (mkIf (!config.networking.nftables.enable) {
      systemd.services.agent-identity-netfilter = {
        description = "nftables table agent-identity (agent uid: no tailnet, no host loopback)";
        wantedBy = [ "multi-user.target" ];
        before = [ "network-pre.target" ];
        wants = [ "network-pre.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre = "-${pkgs.nftables}/bin/nft delete table inet agent-identity";
          ExecStart = "${pkgs.nftables}/bin/nft -f ${nftRulesFile}";
          ExecStop = "${pkgs.nftables}/bin/nft delete table inet agent-identity";
        };
      };
      systemd.services.agent-netns = {
        requires = [ "agent-identity-netfilter.service" ];
        after = [ "agent-identity-netfilter.service" ];
      };
    })
  ]);
}
