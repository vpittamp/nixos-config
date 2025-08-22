{ pkgs, lib, stdenv, deno, ... }:

stdenv.mkDerivation rec {
  pname = "claude-session-manager";
  version = "1.0.0";
  
  # Include source files directly
  src = ./claude-manager-src;
  
  nativeBuildInputs = [ 
    deno 
    pkgs.makeWrapper
  ];
  
  # Runtime dependencies
  buildInputs = with pkgs; [
    tmux
    fzf
    gum
    zoxide
    jq
  ];
  
  # Skip network-dependent build for now, just create a wrapper
  buildPhase = ''
    echo "Preparing claude-manager..."
  '';
  
  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/lib/claude-manager
    
    # Copy source files
    cp -r $src/*.ts $src/deno.json $out/lib/claude-manager/
    
    # Create a runner script that uses deno run
    cat > $out/bin/claude-manager <<'EOF'
    #!/usr/bin/env bash
    export PATH="${lib.makeBinPath buildInputs}:$PATH"
    
    # Run with deno from the stored source
    exec ${deno}/bin/deno run \
      --allow-all \
      $out/lib/claude-manager/claude-session-manager.ts \
      "$@"
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