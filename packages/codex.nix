# OpenAI Codex CLI — AI coding agent for terminal workflows.
# Shipped by OpenAI as a self-contained release package (native binary + code-mode host).
# Version 0.159.2 with GPT-6.1 Sol support.
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
  version = "0.159.2";

  platformMap = {
    "x86_64-linux" = "x86_64-unknown-linux-musl";
    "aarch64-linux" = "aarch64-unknown-linux-musl";
  };

  platform = platformMap.${stdenv.hostPlatform.system}
    or (throw "Unsupported platform for codex: ${stdenv.hostPlatform.system}");

  nativeHashes = {
    "x86_64-unknown-linux-musl" = "0svs6fhzig9rqvkl7p3nmmgx0k1j247g3hny82r7hi5r2fkjjbcy";
    "aarch64-unknown-linux-musl" = "0brindphxrajmcgmy7wbwz1p82qdki9j7yf748z7xpyacfj29985";
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
