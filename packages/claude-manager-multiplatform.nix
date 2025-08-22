{ pkgs, lib, stdenv, system ? stdenv.hostPlatform.system, ... }:

let
  # Map system strings to binary names
  binaryForSystem = {
    "x86_64-linux" = "claude-manager-linux-x64";
    "aarch64-linux" = "claude-manager-linux-arm64";  # Would need aarch64-linux binary
    "x86_64-darwin" = "claude-manager-macos-x64";
    "aarch64-darwin" = "claude-manager-macos-arm64";
  };
  
  # Select the appropriate binary for the current system
  binaryName = binaryForSystem.${system} or "claude-manager-linux-x64";
  
  # Runtime dependencies - adjust based on platform
  runtimeDeps = with pkgs; 
    if stdenv.isDarwin then
      [ tmux fzf gum zoxide jq ]
    else if stdenv.isLinux then
      [ tmux fzf gum zoxide jq ]
    else
      [ ];
in
stdenv.mkDerivation rec {
  pname = "claude-session-manager";
  version = "1.0.0";
  
  # Use the appropriate pre-compiled binary
  src = ./binaries + "/${binaryName}";
  
  dontUnpack = true;
  dontBuild = true;
  
  buildInputs = runtimeDeps;
  
  nativeBuildInputs = with pkgs; [
    makeWrapper
  ] ++ lib.optionals stdenv.isLinux [ patchelf ];
  
  installPhase = if stdenv.isLinux then ''
    mkdir -p $out/bin
    
    # Linux: Create wrapper with proper paths
    cat > $out/bin/claude-manager <<EOF
    #!/usr/bin/env bash
    export PATH="${lib.makeBinPath runtimeDeps}:\$PATH"
    exec ${src} "\$@"
    EOF
    
    chmod +x $out/bin/claude-manager
  '' else if stdenv.isDarwin then ''
    mkdir -p $out/bin
    
    # macOS: Copy binary and wrap with dependencies
    cp ${src} $out/bin/.claude-manager-unwrapped
    chmod +x $out/bin/.claude-manager-unwrapped
    
    makeWrapper $out/bin/.claude-manager-unwrapped $out/bin/claude-manager \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
  '' else ''
    mkdir -p $out/bin
    echo "Unsupported platform: ${system}" > $out/bin/claude-manager
    chmod +x $out/bin/claude-manager
  '';
  
  meta = with lib; {
    description = "Claude session manager for managing Claude Code sessions";
    homepage = "https://github.com/PittampalliOrg/claude-session-manager";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
    mainProgram = "claude-manager";
  };
}