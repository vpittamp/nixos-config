{ pkgs, lib, stdenv, system ? stdenv.hostPlatform.system, ... }:

let
  # Version information
  version = "1.0.0";
  
  # Binary URLs and hashes for different platforms
  # Add more platforms as binaries become available
  sources = {
    "x86_64-linux" = {
      url = "https://github.com/PittampalliOrg/claude-session-manager/releases/download/v${version}/claude-manager-linux-x64";
      sha256 = "Ku5GK+AVB5+9cwwO/wyJmzDSEM6jMmkYfuaV/TukhHs=";
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
  
  buildInputs = runtimeDeps;
  
  nativeBuildInputs = with pkgs; [
    makeWrapper
  ] ++ lib.optionals stdenv.isLinux [ patchelf ];
  
  installPhase = ''
    mkdir -p $out/bin
    
    # Copy the binary
    cp $src $out/bin/claude-manager
    chmod +x $out/bin/claude-manager
    
    # Wrap with runtime dependencies in PATH
    wrapProgram $out/bin/claude-manager \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
    
    # On Linux, patch the interpreter if needed
    ${lib.optionalString stdenv.isLinux ''
      if ldd $out/bin/claude-manager 2>/dev/null | grep -q "not a dynamic executable"; then
        echo "Binary is statically linked, no patching needed"
      else
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
          $out/bin/claude-manager || true
      fi
    ''}
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