{ pkgs, ... }:

{
  # Python with required packages for both modes (one-shot and streaming)
  # pyxdg required for XDG icon theme lookup (resolves icon names like "firefox" to paths)
  pythonForBackend = pkgs.python3.withPackages (ps: [ ps.i3ipc ps.pyxdg ps.pydantic ]);

  # Clipboard sync script - fully parameterized with nix store paths
  clipboardSyncScript = pkgs.writeShellScript "clipboard-sync" ''
    #!/usr/bin/env bash
    set -euo pipefail

    tmp=$(${pkgs.coreutils}/bin/mktemp -t clipboard-sync-XXXXXX)
    cleanup() {
      ${pkgs.coreutils}/bin/rm -f "$tmp"
    }
    trap cleanup EXIT

    ${pkgs.coreutils}/bin/cat >"$tmp"

    # Exit cleanly on empty input
    if [[ ! -s "$tmp" ]]; then
      exit 0
    fi

    # Copy to Wayland clipboard
    if [[ -n "''${WAYLAND_DISPLAY:-}" ]]; then
      ${pkgs.wl-clipboard}/bin/wl-copy <"$tmp"
      ${pkgs.wl-clipboard}/bin/wl-copy --primary <"$tmp"
    fi

    # Copy to X11 clipboard
    if command -v ${pkgs.xclip}/bin/xclip >/dev/null 2>&1; then
      ${pkgs.xclip}/bin/xclip -selection clipboard <"$tmp"
      ${pkgs.xclip}/bin/xclip -selection primary <"$tmp"
    fi
  '';
}
