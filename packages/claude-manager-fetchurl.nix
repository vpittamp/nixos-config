{ pkgs, lib, stdenv, system ? stdenv.hostPlatform.system, ... }:

let
  # Version information
  version = "1.0.1";
  
  # Binary URLs and hashes for different platforms
  # Add more platforms as binaries become available
  sources = {
    "x86_64-linux" = {
      url = "https://github.com/PittampalliOrg/claude-session-manager/releases/download/v${version}/claude-manager-linux-x64";
      sha256 = "yfVMQ+TALF2HWlO3T7QAQWp7zIdUxZVkM2bOok/H6D0=";
    };
    # Future platform support can be added here
    # "aarch64-linux" = {
    #   url = "https://github.com/vpittamp/nixos-config/releases/download/v${version}/claude-manager-linux-arm64";
    #   sha256 = "...";
    # };
    # "x86_64-darwin" = {
    #   url = "https://github.com/vpittamp/nixos-config/releases/download/v${version}/claude-manager-macos-x64";
    #   sha256 = "...";
    # };
    # "aarch64-darwin" = {
    #   url = "https://github.com/vpittamp/nixos-config/releases/download/v${version}/claude-manager-macos-arm64";
    #   sha256 = "...";
    # };
  };
  
  # Get source for current system
  source = sources.${system} or (throw "Unsupported system: ${system}");
  
  # Runtime dependencies
  runtimeDeps = with pkgs; [ 
    tmux 
    fzf 
    gum 
    zoxide 
    jq 
  ];
in
stdenv.mkDerivation rec {
  pname = "claude-session-manager";
  inherit version;
  
  # Fetch the binary from GitHub releases
  src = pkgs.fetchurl {
    inherit (source) url sha256;
    # Add executable bit preservation
    executable = true;
  };
  
  # Don't unpack since src is already a binary
  dontUnpack = true;
  dontBuild = true;
  
  # CRITICAL: Don't patch the ELF binary - it corrupts Deno compiled executables
  dontPatchELF = true;
  dontStrip = true;
  dontPatchShebangs = true;
  
  buildInputs = runtimeDeps;
  
  nativeBuildInputs = with pkgs; [ ];
  
  installPhase = ''
    mkdir -p $out/bin
    
    # Copy the binary unchanged to preserve its integrity
    cp $src $out/bin/.claude-manager-binary
    chmod +x $out/bin/.claude-manager-binary
    
    # Create a wrapper script that sets up the environment
    cat > $out/bin/claude-manager <<'EOF'
    #!/usr/bin/env bash
    # Set PATH to include runtime dependencies
    export PATH="${lib.makeBinPath runtimeDeps}:$PATH"
    # Execute the original binary with all arguments
    exec "''${BASH_SOURCE[0]%/*}/.claude-manager-binary" "$@"
    EOF
    
    chmod +x $out/bin/claude-manager
  '';
  
  meta = with lib; {
    description = "Claude session manager for managing Claude Code sessions";
    homepage = "https://github.com/PittampalliOrg/claude-session-manager";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];  # Add more as binaries become available
    mainProgram = "claude-manager";
    # Mark as binary distribution
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}