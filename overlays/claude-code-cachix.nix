# Overlay to use claude-code from the sadjow/claude-code-nix flake
# This provides pre-built binaries via Cachix, avoiding build permission issues in containers
final: prev: {
  # Override claude-code with the flake version that has Cachix binaries
  claude-code = 
    let
      # Import the flake
      claude-code-flake = builtins.getFlake "github:sadjow/claude-code-nix";
      
      # Get the package for the current system
      system = prev.stdenv.system;
    in
      # Use the flake's package if available, otherwise fall back to nixpkgs
      if claude-code-flake ? packages && claude-code-flake.packages ? ${system} && claude-code-flake.packages.${system} ? default then
        claude-code-flake.packages.${system}.default
      else
        prev.claude-code or (throw "claude-code not available");
}