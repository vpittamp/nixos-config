# prediction-markets-mcp — read-only MCP server for prediction market prices
# (Kalshi, Polymarket, PredictIt). No API keys required; exposes a single
# `get-prediction-markets` keyword-search tool over stdio.
#
# Upstream ships no package-lock.json, so we vendor a generated one in
# packages/prediction-markets-mcp/package-lock.json (npm install
# --package-lock-only --ignore-scripts) and copy it into the source in
# postPatch.
#
# PATCHES:
#   - build/index.js lacks a shebang, so the `prediction-markets` bin cannot
#     be exec'd directly; prepend `#!/usr/bin/env node`.
#   - the `postinstall` script writes into the user's Claude Desktop config;
#     --ignore-scripts disables it (it must never touch local state).
{ lib, buildNpmPackage, fetchurl }:

buildNpmPackage rec {
  pname = "prediction-markets-mcp";
  version = "1.0.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/prediction-markets-mcp/-/prediction-markets-mcp-${version}.tgz";
    hash = "sha256-zCzvueq2p2NlLYjlZEMZ/xP82xxYSZy36M0HPuuGjrs=";
  };

  postPatch = ''
    cp ${./prediction-markets-mcp/package-lock.json} package-lock.json

    sed -i '1i #!/usr/bin/env node' build/index.js
  '';

  npmDepsHash = "sha256-Q01+SuzeEdxU6VaMwVvY2lJ4wqwC2xKPjG1Ek15DS+g=";

  # Tarball ships prebuilt build/ — upstream has no usable build script here.
  dontNpmBuild = true;

  # postinstall mutates the user's Claude config; never run it.
  npmFlags = [ "--ignore-scripts" ];

  meta = {
    description = "Read-only MCP server for prediction market prices (Kalshi, Polymarket, PredictIt)";
    homepage = "https://github.com/JamesANZ/prediction-market-mcp";
    license = lib.licenses.mit;
    mainProgram = "prediction-markets";
  };
}
