{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Nix helper tools
    nh  # Yet another nix cli helper
    nix-output-monitor  # Prettier nix build output
    nixpkgs-fmt  # Nix code formatter
    alejandra  # Alternative Nix formatter
    nix-tree  # Visualize Nix store dependencies
    nix-prefetch-git  # Prefetch git repositories
    nix-diff  # Compare Nix derivations
    nix-index  # Files database for nixpkgs
    comma  # Run programs without installing them
  ];

  # Configure nh (Nix Helper) environment variables
  # NH_FLAKE is the default flake for all nh operations
  # NH_OS_FLAKE takes priority for 'nh os' commands
  home.sessionVariables = {
    NH_FLAKE = "/etc/nixos";  # Default flake directory for nh commands
    NH_OS_FLAKE = "/etc/nixos";  # Specific flake for 'nh os' commands
    # NH_HOME_FLAKE can be set if using a separate home-manager flake
  };

  # Configure nh (Nix Helper) aliases
  programs.bash.shellAliases = {
    # nh shortcuts - now work without specifying path thanks to NH_FLAKE
    nhs = "nh search";
    nho = "nh os switch";  # Uses NH_OS_FLAKE automatically
    nhh = "nh home switch";  # Uses NH_FLAKE by default
    nhc = "nh clean all";
    nhb = "nh os build";  # Build without switching
    nhd = "nh os dry";  # Dry build
  };

  programs.zsh.shellAliases = config.programs.bash.shellAliases;
}