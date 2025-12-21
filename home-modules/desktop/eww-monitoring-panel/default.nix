{ config, lib, pkgs, osConfig ? null, monitorConfig ? {}, ... }:

with lib;

let
  cfg = config.programs.eww-monitoring-panel;

  hostname = osConfig.networking.hostName or "hetzner";

  hostMonitors = monitorConfig.${hostname} or {
    primary = "HEADLESS-1";
    secondary = "HEADLESS-2";
    tertiary = "HEADLESS-3";
    quaternary = "HEADLESS-3";
    outputs = [ "HEADLESS-1" "HEADLESS-2" "HEADLESS-3" ];
  };

  primaryOutput = hostMonitors.primary;

  theme = import ./theme.nix {};
  mocha = theme.mocha;

  utils = import ./utils.nix { inherit pkgs; };
  pythonForBackend = utils.pythonForBackend;
  clipboardSyncScript = utils.clipboardSyncScript;

  scripts = import ./scripts/default.nix {
    inherit pkgs config pythonForBackend mocha hostname cfg clipboardSyncScript;
  };

  inherit (scripts)
    monitoringDataScript wrapperScript toggleScript toggleDockModeScript
    monitorPanelTabScript monitorPanelGetViewScript monitorPanelIsProjectsScript
    monitorPanelNavScript swayNCToggleScript restartServiceScript
    projectCrudScript projectEditOpenScript projectEditSaveScript
    projectConflictResolveScript formValidationStreamScript
    worktreeCreateOpenScript worktreeAutoPopulateScript
    worktreeDeleteOpenScript worktreeDeleteConfirmScript
    worktreeDeleteCancelScript worktreeValidateBranchScript
    worktreeEditOpenScript worktreeCreateScript worktreeDeleteScript
    worktreeEditSaveScript toggleProjectExpandedScript toggleExpandAllScript projectsNavScript
    copyProjectJsonScript projectCreateOpenScript projectCreateSaveScript
    projectCreateCancelScript projectDeleteOpenScript projectDeleteConfirmScript
    projectDeleteCancelScript appCreateOpenScript appCreateSaveScript
    appCreateCancelScript appDeleteOpenScript appDeleteConfirmScript
    appDeleteCancelScript showSuccessNotificationScript startWindowTraceScript
    fetchTraceEventsScript navigateToTraceScript navigateToEventScript
    startTraceFromTemplateScript focusWindowScript switchProjectScript closeWorktreeScript
    closeAllWindowsScript closeWindowScript toggleProjectContextScript
    toggleWindowsProjectExpandScript copyWindowJsonScript copyTraceDataScript
    fetchWindowEnvScript handleKeyScript pulsePhaseScript;

  mainYuck = import ./yuck/main.yuck.nix {
    inherit primaryOutput toggleDockModeScript;
    panelWidth = cfg.panelWidth;
  };

  variablesYuck = import ./yuck/variables.yuck.nix {
    inherit monitoringDataScript pulsePhaseScript;
  };

  windowsViewYuck = import ./yuck/windows-view.yuck.nix (scripts // { inherit pkgs; });

  projectsViewYuck = import ./yuck/projects-view.yuck.nix (scripts // { inherit pkgs; });

  formsYuck = import ./yuck/forms.yuck.nix (scripts // { inherit pkgs; });

  dialogsYuck = import ./yuck/dialogs.yuck.nix (scripts // { inherit pkgs; });

  notificationsYuck = import ./yuck/notifications.yuck.nix {};

  disabledStubsYuck = import ./yuck/disabled-stubs.yuck.nix {};

  mainScss = import ./scss.nix {
    inherit mocha;
  };

in
{
  options.programs.eww-monitoring-panel = {
    enable = mkEnableOption "Eww monitoring panel for window/project state visualization";

    toggleKey = mkOption {
      type = types.str;
      default = "$mod+m";
      description = "Keybinding to toggle monitoring panel visibility.";
    };

    updateInterval = mkOption {
      type = types.int;
      default = 10;
      description = "DEPRECATED: This option is no longer used since migrating to deflisten.";
    };

    panelWidth = mkOption {
      type = types.int;
      default = if hostname == "thinkpad" || hostname == "ryzen" then 450 else 307;
      description = "Width of the monitoring panel in pixels.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.eww
      pkgs.inotify-tools
      monitoringDataScript
      toggleScript
      toggleDockModeScript
      monitorPanelTabScript
      monitorPanelGetViewScript
      monitorPanelIsProjectsScript
      monitorPanelNavScript
      swayNCToggleScript
      restartServiceScript
      focusWindowScript
      switchProjectScript
      closeWorktreeScript
      closeAllWindowsScript
      closeWindowScript
      toggleProjectContextScript
      toggleWindowsProjectExpandScript
      projectCrudScript
      projectEditOpenScript
      projectEditSaveScript
      worktreeEditOpenScript
      worktreeCreateScript
      worktreeDeleteScript
      worktreeEditSaveScript
      toggleProjectExpandedScript
      toggleExpandAllScript
      projectsNavScript
      worktreeCreateOpenScript
      worktreeAutoPopulateScript
      worktreeValidateBranchScript
      worktreeDeleteOpenScript
      worktreeDeleteConfirmScript
      worktreeDeleteCancelScript
      projectCreateOpenScript
      projectCreateSaveScript
      projectCreateCancelScript
      appCreateOpenScript
      appCreateSaveScript
      appCreateCancelScript
      projectDeleteOpenScript
      projectDeleteConfirmScript
      projectDeleteCancelScript
      appDeleteOpenScript
      appDeleteConfirmScript
      appDeleteCancelScript
      showSuccessNotificationScript
      pulsePhaseScript
    ];

    xdg.configFile."eww-monitoring-panel/eww.yuck".text = mainYuck;
    xdg.configFile."eww-monitoring-panel/variables.yuck".text = variablesYuck;
    xdg.configFile."eww-monitoring-panel/windows-view.yuck".text = windowsViewYuck;
    xdg.configFile."eww-monitoring-panel/projects-view.yuck".text = projectsViewYuck;
    xdg.configFile."eww-monitoring-panel/forms.yuck".text = formsYuck;
    xdg.configFile."eww-monitoring-panel/dialogs.yuck".text = dialogsYuck;
    xdg.configFile."eww-monitoring-panel/notifications.yuck".text = notificationsYuck;
    xdg.configFile."eww-monitoring-panel/popups.yuck".text = "";
    xdg.configFile."eww-monitoring-panel/disabled-stubs.yuck".text = disabledStubsYuck;
    xdg.configFile."eww-monitoring-panel/eww.scss".text = mainScss;

    systemd.user.services.eww-monitoring-panel = {
      Unit = {
        Description = "Eww Monitoring Panel for Window/Project State";
        After = [ "sway-session.target" "i3-project-daemon.service" "home-manager-vpittamp.service" ];
        Wants = [ "i3-project-daemon.service" ];
        PartOf = [ "sway-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'mkdir -p %h/.local/state/eww-monitoring-panel && ${pkgs.eww}/bin/eww --config %h/.config/eww-monitoring-panel kill 2>/dev/null || true'";
        ExecStart = "${wrapperScript}/bin/eww-monitoring-panel-wrapper";
        ExecStopPost = "${pkgs.bash}/bin/bash -c '${pkgs.eww}/bin/eww --config %h/.config/eww-monitoring-panel kill 2>/dev/null || true'";
        Restart = "on-failure";
        RestartSec = "3s";
        KillMode = "control-group";
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}