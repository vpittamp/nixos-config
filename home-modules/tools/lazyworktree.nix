# Lazyworktree - Terminal UI for git worktree management
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    lazyworktree
  ];

  # Desktop entries managed by app-registry.nix (Feature 034)
}
