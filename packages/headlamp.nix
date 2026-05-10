# Headlamp - Kubernetes Web UI Dashboard
{ lib, stdenv, fetchurl, appimageTools, makeWrapper, electron }:

let
  pname = "headlamp";
  version = "0.42.0";

  # Select architecture-specific source
  src = fetchurl (
    if stdenv.isx86_64 then {
      url = "https://github.com/kubernetes-sigs/headlamp/releases/download/v${version}/Headlamp-${version}-linux-x64.AppImage";
      sha256 = "083zg195ayvckya6nphw07d574a61ad5lymnk4d8jbswkq8przrk";
    } else if stdenv.isAarch64 then {
      url = "https://github.com/kubernetes-sigs/headlamp/releases/download/v${version}/Headlamp-${version}-linux-arm64.AppImage";
      sha256 = "0ly3kq0lk8ncqg97n8ms0qwfa0g68278rzlb6mnxgziq2w9y8q63";
    } else throw "Unsupported platform for headlamp"
  );

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
if stdenv.isLinux then
  appimageTools.wrapType2 {
    inherit pname version src;
    
    extraInstallCommands = ''
      # Install desktop file and icon from AppImage contents
      install -m 444 -D ${appimageContents}/headlamp.desktop \
        $out/share/applications/headlamp.desktop
      substituteInPlace $out/share/applications/headlamp.desktop \
        --replace 'Exec=AppRun' "Exec=$out/bin/${pname} --disable-gpu" \
        --replace 'Exec=headlamp' "Exec=$out/bin/${pname} --disable-gpu"
      
      # Install icon
      install -m 444 -D ${appimageContents}/headlamp.png \
        $out/share/pixmaps/headlamp.png
    '';
    
    meta = with lib; {
      description = "A Kubernetes web UI that is fully-featured, user-friendly and extensible";
      homepage = "https://headlamp.dev/";
      license = licenses.asl20;
      maintainers = with maintainers; [ ];
      platforms = [ "x86_64-linux" "aarch64-linux" ];
      mainProgram = "headlamp";
    };
  }
else
  throw "Headlamp is only available on Linux (x86_64 and aarch64)"
