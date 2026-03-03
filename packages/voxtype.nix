# Voxtype - Push-to-talk speech-to-text for Wayland
# https://github.com/peteonrails/voxtype
# Rust-based, GPU-accelerated (Vulkan), injects text via wtype/dotool/clipboard
# Designed for Wayland compositors - works in tmux/CLI sessions
{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper,
  vulkan-loader, alsa-lib, pipewire,
  wtype, dotool, wl-clipboard }:

let
  pname = "voxtype";
  version = "0.6.3";
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/peteonrails/voxtype/releases/download/v${version}/voxtype-${version}-linux-x86_64-vulkan";
    sha256 = "sha256-WvRpADps5OiiRxZ1dYdzDOwEMeaiz18J/HhkpUJBzEk=";
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

    # GPU-accelerated inference
    vulkan-loader

    # Audio capture
    alsa-lib
    pipewire
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/voxtype

    # Wrap with runtime deps for text injection chain:
    # 1. wtype (native Wayland text input)
    # 2. dotool (fallback input automation)
    # 3. wl-clipboard (clipboard paste fallback)
    wrapProgram $out/bin/voxtype \
      --prefix PATH : ${lib.makeBinPath [ wtype dotool wl-clipboard ]}

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
