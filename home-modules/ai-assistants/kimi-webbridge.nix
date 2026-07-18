{ config, pkgs, lib, ... }:

# Kimi WebBridge (Moonshot AI) lets local AI agents drive the user's real
# Chrome via a force-installed Chrome extension. The extension auto-connects
# as a WebSocket client to ws://127.0.0.1:10086/ws served by the
# `kimi-webbridge` Node daemon packaged at packages/kimi-webbridge.nix.
#
# Deliberate design: exactly ONE persistent bridge runs as this systemd user
# service (`kimi-webbridge mcp`). Its stdio MCP transport is intentionally
# unused — stdin is held open with `tail -f /dev/null` so the stdio transport
# never sees EOF and exits. All agents drive the browser via one-shot CLI
# calls (`kimi-webbridge <action> '<json-args>'`, e.g. navigate/snapshot/
# click/screenshot/list_tabs), which connect to the running bridge as
# transient WebSocket clients. No per-agent MCP server is registered because
# a second `mcp` process exits(1) on EADDRINUSE for port 10086.
#
# The companion Chrome extension (Web Store ID
# fldmhceldgbpfpkbgopacenieobmligc) is force-installed into all Chrome
# profiles by modules/desktop/chrome-kimi-webbridge.nix (system side).

let
  shared = import ./browser-mcp-shared.nix { inherit config lib pkgs; };

  kimi-webbridge = pkgs.callPackage ../../packages/kimi-webbridge.nix { };

  # Hold stdin open forever so `kimi-webbridge mcp` never sees EOF on its
  # (unused) stdio MCP transport under systemd; the WS bridge on
  # 127.0.0.1:10086/ws is the useful part.
  kimiWebbridgeBridge = pkgs.writeShellScriptBin "kimi-webbridge-bridge" ''
    ${pkgs.coreutils}/bin/tail -f /dev/null | ${kimi-webbridge}/bin/kimi-webbridge mcp
  '';
in
{
  config = lib.mkIf shared.enableBrowserMcpServers {
    home.packages = [ kimi-webbridge ];

    systemd.user.services.kimi-webbridge = {
      Unit = {
        Description = "Kimi WebBridge local browser bridge (WebSocket 127.0.0.1:10086)";
        After = [ "sway-session.target" ];
        BindsTo = [ "sway-session.target" ];
        PartOf = [ "sway-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${kimiWebbridgeBridge}/bin/kimi-webbridge-bridge";
        Restart = "on-failure";
        RestartSec = "5s";
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}
