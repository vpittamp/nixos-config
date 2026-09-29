# Voxtype - Push-to-talk speech-to-text for Wayland
# https://github.com/peteonrails/voxtype
# Rust-based speech-to-text, injects text via wtype/dotool/clipboard
# Designed for Wayland compositors - works in tmux/CLI sessions
{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper,
  vulkan-loader, alsa-lib, pipewire,
  wtype, dotool, wl-clipboard,
  # Which upstream build to install. `onnx-avx2` is the default because it is
  # the only variant that carries the non-Whisper engines (Parakeet, Moonshine,
  # SenseVoice, ...), and Whisper is the reason dictation was unusably slow:
  # it pads every clip to a fixed 30-second window, so a 3.5s command cost the
  # same as a 30s one. Measured on the Surface (i5-8250U, UHD 620):
  #
  #   whisper large-v3-turbo, Vulkan   35.4s for 3.5s of audio, 33.3s for 11s
  #   whisper large-v3-turbo, AVX2 CPU 43.8s for 3.5s
  #   parakeet-tdt-0.6b-v3-int8, ONNX   0.48s for 3.5s, 1.42s for 11s
  #
  # The Vulkan build did beat plain CPU for Whisper, so the iGPU was doing real
  # work — the model was simply the wrong shape for short utterances. Parakeet
  # also scores better on the Open ASR Leaderboard (6.34% WER vs ~7.4%) and
  # its int8 weights are 640 MB against Whisper's 1.6 GB, which matters on a
  # 7.7 GB machine.
  variant ? "onnx-avx2",
  # Null means "use the known hash for this variant"; pass one explicitly to
  # build a variant this file does not list. It cannot default to
  # `variantHashes.${variant}` directly — an argument default cannot see the
  # `let` block below it.
  hash ? null }:

let
  pname = "voxtype";
  version = "0.7.5";

  # From the release's SHA256SUMS.txt. A host with an NVIDIA card can pass
  # variant = "onnx-cuda-12"; note those builds also need their separate
  # libonnxruntime_providers_*.so assets, which this derivation does not fetch.
  variantHashes = {
    "onnx-avx2" = "sha256-oOjxzU+kIpiebAG+J/NzK4dP8cCzMircdWxqWrlMZZQ=";
    "avx2" = "sha256-GK4FENDJZGifjJtxGcC5pFVpmF6Cl33E8e9Ndv3diHw=";
    "vulkan" = "sha256-ZGJtB/Oq4oJd24LqZoePcIyKggo/0+znbZn/mEd/Ey0=";
  };

  srcHash =
    if hash != null then hash
    else variantHashes.${variant} or (throw
      "voxtype: no known hash for variant ${variant}; pass `hash` explicitly");
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/peteonrails/voxtype/releases/download/v${version}/voxtype-${version}-linux-x86_64-${variant}";
    sha256 = srcHash;
  };

  # Binary download, no unpack needed
  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    # C++ runtime (libstdc++.so.6, libgcc_s.so.1)
    stdenv.cc.cc.lib

    # GPU-accelerated Whisper inference.
    vulkan-loader

    # Audio capture
    alsa-lib
    pipewire
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/voxtype

    # Wrap with runtime deps for text injection chain. The --run hook prepends
    # a runtime HOME-relative path so the Home Manager dictation module can
    # install a tiny wtype tap that persists dictated text before delegating to
    # the real wtype.
    wrapProgram $out/bin/voxtype \
      --prefix PATH : ${lib.makeBinPath [ wtype dotool wl-clipboard ]} \
      --run 'if [ -n "''${HOME:-}" ] && [ -d "$HOME/.local/share/voxtype/bin" ]; then export PATH="$HOME/.local/share/voxtype/bin:$PATH"; fi'

    runHook postInstall
  '';

  meta = with lib; {
    description = "Push-to-talk speech-to-text for Wayland compositors";
    homepage = "https://github.com/peteonrails/voxtype";
    license = licenses.mit;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "voxtype";
  };
}
