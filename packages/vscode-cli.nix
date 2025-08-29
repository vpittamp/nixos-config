{ pkgs, lib, stdenv, ... }:

stdenv.mkDerivation rec {
  pname = "vscode-cli";
  version = "1.103.2";
  
  src = pkgs.fetchurl {
    url = "https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64";
    sha256 = "0mxcb6valgwl4cb95k0rxvs9q37h47pwjm2bajjjgy09lbx4nshd";
    name = "vscode-cli-${version}.tar.gz";
  };
  
  # The tarball contains a single 'code' binary
  sourceRoot = ".";
  
  # No build phase needed - it's a pre-built binary
  dontBuild = true;
  dontConfigure = true;
  dontPatchELF = true;
  dontStrip = true;
  
  unpackPhase = ''
    tar -xzf $src
  '';
  
  installPhase = ''
    mkdir -p $out/bin
    cp code $out/bin/code
    chmod +x $out/bin/code
  '';
  
  meta = with lib; {
    description = "Visual Studio Code CLI - standalone binary";
    homepage = "https://code.visualstudio.com/";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "code";
  };
}