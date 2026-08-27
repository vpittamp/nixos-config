# Kimi Code CLI — MoonshotAI's coding-agent CLI (the `kimi` command).
#
# Upstream ships two install paths: a `curl | bash` script that drops a
# prebuilt single-file binary (a Node SEA that won't run unpatched on NixOS),
# and the npm package `@moonshot-ai/kimi-code`. We package the npm route: the
# published tarball is a single self-contained ESM bundle (`dist/main.mjs`,
# ~16 MB).
#
# Notes:
#   - Through 0.38.0 that bundle had an EMPTY `dependencies` set and could be
#     run straight off a Nix `nodejs`. 0.39.0 added two REAL runtime deps —
#     `ws` and `qrcode` — as static top-level imports, so Node resolves them at
#     load time and the CLI will not start without a populated node_modules.
#     Hence buildNpmPackage plus a vendored lockfile, the same shape as
#     packages/kimi-webbridge.nix.
#   - `devDependencies` are stripped before `npm ci`. Several of them
#     (`@moonshot-ai/acp-adapter`, `@moonshot-ai/agent-core-v2`, …) are not
#     published to the public registry and 404 — they are upstream's own build
#     inputs, already inlined into the shipped bundle, and resolving them is
#     both impossible and unnecessary for a prebuilt dist.
#   - `node-pty` / `@mariozechner/clipboard` are OPTIONAL native deps, stripped
#     for the same reason as before: the CLI runs fine without them (verified:
#     `--version`, `--help`) and interactive shell/clipboard features degrade
#     gracefully.
#   - The upstream `postinstall` script only renames a legacy Python `kimi`
#     shim on the user's PATH; it is irrelevant here and deliberately not run.
#   - Auth is runtime state: `kimi` → `/login` (OAuth or Moonshot API key),
#     or edit ~/.kimi-code/config.toml. Nothing to configure at build time.
#
# Bump: set `version` + `hash` to the npm `dist.integrity` (already SRI-form)
# from https://registry.npmjs.org/@moonshot-ai/kimi-code, then regenerate
# ./kimi-code/package-lock.json from the new tarball's package.json with
# devDependencies and optionalDependencies removed, and refresh npmDepsHash.
{ lib, buildNpmPackage, fetchurl, nodejs_22, makeWrapper, jq }:

let
  pname = "kimi-code";
  version = "0.39.0";
  nodejs = nodejs_22;
in
buildNpmPackage {
  inherit pname version nodejs;

  src = fetchurl {
    url = "https://registry.npmjs.org/@moonshot-ai/kimi-code/-/kimi-code-${version}.tgz";
    # npm dist.integrity is already an SRI hash — use it verbatim.
    hash = "sha512-T+8IwTc3etpNQhJXbB6wNppLvC4URWBR0SycDM2mb2ObXmqwn8xbOKzaItQQ63ZxjyV6zSHQDaogw0BjlHmtvA==";
  };

  postPatch = ''
    cp ${./kimi-code/package-lock.json} package-lock.json
    ${jq}/bin/jq 'del(.devDependencies, .optionalDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
  '';

  npmDepsHash = "sha256-yerS1+K3MEx6+wcLBE1nNaAUnePkroJP17OzZ5yZqUw=";

  nativeBuildInputs = [ makeWrapper ];

  # dist/ is prebuilt and shipped in the tarball; upstream's `build` script
  # needs the unpublished devDependencies above.
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/${pname}"
    cp -r dist dist-web package.json README.md LICENSE "$out/lib/${pname}/"
    cp -r node_modules "$out/lib/${pname}/node_modules"

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
