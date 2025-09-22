{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.tmuxSupervisor;

  # Enhanced supervisor script
  tmuxSupervisorScript = pkgs.writeScriptBin "tmux-supervisor" ''
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash ${../scripts/tmux-supervisor-enhanced.sh} "$@"
  '';

  # Simple supervisor script
  tmuxSupervisorSimpleScript = pkgs.writeScriptBin "tmux-supervisor-simple" ''
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash ${../scripts/tmux-supervisor-simple.sh} "$@"
  '';

  # Konsole launcher for supervisor
  konsoleSupervisorScript = pkgs.writeScriptBin "konsole-supervisor" ''
    #!${pkgs.bash}/bin/bash
    # Launch Konsole with tmux supervisor dashboard using Supervisor profile
    exec ${pkgs.kdePackages.konsole}/bin/konsole \
        --profile Supervisor \
        --workdir "$HOME"
  '';

in {
  options.programs.tmuxSupervisor = {
    enable = mkEnableOption "Tmux Supervisor Dashboard for cross-activity session management";

    package = mkOption {
      type = types.package;
      default = tmuxSupervisorScript;
      description = "The tmux-supervisor package to use";
    };

    enableKonsoleIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Konsole integration for launching supervisor dashboard";
    };

    enableSystemdService = mkOption {
      type = types.bool;
      default = false;
      description = "Enable systemd user service for persistent supervisor";
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically start supervisor service on login";
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional settings for tmux supervisor";
      example = {
        refreshInterval = 30;
        maxSessions = 12;
        gridLayout = "auto";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install the supervisor scripts
    environment.systemPackages = with pkgs; [
      tmuxSupervisorScript
      tmuxSupervisorSimpleScript
    ] ++ optionals cfg.enableKonsoleIntegration [
      konsoleSupervisorScript
    ];

    # Create systemd user service if enabled
    systemd.user.services.tmux-supervisor = mkIf cfg.enableSystemdService {
      description = "Tmux Supervisor Dashboard Service";
      after = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];

      serviceConfig = {
        Type = "forking";
        ExecStart = "${tmuxSupervisorScript}/bin/tmux-supervisor start";
        ExecStop = "${pkgs.tmux}/bin/tmux kill-session -t supervisor-dashboard";
        Restart = "on-failure";
        RestartSec = 5;
      };

      wantedBy = mkIf cfg.autoStart [ "default.target" ];
    };

    # Add shell aliases for convenience
    programs.bash.shellAliases = {
      "tmux-sup" = "tmux-supervisor";
      "tsup" = "tmux-supervisor";
      "supervisor" = "tmux-supervisor";
    };

    # Note: Desktop entries should be created in home-manager configuration
    # not at the system level. Users can add desktop entries in their
    # home configuration if desired.

    # Create configuration file if settings are provided
    environment.etc."tmux-supervisor/config" = mkIf (cfg.settings != {}) {
      text = lib.generators.toKeyValue {} cfg.settings;
      mode = "0644";
    };
  };
}