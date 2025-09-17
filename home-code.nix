{ ... }:
{
  imports = [ ./home-modules/profiles/base-home.nix ];

  home.username = "code";
  home.homeDirectory = "/home/code";
}
