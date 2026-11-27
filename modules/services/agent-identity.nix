# Agent identity separation (option-b design v2, section 5, step I2).
#
# Lead coding agents (Claude Code, Codex, agy and their subagents) run as a
# separate OS user instead of the owner. That user:
#   - authors on GitHub as the App `pittampalli-agent-author` (installation
#     token minted on dev, fetched on demand; contents/issues/pull_requests on
#     PittampalliOrg/stacks and PittampalliOrg/workflow-builder only);
#   - reads dev (and, after the stacks follow-up, hub) through ServiceAccounts
#     with the built-in `view` role; it has no other kube context;
#   - cannot read the owner's home, is in no privileged group, has no sudo,
#     no subordinate uid range and no SSH login (unless keys are configured,
#     and then without forwarding);
#   - has every login land in its own user+network+mount namespace (private
#     loopback, private /tmp, internet via pasta), and an nftables table keyed
#     on its uid that rejects host-local, tailnet and container destinations
#     for anything it runs outside that namespace.
#
# Owner runbook: docs/AGENT_IDENTITY.md. Not enabled by default on any host.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkOption mkIf mkMerge mkAfter mkForce types concatStringsSep optionalString;
  cfg = config.services.agentIdentity;

  scriptsDir = ../../scripts/agent-identity;

  subst = text: builtins.replaceStrings
    [ "@agentUser@" "@agentUid@" "@ownerUser@" "@stateDir@" "@cacheDir@" "@runDir@" "@allowedRepos@" "@botLogin@" "@botEmail@" ]
    [ cfg.user (toString cfg.uid) cfg.ownerUser cfg.stateDir cfg.cacheDir cfg.runDir (concatStringsSep " " cfg.github.repositories) cfg.github.botLogin cfg.github.botEmail ]
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

  agentNetnsPublish = mkScript {
    name = "agent-netns-publish";
    file = "agent-netns-publish.sh";
    runtimeInputs = with pkgs; [ coreutils procps ];
  };

  agentEnter = mkScript {
    name = "agent-enter";
    file = "agent-enter.sh";
    runtimeInputs = with pkgs; [ coreutils util-linux systemd gawk ];
  };

  # Login shell of the agent user: every login (sudo -i, su -, ssh, sftp)
  # lands inside the agent namespace, or fails.
  agentLoginShell = (pkgs.writeShellScriptBin "agent-login-shell" ''
    exec ${agentEnter}/bin/agent-enter ${pkgs.bashInteractive}/bin/bash --login "$@"
  '').overrideAttrs (_: { passthru.shellPath = "/bin/agent-login-shell"; });

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
    # A FAIL is recorded and the run continues: no errexit. The probe script
    # is single-quoted on purpose (SC2016).
    bashOptions = [ "nounset" "pipefail" ];
    excludeShellChecks = [ "SC2016" ];
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.gnugrep pkgs.gnused pkgs.gawk pkgs.iproute2 pkgs.python3 pkgs.getent pkgs.findutils pkgs.openssh pkgs.acl ];
  };

  uid = toString cfg.uid;

  # One table for both firewall backends. It matches the agent uid POSITIVELY
  # in the hooked chain and nothing else: packets without a full socket
  # (kernel RSTs, ICMP errors, echo replies, FIN/LAST-ACK after close) and
  # every other uid pass the hook untouched. Numeric uid: the ruleset is
  # checked at build time in a sandbox without the user database.
  # tests/agent-identity/namespace-tests.sh exercises it in scratch namespaces.
  nftRules = ''
    chain deny {
      meta l4proto tcp counter reject with tcp reset
      counter reject with icmpx admin-prohibited
    }

    chain agent_out {
      # Name resolution through MagicDNS stays available.
      ip daddr 100.100.100.100 meta l4proto { tcp, udp } th dport 53 accept
      ip6 daddr fd7a:115c:a1e0::53 meta l4proto { tcp, udp } th dport 53 accept

      # Published container ports (DNAT, also from host addresses).
      ct status dnat counter jump deny

      # The tailnet.
      ${optionalString cfg.network.blockTailscaleInterface ''oifname "tailscale0" counter jump deny''}
      ip daddr 100.64.0.0/10 counter jump deny
      ip6 daddr fd7a:115c:a1e0::/48 counter jump deny

      # Host loopback and the host's own addresses (they route via lo).
      oifname "lo" counter jump deny

      # Container and VM networks on this host.
      oifname "docker0" counter jump deny
      oifname "br-*" counter jump deny
      oifname "veth*" counter jump deny
      oifname "podman*" counter jump deny
      oifname "virbr*" counter jump deny
      oifname "incus*" counter jump deny
      oifname "cni*" counter jump deny
    }

    chain output {
      type filter hook output priority filter; policy accept;
      meta skuid ${uid} jump agent_out
    }
  '';

  nftRulesFile = pkgs.writeText "agent-identity.nft" ''
    table inet agent-identity {
    ${nftRules}
    }
  '';

  sshHasKeys = cfg.authorizedKeys != [ ];
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
      description = "Fixed uid of the agent user (the nftables table and the tailscaled ACL match it numerically).";
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
      description = "Root-owned runtime directory; holds netns.pid, written by root.";
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
      description = ''
        SSH public keys that may log in as the agent (e.g. `herdr --remote`).
        Empty (default): sshd denies the user outright. Non-empty: keys are
        read only from the root-owned /etc/ssh/authorized_keys.d/<user>, all
        forwarding is off, and the login shell enters the agent namespace.
      '';
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
        {
          # A subordinate range would let the agent run processes under other
          # kernel uids (newuidmap), which the uid-keyed table does not match.
          assertion = !config.users.users.${cfg.user}.autoSubUidGidRange
            && config.users.users.${cfg.user}.subUidRanges == [ ]
            && config.users.users.${cfg.user}.subGidRanges == [ ];
          message = "services.agentIdentity: the agent user must have no subordinate uid/gid range";
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
        extraGroups = mkForce [ ];
        # No /etc/subuid or /etc/subgid line (podman otherwise turns
        # autoSubUidGidRange on for normal users).
        autoSubUidGidRange = mkForce false;
        subUidRanges = mkForce [ ];
        subGidRanges = mkForce [ ];
        # Locked password: reachable only through the owner's sudo.
        hashedPassword = "!";
        openssh.authorizedKeys.keys = cfg.authorizedKeys;
        shell = agentLoginShell;
        ignoreShellProgramCheck = true;
      };
      environment.shells = [ agentLoginShell ];

      # sshd (TCP and the AF_UNIX socket-activated instance share this config).
      services.openssh.settings.DenyUsers = mkIf (!sshHasKeys) [ cfg.user ];
      services.openssh.extraConfig = mkIf sshHasKeys (mkAfter ''
        Match User ${cfg.user}
          AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
          AllowTcpForwarding no
          AllowStreamLocalForwarding no
          AllowAgentForwarding no
          X11Forwarding no
          PermitTunnel no
          PermitUserRC no
        Match all
      '');

      # Agent processes never hold the owner's terminal (no TIOCSTI injection
      # into the owner's shell after an agent session ends).
      security.sudo.extraConfig = ''
        Defaults use_pty
      '';
      boot.kernel.sysctl."dev.tty.legacy_tiocsti" = lib.mkDefault 0;

      systemd.tmpfiles.rules = [
        "d ${cfg.stateDir} 0755 root root -"
        "d ${cfg.runDir} 0755 root root -"
        "d ${cfg.cacheDir} 0700 ${cfg.user} ${cfg.user} -"
      ];

      environment.systemPackages = [
        agentEnter
        agentSession
        agentShell
        agentIdentityProvision
        agentIdentityVerify
        pkgs.acl
      ];

      # One user+network+mount namespace for all agent sessions: internet via
      # pasta, no path to host loopback, private /tmp, /var/tmp and /dev/shm.
      # PrivateTmp is set up by systemd in a mount namespace owned by the
      # initial user namespace, so inside the agent's own user namespace those
      # mounts are locked and cannot be unmounted to reveal the host's /tmp.
      systemd.services.agent-netns = {
        description = "Namespace for AI agent sessions (pasta; private loopback and /tmp)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "systemd-tmpfiles-setup.service" ];
        wants = [ "network-online.target" ];
        # A rebuild must not silently cut running sessions off the network.
        # Restart deliberately: sudo systemctl restart agent-netns.
        restartIfChanged = false;
        serviceConfig = {
          User = cfg.user;
          Group = cfg.user;
          ExecStart = "${agentNetns}/bin/agent-netns";
          # As root: publish the namespace holder's pid in the root-owned
          # runtime directory, only after it has left the host namespaces.
          ExecStartPost = "+${agentNetnsPublish}/bin/agent-netns-publish";
          ExecStopPost = "+${pkgs.coreutils}/bin/rm -f ${cfg.runDir}/netns.pid ${cfg.runDir}/host-netns";
          PrivateTmp = true;
          TemporaryFileSystem = "/dev/shm:mode=1777";
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

      system.build.agentIdentityNftRules = nftRulesFile;
    }

    # tailscaled's LocalAPI socket is a 0666 file socket; through it tailscaled
    # (root) dials the tailnet on the caller's behalf, which no uid-keyed
    # firewall rule sees. Deny the agent uid the directory. /run/tailscale is
    # tailscaled's RuntimeDirectory: systemd recreates it on every start and
    # removes it on stop, so a tmpfiles ACL would be lost on the first
    # restart. ExecStartPre runs after systemd has created the directory and
    # before tailscaled creates the socket, so there is no window
    # (ExecStartPost would leave one).
    (mkIf config.services.tailscale.enable {
      systemd.services.tailscaled.serviceConfig.ExecStartPre = [
        "+${pkgs.acl}/bin/setfacl -m u:${uid}:--- /run/tailscale"
      ];
    })

    # Firewall backend: nftables hosts (ryzen) get a declarative table that
    # survives the NixOS ruleset flush; iptables hosts (thinkpad, surface) get
    # the same table from a oneshot unit.
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
        description = "nftables table agent-identity (agent uid only)";
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
