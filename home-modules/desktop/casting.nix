# Desktop-level Google Cast: drives Chrome's own cast engine over CDP.
#
# Chrome's built-in Cast is the only maintained Linux sender for the mirroring
# protocol Chromecast-class receivers accept (the Cast V2 CLI ecosystem can
# only fling media URLs — see AGENTS.md), so instead of reimplementing the
# protocol this module automates Chrome itself via the DevTools Protocol's
# Cast domain:
#
#   cast-caster.service  a dedicated-profile Chrome with --remote-debugging-port
#                        (Chrome 136+ refuses debugging on the default profile;
#                        the separate profile also isolates it from the daily
#                        browser — same pattern as google-chrome-codex-devtools)
#                        plus the flags mirroring needs: desktop-audio loopback
#                        (PulseaudioLoopbackForCast is disabled upstream) and
#                        auto-accept of Chrome's own capture dialog. Started on
#                        demand by the CLI, not at login.
#   cast                 Deno CLI speaking the Cast domain: list / start /
#                        extend / stop / toggle / status (scripts/cast.ts).
#   Mod+Shift+d          cast toggle — the TV as a wireless extended display.
#   ;c  (Elephant)       receiver list + mirror/extend/stop menu (walker.nix).
#
# The caster window is parked on workspace 87: it must stay MAPPED (an
# unmapped caster stalls the portal consent chain) but never needs to be seen.
# The one visible interaction per cast is the walker portal chooser picking
# WHICH output to capture — on Wayland nothing can bypass it, and here it is
# the feature: picking the HEADLESS-* entry is what turns a mirror into an
# extended display.
#
# Chrome freshness still matters: the Cast CRL expires 20 weeks after the
# browser build date (configurations/ryzen.nix), so the caster deliberately
# uses the same unpinned google-chrome as everything else.
{ config, lib, pkgs, ... }:

let
  castPort = 9333;

  castCli = pkgs.writeShellScriptBin "cast" ''
    exec ${pkgs.deno}/bin/deno run --no-lock -A --no-check \
      ${./scripts/cast.ts} "$@"
  '';

  casterChrome = pkgs.writeShellScript "cast-caster-chrome" ''
    # --class sets the Wayland app_id, which the sway window rule below parks.
    # Do NOT add --disable-features=MediaRouter: every CDP Cast command would
    # fail with "You must enable the Media Router feature in order to use Cast."
    exec ${pkgs.google-chrome}/bin/google-chrome-stable \
      --user-data-dir="$HOME/.cache/cast-caster" \
      --remote-debugging-port=${toString castPort} \
      --class=google-chrome-cast-caster \
      --app=about:blank \
      --window-size=300,220 \
      --no-first-run \
      --no-default-browser-check \
      --password-store=basic \
      --enable-features=PulseaudioLoopbackForCast \
      --auto-select-desktop-capture-source="Entire screen"
  '';
in
{
  config = lib.mkIf (config.wayland.windowManager.sway.enable) {
    home.packages = [ castCli ];

    wayland.windowManager.sway.config = {
      keybindings = lib.mkOptionDefault {
        "${config.wayland.windowManager.sway.config.modifier}+Shift+d" = "exec cast toggle";
      };

      window.commands = [
        {
          # Workspace 87 sits in the 85-91 gap of the PWA workspace map
          # (shared/pwa-sites.nix; apps use 1-50, PWAs 50+) — re-check that
          # gap if a PWA ever lands on 87. Floating + borderless keeps the
          # caster from flashing a layout if the workspace is ever visited.
          criteria = { app_id = "google-chrome-cast-caster"; };
          command = "floating enable, border none, move container to workspace 87";
        }
      ];
    };

    # On demand (the CLI runs `systemctl --user start cast-caster`); PartOf
    # still tears it down with the graphical session. No Install.WantedBy —
    # an idle Chrome instance per login is not worth faster first-cast.
    systemd.user.services.cast-caster = {
      Unit = {
        Description = "Cast caster: dedicated-profile Chrome exposing CDP Cast (screen mirroring engine)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${casterChrome}";
        Restart = "on-failure";
        RestartSec = "2";
      };
    };
  };
}
