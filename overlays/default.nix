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
  # NOTE: These modifications are only applied if the packages are already included
  # We don't force these packages into the build
  modifications = final: prev: {
    # Only override if nodejs is already in the package set
    # This avoids forcing nodejs into containers that don't need it
  };
  
  # Unstable packages overlay - for bleeding edge versions
  # NOTE: Commented out to reduce container size
  # Uncomment only if you need unstable packages
  # unstable-packages = final: prev: {
  #   unstable = import inputs.nixpkgs-unstable {
  #     system = final.system;
  #     config.allowUnfree = true;
  #   };
  # };
}