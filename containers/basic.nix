{ pkgs }:

pkgs.dockerTools.buildLayeredImage {
  name = "nixos-basic";
  tag = "latest";
  
  contents = with pkgs; [
    bashInteractive
    coreutils
    curl
    jq
    git
  ];
  
  config = {
    Env = [ "PATH=/bin:/usr/bin" ];
    Cmd = [ "/bin/bash" ];
    WorkingDir = "/";
  };
}