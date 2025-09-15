# Headlamp - Kubernetes Web UI Dashboard
{ lib, stdenv, fetchurl, appimageTools, makeWrapper, electron }:

let
  pname = "headlamp";
  version = "0.35.0";
  
  # Use the AppImage for simplicity on x86_64
  src = fetchurl {
    url = "https://github.com/kubernetes-sigs/headlamp/releases/download/v${version}/Headlamp-${version}-linux-x64.AppImage";
    sha256 = "02iqwnm0jivgv06h8wv2gslp3sf2jd9x19g9wxrljv58i6yplyzn";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
if stdenv.isLinux && stdenv.isx86_64 then
  appimageTools.wrapType2 {
    inherit pname version src;
    
    extraInstallCommands = ''
      # Install desktop file and icon from AppImage contents
      install -m 444 -D ${appimageContents}/headlamp.desktop \
        $out/share/applications/headlamp.desktop
      substituteInPlace $out/share/applications/headlamp.desktop \
        --replace 'Exec=headlamp' 'Exec=${pname}'
      
      # Install icon
      install -m 444 -D ${appimageContents}/headlamp.png \
        $out/share/pixmaps/headlamp.png
    '';
    
    meta = with lib; {
      description = "A Kubernetes web UI that is fully-featured, user-friendly and extensible";
      homepage = "https://headlamp.dev/";
      license = licenses.asl20;
      maintainers = with maintainers; [ ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "headlamp";
    };
  }
else
  # Alternative: Build from tarball for other architectures
  stdenv.mkDerivation rec {
    inherit pname version;
    
    src = fetchurl {
      url = "https://github.com/kubernetes-sigs/headlamp/releases/download/v${version}/Headlamp-${version}-linux-x64.tar.gz";
      sha256 = "1lpg9vmyw5k6dijkij4ffay73431dvyrb69dcaibczc65k8mhcrq";
    };
    
    nativeBuildInputs = [ makeWrapper ];
    
    installPhase = ''
      mkdir -p $out/opt/headlamp
      cp -r * $out/opt/headlamp/
      
      makeWrapper $out/opt/headlamp/headlamp $out/bin/headlamp \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}"
      
      # Install desktop file
      mkdir -p $out/share/applications
      cat > $out/share/applications/headlamp.desktop <<EOF
      [Desktop Entry]
      Name=Headlamp
      Comment=Kubernetes Dashboard
      Exec=$out/bin/headlamp %U
      Terminal=false
      Type=Application
      Icon=headlamp
      Categories=Development;
      EOF
    '';
    
    meta = with lib; {
      description = "A Kubernetes web UI that is fully-featured, user-friendly and extensible";
      homepage = "https://headlamp.dev/";
      license = licenses.asl20;
      maintainers = with maintainers; [ ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "headlamp";
    };
  }
