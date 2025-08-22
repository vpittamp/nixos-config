{ pkgs, lib, stdenv, ... }:

stdenv.mkDerivation rec {
  pname = "claude-session-manager";
  version = "1.0.0";
  
  # Use the pre-compiled binary
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
    glibc  # Include glibc for the dynamic linker
  ];
  
  nativeBuildInputs = with pkgs; [
    makeWrapper
    patchelf
  ];
  
  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/libexec
    
    # Copy the original binary
    cp $src $out/libexec/claude-manager-bin
    chmod 755 $out/libexec/claude-manager-bin
    
    # Try to patch it, but if it fails, we'll use the fallback
    ${pkgs.patchelf}/bin/patchelf \
      --set-interpreter "${pkgs.glibc}/lib/ld-linux-x86-64.so.2" \
      $out/libexec/claude-manager-bin 2>/dev/null || true
    
    # Create a universal wrapper that works in containers and on host
    cat > $out/bin/claude-manager <<'WRAPPER'
    #!/usr/bin/env bash
    
    # Add runtime dependencies to PATH
    export PATH="${lib.makeBinPath buildInputs}:$PATH"
    
    # Determine the best way to run the binary
    CLAUDE_BIN="$out/libexec/claude-manager-bin"
    
    # Check if we can run it directly
    if $CLAUDE_BIN --version >/dev/null 2>&1; then
      exec $CLAUDE_BIN "$@"
    # Try with explicit interpreter
    elif [ -f "${pkgs.glibc}/lib/ld-linux-x86-64.so.2" ]; then
      exec "${pkgs.glibc}/lib/ld-linux-x86-64.so.2" $CLAUDE_BIN "$@"
    # Fallback to system interpreter if available
    elif [ -f /lib64/ld-linux-x86-64.so.2 ]; then
      exec /lib64/ld-linux-x86-64.so.2 $CLAUDE_BIN "$@"
    else
      echo "Error: Cannot find a suitable dynamic linker for claude-manager" >&2
      echo "This may happen in minimal containers. Consider using a base image with glibc." >&2
      exit 1
    fi
    WRAPPER
    
    # Substitute the actual paths
    substituteInPlace $out/bin/claude-manager \
      --replace '$out' "$out"
    
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