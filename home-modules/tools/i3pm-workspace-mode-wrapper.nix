# Temporary wrapper for workspace mode IPC calls
# TODO: Replace with TypeScript CLI integration (add workspace-mode subcommand to i3pm/src/main.ts)
{ pkgs, ... }:

let
  workspaceModeVisualScript = let
    template = builtins.readFile ./scripts/workspace-mode-visual.sh;
  in builtins.replaceStrings
    [ "@notify_send@" "@makoctl@" "@mkdir@" "@printf@" "@cat@" "@rm@" "@setsid@" "@pkill@" "@id@" "@wshowkeys@" ]
    [ "${pkgs.libnotify}/bin/notify-send" "${pkgs.mako}/bin/makoctl" "${pkgs.coreutils}/bin/mkdir" "${pkgs.coreutils}/bin/printf" "${pkgs.coreutils}/bin/cat" "${pkgs.coreutils}/bin/rm" "${pkgs.util-linux}/bin/setsid" "${pkgs.procps}/bin/pkill" "${pkgs.coreutils}/bin/id" "/run/wrappers/bin/wshowkeys" ]
    template;
  workspaceModeVisualPath = "$HOME/.local/bin/workspace-mode-visual";
  i3pmWorkspaceModeScript = let
    template = builtins.readFile ./scripts/i3pm-workspace-mode.sh;
  in builtins.replaceStrings
    [ "@workspace_visual_bin@" "@socat@" "@jq@" ]
    [ workspaceModeVisualPath "${pkgs.socat}/bin/socat" "${pkgs.jq}/bin/jq" ]
    template;
in
{
  home.file.".local/bin/workspace-mode-visual" = {
    text = workspaceModeVisualScript;
    executable = true;
  };

  home.file.".local/bin/i3pm-workspace-mode" = {
    text = i3pmWorkspaceModeScript;
    executable = true;
  };
}
