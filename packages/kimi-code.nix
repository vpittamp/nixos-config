# Kimi Code CLI — MoonshotAI's coding-agent CLI (the `kimi` command).
#
# Upstream ships two install paths: a `curl | bash` script that drops a
# prebuilt single-file binary (a Node SEA that won't run unpatched on NixOS),
# and the npm package `@moonshot-ai/kimi-code`. We package the npm route: the
# published tarball is a single self-contained ESM bundle (`dist/main.mjs`,
# ~16 MB) with an EMPTY `dependencies` set, so no npmDepsHash / lockfile dance
# is needed — we just run it under a Nix `nodejs`.
#
# Notes:
#   - `node-pty` / `@mariozechner/clipboard` are OPTIONAL native deps. The CLI
#     runs fine without them (verified: `--version`, `--help`); interactive
#     shell/clipboard features degrade gracefully. Add them later if needed.
#   - The upstream `postinstall` script only renames a legacy Python `kimi`
#     shim on the user's PATH; it is irrelevant here and deliberately not run.
#   - Auth is runtime state: `kimi` → `/login` (OAuth or Moonshot API key),
#     or edit ~/.kimi-code/config.toml. Nothing to configure at build time.
#
# Bump: set `version` + `hash` to the npm `dist.integrity` (already SRI-form)
# from https://registry.npmjs.org/@moonshot-ai/kimi-code
{ lib, stdenvNoCC, fetchurl, nodejs_22, makeWrapper }:

let
  pname = "kimi-code";
  version = "0.28.1";
  nodejs = nodejs_22;
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@moonshot-ai/kimi-code/-/kimi-code-${version}.tgz";
    # npm dist.integrity is already an SRI hash — use it verbatim.
    hash = "sha512-1+GqFBdY6N0O6YBqNuclaoUY2jtKVQSKPikDBAMxF633AuB4emuSsMxDyh2KCnINH7f4ceeUdQhIjKunbS6GDA==";
  };

  nativeBuildInputs = [ makeWrapper ];

  # Tarball unpacks to `package/`; stdenv sets sourceRoot there automatically.
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/${pname}"
    cp -r dist dist-web package.json README.md LICENSE "$out/lib/${pname}/"

    makeWrapper ${nodejs}/bin/node "$out/bin/kimi" \
      --add-flags "$out/lib/${pname}/dist/main.mjs" \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Kimi Code CLI — MoonshotAI's next-gen coding agent (kimi command)";
    homepage = "https://github.com/MoonshotAI/kimi-code";
    license = licenses.mit; # MIT — see LICENSE in the npm tarball
    maintainers = [ ];
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "kimi";
  };
}
