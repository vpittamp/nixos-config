# Natural-language desktop commands, routed by TypeSafe's jev model.
#
# You type (or say) one line; jev picks one of this desktop's own commands and
# fills its arguments from closed sets. Nothing is generated: the model only
# ever chooses among options this file wrote, so the blast radius of a wrong
# answer is the wrong one of *our* commands, never an arbitrary one.
#
#   jev run "make the screen dimmer"     -> quickshell-brightness-key display down
#   jev plan "put this window on 3"      -> resolve it, print it, run nothing
#   jev functions                        -> the catalog
#   jev doctor                           -> key, API and binary check
#
# The catalog lives in ./catalog.nix and is built from the same sources the
# rest of the desktop reads — the application registry, the runtime shell's
# theme set, its surface ids — so it cannot offer an app that is not installed
# or a theme that does not exist. The generated spec.json is in the Nix store
# and contains no secrets; the TypeSafe key is read from 1Password at runtime.
{ config, lib, pkgs, osConfig ? null, ... }:

let
  cfg = config.programs.jev-commands;

  registry = import ../app-registry-data.nix { inherit lib; };
  themes = import ../quickshell-runtime-shell/themes.nix;

  profileBin = name: "${config.home.profileDirectory}/bin/${name}";
  localBin = name: "${config.home.homeDirectory}/.local/bin/${name}";

  # Set the backlight to an absolute level and show the OSD for it.
  # quickshell-brightness-key only steps; nothing else pairs brightnessctl
  # with the OSD, and a level set with no visible feedback reads as a no-op.
  setBrightnessScript = pkgs.writeShellScriptBin "jev-set-brightness" ''
    set -euo pipefail
    export PATH=${pkgs.coreutils}/bin:$PATH
    level="''${1:-50}"
    case "$level" in
      ""|*[!0-9]*) echo "usage: jev-set-brightness <0-100>" >&2; exit 2 ;;
    esac
    ${lib.getExe pkgs.brightnessctl} -m set "$level%" >/dev/null
    ${profileBin "runtime-shell"} call showOsd brightness "$level" >/dev/null 2>&1 || true
  '';

  bins = {
    swaymsg = "${pkgs.sway}/bin/swaymsg";
    wpctl = "${pkgs.wireplumber}/bin/wpctl";
    playerctl = "${pkgs.playerctl}/bin/playerctl";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    setBrightness = "${setBrightnessScript}/bin/jev-set-brightness";

    # Installed by sibling home modules into the user profile. Absolute paths,
    # because the runtime shell spawns its children with no inherited PATH.
    i3pm = profileBin "i3pm";
    runtimeShell = profileBin "runtime-shell";
    runtimeTheme = profileBin "runtime-theme";
    capture = profileBin "capture";
    cast = profileBin "cast";
    reminder = profileBin "runtime-reminder";
    nightlight = profileBin "quickshell-nightlight";
    lockSession = profileBin "lock-session";
    brightnessKey = profileBin "quickshell-brightness-key";
    restartShell = profileBin "quickshell-runtime-shell-restart";
    toggleDockMode = profileBin "toggle-panel-dock-mode";
    toggleNotifications = profileBin "toggle-runtime-notifications";
    toggleDnd = profileBin "toggle-runtime-notification-dnd";
    clearNotifications = profileBin "clear-runtime-notifications";
    cycleDisplayLayout = profileBin "cycle-display-layout";
    touchMode = localBin "touch-mode";
  };

  # The shell surfaces worth naming out loud. This is a subset of
  # `runtime-shell list` on purpose: ids that are only reachable as a bar panel
  # index, or that have a better-named function of their own (themes, the
  # launcher, the lock screen), would only dilute the choice.
  surfaces = [
    { id = "panel"; description = "the monitoring panel — windows, AI sessions, system health"; }
    { id = "settings"; description = "the settings window — devices, commands, configuration"; }
    { id = "expose"; description = "an overview of every open window, laid out by monitor"; }
    { id = "keybindings"; description = "the keyboard shortcut cheat sheet"; }
    { id = "notifications"; description = "the notification centre and its history"; }
    { id = "audio"; description = "the audio controls — output device, input device, volume"; }
    { id = "bluetooth"; description = "the Bluetooth panel — pair and connect devices"; }
    { id = "tailscale"; description = "the Tailscale panel — VPN, exit nodes, machines on the tailnet"; }
    { id = "display-selector"; description = "the display panel — monitors, scaling, arrangement"; }
    { id = "cast"; description = "the casting panel — TVs and receivers on the network"; }
    { id = "power-menu"; description = "the power menu — lock, suspend, restart, shut down"; }
    { id = "calendar"; description = "the calendar and the list of pending reminders"; }
    { id = "agents"; description = "AI coding subscription usage — plan limits, tokens, resets"; }
    { id = "agent-monitor"; description = "the live AI agent monitor overlay"; }
  ];

  catalog = import ./catalog.nix {
    inherit lib bins themes surfaces;
    apps = lib.filter (app: lib.elem app.name cfg.apps) registry.applications;
    workspaces = cfg.workspaces;
  };

  spec = {
    version = 1;
    inherit (cfg) model autoThreshold rejectThreshold;
    inherit (catalog) routeQuestion;
    functions = catalog.functions // cfg.extraFunctions;
  };

  specFile = pkgs.writeText "jev-command-spec.json" (builtins.toJSON spec);

  # Both entry points share jev_api.py, so the key path and the retry policy
  # are written once. They are copied into one store directory rather than
  # referenced individually: a plain `${./file}` gives each its own store path,
  # and then the import would not resolve.
  jevLib = pkgs.runCommandLocal "jev-lib" { } ''
    mkdir -p "$out"
    cp ${./jev_api.py} "$out/jev_api.py"
    cp ${./jev_dispatch.py} "$out/jev_dispatch.py"
    cp ${./agent_judge.py} "$out/agent_judge.py"
    cp ${./ha_catalog.py} "$out/ha_catalog.py"
    cp ${./ha_call.py} "$out/ha_call.py"
  '';

  jevScript = pkgs.writeShellApplication {
    name = "jev";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export JEV_SPEC=${specFile}
      export JEV_API_KEY_REF="''${JEV_API_KEY_REF:-${cfg.apiKeyReference}}"
      export JEV_FRAGMENT_DIR="''${JEV_FRAGMENT_DIR:-${fragmentDir}}"
      exec python3 ${jevLib}/jev_dispatch.py "$@"
    '';
  };

  # The agent judge: what each AI session wants, read off its own screen.
  # Shares the key and the API client with the dispatcher; its questions live
  # in agent_judge.py because they are a classification rather than a call.
  agentJudgeScript = pkgs.writeShellApplication {
    name = "agent-judge";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export JEV_API_KEY_REF="''${JEV_API_KEY_REF:-${cfg.apiKeyReference}}"
      export AGENT_JUDGE_HERDR_BIN="''${AGENT_JUDGE_HERDR_BIN:-${config.home.profileDirectory}/bin/herdr}"
      export AGENT_JUDGE_STORE="''${AGENT_JUDGE_STORE:-${judgementStorePath}}"
      export AGENT_JUDGE_LINES="''${AGENT_JUDGE_LINES:-${toString cfg.agentJudge.screenLines}}"
      export AGENT_JUDGE_ALARM_THRESHOLD="''${AGENT_JUDGE_ALARM_THRESHOLD:-${toString cfg.agentJudge.alarmThreshold}}"
      export AGENT_JUDGE_SHOW_THRESHOLD="''${AGENT_JUDGE_SHOW_THRESHOLD:-${toString cfg.agentJudge.showThreshold}}"
      export AGENT_JUDGE_RECHECK_SECONDS="''${AGENT_JUDGE_RECHECK_SECONDS:-${toString cfg.agentJudge.recheckSeconds}}"
      export AGENT_JUDGE_STRUGGLE_FLOOR="''${AGENT_JUDGE_STRUGGLE_FLOOR:-${toString cfg.agentJudge.struggleFloor}}"
      export AGENT_JUDGE_STRUGGLE_STREAK="''${AGENT_JUDGE_STRUGGLE_STREAK:-${toString cfg.agentJudge.struggleStreak}}"
      export AGENT_JUDGE_HISTORY="''${AGENT_JUDGE_HISTORY:-${toString cfg.agentJudge.historyLength}}"
      export AGENT_JUDGE_MAX_PER_HOUR="''${AGENT_JUDGE_MAX_PER_HOUR:-${toString cfg.agentJudge.maxPerHour}}"
      export AGENT_JUDGE_LOCAL_HOST="''${AGENT_JUDGE_LOCAL_HOST:-${judgeLocalHost}}"
      export AGENT_JUDGE_HOSTS=${lib.escapeShellArg (builtins.toJSON cfg.agentJudge.remoteHosts)}
      export PATH="${lib.makeBinPath [ pkgs.openssh ]}:$PATH"
      exec python3 ${jevLib}/agent_judge.py "$@"
    '';
  };

  judgementStorePath = "${config.xdg.stateHome}/quickshell-runtime-shell/agents/judgements.json";

  # ---- Home Assistant -----------------------------------------------------
  # The house cannot be baked into the store the way the desktop is: lights are
  # paired and unpaired, a TV goes unavailable when it is unplugged, a script
  # appears in the UI at four in the afternoon. So its half of the catalog is
  # generated at runtime into a fragment the dispatcher merges.
  fragmentDir = "${config.xdg.stateHome}/jev/fragments";
  haFragment = "${fragmentDir}/home-assistant.json";

  haEnv = ''
    export HASS_URL="''${HASS_URL:-${cfg.homeAssistant.url}}"
    export HASS_TOKEN_OP_REF="''${HASS_TOKEN_OP_REF:-${cfg.homeAssistant.tokenReference}}"
  '';

  haCallScript = pkgs.writeShellApplication {
    name = "ha-call";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      ${haEnv}
      exec python3 ${jevLib}/ha_call.py "$@"
    '';
  };

  haCatalogScript = pkgs.writeShellApplication {
    name = "ha-catalog";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      ${haEnv}
      export HA_FRAGMENT="''${HA_FRAGMENT:-${haFragment}}"
      export HA_CALL_BIN="''${HA_CALL_BIN:-${haCallScript}/bin/ha-call}"
      exec python3 ${jevLib}/ha_catalog.py "$@"
    '';
  };

  # The name the shell and herdr use for this machine, so a local verdict's
  # key matches the host key the session carries.
  judgeLocalHost = lib.attrByPath [ "networking" "hostName" ] "" (if osConfig != null then osConfig else { });

  # The remote herdr instances the i3pm daemon already aggregates. Taking the
  # list from there rather than restating it is what keeps the set of hosts
  # judged identical to the set of hosts shown.
  daemonRemoteTargets =
    lib.attrByPath [ "programs" "i3-project-daemon" "herdrRemoteTargets" ] [ ] config;
