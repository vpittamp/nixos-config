# Voxtype - Push-to-talk speech-to-text for Wayland
# https://github.com/peteonrails/voxtype
# Rust-based speech-to-text, injects text via wtype/dotool/clipboard
# Designed for Wayland compositors - works in tmux/CLI sessions
{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper,
  vulkan-loader, alsa-lib, pipewire,
  wtype, dotool, wl-clipboard,
  variant ? "vulkan",
  hash ? "sha256-ZGJtB/Oq4oJd24LqZoePcIyKggo/0+znbZn/mEd/Ey0=" }:

let
  pname = "voxtype";
  version = "0.7.5";
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/peteonrails/voxtype/releases/download/v${version}/voxtype-${version}-linux-x86_64-${variant}";
    sha256 = hash;
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
