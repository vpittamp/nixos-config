{ config, lib, pkgs, ... }:

let
  modifier = config.wayland.windowManager.sway.config.modifier;
  runtimeShellCfg = config.programs.quickshell-runtime-shell or null;
  hasRuntimeShell = runtimeShellCfg != null && (runtimeShellCfg.enable or false);
  rawToggleKey = if hasRuntimeShell then runtimeShellCfg.toggleKey else "$mod+m";
  toggleKeyList =
    let keys = if lib.isList rawToggleKey then rawToggleKey else [ rawToggleKey ];
    in map (key: lib.replaceStrings ["$mod"] [modifier] key) keys;
  monitoringPanelBindings =
    if hasRuntimeShell
    then lib.listToAttrs (map (key: lib.nameValuePair key "exec toggle-runtime-panel") (lib.unique toggleKeyList))
    else {};
  # Minimalist AI-agents monitor strip (e.g. watch the TV PWA fullscreen while
  # keeping an eye on agents). Keybind because a bar chip is hidden under a
  # fullscreen app.
  agentMonitorBindings =
    if hasRuntimeShell
    then { "${modifier}+Shift+a" = "exec toggle-agent-monitor"; }
    else {};

  # The bindings themselves live in sway-keybindings-data.nix as a described
  # list, so the runtime shell's Keys cheat sheet is generated from the same
  # source sway runs. Add or change bindings there, not here.
  keybindingData = import ./sway-keybindings-data.nix {
    inherit lib modifier hasRuntimeShell;
  };
in
{
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault (
    keybindingData.attrs
    // monitoringPanelBindings
    // agentMonitorBindings);
}
