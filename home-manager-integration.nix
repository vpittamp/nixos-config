{ config, pkgs, lib, ... }:

{
  imports = [
    <home-manager/nixos>
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.vpittamp = import ./home-vpittamp.nix;
    extraSpecialArgs = {
      # Provide empty inputs for modules that expect it
      inputs = {};
      pkgs-unstable = pkgs;
      isDarwin = false;
    };
  };
}
