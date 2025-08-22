{ config, pkgs, lib, ... }:

{
  # Bat configuration (better cat)
  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
      style = "numbers,changes,header";
    };
  };
}