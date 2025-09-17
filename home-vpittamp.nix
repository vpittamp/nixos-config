{ ... }:
{
  imports = [
    ./home-modules/profiles/base-home.nix
    ./home-modules/profiles/plasma-home.nix
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";
}
