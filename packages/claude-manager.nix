{ pkgs, lib, stdenv, fetchFromGitHub, deno, ... }:

stdenv.mkDerivation rec {
  pname = "claude-manager";
  version = "1.0.0";
  
  # Source files from your local directory
  # You can also use fetchFromGitHub if you push to a repo
  src = ./claude-manager-src;
  
  # Build dependencies
  nativeBuildInputs = [ deno ];
  
  # Runtime dependencies that claude-manager needs
  buildInputs = with pkgs; [
    tmux
    fzf
    gum
    zoxide
    jq
  ];
  
  # Build phase - compile the Deno binary
  buildPhase = ''
    # Copy source files
    cp -r $src/* .
    
    # Ensure deno.json is present
    if [ -f deno.json ]; then
      echo "Found deno.json"
    fi
    
    # Compile the binary
    deno compile \
      --allow-all \
      --output claude-manager \
      claude-session-manager.ts
  '';
  
  # Install phase - copy binary to output
  installPhase = ''
    mkdir -p $out/bin
    cp claude-manager $out/bin/
    chmod +x $out/bin/claude-manager
    
    # Create wrapper script that ensures runtime deps are available
    makeWrapper $out/bin/claude-manager $out/bin/claude-manager-wrapped \
      --prefix PATH : ${lib.makeBinPath buildInputs}
    
    # Rename wrapped version to main
    mv $out/bin/claude-manager $out/bin/.claude-manager-unwrapped
    mv $out/bin/claude-manager-wrapped $out/bin/claude-manager
  '';
  
  meta = with lib; {
    description = "Claude session manager for managing Claude Code sessions";
    homepage = "https://github.com/yourusername/claude-manager";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}