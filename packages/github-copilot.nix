# GitHub Copilot - agent-native desktop app (github/app)
# Tauri (WebKitGTK) app shipped as a self-contained AppImage. The AppImage
# bundles its own webkitgtk-4.1 / gtk-3 / libsoup-3, and its AppRun forces
# GDK_BACKEND=x11 (Tauri crashes on the Wayland backend, tauri-apps/tauri#8541),
# so under Sway it renders through XWayland with X11 WM class "github".
#
# NixOS quirks (keep an eye on these at every version bump):
# - The app's runtime-downloaded "embedded git" is linked against Debian's
#   libcurl-gnutls.so.4 (CURL_GNUTLS_3 symbols), which does not exist in this
#   FHS env, so every GitHub clone fails instantly with "error while loading
#   shared libraries: libcurl-gnutls.so.4" (upstream: github/app#2244, fixed
#   for real in v1.1.5 via host-git fallback). We still force
#   LOCAL_GIT_DIRECTORY to the system profile below so the app always uses the
#   NixOS git instead of the bundled one.
# - The built-in self-updater can never work here: the app lives in the
#   read-only /nix/store, so applying a staged update fails with
#   "Invalid cross-device link", and the app downloads ~485MB and exits on
#   every launch once a newer release exists. Bump this package instead.
{ lib, stdenv, fetchurl, appimageTools, bash }:

let
  pname = "github-copilot";
  version = "1.1.5";

  # Select architecture-specific source
  src = fetchurl (
    if stdenv.isx86_64 then {
      url = "https://github.com/github/app/releases/download/v${version}/GitHub-Copilot-linux-x64.AppImage";
      sha256 = "sha256-rw3s0q8w4t1GlYHTdoj2P+clzRw8sI3e64SK6OFDDv8=";
    } else if stdenv.isAarch64 then {
      url = "https://github.com/github/app/releases/download/v${version}/GitHub-Copilot-linux-arm64.AppImage";
      sha256 = "sha256-zmEs1LaePn71ym/t0MFd486HYvGZ8Todtehms0RyC1g=";
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

      # Route the app at the NixOS git (see header comment). The app appends
      # bin/git to LOCAL_GIT_DIRECTORY, so point it at the system profile.
      mv "$out/bin/${pname}" "$out/bin/.${pname}-unwrapped"
      cat > "$out/bin/${pname}" <<'EOF'
      #!${bash}/bin/bash
      # Default to the NixOS system git unless the user overrides it; the
      # app's bundled git cannot resolve libcurl-gnutls.so.4 on NixOS.
      export LOCAL_GIT_DIRECTORY="''${LOCAL_GIT_DIRECTORY:-/run/current-system/sw}"
      exec "$(dirname "$0")/.${pname}-unwrapped" "$@"
      EOF
      chmod +x "$out/bin/${pname}"
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
