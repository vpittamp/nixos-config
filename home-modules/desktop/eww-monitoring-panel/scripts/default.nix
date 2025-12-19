{ pkgs, config, pythonForBackend, mocha, hostname, cfg, clipboardSyncScript, ... }:

let
  core = import ./core.nix { inherit pkgs config pythonForBackend mocha hostname cfg clipboardSyncScript; };
  projects = import ./projects.nix { inherit pkgs pythonForBackend; };
  windows = import ./windows.nix { inherit pkgs; };
  apps = import ./apps.nix { inherit pkgs pythonForBackend; };
  misc = import ./misc.nix { inherit pkgs; };
in
core // projects // windows // apps // misc