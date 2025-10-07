{ pkgs, lib, ... }:

let
  # Use nixos-24.11 which has Azure CLI with Python 3.12 and updated MSAL
  # This version is stable and avoids Python 3.13 SSL issues while having recent MSAL
  pkgs-stable = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/nixos-24.11.tar.gz";
    sha256 = "1s2gr5rcyqvpr58vxdcb095mdhblij9bfzaximrva2243aal3dgx";
  }) {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
  pkgs-stable.azure-cli