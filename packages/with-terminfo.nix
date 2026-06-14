# Wrap a terminal-UI binary so its runtime helper `infocmp` (from ncurses) is
# always available on PATH, independent of the PATH it happens to be launched
# with.
#
# Why this is needed: gocui-based TUIs (lazygit, lazydocker) and tcell-based
# ones (k9s) shell out to `infocmp` while initialising the terminal. When these
# apps are launched from a systemd/daemon context (e.g. the i3pm launcher, which
# spawns them via `ghostty -e <app>` under the systemd --user manager) they
# inherit a stripped-down PATH that contains only systemd's own bin dir. Without
# `infocmp` they crash on startup with:
#   exec: "infocmp": executable file not found in $PATH
# Forwarding PATH at the launcher layer helps, but wrapping the binary makes the
# dependency explicit and guaranteed regardless of who launches it.
#
# Usage:
#   withTerminfo = import ../packages/with-terminfo.nix { inherit pkgs; };
#   ... (withTerminfo pkgs.lazydocker "lazydocker")
{ pkgs, lib ? pkgs.lib }:
pkg: binName:
pkgs.symlinkJoin {
  name = "${binName}-with-terminfo";
  paths = [ pkg ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/${binName}" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.ncurses ]}
  '';
}
