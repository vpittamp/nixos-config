# VibeTyper - AI Voice Typing for Linux
# https://vibetyper.com
# Voice-to-text with AI that rewrites, replies, and refines
{ lib, stdenv, fetchurl, appimageTools, makeWrapper, xdotool, libfuse2 }:

let
  pname = "vibetyper";
  version = "1.0.7";

  src = fetchurl {
    url = "https://cdn.vibetyper.com/releases/linux/VibeTyper.AppImage";
    sha256 = "1p0qgjbiczgbvcnqsv1658fidr902h33k8l5lzw6imi2n2qb7y7z";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
if stdenv.isLinux then
  appimageTools.wrapType2 {
    inherit pname version src;

    extraPkgs = pkgs: with pkgs; [
      # X11 support (fully supported)
      xdotool
      xorg.libX11
      xorg.libXtst
      xorg.libXi

      # Wayland support (experimental)
      wl-clipboard

      # Audio for speech recognition
      pulseaudio
      alsa-lib

      # Common dependencies
      glib
      gtk3
      nss
      nspr
      dbus
      libdrm
      mesa
      expat
      libxkbcommon
      at-spi2-core
      cups
    ];

    extraInstallCommands = ''
      # Install desktop file from AppImage contents if available
      if [ -f ${appimageContents}/vibetyper.desktop ]; then
        install -m 444 -D ${appimageContents}/vibetyper.desktop \
          $out/share/applications/vibetyper.desktop
        substituteInPlace $out/share/applications/vibetyper.desktop \
          --replace 'Exec=AppRun' "Exec=$out/bin/${pname}" \
          --replace 'Exec=vibetyper' "Exec=$out/bin/${pname}"
      else
        # Create a desktop entry if not found in AppImage
        mkdir -p $out/share/applications
        cat > $out/share/applications/vibetyper.desktop <<EOF
[Desktop Entry]
Name=VibeTyper
Comment=AI Voice Typing - Write 3x faster with voice-to-text and AI
Exec=$out/bin/${pname}
Icon=vibetyper
Terminal=false
Type=Application
Categories=Utility;Accessibility;
Keywords=voice;typing;speech;dictation;ai;
EOF
      fi

      # Install icon if available
      for size in 16 24 32 48 64 128 256 512; do
        if [ -f ${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/vibetyper.png ]; then
          install -m 444 -D ${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/vibetyper.png \
            $out/share/icons/hicolor/''${size}x''${size}/apps/vibetyper.png
        fi
      done

      # Fallback: check common icon locations
      if [ -f ${appimageContents}/vibetyper.png ]; then
        install -m 444 -D ${appimageContents}/vibetyper.png \
          $out/share/pixmaps/vibetyper.png
      fi
    '';

    meta = with lib; {
      description = "AI Voice Typing - Write 3x faster with voice-to-text and AI";
      homepage = "https://vibetyper.com";
      license = licenses.unfree;
      maintainers = [ ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "vibetyper";
    };
  }
else
  throw "VibeTyper is only available on Linux (x86_64)"
