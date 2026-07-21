# GitHub Copilot - agent-native desktop app (github/app)
# Tauri (WebKitGTK) app shipped as a self-contained AppImage. The AppImage
# bundles its own webkitgtk-4.1 / gtk-3 / libsoup-3, and its AppRun forces
# GDK_BACKEND=x11 (Tauri crashes on the Wayland backend, tauri-apps/tauri#8541),
# so under Sway it renders through XWayland with X11 WM class "github".
{ lib, stdenv, fetchurl, appimageTools }:

let
  pname = "github-copilot";
  version = "1.0.25";

  # Select architecture-specific source
  src = fetchurl (
    if stdenv.isx86_64 then {
      url = "https://github.com/github/app/releases/download/v${version}/GitHub-Copilot-linux-x64.AppImage";
      sha256 = "011vqlsavk55rhrm3awz4hjbiqasghi2csasmmxq8987lagg5f17";
    } else if stdenv.isAarch64 then {
      url = "https://github.com/github/app/releases/download/v${version}/GitHub-Copilot-linux-arm64.AppImage";
      sha256 = "08zryw5b6if48k8hsi116ddvvrphwrsnmax4gdfisxsw2wkfdlw8";
    } else throw "Unsupported platform for github-copilot"
  );

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
if stdenv.isLinux then
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      # Install desktop file from AppImage contents, routing the launcher at the
      # wrapped binary (the internal Exec is "github"). Keep StartupWMClass and
      # the github-app:// scheme handlers so OAuth deep-links resolve here.
      install -m 444 -D "${appimageContents}/GitHub Copilot.desktop" \
        "$out/share/applications/${pname}.desktop"
      substituteInPlace "$out/share/applications/${pname}.desktop" \
        --replace-quiet 'Exec=github %u' "Exec=$out/bin/${pname} %u" \
        --replace-quiet 'Exec=github' "Exec=$out/bin/${pname}" \
        --replace-quiet 'Icon=github' "Icon=${pname}"

      # Install icon (hicolor) so menus/launchers resolve Icon=github-copilot.
      install -m 444 -D "${appimageContents}/GitHub Copilot.png" \
        "$out/share/icons/hicolor/512x512/apps/${pname}.png"
    '';

    meta = with lib; {
      description = "GitHub Copilot — agent-native desktop app for running and landing software work across GitHub repositories";
      homepage = "https://github.com/github/app";
      license = licenses.unfree;
      maintainers = with maintainers; [ ];
      platforms = [ "x86_64-linux" "aarch64-linux" ];
      mainProgram = pname;
    };
  }
else
  throw "github-copilot is only available on Linux (x86_64 and aarch64)"
