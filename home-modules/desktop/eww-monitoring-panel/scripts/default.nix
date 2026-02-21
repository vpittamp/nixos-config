{ pkgs, config, pythonForBackend, mocha, hostname, cfg, clipboardSyncScript, tailscaleNamespacesCsv, ... }:

let
  core = import ./core.nix { inherit pkgs config pythonForBackend mocha hostname cfg clipboardSyncScript tailscaleNamespacesCsv; };
  projects = import ./projects.nix { inherit pkgs pythonForBackend; };
  windows = import ./windows.nix { inherit pkgs config; };
  apps = import ./apps.nix { inherit pkgs pythonForBackend; };
  tailscale = import ./tailscale.nix { inherit pkgs config; };
  misc = import ./misc.nix { inherit pkgs; };
in
core // projects // windows // apps // tailscale // misc
