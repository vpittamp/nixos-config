# Overlays for extending the base package set
# These overlays allow us to add custom packages and modifications
# without rebuilding the entire container

{ inputs, ... }:

{
  # Custom package overlays
  additions = final: prev: {
    # Custom packages can be added here
    # Example: myCustomPackage = final.callPackage ./my-package {};
    
    # Development tools overlay - commonly needed packages
    devTools = with final; [
      jq
      yq
      httpie
      ngrok
      dive
      lazydocker
    ];
    
    # Node.js development packages
    nodeDevTools = with final; [
      nodejs_20
      nodePackages.yarn
      nodePackages.pnpm
      nodePackages.typescript
      nodePackages.ts-node
      nodePackages.nodemon
    ];
    
    # Python development packages
    pythonDevTools = with final; [
      python3
      python3Packages.pip
      python3Packages.virtualenv
      python3Packages.ipython
      python3Packages.black
      python3Packages.pylint
    ];
    
    # Go development packages
    goDevTools = with final; [
      go
      gopls
      go-tools
      golangci-lint
      delve
    ];
    
    # Rust development packages
    rustDevTools = with final; [
      rustc
      cargo
      rustfmt
      rust-analyzer
      clippy
    ];
  };
  
  # Modifications overlay - override existing packages
  modifications = final: prev: {
    # Fix SSL certificates for Node.js/Yarn
    nodejs = prev.nodejs.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        # Ensure NODE_EXTRA_CA_CERTS points to system certificates
        wrapProgram $out/bin/node \
          --set NODE_EXTRA_CA_CERTS /etc/ssl/certs/ca-certificates.crt \
          --set SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
      '';
    });
    
    # Override yarn to handle SSL certificates
    yarn = prev.yarn.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        # Set SSL certificate environment for yarn
        wrapProgram $out/bin/yarn \
          --set NODE_EXTRA_CA_CERTS /etc/ssl/certs/ca-certificates.crt \
          --set SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
      '';
    });
  };
  
  # Unstable packages overlay - for bleeding edge versions
  unstable-packages = final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };
}