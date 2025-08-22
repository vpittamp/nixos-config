{ pkgs, lib, stdenv, ... }:

stdenv.mkDerivation rec {
  pname = "claude-session-manager";
  version = "1.0.0";
  
  # Use the pre-compiled binary included in the package directory
  src = ./claude-manager;
  
  dontUnpack = true;
  dontBuild = true;
  
  # Runtime dependencies
  buildInputs = with pkgs; [
    tmux
    fzf
    gum
    zoxide
    jq
  ];
  
  nativeBuildInputs = with pkgs; [
    makeWrapper
  ];
  
  installPhase = ''
    mkdir -p $out/bin
    
    # Create a wrapper script instead of wrapping the binary
    cat > $out/bin/claude-manager <<EOF
    #!/usr/bin/env bash
    export PATH="${lib.makeBinPath buildInputs}:\$PATH"
    exec ${src} "\$@"
    EOF
    
    chmod +x $out/bin/claude-manager
  '';
  
  meta = with lib; {
    description = "Claude session manager for managing Claude Code sessions";
    homepage = "https://github.com/PittampalliOrg/claude-session-manager";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "claude-manager";
  };
}