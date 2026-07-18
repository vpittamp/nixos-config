# Kimi WebBridge — browser control CLI and MCP server (Moonshot AI)
#
# Drives the user's real Chrome via the Kimi WebBridge Chrome extension:
# the extension auto-connects as a WebSocket client to ws://127.0.0.1:10086/ws,
# served by `kimi-webbridge mcp`; agents then run one-shot commands such as
#   kimi-webbridge navigate '{"url":"https://example.com"}'
#   kimi-webbridge snapshot
#
# Upstream ships no package-lock.json, so we vendor a generated one in
# packages/kimi-webbridge/package-lock.json (npm install --package-lock-only
# --ignore-scripts) and copy it into the source in postPatch.
#
# SECURITY PATCH: upstream `new WebSocketServer({ port, path })` binds all
# interfaces (0.0.0.0). We patch src/mcp.js to bind localhost only — the
# bridge must never be reachable off-machine. --replace-fail makes a future
# upstream change fail loudly instead of silently dropping the patch.
{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "kimi-webbridge";
  version = "0.1.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/kimi-webbridge/-/kimi-webbridge-${version}.tgz";
    hash = "sha256-OBtJu05uMz0qVCRrsLH5GipI7Ybz3nbAUhWHWM77YxQ=";
  };

  postPatch = ''
    cp ${./kimi-webbridge/package-lock.json} package-lock.json

    substituteInPlace src/mcp.js \
      --replace-fail 'port: CONFIG.WS_PORT,' 'port: CONFIG.WS_PORT, host: "127.0.0.1",'
  '';

  npmDepsHash = "sha256-UsxvFITnyXSDjeaVTxuCuj47Qq7lZQBprxh4VNHsvyo=";

  # Pure runtime package — upstream has no build script.
  dontNpmBuild = true;

  meta = {
    description = "Browser control CLI and MCP server for the Kimi WebBridge Chrome extension";
    homepage = "https://www.kimi.com/features/webbridge";
    license = lib.licenses.mit;
    mainProgram = "kimi-webbridge";
  };
}
