# Temporary wrapper for workspace mode IPC calls
# TODO: Replace with TypeScript CLI integration (add workspace-mode subcommand to i3pm/src/main.ts)
{ pkgs, ... }:

{
  home.packages = [
    (pkgs.writeShellScriptBin "i3pm-workspace-mode" ''
      # Wrapper for workspace mode daemon IPC calls
      SOCK="/run/i3-project-daemon/ipc.sock"

      case "$1" in
        digit)
          echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.digit\",\"params\":{\"digit\":\"$2\"},\"id\":1}" | \
            ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK > /dev/null 2>&1
          ;;
        execute)
          echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.execute\",\"params\":{},\"id\":1}" | \
            ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK > /dev/null 2>&1
          ;;
        cancel)
          echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.cancel\",\"params\":{},\"id\":1}" | \
            ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK > /dev/null 2>&1
          ;;
        *)
          echo "Usage: $0 {digit <0-9>|execute|cancel}"
          exit 1
          ;;
      esac
    '')
  ];
}
