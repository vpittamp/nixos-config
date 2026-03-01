# Handy - Offline speech-to-text application
# https://github.com/cjpais/Handy
# A free, open source, extensible speech-to-text app that works completely offline.
# Uses whisper.cpp for local transcription. Tauri v2 desktop app.
{ lib, stdenv, fetchurl, appimageTools, wtype }:

let
  pname = "handy";
  version = "0.7.9";

  src = fetchurl {
    url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_amd64.AppImage";
    sha256 = "0gig8l0cmhf9ikd73xi3bz0lbfwjydi2fqv8p9gi5wwyk539na49";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
if stdenv.isLinux then
  appimageTools.wrapType2 {
    inherit pname version src;

    extraPkgs = pkgs: with pkgs; [
      # Wayland text input (Sway/wlroots)
      wtype
      wl-clipboard

      # Audio for speech recognition
      pulseaudio
      alsa-lib
      pipewire

      # WebKit/GTK (Tauri v2 runtime)
      webkitgtk_4_1
      gtk3
      glib
      glib-networking
      libsoup_3
      dbus

      # Graphics
      libdrm
      mesa
      libxkbcommon

      # Common dependencies
      openssl
      at-spi2-core
    ];

    extraInstallCommands = ''
      # Install desktop file from AppImage contents
      if [ -f ${appimageContents}/handy.desktop ]; then
        install -m 444 -D ${appimageContents}/handy.desktop \
          $out/share/applications/handy.desktop
        substituteInPlace $out/share/applications/handy.desktop \
          --replace 'Exec=AppRun' "Exec=$out/bin/${pname}" \
          --replace 'Exec=handy' "Exec=$out/bin/${pname}"
      else
        mkdir -p $out/share/applications
        cat > $out/share/applications/handy.desktop <<EOF
[Desktop Entry]
Name=Handy
Comment=Offline speech-to-text application
Exec=$out/bin/${pname}
Icon=handy
Terminal=false
Type=Application
Categories=Utility;Accessibility;Audio;
Keywords=speech;voice;transcription;dictation;whisper;offline;
EOF
      fi

      # Install icons if available
      for size in 16 24 32 48 64 128 256 512; do
        if [ -f ${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/handy.png ]; then
          install -m 444 -D ${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/handy.png \
            $out/share/icons/hicolor/''${size}x''${size}/apps/handy.png
        fi
      done

      if [ -f ${appimageContents}/handy.png ]; then
        install -m 444 -D ${appimageContents}/handy.png \
          $out/share/pixmaps/handy.png
      fi
    '';

    meta = with lib; {
      description = "Free, open source, offline speech-to-text application";
      homepage = "https://github.com/cjpais/Handy";
      license = licenses.mit;
      maintainers = [ ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "handy";
    };
  }
else
  throw "Handy is only available on Linux (x86_64)"
