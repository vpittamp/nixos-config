{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.aiAssistants.linkedinMcp;

  chromeBin =
    if cfg.chromePath != null then
      cfg.chromePath
    else
      "${pkgs.google-chrome}/bin/google-chrome-stable";

  launcher = pkgs.writeShellScript "linkedin-mcp-server" ''
    set -euo pipefail

    # Ensure dynamic runtime libraries needed by Patchright's Python bindings (greenlet)
    # are present in LD_LIBRARY_PATH on NixOS.
    export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [ -d "/run/current-system/sw/share/nix-ld/lib" ]; then
      export LD_LIBRARY_PATH="/run/current-system/sw/share/nix-ld/lib:$LD_LIBRARY_PATH"
    fi

    export UV_HTTP_TIMEOUT="''${UV_HTTP_TIMEOUT:-300}"

    chrome_exe="${chromeBin}"
    if [ ! -x "$chrome_exe" ] && command -v google-chrome >/dev/null 2>&1; then
      chrome_exe="$(command -v google-chrome)"
    fi

    exec ${pkgs.uv}/bin/uvx mcp-server-linkedin@latest \
      --transport stdio \
      --chrome-path "$chrome_exe" \
      "$@"
  '';
in
{
  options.modules.aiAssistants.linkedinMcp = {
    enable = mkEnableOption "LinkedIn MCP server (Patchright/browser-driven) for local AI CLIs";

    chromePath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to Google Chrome/Chromium binary. Defaults to pkgs.google-chrome.";
    };

    timeoutSeconds = mkOption {
      type = types.int;
      default = 180;
      description = "Timeout in seconds for LinkedIn MCP tool calls.";
    };

    command = mkOption {
      type = types.package;
      readOnly = true;
      description = "Wrapped launcher script ensuring proper dynamic linker and browser paths on NixOS.";
    };
  };

  config = {
    modules.aiAssistants.linkedinMcp.command = launcher;

    # Expose a convenience wrapper `linkedin-mcp` on PATH so the user can easily run
    # `linkedin-mcp --login`, `linkedin-mcp --status`, `linkedin-mcp --import-from-browser chrome`, etc.
    home.packages = mkIf cfg.enable [
      (pkgs.writeShellScriptBin "linkedin-mcp" ''
        set -euo pipefail
        export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        if [ -d "/run/current-system/sw/share/nix-ld/lib" ]; then
          export LD_LIBRARY_PATH="/run/current-system/sw/share/nix-ld/lib:$LD_LIBRARY_PATH"
        fi
        export UV_HTTP_TIMEOUT="''${UV_HTTP_TIMEOUT:-300}"

        chrome_exe="${chromeBin}"
        if [ ! -x "$chrome_exe" ] && command -v google-chrome >/dev/null 2>&1; then
          chrome_exe="$(command -v google-chrome)"
        fi

        exec ${pkgs.uv}/bin/uvx mcp-server-linkedin@latest \
          --chrome-path "$chrome_exe" \
          "$@"
      '')
    ];
  };
}
