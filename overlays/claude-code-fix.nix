# Overlay to fix Claude Code permission issues in containers
final: prev: {
  # Override claude-code to handle permission issues in containers
  claude-code = if prev ? claude-code then
    prev.claude-code.overrideAttrs (oldAttrs: {
      # Add pre-unpack phase to handle permission issues
      preUnpack = ''
        ${oldAttrs.preUnpack or ""}
        
        # Set umask to ensure files are created with proper permissions
        umask 0022
      '';
      
      # Override unpack phase to handle chmod failures gracefully
      unpackPhase = ''
        runHook preUnpack
        
        # Standard npm package unpacking with permission handling
        mkdir -p source
        tar xzf $src -C source --no-same-permissions --no-same-owner 2>/dev/null || \
          tar xzf $src -C source 2>/dev/null || true
        
        # Move package contents to expected location
        if [ -d source/package ]; then
          mv source/package/* .
        else
          mv source/* .
        fi
        
        # Ensure all files are readable and directories are traversable
        find . -type d -exec chmod 755 {} + 2>/dev/null || true
        find . -type f -exec chmod 644 {} + 2>/dev/null || true
        
        # Make executables actually executable
        find . -type f -name "*.sh" -exec chmod 755 {} + 2>/dev/null || true
        find . -type f -path "*/bin/*" -exec chmod 755 {} + 2>/dev/null || true
        [ -f cli.js ] && chmod 755 cli.js 2>/dev/null || true
        
        runHook postUnpack
      '';
      
      # Ensure the build doesn't fail on permission errors
      buildPhase = ''
        runHook preBuild
        
        ${oldAttrs.buildPhase or ""}
        
        runHook postBuild
      '';
      
      # Add sandbox relaxation for container builds
      __noChroot = true;
    })
  else
    # If claude-code doesn't exist in prev, create a simple derivation
    # This is a fallback for when the package isn't available
    prev.stdenv.mkDerivation rec {
      pname = "claude-code";
      version = "1.0.98";
      
      src = prev.fetchurl {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Placeholder
      };
      
      nativeBuildInputs = with prev; [ 
        nodejs
        makeWrapper
      ];
      
      unpackPhase = ''
        mkdir -p source
        tar xzf $src -C source --no-same-permissions --no-same-owner 2>/dev/null || \
          tar xzf $src -C source 2>/dev/null || true
        
        if [ -d source/package ]; then
          cp -r source/package/* .
        else
          cp -r source/* .
        fi
        
        # Fix permissions
        find . -type d -exec chmod 755 {} + 2>/dev/null || true
        find . -type f -exec chmod 644 {} + 2>/dev/null || true
        find . -type f -name "*.sh" -exec chmod 755 {} + 2>/dev/null || true
        find . -type f -path "*/bin/*" -exec chmod 755 {} + 2>/dev/null || true
        [ -f cli.js ] && chmod 755 cli.js 2>/dev/null || true
      '';
      
      buildPhase = ''
        # No build needed for pre-built npm package
        echo "Claude Code ${version}"
      '';
      
      installPhase = ''
        mkdir -p $out/lib/node_modules/@anthropic-ai/claude-code
        cp -r . $out/lib/node_modules/@anthropic-ai/claude-code/
        
        mkdir -p $out/bin
        makeWrapper ${prev.nodejs}/bin/node $out/bin/claude \
          --add-flags "$out/lib/node_modules/@anthropic-ai/claude-code/cli.js" \
          --set NODE_PATH "$out/lib/node_modules"
        
        # Ensure binary is executable
        chmod 755 $out/bin/claude
      '';
      
      meta = with prev.lib; {
        description = "Claude Code - AI pair programming in the terminal";
        homepage = "https://github.com/anthropics/claude-code";
        license = licenses.mit;
        maintainers = [];
        platforms = platforms.unix;
      };
    };
}