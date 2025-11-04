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
        char)
          echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.char\",\"params\":{\"char\":\"$2\"},\"id\":1}" | \
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
        state)
          # Query workspace mode state from daemon (for status bar polling)
          if [ "$2" = "--json" ]; then
            echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.state\",\"params\":{},\"id\":1}" | \
              ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK 2>/dev/null | \
              ${pkgs.jq}/bin/jq -c '.result // {}'
          else
            echo "{\"jsonrpc\":\"2.0\",\"method\":\"workspace_mode.state\",\"params\":{},\"id\":1}" | \
              ${pkgs.socat}/bin/socat - UNIX-CONNECT:$SOCK 2>/dev/null | \
              ${pkgs.jq}/bin/jq '.result // {}'
          fi
          ;;
        *)
          echo "Usage: $0 {digit <0-9>|char <a-z>|execute|cancel|state [--json]}"
          exit 1
          ;;
      esac
    '')
  ];
}
