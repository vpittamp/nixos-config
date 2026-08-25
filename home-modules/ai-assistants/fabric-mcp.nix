{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.aiAssistants.fabricMcp;
  proxyScript = pkgs.writeText "fabric-mcp-relay.js" ''
    const readline = require("readline");
    const https = require("https");
    const { execSync } = require("child_process");

    function getToken() {
      if (process.env.FABRIC_TOKEN) return process.env.FABRIC_TOKEN;
      if (process.env.AZURE_FABRIC_TOKEN) return process.env.AZURE_FABRIC_TOKEN;
      if (process.env.AZURE_TOKEN) return process.env.AZURE_TOKEN;

      const opBin = "/run/wrappers/bin/op";
      const opCmd = require("fs").existsSync(opBin) ? opBin : "${pkgs._1password-cli}/bin/op";
      const tokenRef = process.env.FABRIC_TOKEN_OP_REF || "${cfg.tokenReference}";
      try {
        const op = execSync(`"''${opCmd}" read "''${tokenRef}" 2>/dev/null`).toString().trim();
        if (op) return op;
      } catch (e) {}

      try {
        const az = execSync("az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv 2>/dev/null").toString().trim();
        if (az) return az;
      } catch (e) {}

      return null;
    }

    const token = getToken();
    if (!token) {
      console.error("FABRIC_TOKEN or AZURE_FABRIC_TOKEN is required for Microsoft Fabric MCP access.");
      console.error("Store an Entra ID token in 1Password at ${cfg.tokenReference}, or run 'az login', or set FABRIC_TOKEN.");
      process.exit(64);
    }

    const endpointUrl = process.env.FABRIC_MCP_URL || "${cfg.url}";
    const endpoint = new URL(endpointUrl);

    async function post(jsonObj) {
      const data = JSON.stringify(jsonObj);
      return new Promise((resolve, reject) => {
        const req = https.request({
          hostname: endpoint.hostname,
          port: endpoint.port || (endpoint.protocol === "https:" ? 443 : 80),
          path: endpoint.pathname + endpoint.search,
          method: "POST",
          headers: {
            "Authorization": `Bearer ''${token}`,
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(data)
          }
        }, res => {
          let body = "";
          res.on("data", chunk => body += chunk);
          res.on("end", () => resolve(body));
        });
        req.on("error", reject);
        req.write(data);
        req.end();
      });
    }

    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: false });

    rl.on("line", async line => {
      const trimmed = line.trim();
      if (!trimmed) return;
      try {
        const msg = JSON.parse(trimmed);
        if (msg.id === undefined) {
          // Notification
          return;
        }
        const resp = await post(msg);
        process.stdout.write(resp.trim() + "\n");
      } catch (err) {
        console.error("Fabric MCP Relay error:", err.message);
      }
    });
  '';

  proxyCommand = pkgs.writeShellScript "fabric-mcp-proxy" ''
    set -euo pipefail

    # Do not let desktop/1Password session credentials survive into Node
    unset DBUS_SESSION_BUS_ADDRESS DISPLAY OP_BIOMETRIC_UNLOCK_ENABLED
    unset OP_SERVICE_ACCOUNT_TOKEN WAYLAND_DISPLAY XDG_RUNTIME_DIR

    exec "${pkgs.nodejs}/bin/node" "${proxyScript}"
  '';
in
{
  options.modules.aiAssistants.fabricMcp = {
    enable = mkEnableOption "Microsoft Fabric Core MCP server (Streamable HTTP bridge) for local AI CLIs";

    url = mkOption {
      type = types.str;
      default = "https://api.fabric.microsoft.com/v1/mcp/core";
      description = "MCP Streamable HTTP URL for Microsoft Fabric Core MCP server.";
    };

    tokenReference = mkOption {
      type = types.str;
      default = "op://CLI/Fabric Token/credential";
      description = ''
        1Password secret reference read at MCP proxy startup when FABRIC_TOKEN is
        unset. The reference may be overridden with FABRIC_TOKEN_OP_REF; the
        resolved token is never written into the Nix store or generated config.
      '';
    };

    proxyCommand = mkOption {
      type = types.package;
      readOnly = true;
      description = ''
        Shared stdio-to-HTTP proxy that authenticates with
        FABRIC_TOKEN / AZURE_FABRIC_TOKEN, 1Password, or az CLI to talk to
        Microsoft Fabric's Streamable HTTP /v1/mcp/core endpoint.
      '';
    };
  };

  config.modules.aiAssistants.fabricMcp.proxyCommand = proxyCommand;
}
