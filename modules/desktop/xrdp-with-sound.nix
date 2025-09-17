# XRDP with Sound Support
# The default NixOS XRDP package doesn't include --enable-sound flag
# This module provides a properly compiled XRDP with full audio support
{ config, lib, pkgs, ... }:

let
  # Custom XRDP package with sound support enabled
  xrdpWithSound = pkgs.xrdp.overrideAttrs (oldAttrs: {
    configureFlags = oldAttrs.configureFlags ++ [
      "--enable-sound"        # Critical: Enable sound redirection support
      "--enable-simplesound"  # Enable simple sound redirection
    ];
  });
in
{
  # Override the XRDP package with our sound-enabled version
  services.xrdp.package = lib.mkForce xrdpWithSound;
}