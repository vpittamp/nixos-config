{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.aiAssistants.onepasswordMcp;
in
{
  options.modules.aiAssistants.onepasswordMcp = {
    enable = mkEnableOption "1Password Environments MCP server (official, local stdio via the desktop app) for local AI CLIs";

    package = mkOption {
      type = types.package;
      default = pkgs._1password-gui;
      defaultText = literalExpression "pkgs._1password-gui";
      description = "1Password desktop package shipping share/1password/onepassword-mcp.";
    };

    # The 8-tool surface read live from the server (1Password 8.12.22, rmcp
    # 1.1.0). Environments-scoped by design: the server never returns secret
    # values to the client. Consumers that require explicit tool enumeration
    # (antigravity) read this list; others accept every tool.
    toolNames = mkOption {
      type = types.listOf types.str;
      default = [
        "append_variables"
        "authenticate"
        "create_environment"
        "create_local_env_file"
        "list_environments"
        "list_local_env_files"
        "list_variables"
        "rename_environment"
      ];
      description = "Tool names served by the 1Password MCP server.";
    };

    command = mkOption {
      type = types.str;
      readOnly = true;
      description = ''
        Patched onepassword-mcp binary path for stdio MCP clients. 1Password
        ships the server as an unpatched generic-Linux ELF inside the desktop
        app package; the derivation below gives it a NixOS interpreter and a
        glibc+libgcc rpath (the binary needs nothing else). Runtime requires
        the desktop app running with Settings → Labs → "Enable local MCP
        server" on; each client/tool combination is authorized once via an
        interactive prompt in the app, remembered until 1Password locks.
      '';
    };
  };

  config.modules.aiAssistants.onepasswordMcp.command =
    let
      mcp = pkgs.runCommand "onepassword-mcp"
        {
          nativeBuildInputs = [ pkgs.patchelf ];
        }
        ''
          install -Dm555 ${cfg.package}/share/1password/onepassword-mcp $out/bin/onepassword-mcp
          patchelf \
            --set-interpreter "${lib.getLib pkgs.glibc}/lib/ld-linux-x86-64.so.2" \
            --set-rpath "${lib.getLib pkgs.libgcc}/lib:${lib.getLib pkgs.glibc}/lib" \
            $out/bin/onepassword-mcp
        '';
    in
    "${mcp}/bin/onepassword-mcp";
}
