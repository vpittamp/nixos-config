{ pkgs, lib, stdenv, ... }:

stdenv.mkDerivation rec {
  pname = "claude-session-manager";
  version = "1.0.0";
  
  # Include the binary as part of the derivation source
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
    patchelf
    makeWrapper
  ];
  
  installPhase = ''
    mkdir -p $out/bin
    
    # Copy the binary with write permissions for patching
    cp $src $out/bin/.claude-manager-orig
    chmod 755 $out/bin/.claude-manager-orig
    
    # Patch the binary to use Nix's dynamic linker and libraries
    patchelf \
      --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      --set-rpath "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}" \
      $out/bin/.claude-manager-orig
    
    # Create wrapper script that ensures dependencies are available
    makeWrapper $out/bin/.claude-manager-orig $out/bin/claude-manager \
      --prefix PATH : ${lib.makeBinPath buildInputs}
  '';
  
  meta = with lib; {
    description = "Claude session manager for managing Claude Code sessions";
    homepage = "https://github.com/PittampalliOrg/claude-session-manager";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "claude-manager";
  };
}