in
{
  options.programs.jev-commands = {
    enable = lib.mkEnableOption "natural-language desktop commands dispatched through TypeSafe jev";

    apiKeyReference = lib.mkOption {
      type = lib.types.str;
      default = "op://hub-eso/TYPESAFE-API-KEY/password";
      description = ''
        1Password reference for the TypeSafe API key, read with `op read` on
        first use and cached in $XDG_RUNTIME_DIR (tmpfs, mode 0600) for the
        rest of the session. Override at runtime with JEV_API_KEY_REF, or skip
        1Password entirely with TYPESAFE_API_KEY. Only the reference reaches
        the Nix store; the key never does.
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "jev-latest";
      description = "TypeSafe model handling the dispatch request.";
    };

    autoThreshold = lib.mkOption {
      type = lib.types.float;
      default = 0.6;
      description = ''
        A call at or above this confidence runs without asking. Confidence is
        the *least* certain judgement behind the call, not the product of them
        all — one wrong argument spoils the result, and a product would punish
        a function merely for taking more arguments.
      '';
    };

    rejectThreshold = lib.mkOption {
      type = lib.types.float;
      default = 0.3;
      description = ''
        Below this confidence the call is refused rather than offered for
        confirmation: a guess this weak is not worth a decision.
      '';
    };

    apps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = map (app: app.name)
        (lib.filter (app: !(lib.hasSuffix "-pwa" app.name)) registry.applications);
      description = ''
        Which registry applications `launch_app` can name. The default is every
        non-PWA entry. The 116 PWAs are left out because their descriptions
        would be paid for on every single command while adding options that are
        mostly environment variants of one another — "grafana dev" reaches them
        through `search_apps`, which hands the launcher the typed words. Add
        the handful you actually say out loud here.
      '';
      example = [ "terminal" "code" "grafana-hub-pwa" ];
    };

    workspaces = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = lib.range 1 10;
      description = "Workspace numbers `switch_workspace` and its siblings can name.";
    };

    extraFunctions = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Extra catalog entries, merged over the built-in ones. Same shape as
        ./catalog.nix: summary, description, argv, arguments, confirm. An
        argument is `type = "choice"` (one value out of `options`) or
        `type = "flag"` (a yes/no, with `whenTrueValue`/`whenFalseValue`);
        either may carry a `stated` question to make it optional.
      '';
      example = lib.literalExpression ''
        {
          start_vpn = {
            summary = "Connect the work VPN";
            description = "Bring up the corporate VPN tunnel.";
            argv = [ "/run/current-system/sw/bin/tailscale" "up" ];
            arguments = { };
            confirm = false;
          };
        }
      '';
    };

    homeAssistant = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Generate desktop commands for a Home Assistant instance, so the same
          command bar that moves a window can also turn off the kitchen lights.
          The catalog is rebuilt from the live house on a timer, because its
          entities change without a rebuild.
        '';
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "http://homeassistant.local:8123";
        description = "Base URL of the Home Assistant instance.";
      };

      tokenReference = lib.mkOption {
        type = lib.types.str;
        default = "op://CLI/Home Assistant MCP Token/credential";
        description = ''
          1Password reference for a long-lived Home Assistant token, read with
          `op read` at call time. Only the reference reaches the Nix store.
        '';
      };

      refreshInterval = lib.mkOption {
        type = lib.types.str;
        default = "hourly";
        description = "systemd OnCalendar for rebuilding the catalog from the live house.";
      };
    };

    agentJudge = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run `agent-judge watch`, which judges each herdr agent session from
          its own terminal screen and writes verdicts the shell watches.
        '';
      };

      screenLines = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = ''
          How many lines of the agent's visible screen are sent; 0 is the whole
          visible viewport, which is the right default. Measured across real
          panes, progress confidence climbed from 0.13 to 0.59 and from 0.74 to
          0.92 as the window widened from ten lines to the full screen. Jev's
          "excess context distracts" warning is about irrelevant state; an
          agent's own recent steps are the most relevant state there is.
        '';
      };

      alarmThreshold = lib.mkOption {
        type = lib.types.float;
        default = 0.7;
        description = ''
          At or above this, `trouble` / `risky` / `drifted` raise an alarm and
          the row is promoted to the top of the monitor. Alarms are the only
          loud thing in the UI, so the bar is deliberately high: if everything
          can shout, nothing is heard.
        '';
      };

      showThreshold = lib.mkOption {
        type = lib.types.float;
        default = 0.45;
        description = ''
          Below this the row shows nothing new and falls back to the plain
          herdr status. An unsure judgement should recede rather than be
          presented at the same weight as a certain one.
        '';
      };

      remoteHosts = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.str);
        default = map (t: { host = t.host; ssh_target = t.ssh_target; })
          (lib.filter (t: (t.ssh_target or "") != "") daemonRemoteTargets);
        description = ''
          Other machines whose herdr sessions are judged, reached by running
          their own herdr CLI over ssh — the same route the i3pm daemon uses to
          aggregate them, and the default is that daemon's own target list.

          A remote pane read costs about a tenth of a second with the
          ControlMaster this account already keeps, which is far less than the
          judgement it feeds. An unreachable host is skipped, not fatal, and
          its verdicts are kept rather than cleared: a sleeping laptop has not
          ended its sessions.
        '';
        example = lib.literalExpression [ { host = "ryzen"; ssh_target = "ryzen"; } ];
      };

      maxPerHour = lib.mkOption {
        type = lib.types.int;
        default = 600;
        description = ''
          Ceiling on judgements per hour across every host. A guardrail rather
          than a budget: it stops a rebuild storm or one chatty agent from
          running away, and anything it skips is retried on the next tick.
          0 disables the cap.
        '';
      };

      struggleFloor = lib.mkOption {
        type = lib.types.float;
        default = 0.45;
        description = ''
          Health below this counts as a bad observation. Health is the weighted
          composite of progress, understanding and not-repeating, computed in
          code from the scores jev returns.
        '';
      };

      struggleStreak = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = ''
          How many consecutive bad observations before a session is called
          struggling. One is ordinary work — every session has a failing test.
          A run of them is a trajectory, which is the thing worth interrupting
          for, and no single screen contains one.
        '';
      };

      historyLength = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "How many observations are kept per pane for the trend.";
      };

      recheckSeconds = lib.mkOption {
        type = lib.types.int;
        default = 120;
        description = ''
          How long an agent may sit in `working` before it is judged again.
          The trend is the product here, so observations are the raw material:
          two minutes gives a struggling session away inside five, where ten
          minutes took half an hour. Calls are cheap; a stuck agent is not.
        '';
      };
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The generated `jev` dispatcher.";
    };

    agentJudgePackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The `agent-judge` session classifier.";
    };

    judgementStore = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Where agent-judge writes its verdicts for the shell to watch.";
    };

    specFile = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      description = "The generated question spec, for inspection and tests.";
    };
  };

  config = lib.mkMerge [
    {
      programs.jev-commands.package = jevScript;
      programs.jev-commands.specFile = specFile;
      programs.jev-commands.agentJudgePackage = agentJudgeScript;
      programs.jev-commands.judgementStore = judgementStorePath;
    }
    (lib.mkIf cfg.enable {
      home.packages = [ jevScript setBrightnessScript agentJudgeScript ];
    })

    (lib.mkIf (cfg.enable && cfg.homeAssistant.enable) {
      home.packages = [ haCallScript haCatalogScript ];

      systemd.user.services.jev-ha-catalog = {
        Unit.Description = "Rebuild the jev Home Assistant catalog from the live house";
        Service = {
          Type = "oneshot";
          ExecStart = "${haCatalogScript}/bin/ha-catalog refresh --quiet";
        };
      };

      systemd.user.timers.jev-ha-catalog = {
        Unit.Description = "Refresh the jev Home Assistant catalog";
        Timer = {
          OnCalendar = cfg.homeAssistant.refreshInterval;
          # The house may have changed while the machine was asleep, and a
          # catalog naming a light that no longer exists is worse than a
          # catalog that is a minute late.
          OnStartupSec = "2min";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })

    (lib.mkIf (cfg.enable && cfg.agentJudge.enable) {
      systemd.user.services.agent-judge = {
        Unit = {
          Description = "Judge what each AI agent session is waiting for";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${agentJudgeScript}/bin/agent-judge watch";
          # herdr may not be up yet, and a session with no agents is normal;
          # the watcher says so once and keeps waiting rather than flapping.
          Restart = "always";
          RestartSec = 10;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })
  ];
}
