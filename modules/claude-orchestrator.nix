{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claudeOrchestrator;

  # Scripts
  orchestratorScript = pkgs.writeScriptBin "claude-orchestrator" ''
    #!${pkgs.bash}/bin/bash
    export PATH="${pkgs.tmux}/bin:${pkgs.jq}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:$PATH"
    exec ${pkgs.bash}/bin/bash ${../scripts/claude-orchestrator.sh} "$@"
  '';

  agentMessageScript = pkgs.writeScriptBin "agent-message" ''
    #!${pkgs.bash}/bin/bash
    export PATH="${pkgs.jq}/bin:${pkgs.coreutils}/bin:$PATH"
    exec ${pkgs.bash}/bin/bash ${../scripts/agent-message.sh} "$@"
  '';

  agentLockScript = pkgs.writeScriptBin "agent-lock" ''
    #!${pkgs.bash}/bin/bash
    export PATH="${pkgs.jq}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:$PATH"
    exec ${pkgs.bash}/bin/bash ${../scripts/agent-lock.sh} "$@"
  '';

  orchestratorMonitorScript = pkgs.writeScriptBin "orchestrator-monitor" ''
    #!${pkgs.bash}/bin/bash
    export PATH="${pkgs.tmux}/bin:${pkgs.jq}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.procps}/bin:$PATH"
    exec ${pkgs.bash}/bin/bash ${../scripts/orchestrator-monitor.sh} "$@"
  '';

  # Konsole launcher for orchestrator
  konsoleOrchestratorScript = pkgs.writeScriptBin "konsole-orchestrator" ''
    #!${pkgs.bash}/bin/bash
    # Launch Konsole with orchestrator dashboard
    exec ${pkgs.kdePackages.konsole}/bin/konsole \
        --profile Orchestrator \
        --workdir "$HOME" \
        -e ${orchestratorScript}/bin/claude-orchestrator attach
  '';

in {
  options.programs.claudeOrchestrator = {
    enable = mkEnableOption "Multi-Agent Claude/Codex Orchestrator";

    package = mkOption {
      type = types.package;
      default = orchestratorScript;
      description = "The claude-orchestrator package to use";
    };

    cliTool = mkOption {
      type = types.enum [ "claude" "codex-cli" ];
      default = "claude";
      description = "The AI CLI tool to use for agents";
    };

    defaultModel = mkOption {
      type = types.str;
      default = "opus";
      description = "Default model for Claude (ignored for codex-cli)";
    };

    coordinationDir = mkOption {
      type = types.str;
      default = "$HOME/coordination";
      description = "Directory for agent coordination files";
    };

    defaultManagers = mkOption {
      type = types.listOf types.str;
      default = [ "nixos" "backstage" "stacks" ];
      description = "Default project managers to launch";
    };

    engineersPerManager = mkOption {
      type = types.int;
      default = 2;
      description = "Number of engineer agents per project manager";
    };

    enableKonsoleIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Konsole integration for GUI launching";
    };

    enableSystemdService = mkOption {
      type = types.bool;
      default = false;
      description = "Enable systemd user service for orchestrator";
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically start orchestrator service on login";
    };

    agentProfiles = mkOption {
      type = types.attrsOf (types.attrsOf types.anything);
      default = {
        orchestrator = {
          model = "opus";
          temperature = 0.7;
          maxTokens = 4000;
        };
        manager = {
          model = "sonnet";
          temperature = 0.7;
          maxTokens = 3000;
        };
        engineer = {
          model = "haiku";
          temperature = 0.8;
          maxTokens = 2000;
        };
      };
      description = "Configuration profiles for different agent types";
    };
  };

  config = mkIf cfg.enable {
    # Install scripts
    environment.systemPackages = with pkgs; [
      orchestratorScript
      agentMessageScript
      agentLockScript
      orchestratorMonitorScript
      tmux
      jq
    ] ++ optionals cfg.enableKonsoleIntegration [
      konsoleOrchestratorScript
    ];

    # Set up environment variables
    environment.sessionVariables = {
      ORCHESTRATOR_CLI = cfg.cliTool;
      DEFAULT_MODEL = cfg.defaultModel;
      COORDINATION_DIR = cfg.coordinationDir;
      DEFAULT_MANAGERS = concatStringsSep "," cfg.defaultManagers;
      DEFAULT_ENGINEERS_PER_MANAGER = toString cfg.engineersPerManager;
    };

    # Create systemd user service if enabled
    systemd.user.services.claude-orchestrator = mkIf cfg.enableSystemdService {
      description = "Multi-Agent Claude/Codex Orchestrator Service";
      after = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];

      environment = {
        ORCHESTRATOR_CLI = cfg.cliTool;
        DEFAULT_MODEL = cfg.defaultModel;
        COORDINATION_DIR = cfg.coordinationDir;
        DEFAULT_MANAGERS = concatStringsSep "," cfg.defaultManagers;
        DEFAULT_ENGINEERS_PER_MANAGER = toString cfg.engineersPerManager;
      };

      serviceConfig = {
        Type = "forking";
        ExecStart = "${orchestratorScript}/bin/claude-orchestrator launch";
        ExecStop = "${orchestratorScript}/bin/claude-orchestrator stop";
        Restart = "on-failure";
        RestartSec = 10;
      };

      wantedBy = mkIf cfg.autoStart [ "default.target" ];
    };

    # Shell aliases for convenience
    programs.bash.shellAliases = {
      "orch" = "claude-orchestrator";
      "orchestrator" = "claude-orchestrator";
      "agent-msg" = "agent-message";
      "agent-lck" = "agent-lock";
      "orch-monitor" = "orchestrator-monitor";
      "orch-mon" = "orchestrator-monitor";
    };

    # Create coordination directory on activation
    system.activationScripts.claudeOrchestrator = ''
      # Create coordination directory structure for all users
      for user_home in /home/*; do
        if [ -d "$user_home" ]; then
          user=$(basename "$user_home")
          coord_dir="$user_home/coordination"

          if [ ! -d "$coord_dir" ]; then
            mkdir -p "$coord_dir"/{agent_locks,message_queue/{orchestrator,managers,engineers},shared_memory}

            # Initialize JSON files
            if [ ! -f "$coord_dir/active_work_registry.json" ]; then
              echo '{"version":"1.0.0","orchestrator":{},"managers":{},"engineers":{},"assignments":[],"locks":[]}' \
                > "$coord_dir/active_work_registry.json"
            fi

            if [ ! -f "$coord_dir/completed_work_log.json" ]; then
              echo '{"version":"1.0.0","completed_tasks":[]}' \
                > "$coord_dir/completed_work_log.json"
            fi

            if [ ! -f "$coord_dir/shared_memory/patterns.json" ]; then
              echo '{"version":"1.0.0","patterns":{},"discovered_apis":[],"shared_insights":[]}' \
                > "$coord_dir/shared_memory/patterns.json"
            fi

            # Set ownership
            chown -R "$user:users" "$coord_dir"
          fi
        fi
      done
    '';

    # Documentation
    environment.etc."claude-orchestrator/README.md" = {
      text = ''
        # Multi-Agent Orchestrator

        ## Quick Start

        Launch the orchestrator:
        ```bash
        claude-orchestrator launch
        ```

        Attach to running session:
        ```bash
        claude-orchestrator attach
        ```

        ## Configuration

        The orchestrator is configured via NixOS options in `programs.claudeOrchestrator`.

        Current settings:
        - CLI Tool: ${cfg.cliTool}
        - Default Model: ${cfg.defaultModel}
        - Coordination Directory: ${cfg.coordinationDir}
        - Managers: ${concatStringsSep ", " cfg.defaultManagers}
        - Engineers per Manager: ${toString cfg.engineersPerManager}

        ## Agent Communication

        Send messages between agents:
        ```bash
        agent-message send orchestrator agent-001 "Task completed"
        agent-message read managers
        ```

        Manage file locks:
        ```bash
        agent-lock acquire agent-001 /path/to/file
        agent-lock release agent-001 /path/to/file
        agent-lock list
        ```

        ## Monitoring

        Launch orchestrator-specific monitor dashboard:
        ```bash
        orchestrator-monitor create
        orchestrator-monitor attach  # View in small-font Konsole
        ```

        Monitor agent status:
        ```bash
        claude-orchestrator monitor
        ```

        View work registry:
        ```bash
        claude-orchestrator status
        ```

        ## Using with Codex-CLI

        To use codex-cli instead of claude:
        ```bash
        ORCHESTRATOR_CLI=codex-cli claude-orchestrator launch
        ```

        Or set permanently in NixOS configuration:
        ```nix
        programs.claudeOrchestrator.cliTool = "codex-cli";
        ```
      '';
      mode = "0644";
    };
  };
}