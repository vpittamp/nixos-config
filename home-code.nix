{ ... }:
{
  imports = [ ./home-modules/profiles/container-home.nix ];

  home.username = "code";
  home.homeDirectory = "/home/code";
}
