# OpenAI Codex CLI — AI coding agent for terminal workflows.
# Shipped by OpenAI as a self-contained release package (native binary + code-mode host).
# Version 0.163.0 with GPT-6.1 Sol support.
{ lib
, stdenv
, fetchurl
, makeWrapper
, installShellFiles
, bubblewrap
, openssl
, libcap
, libz
, gnutar
, gzip
}:

let
  version = "0.163.0";

  platformMap = {
    "x86_64-linux" = "x86_64-unknown-linux-musl";
    "aarch64-linux" = "aarch64-unknown-linux-musl";
  };

  platform = platformMap.${stdenv.hostPlatform.system}
    or (throw "Unsupported platform for codex: ${stdenv.hostPlatform.system}");

  nativeHashes = {
    "x86_64-unknown-linux-musl" = "10i128i1fzqbhfb6xg16m28h06qjp62zrxs0wl6ynq85pz34c9jq";
    "aarch64-unknown-linux-musl" = "1yr7b627bjd0m21c6wnbin4b6j6yhmn2v443g63q9qfk34nwz3lx";
  };

  nativeBinary = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${platform}.tar.gz";
    sha256 = nativeHashes.${platform};
  };

  linuxRuntimePath = lib.makeBinPath [ bubblewrap ];
in
stdenv.mkDerivation rec {
  pname = "codex";
  inherit version;

  dontUnpack = true;
  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = [ gnutar gzip makeWrapper installShellFiles ];
  buildInputs = [ openssl libcap libz ];

  buildPhase = ''
    runHook preBuild
    mkdir -p build
    tar -xzf ${nativeBinary} -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib

    # Codex discovers its package from bin/ and the adjacent manifest.
    cp -r build $out/lib/codex
    ln -s ../lib/codex/bin/codex-code-mode-host $out/bin/codex-code-mode-host
    makeWrapper "$out/lib/codex/bin/codex" "$out/bin/codex" \
      --run 'export CODEX_EXECUTABLE_PATH="$HOME/.local/bin/codex"' \
      --set DISABLE_AUTOUPDATER 1 \
      --prefix PATH : "${linuxRuntimePath}"
    runHook postInstall
  '';

  postInstall = ''
    installShellCompletion --cmd codex \
      --bash <("$out/bin/codex" completion bash) \
      --fish <("$out/bin/codex" completion fish) \
      --zsh <("$out/bin/codex" completion zsh)
  '';

  meta = with lib; {
    description = "OpenAI Codex CLI (Native Binary) - AI coding assistant in your terminal";
    homepage = "https://github.com/openai/codex";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "codex";
  };
}
