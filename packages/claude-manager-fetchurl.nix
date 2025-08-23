{ pkgs, lib, stdenv, system ? stdenv.hostPlatform.system, ... }:

let
  # Version information - ONLY UPDATE THIS!
  version = "1.3.8";
  
  # Runtime dependencies
  runtimeDeps = with pkgs; [ 
    tmux 
    fzf 
    gum 
    zoxide 
    jq 
  ];

  # Platform mapping
  platformMap = {
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
    "x86_64-darwin" = "macos-x64";
    "aarch64-darwin" = "macos-arm64";
  };

  platformSuffix = platformMap.${system} or (throw "Unsupported system: ${system}");
  
  # Build from source using Deno
  buildFromSource = stdenv.mkDerivation rec {
    pname = "claude-session-manager";
    inherit version;
    
    # Fetch source from GitHub - Nix will calculate hash automatically
    src = pkgs.fetchFromGitHub {
      owner = "PittampalliOrg";
      repo = "claude-session-manager";
      rev = "v${version}";
      # This hash is calculated by Nix from the git revision
      # When updating version, just delete this line and Nix will tell you the new hash
      sha256 = "sha256-Qys5gKTdpdRBW5xq2Sg3ca9O5PMM2eoPDCZtqONnD9U=";
    };
    
    nativeBuildInputs = with pkgs; [ deno ];
    buildInputs = runtimeDeps;
    
    buildPhase = ''
      export DENO_DIR=$TMPDIR/deno_cache
      export HOME=$TMPDIR
      
      # Map Nix system to Deno target
      case "${system}" in
        x86_64-linux) target="x86_64-unknown-linux-gnu" ;;
        aarch64-linux) target="aarch64-unknown-linux-gnu" ;;
        x86_64-darwin) target="x86_64-apple-darwin" ;;
        aarch64-darwin) target="aarch64-apple-darwin" ;;
        *) echo "Unsupported system: ${system}"; exit 1 ;;
      esac
      
      # First cache all dependencies using the lock file
      deno cache --lock=deno.lock claude-session-manager.ts || true
      
      # Now compile with cached dependencies
      deno compile \
        --allow-all \
        --no-check \
        --cached-only \
        --target $target \
        --output claude-manager \
        claude-session-manager.ts
    '';
    
    installPhase = ''
      mkdir -p $out/bin
      cp claude-manager $out/bin/
    '';
  };

  # Fetch pre-built binary (requires hash update)
  fetchBinary = stdenv.mkDerivation rec {
    pname = "claude-session-manager";
    inherit version;
    
    src = pkgs.fetchurl {
      url = "https://github.com/PittampalliOrg/claude-session-manager/releases/download/v${version}/claude-manager-${platformSuffix}";
      # IMPORTANT: This hash needs updating when version changes
      # Run: nix-prefetch-url <url> to get the hash
      sha256 = "sha256-kbdU3aVevc0HgD3Q0p576fMdg4jzDFo0MM9Pc/WcUjw=";
      executable = true;
    };
    
    dontUnpack = true;
    dontBuild = true;
    dontPatchELF = true;
    dontStrip = true;
    dontPatchShebangs = true;
    
    buildInputs = runtimeDeps;
    
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/.claude-manager-binary
      chmod +x $out/bin/.claude-manager-binary
      
      cat > $out/bin/claude-manager <<'EOF'
      #!/usr/bin/env bash
      export PATH="${lib.makeBinPath runtimeDeps}:$PATH"
      exec "''${BASH_SOURCE[0]%/*}/.claude-manager-binary" "$@"
      EOF
      
      chmod +x $out/bin/claude-manager
    '';
  };

in
# Choose strategy: set to true to build from source (no hash needed!)
# Set to false to use pre-built binary (faster but needs hash update)
if false  # Using pre-built binary for simplicity
then buildFromSource
else fetchBinary // {
  meta = with lib; {
    description = "Claude session manager for managing Claude Code sessions";
    homepage = "https://github.com/PittampalliOrg/claude-session-manager";
    license = licenses.mit;
    platforms = [ system ];
    mainProgram = "claude-manager";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
